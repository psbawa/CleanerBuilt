import AppKit

nonisolated enum Permissions {
    /// Places only readable with Full Disk Access. The system TCC.db always exists; the rest are
    /// backups in case a macOS version moves it. Read-only: we only open or list, never modify.
    static let probes = [
        "/Library/Application Support/com.apple.TCC/TCC.db",
        NSHomeDirectory() + "/Library/Application Support/com.apple.TCC/TCC.db",
        NSHomeDirectory() + "/Library/Safari",
        NSHomeDirectory() + "/Library/Mail",
        NSHomeDirectory() + "/Library/Messages",
    ]

    static func hasFullDiskAccess(probes: [String] = probes) -> Bool {
        probes.contains { path in
            if let handle = FileHandle(forReadingAtPath: path) {
                try? handle.close()
                // A folder opens without FDA on some versions; listing it is the real test.
                var isDir: ObjCBool = false
                FileManager.default.fileExists(atPath: path, isDirectory: &isDir)
                return !isDir.boolValue || (try? FileManager.default.contentsOfDirectory(atPath: path)) != nil
            }
            return false
        }
    }

    static func openFullDiskAccessSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles") {
            NSWorkspace.shared.open(url)
        }
    }
}
