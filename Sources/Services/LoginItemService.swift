import Foundation
import Observation
import ServiceManagement

/// SMAppService wrapper for the launch-at-login toggle.
/// Note: register from a STABLE path (~/Applications/NetBar.app) - registering a
/// DerivedData build binds the login item to a path that vanishes on the next build.
@MainActor
@Observable
final class LoginItemService {
    private(set) var enabled: Bool = SMAppService.mainApp.status == .enabled
    private(set) var lastError: String?

    func setEnabled(_ on: Bool) {
        do {
            if on {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            lastError = nil
        } catch {
            lastError = error.localizedDescription
        }
        enabled = SMAppService.mainApp.status == .enabled
    }

    func refresh() {
        enabled = SMAppService.mainApp.status == .enabled
    }
}
