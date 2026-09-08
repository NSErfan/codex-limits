import Foundation
import XCTest
@testable import CodexWidgetKit

final class WeeklyWidgetStoreTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    func testPaceSurvivesStorageAndIsHiddenWhenStaleOrExpired() throws {
        let store = temporaryStore()
        defer { try? FileManager.default.removeItem(at: store.directory) }
        let snapshot = WeeklyWidgetSnapshot.preview(at: now, pace: .slowDown)
        try store.write(snapshot, writer: .collector)
        let restored = try XCTUnwrap(store.read())
        XCTAssertEqual(restored.pace(at: now), .slowDown)
        XCTAssertNil(restored.pace(at: now.addingTimeInterval(WeeklyWidgetSnapshot.staleInterval)))
        XCTAssertNil(restored.pace(at: restored.window!.resetsAt))
    }

    func testLegacySnapshotWithoutPaceStillDecodes() throws {
        let snapshot = WeeklyWidgetSnapshot.preview(at: now)
        let data = try JSONEncoder().encode(snapshot)
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        json.removeValue(forKey: "pace")
        let legacy = try JSONDecoder().decode(WeeklyWidgetSnapshot.self, from: JSONSerialization.data(withJSONObject: json))
        XCTAssertEqual(legacy.window, snapshot.window)
        XCTAssertEqual(legacy.status(at: now), .current)
        XCTAssertNil(legacy.pace(at: now))
    }

    func testConcurrentWritersKeepNewestReadingAndCombineHistory() throws {
        let store = temporaryStore()
        defer { try? FileManager.default.removeItem(at: store.directory) }
        let older = snapshot(offset: -600, remaining: 72)
        let newer = snapshot(offset: 0, remaining: 68)
        try store.write(newer, writer: .app)
        try store.write(older, writer: .collector)
        let result = try XCTUnwrap(store.read())
        XCTAssertEqual(result.fetchedAt, now)
        XCTAssertEqual(result.window?.remainingPercent, 68)
        XCTAssertEqual(result.samples.map(\.remainingPercent), [72, 68])
        try store.write(snapshot(offset: -1_200, remaining: 80), writer: .app)
        XCTAssertEqual(store.read(), result)
    }

    func testUsageWritersPreserveAppearanceWithoutChangingReadingDates() throws {
        let store = temporaryStore()
        defer { try? FileManager.default.removeItem(at: store.directory) }
        XCTAssertEqual(store.readAccent(), .automatic)
        try store.writeAccent(.indigo)
        XCTAssertNil(store.read())
        try store.write(snapshot(offset: -600, remaining: 72), writer: .app)
        try store.write(snapshot(offset: 0, remaining: 68), writer: .collector)
        XCTAssertEqual(store.readAccent(), .indigo)
        let reading = store.read()
        try store.writeAccent(.custom(red: 0.2, green: 0.4, blue: 0.6))
        XCTAssertEqual(store.read(), reading)
        XCTAssertEqual(store.readAccent(), .custom(red: 0.2, green: 0.4, blue: 0.6))
    }

    func testCorruptAndOutOfRangeAppearanceFallsBackToAutomatic() throws {
        let store = temporaryStore()
        defer { try? FileManager.default.removeItem(at: store.directory) }
        try store.writeAccent(.rose)
        let url = store.directory.appendingPathComponent("appearance.json")
        try Data("not JSON".utf8).write(to: url)
        XCTAssertEqual(store.readAccent(), .automatic)
        try JSONEncoder().encode(UsageAccent.custom(red: 2, green: 0, blue: 0)).write(to: url)
        XCTAssertEqual(store.readAccent(), .automatic)
        XCTAssertThrowsError(try store.writeAccent(.custom(red: -1, green: 0, blue: 0)))
    }

    func testResetExcludesPreviousWeekAndFutureSamples() throws {
        let old = snapshot(offset: -600, remaining: 2)
        let newWindow = WeeklyWidgetSnapshot.Window(
            remainingPercent: 99, startsAt: now, resetsAt: now.addingTimeInterval(7 * 86_400)
        )
        let new = WeeklyWidgetSnapshot(fetchedAt: now, window: newWindow, samples: [
            .init(date: now.addingTimeInterval(600), remainingPercent: 50),
            .init(date: now.addingTimeInterval(-600), remainingPercent: 2)
        ])
        let merged = new.merging([old])
        XCTAssertEqual(merged.samples, [.init(date: now, remainingPercent: 99)])
    }

    func testStaleAndExpiredReadingsAreDistinctFromCurrentBalance() {
        let value = snapshot(offset: 0, remaining: 68)
        XCTAssertEqual(value.status(at: now), .current)
        XCTAssertEqual(value.status(at: now.addingTimeInterval(1_799)), .current)
        XCTAssertEqual(value.status(at: now.addingTimeInterval(1_800)), .stale)
        XCTAssertEqual(value.status(at: value.window!.resetsAt), .expired)
        XCTAssertEqual(snapshot(offset: 0, remaining: .nan).status(at: now), .unavailable)
        XCTAssertEqual(snapshot(offset: 0, remaining: 101).status(at: now), .unavailable)
    }

    func testMissingWeeklyLimitDoesNotResurrectOldBalance() throws {
        let store = temporaryStore()
        defer { try? FileManager.default.removeItem(at: store.directory) }
        try store.write(snapshot(offset: -600, remaining: 68), writer: .app)
        try store.write(.init(fetchedAt: now, window: nil), writer: .collector)
        let value = try XCTUnwrap(store.read())
        XCTAssertNil(value.window)
        XCTAssertEqual(value.status(at: now), .unavailable)
    }

    func testMissingAndCorruptFilesReturnNoFabricatedUsage() throws {
        let store = temporaryStore()
        defer { try? FileManager.default.removeItem(at: store.directory) }
        XCTAssertNil(store.read())
        try FileManager.default.createDirectory(at: store.directory, withIntermediateDirectories: true)
        try Data("not JSON".utf8).write(to: store.directory.appendingPathComponent("app.json"))
        XCTAssertNil(store.read())
        try store.write(snapshot(offset: 0, remaining: 0), writer: .collector)
        XCTAssertEqual(store.read()?.window?.remainingPercent, 0)
    }

    func testHistoryIsBoundedAndKeepsStartAndLatestReading() {
        let value = snapshot(offset: 0, remaining: 68)
        let samples = (1 ... 5_000).map { index in
            WeeklyWidgetSnapshot.Sample(date: now.addingTimeInterval(-Double(index)), remainingPercent: 80)
        }
        let result = WeeklyWidgetSnapshot(fetchedAt: now, window: value.window, samples: samples).merging([])
        XCTAssertEqual(result.samples.count, 1_200)
        XCTAssertEqual(result.samples.first?.date, now.addingTimeInterval(-5_000))
        XCTAssertEqual(result.samples.last?.date, now)
        XCTAssertEqual(result.samples.last?.remainingPercent, 68)
    }

    private func snapshot(offset: TimeInterval, remaining: Double) -> WeeklyWidgetSnapshot {
        WeeklyWidgetSnapshot(
            fetchedAt: now.addingTimeInterval(offset),
            window: .init(remainingPercent: remaining, startsAt: now.addingTimeInterval(-3 * 86_400), resetsAt: now.addingTimeInterval(4 * 86_400))
        ).merging([])
    }

    private func temporaryStore() -> WeeklyWidgetStore {
        WeeklyWidgetStore(directory: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
    }
}
