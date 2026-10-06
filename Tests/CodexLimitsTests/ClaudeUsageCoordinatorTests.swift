import Darwin
import Foundation
import XCTest
@testable import CodexLimits

final class ClaudeUsageCoordinatorTests: XCTestCase {
    func testFreshReadingIsSharedWithoutLaunchingCommandOrChangingTimestamp() async throws {
        let context = try Context()
        defer { context.cleanUp() }
        let source = RequestRecorder()
        let original = Self.snapshot(at: context.clock.now)

        let first = try await context.coordinator().fetch(
            prepare: { await source.prepare() },
            request: { _ in await source.fetch(original) }
        )
        context.clock.advance(by: 899)
        let second = try await context.coordinator().fetch(
            prepare: { await source.prepare() },
            request: { _ in await source.fetch(Self.snapshot(at: context.clock.now)) }
        )

        XCTAssertEqual(try fetched(first), original)
        let cached = try cached(second)
        XCTAssertEqual(cached.snapshot, original)
        XCTAssertEqual(cached.nextRefreshAt, original.fetchedAt.addingTimeInterval(900))
        let counts = await source.counts
        XCTAssertEqual(counts.prepare, 1)
        XCTAssertEqual(counts.request, 1)
    }

    func testRequestBecomesEligibleAtMinimumIntervalBoundary() async throws {
        let context = try Context()
        defer { context.cleanUp() }
        let source = RequestRecorder()
        _ = try await context.coordinator().fetch(prepare: { Self.command() }) { _ in
            await source.fetch(Self.snapshot(at: context.clock.now))
        }
        context.clock.advance(by: 900)

        let result = try await context.coordinator().fetch(prepare: { Self.command() }) { _ in
            await source.fetch(Self.snapshot(at: context.clock.now))
        }

        XCTAssertEqual(try fetched(result).fetchedAt, context.clock.now)
        let counts = await source.counts
        XCTAssertEqual(counts.request, 2)
    }

    func testSlowPreparationDoesNotConsumeRequestSpacing() async throws {
        let context = try Context()
        defer { context.cleanUp() }
        let source = RequestRecorder()
        let result = try await context.coordinator().fetch(
            prepare: {
                context.clock.advance(by: 1_800)
                return Self.command()
            },
            request: { _ in await source.fetch(Self.snapshot(at: context.clock.now)) }
        )
        let original = try fetched(result)
        context.clock.advance(by: 899)

        let repeated = try await context.coordinator().fetch(prepare: { Self.command() }) { _ in
            await source.fetch(Self.snapshot(at: context.clock.now))
        }

        XCTAssertEqual(try cached(repeated).snapshot, original)
        let counts = await source.counts
        XCTAssertEqual(counts.request, 1)
    }

    func testSpacingAlsoSurvivesLongRequestAndCoordinatorRecreation() async throws {
        let context = try Context()
        defer { context.cleanUp() }
        let result = try await context.coordinator().fetch(prepare: { Self.command() }) { _ in
            context.clock.advance(by: 1_800)
            return Self.snapshot(at: context.clock.now)
        }
        let original = try fetched(result)

        let repeated = try await context.coordinator().fetch(prepare: { try Self.unexpectedPreparation() }) { _ in
            XCTFail("Completed request must still be spaced")
            return original
        }

        XCTAssertEqual(try cached(repeated).nextRefreshAt, original.fetchedAt.addingTimeInterval(900))
    }

    func testConcurrentCoordinatorsShareOneRequest() async throws {
        let context = try Context()
        defer { context.cleanUp() }
        let source = SuspendedRequest()
        let original = Self.snapshot(at: context.clock.now)
        let first = Task {
            try await context.coordinator().fetch(prepare: { Self.command() }) { _ in
                await source.fetch(original)
            }
        }
        await source.waitUntilStarted()

        let busy = try await context.coordinator(lockTimeout: .zero).fetch(
            prepare: { try Self.unexpectedPreparation() },
            request: { _ in original }
        )
        guard case .inProgress = try deferredError(busy) as? ClaudeRefreshError else {
            await source.resume()
            XCTFail("Expected another process's request to block preparation")
            return
        }
        let second = Task {
            try await context.coordinator().fetch(prepare: { try Self.unexpectedPreparation() }) { _ in original }
        }
        await source.resume()

        let firstResult = try await first.value
        let secondResult = try await second.value
        XCTAssertEqual(try fetched(firstResult), original)
        XCTAssertEqual(try cached(secondResult).snapshot, original)
        let requestCount = await source.requestCount
        XCTAssertEqual(requestCount, 1)
    }

    func testMissingRetryAfterBackoffPersistsAndIsBounded() async throws {
        let context = try Context()
        defer { context.cleanUp() }
        for expectedDelay in [1_800.0, 3_600, 7_200, 7_200] {
            let attemptedAt = context.clock.now
            let limited = try await context.coordinator().fetch(prepare: { Self.command() }) { _ in
                throw ClaudeClientError.rateLimited(retryAfter: nil)
            }
            let deadline = try rateLimitDeadline(limited)
            XCTAssertEqual(deadline, attemptedAt.addingTimeInterval(expectedDelay))
            context.clock.advance(by: expectedDelay - 1)

            let blocked = try await context.coordinator().fetch(
                prepare: { try Self.unexpectedPreparation() },
                request: { _ in Self.snapshot(at: context.clock.now) }
            )

            XCTAssertEqual(try rateLimitDeadline(blocked), deadline)
            context.clock.advance(by: 1)
        }
    }

    func testUnavailableCLIReportsBackOffWithoutClaimingARateLimit() async throws {
        let context = try Context()
        defer { context.cleanUp() }
        for delay in [1_800.0, 3_600, 7_200, 7_200] {
            let deadline = context.clock.now.addingTimeInterval(delay)
            let result = try await context.coordinator().fetch(prepare: { Self.command() }) { _ in
                throw ClaudeClientError.usageUnavailable
            }
            guard case let .failed(error, until) = try deferredError(result) as? ClaudeRefreshError else {
                return XCTFail("Expected unavailable usage with a cooldown")
            }
            XCTAssertEqual(error, .usageUnavailable)
            XCTAssertEqual(until, deadline)
            context.clock.advance(by: delay - 1)
            let repeated = try await context.coordinator().fetch(
                prepare: { try Self.unexpectedPreparation() }, request: { _ in Self.snapshot(at: context.clock.now) }
            )
            guard case let .failed(savedError, savedDeadline) = try deferredError(repeated) as? ClaudeRefreshError else {
                return XCTFail("Expected cooldown reason to survive coordinator recreation")
            }
            XCTAssertEqual(savedError, .usageUnavailable)
            XCTAssertEqual(savedDeadline, deadline)
            context.clock.advance(by: 1)
        }
    }

    func testCooldownFromEarlierAppVersionIsPreserved() async throws {
        let context = try Context()
        defer { context.cleanUp() }
        let deadline = context.clock.now.addingTimeInterval(3_600)
        let state: [String: Any] = ["version": 1, "rateLimitCount": 2,
                                  "lastAttemptAt": context.clock.now.timeIntervalSinceReferenceDate,
                                  "cooldownUntil": deadline.timeIntervalSinceReferenceDate]
        try JSONSerialization.data(withJSONObject: state).write(to: context.directory.appendingPathComponent("state.json"))
        let result = try await context.coordinator().fetch(
            prepare: { try Self.unexpectedPreparation() }, request: { _ in Self.snapshot(at: context.clock.now) }
        )
        XCTAssertEqual(try rateLimitDeadline(result), deadline)
    }

    func testSuccessfulRequestResetsFallbackBackoff() async throws {
        let context = try Context()
        defer { context.cleanUp() }
        _ = try await context.coordinator().fetch(prepare: { Self.command() }) { _ in
            throw ClaudeClientError.rateLimited(retryAfter: nil)
        }
        context.clock.advance(by: 1_800)
        _ = try await context.coordinator().fetch(prepare: { Self.command() }) { _ in
            Self.snapshot(at: context.clock.now)
        }
        context.clock.advance(by: 900)

        let limited = try await context.coordinator().fetch(prepare: { Self.command() }) { _ in
            throw ClaudeClientError.rateLimited(retryAfter: nil)
        }

        XCTAssertEqual(try rateLimitDeadline(limited), context.clock.now.addingTimeInterval(1_800))
    }

    func testRetryAfterIsHonoredBeyondFallbackCapAndFlooredToMinimumSpacing() async throws {
        for serverDelay in [-100.0, 0, 120, 900, 10_800] {
            let context = try Context()
            defer { context.cleanUp() }
            let attemptedAt = context.clock.now

            let result = try await context.coordinator().fetch(prepare: { Self.command() }) { _ in
                throw ClaudeClientError.rateLimited(retryAfter: attemptedAt.addingTimeInterval(serverDelay))
            }

            XCTAssertEqual(
                try rateLimitDeadline(result),
                attemptedAt.addingTimeInterval(max(900, serverDelay))
            )
        }
    }

    func testRateLimitKeepsPriorSnapshotAndItsTimestamp() async throws {
        let context = try Context()
        defer { context.cleanUp() }
        let original = Self.snapshot(at: context.clock.now)
        _ = try await context.coordinator().fetch(prepare: { Self.command() }) { _ in original }
        context.clock.advance(by: 900)

        let limited = try await context.coordinator().fetch(prepare: { Self.command() }) { _ in
            throw ClaudeClientError.rateLimited(retryAfter: nil)
        }
        let blocked = try await context.coordinator().fetch(
            prepare: { try Self.unexpectedPreparation() },
            request: { _ in original }
        )

        for result in [limited, blocked] {
            guard case let .deferred(_, snapshot, _) = result else {
                XCTFail("Expected deferred reading")
                continue
            }
            XCTAssertEqual(snapshot, original)
        }
    }

    func testAuthenticationFailureSurvivesCoordinatorRecreationWithoutAnotherRequest() async throws {
        for failure in [ClaudeClientError.unauthorized, .forbidden] {
            let context = try Context()
            defer { context.cleanUp() }
            _ = try await context.coordinator().fetch(prepare: { Self.command() }) { _ in
                throw failure
            }

            let repeated = try await context.coordinator().fetch(
                prepare: { try Self.unexpectedPreparation() },
                request: { _ in Self.snapshot(at: context.clock.now) }
            )

            let error = try deferredError(repeated)
            guard case let .failed(savedFailure, until) = error as? ClaudeRefreshError else {
                XCTFail("Expected saved authentication failure and next check time")
                continue
            }
            XCTAssertEqual(savedFailure, failure)
            XCTAssertEqual(until, context.clock.now.addingTimeInterval(900))
            XCTAssertEqual(error.requiresLogin, failure.requiresLogin)
        }
    }

    func testMissingCommandDoesNotReserveAnAttempt() async throws {
        let context = try Context()
        defer { context.cleanUp() }
        for failure in [ClaudeClientError.cliNotFound] {
            do {
                _ = try await context.coordinator().fetch(prepare: { () throws -> String in throw failure }) { _ in
                    XCTFail("A missing executable must prevent command execution")
                    return Self.snapshot(at: context.clock.now)
                }
                XCTFail("Expected preparation failure")
            } catch {
                XCTAssertEqual(error as? ClaudeClientError, failure)
            }
        }

        let result = try await context.coordinator().fetch(prepare: { Self.command() }) { _ in
            Self.snapshot(at: context.clock.now)
        }

        XCTAssertEqual(try fetched(result).fetchedAt, context.clock.now)
    }

    func testCancelledRequestRetainsPersistedReservation() async throws {
        let context = try Context()
        defer { context.cleanUp() }
        do {
            _ = try await context.coordinator().fetch(prepare: { Self.command() }) { _ in
                let data = try Data(contentsOf: context.directory.appendingPathComponent("state.json"))
                let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
                XCTAssertNotNil(object["lastAttemptAt"])
                throw CancellationError()
            }
            XCTFail("Expected cancellation")
        } catch is CancellationError {
        }

        let repeated = try await context.coordinator().fetch(
            prepare: { try Self.unexpectedPreparation() },
            request: { _ in Self.snapshot(at: context.clock.now) }
        )

        guard case let .tooSoon(until) = try deferredError(repeated) as? ClaudeRefreshError else {
            return XCTFail("Expected persisted minimum spacing")
        }
        XCTAssertEqual(until, context.clock.now.addingTimeInterval(900))
    }

    func testNetworkFailureDoesNotImmediatelyRetry() async throws {
        let context = try Context()
        defer { context.cleanUp() }
        _ = try await context.coordinator().fetch(prepare: { Self.command() }) { _ in
            throw ClaudeClientError.networkUnavailable
        }

        let repeated = try await context.coordinator().fetch(
            prepare: { try Self.unexpectedPreparation() },
            request: { _ in Self.snapshot(at: context.clock.now) }
        )

        guard case .tooSoon = try deferredError(repeated) as? ClaudeRefreshError else {
            return XCTFail("Network failure must retain minimum spacing")
        }
    }

    func testExpiredWindowIsDeferredWithoutInventingFreshData() async throws {
        let context = try Context()
        defer { context.cleanUp() }
        let original = Self.snapshot(at: context.clock.now, resetAfter: 100)
        _ = try await context.coordinator().fetch(prepare: { Self.command() }) { _ in original }
        context.clock.advance(by: 101)

        let result = try await context.coordinator().fetch(
            prepare: { try Self.unexpectedPreparation() },
            request: { _ in original }
        )

        guard case .tooSoon = try deferredError(result) as? ClaudeRefreshError else {
            return XCTFail("An expired window must not be labeled fresh cache")
        }
    }

    func testCorruptOrUnsupportedStatePreventsCommandExecution() async throws {
        for payload in ["not json", "{}", #"{"version":2,"rateLimitCount":0}"#, #"{"version":1,"rateLimitCount":4}"#] {
            let context = try Context()
            defer { context.cleanUp() }
            try Data(payload.utf8).write(to: context.directory.appendingPathComponent("state.json"))

            await assertStorageFailure(context)
        }
    }

    func testUnwritableStatePreventsNetworkAccess() async throws {
        let context = try Context()
        defer { context.cleanUp() }
        try FileManager.default.createDirectory(
            at: context.directory.appendingPathComponent("state.json"),
            withIntermediateDirectories: false
        )

        await assertStorageFailure(context)
    }

    func testSeparateProcessLockBlocksRequestAndIsReleasedAfterProcessTermination() async throws {
        guard FileManager.default.isExecutableFile(atPath: "/usr/bin/perl") else {
            throw XCTSkip("System Perl is unavailable for the independent lock-owner fixture")
        }
        let context = try Context()
        defer { context.cleanUp() }
        let child = try lockOwner(in: context.directory)
        defer {
            if child.isRunning { kill(child.processIdentifier, SIGKILL) }
            child.waitUntilExit()
        }

        let blocked = try await context.coordinator(lockTimeout: .zero).fetch(
            prepare: { try Self.unexpectedPreparation() },
            request: { _ in Self.snapshot(at: context.clock.now) }
        )
        guard case .inProgress = try deferredError(blocked) as? ClaudeRefreshError else {
            return XCTFail("A separate process's lock must prevent a request")
        }
        kill(child.processIdentifier, SIGKILL)
        child.waitUntilExit()

        let recovered = try await context.coordinator().fetch(prepare: { Self.command() }) { _ in
            Self.snapshot(at: context.clock.now)
        }

        XCTAssertEqual(try fetched(recovered).fetchedAt, context.clock.now)
    }

    private func assertStorageFailure(_ context: Context) async {
        do {
            _ = try await context.coordinator().fetch(prepare: { try Self.unexpectedPreparation() }) { _ in
                XCTFail("Unreadable state must prevent command execution")
                return Self.snapshot(at: context.clock.now)
            }
            XCTFail("Expected storage failure")
        } catch ClaudeRefreshError.storageUnavailable {
        } catch {
            XCTFail("Unexpected failure: \(error)")
        }
    }

    private func lockOwner(in directory: URL) throws -> Process {
        let process = Process()
        let output = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/perl")
        process.arguments = [
            "-e",
            "open(my $lock, '>>', $ARGV[0]) or die $!; flock($lock, 2) or die $!; $|=1; print qq(R); sleep 60;",
            directory.appendingPathComponent("request.lock").path
        ]
        process.standardOutput = output
        try process.run()
        let ready = output.fileHandleForReading.readData(ofLength: 1)
        guard ready == Data("R".utf8) else {
            process.terminate()
            process.waitUntilExit()
            throw FixtureError.unexpectedResult
        }
        return process
    }

    private func fetched(_ result: UsageFetchResult) throws -> UsageSnapshot {
        guard case let .fetched(snapshot, _) = result else {
            XCTFail("Expected network reading")
            throw FixtureError.unexpectedResult
        }
        return snapshot
    }

    private func cached(_ result: UsageFetchResult) throws -> (snapshot: UsageSnapshot, nextRefreshAt: Date) {
        guard case let .cached(snapshot, nextRefreshAt) = result else {
            XCTFail("Expected cached reading")
            throw FixtureError.unexpectedResult
        }
        return (snapshot, nextRefreshAt)
    }

    private func deferredError(_ result: UsageFetchResult) throws -> any UsageFetchError {
        guard case let .deferred(error, _, _) = result else {
            XCTFail("Expected deferred request")
            throw FixtureError.unexpectedResult
        }
        return error
    }

    private func rateLimitDeadline(_ result: UsageFetchResult) throws -> Date {
        guard case let .rateLimited(until) = try deferredError(result) as? ClaudeRefreshError else {
            XCTFail("Expected rate-limit cooldown")
            throw FixtureError.unexpectedResult
        }
        return until
    }

    private static func command() -> String {
        "/fixture/claude"
    }

    private static func unexpectedPreparation() throws -> String {
        XCTFail("Request should be gated before launching the command")
        throw FixtureError.unexpectedPreparation
    }

    private static func snapshot(at date: Date, resetAfter: TimeInterval = 18_000) -> UsageSnapshot {
        UsageSnapshot(
            mainLimit: LimitReading(
                limitId: "claude",
                name: "Claude Code",
                window: UsageWindow(
                    remainingPercent: 62,
                    resetsAt: date.addingTimeInterval(resetAfter),
                    durationMinutes: 300
                )
            ),
            otherLimits: [], tokenHistory: [], resetCredits: [], fetchedAt: date
        )
    }

    private struct Context: Sendable {
        let directory: URL
        let clock = TestClock()

        init() throws {
            directory = FileManager.default.temporaryDirectory
                .appendingPathComponent("ClaudeUsageCoordinatorTests.\(UUID().uuidString)", isDirectory: true)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        }

        func coordinator(lockTimeout: Duration = .seconds(2)) -> ClaudeUsageCoordinator {
            ClaudeUsageCoordinator(directory: directory, now: { clock.now }, lockTimeout: lockTimeout)
        }

        func cleanUp() {
            try? FileManager.default.removeItem(at: directory)
        }
    }

    private final class TestClock: @unchecked Sendable {
        private let lock = NSLock()
        private var date = Date(timeIntervalSince1970: 1_800_000_000)

        var now: Date { lock.withLock { date } }

        func advance(by interval: TimeInterval) {
            lock.withLock { date.addTimeInterval(interval) }
        }
    }

    private actor RequestRecorder {
        private var preparationCount = 0
        private var requestCount = 0

        var counts: (prepare: Int, request: Int) { (preparationCount, requestCount) }

        func prepare() -> String {
            preparationCount += 1
            return ClaudeUsageCoordinatorTests.command()
        }

        func fetch(_ snapshot: UsageSnapshot) -> UsageSnapshot {
            requestCount += 1
            return snapshot
        }
    }

    private actor SuspendedRequest {
        private var continuation: CheckedContinuation<Void, Never>?
        private var started: CheckedContinuation<Void, Never>?
        private(set) var requestCount = 0

        func fetch(_ snapshot: UsageSnapshot) async -> UsageSnapshot {
            requestCount += 1
            await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                self.continuation = continuation
                started?.resume()
                started = nil
            }
            return snapshot
        }

        func waitUntilStarted() async {
            if requestCount > 0 { return }
            await withCheckedContinuation { started = $0 }
        }

        func resume() {
            continuation?.resume()
            continuation = nil
        }
    }

    private enum FixtureError: Error {
        case unexpectedResult
        case unexpectedPreparation
    }
}
