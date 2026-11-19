import SwiftUI

struct OnboardingView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(spacing: 18) {
            Image(systemName: "lock.shield")
                .font(.system(size: 56))
                .foregroundStyle(.tint)
            Text("Cleaner Built needs Full Disk Access")
                .font(.title2.bold())
            Text("To measure app caches, logs and the Trash, macOS requires Full Disk Access. Cleaner Built only looks in folders it is allowed to clean, always shows you a preview first, and moves what you choose to the Trash so you can put it back.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .frame(maxWidth: 440)
            VStack(alignment: .leading, spacing: 6) {
                Label("Click **Open System Settings**", systemImage: "1.circle")
                Label("Turn on **Cleaner Built** in the list (use + if it's missing)", systemImage: "2.circle")
                Label("Come back here. If macOS asks, quit and reopen the app", systemImage: "3.circle")
            }
            HStack {
                Button("Check Again") { model.refreshPermissions() }
                Button("Open System Settings") { Permissions.openFullDiskAccessSettings() }
                    .keyboardShortcut(.defaultAction)
            }
            .controlSize(.large)
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
