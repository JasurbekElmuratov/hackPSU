import Foundation

/// A local workspace, not a Google, Apple ID, or campus authentication session.
@MainActor
final class LocalWorkspaceService: AuthServiceProtocol {
    func signIn(provider: AuthProvider) async throws -> UserSession {
        UserSession(id: UUID().uuidString, displayName: "Student", detail: "Private on-device workspace", provider: .onDevice)
    }
    func signOut() async {}
}

@MainActor
final class LocalSyllabusExtractor: SyllabusExtractorProtocol {
    func extract(from url: URL) async throws -> ImportedSyllabus {
        guard url.pathExtension.lowercased() == "pdf" else { throw ServiceError.unavailable("Choose a PDF syllabus. Other document formats are not supported.") }
        let accessed = url.startAccessingSecurityScopedResource()
        defer { if accessed { url.stopAccessingSecurityScopedResource() } }
        let document = try await Task.detached(priority: .userInitiated) { try SyllabusDocument.pdf(at: url) }.value
        try Task.checkCancellation()
        let result = try await SyllabusExtractor.extract(document)
        return ImportedSyllabus(result: result, document: document)
    }
}

@MainActor
final class LocalChatService: ChatServiceProtocol {
    func reply(to userMessage: String, syllabus: SyllabusResult) async -> AssistantReply {
        await SyllabusAssistant.answer(userMessage, result: syllabus)
    }
}
