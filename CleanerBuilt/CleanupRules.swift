import Foundation

// The ONLY place cleanup paths are defined. Ask before adding a new root.

nonisolated enum CleanupCategory: String, CaseIterable, Identifiable, Sendable {
    case userCaches, userLogs, temp, xcode, largeFiles

    var id: Self { self }

    var title: String {
        switch self {
        case .userCaches: "App Caches"
        case .userLogs: "App Logs"
        case .temp: "Temporary Files"
        case .xcode: "Xcode"
        case .largeFiles: "Large & Old Files"
        }
    }

    var symbol: String {
        switch self {
        case .userCaches: "archivebox"
        case .userLogs: "doc.text"
        case .temp: "clock.badge.xmark"
        case .xcode: "hammer"
        case .largeFiles: "doc.badge.ellipsis"
        }
    }

    var explanation: String {
        switch self {
        case .userCaches: "Files apps keep so they load faster. Apps rebuild them automatically, so removing them is safe; an app may be a little slower the first time. Apple system caches and caches of running apps are never included."
        case .userLogs: "Diagnostic text logs written by apps. Only useful when troubleshooting a problem. Safe to remove."
        case .temp: "Scratch files apps left in your private temporary folder. Only items untouched for the age threshold and not open in any app."
        case .xcode: "Build products and support files from Xcode. Xcode recreates what it needs. Skipped entirely while Xcode is running."
        case .largeFiles: "Big files in Downloads you haven't opened in 90+ days. Review only: Cleaner Built never selects or removes these."
        }
    }
}

nonisolated enum Unit: Sendable, Equatable {
    /// Each direct child of the root is one item (e.g. one app's cache folder).
    case eachChild
    /// Listed for the user to review in Finder; never selectable for cleaning.
    case reviewOnly(minBytes: Int64, unusedDays: Int)
}

nonisolated struct Rule: Identifiable, Sendable {
    let id: String
    let category: CleanupCategory
    let title: String
    /// "~" = home folder, "$TMPDIR" = the user's own NSTemporaryDirectory().
    let root: String
    var unit: Unit = .eachChild
    /// Only include items where nothing inside changed within the age threshold.
    var ageFiltered = true
    var defaultOn = true
    /// Children are sorted by version name; the newest N are always kept.
    var keepNewest: Int? = nil
    /// fnmatch patterns on child names that are never included.
    var excludeNames: [String] = []
    /// If any of these apps is running, the whole rule is skipped.
    var ownerBundleIDs: [String] = []
    let explanation: String

    var rootPath: String { CleanupRules.expand(root) }
    var isReviewOnly: Bool { if case .reviewOnly = unit { true } else { false } }
}

nonisolated enum CleanupRules {
    static let rules: [Rule] = [
        Rule(id: "userCaches", category: .userCaches, title: "App caches", root: "~/Library/Caches",
             excludeNames: [
                "com.apple.*", "CloudKit", "GeoServices", "FamilyCircle", "PassKit", // Apple / sync state
                "Homebrew",                                                         // cleaned by `brew cleanup` (phase e)
                "pip", "Yarn", "CocoaPods", "Google", "Firefox",                    // own categories in phase e
             ],
             explanation: "One item per app. Only folders untouched for the age threshold."),
        Rule(id: "userLogs", category: .userLogs, title: "App logs", root: "~/Library/Logs",
             excludeNames: ["CleanerBuilt"],
             explanation: "One item per app or log file. Only items untouched for the age threshold."),
        Rule(id: "temp", category: .temp, title: "Your temporary folder", root: "$TMPDIR",
             excludeNames: ["com.apple.*"],
             explanation: "Only items untouched for the age threshold and not currently open."),
        Rule(id: "xcodeDerivedData", category: .xcode, title: "DerivedData", root: "~/Library/Developer/Xcode/DerivedData",
             ownerBundleIDs: ["com.apple.dt.Xcode"],
             explanation: "Intermediate build files and indexes. Xcode rebuilds them; the next build of that project is slower."),
        Rule(id: "xcodeArchives", category: .xcode, title: "Archives", root: "~/Library/Developer/Xcode/Archives",
             ageFiltered: false, defaultOn: false, ownerBundleIDs: ["com.apple.dt.Xcode"],
             explanation: "Warning: archived app builds, including the dSYM files needed to read crash reports from released versions. Only enable this if you've exported what you need."),
        Rule(id: "xcodeDeviceSupport", category: .xcode, title: "iOS DeviceSupport", root: "~/Library/Developer/Xcode/iOS DeviceSupport",
             ageFiltered: false, keepNewest: 2, ownerBundleIDs: ["com.apple.dt.Xcode"],
             explanation: "Debug symbols copied from each iOS version you've connected. The newest 2 versions are always kept; older ones are copied again if needed."),
        Rule(id: "largeDownloads", category: .largeFiles, title: "Large, unused downloads", root: "~/Downloads",
             unit: .reviewOnly(minBytes: 500_000_000, unusedDays: 90), ageFiltered: false,
             explanation: "Files over 500 MB not opened in 90+ days. Shown for review only."),
    ]

    /// Always wins over the rules above. fnmatch patterns; a match also covers everything inside.
    static let deny: [String] = [
        "/System", "/usr", "/bin", "/sbin", "/private/var/db", "/Library/Apple",
        "~/Library/Keychains", "~/Library/Mobile Documents", "~/Library/Containers/*/Data/Documents",
        "~/Library/Mail", "~/Library/Messages", "~/Library/Photos", "~/Library/Application Support",
        "~/Documents", "~/Desktop", "~/Pictures", "~/Music", "~/Movies",
        "~/Library/Logs/CleanerBuilt", // our own action log
    ]

    static let trash = "~/.Trash"

    static func expand(_ path: String) -> String {
        if path == "$TMPDIR" { return NSTemporaryDirectory() }
        if path.hasPrefix("~/") { return NSHomeDirectory() + path.dropFirst() }
        return path
    }
}
