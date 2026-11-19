import Foundation
import Testing
@testable import CleanerBuilt

struct CleanerTests {
    private struct Env {
        let sb: Sandbox
        let root: URL
        let rule: Rule
        var cleaner: Cleaner
        var log: ActionLog { cleaner.log }
        var fakeTrash: URL { sb.url("FakeTrash") }

        init(_ sb: Sandbox, deny: [String] = [], rule makeRule: (String) -> Rule = { Rule(id: "t", category: .userCaches, title: "t", root: $0, explanation: "") }) throws {
            self.sb = sb
            root = try sb.dir("root")
            rule = makeRule(root.path)
            let fakeTrash = try sb.dir("FakeTrash")
            cleaner = Cleaner(
                scanner: Scanner(rules: [rule], pathGuard: PathGuard(deny: deny, roots: [root.path]), trashPath: nil),
                rules: [rule],
                log: ActionLog(fileURL: sb.url("logs/actions.jsonl")),
                trashPath: sb.url("Trash").path,
                trash: { url in
                    let dest = fakeTrash.appendingPathComponent(url.lastPathComponent)
                    try FileManager.default.moveItem(at: url, to: dest)
                    return dest
                }
            )
        }

        func item(_ relative: String, ruleID: String? = nil, category: CleanupCategory = .userCaches) -> ScanItem {
            ScanItem(url: sb.url(relative), ruleID: ruleID ?? rule.id, category: category, bytes: 1, lastUsed: .distantPast)
        }

        /// An old folder with one file, ready to be cleaned.
        @discardableResult
        func oldFolder(_ relative: String) throws -> URL {
            try sb.file("\(relative)/data")
            try sb.setAge(sb.url(relative), days: 30)
            return sb.url(relative)
        }

        func clean(_ items: [ScanItem], running: Set<String> = [], open: Set<String> = []) async -> [LogEntry] {
            await cleaner.moveToTrash(items, options: ScanOptions(enabledRuleIDs: [], ageDays: 7, runningApps: running, openPaths: open)) { _ in }
        }
    }

    private func exists(_ u: URL) -> Bool {
        var st = stat()
        return lstat(u.path, &st) == 0
    }

    @Test func movesOldItemToTrashAndLogsIt() async throws {
        let sb = try Sandbox(); defer { sb.remove() }
        let env = try Env(sb)
        let folder = try env.oldFolder("root/com.example.app")
        let entries = await env.clean([env.item("root/com.example.app")])
        #expect(entries.map(\.outcome) == [.trashed])
        #expect(!exists(folder))
        #expect(exists(env.fakeTrash.appendingPathComponent("com.example.app/data")))
        let logged = env.log.read()
        #expect(logged.count == 1)
        #expect(logged.first?.path == folder.path)
        #expect(logged.first?.outcome == .trashed)
        #expect((logged.first?.bytes ?? 0) > 0)
    }

    @Test func itemModifiedSinceScanIsSkipped() async throws {
        let sb = try Sandbox(); defer { sb.remove() }
        let env = try Env(sb)
        let folder = try env.oldFolder("root/app")
        try sb.file("root/app/new-since-scan")
        let entries = await env.clean([env.item("root/app")])
        #expect(entries.map(\.outcome) == [.skipped])
        #expect(exists(folder))
    }

    @Test func itemSwappedForSymlinkAfterScanIsSkipped() async throws {
        let sb = try Sandbox(); defer { sb.remove() }
        let env = try Env(sb)
        try env.oldFolder("outside")
        try FileManager.default.createDirectory(at: env.root, withIntermediateDirectories: true)
        try sb.symlink("root/app", to: sb.url("outside"))
        let entries = await env.clean([env.item("root/app")])
        #expect(entries.map(\.outcome) == [.skipped])
        #expect(exists(sb.url("outside/data")))
        #expect(exists(sb.url("root/app")))
    }

    @Test func traversalOutOfRootIsRefused() async throws {
        let sb = try Sandbox(); defer { sb.remove() }
        let env = try Env(sb)
        let outside = try env.oldFolder("outside")
        let sneaky = ScanItem(url: URL(fileURLWithPath: env.root.path + "/../outside"), ruleID: "t", category: .userCaches, bytes: 1, lastUsed: .distantPast)
        let entries = await env.clean([sneaky])
        #expect(entries.map(\.outcome) == [.skipped])
        #expect(exists(outside))
    }

    @Test func nestedPathIsRefused() async throws {
        let sb = try Sandbox(); defer { sb.remove() }
        let env = try Env(sb)
        let inner = try env.oldFolder("root/app/inner")
        try sb.setAge(sb.url("root/app"), days: 30)
        let entries = await env.clean([env.item("root/app/inner")])
        #expect(entries.first?.detail == "Not directly inside its cleanup folder")
        #expect(exists(inner))
    }

    @Test func unknownRuleOrWrongCategoryIsRefused() async throws {
        let sb = try Sandbox(); defer { sb.remove() }
        let env = try Env(sb)
        let folder = try env.oldFolder("root/app")
        let entries = await env.clean([env.item("root/app", ruleID: "nope"), env.item("root/app", category: .xcode)])
        #expect(entries.map(\.outcome) == [.skipped, .skipped])
        #expect(exists(folder))
    }

    @Test func reviewOnlyItemsAreNeverMoved() async throws {
        let sb = try Sandbox(); defer { sb.remove() }
        let env = try Env(sb) { Rule(id: "big", category: .largeFiles, title: "t", root: $0, unit: .reviewOnly(minBytes: 0, unusedDays: 0), explanation: "") }
        let file = try sb.file("root/huge.iso", age: 400)
        let entries = await env.clean([ScanItem(url: file, ruleID: "big", category: .largeFiles, bytes: 1, lastUsed: .distantPast)])
        #expect(entries.map(\.outcome) == [.skipped])
        #expect(exists(file))
    }

    @Test func deniedPathIsRefusedAtCleanTime() async throws {
        let sb = try Sandbox(); defer { sb.remove() }
        let env = try Env(sb, deny: [sb.url("root/protected").path])
        let folder = try env.oldFolder("root/protected")
        let entries = await env.clean([env.item("root/protected")])
        #expect(entries.map(\.outcome) == [.skipped])
        #expect(exists(folder))
    }

    @Test func openFileIsRefusedAtCleanTime() async throws {
        let sb = try Sandbox(); defer { sb.remove() }
        let env = try Env(sb)
        let folder = try env.oldFolder("root/app")
        let entries = await env.clean([env.item("root/app")], open: [PathGuard.realPath(sb.url("root/app/data").path)!])
        #expect(entries.first?.detail == "Open in another app")
        #expect(exists(folder))
    }

    @Test func appThatStartedRunningIsRefused() async throws {
        let sb = try Sandbox(); defer { sb.remove() }
        let env = try Env(sb)
        let folder = try env.oldFolder("root/com.example.app")
        let entries = await env.clean([env.item("root/com.example.app")], running: ["com.example.app"])
        #expect(entries.first?.detail == "App is running")
        #expect(exists(folder))
    }

    @Test func newestVersionsAreKeptAtCleanTime() async throws {
        let sb = try Sandbox(); defer { sb.remove() }
        let env = try Env(sb) { Rule(id: "t", category: .xcode, title: "t", root: $0, ageFiltered: false, keepNewest: 2, explanation: "") }
        for v in ["15.0", "16.0", "17.0"] { try sb.file("root/\(v)/sym") }
        let entries = await env.clean(["15.0", "16.0", "17.0"].map { env.item("root/\($0)", category: .xcode) })
        #expect(entries.map(\.outcome) == [.trashed, .skipped, .skipped])
        #expect(exists(sb.url("root/16.0")) && exists(sb.url("root/17.0")))
    }

    @Test func oneFailureDoesNotStopTheRest() async throws {
        let sb = try Sandbox(); defer { sb.remove() }
        var env = try Env(sb)
        for n in ["a", "b", "c"] { try env.oldFolder("root/\(n)") }
        let fakeTrash = env.fakeTrash
        env.cleaner.trash = { url in
            if url.lastPathComponent == "b" { throw CocoaError(.fileWriteNoPermission) }
            let dest = fakeTrash.appendingPathComponent(url.lastPathComponent)
            try FileManager.default.moveItem(at: url, to: dest)
            return dest
        }
        let entries = await env.clean(["a", "b", "c"].map { env.item("root/\($0)") })
        #expect(entries.map(\.outcome) == [.trashed, .failed, .trashed])
        #expect(env.log.read().count == 3)
        #expect(exists(sb.url("root/b")))
    }

    @Test func unwritableLogMeansNothingMoves() async throws {
        let sb = try Sandbox(); defer { sb.remove() }
        var env = try Env(sb)
        try sb.file("not-a-folder")
        env.cleaner.log = ActionLog(fileURL: sb.url("not-a-folder/actions.jsonl"))
        let folder = try env.oldFolder("root/app")
        let entries = await env.clean([env.item("root/app")])
        #expect(entries.map(\.outcome) == [.skipped])
        #expect(exists(folder))
    }

    @Test func emptyTrashErasesTrashButNeverFollowsSymlinks() async throws {
        let sb = try Sandbox(); defer { sb.remove() }
        let env = try Env(sb)
        let precious = try sb.file("outside/precious.txt")
        try sb.file("Trash/old.txt")
        try sb.file("Trash/folder/inner.txt")
        try sb.symlink("Trash/link-to-outside", to: sb.url("outside"))
        let entries = await env.cleaner.emptyTrash()
        #expect(Set(entries.map(\.outcome)) == [.deleted])
        #expect(entries.count == 3)
        #expect(try FileManager.default.contentsOfDirectory(atPath: sb.url("Trash").path).isEmpty)
        #expect(exists(precious))
        #expect(env.log.read().count == 3)
    }
}

struct Phase5Tests {
    @Test func includeNamesLimitsScanToNamedChild() async throws {
        let sb = try Sandbox(); defer { sb.remove() }
        let root = try sb.dir("root")
        for n in ["_cacache", "_logs", "other"] {
            try sb.file("root/\(n)/x")
            try sb.setAge(sb.url("root/\(n)"), days: 30)
        }
        let rule = Rule(id: "npm", category: .devCaches, title: "t", root: root.path, includeNames: ["_cacache"], explanation: "")
        let scanner = Scanner(rules: [rule], pathGuard: PathGuard(deny: [], roots: [root.path]), trashPath: nil)
        let r = try await scanner.scan(ScanOptions(enabledRuleIDs: ["npm"], ageDays: 7, runningApps: [], openPaths: [])) { _, _ in }
        #expect(r.items.map(\.name) == ["_cacache"])
        #expect(r.skipped.isEmpty) // non-included siblings are not even listed
    }

    @Test func cleanerRefusesSiblingOfIncludedFolder() async throws {
        let sb = try Sandbox(); defer { sb.remove() }
        let root = try sb.dir("root")
        try sb.file("root/other/x")
        try sb.setAge(sb.url("root/other"), days: 30)
        let rule = Rule(id: "npm", category: .devCaches, title: "t", root: root.path, includeNames: ["_cacache"], explanation: "")
        let cleaner = Cleaner(scanner: Scanner(rules: [rule], pathGuard: PathGuard(deny: [], roots: [root.path]), trashPath: nil),
                              rules: [rule], log: ActionLog(fileURL: sb.url("log.jsonl")), trashPath: sb.url("Trash").path,
                              trash: { _ in Issue.record("must not trash"); return nil })
        let item = ScanItem(url: sb.url("root/other"), ruleID: "npm", category: .devCaches, bytes: 1, lastUsed: .distantPast)
        let entries = await cleaner.moveToTrash([item], options: ScanOptions(enabledRuleIDs: [], ageDays: 7, runningApps: [], openPaths: [])) { _ in }
        #expect(entries.first?.detail == "Excluded by rule")
    }

    @Test func toolItemWithUnexpectedPathIsNeverRun() async throws {
        let sb = try Sandbox(); defer { sb.remove() }
        let brew = try #require(CleanupRules.rule("brew"))
        let fake = try sb.file("evil/brew")
        let cleaner = Cleaner(rules: [brew], log: ActionLog(fileURL: sb.url("log.jsonl")), trashPath: sb.url("Trash").path,
                              trash: { _ in Issue.record("must not trash"); return nil })
        let item = ScanItem(url: fake, ruleID: "brew", category: .devCaches, bytes: 1, lastUsed: .distantPast)
        let entries = await cleaner.moveToTrash([item], options: ScanOptions(enabledRuleIDs: [], ageDays: 7, runningApps: [], openPaths: [])) { _ in }
        #expect(entries.map(\.outcome) == [.skipped])
    }

    @Test func parsesBrewEstimate() {
        #expect(ToolRunner.parseBrewSize("==> This operation would free approximately 1.5GB of disk space.") == Int64(1.5 * 1_073_741_824))
        #expect(ToolRunner.parseBrewSize("would free approximately 312.4KB of disk space") == Int64(312.4 * 1024))
        #expect(ToolRunner.parseBrewSize("Nothing to clean") == nil)
    }

    @Test func toolsArePermanentSoTheyAreOptIn() {
        for rule in CleanupRules.rules {
            guard case .tool = rule.unit else { continue }
            #expect(!rule.defaultOn, "\(rule.id)")
        }
    }

    @Test func browserRulesStayInsideCachesFolder() {
        let caches = CleanupRules.expand("~/Library/Caches")
        for rule in CleanupRules.rules where rule.category == .browserCaches {
            #expect(rule.rootPath == caches || rule.rootPath.hasPrefix(caches + "/"), "\(rule.id)")
        }
    }

    @Test func toolRulesAddNoAllowedRoots() {
        #expect(!PathGuard.live.roots.contains(""))
        #expect(Set(PathGuard.live.roots) == Set(CleanupRules.rules.filter(\.movesToTrash).compactMap { PathGuard.realPath($0.rootPath)?.lowercased() }))
    }
}
