import CryptoKit
import Darwin
import Foundation

struct ClaudeUsageCoordinator: Sendable {
    static let minimumInterval: TimeInterval = 15 * 60
    private static let fallbackCooldown: TimeInterval = 30 * 60
    private static let maximumFallbackCooldown: TimeInterval = 2 * 60 * 60

    let directory: URL
    var now: @Sendable () -> Date = { Date() }
    var lockTimeout: Duration = .seconds(30)

    static func shared() -> Self {
        let service = ClaudeCredentialReader.location(
            environment: ProcessInfo.processInfo.environment,
            homeDirectory: FileManager.default.homeDirectoryForCurrentUser,
            workingDirectory: URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        ).service
        let profile = SHA256.hash(data: Data(service.utf8)).map { String(format: "%02x", $0) }.joined()
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return Self(directory: base
            .appendingPathComponent("com.github.nserfan.CodexLimits/ClaudeRefresh", isDirectory: true)
            .appendingPathComponent(profile, isDirectory: true))
    }

    func fetch(
        allowCredentialPrompt: Bool,
        readAccount: @escaping @Sendable () -> ClaudeAccountReader.Account? = { ClaudeAccountReader.read() },
        readCredentials: @escaping @Sendable (Bool) throws -> ClaudeCredentials = {
            try ClaudeCredentialReader.read(allowPrompt: $0)
        },
        request: @escaping @Sendable (ClaudeCredentials, ClaudeAccountReader.Account?) async throws -> UsageSnapshot = {
            try await ClaudeClient.fetch(credentials: $0, account: $1)
        }
    ) async throws -> UsageFetchResult {
        try await fetch(
            prepare: {
                // Keep the same CLI account on both sides of the single credential read.
                let account = readAccount()
                let credentials = try readCredentials(allowCredentialPrompt)
                return Authentication(credentials: credentials, account: account == readAccount() ? account : nil)
            },
            request: { try await request($0.credentials, $0.account) }
        )
    }

    func fetch<Prepared: Sendable>(
        prepare: @Sendable () async throws -> Prepared,
        request: @Sendable (Prepared) async throws -> UsageSnapshot
    ) async throws -> UsageFetchResult {
        let lock: FileLock
        do {
            lock = try await acquireLock()
        } catch ClaudeRefreshError.inProgress {
            return .deferred(ClaudeRefreshError.inProgress, snapshot: try? readState().snapshot)
        }
        defer { lock.release() }
        var state = try readState()
        if let existing = cachedResult(state, at: now()) { return existing }

        // A Keychain prompt can outlast the spacing interval. Reserve only after
        // credentials are ready, immediately before the HTTP operation starts.
        let credentials = try await prepare()
        try Task.checkCancellation()
        state.lastAttemptAt = now()
        try writeState(state)
        do {
            let snapshot = try await request(credentials)
            let completedAt = now()
            state.lastAttemptAt = completedAt
            state.snapshot = snapshot
            state.cooldownUntil = nil
            state.rateLimitCount = 0
            state.authenticationFailure = nil
            try writeState(state)
            return .fetched(snapshot, nextRefreshAt: completedAt.addingTimeInterval(Self.minimumInterval))
        } catch let error as ClaudeClientError {
            let completedAt = now()
            let nextRefreshAt = completedAt.addingTimeInterval(Self.minimumInterval)
            state.lastAttemptAt = completedAt
            if case let .rateLimited(retryAfter) = error {
                state.rateLimitCount = min(state.rateLimitCount + 1, 3)
                let fallback = min(Self.fallbackCooldown * pow(2, Double(state.rateLimitCount - 1)),
                                   Self.maximumFallbackCooldown)
                let cooldown = max(
                    nextRefreshAt,
                    retryAfter ?? completedAt.addingTimeInterval(fallback)
                )
                state.cooldownUntil = cooldown
                try writeState(state)
                return .deferred(ClaudeRefreshError.rateLimited(until: cooldown),
                                 snapshot: state.snapshot, nextRefreshAt: cooldown)
            }
            state.authenticationFailure = error == .unauthorized ? .unauthorized
                : error == .forbidden ? .forbidden : nil
            try writeState(state)
            return .deferred(ClaudeRefreshError.failed(error, until: nextRefreshAt),
                             snapshot: state.snapshot, nextRefreshAt: nextRefreshAt)
        } catch {
            state.lastAttemptAt = now()
            try writeState(state)
            throw error
        }
    }

    private struct Authentication: Sendable {
        let credentials: ClaudeCredentials
        let account: ClaudeAccountReader.Account?
    }

    private func cachedResult(_ state: State, at date: Date) -> UsageFetchResult? {
        if let cooldown = state.cooldownUntil, date < cooldown {
            return .deferred(ClaudeRefreshError.rateLimited(until: cooldown), snapshot: state.snapshot, nextRefreshAt: cooldown)
        }
        guard let attempt = state.lastAttemptAt else { return nil }
        let next = attempt.addingTimeInterval(Self.minimumInterval)
        guard date < next else { return nil }
        if let failure = state.authenticationFailure {
            return .deferred(ClaudeRefreshError.failed(failure.error, until: next), snapshot: state.snapshot, nextRefreshAt: next)
        }
        if let snapshot = state.snapshot, snapshot.fetchedAt <= date,
           date.timeIntervalSince(snapshot.fetchedAt) < Self.minimumInterval,
           snapshot.mainLimit.window.resetsAt > date {
            return .cached(snapshot, nextRefreshAt: next)
        }
        return .deferred(ClaudeRefreshError.tooSoon(until: next), snapshot: state.snapshot, nextRefreshAt: next)
    }

    private func acquireLock() async throws -> FileLock {
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true,
                                                    attributes: [.posixPermissions: 0o700])
        } catch { throw ClaudeRefreshError.storageUnavailable }
        let descriptor = open(directory.appendingPathComponent("request.lock").path, O_CREAT | O_RDWR | O_CLOEXEC, 0o600)
        guard descriptor >= 0 else { throw ClaudeRefreshError.storageUnavailable }
        let lock = FileLock(descriptor: descriptor)
        let deadline = ContinuousClock.now.advanced(by: lockTimeout)
        while flock(descriptor, LOCK_EX | LOCK_NB) != 0 {
            guard errno == EWOULDBLOCK || errno == EAGAIN else {
                throw ClaudeRefreshError.storageUnavailable
            }
            guard ContinuousClock.now < deadline else { throw ClaudeRefreshError.inProgress }
            try await Task.sleep(for: .milliseconds(50))
        }
        return lock
    }

    private func readState() throws -> State {
        let url = directory.appendingPathComponent("state.json")
        guard FileManager.default.fileExists(atPath: url.path) else { return State() }
        do {
            let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
            guard size <= 1_000_000 else { throw ClaudeRefreshError.storageUnavailable }
            let state = try JSONDecoder().decode(State.self, from: Data(contentsOf: url))
            guard state.version == 1, (0 ... 3).contains(state.rateLimitCount) else {
                throw ClaudeRefreshError.storageUnavailable
            }
            return state
        } catch { throw ClaudeRefreshError.storageUnavailable }
    }

    private func writeState(_ state: State) throws {
        do {
            let url = directory.appendingPathComponent("state.json")
            try JSONEncoder().encode(state).write(to: url, options: .atomic)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        } catch { throw ClaudeRefreshError.storageUnavailable }
    }

    private struct State: Codable {
        var version = 1
        var lastAttemptAt: Date?
        var snapshot: UsageSnapshot?
        var cooldownUntil: Date?
        var rateLimitCount = 0
        var authenticationFailure: AuthenticationFailure?
    }

    private enum AuthenticationFailure: String, Codable {
        case unauthorized, forbidden
        var error: ClaudeClientError { self == .unauthorized ? .unauthorized : .forbidden }
    }

    private final class FileLock {
        private var descriptor: Int32
        init(descriptor: Int32) { self.descriptor = descriptor }
        deinit { release() }
        func release() {
            guard descriptor >= 0 else { return }
            flock(descriptor, LOCK_UN)
            close(descriptor)
            descriptor = -1
        }
    }
}
