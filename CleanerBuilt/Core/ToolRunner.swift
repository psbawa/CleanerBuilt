import Foundation

/// Runs developer tools' own cleanup commands. Never with sudo.
nonisolated enum ToolRunner {
    struct Output {
        let status: Int32
        let text: String
    }

    /// nil if the process couldn't be launched.
    static func run(_ executable: String, _ arguments: [String]) -> Output? {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: executable)
        p.arguments = arguments
        var env = ProcessInfo.processInfo.environment
        env["PATH"] = "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin" // GUI apps get a minimal PATH
        env["HOMEBREW_NO_AUTO_UPDATE"] = "1"
        env["HOMEBREW_NO_ENV_HINTS"] = "1"
        p.environment = env
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = pipe
        do { try p.run() } catch { return nil }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        return Output(status: p.terminationStatus, text: String(decoding: data, as: UTF8.self))
    }

    /// The tool's executable, or nil if it isn't installed.
    static func executable(_ kind: ToolKind) -> String? {
        let fm = FileManager.default
        switch kind {
        case .brewCleanup:
            return ["/opt/homebrew/bin/brew", "/usr/local/bin/brew"].first(where: fm.isExecutableFile(atPath:))
        case .simctlDeleteUnavailable:
            guard fm.isExecutableFile(atPath: "/usr/bin/xcrun"), run("/usr/bin/xcrun", ["--find", "simctl"])?.status == 0 else { return nil }
            return "/usr/bin/xcrun"
        }
    }

    static func cleanupArguments(_ kind: ToolKind) -> [String] {
        switch kind {
        case .brewCleanup: ["cleanup"]
        case .simctlDeleteUnavailable: ["simctl", "delete", "unavailable"]
        }
    }

    /// Bytes Homebrew says `brew cleanup` would free, from `brew cleanup --dry-run`. nil if nothing to do.
    // ponytail: parses Homebrew's human-readable summary line; it's an estimate shown before you opt in.
    static func brewEstimate(_ brew: String) -> Int64? {
        guard let out = run(brew, ["cleanup", "--dry-run"]), out.status == 0 else { return nil }
        return parseBrewSize(out.text)
    }

    static func parseBrewSize(_ text: String) -> Int64? {
        guard let m = text.firstMatch(of: #/free approximately ([0-9.]+)\s*(B|KB|MB|GB|TB)/#) else { return nil }
        let units: [Substring: Double] = ["B": 1, "KB": 0x1p10, "MB": 0x1p20, "GB": 0x1p30, "TB": 0x1p40]
        guard let value = Double(m.1), let unit = units[m.2] else { return nil }
        return Int64(value * unit)
    }

    /// Data folders of simulators `simctl delete unavailable` would remove.
    static func unavailableSimulatorPaths() -> [String] {
        guard let out = run("/usr/bin/xcrun", ["simctl", "list", "devices", "unavailable", "-j"]), out.status == 0,
              let json = try? JSONSerialization.jsonObject(with: Data(out.text.utf8)) as? [String: Any],
              let devices = json["devices"] as? [String: [[String: Any]]]
        else { return [] }
        return devices.values.flatMap { $0 }.compactMap { $0["dataPath"] as? String }
    }
}

nonisolated enum OpenFiles {
    /// Paths currently open by the user's own processes (no sudo). nil if lsof failed.
    static func snapshot() -> Set<String>? {
        guard let out = ToolRunner.run("/usr/sbin/lsof", ["-nP", "-w", "-Fn", "-u", String(getuid())]), !out.text.isEmpty else { return nil }
        var paths = Set<String>()
        for line in out.text.split(separator: "\n") where line.hasPrefix("n/") {
            paths.insert(String(line.dropFirst()))
        }
        return paths
    }
}
