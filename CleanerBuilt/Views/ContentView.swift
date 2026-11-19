import SwiftUI

enum SidebarItem: String, CaseIterable, Identifiable {
    case overview = "Overview"
    case results = "Scan Results"
    case largeFiles = "Large Files"
    case history = "History"
    case settings = "Settings"

    var id: Self { self }

    var symbol: String {
        switch self {
        case .overview: "gauge.with.dots.needle.33percent"
        case .results: "list.bullet.indent"
        case .largeFiles: "doc.badge.ellipsis"
        case .history: "clock.arrow.circlepath"
        case .settings: "gearshape"
        }
    }
}

struct ContentView: View {
    @State private var selection: SidebarItem? = .overview

    var body: some View {
        NavigationSplitView {
            List(SidebarItem.allCases, selection: $selection) { item in
                Label(item.rawValue, systemImage: item.symbol)
            }
            .navigationSplitViewColumnWidth(min: 180, ideal: 200)
        } detail: {
            switch selection ?? .overview {
            case .overview: OverviewView(showResults: { selection = .results })
            case .results: ResultsView()
            case .largeFiles: LargeFilesView()
            case .history:
                ContentUnavailableView("History", systemImage: "clock.arrow.circlepath", description: Text("Cleaning history arrives with the cleaning phase."))
                    .navigationTitle("History")
            case .settings: SettingsView()
            }
        }
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
