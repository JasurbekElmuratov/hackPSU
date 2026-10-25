import SwiftUI

struct RootView: View {
    @EnvironmentObject private var appModel: AppModel

    var body: some View {
        Group {
            if appModel.isSignedIn {
                MainTabView()
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
            } else {
                LoginView()
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.35), value: appModel.isSignedIn)
        .preferredColorScheme(.light)
    }
}
