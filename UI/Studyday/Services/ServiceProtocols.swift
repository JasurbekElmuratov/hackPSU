import Foundation

@MainActor
protocol AuthServiceProtocol {
    func signIn(provider: AuthProvider) async throws -> UserSession
    func signOut() async
}

struct ImportedSyllabus: Sendable {
    let result: SyllabusResult
    let document: SyllabusDocument
}

@MainActor
protocol SyllabusExtractorProtocol {
    func extract(from url: URL) async throws -> ImportedSyllabus
}

@MainActor
protocol ChatServiceProtocol {
    func reply(to userMessage: String, syllabus: SyllabusResult) async -> AssistantReply
}

enum ServiceError: LocalizedError {
    case unavailable(String)
    var errorDescription: String? { if case .unavailable(let message) = self { return message }; return nil }
}
