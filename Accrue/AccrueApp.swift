import SwiftUI

@main
struct AccrueApp: App {
    @State private var model = AppModel.live()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(model)
                .task { await model.loadCatalog() }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active { model.saveNow() }
        }
    }
}
