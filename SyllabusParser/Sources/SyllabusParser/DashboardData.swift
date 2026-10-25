import Foundation

struct DashboardDate: Equatable, Sendable {
    let date: Date
    let yearFromSemester: Fact?
}

struct DashboardEvent: Identifiable, Sendable {
    let id: Int
    let event: AcademicEvent
    let normalized: DashboardDate?
    let courseName: String
}

struct DashboardSnapshot {
    let result: SyllabusResult
    let calendar: Calendar
    let upcoming: [DashboardEvent]
    let past: [DashboardEvent]
    let undated: [DashboardEvent]

    init(result: SyllabusResult, now: Date = .now, calendar: Calendar = .current) {
        self.result = result
        self.calendar = calendar
        let course = result.courseName?.value ?? result.courseCode?.value ?? "Course name unavailable"
        let events = result.events.enumerated().filter { Self.isAcademicEvent($0.element.title) && $0.element.certainty != "recurring" }.map { index, event in
            DashboardEvent(id: index, event: event,
                           normalized: AcademicDates.normalize(event, semester: result.semester, calendar: calendar), courseName: course)
        }
        let dated = events.filter { $0.normalized != nil }.sorted {
            if $0.normalized!.date != $1.normalized!.date { return $0.normalized!.date < $1.normalized!.date }
            return $0.id < $1.id
        }
        let today = calendar.startOfDay(for: now)
        upcoming = dated.filter { $0.normalized!.date >= today }
        past = dated.filter { $0.normalized!.date < today }
        undated = events.filter { $0.normalized == nil }
    }

    static func isAcademicEvent(_ title: String) -> Bool {
        title.range(of: #"\b(exams?|midterms?|quizzes|quiz|tests?|assignments?|projects?|homework|essays?|papers?|presentations?|labs?|reports?|deadlines?)\b"#,
                    options: [.regularExpression, .caseInsensitive]) != nil
    }
    static func isExam(_ title: String) -> Bool {
        title.range(of: #"\b(exams?|midterms?|tests?)\b"#, options: [.regularExpression, .caseInsensitive]) != nil
    }
    static func percentage(_ grade: GradeCategory) -> Double? {
        guard let value = grade.percentage, value.isFinite, (0...100).contains(value),
              ResultValidator.supportsWeight(value, category: grade.category, quote: grade.source.quote) else { return nil }
        return value
    }
    static func percentText(_ value: Double) -> String { value.formatted(.number.precision(.fractionLength(0...2))) + "%" }
    func dateText(_ date: Date) -> String { AcademicDates.display(date, calendar: calendar) }
}

enum AcademicDates {
    static func normalize(_ event: AcademicEvent, semester: Fact?, calendar: Calendar) -> DashboardDate? {
        guard let literal = event.dateText, event.source.quote.evidenceContains(literal),
              event.source.quote.evidenceContains(event.title) else { return nil }
        let text = literal.evidenceText.lowercased()
        let months = ["jan": 1, "feb": 2, "mar": 3, "apr": 4, "may": 5, "jun": 6, "jul": 7, "aug": 8, "sep": 9, "oct": 10, "nov": 11, "dec": 12]
        let named = #"^(?:(mon(?:day)?|m|tue(?:s(?:day)?)?|tu|wed(?:nesday)?|w|thu(?:rs(?:day)?)?|th|fri(?:day)?|f|sat(?:urday)?|sun(?:day)?)[.,]?\s+)?(jan(?:uary)?|feb(?:ruary)?|mar(?:ch)?|apr(?:il)?|may|jun(?:e)?|jul(?:y)?|aug(?:ust)?|sep(?:t(?:ember)?)?|oct(?:ober)?|nov(?:ember)?|dec(?:ember)?)[.]?\s+(\d{1,2})(?:st|nd|rd|th)?(?:,?\s+(\d{4}))?[.]?$"#
        var month: Int, day: Int, year: Int?, weekday = ""
        if let fields = fields(named, in: text), let m = months[String(fields[1].prefix(3))], let d = Int(fields[2]) {
            month = m; day = d; year = Int(fields[3]); weekday = fields[0]
        } else if let fields = fields(#"^(\d{4})-(\d{1,2})-(\d{1,2})$"#, in: text), let y = Int(fields[0]), let m = Int(fields[1]), let d = Int(fields[2]) {
            month = m; day = d; year = y
        } else if let fields = fields(#"^(\d{1,2})/(\d{1,2})(?:/(\d{4}))?$"#, in: text), let m = Int(fields[0]), let d = Int(fields[1]), d > 12 || m == d {
            month = m; day = d; year = Int(fields[2])
        } else { return nil }
        var basis: Fact?
        if year == nil {
            guard let semester, semester.source.quote.evidenceContains(semester.value),
                  let term = fields(#"(?i)^(fall|autumn|spring|summer)\s+(\d{4})$"#, in: semester.value.evidenceText), let y = Int(term[1]) else { return nil }
            let inTerm: Bool
            switch term[0].lowercased() {
            case "fall", "autumn": inTerm = (8...12).contains(month)
            case "spring": inTerm = (1...6).contains(month)
            case "summer": inTerm = (5...8).contains(month)
            default: inTerm = false
            }
            guard inTerm else { return nil }
            year = y; basis = semester
        }
        guard let year, (1...9999).contains(year), (1...12).contains(month), (1...31).contains(day),
              let date = calendar.date(from: DateComponents(year: year, month: month, day: day)) else { return nil }
        let checked = calendar.dateComponents([.year, .month, .day, .weekday], from: date)
        guard checked.year == year, checked.month == month, checked.day == day else { return nil }
        if !weekday.isEmpty {
            let weekdays = ["sun": 1, "mon": 2, "m": 2, "tue": 3, "tu": 3, "wed": 4, "w": 4, "thu": 5, "th": 5, "fri": 6, "f": 6, "sat": 7]
            guard weekdays[String(weekday.prefix(3))] == checked.weekday else { return nil }
        }
        return DashboardDate(date: calendar.startOfDay(for: date), yearFromSemester: basis)
    }

    static func display(_ date: Date, calendar: Calendar) -> String {
        let formatter = DateFormatter()
        formatter.locale = .autoupdatingCurrent
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter.string(from: date)
    }
    private static func fields(_ pattern: String, in text: String) -> [String]? {
        guard let regex = try? NSRegularExpression(pattern: pattern), let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) else { return nil }
        return (1..<match.numberOfRanges).map { Range(match.range(at: $0), in: text).map { String(text[$0]) } ?? "" }
    }
}

enum DemoSyllabus {
    static func load() throws -> SyllabusResult {
        #if SWIFT_PACKAGE
        let bundle = Bundle.module
        #else
        let bundle = Bundle.main
        #endif
        guard let url = bundle.url(forResource: "VerifiedCalculus", withExtension: "json") else { throw DemoError.missing }
        return try JSONDecoder().decode(SyllabusResult.self, from: Data(contentsOf: url))
    }
    enum DemoError: LocalizedError {
        case missing
        var errorDescription: String? { "The bundled verified syllabus could not be found. Your current data has not been replaced." }
    }
}
