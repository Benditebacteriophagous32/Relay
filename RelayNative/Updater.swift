import SwiftUI
import Sparkle

// In-app updates via Sparkle — MANUAL only (no background checks; SUEnableAutomaticChecks
// is false in Info.plist). When the user clicks "Download the Latest Version" (Settings)
// or "Check for Updates…" (menu), Sparkle checks the signed appcast on GitHub Releases and,
// if a newer build exists, offers a one-click download → install → relaunch — no GitHub trip.

@MainActor
final class UpdaterModel: ObservableObject {
    static let shared = UpdaterModel()
    let controller: SPUStandardUpdaterController

    init() {
        controller = SPUStandardUpdaterController(startingUpdater: true,
                                                  updaterDelegate: nil,
                                                  userDriverDelegate: nil)
    }

    var canCheck: Bool { controller.updater.canCheckForUpdates }
    func checkForUpdates() { controller.checkForUpdates(nil) }
}

/// `Relay ▸ Check for Updates…` menu command.
struct CheckForUpdatesCommand: View {
    @ObservedObject private var updater = UpdaterModel.shared
    var body: some View {
        Button("Check for Updates…") { updater.checkForUpdates() }
            .disabled(!updater.canCheck)
    }
}
