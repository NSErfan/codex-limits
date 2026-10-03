import Foundation

protocol UsageFetchError: LocalizedError {
    var shouldRetryAutomatically: Bool { get }
    var requiresLogin: Bool { get }
}
