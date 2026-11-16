import SwiftUI

@main
struct MathPadApp: App {
    @State private var model = AppModel.shared
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    init() {
        SketchFeature.register()
    }

    var body: some Scene {
        Window("MathPad", id: "main") {
            RootView()
                .environment(model)
                .frame(minWidth: 720, minHeight: 460)
        }
        .defaultSize(width: 1080, height: 760)
        .commands { MathPadCommands(model: model) }

        Settings {
            SettingsView()
        }
    }
}

/// Hosts whichever feature is active.
struct RootView: View {
    @State private var registry = FeatureRegistry.shared

    var body: some View {
        if let feature = registry.active {
            feature.makeView()
        } else {
            ContentUnavailableView("Kein Modus registriert", systemImage: "questionmark.square.dashed")
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Come to the front when started directly (from a terminal, a script or
        // a file handler) rather than opening behind whatever is in focus.
        NSApp.activate()
    }

    /// A worksheet dropped on the dock icon, or opened with `open -a MathPad …`,
    /// goes straight into the import flow.
    func application(_ application: NSApplication, open urls: [URL]) {
        guard let url = urls.first else { return }
        MainActor.assumeIsolated {
            AppModel.shared.importWorksheet(from: url)
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        MainActor.assumeIsolated { AppModel.shared.store.saveNow() }
    }
}
