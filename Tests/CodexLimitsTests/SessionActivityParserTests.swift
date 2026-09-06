import XCTest
@testable import CodexLimits

final class SessionActivityParserTests: XCTestCase {
    func testCumulativeCountersCountOnlyNewTokens() {
        var parser = SessionActivityParser(sessionID: "session")
        _ = parser.consume(context(model: "model-a", effort: "high"))
        let first = parser.consume(token(total: 100, last: 100))
        XCTAssertEqual(first?.tokens.total, 100)
        XCTAssertNil(parser.consume(token(total: 100, last: 100, second: 2)))
        let second = parser.consume(token(total: 140, last: 40, second: 3))
        XCTAssertEqual(second?.tokens.total, 40)
        XCTAssertEqual(second?.group, .init(model: "model-a", effort: "high"))
    }

    func testInitialAndResetCountersUseLatestUsageNotHistoricalTotal() {
        var parser = SessionActivityParser(sessionID: "session")
        XCTAssertEqual(parser.consume(token(total: 1_000, last: 20))?.tokens.total, 20)
        XCTAssertEqual(parser.consume(token(total: 30, last: 10, second: 2))?.tokens.total, 10)
        XCTAssertEqual(parser.consume(token(total: 60, last: 30, second: 3))?.tokens.total, 30)
    }

    func testModelSwitchAndMissingEffortDoNotInheritOldSettings() {
        var parser = SessionActivityParser(sessionID: "session")
        _ = parser.consume(context(model: "model-a", effort: "HIGH"))
        XCTAssertEqual(parser.consume(token(total: 100, last: 100))?.group.effort, "high")
        _ = parser.consume(context(model: "model-b", effort: nil))
        XCTAssertEqual(parser.consume(token(total: 120, last: 20, second: 2))?.group, .init(model: "model-b", effort: "unknown"))
        _ = parser.consume(record(type: "event_msg", payload: ["type": "task_started", "turn_id": "next-turn"]))
        XCTAssertEqual(parser.consume(token(total: 140, last: 20, second: 3))?.group, .init(model: "Unknown model", effort: "unknown"))
    }

    func testMissingInfoAndMalformedRecordsDoNotInventUsage() {
        var parser = SessionActivityParser(sessionID: "session")
        XCTAssertNil(parser.consume(record(type: "event_msg", payload: ["type": "token_count"])))
        XCTAssertNil(parser.consume(Data("{\"type\":\"turn_context\",broken".utf8)))
        XCTAssertEqual(parser.invalidRecords, 1)
        XCTAssertNil(parser.consume(token(total: -1, last: -1)))
        XCTAssertNil(parser.consume(record(type: "response_item", payload: ["content": "not retained"])))
    }

    func testUnreadableRecordsDoNotCarryStaleAttributionOrCountersForward() {
        var parser = SessionActivityParser(sessionID: "session")
        _ = parser.consume(context(model: "model-a", effort: "high"))
        _ = parser.consume(token(total: 100, last: 100))
        parser.skipRelevantRecord()
        let recovered = parser.consume(token(total: 1_000, last: 20, second: 2))
        XCTAssertEqual(recovered?.tokens.total, 20)
        XCTAssertEqual(recovered?.group, .init(model: "Unknown model", effort: "unknown"))
        XCTAssertEqual(parser.invalidRecords, 1)
    }

    func testCopiedTurnEventsHaveTheSameIdentityAcrossSessions() {
        var original = SessionActivityParser(sessionID: "original")
        var copied = SessionActivityParser(sessionID: "copy")
        _ = original.consume(context(model: "model-a", effort: "medium"))
        _ = copied.consume(context(model: "model-a", effort: "medium"))
        XCTAssertEqual(original.consume(token(total: 100, last: 100))?.id, copied.consume(token(total: 100, last: 100))?.id)
    }

    private func context(model: String, effort: String?) -> Data {
        var payload = ["turn_id": "shared-turn", "model": model]
        if let effort { payload["effort"] = effort }
        return record(type: "turn_context", payload: payload)
    }

    private func token(total: Int, last: Int, second: Int = 1) -> Data {
        func usage(_ amount: Int) -> [String: Int] {
            ["input_tokens": amount, "output_tokens": 0, "cached_input_tokens": 0, "total_tokens": amount]
        }
        return record(type: "event_msg", payload: ["type": "token_count", "info": [
            "total_token_usage": usage(total), "last_token_usage": usage(last)
        ]], second: second)
    }

    private func record(type: String, payload: [String: Any], second: Int = 1) -> Data {
        try! JSONSerialization.data(withJSONObject: ["type": type, "timestamp": String(format: "2026-09-05T00:00:%02d.000Z", second), "payload": payload], options: [.sortedKeys])
    }
}
