import SwiftUI

enum SidebarItem: Hashable {
    case overview
    /// nil = all categories.
    case results(CleanupCategory?)
    case largeFiles, history, settings
}

struct ContentView: View {
    @Environment(AppModel.self) private var model
    @State private var selection: SidebarItem? = .overview

    var body: some View {
        NavigationSplitView {
            List(selection: $selection) {
                Label("Overview", systemImage: "gauge.with.dots.needle.33percent").tag(SidebarItem.overview)
                Label("Scan Results", systemImage: "list.bullet.indent").tag(SidebarItem.results(nil))
                ForEach(model.foundCategories) { category in
                    Label(category.title, systemImage: category.symbol)
                        .badge(Text(model.bytes(in: category).byteString))
                        .padding(.leading, 14)
                        .tag(SidebarItem.results(category))
                }
                Label("Large Files", systemImage: "doc.badge.ellipsis")
                    .badge(model.result?.largeFiles.count ?? 0)
                    .tag(SidebarItem.largeFiles)
                Label("History", systemImage: "clock.arrow.circlepath").tag(SidebarItem.history)
                Label("Settings", systemImage: "gearshape").tag(SidebarItem.settings)
            }
            .navigationSplitViewColumnWidth(min: 200, ideal: 230)
        } detail: {
            switch selection ?? .overview {
            case .overview: OverviewView(showResults: { selection = .results(nil) })
            case .results(let category): ResultsView(only: category)
            case .largeFiles: LargeFilesView()
            case .history: HistoryView()
            case .settings: SettingsView()
            }
        }
        .sheet(item: Bindable(model).report) { CleanReportSheet(report: $0) }
    }
}

struct ScanProgressView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(spacing: 10) {
            ProgressView()
            Text("Scanning… \(model.scannedFiles.formatted()) files")
                .monospacedDigit()
            Text(model.currentPath)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
            Button("Cancel", role: .cancel) { model.cancelScan() }
        }
        .frame(maxWidth: 460)
    }
}
