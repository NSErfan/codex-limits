import Foundation

protocol UsageFetchError: LocalizedError, Sendable {
    var shouldRetryAutomatically: Bool { get }
    var requiresLogin: Bool { get }
}
