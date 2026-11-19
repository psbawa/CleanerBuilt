import AppKit

enum Permissions {
    /// TCC.db is only readable with Full Disk Access. We open it read-only and close it immediately; never modified.
    static func hasFullDiskAccess() -> Bool {
        let tcc = URL(fileURLWithPath: NSHomeDirectory())
            .appendingPathComponent("Library/Application Support/com.apple.TCC/TCC.db")
        guard let handle = try? FileHandle(forReadingFrom: tcc) else { return false }
        try? handle.close()
        return true
    }

    static func openFullDiskAccessSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles") {
            NSWorkspace.shared.open(url)
        }
    }
}
