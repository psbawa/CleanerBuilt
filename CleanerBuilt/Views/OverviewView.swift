import SwiftUI

struct OverviewView: View {
    @Environment(AppModel.self) private var model
    @State private var disk = DiskUsage.current()
    @State private var confirmEmptyTrash = false
    let showResults: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                GroupBox {
                    DiskBar(disk: disk, reclaimable: model.reclaimableBytes)
                        .padding(8)
                } label: {
                    Label("Startup Disk", systemImage: "internaldrive")
                }

                HStack {
                    Spacer()
                    if model.isScanning {
                        ScanProgressView()
                    } else if model.isCleaning {
                        CleanProgressView()
                    } else {
                        Button { model.startScan() } label: {
                            Label("Scan", systemImage: "magnifyingglass")
                                .font(.title3.weight(.semibold))
                                .frame(minWidth: 180, minHeight: 32)
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                    }
                    Spacer()
                }

                if let result = model.result {
                    GroupBox {
                        VStack(alignment: .leading, spacing: 8) {
                            LabeledContent("Scanned", value: result.date.formatted(date: .abbreviated, time: .shortened))
                            LabeledContent("Reclaimable", value: model.reclaimableBytes.byteString)
                            LabeledContent("Items found", value: result.items.count.formatted())
                            LabeledContent("Skipped for safety", value: result.skipped.count.formatted())
                            LabeledContent("Large files to review", value: result.largeFiles.count.formatted())
                            LabeledContent("Trash") {
                                HStack {
                                    Text(result.trashBytes.byteString)
                                    Button("Empty Trash…", role: .destructive) { confirmEmptyTrash = true }
                                        .disabled(model.isBusy || result.trashBytes == 0)
                                }
                            }
                            Button("View Results", action: showResults)
                                .padding(.top, 4)
                        }
                        .padding(8)
                    } label: {
                        Label("Last Scan", systemImage: "checkmark.circle")
                    }
                }
            }
            .padding(24)
        }
        .navigationTitle("Overview")
        .onChange(of: model.isBusy) { disk = .current() }
        .confirmationDialog("Permanently erase everything in the Trash?", isPresented: $confirmEmptyTrash) {
            Button("Erase \(model.result?.trashBytes.byteString ?? "") Permanently", role: .destructive) { model.emptyTrash() }
        } message: {
            Text("This is the only action in Cleaner Built that can't be undone. Items in your Home Trash will be erased and can't be put back.")
        }
    }
}

struct DiskUsage {
    var total: Int64 = 0
    var free: Int64 = 0
    var used: Int64 { total - free }

    static func current() -> DiskUsage {
        let v = try? URL(fileURLWithPath: NSHomeDirectory())
            .resourceValues(forKeys: [.volumeTotalCapacityKey, .volumeAvailableCapacityForImportantUsageKey])
        return DiskUsage(total: Int64(v?.volumeTotalCapacity ?? 0), free: v?.volumeAvailableCapacityForImportantUsage ?? 0)
    }
}

struct DiskBar: View {
    let disk: DiskUsage
    let reclaimable: Int64

    var body: some View {
        let total = max(Double(disk.total), 1)
        let rec = min(reclaimable, disk.used)
        VStack(alignment: .leading, spacing: 10) {
            GeometryReader { geo in
                HStack(spacing: 0) {
                    Rectangle().fill(Color.accentColor).frame(width: geo.size.width * Double(disk.used - rec) / total)
                    Rectangle().fill(.orange).frame(width: geo.size.width * Double(rec) / total)
                    Rectangle().fill(.quaternary)
                }
            }
            .frame(height: 18)
            .clipShape(RoundedRectangle(cornerRadius: 5))
            HStack(spacing: 18) {
                legend(Color.accentColor, "Used", disk.used)
                legend(.orange, "Reclaimable", rec)
                legend(.secondary, "Free", disk.free)
            }
            .font(.callout)
        }
    }

    private func legend(_ color: Color, _ title: String, _ bytes: Int64) -> some View {
        HStack(spacing: 6) {
            Circle().fill(color).frame(width: 8, height: 8)
            Text(title).foregroundStyle(.secondary)
            Text(bytes.byteString).monospacedDigit()
        }
    }
}
