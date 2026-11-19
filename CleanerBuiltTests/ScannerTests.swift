import Foundation
import Testing
@testable import CleanerBuilt

struct ScannerTests {
    /// Scans one rule rooted in the sandbox, with no lsof snapshot and no Trash.
    private func scan(_ sb: Sandbox, rule: (String) -> Rule, running: Set<String> = [], open: Set<String> = [], ageDays: Int = 7) async throws -> ScanResult {
        let root = try sb.dir("root")
        let r = rule(root.path)
        let scanner = Scanner(rules: [r], pathGuard: PathGuard(deny: [], roots: [root.path]), trashPath: nil)
        let options = ScanOptions(enabledRuleIDs: [r.id], ageDays: ageDays, runningApps: running, openPaths: open)
        return try await scanner.scan(options) { _, _ in }
    }

    private func cacheRule(_ root: String) -> Rule {
        Rule(id: "t", category: .userCaches, title: "t", root: root, explanation: "")
    }

    private func names(_ r: ScanResult) -> Set<String> { Set(r.items.map(\.name)) }

    // MARK: age

    @Test func onlyOldItemsAreIncluded() async throws {
        let sb = try Sandbox(); defer { sb.remove() }
        try sb.file("root/old.app/c", age: 30)
        try sb.file("root/new.app/c", age: 1)
        try sb.setAge(sb.url("root/old.app"), days: 30)
        let r = try await scan(sb, rule: cacheRule)
        #expect(names(r) == ["old.app"])
        #expect(r.skipped.contains { $0.path.hasSuffix("/new.app") })
    }

    @Test func oneFreshFileDeepInsideKeepsTheWholeFolder() async throws {
        let sb = try Sandbox(); defer { sb.remove() }
        try sb.file("root/app/a/b/c/old", age: 30)
        try sb.setAge(sb.url("root/app"), days: 30)
        try sb.file("root/app/a/b/c/fresh", age: 0)
        let r = try await scan(sb, rule: cacheRule)
        #expect(r.items.isEmpty)
    }

    @Test func thresholdIsConfigurable() async throws {
        let sb = try Sandbox(); defer { sb.remove() }
        try sb.file("root/app/c")
        try sb.setAge(sb.url("root/app"), days: 10)
        #expect(try await scan(sb, rule: cacheRule, ageDays: 7).items.count == 1)
        #expect(try await scan(sb, rule: cacheRule, ageDays: 14).items.isEmpty)
    }

    @Test func ageFilterCanBeTurnedOffPerRule() async throws {
        let sb = try Sandbox(); defer { sb.remove() }
        try sb.file("root/archive/c", age: 0)
        let r = try await scan(sb) { Rule(id: "t", category: .xcode, title: "t", root: $0, ageFiltered: false, explanation: "") }
        #expect(names(r) == ["archive"])
    }

    // MARK: running apps

    @Test func cacheOfRunningAppIsSkipped() async throws {
        let sb = try Sandbox(); defer { sb.remove() }
        for name in ["com.example.app", "com.example.app.helper", "Example", "com.other.app"] {
            try sb.file("root/\(name)/c")
            try sb.setAge(sb.url("root/\(name)"), days: 30)
        }
        let r = try await scan(sb, rule: cacheRule, running: ["com.example.app", "example"])
        #expect(names(r) == ["com.other.app"])
        #expect(r.skipped.filter { $0.reason == "App is running" }.count == 3)
    }

    @Test func runningMatchIsCaseInsensitive() {
        #expect(Scanner.isRunning("Com.Example.App", in: ["com.example.app"]))
        #expect(!Scanner.isRunning("com.example.application", in: ["com.example.app"]))
    }

    @Test func wholeRuleIsSkippedWhileOwnerRuns() async throws {
        let sb = try Sandbox(); defer { sb.remove() }
        try sb.file("root/Project-abc/c")
        try sb.setAge(sb.url("root/Project-abc"), days: 30)
        let rule: (String) -> Rule = { Rule(id: "t", category: .xcode, title: "t", root: $0, ownerBundleIDs: ["com.apple.dt.Xcode"], explanation: "") }
        #expect(try await scan(sb, rule: rule, running: ["com.apple.dt.xcode"]).items.isEmpty)
        #expect(try await scan(sb, rule: rule).items.count == 1)
    }

    // MARK: other safety skips

    @Test func openFileKeepsItsFolder() async throws {
        let sb = try Sandbox(); defer { sb.remove() }
        let f = try sb.file("root/app/inner/open.db")
        try sb.setAge(sb.url("root/app"), days: 30)
        let r = try await scan(sb, rule: cacheRule, open: [PathGuard.realPath(f.path)!])
        #expect(r.items.isEmpty)
        #expect(r.skipped.first?.reason == "Open in another app")
    }

    @Test func symlinkChildIsNeverAnItemOrFollowed() async throws {
        let sb = try Sandbox(); defer { sb.remove() }
        try sb.file("outside/big", contents: String(repeating: "x", count: 100_000))
        try sb.setAge(sb.url("outside"), days: 30)
        try sb.dir("root")
        try sb.symlink("root/escape", to: sb.url("outside"))
        try sb.file("root/app/link-target-inside", age: 30)
        try sb.symlink("root/app/inner-link", to: sb.url("outside"))
        try sb.setAge(sb.url("root/app"), days: 30)
        let r = try await scan(sb, rule: cacheRule)
        #expect(names(r) == ["app"])
        #expect(r.items[0].bytes < 100_000) // the linked folder's contents were not counted
        #expect(r.skipped.contains { $0.path.hasSuffix("/escape") })
    }

    @Test func keepsNewestVersionsByVersionNumber() async throws {
        let sb = try Sandbox(); defer { sb.remove() }
        for v in ["9.0 (A)", "15.0 (B)", "16.4 (C)", "17.0 (D)"] { try sb.file("root/\(v)/sym") }
        let r = try await scan(sb) { Rule(id: "t", category: .xcode, title: "t", root: $0, ageFiltered: false, keepNewest: 2, explanation: "") }
        #expect(names(r) == ["9.0 (A)", "15.0 (B)"])
    }

    @Test func excludedNamesAreNeverIncluded() async throws {
        let sb = try Sandbox(); defer { sb.remove() }
        for n in ["com.apple.Safari", "Homebrew", "com.example.app"] {
            try sb.file("root/\(n)/c")
            try sb.setAge(sb.url("root/\(n)"), days: 30)
        }
        let r = try await scan(sb) { Rule(id: "t", category: .userCaches, title: "t", root: $0, excludeNames: ["com.apple.*", "Homebrew"], explanation: "") }
        #expect(names(r) == ["com.example.app"])
    }

    @Test func scanIsReadOnly() async throws {
        let sb = try Sandbox(); defer { sb.remove() }
        let f = try sb.file("root/app/c", age: 30)
        try sb.setAge(sb.url("root/app"), days: 30)
        _ = try await scan(sb, rule: cacheRule)
        #expect(FileManager.default.fileExists(atPath: f.path))
    }

    @Test func cancellationStopsTheScan() async throws {
        let sb = try Sandbox(); defer { sb.remove() }
        for i in 0..<50 { try sb.file("root/app\(i)/c", age: 30) }
        let task = Task { try await scan(sb, rule: cacheRule) }
        task.cancel()
        await #expect(throws: CancellationError.self) { try await task.value }
    }
}
