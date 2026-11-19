import Foundation
import Testing
@testable import CleanerBuilt

struct PathGuardTests {
    // MARK: allowlist / denylist

    @Test func childOfRootIsAllowed() throws {
        let sb = try Sandbox(); defer { sb.remove() }
        let root = try sb.dir("root")
        let f = try sb.file("root/app/cache.db")
        let g = PathGuard(deny: [], roots: [root.path])
        #expect(g.validate(f) != nil)
        #expect(g.validate(f.deletingLastPathComponent()) != nil)
    }

    @Test func rootItselfIsNeverAllowed() throws {
        let sb = try Sandbox(); defer { sb.remove() }
        let root = try sb.dir("root")
        #expect(PathGuard(deny: [], roots: [root.path]).validate(root) == nil)
    }

    @Test func pathOutsideRootsIsRejected() throws {
        let sb = try Sandbox(); defer { sb.remove() }
        let root = try sb.dir("root")
        let outside = try sb.file("outside/secret.txt")
        #expect(PathGuard(deny: [], roots: [root.path]).validate(outside) == nil)
    }

    @Test func siblingWithSharedPrefixIsRejected() throws {
        let sb = try Sandbox(); defer { sb.remove() }
        let root = try sb.dir("root")
        let evil = try sb.file("rootevil/x")
        #expect(PathGuard(deny: [], roots: [root.path]).validate(evil) == nil)
    }

    @Test func missingPathIsRejected() throws {
        let sb = try Sandbox(); defer { sb.remove() }
        let root = try sb.dir("root")
        #expect(PathGuard(deny: [], roots: [root.path]).validate(sb.url("root/nope")) == nil)
    }

    @Test func denylistWinsOverAllowlist() throws {
        let sb = try Sandbox(); defer { sb.remove() }
        let root = try sb.dir("root")
        let f = try sb.file("root/protected/inner/file")
        let g = PathGuard(deny: [sb.url("root/protected").path], roots: [root.path])
        #expect(g.validate(f) == nil)
        #expect(g.validate(sb.url("root/protected")) == nil)
    }

    @Test func denyWildcardMatches() throws {
        let sb = try Sandbox(); defer { sb.remove() }
        let root = try sb.dir("root")
        let doc = try sb.file("root/com.x.app/Data/Documents/a.txt")
        let other = try sb.file("root/com.x.app/Data/Caches/a.txt")
        let g = PathGuard(deny: [root.path + "/*/Data/Documents"], roots: [root.path])
        #expect(g.validate(doc) == nil)
        #expect(g.validate(other) != nil)
    }

    @Test func denyIsCaseInsensitive() throws {
        let sb = try Sandbox(); defer { sb.remove() }
        let root = try sb.dir("root")
        try sb.file("root/Protected/file")
        let g = PathGuard(deny: [sb.url("root/protected").path], roots: [root.path])
        #expect(g.validate(sb.url("root/PROTECTED/file")) == nil)
    }

    @Test func denyGivenThroughSymlinkedParentStillMatches() throws {
        // /var -> /private/var: the temp folder lives under /var/folders, so this deny entry is written in unresolved form.
        let sb = try Sandbox(); defer { sb.remove() }
        let root = try sb.dir("root")
        let f = try sb.file("root/protected/file")
        let unresolved = sb.url("root/protected").path.replacingOccurrences(of: "/private/var/", with: "/var/")
        #expect(PathGuard(deny: [unresolved], roots: [root.path]).validate(f) == nil)
    }

    // MARK: symlink escapes

    @Test func symlinkItemIsRejected() throws {
        let sb = try Sandbox(); defer { sb.remove() }
        let root = try sb.dir("root")
        let target = try sb.file("root/real.txt")
        try sb.symlink("root/link.txt", to: target)
        #expect(PathGuard(deny: [], roots: [root.path]).validate(sb.url("root/link.txt")) == nil)
    }

    @Test func symlinkedFolderPointingOutsideIsRejected() throws {
        let sb = try Sandbox(); defer { sb.remove() }
        let root = try sb.dir("root")
        let outside = try sb.dir("outside")
        try sb.file("outside/precious.txt")
        try sb.symlink("root/escape", to: outside)
        let g = PathGuard(deny: [], roots: [root.path])
        #expect(g.validate(sb.url("root/escape")) == nil)
        #expect(g.validate(sb.url("root/escape/precious.txt")) == nil)
    }

    @Test func symlinkIntoDeniedFolderIsRejected() throws {
        let sb = try Sandbox(); defer { sb.remove() }
        let root = try sb.dir("root")
        let vault = try sb.dir("root/vault")
        try sb.file("root/vault/key")
        try sb.symlink("root/shortcut", to: vault)
        let g = PathGuard(deny: [vault.path], roots: [root.path])
        #expect(g.validate(sb.url("root/shortcut/key")) == nil)
    }

    @Test func symlinkedRootResolvesToRealRoot() throws {
        let sb = try Sandbox(); defer { sb.remove() }
        try sb.dir("realroot")
        try sb.symlink("aliasroot", to: sb.url("realroot"))
        let f = try sb.file("realroot/app/file")
        let g = PathGuard(deny: [], roots: [sb.url("aliasroot").path])
        #expect(g.validate(f) == PathGuard.realPath(f.path))
    }

    // MARK: path traversal

    @Test func dotDotOutOfRootIsRejected() throws {
        let sb = try Sandbox(); defer { sb.remove() }
        let root = try sb.dir("root")
        try sb.file("outside/secret.txt")
        let sneaky = URL(fileURLWithPath: root.path + "/../outside/secret.txt")
        #expect(PathGuard(deny: [], roots: [root.path]).validate(sneaky) == nil)
    }

    @Test func dotDotIntoDeniedFolderIsRejected() throws {
        let sb = try Sandbox(); defer { sb.remove() }
        let root = try sb.dir("root")
        try sb.file("root/vault/key")
        try sb.dir("root/app")
        let sneaky = URL(fileURLWithPath: root.path + "/app/../vault/key")
        #expect(PathGuard(deny: [sb.url("root/vault").path], roots: [root.path]).validate(sneaky) == nil)
    }

    @Test func dotDotBackToRootItselfIsRejected() throws {
        let sb = try Sandbox(); defer { sb.remove() }
        let root = try sb.dir("root")
        try sb.dir("root/app")
        #expect(PathGuard(deny: [], roots: [root.path]).validate(URL(fileURLWithPath: root.path + "/app/..")) == nil)
    }

    @Test func dotDotStayingInsideRootIsAllowedAndResolved() throws {
        let sb = try Sandbox(); defer { sb.remove() }
        let root = try sb.dir("root")
        try sb.dir("root/a")
        let b = try sb.file("root/b/file")
        let g = PathGuard(deny: [], roots: [root.path])
        #expect(g.validate(URL(fileURLWithPath: root.path + "/a/../b/file")) == PathGuard.realPath(b.path))
    }

    // MARK: the real rules (string checks only, nothing on disk is touched)

    @Test(arguments: [
        "/System/Library/foo", "/usr/lib/x", "/bin/ls", "/sbin/x", "/private/var/db/x", "/Library/Apple/x",
        "~/Library/Keychains/login.keychain-db", "~/Library/Mobile Documents/com~apple~CloudDocs/a",
        "~/Library/Containers/com.example/Data/Documents/a", "~/Library/Mail/V10", "~/Library/Messages/chat.db",
        "~/Library/Photos/x", "~/Library/Application Support/Foo/bar", "~/Documents/a", "~/Desktop/a",
        "~/Pictures/a", "~/Music/a", "~/Movies/a", "~/Library/Logs/CleanerBuilt/log.jsonl",
    ])
    func liveDenylistCoversSpec(_ path: String) {
        #expect(PathGuard.live.isDenied(CleanupRules.expand(path)))
    }

    @Test func liveDenylistLeavesCachesAlone() {
        #expect(!PathGuard.live.isDenied(CleanupRules.expand("~/Library/Caches/com.example.app")))
        #expect(!PathGuard.live.isDenied(CleanupRules.expand("~/Library/Logs/SomeApp")))
    }

    @Test func noRuleRootIsDenied() {
        for rule in CleanupRules.rules where !rule.isReviewOnly {
            #expect(!PathGuard.live.isDenied(rule.rootPath), "\(rule.id)")
        }
    }

    @Test func reviewOnlyRootsAreNotCleanable() {
        let downloads = CleanupRules.expand("~/Downloads")
        #expect(!PathGuard.live.roots.contains(downloads.lowercased()))
    }
}
