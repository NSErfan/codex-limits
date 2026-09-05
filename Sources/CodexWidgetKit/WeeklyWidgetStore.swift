import Foundation

public struct WeeklyWidgetStore: Sendable {
    public enum Writer: String, Sendable { case app, collector }

    public static let percentageKind = "CodexWeeklyPercentage"
    public static let graphKind = "CodexWeeklyGraph"
    public let directory: URL

    public init(directory: URL) {
        self.directory = directory
    }

    /// The signing/build script injects the identical group into both bundles.
    /// An ad-hoc build has no authorized group and deliberately returns nil.
    public static func shared(bundle: Bundle = .main) -> Self? {
        guard let group = bundle.object(forInfoDictionaryKey: "CodexWidgetAppGroup") as? String,
              !group.isEmpty,
              let container = FileManager.default.containerURL(
                forSecurityApplicationGroupIdentifier: group
              ) else { return nil }
        return Self(directory: container.appendingPathComponent("WeeklyWidget", isDirectory: true))
    }

    public func read() -> WeeklyWidgetSnapshot? {
        let records = readRecords()
        return records.max { $0.fetchedAt < $1.fetchedAt }?.merging(records)
    }

    public func readAccent() -> UsageAccent {
        let url = directory.appendingPathComponent("appearance.json")
        guard let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize,
              size <= 4_096,
              let data = try? Data(contentsOf: url),
              let accent = try? JSONDecoder().decode(UsageAccent.self, from: data),
              accent.isValid else { return .automatic }
        return accent
    }

    public func writeAccent(_ accent: UsageAccent) throws {
        guard accent.isValid else {
            throw CocoaError(.coderInvalidValue)
        }
        // Appearance is owned by the app, independently of usage timestamps.
        // A later background collection must never overwrite the user's choice.
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try JSONEncoder().encode(accent).write(
            to: directory.appendingPathComponent("appearance.json"), options: .atomic
        )
    }

    public func write(_ snapshot: WeeklyWidgetSnapshot, writer: Writer) throws {
        // Each process owns its file. Atomic replacement prevents partial reads;
        // separate files prevent an older concurrent fetch overwriting a newer one.
        let records = readRecords()
        let ownURL = file(for: writer)
        if let own = readRecord(at: ownURL), own.fetchedAt > snapshot.fetchedAt { return }
        let merged = snapshot.merging(records)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try JSONEncoder().encode(merged).write(to: ownURL, options: .atomic)
    }

    private func readRecords() -> [WeeklyWidgetSnapshot] {
        [Writer.app, .collector].compactMap { readRecord(at: file(for: $0)) }
    }

    private func file(for writer: Writer) -> URL {
        directory.appendingPathComponent("\(writer.rawValue).json")
    }

    private func readRecord(at url: URL) -> WeeklyWidgetSnapshot? {
        guard let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize,
              size <= 1_000_000,
              let data = try? Data(contentsOf: url),
              let record = try? JSONDecoder().decode(WeeklyWidgetSnapshot.self, from: data),
              record.version == 1 else { return nil }
        return record
    }
}
