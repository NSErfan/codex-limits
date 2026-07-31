import XCTest
@testable import CodexLimits

final class LegacyBundleMigrationTests: XCTestCase {
    private let newIdentifier = "com.github.nserfan.CodexLimits"
    private var root: URL!
    private var defaults: UserDefaults!
    private var legacyDefaults: UserDefaults!
    private var defaultsName: String!
    private var legacyName: String!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("migration-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defaultsName = "test-new-\(UUID().uuidString)"
        legacyName = "test-legacy-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: defaultsName)
        legacyDefaults = UserDefaults(suiteName: legacyName)
    }

    override func tearDownWithError() throws {
        UserDefaults.standard.removePersistentDomain(forName: defaultsName)
        UserDefaults.standard.removePersistentDomain(forName: legacyName)
        try? FileManager.default.removeItem(at: root)
    }

    private func migrate(identifier: String? = nil) {
        LegacyBundleMigration.run(
            identifier: identifier ?? newIdentifier,
            defaults: defaults,
            legacyDefaults: legacyDefaults,
            applicationSupport: root
        )
    }

    private func writeLegacyHistory(_ contents: String = "{\"version\":1}") throws {
        let historyDirectory = root
            .appendingPathComponent(LegacyBundleMigration.legacyIdentifier, isDirectory: true)
            .appendingPathComponent("History", isDirectory: true)
        try FileManager.default.createDirectory(at: historyDirectory, withIntermediateDirectories: true)
        try Data(contents.utf8).write(to: historyDirectory.appendingPathComponent("2026-07-30.json"))
    }

    private func migratedHistoryFile() -> URL {
        root
            .appendingPathComponent(newIdentifier, isDirectory: true)
            .appendingPathComponent("History", isDirectory: true)
            .appendingPathComponent("2026-07-30.json")
    }

    func testCopiesPreferencesAndHistory() throws {
        try writeLegacyHistory()
        legacyDefaults.set(7.0, forKey: UsageMonitor.safetyBufferKey)
        legacyDefaults.set("credit-1", forKey: UsageMonitor.paceTargetCreditIDKey)
        legacyDefaults.set("installation-id", forKey: "historyInstallationID")

        migrate()

        XCTAssertEqual(defaults.double(forKey: UsageMonitor.safetyBufferKey), 7)
        XCTAssertEqual(defaults.string(forKey: UsageMonitor.paceTargetCreditIDKey), "credit-1")
        XCTAssertEqual(defaults.string(forKey: "historyInstallationID"), "installation-id")
        XCTAssertTrue(FileManager.default.fileExists(atPath: migratedHistoryFile().path))
        XCTAssertTrue(defaults.bool(forKey: LegacyBundleMigration.completionKey))
    }

    func testLeavesTheLegacyCopyInPlace() throws {
        try writeLegacyHistory()

        migrate()

        let legacyFile = root
            .appendingPathComponent(LegacyBundleMigration.legacyIdentifier, isDirectory: true)
            .appendingPathComponent("History", isDirectory: true)
            .appendingPathComponent("2026-07-30.json")
        XCTAssertTrue(FileManager.default.fileExists(atPath: legacyFile.path))
    }

    func testDoesNotOverwriteExistingValuesOrHistory() throws {
        try writeLegacyHistory("legacy")
        legacyDefaults.set(7.0, forKey: UsageMonitor.safetyBufferKey)
        defaults.set(3.0, forKey: UsageMonitor.safetyBufferKey)
        let destination = migratedHistoryFile()
        try FileManager.default.createDirectory(
            at: destination.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data("current".utf8).write(to: destination)

        migrate()

        XCTAssertEqual(defaults.double(forKey: UsageMonitor.safetyBufferKey), 3)
        XCTAssertEqual(try String(contentsOf: destination, encoding: .utf8), "current")
    }

    func testRunsOnlyOnce() throws {
        try writeLegacyHistory()
        legacyDefaults.set(7.0, forKey: UsageMonitor.safetyBufferKey)
        migrate()

        defaults.removeObject(forKey: UsageMonitor.safetyBufferKey)
        legacyDefaults.set(9.0, forKey: UsageMonitor.safetyBufferKey)
        migrate()

        XCTAssertNil(defaults.object(forKey: UsageMonitor.safetyBufferKey))
    }

    func testDoesNothingWhenRunningUnderTheLegacyIdentifier() throws {
        try writeLegacyHistory()
        legacyDefaults.set(7.0, forKey: UsageMonitor.safetyBufferKey)

        migrate(identifier: LegacyBundleMigration.legacyIdentifier)

        XCTAssertNil(defaults.object(forKey: UsageMonitor.safetyBufferKey))
        XCTAssertFalse(defaults.bool(forKey: LegacyBundleMigration.completionKey))
    }

    func testCleanInstallWithoutLegacyDataIsMarkedComplete() {
        migrate()

        XCTAssertFalse(FileManager.default.fileExists(atPath: migratedHistoryFile().path))
        XCTAssertTrue(defaults.bool(forKey: LegacyBundleMigration.completionKey))
    }
}
