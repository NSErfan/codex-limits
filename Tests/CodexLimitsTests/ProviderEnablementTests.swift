import CodexWidgetKit
import Foundation
import XCTest
@testable import CodexLimits

final class ProviderEnablementTests: XCTestCase {
    func testEveryProviderIsOnByDefault() throws {
        try withDefaults { defaults in
            XCTAssertEqual(ProviderEnablement.enabledProviders(in: defaults), UsageProvider.allCases)
        }
    }

    func testTurningOffPersistsAndKeepsDeclarationOrder() throws {
        try withDefaults { defaults in
            XCTAssertTrue(ProviderEnablement.setEnabled(false, for: .claude, in: defaults))

            XCTAssertEqual(defaults.stringArray(forKey: ProviderEnablement.disabledKey), ["claude"])
            XCTAssertEqual(ProviderEnablement.enabledProviders(in: defaults), [.codex, .copilot])
            XCTAssertFalse(ProviderEnablement.setEnabled(false, for: .claude, in: defaults), "No change to report")

            XCTAssertTrue(ProviderEnablement.setEnabled(true, for: .claude, in: defaults))
            XCTAssertEqual(ProviderEnablement.enabledProviders(in: defaults), UsageProvider.allCases)
            XCTAssertEqual(defaults.stringArray(forKey: ProviderEnablement.disabledKey), [])
        }
    }

    func testLastProviderThatIsOnCannotBeTurnedOff() throws {
        try withDefaults { defaults in
            ProviderEnablement.setEnabled(false, for: .codex, in: defaults)
            ProviderEnablement.setEnabled(false, for: .copilot, in: defaults)

            XCTAssertFalse(ProviderEnablement.setEnabled(false, for: .claude, in: defaults))
            XCTAssertEqual(ProviderEnablement.enabledProviders(in: defaults), [.claude])
            XCTAssertEqual(defaults.stringArray(forKey: ProviderEnablement.disabledKey), ["codex", "copilot"])
        }
    }

    func testUnknownStoredValuesAreIgnoredAndKeptWhenSaving() throws {
        try withDefaults { defaults in
            defaults.set(["future-provider", "claude"], forKey: ProviderEnablement.disabledKey)

            XCTAssertEqual(ProviderEnablement.enabledProviders(in: defaults), [.codex, .copilot])
            ProviderEnablement.setEnabled(true, for: .claude, in: defaults)
            ProviderEnablement.setEnabled(false, for: .copilot, in: defaults)

            XCTAssertEqual(defaults.stringArray(forKey: ProviderEnablement.disabledKey), ["future-provider", "copilot"])
        }
    }

    func testStoredStateWithEveryProviderOffShowsEveryProvider() throws {
        try withDefaults { defaults in
            defaults.set(UsageProvider.allCases.map(\.rawValue), forKey: ProviderEnablement.disabledKey)
            XCTAssertEqual(ProviderEnablement.enabledProviders(in: defaults), UsageProvider.allCases)
        }
    }

    func testTurningOffFromStoredStateWithEveryProviderOffTurnsOffOnlyThatProvider() throws {
        try withDefaults { defaults in
            defaults.set(["future-provider"] + UsageProvider.allCases.map(\.rawValue), forKey: ProviderEnablement.disabledKey)

            XCTAssertTrue(ProviderEnablement.setEnabled(false, for: .claude, in: defaults))

            XCTAssertEqual(ProviderEnablement.enabledProviders(in: defaults), [.codex, .copilot])
            XCTAssertEqual(defaults.stringArray(forKey: ProviderEnablement.disabledKey), ["future-provider", "claude"])
        }
    }

    private func withDefaults(_ body: (UserDefaults) throws -> Void) throws {
        let suite = "ProviderEnablementTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        try body(defaults)
    }
}
