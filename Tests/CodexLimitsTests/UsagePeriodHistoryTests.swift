import CodexWidgetKit
import Foundation
import XCTest
@testable import CodexLimits

@MainActor
final class UsagePeriodHistoryTests: XCTestCase {
    func testAccountPeriodsAreFoundInEitherMainOrderWithoutSelectingModelLimits() throws {
        let now = Date()
        for provider in UsageProvider.allCases {
            for mainPeriod in UsagePeriod.allCases {
                let snapshot = Self.snapshot(provider: provider, mainPeriod: mainPeriod, observedAt: now)

                XCTAssertEqual(snapshot.limit(for: .fiveHour, provider: provider)?.window.remainingPercent, 82)
                XCTAssertEqual(snapshot.limit(for: .weekly, provider: provider)?.window.remainingPercent, 46)
                XCTAssertNil(snapshot.limit(for: .weekly, provider: provider == .codex ? .claude : .codex))
            }
        }
    }

    func testMissingAccountPeriodDoesNotFallBackToModelOrDifferentDuration() {
        let now = Date()
        let snapshot = UsageSnapshot(
            mainLimit: Self.limit(provider: .claude, period: .fiveHour, remainingPercent: 82, resetsAt: now),
            otherLimits: [
                LimitReading(limitId: "claude-sonnet", name: "Sonnet", window: UsageWindow(
                    remainingPercent: 18, resetsAt: now, durationMinutes: 10_080)),
                LimitReading(limitId: "claude", name: "Claude Code", window: UsageWindow(
                    remainingPercent: 25, resetsAt: now, durationMinutes: 43_200))
            ],
            tokenHistory: [], resetCredits: [], fetchedAt: now
        )

        XCTAssertNil(snapshot.limit(for: .weekly, provider: .claude))
        XCTAssertEqual(snapshot.limit(for: .fiveHour, provider: .claude)?.window.remainingPercent, 82)
    }

    func testMonitorRecordsBothPeriodsWhenMainLimitOrderChanges() async throws {
        let context = try Context()
        defer { context.cleanUp() }
        let first = Self.snapshot(provider: .claude, mainPeriod: .weekly, observedAt: context.now)
        let second = Self.snapshot(provider: .claude, mainPeriod: .fiveHour,
                                   observedAt: context.now.addingTimeInterval(60),
                                   resetsAt: context.reset, fiveHourRemaining: 71, weeklyRemaining: 43)
        let sequence = SnapshotSequence([first, second])
        let monitor = context.monitor(provider: .claude) { .fetched(await sequence.next()) }

        await monitor.refresh()
        await monitor.refresh()

        XCTAssertEqual(monitor.samples(for: .fiveHour).map(\.remainingPercent), [82, 71])
        XCTAssertEqual(monitor.samples(for: .weekly).map(\.remainingPercent), [46, 43])
        XCTAssertEqual(monitor.samples(for: .fiveHour).map(\.observedAt), [first.fetchedAt, second.fetchedAt])
        XCTAssertEqual(monitor.samples(for: .weekly).map(\.observedAt), [first.fetchedAt, second.fetchedAt])
        XCTAssertEqual(monitor.samples.map(\.remainingPercent), [46, 71])
    }

    func testPeriodsWithTheSameResetTimestampStaySeparateOnDisk() async throws {
        let context = try Context()
        defer { context.cleanUp() }
        let snapshot = Self.snapshot(provider: .codex, observedAt: context.now, resetsAt: context.reset)
        let monitor = context.monitor(provider: .codex) { .fetched(snapshot) }

        await monitor.refresh()

        for period in UsagePeriod.allCases {
            let expected = try Self.sample(in: snapshot, period: period, provider: .codex)
            XCTAssertEqual(monitor.samples(for: period), [expected])
            let saved = await context.readHistory(at: context.periodDirectory(provider: .codex, period: period))
            XCTAssertEqual(saved.samples, [expected])
            XCTAssertNil(saved.errorMessage)
        }
    }

    func testColdLaunchRestoresBothPeriodHistoriesBeforeFetchAndCachedRefreshKeepsObservationTimes() async throws {
        let context = try Context()
        defer { context.cleanUp() }
        let snapshot = Self.snapshot(provider: .claude, observedAt: context.now)
        let original = context.monitor(provider: .claude) { .fetched(snapshot) }
        await original.refresh()
        let calls = FetchCounter()
        let restored = context.monitor(provider: .claude) {
            await calls.record()
            return .cached(snapshot, nextRefreshAt: snapshot.fetchedAt.addingTimeInterval(900))
        }

        XCTAssertEqual(restored.snapshot, snapshot)
        XCTAssertEqual(restored.samples(for: .fiveHour), original.samples(for: .fiveHour))
        XCTAssertEqual(restored.samples(for: .weekly), original.samples(for: .weekly))
        let countBeforeRefresh = await calls.count
        XCTAssertEqual(countBeforeRefresh, 0)

        let fetched = await restored.refresh()

        XCTAssertFalse(fetched)
        for period in UsagePeriod.allCases {
            XCTAssertEqual(restored.samples(for: period), [try Self.sample(in: snapshot, period: period, provider: .claude)])
        }
    }

    func testLegacyMigrationUsesExplicitDurationsAndExcludesAmbiguousSamples() async throws {
        let context = try Context()
        defer { context.cleanUp() }
        let fiveHour = UsageSample(observedAt: context.now.addingTimeInterval(-120), remainingPercent: 84,
                                   resetsAt: context.reset, durationMinutes: 300)
        let weekly = UsageSample(observedAt: context.now.addingTimeInterval(-60), remainingPercent: 47,
                                 resetsAt: context.reset, durationMinutes: 10_080)
        let ambiguous = UsageSample(observedAt: context.now, remainingPercent: 12, resetsAt: context.reset)
        let legacySamples = [fiveHour, weekly, ambiguous]
        context.defaults.set(try JSONEncoder().encode(LegacyState(samples: legacySamples)), forKey: "usageState")
        let historyNow = context.now
        let legacyHistory = UsageHistory(localDirectory: context.historyDirectory(provider: .codex),
                                         installationID: "legacy", now: { historyNow })
        _ = await legacyHistory.load(legacySamples: legacySamples)
        let monitor = context.monitor(provider: .codex) { throw CodexClientError.invalidResponse }

        await monitor.refresh()

        XCTAssertEqual(monitor.samples(for: .fiveHour), [fiveHour])
        XCTAssertEqual(monitor.samples(for: .weekly), [weekly])
        XCTAssertEqual(Set(monitor.samples), Set(legacySamples))
        let restored = context.monitor(provider: .codex) { throw CodexClientError.invalidResponse }
        XCTAssertEqual(restored.samples(for: .fiveHour), [fiveHour])
        XCTAssertEqual(restored.samples(for: .weekly), [weekly])
    }

    func testColdLaunchSeedsWeeklyHistoryFromWidgetWithoutInferringAmbiguousLegacyDuration() async throws {
        let context = try Context()
        defer { context.cleanUp() }
        let widget = Self.widgetSnapshot(observedAt: context.now)
        let store = context.widgetStore(provider: .claude)
        try store.write(widget, writer: .collector)
        let ambiguous = UsageSample(observedAt: context.now, remainingPercent: 10, resetsAt: context.reset)
        context.defaults.set(try JSONEncoder().encode(LegacyState(samples: [ambiguous])),
                             forKey: "claude.usageState")
        let calls = FetchCounter()
        let monitor = context.monitor(provider: .claude) {
            await calls.record()
            throw CodexClientError.invalidResponse
        }
        let expected = try XCTUnwrap(store.read()).samples.map {
            UsageSample(observedAt: $0.date, remainingPercent: $0.remainingPercent,
                        resetsAt: context.reset, durationMinutes: 10_080)
        }

        XCTAssertNil(monitor.snapshot)
        XCTAssertEqual(monitor.samples(for: .weekly), expected)
        XCTAssertTrue(monitor.samples(for: .fiveHour).isEmpty)
        let countBeforeRefresh = await calls.count
        XCTAssertEqual(countBeforeRefresh, 0)

        await monitor.refresh()

        XCTAssertEqual(monitor.samples(for: .weekly), expected)
        let saved = await context.readHistory(at: context.periodDirectory(provider: .claude, period: .weekly))
        XCTAssertEqual(saved.samples, expected)
        XCTAssertFalse(monitor.samples(for: .weekly).contains(ambiguous))
    }

    func testWidgetHistoryFromAnotherProviderCannotSeedPeriodHistory() async throws {
        let context = try Context()
        defer { context.cleanUp() }
        let codexStore = context.widgetStore(provider: .codex)
        try codexStore.write(Self.widgetSnapshot(observedAt: context.now), writer: .collector)
        let monitor = context.monitor(provider: .claude, widgetStore: codexStore) {
            throw CodexClientError.invalidResponse
        }

        XCTAssertTrue(monitor.samples(for: .weekly).isEmpty)
        await monitor.refresh()
        XCTAssertTrue(monitor.samples(for: .weekly).isEmpty)
        XCTAssertTrue(monitor.samples(for: .fiveHour).isEmpty)
    }

    func testNonweeklyWidgetWindowCannotSeedWeeklyHistory() throws {
        let context = try Context()
        defer { context.cleanUp() }
        let store = context.widgetStore(provider: .codex)
        let short = WeeklyWidgetSnapshot(fetchedAt: context.now, window: .init(
            remainingPercent: 55,
            startsAt: context.reset.addingTimeInterval(-300 * 60),
            resetsAt: context.reset
        ))
        try store.write(short, writer: .collector)

        let monitor = context.monitor(provider: .codex) { throw CodexClientError.invalidResponse }

        XCTAssertTrue(monitor.samples(for: .weekly).isEmpty)
        XCTAssertTrue(monitor.samples(for: .fiveHour).isEmpty)
    }

    func testCollectorPersistsBothPeriodsWithOriginalObservationAndPreservesLegacyMainHistory() async throws {
        let context = try Context()
        defer { context.cleanUp() }
        for provider in UsageProvider.allCases {
            let snapshot = Self.snapshot(provider: provider, mainPeriod: .fiveHour,
                                         observedAt: context.now.addingTimeInterval(-600))

            let collected = await BackgroundCollector.collectOnce(
                defaults: context.defaults,
                historyDirectory: context.historyDirectory(provider: provider),
                widgetStore: context.widgetStore(provider: provider),
                provider: provider,
                fetchUsage: { snapshot }
            )

            XCTAssertTrue(collected)
            for period in UsagePeriod.allCases {
                let saved = await context.readHistory(at: context.periodDirectory(provider: provider, period: period))
                XCTAssertEqual(saved.samples, [try Self.sample(in: snapshot, period: period, provider: provider)])
            }
            let legacy = await context.readHistory(at: context.historyDirectory(provider: provider))
            XCTAssertEqual(legacy.samples, [try Self.sample(in: snapshot, period: .fiveHour, provider: provider)])
            let monitor = context.monitor(provider: provider) { throw CodexClientError.invalidResponse }
            await monitor.refresh()
            XCTAssertEqual(monitor.samples(for: .fiveHour).map(\.observedAt), [snapshot.fetchedAt])
            XCTAssertEqual(monitor.samples(for: .weekly).map(\.observedAt), [snapshot.fetchedAt])
        }
    }

    func testSharedFolderSeparatesBothProvidersAndPeriodsAndRestoresTheirBookmarks() async throws {
        let context = try Context()
        defer { context.cleanUp() }
        let shared = try context.makeSharedDirectory()
        for provider in [UsageProvider.claude, .codex] {
            let snapshot = Self.snapshot(provider: provider, observedAt: context.now,
                                         fiveHourRemaining: provider == .codex ? 87 : 63,
                                         weeklyRemaining: provider == .codex ? 51 : 29)
            let monitor = context.monitor(provider: provider) { .fetched(snapshot) }
            await monitor.refresh()
            await monitor.connectHistoryFolder(shared)

            XCTAssertNil(monitor.syncErrorMessage)
            XCTAssertEqual(monitor.syncFolderName, shared.lastPathComponent)
            for period in UsagePeriod.allCases {
                let directory = context.sharedPeriodDirectory(shared, provider: provider, period: period)
                let state = await context.readHistory(at: directory)
                XCTAssertEqual(state.samples, [try Self.sample(in: snapshot, period: period, provider: provider)])
            }

            let restored = context.monitor(provider: provider) { throw CodexClientError.invalidResponse }
            await restored.refresh()
            XCTAssertEqual(restored.syncFolderName, shared.lastPathComponent)
            XCTAssertNil(restored.syncErrorMessage)
            for period in UsagePeriod.allCases {
                XCTAssertEqual(restored.samples(for: period), monitor.samples(for: period))
            }
        }

        let other = try Context(now: context.now)
        defer { other.cleanUp() }
        for provider in UsageProvider.allCases {
            let imported = other.monitor(provider: provider) { throw CodexClientError.invalidResponse }
            await imported.connectHistoryFolder(shared)

            XCTAssertNil(imported.syncErrorMessage)
            XCTAssertEqual(imported.samples(for: .fiveHour).map(\.remainingPercent), provider == .codex ? [87] : [63])
            XCTAssertEqual(imported.samples(for: .weekly).map(\.remainingPercent), provider == .codex ? [51] : [29])
        }
    }

    func testDisconnectStopsPublishingBothPeriodsAndReconnectCatchesUp() async throws {
        let context = try Context()
        defer { context.cleanUp() }
        let shared = try context.makeSharedDirectory()
        let first = Self.snapshot(provider: .claude, observedAt: context.now)
        let second = Self.snapshot(provider: .claude, observedAt: context.now.addingTimeInterval(60),
                                   fiveHourRemaining: 70, weeklyRemaining: 41)
        let sequence = SnapshotSequence([first, second])
        let monitor = context.monitor(provider: .claude) { .fetched(await sequence.next()) }
        await monitor.refresh()
        await monitor.connectHistoryFolder(shared)

        await monitor.stopHistorySync()
        await monitor.refresh()

        XCTAssertNil(monitor.syncFolderName)
        XCTAssertNil(context.defaults.data(forKey: "claude.historySyncBookmark"))
        for period in UsagePeriod.allCases {
            let directory = context.sharedPeriodDirectory(shared, provider: .claude, period: period)
            let remote = await context.readHistory(at: directory)
            XCTAssertEqual(remote.samples, [try Self.sample(in: first, period: period, provider: .claude)])
            XCTAssertEqual(monitor.samples(for: period).count, 2)
        }

        await monitor.connectHistoryFolder(shared)

        XCTAssertNil(monitor.syncErrorMessage)
        XCTAssertEqual(monitor.syncFolderName, shared.lastPathComponent)
        for period in UsagePeriod.allCases {
            let directory = context.sharedPeriodDirectory(shared, provider: .claude, period: period)
            let remote = await context.readHistory(at: directory)
            XCTAssertEqual(remote.samples, monitor.samples(for: period))
        }
    }

    func testReplacingSyncFolderWithUnavailableFolderStopsPublishingToPreviousFolderAndRecovers() async throws {
        let context = try Context()
        defer { context.cleanUp() }
        let firstFolder = try context.makeSharedDirectory()
        let replacement = context.directory.appendingPathComponent("replacement", isDirectory: true)
        let historyNow = context.now
        let history = UsagePeriodHistory(localDirectory: context.historyDirectory(provider: .codex),
                                         installationID: "app", provider: .codex, now: { historyNow })
        let first = Self.snapshot(provider: .codex, observedAt: context.now)
        let second = Self.snapshot(provider: .codex, observedAt: context.now.addingTimeInterval(60),
                                   fiveHourRemaining: 70, weeklyRemaining: 41)
        _ = await history.load(legacySamples: [])
        _ = await history.record(first)
        let connected = await history.connect(to: firstFolder)
        XCTAssertNil(connected.errorMessage)

        let failedReplacement = await history.connect(to: replacement)
        _ = await history.record(second)

        XCTAssertNotNil(failedReplacement.errorMessage)
        for period in UsagePeriod.allCases {
            let directory = context.sharedPeriodDirectory(firstFolder, provider: .codex, period: period)
            let remote = await context.readHistory(at: directory)
            XCTAssertEqual(remote.samples, [try Self.sample(in: first, period: period, provider: .codex)])
        }

        try FileManager.default.createDirectory(at: replacement, withIntermediateDirectories: true)
        let recovered = await history.synchronize()

        XCTAssertNil(recovered.errorMessage)
        for period in UsagePeriod.allCases {
            let directory = context.sharedPeriodDirectory(replacement, provider: .codex, period: period)
            let remote = await context.readHistory(at: directory)
            XCTAssertEqual(remote.samples, [try Self.sample(in: first, period: period, provider: .codex),
                                           try Self.sample(in: second, period: period, provider: .codex)])
        }
    }

    private static func snapshot(
        provider: UsageProvider,
        mainPeriod: UsagePeriod = .weekly,
        observedAt: Date,
        resetsAt: Date? = nil,
        fiveHourRemaining: Double = 82,
        weeklyRemaining: Double = 46
    ) -> UsageSnapshot {
        let reset = resetsAt ?? observedAt.addingTimeInterval(3_600)
        let fiveHour = limit(provider: provider, period: .fiveHour, remainingPercent: fiveHourRemaining, resetsAt: reset)
        let weekly = limit(provider: provider, period: .weekly, remainingPercent: weeklyRemaining, resetsAt: reset)
        let model = LimitReading(limitId: "\(provider.rawValue)-model", name: "Model", window: UsageWindow(
            remainingPercent: 9, resetsAt: reset, durationMinutes: 10_080))
        return UsageSnapshot(mainLimit: mainPeriod == .weekly ? weekly : fiveHour,
                             otherLimits: [model, mainPeriod == .weekly ? fiveHour : weekly],
                             tokenHistory: [], resetCredits: [], fetchedAt: observedAt)
    }

    private static func limit(
        provider: UsageProvider, period: UsagePeriod, remainingPercent: Double, resetsAt: Date
    ) -> LimitReading {
        LimitReading(limitId: provider.rawValue, name: provider.displayName, window: UsageWindow(
            remainingPercent: remainingPercent, resetsAt: resetsAt, durationMinutes: period.durationMinutes))
    }

    private static func sample(in snapshot: UsageSnapshot, period: UsagePeriod, provider: UsageProvider) throws -> UsageSample {
        let window = try XCTUnwrap(snapshot.limit(for: period, provider: provider)).window
        return UsageSample(observedAt: snapshot.fetchedAt, remainingPercent: window.remainingPercent,
                           resetsAt: window.resetsAt, durationMinutes: window.durationMinutes)
    }

    private static func widgetSnapshot(observedAt: Date) -> WeeklyWidgetSnapshot {
        let reset = observedAt.addingTimeInterval(3_600)
        return WeeklyWidgetSnapshot(fetchedAt: observedAt, window: .init(
            remainingPercent: 55, startsAt: reset.addingTimeInterval(-10_080 * 60), resetsAt: reset
        ), samples: [
            .init(date: observedAt.addingTimeInterval(-120), remainingPercent: 62),
            .init(date: observedAt.addingTimeInterval(-60), remainingPercent: 58)
        ])
    }

    private struct LegacyState: Encodable {
        let snapshot: UsageSnapshot? = nil
        let samples: [UsageSample]
        let previousStatus: PaceStatus? = nil
    }

    private actor SnapshotSequence {
        private var snapshots: [UsageSnapshot]

        init(_ snapshots: [UsageSnapshot]) { self.snapshots = snapshots }

        func next() -> UsageSnapshot { snapshots.removeFirst() }
    }

    private actor FetchCounter {
        private(set) var count = 0

        func record() { count += 1 }
    }

    private struct Context {
        let name = "UsagePeriodHistoryTests.\(UUID().uuidString)"
        let directory: URL
        let defaults: UserDefaults
        let now: Date
        var reset: Date { now.addingTimeInterval(3_600) }

        init(now: Date = Date()) throws {
            self.now = now
            directory = FileManager.default.temporaryDirectory.appendingPathComponent(name, isDirectory: true)
            defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        }

        func historyDirectory(provider: UsageProvider) -> URL {
            directory.appendingPathComponent(provider.rawValue, isDirectory: true)
        }

        func periodDirectory(provider: UsageProvider, period: UsagePeriod) -> URL {
            historyDirectory(provider: provider)
                .appendingPathComponent("Windows", isDirectory: true)
                .appendingPathComponent(String(period.durationMinutes), isDirectory: true)
        }

        func sharedPeriodDirectory(_ root: URL, provider: UsageProvider, period: UsagePeriod) -> URL {
            let providerRoot = provider == .claude ? root.appendingPathComponent("Claude", isDirectory: true) : root
            return providerRoot.appendingPathComponent("Windows", isDirectory: true)
                .appendingPathComponent(String(period.durationMinutes), isDirectory: true)
        }

        func widgetStore(provider: UsageProvider) -> WeeklyWidgetStore {
            WeeklyWidgetStore(directory: directory.appendingPathComponent("widget-\(provider.rawValue)"), provider: provider)
        }

        @MainActor
        func monitor(
            provider: UsageProvider,
            widgetStore: WeeklyWidgetStore? = nil,
            fetch: @escaping @Sendable () async throws -> UsageFetchResult
        ) -> UsageMonitor {
            let historyNow = now
            return UsageMonitor(provider: provider, defaults: defaults,
                                historyDirectory: historyDirectory(provider: provider), historyNow: { historyNow },
                                widgetStore: widgetStore ?? self.widgetStore(provider: provider), fetchResult: { try await fetch() },
                                recoveryDelaysNanoseconds: [], startsAutomatically: false)
        }

        func readHistory(at root: URL) async -> UsageHistory.State {
            let historyNow = now
            return await UsageHistory(localDirectory: root, installationID: "reader", now: { historyNow }).load()
        }

        func makeSharedDirectory() throws -> URL {
            let shared = directory.appendingPathComponent("shared", isDirectory: true)
            try FileManager.default.createDirectory(at: shared, withIntermediateDirectories: true)
            return shared
        }

        func cleanUp() {
            defaults.removePersistentDomain(forName: name)
            try? FileManager.default.removeItem(at: directory)
        }
    }
}
