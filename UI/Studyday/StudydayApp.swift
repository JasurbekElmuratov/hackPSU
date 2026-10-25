import SwiftUI

@main
struct StudydayApp: App {
    @StateObject private var appModel = AppModel()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(appModel)
        }
        #if os(macOS)
        .defaultSize(width: 960, height: 800)
        #endif
    }
}
