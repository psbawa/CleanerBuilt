import SwiftUI

@main
struct CleanerBuiltApp: App {
    @State private var model = AppModel()

    var body: some Scene {
        WindowGroup {
            Group {
                if model.hasFullDiskAccess {
                    ContentView()
                } else {
                    OnboardingView()
                }
            }
            .environment(model)
            .frame(minWidth: 760, minHeight: 480)
            // Re-check when the user comes back from System Settings.
            .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
                model.refreshPermissions()
            }
        }
    }
}
