import Foundation

actor SessionActivityReader {
    struct Snapshot: Sendable {
        let events: [ModelActivityEvent]
        let filesRead: Int
        let issueCount: Int
        let folderExists: Bool
    }

    private struct CachedFile {
        let size: Int
        let modified: Date
        let events: [ModelActivityEvent]
        let issues: Int
    }

    private var cache: [URL: CachedFile] = [:]

    func load(home: URL, since: Date) throws -> Snapshot {
        let manager = FileManager.default
        var events: [String: ModelActivityEvent] = [:]
        var visited: Set<URL> = []
        var issues = 0
        var folderExists = false
        let keys: [URLResourceKey] = [.contentModificationDateKey, .fileSizeKey, .isRegularFileKey, .isSymbolicLinkKey]
        for folder in ["sessions", "archived_sessions"] {
            let root = home.appendingPathComponent(folder, isDirectory: true)
            guard manager.fileExists(atPath: root.path) else { continue }
            folderExists = true
            guard let enumerator = manager.enumerator(at: root, includingPropertiesForKeys: keys,
                options: [.skipsHiddenFiles], errorHandler: { _, _ in issues += 1; return true }) else {
                issues += 1
                continue
            }
            for case let url as URL in enumerator {
                try Task.checkCancellation()
                guard url.pathExtension == "jsonl" else { continue }
                do {
                    let attributes = try url.resourceValues(forKeys: Set(keys))
                    guard attributes.isRegularFile == true, attributes.isSymbolicLink != true,
                          let modified = attributes.contentModificationDate, modified >= since,
                          let size = attributes.fileSize else { continue }
                    visited.insert(url)
                    let file: CachedFile
                    if let known = cache[url], known.size == size, known.modified == modified {
                        file = known
                    } else {
                        file = try read(url, size: size, modified: modified)
                        cache[url] = file
                    }
                    issues += file.issues
                    for event in file.events where event.date >= since {
                        events[event.id] = event
                    }
                } catch is CancellationError { throw CancellationError() }
                catch { issues += 1 }
            }
        }
        cache = cache.filter { visited.contains($0.key) }
        return Snapshot(events: events.values.sorted { $0.date < $1.date }, filesRead: visited.count,
                        issueCount: issues, folderExists: folderExists)
    }

    private func read(_ url: URL, size: Int, modified: Date) throws -> CachedFile {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var parser = SessionActivityParser(sessionID: url.lastPathComponent)
        var buffer = Data()
        var skippingLongLine = false
        var events: [ModelActivityEvent] = []
        let newline = Data([10])
        while let chunk = try handle.read(upToCount: 65_536), !chunk.isEmpty {
            try Task.checkCancellation()
            let previousCount = buffer.count
            buffer.append(chunk)
            var lineStart = buffer.startIndex
            var searchStart = buffer.startIndex + previousCount
            // Search each byte once, and discard consumed bytes once per chunk.
            // Re-scanning long tool-output lines made large histories expensive.
            while let boundary = buffer.range(of: newline, in: searchStart ..< buffer.endIndex) {
                if !skippingLongLine, let event = parser.consume(Data(buffer[lineStart ..< boundary.lowerBound])) {
                    events.append(event)
                }
                lineStart = boundary.upperBound
                searchStart = lineStart
                skippingLongLine = false
            }
            buffer.removeSubrange(buffer.startIndex ..< lineStart)
            if buffer.count > 2_000_000 {
                if !skippingLongLine, SessionActivityParser.hasRelevantPrefix(buffer) { parser.skipRelevantRecord() }
                buffer.removeAll(keepingCapacity: false)
                skippingLongLine = true
            }
        }
        // An unfinished last line is retried when the live file changes.
        return CachedFile(size: size, modified: modified, events: events, issues: parser.invalidRecords)
    }
}
