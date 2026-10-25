import SwiftUI

struct MainTabView: View {
    @EnvironmentObject private var appModel: AppModel
    var body: some View {
        TabView(selection: $appModel.selectedTab) {
            ChatView().tabItem { Label("AI Chat", systemImage: "bubble.left.and.bubble.right.fill") }.tag(AppTab.chat)
            HomeView().tabItem { Label("Home", systemImage: "house.fill") }.tag(AppTab.home)
            ProfileView().tabItem { Label("You", systemImage: "person.crop.circle") }.tag(AppTab.profile)
        }.tint(StudydayTheme.accent)
    }
}

struct ProfileView: View {
    @EnvironmentObject private var appModel: AppModel
    @State private var confirmEnd = false
    var body: some View {
        NavigationStack {
            ZStack {
                StudydayBackground()
                List {
                    if let session = appModel.session {
                        Section {
                            Label(session.displayName, systemImage: "person.crop.circle.fill").font(.headline)
                            Text(session.detail).foregroundStyle(StudydayTheme.muted)
                        }
                        Section("On this device") {
                            LabeledContent("Courses", value: "\(appModel.courses.count)")
                            Text("PDFKit, Vision, and Apple Foundation Models process syllabuses locally. Common questions have deterministic answers when the model is unavailable. Course data and chats remain in memory for this workspace.")
                                .font(.footnote).foregroundStyle(StudydayTheme.muted)
                            Button("Load verified demo") { do { try appModel.loadDemo(); appModel.selectedTab = .home } catch { appModel.chatError = error.localizedDescription } }.disabled(appModel.isChatBusy)
                        }
                        Section {
                            Button("End local workspace", role: .destructive) { confirmEnd = true }
                        }
                    }
                }.scrollContentBackground(.hidden)
            }.navigationTitle("You")
            .confirmationDialog("End this workspace and clear its in-memory courses and chats?", isPresented: $confirmEnd, titleVisibility: .visible) {
                Button("End workspace", role: .destructive) { appModel.signOut() }
                Button("Cancel", role: .cancel) {}
            }
        }
    }
}
