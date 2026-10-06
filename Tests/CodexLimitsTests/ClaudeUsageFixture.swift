import Foundation

enum ClaudeUsageFixture {
    static func limit(
        _ kind: String = "weekly_all", percent: Double = 34,
        reset: Any = "2027-01-20T09:00:00.563632+00:00"
    ) -> [String: Any] {
        ["kind": kind, "group": kind == "session" ? "session" : "weekly", "percent": percent,
         "resets_at": reset, "is_active": true]
    }

    static func output(
        limits: [[String: Any]]? = [limit()],
        command: String = "usage", args: String = "", turns: Int = 0, cost: Double = 0,
        includeReport: Bool = true, isError: Bool = false
    ) throws -> Data {
        var event: [String: Any] = [
            "type": "assistant", "local_command_run": ["command": command, "args": args]
        ]
        if includeReport {
            event["usage_report"] = ["rate_limits": ["limits": limits as Any? ?? NSNull()]]
        }
        let result: [String: Any] = [
            "type": "result", "subtype": "success", "is_error": isError,
            "num_turns": turns, "total_cost_usd": cost, "local_command": command
        ]
        return try [event, result].reduce(into: Data()) { output, value in
            output.append(try JSONSerialization.data(withJSONObject: value, options: [.sortedKeys]))
            output.append(0x0A)
        }
    }
}
