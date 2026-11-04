import Foundation

protocol UsageFetchError: LocalizedError, Sendable {
    var shouldRetryAutomatically: Bool { get }
    var requiresLogin: Bool { get }
    /// The provider's CLI couldn't be found, so installing it is the next step.
    var requiresInstallation: Bool { get }
}
