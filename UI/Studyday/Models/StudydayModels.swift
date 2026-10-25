import Foundation

enum AuthProvider: String, CaseIterable, Identifiable, Sendable {
    case onDevice
    var id: String { rawValue }
    var title: String { "Continue on this device" }
    var systemImage: String { "lock.shield" }
}

struct UserSession: Equatable, Sendable {
    let id: String
    let displayName: String
    let detail: String
    let provider: AuthProvider
}

struct CourseItem: Identifiable, Sendable {
    var id: String
    var syllabus: SyllabusResult
    var isDemo: Bool
    var createdAt: Date
    var code: String { syllabus.courseCode?.value ?? "Course code unknown" }
    var title: String { syllabus.courseName?.value ?? "Course title unknown" }
    var instructor: String { syllabus.instructor?.value ?? "Instructor unknown" }
    var term: String { syllabus.semester?.value ?? "Term unknown" }
    var meetingTimes: String {
        let schedules = syllabus.classSchedules.map { $0.days.joined(separator: " and ") + ": " + $0.timeText }
        return schedules.isEmpty ? "Class schedule unknown" : schedules.joined(separator: "\n")
    }
    var exams: [CourseTask] { tasks().filter { DashboardSnapshot.isExam($0.title) } }
    var quizzes: [CourseTask] { tasks().filter { $0.title.range(of: #"\b(quiz|quizzes)\b"#, options: [.regularExpression, .caseInsensitive]) != nil } }
    var assignments: [CourseTask] {
        tasks().filter { task in !DashboardSnapshot.isExam(task.title) && task.title.range(of: #"\b(quiz|quizzes)\b"#, options: [.regularExpression, .caseInsensitive]) == nil }
    }
    func tasks(now: Date = .now, calendar: Calendar = .current) -> [CourseTask] {
        let snapshot = DashboardSnapshot(result: syllabus, now: now, calendar: calendar)
        return (snapshot.upcoming + snapshot.past + snapshot.undated).map { entry in
            CourseTask(id: "\(id)-event-\(entry.id)", title: entry.event.title, dueDate: entry.normalized?.date,
                       writtenDate: entry.event.dateText, certainty: entry.event.certainty, source: entry.event.source,
                       yearSource: entry.normalized?.yearFromSemester)
        }
    }
}

struct CourseTask: Identifiable, Sendable {
    let id: String
    let title: String
    let dueDate: Date?
    let writtenDate: String?
    let certainty: String
    let source: SourceReference
    let yearSource: Fact?
}

struct ChatMessage: Identifiable, Equatable, Sendable {
    enum Role: String, Sendable { case user, assistant, system }
    let id: String
    let role: Role
    let text: String
    let timestamp: Date
    var attachedFileName: String?
    var mode: AssistantMode?
    var sources: [SourceReference] = []
}
