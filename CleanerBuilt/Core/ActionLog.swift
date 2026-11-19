import Foundation

nonisolated struct LogEntry: Codable, Sendable, Identifiable, Hashable {
    enum Outcome: String, Codable, Sendable {
        case trashed, deleted, skipped, failed
    }

    var id = UUID()
    var date = Date()
    let action: String
    let path: String
    let bytes: Int64
    let outcome: Outcome
    let detail: String
}

/// Append-only JSON-lines log of every action, in ~/Library/Logs/CleanerBuilt/.
nonisolated struct ActionLog: Sendable {
    let fileURL: URL

    static let live = ActionLog(fileURL: URL(fileURLWithPath: CleanupRules.expand("~/Library/Logs/CleanerBuilt/actions.jsonl")))

    /// Throws if the log can't be written. Cleaning refuses to start in that case.
    func prepare() throws {
        try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        if !FileManager.default.fileExists(atPath: fileURL.path) {
            try Data().write(to: fileURL)
        }
        try FileHandle(forWritingTo: fileURL).close()
    }

    func append(_ entry: LogEntry) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let handle = try FileHandle(forWritingTo: fileURL)
        defer { try? handle.close() }
        try handle.seekToEnd()
        try handle.write(contentsOf: try encoder.encode(entry) + Data("\n".utf8))
    }

    /// Newest first. Unreadable lines are ignored.
    // ponytail: reads the whole file; rotate or page it if the log ever gets huge.
    func read() -> [LogEntry] {
        guard let data = try? Data(contentsOf: fileURL) else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return data.split(separator: UInt8(ascii: "\n")).compactMap { try? decoder.decode(LogEntry.self, from: Data($0)) }.reversed()
    }
}
