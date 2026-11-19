import Foundation

/// The only code that removes anything. Everything goes to the Trash, except the explicit Empty Trash action.
nonisolated struct Cleaner {
    var scanner = Scanner()
    var rules = CleanupRules.rules
    var log = ActionLog.live
    var trashPath = CleanupRules.expand(CleanupRules.trash)
    /// Moves an item to the Trash and returns where it ended up. Injected in tests so they never touch the real Trash.
    var trash: @Sendable (URL) throws -> URL? = { url in
        var out: NSURL?
        try FileManager.default.trashItem(at: url, resultingItemURL: &out)
        return out as URL?
    }

    static let moveAction = "Move to Trash"
    static let emptyAction = "Empty Trash"

    /// `options` must be fresh (now, running apps). Stops between items when cancelled; returns one entry per item handled.
    @concurrent
    func moveToTrash(_ items: [ScanItem], options: ScanOptions, progress: @escaping @Sendable (Int) -> Void) async -> [LogEntry] {
        func refuseAll(_ reason: String) -> [LogEntry] {
            items.map { LogEntry(action: Self.moveAction, path: $0.url.path, bytes: $0.bytes, outcome: .skipped, detail: reason) }
        }
        do { try log.prepare() } catch {
            return refuseAll("Nothing was moved: the action log couldn't be written (\(error.localizedDescription)).")
        }
        guard let open = options.openPaths ?? OpenFiles.snapshot() else {
            return record(refuseAll("Nothing was moved: couldn't check which files are open."))
        }
        var entries: [LogEntry] = []
        for (index, item) in items.enumerated() {
            if Task.isCancelled { break }
            entries += record([cleanOne(item, options: options, open: open)])
            progress(index + 1)
        }
        return entries
    }

    private func cleanOne(_ item: ScanItem, options: ScanOptions, open: Set<String>) -> LogEntry {
        func entry(_ outcome: LogEntry.Outcome, _ detail: String, bytes: Int64? = nil) -> LogEntry {
            LogEntry(action: Self.moveAction, path: item.url.path, bytes: bytes ?? item.bytes, outcome: outcome, detail: detail)
        }
        // Final safety check: re-validate everything, don't trust the scan.
        guard let rule = rules.first(where: { $0.id == item.ruleID }), rule.category == item.category else {
            return entry(.skipped, "No matching cleanup rule")
        }
        if case .tool(let kind) = rule.unit {
            return runTool(kind, item: item, entry: entry)
        }
        guard rule.movesToTrash else { return entry(.skipped, "Review-only items are never removed") }
        guard let real = scanner.pathGuard.validate(item.url) else {
            return entry(.skipped, "Failed final safety check (symlink, protected, missing, or outside allowed folders)")
        }
        guard let root = PathGuard.realPath(rule.rootPath),
              (real as NSString).deletingLastPathComponent.lowercased() == root.lowercased() else {
            return entry(.skipped, "Not directly inside its cleanup folder")
        }
        var kept: Set<String> = []
        if let keep = rule.keepNewest {
            guard let children = try? scanner.candidates(rule) else { return entry(.skipped, "Couldn't list \(rule.title) to find the newest versions") }
            kept = Set(children.prefix(keep).map(\.lastPathComponent))
        }
        var counter = Scanner.Counter { _, _ in }
        var errors: [String] = []
        let verdict: Scanner.Verdict
        do {
            verdict = try scanner.check(URL(fileURLWithPath: real), rule: rule, kept: kept, options: options, open: open, counter: &counter, errors: &errors)
        } catch {
            return entry(.skipped, "Cancelled")
        }
        guard case .ok(let measure) = verdict else {
            if case .skip(let reason) = verdict { return entry(.skipped, reason) }
            return entry(.skipped, "Unknown")
        }
        // ponytail: a tiny window remains between this check and the move (TOCTOU); acceptable because the move is to the Trash.
        do {
            let moved = try trash(URL(fileURLWithPath: real))
            return entry(.trashed, "In the Trash as “\(moved?.lastPathComponent ?? item.name)”", bytes: measure.bytes)
        } catch {
            return entry(.failed, error.localizedDescription)
        }
    }

    /// PERMANENT, done by the tool itself. Only the exact installed executable found now is run, never a path from the scan.
    private func runTool(_ kind: ToolKind, item: ScanItem, entry: (LogEntry.Outcome, String, Int64?) -> LogEntry) -> LogEntry {
        guard let exe = ToolRunner.executable(kind), exe == item.url.path else {
            return entry(.skipped, "Tool not found where the scan saw it", nil)
        }
        let args = ToolRunner.cleanupArguments(kind)
        let command = ([(exe as NSString).lastPathComponent] + args).joined(separator: " ")
        guard let out = ToolRunner.run(exe, args) else { return entry(.failed, "Couldn't start `\(command)`", nil) }
        guard out.status == 0 else {
            return entry(.failed, "`\(command)` exited with \(out.status): \(out.text.suffix(300))", nil)
        }
        return entry(.deleted, "Ran `\(command)` (removed permanently by the tool)", nil)
    }

    /// PERMANENT. Erases everything in the user's Home Trash (~/.Trash).
    @concurrent
    func emptyTrash() async -> [LogEntry] {
        do { try log.prepare() } catch {
            return [LogEntry(action: Self.emptyAction, path: trashPath, bytes: 0, outcome: .skipped,
                             detail: "Nothing was erased: the action log couldn't be written (\(error.localizedDescription)).")]
        }
        guard let root = PathGuard.realPath(trashPath),
              let children = try? FileManager.default.contentsOfDirectory(at: URL(fileURLWithPath: root, isDirectory: true), includingPropertiesForKeys: nil)
        else { return [] }
        let trashGuard = PathGuard(deny: CleanupRules.deny.map(CleanupRules.expand), roots: [root])
        var entries: [LogEntry] = []
        for child in children {
            var st = stat()
            let isLink = lstat(child.path, &st) == 0 && (st.st_mode & S_IFMT) == S_IFLNK
            // A symlink in the Trash: only the link is erased (removeItem never follows it), never its target.
            let allowed = isLink ? child.deletingLastPathComponent().path == root : trashGuard.validate(child) != nil
            var counter = Scanner.Counter { _, _ in }
            var ignored: [String] = []
            let bytes = isLink ? 0 : ((try? scanner.measure(child, open: [], counter: &counter, errors: &ignored))?.bytes ?? 0)
            let entry: LogEntry
            if !allowed {
                entry = LogEntry(action: Self.emptyAction, path: child.path, bytes: bytes, outcome: .skipped, detail: "Failed safety check")
            } else {
                do {
                    try FileManager.default.removeItem(at: child)
                    entry = LogEntry(action: Self.emptyAction, path: child.path, bytes: bytes, outcome: .deleted, detail: "Erased permanently")
                } catch {
                    entry = LogEntry(action: Self.emptyAction, path: child.path, bytes: bytes, outcome: .failed, detail: error.localizedDescription)
                }
            }
            entries += record([entry])
        }
        return entries
    }

    /// Writes entries to the action log. A failed write is noted on the entry itself.
    private func record(_ entries: [LogEntry]) -> [LogEntry] {
        entries.map { e in
            do {
                try log.append(e)
                return e
            } catch {
                return LogEntry(id: e.id, date: e.date, action: e.action, path: e.path, bytes: e.bytes, outcome: e.outcome,
                                detail: e.detail + " (not written to log: \(error.localizedDescription))")
            }
        }
    }
}
