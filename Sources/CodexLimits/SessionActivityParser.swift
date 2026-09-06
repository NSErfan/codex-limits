import Foundation

/// Reads metadata and usage counters only. Conversation text is never retained.
struct SessionActivityParser {
    private var sessionID: String
    private var turnID: String?
    private var model = "Unknown model"
    private var effort = "unknown"
    private var previous: ModelActivityEvent.Tokens?
    private let decoder = JSONDecoder()
    private let fractionalDate = ISO8601DateFormatter()
    private let plainDate = ISO8601DateFormatter()
    private(set) var invalidRecords = 0

    init(sessionID: String) {
        self.sessionID = sessionID
        fractionalDate.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    }

    mutating func consume(_ line: Data) -> ModelActivityEvent? {
        // Rollouts put the envelope type before payloads. Avoid decoding large
        // tool outputs or message bodies that are irrelevant to usage metadata.
        guard Self.hasRelevantPrefix(line) else { return nil }
        guard let record = try? decoder.decode(Record.self, from: line) else {
            skipRelevantRecord()
            return nil
        }
        let payload = record.payload
        switch record.type {
        case "session_meta":
            sessionID = payload.id ?? payload.sessionID ?? sessionID
        case "turn_context":
            turnID = payload.turnID
            model = nonempty(payload.model) ?? "Unknown model"
            effort = nonempty(payload.effort ?? payload.reasoningEffort)?.lowercased() ?? "unknown"
        case "event_msg" where payload.type == "task_started":
            if payload.turnID != turnID {
                turnID = payload.turnID
                model = "Unknown model"
                effort = "unknown"
            }
        case "event_msg" where payload.type == "token_count":
            guard let info = payload.info, let total = info.total, total.isValid else { return nil }
            let old = previous
            previous = total
            guard total != old else { return nil }
            // On an initial/truncated log or a counter reset, only the explicit
            // latest usage is attributable to this event, not the whole total.
            let delta = old.flatMap { total.increase(from: $0) } ?? info.last
            guard let delta, delta.isValid, delta.total > 0,
                  let timestamp = record.timestamp,
                  let date = fractionalDate.date(from: timestamp) ?? plainDate.date(from: timestamp) else { return nil }
            let identity = "\(turnID ?? sessionID)|\(timestamp)|\(total.input)|\(total.output)|\(total.total)"
            return .init(id: identity, date: date, group: .init(model: model, effort: effort), tokens: delta)
        default: break
        }
        return nil
    }

    mutating func skipRelevantRecord() {
        // A lost context/counter record makes inherited attribution uncertain.
        // Resume from explicit metadata and the next event's latest usage.
        invalidRecords += 1
        previous = nil
        turnID = nil
        model = "Unknown model"
        effort = "unknown"
    }

    static func hasRelevantPrefix(_ line: Data) -> Bool {
        let prefix = String(decoding: line.prefix(512), as: UTF8.self)
        return ["session_meta", "turn_context", "token_count", "task_started"].contains(where: prefix.contains)
    }

    private func nonempty(_ value: String?) -> String? {
        guard let value, !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        return value
    }

    private struct Record: Decodable {
        let type: String
        let timestamp: String?
        let payload: Payload
    }

    private struct Payload: Decodable {
        let type: String?
        let id: String?
        let sessionID: String?
        let turnID: String?
        let model: String?
        let effort: String?
        let reasoningEffort: String?
        let info: Info?
        enum CodingKeys: String, CodingKey {
            case type, id, model, effort, info
            case sessionID = "session_id", turnID = "turn_id", reasoningEffort = "reasoning_effort"
        }
    }

    private struct Info: Decodable {
        let total: ModelActivityEvent.Tokens?
        let last: ModelActivityEvent.Tokens?
        enum CodingKeys: String, CodingKey {
            case total = "total_token_usage", last = "last_token_usage"
        }
    }
}
