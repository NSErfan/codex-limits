import Foundation

enum ClaudeClient {
    static func fetch(allowCredentialPrompt: Bool = false) async throws -> UsageSnapshot {
        try Task.checkCancellation()
        let credentials = try ClaudeCredentialReader.read(allowPrompt: allowCredentialPrompt)
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpCookieStorage = nil
        configuration.urlCache = nil
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }
        return try await fetch(credentials: credentials) { request in
            try await session.data(for: request)
        }
    }

    static func fetch(
        credentials: ClaudeCredentials,
        fetchedAt: Date = Date(),
        transport: (URLRequest) async throws -> (Data, URLResponse)
    ) async throws -> UsageSnapshot {
        try Task.checkCancellation()
        var request = URLRequest(url: URL(string: "https://api.anthropic.com/api/oauth/usage")!)
        request.httpMethod = "GET"
        request.timeoutInterval = 20
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("Bearer \(credentials.accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")
        request.setValue("CodexLimits", forHTTPHeaderField: "User-Agent")

        do {
            let (data, response) = try await transport(request)
            try Task.checkCancellation()
            guard let response = response as? HTTPURLResponse else {
                throw ClaudeClientError.invalidResponse
            }
            switch response.statusCode {
            case 200:
                return try decode(data, fetchedAt: fetchedAt)
            case 401:
                throw ClaudeClientError.unauthorized
            case 403:
                throw ClaudeClientError.forbidden
            case 429:
                throw ClaudeClientError.rateLimited
            default:
                throw ClaudeClientError.serverError(response.statusCode)
            }
        } catch is CancellationError {
            throw CancellationError()
        } catch let error as ClaudeClientError {
            throw error
        } catch let error as URLError where error.code == .cancelled {
            throw CancellationError()
        } catch let error as URLError where error.code == .timedOut {
            throw ClaudeClientError.timedOut
        } catch {
            throw ClaudeClientError.networkUnavailable
        }
    }

    static func decode(_ data: Data, fetchedAt: Date) throws -> UsageSnapshot {
        guard let payload = try? JSONDecoder().decode(Payload.self, from: data) else {
            throw ClaudeClientError.invalidResponse
        }
        let accountLimits = [
            reading(payload.fiveHour, id: "claude", name: "5-hour window", minutes: 300),
            reading(payload.sevenDay, id: "claude", name: "Weekly window", minutes: 10_080)
        ].compactMap { $0 }
        guard let primary = accountLimits.min(by: {
            $0.window.remainingPercent < $1.window.remainingPercent
        }) else {
            throw ClaudeClientError.mainLimitMissing
        }
        var others = accountLimits.filter { $0.id != primary.id }
        var modelLimits = [
            reading(payload.sevenDaySonnet, id: "claude-sonnet", name: "Sonnet weekly", minutes: 10_080),
            reading(payload.sevenDayOpus, id: "claude-opus", name: "Opus weekly", minutes: 10_080),
            reading(payload.sevenDayOAuthApps, id: "claude-oauth-apps", name: "OAuth apps weekly", minutes: 10_080)
        ].compactMap { $0 }
        for entry in payload.limits ?? [] {
            guard entry.group == "weekly", entry.kind == "weekly_scoped",
                  entry.isActive != false,
                  let model = entry.scope?.model,
                  let name = nonempty(model.displayName),
                  let identifier = nonempty(model.id) ?? nonempty(model.displayName) else { continue }
            let slug = identifier.lowercased().split(whereSeparator: { !$0.isLetter && !$0.isNumber }).joined(separator: "-")
            guard !slug.isEmpty, !slug.hasSuffix("all-models"), name.lowercased() != "all models" else { continue }
            guard let limit = reading(
                Window(utilization: entry.percent, resetsAt: entry.resetsAt),
                id: "claude-\(slug)",
                name: "\(name) weekly",
                minutes: 10_080
            ) else { continue }
            modelLimits.removeAll { $0.limitId == limit.limitId }
            modelLimits.append(limit)
        }
        others.append(contentsOf: modelLimits)
        others.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        return UsageSnapshot(
            mainLimit: LimitReading(limitId: "claude", name: "Claude Code", window: primary.window),
            otherLimits: others,
            tokenHistory: [],
            resetCredits: [],
            fetchedAt: fetchedAt
        )
    }

    private static func reading(_ payload: Window?, id: String, name: String, minutes: Int) -> LimitReading? {
        guard let payload, let used = payload.utilization, used.isFinite,
              let rawReset = payload.resetsAt else { return nil }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let resetWithFraction = formatter.date(from: rawReset)
        formatter.formatOptions = [.withInternetDateTime]
        guard let reset = resetWithFraction ?? formatter.date(from: rawReset) else { return nil }
        return LimitReading(
            limitId: id,
            name: name,
            window: UsageWindow(
                remainingPercent: min(max(100 - used, 0), 100),
                resetsAt: reset,
                durationMinutes: minutes
            )
        )
    }

    private static func nonempty(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmed.isEmpty else { return nil }
        return trimmed
    }

    private struct Payload: Decodable {
        let fiveHour: Window?
        let sevenDay: Window?
        let sevenDaySonnet: Window?
        let sevenDayOpus: Window?
        let sevenDayOAuthApps: Window?
        let limits: [ScopedLimit]?

        private enum CodingKeys: String, CodingKey {
            case fiveHour = "five_hour"
            case sevenDay = "seven_day"
            case sevenDaySonnet = "seven_day_sonnet"
            case sevenDayOpus = "seven_day_opus"
            case sevenDayOAuthApps = "seven_day_oauth_apps"
            case limits
        }
    }

    private struct Window: Decodable {
        let utilization: Double?
        let resetsAt: String?

        private enum CodingKeys: String, CodingKey {
            case utilization
            case resetsAt = "resets_at"
        }
    }

    private struct ScopedLimit: Decodable {
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

    private struct Scope: Decodable {
        let model: Model?
    }

    private struct Model: Decodable {
        let id: String?
        let displayName: String?

        private enum CodingKeys: String, CodingKey {
            case id
            case displayName = "display_name"
        }
    }
}
