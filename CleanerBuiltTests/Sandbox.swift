import Foundation

/// A throwaway folder under the system temp dir. Tests never touch real user folders.
struct Sandbox {
    let base: URL

    init() throws {
        base = FileManager.default.temporaryDirectory
            .appendingPathComponent("CleanerBuiltTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
    }

    func remove() { try? FileManager.default.removeItem(at: base) }

    func url(_ relative: String) -> URL { base.appendingPathComponent(relative) }

    /// Creates a file (and its parent folders) and returns it.
    @discardableResult
    func file(_ relative: String, contents: String = "x", age days: Double = 0) throws -> URL {
        let u = url(relative)
        try FileManager.default.createDirectory(at: u.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(contents.utf8).write(to: u)
        try setAge(u, days: days)
        return u
    }

    @discardableResult
    func dir(_ relative: String) throws -> URL {
        let u = url(relative)
        try FileManager.default.createDirectory(at: u, withIntermediateDirectories: true)
        return u
    }

    func symlink(_ relative: String, to target: URL) throws {
        try FileManager.default.createSymbolicLink(at: url(relative), withDestinationURL: target)
    }

    /// Back-dates an item and everything inside it (children first, so folder dates stick).
    func setAge(_ u: URL, days: Double) throws {
        let date = Date().addingTimeInterval(-days * 86_400)
        if let e = FileManager.default.enumerator(at: u, includingPropertiesForKeys: nil) {
            for case let child as URL in e.allObjects.reversed() {
                try FileManager.default.setAttributes([.modificationDate: date], ofItemAtPath: child.path)
            }
        }
        try FileManager.default.setAttributes([.modificationDate: date], ofItemAtPath: u.path)
    }
}
