import AppKit
import Observation

@Observable
final class AppModel {
    private(set) var hasFullDiskAccess = Permissions.hasFullDiskAccess()
    private(set) var result: ScanResult?
    private(set) var appNames: [String: String] = [:]
    var selection: Set<String> = []

    private(set) var isScanning = false
    private(set) var scannedFiles = 0
    private(set) var currentPath = ""
    private var scanTask: Task<Void, Never>?

    init() {
        UserDefaults.standard.register(defaults: Prefs.defaults)
    }

    func refreshPermissions() {
        hasFullDiskAccess = Permissions.hasFullDiskAccess()
    }

    var selectedItems: [ScanItem] { result?.items.filter { selection.contains($0.id) } ?? [] }
    var selectedBytes: Int64 { selectedItems.reduce(0) { $0 + $1.bytes } }
    var reclaimableBytes: Int64 { result?.items.reduce(0) { $0 + $1.bytes } ?? 0 }

    func startScan() {
        guard !isBusy else { return }
        isScanning = true
        scannedFiles = 0
        currentPath = ""
        let options = ScanOptions(enabledRuleIDs: Prefs.enabledRuleIDs, ageDays: Prefs.ageDays, runningApps: Self.runningApps())
        scanTask = Task { [weak self] in
            // Only CancellationError is thrown; per-file problems are collected in the result.
            let result = try? await Scanner().scan(options) { files, path in
                Task { @MainActor in
                    self?.scannedFiles = files
                    self?.currentPath = path
                }
            }
            guard let self else { return }
            if let result { finish(result) }
            isScanning = false
            scanTask = nil
        }
    }

    func cancelScan() {
        scanTask?.cancel()
    }

    // MARK: Cleaning

    private(set) var isCleaning = false
    private(set) var cleanedCount = 0
    private(set) var cleanTotal = 0
    var report: CleanReport?
    private(set) var history: [LogEntry] = []
    private var cleanTask: Task<Void, Never>?

    var isBusy: Bool { isScanning || isCleaning }

    /// Moves the selected items to the Trash. Each one is re-checked right before it moves.
    func clean() {
        let items = selectedItems
        guard !isBusy, !items.isEmpty else { return }
        isCleaning = true
        cleanedCount = 0
        cleanTotal = items.count
        let options = ScanOptions(enabledRuleIDs: [], ageDays: Prefs.ageDays, runningApps: Self.runningApps())
        cleanTask = Task { [weak self] in
            let entries = await Cleaner().moveToTrash(items, options: options) { done in
                Task { @MainActor in self?.cleanedCount = done }
            }
            guard let self else { return }
            let moved = entries.filter { $0.outcome == .trashed }
            let movedPaths = Set(moved.map(\.path))
            result?.items.removeAll { movedPaths.contains($0.id) }
            result?.trashBytes += moved.reduce(0) { $0 + $1.bytes }
            selection.subtract(movedPaths)
            report = CleanReport(title: "Moved to Trash", entries: entries, stoppedEarly: entries.count < items.count)
            finishCleaning()
        }
    }

    func cancelClean() {
        cleanTask?.cancel()
    }

    /// PERMANENT. The UI must confirm first.
    func emptyTrash() {
        guard !isBusy else { return }
        isCleaning = true
        cleanedCount = 0
        cleanTotal = 0
        cleanTask = Task { [weak self] in
            let entries = await Cleaner().emptyTrash()
            guard let self else { return }
            result?.trashBytes = entries.filter { $0.outcome != .deleted }.reduce(0) { $0 + $1.bytes }
            report = CleanReport(title: "Trash Emptied", entries: entries, stoppedEarly: false)
            finishCleaning()
        }
    }

    func loadHistory() {
        history = ActionLog.live.read()
    }

    private func finishCleaning() {
        isCleaning = false
        cleanTask = nil
        loadHistory()
    }

    func displayName(_ item: ScanItem) -> String {
        if let rule = CleanupRules.rule(item.ruleID), !rule.movesToTrash { return rule.title }
        return appNames[item.name] ?? item.name
    }

    private func finish(_ result: ScanResult) {
        self.result = result
        selection = Set(result.items.map(\.id)) // dry run: everything starts selected, user deselects
        for item in result.items where appNames[item.name] == nil {
            if let app = NSWorkspace.shared.urlForApplication(withBundleIdentifier: item.name) {
                appNames[item.name] = app.deletingPathExtension().lastPathComponent
            }
        }
    }

    private static func runningApps() -> Set<String> {
        Set(NSWorkspace.shared.runningApplications.flatMap { [$0.bundleIdentifier, $0.localizedName] }.compactMap { $0?.lowercased() })
    }
}

struct CleanReport: Identifiable {
    let id = UUID()
    let title: String
    let entries: [LogEntry]
    let stoppedEarly: Bool

    var done: [LogEntry] { entries.filter { $0.outcome == .trashed || $0.outcome == .deleted } }
    var problems: [LogEntry] { entries.filter { $0.outcome == .skipped || $0.outcome == .failed } }
    var doneBytes: Int64 { done.reduce(0) { $0 + $1.bytes } }
}

enum Prefs {
    static let ageDaysKey = "ageDays"
    static func ruleKey(_ id: String) -> String { "rule.\(id)" }

    static var defaults: [String: Any] {
        var d: [String: Any] = [ageDaysKey: 7]
        for rule in CleanupRules.rules { d[ruleKey(rule.id)] = rule.defaultOn }
        return d
    }

    static var ageDays: Int { max(1, UserDefaults.standard.integer(forKey: ageDaysKey)) }

    static var enabledRuleIDs: Set<String> {
        Set(CleanupRules.rules.filter { UserDefaults.standard.bool(forKey: ruleKey($0.id)) }.map(\.id))
    }
}

extension Int64 {
    var byteString: String { ByteCountFormatter.string(fromByteCount: self, countStyle: .file) }
}
