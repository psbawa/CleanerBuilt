import Observation

@Observable
final class AppModel {
    private(set) var hasFullDiskAccess = Permissions.hasFullDiskAccess()

    func refreshPermissions() {
        hasFullDiskAccess = Permissions.hasFullDiskAccess()
    }
}
