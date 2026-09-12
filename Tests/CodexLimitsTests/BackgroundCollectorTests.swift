import Foundation
import XCTest
@testable import CodexLimits

final class BackgroundCollectorTests: XCTestCase {
    func testCollectArgumentIsOnlyRecognizedAfterTheExecutableName() {
        XCTAssertTrue(
            BackgroundCollector.shouldRun(arguments: ["CodexLimits", "--collect"])
        )
        XCTAssertTrue(
            BackgroundCollector.shouldRun(
                arguments: ["/Applications/App/Contents/MacOS/CodexLimits", "extra", "--collect"]
            )
        )
        XCTAssertFalse(BackgroundCollector.shouldRun(arguments: ["CodexLimits"]))
        XCTAssertFalse(BackgroundCollector.shouldRun(arguments: ["--collect"]))
        XCTAssertFalse(BackgroundCollector.shouldRun(arguments: []))
    }

    func testCollectOnceRecordsTheFetchedSampleUnderItsOwnWriterDirectory() async throws {
        let context = try makeContext()
        defer { context.cleanUp() }
        let snapshot = Self.snapshot(remainingPercent: 64)

        let success = await BackgroundCollector.collectOnce(
            defaults: context.defaults,
            historyDirectory: context.historyDirectory,
            fetchUsage: { snapshot }
        )

        XCTAssertTrue(success)
        let reader = UsageHistory(
            localDirectory: context.historyDirectory,
            installationID: "reader"
        )
        let state = await reader.load()
        XCTAssertEqual(
            state.samples,
            [
                UsageSample(
                    observedAt: snapshot.fetchedAt,
                    remainingPercent: 64,
                    resetsAt: snapshot.mainLimit.window.resetsAt,
                    durationMinutes: snapshot.mainLimit.window.durationMinutes
                )
            ]
        )
        let collectorID = try XCTUnwrap(
            context.defaults.string(forKey: BackgroundCollector.installationIDKey)
        )
        let writerFiles = try FileManager.default.contentsOfDirectory(
            at: context.historyDirectory
                .appendingPathComponent("installations", isDirectory: true)
                .appendingPathComponent(collectorID, isDirectory: true),
            includingPropertiesForKeys: nil
        )
        XCTAssertEqual(writerFiles.filter { $0.pathExtension == "json" }.count, 1)
    }

    func testCollectorInstallationIDIsStableAndDistinctFromTheApps() throws {
        let context = try makeContext()
        defer { context.cleanUp() }
        let appID = UUID().uuidString.lowercased()
        context.defaults.set(appID, forKey: "historyInstallationID")

        let first = BackgroundCollector.installationID(in: context.defaults)
        let second = BackgroundCollector.installationID(in: context.defaults)

        XCTAssertEqual(first, second)
        XCTAssertNotEqual(first, appID)
    }

    func testFailedFetchWritesNothingAndReportsFailure() async throws {
        let context = try makeContext()
        defer { context.cleanUp() }

        let success = await BackgroundCollector.collectOnce(
            defaults: context.defaults,
            historyDirectory: context.historyDirectory,
            fetchUsage: { throw CodexClientError.invalidResponse }
        )

        XCTAssertFalse(success)
        XCTAssertFalse(
            FileManager.default.fileExists(atPath: context.historyDirectory.path)
        )
    }

    func testCollectOnceLeavesTheAppsStoredStateAlone() async throws {
        let context = try makeContext()
        defer { context.cleanUp() }
        let storedState = Data("app-owned".utf8)
        let appInstallationID = UUID().uuidString.lowercased()
        context.defaults.set(storedState, forKey: "usageState")
        context.defaults.set(appInstallationID, forKey: "historyInstallationID")

        _ = await BackgroundCollector.collectOnce(
            defaults: context.defaults,
            historyDirectory: context.historyDirectory,
            fetchUsage: { Self.snapshot(remainingPercent: 50) }
        )

        XCTAssertEqual(context.defaults.data(forKey: "usageState"), storedState)
        XCTAssertEqual(
            context.defaults.string(forKey: "historyInstallationID"),
            appInstallationID
        )
    }

    @MainActor
    func testMonitorPicksUpSamplesRecordedByTheCollector() async throws {
        let context = try makeContext()
        defer { context.cleanUp() }
        let collected = Self.snapshot(remainingPercent: 42)
        _ = await BackgroundCollector.collectOnce(
            defaults: context.defaults,
            historyDirectory: context.historyDirectory,
            fetchUsage: { collected }
        )

        let monitor = UsageMonitor(
            defaults: context.defaults,
            historyDirectory: context.historyDirectory,
            fetchUsage: { throw CodexClientError.timedOut },
            startsAutomatically: false
        )
        await monitor.refresh()

        XCTAssertEqual(
            monitor.samples,
            [
                UsageSample(
                    observedAt: collected.fetchedAt,
                    remainingPercent: 42,
                    resetsAt: collected.mainLimit.window.resetsAt,
                    durationMinutes: collected.mainLimit.window.durationMinutes
                )
            ]
        )
    }

    func testBundledAgentPlistMatchesTheRegistrationContract() throws {
        let plistURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Resources", isDirectory: true)
            .appendingPathComponent(BackgroundCollection.agentPlistName)
        let plist = try XCTUnwrap(
            try PropertyListSerialization.propertyList(
                from: Data(contentsOf: plistURL),
                format: nil
            ) as? [String: Any]
        )

        XCTAssertEqual(
            plist["Label"] as? String,
            "com.github.nserfan.CodexLimits.collector"
        )
        XCTAssertEqual(plist["BundleProgram"] as? String, "Contents/MacOS/CodexLimits")
        let arguments = try XCTUnwrap(plist["ProgramArguments"] as? [String])
        XCTAssertTrue(BackgroundCollector.shouldRun(arguments: arguments))
        let interval = try XCTUnwrap(plist["StartInterval"] as? Int)
        XCTAssertGreaterThanOrEqual(interval, 600)
        XCTAssertEqual(plist["RunAtLoad"] as? Bool, false)
        XCTAssertEqual(
            plist["AssociatedBundleIdentifiers"] as? [String],
            ["com.github.nserfan.CodexLimits"]
        )
    }

    private func makeContext() throws -> Context {
        let suiteName = "BackgroundCollectorTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        let historyDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(suiteName, isDirectory: true)
        return Context(
            defaults: defaults,
            suiteName: suiteName,
            historyDirectory: historyDirectory
        )
    }

    // Anchored near the real clock: `UsageHistory` prunes samples outside its
    // retention window measured from the current date.
    private static let referenceDate = Date()

    private static func snapshot(remainingPercent: Double) -> UsageSnapshot {
        UsageSnapshot(
            mainLimit: LimitReading(
                limitId: "codex",
                name: "Codex",
                window: UsageWindow(
                    remainingPercent: remainingPercent,
                    resetsAt: referenceDate.addingTimeInterval(100_000),
                    durationMinutes: 10_080
                )
            ),
            otherLimits: [],
            tokenHistory: [],
            resetCredits: [],
            fetchedAt: referenceDate
        )
    }

    private struct Context {
        let defaults: UserDefaults
        let suiteName: String
        let historyDirectory: URL

        func cleanUp() {
            defaults.removePersistentDomain(forName: suiteName)
            try? FileManager.default.removeItem(at: historyDirectory)
        }
    }
}
