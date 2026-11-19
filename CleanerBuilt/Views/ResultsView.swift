import SwiftUI

struct ResultsView: View {
    @Environment(AppModel.self) private var model
    @State private var showConfirm = false

    var body: some View {
        Group {
            if model.isScanning {
                ScanProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let result = model.result {
                list(result)
            } else {
                ContentUnavailableView {
                    Label("No Scan Yet", systemImage: "magnifyingglass")
                } description: {
                    Text("Run a scan to preview what can be cleaned. Nothing is removed until you confirm.")
                } actions: {
                    Button("Scan") { model.startScan() }
                }
            }
        }
        .navigationTitle("Scan Results")
    }

    private func list(_ result: ScanResult) -> some View {
        List {
            ForEach(CleanupCategory.allCases.filter { $0 != .largeFiles }) { category in
                let items = result.items.filter { $0.category == category }.sorted { $0.bytes > $1.bytes }
                if !items.isEmpty {
                    Section {
                        DisclosureGroup {
                            ForEach(items) { row($0) }
                        } label: {
                            HStack {
                                Toggle(isOn: isOn(items.map(\.id))) {
                                    Label(category.title, systemImage: category.symbol).font(.headline)
                                }
                                Spacer()
                                Text(items.reduce(0) { $0 + $1.bytes }.byteString).monospacedDigit()
                            }
                        }
                    } footer: {
                        Text(category.explanation).font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            if !result.skipped.isEmpty {
                Section {
                    DisclosureGroup("\(result.skipped.count) items skipped for safety") {
                        ForEach(result.skipped) { s in
                            VStack(alignment: .leading) {
                                Text(s.reason)
                                Text(s.path).font(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                            }
                        }
                    }
                }
            }
            if !result.errors.isEmpty {
                Section {
                    DisclosureGroup("\(result.errors.count) couldn't be read") {
                        ForEach(result.errors, id: \.self) { Text($0).font(.caption) }
                    }
                }
            }
        }
        .safeAreaInset(edge: .bottom) {
            HStack {
                if model.isCleaning {
                    CleanProgressView()
                    Spacer()
                } else {
                    Text("\(model.selection.count) of \(result.items.count) items selected")
                    Spacer()
                    Text(model.selectedBytes.byteString).font(.title3.bold()).monospacedDigit()
                    Button("Move to Trash…", systemImage: "trash") { showConfirm = true }
                        .buttonStyle(.borderedProminent)
                        .disabled(model.selection.isEmpty || model.isBusy)
                }
            }
            .padding()
            .background(.bar)
        }
        .sheet(isPresented: $showConfirm) {
            ConfirmCleanSheet()
        }
    }

    private func row(_ item: ScanItem) -> some View {
        HStack {
            Toggle(isOn: isOn([item.id])) {
                VStack(alignment: .leading) {
                    Text(model.displayName(item))
                    Text(item.url.path).font(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                }
            }
            Spacer()
            Text(item.bytes.byteString).monospacedDigit()
        }
        .contextMenu {
            Button("Reveal in Finder") { NSWorkspace.shared.activateFileViewerSelecting([item.url]) }
        }
    }

    // ponytail: a partly selected category shows as unchecked; use Toggle(sources:) if a mixed state is wanted.
    private func isOn(_ ids: [String]) -> Binding<Bool> {
        Binding(
            get: { ids.allSatisfy(model.selection.contains) },
            set: { on in if on { model.selection.formUnion(ids) } else { model.selection.subtract(ids) } }
        )
    }
}

struct LargeFilesView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(CleanupCategory.largeFiles.explanation)
                .foregroundStyle(.secondary)
                .padding()
            Table(model.result?.largeFiles.sorted { $0.bytes > $1.bytes } ?? []) {
                TableColumn("Name") { Text($0.name).help($0.url.path) }
                TableColumn("Size") { Text($0.bytes.byteString).monospacedDigit() }.width(90)
                TableColumn("Last Opened") { Text($0.lastUsed, format: .dateTime.year().month().day()) }.width(110)
                TableColumn("") { item in
                    Button("Reveal in Finder") { NSWorkspace.shared.activateFileViewerSelecting([item.url]) }
                }.width(130)
            }
        }
        .navigationTitle("Large Files")
        .overlay {
            if model.result == nil && !model.isScanning {
                ContentUnavailableView("No Scan Yet", systemImage: "doc.badge.ellipsis", description: Text("Run a scan from Overview."))
            }
        }
    }
}
