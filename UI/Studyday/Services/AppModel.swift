import Foundation
import Combine

@MainActor
final class AppModel: ObservableObject {
    @Published private(set) var session: UserSession?
    @Published private(set) var courses: [CourseItem] = []
    @Published private(set) var messages: [ChatMessage] = []
    @Published private(set) var selectedCourseID: String?
    @Published private(set) var isAuthenticating = false
    @Published private(set) var isChatBusy = false
    @Published var authError: String?
    @Published var chatError: String?
    @Published var selectedTab: AppTab = .chat
    @Published private(set) var pendingSyllabusName: String?
    private let auth: any AuthServiceProtocol
    private let extractor: any SyllabusExtractorProtocol
    private let chat: any ChatServiceProtocol
    private var documents: [String: SyllabusDocument] = [:]
    private var activeTask: Task<Void, Never>?
    private var operationID = UUID()

    init(auth: any AuthServiceProtocol = LocalWorkspaceService(),
         extractor: any SyllabusExtractorProtocol = LocalSyllabusExtractor(),
         chat: any ChatServiceProtocol = LocalChatService()) {
        self.auth = auth; self.extractor = extractor; self.chat = chat
        seedWelcome()
    }
    var isSignedIn: Bool { session != nil }
    var selectedCourse: CourseItem? { courses.first { $0.id == selectedCourseID } }

    func signIn(provider: AuthProvider = .onDevice) { Task { await startWorkspace(demo: false) } }
    func tryDemo() { Task { await startWorkspace(demo: true) } }
    func startWorkspace(demo: Bool) async {
        guard !isAuthenticating else { return }
        isAuthenticating = true; authError = nil
        defer { isAuthenticating = false }
        do {
            if session == nil { session = try await auth.signIn(provider: .onDevice) }
            if demo { try loadDemo(); selectedTab = .home }
            else { selectedTab = .chat }
        } catch { authError = error.localizedDescription }
    }
    func signOut() { Task { await endWorkspace() } }
    func endWorkspace() async {
        cancelOperation()
        await auth.signOut()
        session = nil; courses = []; documents = [:]; selectedCourseID = nil
        chatError = nil; authError = nil
        seedWelcome()
    }
    func loadDemo() throws {
        guard !isChatBusy else { return }
        if let existing = courses.first(where: \.isDemo) { selectCourse(existing.id); return }
        let result = try DemoSyllabus.load()
        addCourse(result, document: nil, isDemo: true)
        appendMessage(role: .system, text: "Loaded the bundled verified JSON as Demo. No PDF was parsed; existing courses and saved files are unchanged.")
    }
    func selectCourse(_ id: String) {
        guard !isChatBusy, courses.contains(where: { $0.id == id }), selectedCourseID != id else { return }
        selectedCourseID = id; chatError = nil; seedWelcome()
    }
    func attachSyllabus(url: URL) {
        guard !isChatBusy else { return }
        activeTask = Task { await importSyllabus(url: url) }
    }
    func importSyllabus(url: URL) async {
        guard session != nil, !isChatBusy else { return }
        let token = UUID(); operationID = token
        isChatBusy = true; chatError = nil; pendingSyllabusName = url.lastPathComponent
        appendMessage(role: .user, text: "Attached syllabus: \(url.lastPathComponent)", fileName: url.lastPathComponent)
        appendMessage(role: .system, text: "Reading the PDF and extracting its syllabus data on this device…")
        defer { if operationID == token { isChatBusy = false; pendingSyllabusName = nil } }
        do {
            let imported = try await extractor.extract(from: url)
            guard !Task.isCancelled, operationID == token, session != nil else { return }
            addCourse(imported.result, document: imported.document, isDemo: false)
            appendMessage(role: .assistant, text: "Added \(selectedCourse?.title ?? "the course") from the selected PDF. Open Home to review its events, weights, policies, and source quotes. Unknown dates remain unknown.")
        } catch {
            guard operationID == token, !Task.isCancelled else { return }
            chatError = error.localizedDescription
            appendMessage(role: .system, text: error.localizedDescription + " No course or sample data was substituted. You can explicitly load the verified demo.")
        }
    }
    func sendUserText(_ text: String) {
        guard !isChatBusy else { return }
        activeTask = Task { await send(text) }
    }
    func send(_ text: String) async {
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !isChatBusy, session != nil else { return }
        appendMessage(role: .user, text: text)
        guard let course = selectedCourse else {
            appendMessage(role: .assistant, text: "No syllabus is selected. Add a PDF or explicitly load the verified demo before asking about course facts.")
            return
        }
        let token = UUID(); operationID = token
        isChatBusy = true; chatError = nil
        defer { if operationID == token { isChatBusy = false } }
        let reply = await chat.reply(to: text, syllabus: course.syllabus)
        guard !Task.isCancelled, operationID == token, selectedCourseID == course.id, session != nil else { return }
        messages.append(ChatMessage(id: UUID().uuidString, role: .assistant, text: reply.text, timestamp: .now, mode: reply.mode, sources: reply.sources))
    }
    @discardableResult
    func applyCorrections(courseID: String, json: String) throws -> SyllabusResult {
        guard !isChatBusy, let index = courses.firstIndex(where: { $0.id == courseID }) else { throw ServiceError.unavailable("That course is not available for editing right now.") }
        var edited = try JSONDecoder().decode(SyllabusResult.self, from: Data(json.utf8))
        ResultValidator.validate(&edited, against: documents[courseID])
        courses[index].syllabus = edited
        if selectedCourseID == courseID { seedWelcome() }
        return edited
    }
    func deleteCourse(_ course: CourseItem) {
        cancelOperation()
        courses.removeAll { $0.id == course.id }; documents[course.id] = nil
        if selectedCourseID == course.id { selectedCourseID = courses.first?.id; seedWelcome() }
    }
    private func addCourse(_ result: SyllabusResult, document: SyllabusDocument?, isDemo: Bool) {
        let course = CourseItem(id: UUID().uuidString, syllabus: result, isDemo: isDemo, createdAt: .now)
        courses.insert(course, at: 0); documents[course.id] = document
        selectedCourseID = course.id; seedWelcome()
    }
    private func cancelOperation() {
        activeTask?.cancel(); operationID = UUID(); isChatBusy = false; pendingSyllabusName = nil
    }
    private func seedWelcome() {
        let text: String
        if let course = selectedCourse {
            text = "Ask about \(course.title)\(course.isDemo ? " (Demo)" : ""). Dates, weights and source quotes come from this syllabus. Select another course to start a separate conversation."
        } else { text = "Your semester, a little lighter. Add a PDF syllabus, or explicitly load the verified demo. Processing stays on this device; no account is required." }
        messages = [ChatMessage(id: UUID().uuidString, role: .assistant, text: text, timestamp: .now)]
    }
    private func appendMessage(role: ChatMessage.Role, text: String, fileName: String? = nil) {
        messages.append(ChatMessage(id: UUID().uuidString, role: role, text: text, timestamp: .now, attachedFileName: fileName))
    }
}

enum AppTab: Hashable { case chat, home, profile }
