import XCTest
@testable import CodexLimits

final class SessionActivityReaderTests: XCTestCase {
    func testArchivedCopiesAreDeduplicatedAndAppendedRecordsReload() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let sessions = root.appendingPathComponent("sessions")
        let archive = root.appendingPathComponent("archived_sessions")
        try FileManager.default.createDirectory(at: sessions, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: archive, withIntermediateDirectories: true)
        let live = sessions.appendingPathComponent("one.jsonl")
        let copy = archive.appendingPathComponent("copy.jsonl")
        let context = "{\"type\":\"turn_context\",\"payload\":{\"model\":\"model-a\",\"effort\":\"high\",\"turn_id\":\"shared\"}}\n"
        let initial = context + token(total: 100, last: 100, second: 1) + "\n"
        try Data(initial.utf8).write(to: live)
        try Data(initial.utf8).write(to: copy)
        let reader = SessionActivityReader()
        let since = Date(timeIntervalSince1970: 0)
        let first = try await reader.load(home: root, since: since)
        XCTAssertEqual(first.filesRead, 2)
        XCTAssertEqual(first.events.count, 1)
        XCTAssertEqual(first.events.first?.tokens.total, 100)
        let repeated = try await reader.load(home: root, since: since)
        XCTAssertEqual(repeated.events, first.events)
        let next = token(total: 150, last: 50, second: 2)
        try Data((initial + next).utf8).write(to: live)
        let partial = try await reader.load(home: root, since: since)
        XCTAssertEqual(partial.events.count, 1, "An incomplete last line must wait for the writer")
        try Data((initial + next + "\n").utf8).write(to: live)
        let appended = try await reader.load(home: root, since: since)
        XCTAssertEqual(appended.events.count, 2)
        XCTAssertEqual(appended.events.reduce(0) { $0 + $1.tokens.total }, 150)
    }

    func testMissingFolderAndOversizedLinesHaveExplicitCoverage() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let reader = SessionActivityReader()
        let missing = try await reader.load(home: root, since: .distantPast)
        XCTAssertFalse(missing.folderExists)
        let sessions = root.appendingPathComponent("sessions")
        try FileManager.default.createDirectory(at: sessions, withIntermediateDirectories: true)
        let log = "{\"type\":\"turn_context\",\"payload\":" + String(repeating: "x", count: 2_200_000) + "\n" + token(total: 5, last: 5, second: 1) + "\n"
        try Data(log.utf8).write(to: sessions.appendingPathComponent("one.jsonl"))
        let result = try await reader.load(home: root, since: .distantPast)
        XCTAssertEqual(result.issueCount, 1)
        XCTAssertEqual(result.events.count, 1)
        XCTAssertEqual(result.events.first?.group.model, "Unknown model")
    }

    private func token(total: Int, last: Int, second: Int) -> String {
        """
        {"type":"event_msg","timestamp":"2026-09-05T00:00:0\(second)Z","payload":{"type":"token_count","info":{"total_token_usage":{"input_tokens":\(total),"output_tokens":0,"cached_input_tokens":0,"total_tokens":\(total)},"last_token_usage":{"input_tokens":\(last),"output_tokens":0,"cached_input_tokens":0,"total_tokens":\(last)}}}}
        """
    }
}
