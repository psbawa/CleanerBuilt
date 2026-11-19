import Foundation

/// Decides whether a path may be touched. Used at scan time and (phase d) again right before trashing.
nonisolated struct PathGuard: Sendable {
    /// Lowercased fnmatch patterns, both as written and with symlinks resolved.
    let deny: [String]
    /// Lowercased real paths of allowed roots.
    let roots: [String]

    static let live = PathGuard(
        deny: CleanupRules.deny.map(CleanupRules.expand),
        roots: CleanupRules.rules.filter(\.movesToTrash).map(\.rootPath)
    )

    init(deny: [String], roots: [String]) {
        self.deny = Array(Set(deny.flatMap { [$0, Self.resolvePattern($0)] }.map { $0.lowercased() }))
        self.roots = roots.compactMap(Self.realPath).map { $0.lowercased() }
    }

    /// Returns the resolved real path if `url` may be touched, otherwise nil.
    /// Rejects: symlinks themselves, anything denied (before or after resolving), anything not strictly inside a root.
    func validate(_ url: URL) -> String? {
        var st = stat()
        guard lstat(url.path, &st) == 0, (st.st_mode & S_IFMT) != S_IFLNK else { return nil }
        guard let real = Self.realPath(url.path) else { return nil }
        guard !isDenied(url.standardizedFileURL.path), !isDenied(real) else { return nil }
        let lower = real.lowercased()
        guard roots.contains(where: { lower.hasPrefix($0 + "/") }) else { return nil }
        return real
    }

    func isDenied(_ path: String) -> Bool {
        let p = path.lowercased() // APFS is case-insensitive by default; over-matching only denies more.
        return deny.contains { fnmatch($0, p, 0) == 0 || fnmatch($0 + "/*", p, 0) == 0 }
    }

    static func realPath(_ path: String) -> String? {
        guard let r = realpath(path, nil) else { return nil }
        defer { free(r) }
        return String(cString: r)
    }

    /// Resolves symlinks in the part of a pattern before its first "*".
    private static func resolvePattern(_ pattern: String) -> String {
        guard let star = pattern.firstIndex(of: "*") else { return realPath(pattern) ?? pattern }
        guard let slash = pattern[..<star].lastIndex(of: "/"),
              let dir = realPath(String(pattern[..<slash])) else { return pattern }
        return dir + pattern[slash...]
    }
}
