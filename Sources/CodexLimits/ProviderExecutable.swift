import CodexWidgetKit
import Foundation

enum ProviderExecutable {
    static func path(
        for provider: UsageProvider,
        environment: [String: String] = ProcessInfo.processInfo.environment,
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser,
        isExecutable: (String) -> Bool = FileManager.default.isExecutableFile(atPath:)
    ) -> String? {
        let directories = [
            homeDirectory.appendingPathComponent(".local/bin").path,
            "/opt/homebrew/bin",
            "/usr/local/bin",
            homeDirectory.appendingPathComponent(".npm-global/bin").path
        ] + (environment["PATH"] ?? "").split(separator: ":").map(String.init)
        return directories
            .filter { $0.hasPrefix("/") }
            .map { URL(fileURLWithPath: $0).appendingPathComponent(provider.rawValue).path }
            .first(where: isExecutable)
    }
}
