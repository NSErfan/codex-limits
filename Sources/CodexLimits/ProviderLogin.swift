import AppKit
import CodexWidgetKit
import Foundation

enum ProviderLogin {
    static func installationURL(for provider: UsageProvider) -> URL {
        switch provider {
        case .codex: URL(string: "https://developers.openai.com/codex/cli")!
        case .claude: URL(string: "https://code.claude.com/docs/en/setup")!
        case .copilot: URL(string: "https://cli.github.com")!
        }
    }

    @MainActor static func open(for provider: UsageProvider) async throws {
        guard let executable = ProviderExecutable.path(for: provider) else {
            throw LaunchError.cliNotFound(provider)
        }
        guard let terminal = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.Terminal") else {
            throw LaunchError.terminalUnavailable
        }
        let commandFile = try writeCommand(for: provider, executable: executable)
        do {
            _ = try await NSWorkspace.shared.open(
                [commandFile], withApplicationAt: terminal,
                configuration: NSWorkspace.OpenConfiguration()
            )
        } catch {
            try? FileManager.default.removeItem(at: commandFile.deletingLastPathComponent())
            throw LaunchError.couldNotOpenTerminal
        }
    }

    static func command(
        for provider: UsageProvider, executable: String,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> String {
        let profileKeys = profileKeys(for: provider)
        let unsetKeys = profileKeys.filter { environment[$0] == nil } + credentialKeys(for: provider)
        let profile = profileKeys.compactMap { key in
            environment[key].map { "\(key)=\($0)" }
        }
        return (["/usr/bin/env"] + unsetKeys.flatMap { ["-u", $0] } + profile + [executable]
            + loginArguments(for: provider, environment: environment))
            .map(shellQuote).joined(separator: " ")
    }

    private static func loginArguments(for provider: UsageProvider, environment: [String: String]) -> [String] {
        switch provider {
        case .codex: ["login"]
        case .claude: ["auth", "login", "--claudeai"]
        case .copilot: ["auth", "login", "--web", "--hostname", environment["GH_HOST"] ?? "github.com"]
        }
    }

    /// Variables that choose where the CLI keeps its sign-in. Terminal gets the app's values, so both use one profile.
    private static func profileKeys(for provider: UsageProvider) -> [String] {
        switch provider {
        case .codex: ["CODEX_HOME"]
        case .claude: ["CLAUDE_CONFIG_DIR", "CLAUDE_SECURESTORAGE_CONFIG_DIR"]
        case .copilot: ["GH_CONFIG_DIR", "XDG_CONFIG_HOME", "GH_HOST"]
        }
    }

    /// Token variables that would make the CLI skip saving the new sign-in, which the app reads.
    private static func credentialKeys(for provider: UsageProvider) -> [String] {
        switch provider {
        case .codex, .claude: []
        case .copilot: ["GH_TOKEN", "GITHUB_TOKEN"]
        }
    }

    private static func writeCommand(for provider: UsageProvider, executable: String) throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("CodexLimits-Login-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(
            at: directory, withIntermediateDirectories: false,
            attributes: [.posixPermissions: 0o700]
        )
        let file = directory.appendingPathComponent("Sign in to \(provider.displayName).command")
        let script = """
        #!/bin/zsh -l
        /bin/rm -f -- "$0"
        /bin/rmdir -- \(shellQuote(directory.path))
        export PATH=\(shellQuote(URL(fileURLWithPath: executable).deletingLastPathComponent().path)):/opt/homebrew/bin:/usr/local/bin:$PATH
        cd -- \(shellQuote(FileManager.default.currentDirectoryPath)) || exit 1
        \(command(for: provider, executable: executable))
        login_result=$?
        if [ "$login_result" -eq 0 ]; then
          /usr/bin/open 'codexlimits://usage/\(provider.rawValue)'
        fi
        exit "$login_result"
        """
        try script.write(to: file, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: file.path)
        return file
    }

    private static func shellQuote(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    private enum LaunchError: LocalizedError {
        case cliNotFound(UsageProvider)
        case terminalUnavailable
        case couldNotOpenTerminal

        var errorDescription: String? {
            switch self {
            case let .cliNotFound(provider): "Install the \(provider.cliDisplayName) first, then try signing in again."
            case .terminalUnavailable: "Terminal could not be found. Sign in from your preferred terminal, then refresh usage."
            case .couldNotOpenTerminal: "Couldn’t open Terminal. Try again or sign in from your preferred terminal."
            }
        }
    }
}
