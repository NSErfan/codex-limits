import Foundation

enum CopilotClient {
    static func fetch() async throws -> UsageSnapshot {
        let executable = try CopilotUsageCommand.executable()
        return try await fetch { try await CopilotUsageCommand.run(executable: executable) }
    }

    static func fetch(
        now: () -> Date = Date.init,
        runCommand: () async throws -> CopilotUsageCommand.Response
    ) async throws -> UsageSnapshot {
        try Task.checkCancellation()
        let response = try await runCommand()
        try Task.checkCancellation()
        return try decode(response, fetchedAt: now())
    }

    static func decode(_ response: CopilotUsageCommand.Response, fetchedAt: Date) throws -> UsageSnapshot {
        switch response.statusCode {
        case 200: break
        case 401: throw CopilotClientError.unauthorized
        case 403: throw CopilotClientError.forbidden
        case 404: throw CopilotClientError.copilotUnavailable
        case 429: throw CopilotClientError.rateLimited
        default: throw CopilotClientError.httpStatus(response.statusCode)
        }
        let account: Account
        do {
            account = try JSONDecoder().decode(Account.self, from: response.body)
        } catch { throw CopilotClientError.invalidResponse }

        let allowances = Allowance.allCases.compactMap { allowance in
            account.remainingPercent(for: allowance).map { (allowance: allowance, remainingPercent: $0) }
        }
        // Premium requests are the paid allowance; plans without them are bounded by their tightest quota.
        guard let primary = allowances.first(where: { $0.allowance == .premiumRequests })
            ?? allowances.min(by: { $0.remainingPercent < $1.remainingPercent }) else { throw CopilotClientError.allowanceNotMetered }
        guard let resetsAt = account.resetsAt,
              let startsAt = monthlyCalendar.date(byAdding: .month, value: -1, to: resetsAt) else {
            throw CopilotClientError.resetDateMissing
        }
        let durationMinutes = Int(resetsAt.timeIntervalSince(startsAt) / 60)
        func reading(_ allowance: Allowance, id: String, remainingPercent: Double) -> LimitReading {
            LimitReading(limitId: id, name: allowance.name,
                         window: UsageWindow(remainingPercent: remainingPercent, resetsAt: resetsAt,
                                             durationMinutes: durationMinutes))
        }
        return UsageSnapshot(
            mainLimit: reading(primary.allowance, id: "copilot", remainingPercent: primary.remainingPercent),
            otherLimits: allowances.filter { $0.allowance != primary.allowance }.map {
                reading($0.allowance, id: "copilot-\($0.allowance.rawValue)", remainingPercent: $0.remainingPercent)
            },
            tokenHistory: [], resetCredits: [], fetchedAt: fetchedAt,
            accountName: account.login
        )
    }

    /// Copilot allowances reset monthly at midnight UTC.
    private static let monthlyCalendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }()

    private enum Allowance: String, CaseIterable {
        case premiumRequests = "premium_interactions"
        case chat
        case completions

        var name: String {
            switch self {
            case .premiumRequests: "Premium requests"
            case .chat: "Chat messages"
            case .completions: "Code completions"
            }
        }
    }

    private struct Account: Decodable {
        let login: String?
        let resetsAt: Date?
        private let quotaSnapshots: [String: Quota]
        private let monthlyQuotas: [String: Double]
        private let limitedUserQuotas: [String: Double]

        private enum CodingKeys: String, CodingKey {
            case login
            case quotaResetDateUTC = "quota_reset_date_utc"
            case quotaResetDate = "quota_reset_date"
            case limitedUserResetDate = "limited_user_reset_date"
            case quotaSnapshots = "quota_snapshots"
            case monthlyQuotas = "monthly_quotas"
            case limitedUserQuotas = "limited_user_quotas"
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            login = (try? container.decodeIfPresent(String.self, forKey: .login))?
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .nilIfEmpty
            resetsAt = [CodingKeys.quotaResetDateUTC, .quotaResetDate, .limitedUserResetDate].lazy
                .compactMap { try? container.decodeIfPresent(String.self, forKey: $0) }
                .compactMap(Self.date(from:))
                .first
            quotaSnapshots = (try? container.decodeIfPresent([String: Quota].self, forKey: .quotaSnapshots)) ?? [:]
            monthlyQuotas = (try? container.decodeIfPresent([String: Double].self, forKey: .monthlyQuotas)) ?? [:]
            limitedUserQuotas = (try? container.decodeIfPresent([String: Double].self, forKey: .limitedUserQuotas)) ?? [:]
        }

        func remainingPercent(for allowance: Allowance) -> Double? {
            if let percent = quotaSnapshots[allowance.rawValue]?.remainingPercent { return percent }
            // Copilot Free can report limits as monthly totals with remaining counts instead.
            guard let total = monthlyQuotas[allowance.rawValue], total > 0,
                  let remaining = limitedUserQuotas[allowance.rawValue] else { return nil }
            return Quota.clamped(remaining / total * 100)
        }

        private static func date(from value: String) -> Date? {
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let date = formatter.date(from: value) { return date }
            formatter.formatOptions = [.withInternetDateTime]
            if let date = formatter.date(from: value) { return date }
            formatter.formatOptions = [.withFullDate]
            return formatter.date(from: value)
        }
    }

    private struct Quota: Decodable {
        let entitlement: Double?
        let remaining: Double?
        let percentRemaining: Double?
        let unlimited: Bool?

        private enum CodingKeys: String, CodingKey {
            case entitlement, remaining, unlimited
            case percentRemaining = "percent_remaining"
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            entitlement = try? container.decodeIfPresent(Double.self, forKey: .entitlement)
            remaining = try? container.decodeIfPresent(Double.self, forKey: .remaining)
            percentRemaining = try? container.decodeIfPresent(Double.self, forKey: .percentRemaining)
            unlimited = try? container.decodeIfPresent(Bool.self, forKey: .unlimited)
        }

        /// Percentage left of a limited allowance. Unlimited quotas and
        /// zero-entitlement placeholders have no balance to track.
        var remainingPercent: Double? {
            guard unlimited != true, let entitlement, entitlement > 0 else { return nil }
            guard let percent = percentRemaining ?? remaining.map({ $0 / entitlement * 100 }) else { return nil }
            return Self.clamped(percent)
        }

        /// Overage can push the reported balance below zero.
        static func clamped(_ percent: Double) -> Double? {
            percent.isFinite ? min(max(percent, 0), 100) : nil
        }
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
