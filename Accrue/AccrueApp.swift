import SwiftUI

@main
struct AccrueApp: App {
    @State private var model = AppModel.shared
    @Environment(\.scenePhase) private var scenePhase

    init() {
        TargetAlerts.install()
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(model)
                .task {
                    if model.usesHealth { model.health.attach(to: model) }
                    await model.loadCatalog()
                    AccrueShortcuts.updateAppShortcutParameters()
                }
                .task(priority: .utility) {
                    // The 3D body takes a while to load; start before the first demo needs it.
                    _ = await BodyAsset.shared.prepare()
                }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active { model.saveNow() }
        }
    }
}
