import AppKit
import AuleumKit

extension AppDelegate {
    func updateStateChanged(_ state: UpdateState) {
        updateStatusItem()
        settingsWindow?.applyUpdateState(state)
    }

    func checkForUpdates() {
        updates.check(manual: true)
    }

    func installAvailableUpdate() {
        updates.installAvailable(manual: true)
    }

    func maybeInstallUpdateAfterIdle() {
        updates.installIfIdle()
    }

    func openUpdateReleasePage() {
        updates.openReleasePage()
    }
}
