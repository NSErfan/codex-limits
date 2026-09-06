import Foundation

struct ModelActivityEvent: Identifiable, Equatable, Sendable {
    struct Group: Hashable, Sendable {
        let model: String
        let effort: String
        var label: String { "\(model) · \(effort.capitalized)" }
    }

    struct Tokens: Decodable, Equatable, Sendable {
        let input: Int64
        let output: Int64
        let cached: Int64
        let total: Int64

        enum CodingKeys: String, CodingKey {
            case input = "input_tokens", output = "output_tokens"
            case cached = "cached_input_tokens", total = "total_tokens"
        }

        var isValid: Bool {
            [input, output, cached, total].allSatisfy { $0 >= 0 && $0 <= 1_000_000_000_000_000 }
                && cached <= input
        }

        func increase(from previous: Self) -> Self? {
            guard input >= previous.input, output >= previous.output,
                  cached >= previous.cached, total >= previous.total else { return nil }
            return .init(input: input - previous.input, output: output - previous.output,
                         cached: cached - previous.cached, total: total - previous.total)
        }
    }

    let id: String
    let date: Date
    let group: Group
    let tokens: Tokens
}
