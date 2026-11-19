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
            // Placeholders until phase (b).
            let item = selection ?? .overview
            ContentUnavailableView(item.rawValue, systemImage: item.symbol, description: Text("Coming in the next phase."))
                .navigationTitle(item.rawValue)
        }
    }
}
