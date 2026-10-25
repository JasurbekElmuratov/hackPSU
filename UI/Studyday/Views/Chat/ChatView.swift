import SwiftUI
import UniformTypeIdentifiers

struct ChatView: View {
    @EnvironmentObject private var appModel: AppModel
    @State private var draft = ""
    @State private var showSyllabusPicker = false
    @FocusState private var inputFocused: Bool

    var body: some View {
        NavigationStack {
            ZStack {
                StudydayBackground()

                VStack(spacing: 0) {
                    if !appModel.courses.isEmpty {
                        Picker("Course", selection: Binding(get: { appModel.selectedCourseID ?? "" }, set: { appModel.selectCourse($0) })) {
                            ForEach(appModel.courses) { Text($0.code + ($0.isDemo ? " · Demo" : "")).tag($0.id) }
                        }.disabled(appModel.isChatBusy).padding(.horizontal, 16).padding(.top, 10)
                    }
                    HStack {
                        Text(ModelAvailability.isAvailable ? "On-device model ready" : "Local model unavailable · deterministic syllabus answers still work")
                            .font(.caption).foregroundStyle(StudydayTheme.muted)
                        Spacer()
                        Button("Load verified demo") { do { try appModel.loadDemo() } catch { appModel.chatError = error.localizedDescription } }.disabled(appModel.isChatBusy)
                    }.padding(.horizontal, 16).padding(.vertical, 8)
                    if let error = appModel.chatError { Text(error).font(.caption).foregroundStyle(StudydayTheme.danger).padding(.horizontal, 16) }
                    ScrollViewReader { proxy in
                        ScrollView {
                            LazyVStack(alignment: .leading, spacing: 14) {
                                ForEach(appModel.messages) { message in
                                    ChatBubble(message: message)
                                        .id(message.id)
                                }
                                if appModel.isChatBusy {
                                    TypingIndicator()
                                        .id("typing")
                                }
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 12)
                        }
                        .onChange(of: appModel.messages.count) { _, _ in
                            scrollToBottom(proxy: proxy)
                        }
                        .onChange(of: appModel.isChatBusy) { _, busy in
                            if busy { scrollToBottom(proxy: proxy) }
                        }
                    }

                    ComposerBar(
                        draft: $draft,
                        isBusy: appModel.isChatBusy,
                        onAddSyllabus: { showSyllabusPicker = true },
                        onSend: send
                    )
                    .focused($inputFocused)
                }.frame(maxWidth: 1100).frame(maxWidth: .infinity)
            }
            .navigationTitle("studyday")
            .studydayInlineTitle()
            .toolbar {
                ToolbarItem(placement: .principal) {
                    HStack(spacing: 0) {
                        Text("studyday")
                            .font(.system(size: 17, weight: .semibold, design: .rounded))
                            .foregroundStyle(StudydayTheme.ink)
                        Text("·")
                            .font(.system(size: 17, weight: .semibold, design: .rounded))
                            .foregroundStyle(StudydayTheme.accent)
                    }
                }
                ToolbarItem(placement: .primaryAction) {
                    if !appModel.courses.isEmpty {
                        Button {
                            appModel.selectedTab = .home
                        } label: {
                            Label("\(appModel.courses.count)", systemImage: "rectangle.stack.fill")
                                .foregroundStyle(StudydayTheme.accent)
                        }
                    }
                }
            }
            .fileImporter(isPresented: $showSyllabusPicker, allowedContentTypes: [.pdf], allowsMultipleSelection: false) { result in
                switch result {
                case .success(let urls): if let url = urls.first { appModel.attachSyllabus(url: url) }
                case .failure(let error): appModel.chatError = error.localizedDescription
                }
            }

        }
    }

    private func send() {
        let text = draft
        draft = ""
        appModel.sendUserText(text)
    }

    private func scrollToBottom(proxy: ScrollViewProxy) {
        DispatchQueue.main.async {
            withAnimation(.easeOut(duration: 0.25)) {
                if appModel.isChatBusy {
                    proxy.scrollTo("typing", anchor: .bottom)
                } else if let last = appModel.messages.last {
                    proxy.scrollTo(last.id, anchor: .bottom)
                }
            }
        }
    }
}

private struct ChatBubble: View {
    let message: ChatMessage

    var body: some View {
        HStack {
            if message.role == .user { Spacer(minLength: 48) }

            VStack(alignment: message.role == .user ? .trailing : .leading, spacing: 6) {
                if message.role == .system {
                    Text(message.text)
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundStyle(StudydayTheme.sage)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                        .background(Capsule().fill(StudydayTheme.chipFill))
                } else {
                    Text(message.text).textSelection(.enabled)
                        .font(.system(size: 16, weight: .regular, design: .rounded))
                        .foregroundStyle(message.role == .user ? Color.white : StudydayTheme.ink)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 12)
                        .background(
                            RoundedRectangle(cornerRadius: 18, style: .continuous)
                                .fill(message.role == .user ? StudydayTheme.ink : StudydayTheme.paperElevated)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                                        .stroke(
                                            message.role == .user ? Color.clear : StudydayTheme.border,
                                            lineWidth: 1
                                        )
                                )
                        )

                    if let mode = message.mode { Text(mode.rawValue).font(.caption).foregroundStyle(StudydayTheme.muted) }
                    ForEach(Array(message.sources.enumerated()), id: \.offset) { _, source in SyllabusSourceView(source: source) }
                    if let file = message.attachedFileName {
                        Label(file, systemImage: "doc.fill")
                            .font(.caption)
                            .foregroundStyle(StudydayTheme.accent)
                    }
                }
            }

            if message.role != .user { Spacer(minLength: 48) }
        }
    }

    private func localizedMarkdown(_ text: String) -> AttributedString {
        (try? AttributedString(markdown: text)) ?? AttributedString(text)
    }
}

private struct TypingIndicator: View {
    @State private var phase = 0.0

    var body: some View {
        HStack(spacing: 6) {
            ForEach(0..<3, id: \.self) { i in
                Circle()
                    .fill(StudydayTheme.muted.opacity(0.55))
                    .frame(width: 7, height: 7)
                    .offset(y: sin(phase + Double(i) * 0.8) * 3)
            }
        }
        .padding(12)
        .background(
            Capsule()
                .fill(StudydayTheme.paperElevated)
                .overlay(Capsule().stroke(StudydayTheme.border, lineWidth: 1))
        )
        .onAppear {
            withAnimation(.easeInOut(duration: 0.7).repeatForever(autoreverses: true)) {
                phase = .pi
            }
        }
    }
}

private struct ComposerBar: View {
    @Binding var draft: String
    let isBusy: Bool
    let onAddSyllabus: () -> Void
    let onSend: () -> Void

    var body: some View {
        HStack(alignment: .bottom, spacing: 10) {
            Button(action: onAddSyllabus) {
                HStack(spacing: 4) {
                    Image(systemName: "plus")
                        .font(.system(size: 14, weight: .bold))
                    Text("Add syllabus")
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                }
                .foregroundStyle(StudydayTheme.ink)
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(
                    Capsule()
                        .fill(StudydayTheme.chipFill)
                        .overlay(Capsule().stroke(StudydayTheme.badgeBorder, lineWidth: 1))
                )
            }
            .buttonStyle(.plain)
            .disabled(isBusy)
            .accessibilityLabel("Add syllabus")

            HStack(spacing: 8) {
                TextField("Ask Studyday…", text: $draft, axis: .vertical)
                    .lineLimit(1...5)
                    .textFieldStyle(.plain)
                    .font(.system(size: 16, design: .rounded))

                Button(action: onSend) {
                    Image(systemName: "arrow.up")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 34, height: 34)
                        .background(
                            Circle()
                                .fill(canSend ? StudydayTheme.ink : StudydayTheme.chipFill)
                        )
                }
                .buttonStyle(.plain)
                .disabled(!canSend)
                .accessibilityLabel("Send")
            }
            .padding(.leading, 14)
            .padding(.trailing, 6)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(StudydayTheme.paperElevated)
                    .overlay(
                        RoundedRectangle(cornerRadius: 22, style: .continuous)
                            .stroke(StudydayTheme.border, lineWidth: 1)
                    )
            )
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(StudydayTheme.paper.opacity(0.92))
    }

    private var canSend: Bool {
        !isBusy && !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

#Preview {
    ChatView()
        .environmentObject(AppModel())
}
