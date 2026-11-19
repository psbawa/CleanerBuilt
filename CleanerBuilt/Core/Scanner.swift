import Foundation
import CoreServices

nonisolated struct ScanItem: Identifiable, Hashable, Sendable {
    let url: URL
    let ruleID: String
    let category: CleanupCategory
    let bytes: Int64
    /// Newest modification inside the item (or last-opened date for large files).
    let lastUsed: Date

    var id: String { url.path }
    var name: String { url.lastPathComponent }
}

nonisolated struct SkippedItem: Identifiable, Sendable {
    let path: String
    let category: CleanupCategory
    let reason: String
    var id: String { path }
}

nonisolated struct ScanResult: Sendable {
    var items: [ScanItem] = []
    var largeFiles: [ScanItem] = []
    var skipped: [SkippedItem] = []
    var errors: [String] = []
    var trashBytes: Int64 = 0
    var date = Date()
}

nonisolated struct ScanOptions: Sendable {
    var enabledRuleIDs: Set<String>
    var ageDays: Int
    /// Lowercased bundle IDs and names of running apps.
    var runningApps: Set<String>
    /// nil = take an `lsof` snapshot of the user's open files.
    var openPaths: Set<String>? = nil
    var now = Date()
}

/// Read-only. Measures what could be cleaned; never modifies anything.
nonisolated struct Scanner {
    var rules = CleanupRules.rules
    var pathGuard = PathGuard.live
    var trashPath: String? = CleanupRules.expand(CleanupRules.trash)

    private static let keys: Set<URLResourceKey> = [.totalFileAllocatedSizeKey, .contentModificationDateKey, .isSymbolicLinkKey, .isDirectoryKey]
    private static let datalessFlag: UInt32 = 0x4000_0000 // SF_DATALESS: iCloud placeholder, contents not on disk

    @concurrent
    func scan(_ options: ScanOptions, progress: @escaping @Sendable (Int, String) -> Void) async throws -> ScanResult {
        var result = ScanResult(date: options.now)
        var counter = Counter(report: progress)
        let open: Set<String>
        if let given = options.openPaths {
            open = given
        } else if let snapshot = OpenFiles.snapshot() {
            open = snapshot
        } else {
            open = []
            result.errors.append("Couldn't list open files (lsof failed), so files in use may not be detected.")
        }
        for rule in rules where options.enabledRuleIDs.contains(rule.id) {
            try Task.checkCancellation()
            switch rule.unit {
            case .eachChild:
                try scanChildren(rule, options, open: open, into: &result, counter: &counter)
            case let .reviewOnly(minBytes, unusedDays):
                try scanLargeFiles(rule, minBytes: minBytes, unusedSince: options.now.addingTimeInterval(-Double(unusedDays) * 86_400), into: &result, counter: &counter)
            case .tool(let kind):
                try scanTool(rule, kind, now: options.now, into: &result, counter: &counter)
            }
        }
        if let trashPath {
            var ignored: [String] = []
            result.trashBytes = try measure(URL(fileURLWithPath: trashPath), open: [], counter: &counter, errors: &ignored).bytes
        }
        return result
    }

    private func scanChildren(_ rule: Rule, _ options: ScanOptions, open: Set<String>,
                              into result: inout ScanResult, counter: inout Counter) throws {
        let children: [URL]
        do {
            children = try candidates(rule)
        } catch {
            result.errors.append("\(rule.rootPath): \(error.localizedDescription)")
            return
        }
        let kept = Set(children.prefix(rule.keepNewest ?? 0).map(\.lastPathComponent))
        for child in children {
            try Task.checkCancellation()
            switch try check(child, rule: rule, kept: kept, options: options, open: open, counter: &counter, errors: &result.errors) {
            case .ok(let m):
                result.items.append(ScanItem(url: child, ruleID: rule.id, category: rule.category, bytes: m.bytes, lastUsed: m.newest))
            case .skip(let reason):
                result.skipped.append(SkippedItem(path: child.path, category: rule.category, reason: reason))
            }
        }
    }

    /// Non-excluded children of a rule's root (real path), highest version name first. Empty if the root doesn't exist.
    func candidates(_ rule: Rule) throws -> [URL] {
        guard let root = PathGuard.realPath(rule.rootPath) else { return [] }
        return try FileManager.default.contentsOfDirectory(at: URL(fileURLWithPath: root, isDirectory: true), includingPropertiesForKeys: nil)
            .filter { !Self.isExcluded($0.lastPathComponent, by: rule) }
            .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedDescending }
    }

    static func isExcluded(_ name: String, by rule: Rule) -> Bool {
        if let include = rule.includeNames, !include.contains(name) { return true }
        return rule.excludeNames.contains { fnmatch($0, name, 0) == 0 }
    }

    /// One item per installed tool that has something to clean; size is the tool's own estimate.
    private func scanTool(_ rule: Rule, _ kind: ToolKind, now: Date, into result: inout ScanResult, counter: inout Counter) throws {
        guard let exe = ToolRunner.executable(kind) else { return } // not installed
        let bytes: Int64
        switch kind {
        case .brewCleanup:
            guard let estimate = ToolRunner.brewEstimate(exe) else { return }
            bytes = estimate
        case .simctlDeleteUnavailable:
            let paths = ToolRunner.unavailableSimulatorPaths()
            guard !paths.isEmpty else { return }
            var ignored: [String] = []
            bytes = try paths.reduce(0) { $0 + (try measure(URL(fileURLWithPath: $1), open: [], counter: &counter, errors: &ignored).bytes) }
        }
        result.items.append(ScanItem(url: URL(fileURLWithPath: exe), ruleID: rule.id, category: rule.category, bytes: bytes, lastUsed: now))
    }

    enum Verdict {
        case ok(Measure)
        case skip(String)
    }

    /// Every per-item safety check. Runs at scan time AND again in Cleaner right before trashing.
    func check(_ child: URL, rule: Rule, kept: Set<String>, options: ScanOptions, open: Set<String>,
               counter: inout Counter, errors: inout [String]) throws -> Verdict {
        let name = child.lastPathComponent
        if Self.isExcluded(name, by: rule) { return .skip("Excluded by rule") }
        if kept.contains(name), let keep = rule.keepNewest { return .skip("Newest \(keep) versions are kept") }
        if let owner = rule.ownerBundleIDs.first(where: { options.runningApps.contains($0.lowercased()) }) { return .skip("\(owner) is running") }
        if pathGuard.validate(child) == nil { return .skip("Symlink, protected, or outside allowed folders") }
        if Self.isRunning(name, in: options.runningApps) { return .skip("App is running") }
        let m = try measure(child, open: open, counter: &counter, errors: &errors)
        if m.unreadable { return .skip("Couldn't read everything inside") }
        if m.dataless { return .skip("Contains iCloud placeholders") }
        if m.inUse { return .skip("Open in another app") }
        let cutoff = options.now.addingTimeInterval(-Double(options.ageDays) * 86_400)
        if rule.ageFiltered, m.newest > cutoff { return .skip("Used in the last \(options.ageDays) days") }
        return .ok(m)
    }

    // ponytail: name-based match (folder == bundle ID / app name, or bundle ID + "."); folders named otherwise
    // aren't linked to their app, the age threshold is the backstop. Per-rule ownerBundleIDs if that matters.
    static func isRunning(_ name: String, in running: Set<String>) -> Bool {
        let n = name.lowercased()
        return running.contains(n) || running.contains { n.hasPrefix($0 + ".") }
    }

    private func scanLargeFiles(_ rule: Rule, minBytes: Int64, unusedSince cutoff: Date,
                                into result: inout ScanResult, counter: inout Counter) throws {
        guard let root = PathGuard.realPath(rule.rootPath) else { return }
        let keys: [URLResourceKey] = [.isRegularFileKey, .isSymbolicLinkKey, .totalFileAllocatedSizeKey, .contentModificationDateKey, .addedToDirectoryDateKey]
        guard let e = FileManager.default.enumerator(at: URL(fileURLWithPath: root), includingPropertiesForKeys: keys, options: [.skipsPackageDescendants]) else { return }
        for case let url as URL in e {
            counter.tick(url.path)
            if counter.count % 1000 == 0 { try Task.checkCancellation() }
            guard let v = try? url.resourceValues(forKeys: Set(keys)), v.isRegularFile == true, v.isSymbolicLink != true else { continue }
            let size = Int64(v.totalFileAllocatedSize ?? 0) // 0 for iCloud placeholders, so they never show
            guard size >= minBytes else { continue }
            let used = Self.lastOpened(url) ?? max(v.contentModificationDate ?? .distantPast, v.addedToDirectoryDate ?? .distantPast)
            guard used < cutoff else { continue }
            result.largeFiles.append(ScanItem(url: url, ruleID: rule.id, category: rule.category, bytes: size, lastUsed: used))
        }
    }

    private static func lastOpened(_ url: URL) -> Date? {
        guard let item = MDItemCreateWithURL(nil, url as CFURL) else { return nil }
        return MDItemCopyAttribute(item, kMDItemLastUsedDate) as? Date
    }

    struct Measure {
        var bytes: Int64 = 0
        var newest = Date.distantPast
        var dataless = false
        var inUse = false
        var unreadable = false
    }

    /// Sums allocated size and finds the newest modification; never follows symlinks.
    func measure(_ url: URL, open: Set<String>, counter: inout Counter, errors: inout [String]) throws -> Measure {
        var m = Measure()
        func add(_ u: URL) -> Bool {
            guard let v = try? u.resourceValues(forKeys: Self.keys), v.isSymbolicLink != true else { return false }
            m.bytes += Int64(v.totalFileAllocatedSize ?? 0)
            if let d = v.contentModificationDate, d > m.newest { m.newest = d }
            var st = stat()
            if lstat(u.path, &st) == 0, st.st_flags & Self.datalessFlag != 0 { m.dataless = true }
            if open.contains(u.path) { m.inUse = true }
            return v.isDirectory == true
        }
        guard add(url) else { return m }
        var enumErrors: [String] = []
        let e = FileManager.default.enumerator(at: url, includingPropertiesForKeys: Array(Self.keys), options: []) { u, error in
            enumErrors.append("\(u.path): \(error.localizedDescription)")
            return true
        }
        while let u = e?.nextObject() as? URL {
            _ = add(u)
            counter.tick(u.path)
            if counter.count % 1000 == 0 { try Task.checkCancellation() }
        }
        m.unreadable = !enumErrors.isEmpty // can't verify age / in-use for what we can't see
        errors += enumErrors
        return m
    }

    struct Counter {
        let report: @Sendable (Int, String) -> Void
        var count = 0
        mutating func tick(_ path: String) {
            count += 1
            if count % 2000 == 0 { report(count, path) }
        }
    }
}
