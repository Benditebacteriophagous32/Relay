import SwiftUI
import Sparkle

// In-app updates via Sparkle — install is MANUAL only (no background auto-install;
// SUEnableAutomaticChecks is false in Info.plist). What IS automatic is a lightweight,
// UI-less PROBE of the signed appcast so we can tell the user "a new version is available."
// They still choose when to install: clicking the badge / "Download the Latest Version"
// runs the real check, which offers a one-click download → install → relaunch (and shows
// the changelog). So: we notify, the user decides — nothing updates behind their back.

final class UpdaterModel: NSObject, ObservableObject, SPUUpdaterDelegate {
    static let shared = UpdaterModel()

    private(set) var controller: SPUStandardUpdaterController!

    /// True once a silent probe finds a newer build on the appcast.
    @Published var updateAvailable = false
    /// The version string of that newer build (e.g. "1.0.4"), for the badge tooltip.
    @Published var latestVersion: String?

    override init() {
        super.init()
        controller = SPUStandardUpdaterController(startingUpdater: true,
                                                  updaterDelegate: self,
                                                  userDriverDelegate: nil)
    }

    var canCheck: Bool { controller.updater.canCheckForUpdates }

    /// User-initiated check — shows Sparkle's UI (the install prompt with release notes).
    func checkForUpdates() { controller.checkForUpdates(nil) }

    /// Silent probe — no UI. Just asks the appcast "is there something newer?" and reports
    /// the answer via the delegate methods below, which flip `updateAvailable`.
    func checkSilently() {
        guard canCheck else { return }
        controller.updater.checkForUpdateInformation()
    }

    // MARK: SPUUpdaterDelegate (Sparkle calls these on the main thread)
    func updater(_ updater: SPUUpdater, didFindValidUpdate item: SUAppcastItem) {
        updateAvailable = true
        latestVersion = item.displayVersionString
    }
    func updaterDidNotFindUpdate(_ updater: SPUUpdater) {
        updateAvailable = false
        latestVersion = nil
    }
    // A successful install relaunches into the new build, so clear the flag if we somehow
    // get here first (e.g. the user installed from the menu).
    func updater(_ updater: SPUUpdater, didFinishUpdateCycleFor updateCheck: SPUUpdateCheck, error: Error?) {
        if updateCheck == .updates, error == nil { /* result already handled above */ }
    }
}

/// `Relay ▸ Check for Updates…` menu command.
struct CheckForUpdatesCommand: View {
    @ObservedObject private var updater = UpdaterModel.shared
    var body: some View {
        Button("Check for Updates…") { updater.checkForUpdates() }
            .disabled(!updater.canCheck)
    }
}
