import Foundation

enum ClaudeClient {
    static func fetch(
        now: () -> Date = Date.init,
        readAccount: () -> ClaudeAccountReader.Account? = { ClaudeAccountReader.read() },
        runCommand: () async throws -> Data
    ) async throws -> UsageSnapshot {
        try Task.checkCancellation()
        let account = readAccount()
        let data = try await runCommand()
        try Task.checkCancellation()
        let email = account.flatMap { $0 == readAccount() ? $0.email : nil }
        return try decode(data, fetchedAt: now(), accountEmail: email)
    }

    static func decode(_ data: Data, fetchedAt: Date, accountEmail: String? = nil) throws -> UsageSnapshot {
        let report = try usageReport(from: data)
        guard let limits = report.rateLimits?.limits else { throw ClaudeClientError.usageUnavailable }
        let accountLimits = limits.compactMap { entry -> LimitReading? in
            switch (entry.kind, entry.group) {
            case ("session", "session"):
                reading(entry, id: "claude", name: "5-hour window", minutes: 300)
            case ("weekly_all", "weekly"):
                reading(entry, id: "claude", name: "Weekly window", minutes: 10_080)
            default:
                nil
            }
        }
        guard let primary = accountLimits.min(by: {
            $0.window.remainingPercent < $1.window.remainingPercent
        }) else { throw ClaudeClientError.mainLimitMissing }
        var others = accountLimits.filter { $0.id != primary.id }
        others.append(contentsOf: modelLimits(limits))
        others.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        return UsageSnapshot(
            mainLimit: LimitReading(limitId: "claude", name: "Claude Code", window: primary.window),
            otherLimits: others,
            tokenHistory: [], resetCredits: [], fetchedAt: fetchedAt, accountName: accountEmail
        )
    }

    private static func usageReport(from data: Data) throws -> Report {
        let decoder = JSONDecoder()
        let events: [Event]
        do {
            events = try data.split(separator: 0x0A).map { try decoder.decode(Event.self, from: Data($0)) }
        } catch { throw ClaudeClientError.invalidResponse }
        guard let result = events.last, result.type == "result" else { throw ClaudeClientError.invalidResponse }
        guard result.isError != true else { throw ClaudeClientError.commandFailed }
        // Only accept the built-in local command's structured output, never generated text or rounded display percentages.
        guard result.subtype == "success", result.localCommand == "usage",
              result.numTurns == 0, result.totalCostUSD == 0 else { throw ClaudeClientError.cliUpdateRequired }
        guard let event = events.last(where: {
            $0.type == "assistant" && $0.localCommandRun?.command == "usage" && $0.localCommandRun?.args == ""
        }) else { throw ClaudeClientError.cliUpdateRequired }
        guard let report = event.usageReport else { throw ClaudeClientError.usageUnavailable }
        return report
    }

    private static func modelLimits(_ limits: [Limit]) -> [LimitReading] {
        var readings: [LimitReading] = []
        for entry in limits {
            guard entry.group == "weekly", entry.kind == "weekly_scoped",
                  entry.isActive != false,
                  let model = entry.scope?.model,
                  let name = nonempty(model.displayName),
                  let identifier = nonempty(model.id) ?? nonempty(model.displayName) else { continue }
            let slug = identifier.lowercased().split(whereSeparator: { !$0.isLetter && !$0.isNumber }).joined(separator: "-")
            guard !slug.isEmpty, !slug.hasSuffix("all-models"), name.lowercased() != "all models",
                  let limit = reading(entry, id: "claude-\(slug)", name: "\(name) weekly", minutes: 10_080) else { continue }
            readings.removeAll { $0.limitId == limit.limitId }
            readings.append(limit)
        }
        return readings
    }

    private static func reading(_ payload: Limit, id: String, name: String, minutes: Int) -> LimitReading? {
        guard let used = payload.percent, used.isFinite, let rawReset = payload.resetsAt else { return nil }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let resetWithFraction = formatter.date(from: rawReset)
        formatter.formatOptions = [.withInternetDateTime]
        guard let reset = resetWithFraction ?? formatter.date(from: rawReset) else { return nil }
        return LimitReading(
            limitId: id, name: name,
            window: UsageWindow(remainingPercent: min(max(100 - used, 0), 100),
                                resetsAt: reset, durationMinutes: minutes)
        )
    }

    private static func nonempty(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else { return nil }
        return trimmed
    }

    private struct Event: Decodable {
        let type: String
        let subtype: String?
        let localCommand: String?
        let localCommandRun: Command?
        let usageReport: Report?
        let numTurns: Int?
        let totalCostUSD: Double?
        let isError: Bool?

        private enum CodingKeys: String, CodingKey {
            case type, subtype
            case localCommand = "local_command"
            case localCommandRun = "local_command_run"
            case usageReport = "usage_report"
            case numTurns = "num_turns"
            case totalCostUSD = "total_cost_usd"
            case isError = "is_error"
        }
    }

    private struct Command: Decodable {
        let command: String
        let args: String
    }

    private struct Report: Decodable {
        let rateLimits: RateLimits?
        private enum CodingKeys: String, CodingKey { case rateLimits = "rate_limits" }
    }

    private struct RateLimits: Decodable {
        let limits: [Limit]?
    }

    private struct Limit: Decodable {
        let kind: String?
        let group: String?
        let percent: Double?
        let resetsAt: String?
        let scope: Scope?
        let isActive: Bool?

        private enum CodingKeys: String, CodingKey {
            case kind, group, percent, scope
            case resetsAt = "resets_at"
            case isActive = "is_active"
        }
    }

    private struct Scope: Decodable { let model: Model? }

    private struct Model: Decodable {
        let id: String?
        let displayName: String?
        private enum CodingKeys: String, CodingKey {
            case id
            case displayName = "display_name"
        }
    }
}
