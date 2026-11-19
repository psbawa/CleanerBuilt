import SwiftUI

struct ConfirmCleanSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let items = model.selectedItems.sorted { $0.bytes > $1.bytes }
        let permanent = items.filter { !(CleanupRules.rule($0.ruleID)?.movesToTrash ?? true) }
        VStack(alignment: .leading, spacing: 14) {
            Label("Move \(items.count) items to the Trash?", systemImage: "trash")
                .font(.title2.bold())
            Text("Total: **\(model.selectedBytes.byteString)**. Nothing is deleted: you can restore any item from the Trash with **Put Back** in Finder. Each item is checked again right before it moves, and anything that changed or is now in use is skipped.")
                .fixedSize(horizontal: false, vertical: true)
            if !permanent.isEmpty {
                Label("Can't be undone: \(permanent.map(model.displayName).joined(separator: ", ")) \(permanent.count == 1 ? "is" : "are") cleaned by the tool itself and won't go to the Trash.", systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }
            List(items) { item in
                HStack {
                    if permanent.contains(item) {
                        Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                    }
                    Text(model.displayName(item))
                    Spacer()
                    Text(item.bytes.byteString).monospacedDigit().foregroundStyle(.secondary)
                }
                .help(item.url.path)
            }
            .frame(height: 220)
            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Move to Trash") {
                    dismiss()
                    model.clean()
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(20)
        .frame(width: 500)
    }
}

struct CleanProgressView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        HStack(spacing: 12) {
            if model.cleanTotal > 0 {
                ProgressView(value: Double(model.cleanedCount), total: Double(model.cleanTotal))
                    .frame(maxWidth: 220)
                Text("Moving to Trash… \(model.cleanedCount) of \(model.cleanTotal)").monospacedDigit()
                Button("Cancel", role: .cancel) { model.cancelClean() }
            } else {
                ProgressView().controlSize(.small)
                Text("Emptying Trash…")
            }
        }
    }
}

struct CleanReportSheet: View {
    let report: CleanReport
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(report.title, systemImage: "checkmark.circle.fill")
                .font(.title2.bold())
                .foregroundStyle(.green)
            Text("\(report.done.count) items, \(report.doneBytes.byteString)")
                .font(.title3)
            if report.stoppedEarly {
                Label("Stopped early. Remaining items were not touched.", systemImage: "stop.circle")
            }
            if report.done.contains(where: { $0.outcome == .trashed }) {
                Text("Changed your mind? Open the Trash in Finder and use **Put Back**.")
                    .foregroundStyle(.secondary)
            }
            if !report.problems.isEmpty {
                Text("\(report.problems.count) not removed").font(.headline)
                List(report.problems) { e in
                    VStack(alignment: .leading) {
                        Text(e.detail)
                        Text(e.path).font(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                    }
                }
                .frame(height: 180)
            }
            HStack {
                Spacer()
                Button("Done") { dismiss() }.keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 500)
    }
}

struct HistoryView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        Table(model.history) {
            TableColumn("Date") { Text($0.date, format: .dateTime.year().month().day().hour().minute()) }.width(140)
            TableColumn("Action", value: \.action).width(110)
            TableColumn("Result") { e in
                Label(e.outcome.rawValue.capitalized, systemImage: e.outcome.symbol).foregroundStyle(e.outcome.color)
            }.width(90)
            TableColumn("Item") { Text($0.path).lineLimit(1).truncationMode(.middle).help($0.path) }
            TableColumn("Size") { Text($0.bytes.byteString).monospacedDigit() }.width(80)
            TableColumn("Details") { Text($0.detail).help($0.detail) }
        }
        .overlay {
            if model.history.isEmpty {
                ContentUnavailableView("No History Yet", systemImage: "clock.arrow.circlepath", description: Text("Every item Cleaner Built moves or erases is listed here."))
            }
        }
        .toolbar {
            Button("Show Log File", systemImage: "doc.text.magnifyingglass") {
                NSWorkspace.shared.activateFileViewerSelecting([ActionLog.live.fileURL])
            }
            .disabled(model.history.isEmpty)
        }
        .navigationTitle("History")
        .onAppear { model.loadHistory() }
    }
}

extension LogEntry.Outcome {
    var symbol: String {
        switch self {
        case .trashed: "trash"
        case .deleted: "xmark.bin"
        case .skipped: "arrow.uturn.right"
        case .failed: "exclamationmark.triangle"
        }
    }

    var color: Color {
        switch self {
        case .trashed, .deleted: .primary
        case .skipped: .secondary
        case .failed: .red
        }
    }
}
