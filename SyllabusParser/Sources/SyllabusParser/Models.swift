import Foundation
import FoundationModels

@Generable
struct ModelFact {
    @Guide(description: "Literal contiguous value copied from the supporting quote. Empty string if missing or ambiguous; never paraphrase or repair corrupted words.")
    var value: String
    @Guide(description: "Shortest verbatim source passage containing the entire value and its meaning, at most 250 characters. No page labels or invented text.")
    var quote: String
}

@Generable
struct CoursePass {
    @Guide(description: "Course identifier copied from the course heading. Not prerequisites, textbook codes, or room numbers.")
    var courseCode: ModelFact
    @Guide(description: "Course title from its heading. Not the syllabus heading or a topic in the description.")
    var courseName: ModelFact
    @Guide(description: "Explicit term and year copied from the source. Empty if absent; do not infer from dates.")
    var semester: ModelFact
    @Guide(description: "Instructor name copied from the instructor line. Empty if not provided. The quote must contain the name.")
    var instructor: ModelFact
}

@Generable
struct ModelGrade {
    @Guide(description: "Literal assessed component name, e.g. Quizzes, Exam 1, Participation/Attendance. Never Final Grade, a table heading, or a letter-grade threshold.")
    var category: String
    @Guide(description: "Percent of the overall course grade explicitly assigned to THIS component in the SAME row or clause; nil if unknown. Never points, exam numbers, grade-scale ranges, fractions, or a calculated percentage.")
    var percentage: Double?
    @Guide(description: "Verbatim table row or short clause containing this component and its own weight, if known. Keep cell order. Never quote a different row or an entire table.")
    var quote: String
}

@Generable
struct GradingPass {
    @Guide(description: "Only components contributing to the course grade. Read Component/Weight tables; skip Percentage Range/Letter Grade scales. Empty array if absent.", .maximumCount(8))
    var categories: [ModelGrade]
}

@Generable
struct PolicyPass {
    @Guide(description: "One item per distinct assessment-policy assertion. Preserve collection/submission status, dropped scores, missed work consuming drops, makeups, restrictions, and exceptions. A no-makeup rule and a missed-work/drop rule are separate items. Copy the full substantive clause verbatim, including negation; never just a heading. Empty if absent.", .maximumCount(6))
    var policies: [ModelFact]
}

@Generable
enum EventCertainty: String {
    case explicit, tentative, unspecified
}

@Generable
struct ModelEvent {
    @Guide(description: "Literal name of a specific exam, test, quiz, assignment deadline, presentation, or course milestone. Never Instructor Information, a policy, a topic list, or a table heading.")
    var title: String
    @Guide(description: "One literal calendar date from the same row/clause as the event, preserving written year or no year. Empty if missing, ambiguous, or to be announced. Never a semester, weekday alone, page number, or inferred year.")
    var dateText: String
    @Guide(description: "tentative when the source says tentative/planned/subject to change; unspecified when the date is unknown; explicit otherwise.")
    var certainty: EventCertainty
    @Guide(description: "Shortest verbatim source row or clause tying this event to its date or explicitly unknown deadline. At most 250 characters.")
    var quote: String
}

@Generable
struct EventPass {
    @Guide(description: "Specific academic events only. An event without a date needs explicit scheduling language such as final project due date TBA. Empty array if none.", .maximumCount(8))
    var events: [ModelEvent]
}

@Generable
struct RecurrencePass {
    @Guide(description: "Only explicitly repeating instructional or assessment activities. Copy exact source text with its stated frequency or meeting weekdays and times. Never supply an example from outside the source. Never classroom locations, calculator bans, makeup policies, grading scales, topic lists, or a bare activity heading. Empty array if none.", .maximumCount(6))
    var rules: [ModelFact]
}

struct SourceReference: Codable, Equatable, Sendable {
    var quote: String
    var page: Int?
    var textOrigin: SourceTextOrigin? = nil
}

// Nil means effective extraction text, preserving the existing source format.
enum SourceTextOrigin: String, Codable, Sendable {
    case rawPDFText
}

struct GradeThreshold: Codable, Equatable, Sendable {
    var grade: String
    var rangeText: String
    var lowerBound: Double?
    var upperBound: Double?
    var lowerInclusive: Bool?
    var upperInclusive: Bool?
    var source: SourceReference
}

struct ClassSchedule: Codable, Equatable, Sendable {
    var days: [String]
    // Keep the literal time range; never infer a missing meridiem or timezone.
    var timeText: String
    var source: SourceReference
}

struct Fact: Codable, Equatable, Sendable {
    var value: String
    var source: SourceReference
}

struct GradeCategory: Codable, Equatable, Sendable {
    var category: String
    var percentage: Double?
    var source: SourceReference
}

struct AcademicEvent: Codable, Equatable, Sendable {
    var title: String
    var dateText: String?
    var certainty: String
    var source: SourceReference
}

struct SyllabusResult: Codable, Equatable, Sendable {
    var courseCode: Fact?
    var courseName: Fact?
    var semester: Fact?
    var instructor: Fact?
    var grading: [GradeCategory]
    var gradingPolicies: [Fact]
    var events: [AcademicEvent]
    var recurringRules: [Fact]
    var warnings: [String]
    var gradeScale: [GradeThreshold] = []
    var classSchedules: [ClassSchedule] = []

    static let empty = SyllabusResult(courseCode: nil, courseName: nil, semester: nil, instructor: nil,
                                      grading: [], gradingPolicies: [], events: [], recurringRules: [], warnings: [])

    var json: String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return String(data: (try? encoder.encode(self)) ?? Data(), encoding: .utf8) ?? "{}"
    }
}

// Encode unknowns explicitly while continuing to decode existing result files.
extension SourceReference {
    private enum CodingKeys: String, CodingKey { case quote, page, textOrigin }
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(quote, forKey: .quote)
        try container.encode(page, forKey: .page)
        try container.encodeIfPresent(textOrigin, forKey: .textOrigin)
    }
}
extension GradeCategory {
    private enum CodingKeys: String, CodingKey { case category, percentage, source }
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(category, forKey: .category)
        try container.encode(percentage, forKey: .percentage)
        try container.encode(source, forKey: .source)
    }
}
extension AcademicEvent {
    private enum CodingKeys: String, CodingKey { case title, dateText, certainty, source }
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(title, forKey: .title)
        try container.encode(dateText, forKey: .dateText)
        try container.encode(certainty, forKey: .certainty)
        try container.encode(source, forKey: .source)
    }
}
extension SyllabusResult {
    private enum CodingKeys: String, CodingKey {
        case courseCode, courseName, semester, instructor, grading, gradingPolicies, events, recurringRules, warnings, gradeScale, classSchedules
    }
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        courseCode = try container.decodeIfPresent(Fact.self, forKey: .courseCode)
        courseName = try container.decodeIfPresent(Fact.self, forKey: .courseName)
        semester = try container.decodeIfPresent(Fact.self, forKey: .semester)
        instructor = try container.decodeIfPresent(Fact.self, forKey: .instructor)
        grading = try container.decode([GradeCategory].self, forKey: .grading)
        gradingPolicies = try container.decode([Fact].self, forKey: .gradingPolicies)
        events = try container.decode([AcademicEvent].self, forKey: .events)
        recurringRules = try container.decode([Fact].self, forKey: .recurringRules)
        warnings = try container.decode([String].self, forKey: .warnings)
        gradeScale = try container.decodeIfPresent([GradeThreshold].self, forKey: .gradeScale) ?? []
        classSchedules = try container.decodeIfPresent([ClassSchedule].self, forKey: .classSchedules) ?? []
    }
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(courseCode, forKey: .courseCode)
        try container.encode(courseName, forKey: .courseName)
        try container.encode(semester, forKey: .semester)
        try container.encode(instructor, forKey: .instructor)
        try container.encode(grading, forKey: .grading)
        try container.encode(gradingPolicies, forKey: .gradingPolicies)
        try container.encode(events, forKey: .events)
        try container.encode(recurringRules, forKey: .recurringRules)
        try container.encode(warnings, forKey: .warnings)
        try container.encode(gradeScale, forKey: .gradeScale)
        try container.encode(classSchedules, forKey: .classSchedules)
    }
}
