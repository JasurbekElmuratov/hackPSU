import Foundation

struct ResultValidator {
    static func validate(_ result: inout SyllabusResult, against document: SyllabusDocument?, reportMissingGrading: Bool = true) {
        var warnings = document?.warnings ?? []
        func warn(_ message: String) { warnings.append(message) }
        func supported(_ source: SourceReference) -> Bool {
            guard !source.quote.evidenceText.isEmpty, source.quote.count <= 600 else { return false }
            return document.map { verified(source, in: $0) } ?? true
        }
        func fact(_ item: Fact?, label: String) -> Fact? {
            guard let item else { return nil }
            guard supported(item.source), item.source.quote.evidenceContains(item.value),
                  !SyllabusDocument.hasDamagedText(item.value) else {
                warn("Rejected unsupported \(label); left unknown.")
                return nil
            }
            let quote = item.source.quote
            let meaningSupported: Bool
            switch label {
            case "course code":
                meaningSupported = item.value.range(of: #"^[A-Z]{2,}[ -]+\d{2,}(?:-\d+)?$"#, options: .regularExpression) != nil
                    && !matches(#"\b(prerequisite|textbook|isbn)"#, quote)
            case "course name":
                meaningSupported = quote.range(of: #"^[A-Z]{2,}[ -]+\d{2,}(?:-\d+)?\s*[:–—]"#, options: .regularExpression) != nil
                    || matches(#"\bcourse (name|title)\s*:"#, quote)
            case "semester": meaningSupported = matches(#"^(fall|spring|summer|winter|autumn)\s+\d{4}$"#, item.value)
            case "instructor": meaningSupported = matches(#"\b(instructor|lecturer|professor)\s*:"#, quote)
            default: meaningSupported = true
            }
            guard meaningSupported else { warn("Rejected \(label) without category-specific evidence; left unknown."); return nil }
            return item
        }
        result.courseCode = fact(result.courseCode, label: "course code")
        result.courseName = fact(result.courseName, label: "course name")
        result.semester = fact(result.semester, label: "semester")
        result.instructor = fact(result.instructor, label: "instructor")

        result.grading = result.grading.compactMap { item in
            guard supported(item.source), item.source.quote.evidenceContains(item.category),
                  isAssessment(item.category), !matches(#"\b(final grade|overall|total|scale|range|weight|component)\b"#, item.category),
                  !SyllabusDocument.hasDamagedText(item.category),
                  !matches(#"\b(ungraded|not graded|not collected|does not count)\b"#, item.source.quote) else {
                warn("Rejected unsupported grading category: \(item.category).")
                return nil
            }
            let hasOwnWeight = capturesAllPercentages(item.source.quote).contains { supportsWeight($0, category: item.category, quote: item.source.quote) }
            guard hasOwnWeight || matches(#"\b(grade|grading|weight|weighted|counts? for|worth)\b"#, item.source.quote) else {
                warn("Rejected category without grading evidence: \(item.category).")
                return nil
            }
            var accepted = item
            if let percentage = item.percentage {
                if !percentage.isFinite || !(0...100).contains(percentage) {
                    warn("Invalid percentage for \(item.category); left weight unknown.")
                    accepted.percentage = nil
                } else if !supportsWeight(percentage, category: item.category, quote: item.source.quote) {
                    warn("Unsupported percentage for \(item.category); left weight unknown.")
                    accepted.percentage = nil
                }
            }
            return accepted
        }
        // Repeated headings across pages are common. Conflicting weights remain unknown,
        // rather than keeping the first generated answer or double-counting a category.
        var grades: [GradeCategory] = []
        var conflictingGrades = Set<String>()
        for item in result.grading {
            let key = semanticKey(item.category)
            if let index = grades.firstIndex(where: { semanticKey($0.category) == key }) {
                if grades[index].percentage != item.percentage {
                    conflictingGrades.insert(key)
                    grades[index].percentage = nil
                    warn("Conflicting weights for \(item.category); left weight unknown.")
                }
            } else { grades.append(item) }
        }
        for index in grades.indices where conflictingGrades.contains(semanticKey(grades[index].category)) { grades[index].percentage = nil }
        result.grading = grades
        let known = result.grading.compactMap(\.percentage)
        if reportMissingGrading && known.count == result.grading.count && !known.isEmpty {
            let total = known.reduce(0, +)
            if abs(total - 100) > 0.01 { warn("Listed grading weights total \(total)%, rather than 100%. Review the source for missing categories or intentional exceptions.") }
        }
        if reportMissingGrading && result.grading.isEmpty { warn("No supported grading breakdown found; weights are unknown.") }

        result.gradingPolicies = deduplicate(result.gradingPolicies.compactMap { item in
            guard let item = fact(item, label: "policy"), isPolicy(item.value) else { return nil }
            return item
        })
        result.events = result.events.compactMap { item in
            guard supported(item.source), isAssessment(item.title) || matches(#"\b(break|holiday|cancell?ation|withdrawal|registration)\b"#, item.title),
                  item.source.quote.evidenceContains(item.title), !SyllabusDocument.hasDamagedText(item.title),
                  !matches(#"\b(information|topic|section|policy|dates|scale)\b"#, item.title) else {
                warn("Rejected unsupported academic event: \(item.title).")
                return nil
            }
            var accepted = item
            guard item.certainty != "recurring" else {
                warn("Rejected recurring activity from academic events: \(item.title).")
                return nil
            }
            let date = item.dateText?.trimmingCharacters(in: .whitespacesAndNewlines)
            if let date, !date.isEmpty {
                guard dateIsValid(date), sameEventRow(title: item.title, date: date, quote: item.source.quote) else {
                    warn("Rejected invalid, ambiguous, or unsupported date for \(item.title); left date unknown.")
                    // Keep an undated event only if its source actually schedules it.
                    guard schedulesEvent(item.source.quote) else { return nil }
                    accepted.dateText = nil
                    accepted.certainty = "unspecified"
                    return accepted
                }
                accepted.dateText = date
                accepted.certainty = matches(#"\b(tentative(ly)?|planned|subject to change|provisional(ly)?)\b"#, item.source.quote) ? "tentative" : "explicit"
            } else {
                guard schedulesEvent(item.source.quote) else {
                    warn("Rejected event without scheduling evidence: \(item.title).")
                    return nil
                }
                accepted.dateText = nil
                accepted.certainty = "unspecified"
            }
            return accepted
        }
        var events: [AcademicEvent] = []
        for item in result.events {
            if !events.contains(where: { semanticKey($0.title) == semanticKey(item.title) && $0.dateText?.evidenceText.lowercased() == item.dateText?.evidenceText.lowercased() }) { events.append(item) }
        }
        let grouped = Dictionary(grouping: events, by: { semanticKey($0.title) })
        for (title, entries) in grouped where Set(entries.compactMap(\.dateText)).count > 1 {
            warn("Conflicting dates for \(title); all conflicting dates left unknown. Review the cited pages.")
            for index in events.indices where semanticKey(events[index].title) == title {
                events[index].dateText = nil
                events[index].certainty = "unspecified"
            }
        }
        result.events = events
        result.recurringRules = deduplicate(result.recurringRules.compactMap { item in
            guard var accepted = fact(item, label: "recurring activity") else { return nil }
            // A model sometimes copies only a heading as the value while citing the
            // actual schedule. Recover only the verbatim cited rule, never a paraphrase.
            if !isRecurring(accepted.value), isRecurring(accepted.source.quote) {
                accepted.value = accepted.source.quote
            }
            guard isRecurring(accepted.value) else {
                warn("Rejected recurring rule without an activity and explicit cadence: \(item.value).")
                return nil
            }
            return accepted
        })
        var thresholds: [GradeThreshold] = []
        for item in result.gradeScale {
            guard supported(item.source), explicitGradeScale(in: item.source.quote, page: item.source.page, origin: item.source.textOrigin).contains(item) else {
                warn("Rejected unsupported letter-grade threshold: \(item.grade).")
                continue
            }
            if !thresholds.contains(where: { $0.grade == item.grade && $0.lowerBound == item.lowerBound && $0.upperBound == item.upperBound && $0.lowerInclusive == item.lowerInclusive && $0.upperInclusive == item.upperInclusive }) { thresholds.append(item) }
        }
        for (grade, values) in Dictionary(grouping: thresholds, by: \.grade) where values.count > 1 {
            warn("Conflicting letter-grade thresholds for \(grade); review the cited rows.")
        }
        result.gradeScale = thresholds
        var schedules: [ClassSchedule] = []
        for item in result.classSchedules {
            guard supported(item.source), item.source.textOrigin == nil,
                  explicitClassSchedules(in: item.source.quote, page: item.source.page).contains(item) else {
                warn("Rejected unsupported class schedule.")
                continue
            }
            if !schedules.contains(where: { $0.days == item.days && $0.timeText.evidenceText == item.timeText.evidenceText }) { schedules.append(item) }
        }
        result.classSchedules = schedules
        result.warnings = Array(Set(warnings)).sorted()
    }

    enum EvidenceTask { case metadata, grading, policies, events, recurrence }

    static func evidence(for task: EvidenceTask, in text: String) -> String {
        if task == .policies { return policySentences(in: text).joined(separator: "\n") }
        return text.components(separatedBy: .newlines).filter { line in
            switch task {
            case .metadata:
                return !matches(#"\b(prerequisite|textbook|isbn)"#, line) &&
                    (line.range(of: #"^[A-Z]{2,}[ -]+\d{2,}(?:-\d+)?\b"#, options: .regularExpression) != nil ||
                     matches(#"\b(fall|spring|summer|winter|autumn)\s+\d{4}\b|\b(instructor|lecturer|professor)\s*:"#, line))
            case .grading:
                return isAssessment(line) && matches(#"\d+(?:\.\d+)?\s*(%|percent\b)"#, line)
            case .policies:
                return isPolicy(line)
            case .events:
                let calendar = matches(#"\b(jan(?:uary)?|feb(?:ruary)?|mar(?:ch)?|apr(?:il)?|may|jun(?:e)?|jul(?:y)?|aug(?:ust)?|sep(?:t(?:ember)?)?|oct(?:ober)?|nov(?:ember)?|dec(?:ember)?)\.?\s+\d{1,2}|\b\d{1,4}[/-]\d{1,2}"#, line)
                return isAssessment(line) && !isPolicy(line) && (calendar || (schedulesEvent(line) && !isRecurring(line)))
            case .recurrence:
                return isRecurring(line)
            }
        }.joined(separator: "\n")
    }

    static func explicitWeights(in text: String, page: Int?) -> [GradeCategory] {
        let pattern = #"^\s*(?:Grading:\s*)?([A-Za-z][A-Za-z0-9 /&()\-]*?)\s*[:–—-]?\s+(\d+(?:\.\d+)?)\s*%[.]?\s*$"#
        return text.components(separatedBy: CharacterSet(charactersIn: "\n;," )).compactMap { row in
            guard let parts = captures(pattern, row), isAssessment(parts[0]), !matches(#"\b(extra credit|penalty|late|range|scale|total|final grade)\b"#, row),
                  let weight = Double(parts[1]), (0...100).contains(weight), !SyllabusDocument.hasDamagedText(parts[0]) else { return nil }
            return GradeCategory(category: parts[0], percentage: weight,
                                 source: SourceReference(quote: row.trimmingCharacters(in: .whitespaces), page: page))
        }
    }

    static func explicitGradeScale(in text: String, page: Int?, origin: SourceTextOrigin? = nil) -> [GradeThreshold] {
        let number = #"\d+(?:\.\d+)?"#
        // Range-first and grade-first rows are supported without filling gaps or
        // reconstructing a grade whose letter was lost in OCR.
        let rangeText = "(?:" + number + #"\s*[–—-]\s*"# + number + "|(?:(?i:under|below|less than|at most|up to|at least|above|over)|[<>]=?|[≤≥])\\s*" + number + ")"
        return text.components(separatedBy: .newlines).compactMap { line in
            let row = line.trimmingCharacters(in: .whitespaces)
            let rangeFirst = captures("^(" + rangeText + #")\s+([A-F][+−-]?)$"#, row)
            let gradeFirst = captures(#"^([A-F][+−-]?)\s*(?:[:=]|\s)\s*("# + rangeText + ")$", row)
            guard let parts = rangeFirst ?? gradeFirst.map({ [$0[1], $0[0]] }) else { return nil }
            let literal = parts[0]
            let normalized = literal.replacingOccurrences(of: "≤", with: "<=").replacingOccurrences(of: "≥", with: ">=")
            var lower: Double?, upper: Double?, lowerInclusive: Bool?, upperInclusive: Bool?
            if let values = captures("^(" + number + #")\s*[–—-]\s*("# + number + ")$", normalized),
               let first = Double(values[0]), let second = Double(values[1]), first <= second {
                lower = first; upper = second; lowerInclusive = true; upperInclusive = true
            } else if let values = captures("(?i)^(under|below|less than|at most|up to|at least|above|over|[<>]=?)\\s*(" + number + ")$", normalized), let bound = Double(values[1]) {
                let relation = values[0].lowercased()
                if ["under", "below", "less than", "at most", "up to", "<", "<="].contains(relation) {
                    upper = bound; upperInclusive = ["at most", "up to", "<="].contains(relation)
                } else { lower = bound; lowerInclusive = ["at least", ">="].contains(relation) }
            } else { return nil }
            guard [lower, upper].compactMap({ $0 }).allSatisfy({ $0.isFinite && (0...100).contains($0) }) else { return nil }
            return GradeThreshold(grade: parts[1], rangeText: literal, lowerBound: lower, upperBound: upper,
                                  lowerInclusive: lowerInclusive, upperInclusive: upperInclusive,
                                  source: SourceReference(quote: row, page: page, textOrigin: origin))
        }
    }

    static func explicitClassSchedules(in text: String, page: Int?) -> [ClassSchedule] {
        let time = #"\d{1,2}(?::\d{2})?\s*(?:[APap][Mm])?\s*[–—-]\s*\d{1,2}(?::\d{2})?\s*(?:[APap][Mm])?"#
        let pattern = #"(?i)^(?:[•*]\s*)?(?:class (?:schedule|meetings?|times?|meets)|classes|lectures?|meeting times?)\s*:?\s*(?:on\s+)?(.+?)\s+("# + time + #")[.]?\s*$"#
        let days: [String: String] = ["m": "Monday", "mon": "Monday", "monday": "Monday", "mondays": "Monday",
            "tu": "Tuesday", "tue": "Tuesday", "tues": "Tuesday", "tuesday": "Tuesday", "tuesdays": "Tuesday",
            "w": "Wednesday", "wed": "Wednesday", "wednesday": "Wednesday", "wednesdays": "Wednesday",
            "th": "Thursday", "thu": "Thursday", "thur": "Thursday", "thursday": "Thursday", "thursdays": "Thursday",
            "f": "Friday", "fri": "Friday", "friday": "Friday", "fridays": "Friday",
            "sat": "Saturday", "saturday": "Saturday", "saturdays": "Saturday", "sun": "Sunday", "sunday": "Sunday", "sundays": "Sunday"]
        return text.components(separatedBy: .newlines).compactMap { line in
            let row = line.trimmingCharacters(in: .whitespaces)
            guard let parts = captures(pattern, row) else { return nil }
            let tokens = parts[0].lowercased().components(separatedBy: CharacterSet.letters.inverted).filter { !$0.isEmpty && $0 != "and" }
            guard !tokens.isEmpty, tokens.allSatisfy({ days[$0] != nil }),
                  parts[0].rangeOfCharacter(from: .decimalDigits) == nil else { return nil }
            // Do not interpret day ranges, alternatives, multiple time slots, or malformed clocks.
            let separators = parts[0].replacingOccurrences(of: #"(?i)\b[a-z]+\b"#, with: "", options: .regularExpression)
            guard separators.allSatisfy({ $0.isWhitespace || ",&/.".contains($0) }) else { return nil }
            let clocks = parts[1].components(separatedBy: CharacterSet(charactersIn: "-–—"))
            guard clocks.count == 2, clocks.allSatisfy({ clock in
                guard let fields = captures(#"(?i)^\s*(\d{1,2})(?::(\d{2}))?\s*([AP]M)?\s*$"#, clock), let hour = Int(fields[0]) else { return false }
                let minute = Int(fields[1]) ?? 0
                return (0...59).contains(minute) && (fields[2].isEmpty ? (0...23).contains(hour) : (1...12).contains(hour))
            }) else { return nil }
            var seen = Set<String>()
            return ClassSchedule(days: tokens.compactMap { days[$0] }.filter { seen.insert($0).inserted }, timeText: parts[1],
                                 source: SourceReference(quote: row, page: page))
        }
    }

    static func policySentences(in text: String) -> [String] {
        // Join wrapped prose, but never join a header/table/schedule to a policy.
        var paragraphs: [String] = []
        var lines: [String] = []
        func flush() {
            if !lines.isEmpty { paragraphs.append(lines.joined(separator: " ")); lines = [] }
        }
        for line in text.components(separatedBy: .newlines) {
            let row = line.trimmingCharacters(in: .whitespaces)
            let heading = matches(#"(?i)^(grade scale|grading(?: scale)?|assessment method|component\s+weight|percentage range\s+grade|course policies(?: and procedures)?|class information|exam dates|assessment\s+date)$"#, row)
            let identity = row.range(of: #"^[A-Z]{2,}[ -]+\d{2,}(?:-\d+)?\s*[:–—]"#, options: .regularExpression) != nil
            let tableOrMeeting = !explicitWeights(in: row, page: nil).isEmpty || !explicitGradeScale(in: row, page: nil).isEmpty || !explicitClassSchedules(in: row, page: nil).isEmpty
            if row.isEmpty || heading || identity || tableOrMeeting { flush() }
            else { lines.append(row) }
        }
        flush()
        var sentences: [String] = []
        for prose in paragraphs {
            prose.enumerateSubstrings(in: prose.startIndex..., options: .bySentences) { sentence, _, _, _ in
                guard let sentence else { return }
                var trimmed = sentence.trimmingCharacters(in: .whitespacesAndNewlines)
                // Remove only a genuinely redundant label, preserving a subject that
                // would otherwise be lost (e.g. "Homework: It is not collected").
                if let colon = trimmed.firstIndex(of: ":") {
                    let label = trimmed[..<colon].trimmingCharacters(in: .whitespaces)
                    let rest = trimmed[trimmed.index(after: colon)...].trimmingCharacters(in: .whitespaces)
                    if !label.isEmpty, label.split(separator: " ").count <= 4,
                       rest.lowercased().hasPrefix(label.lowercased() + " ") { trimmed = rest }
                }
                if isPolicy(trimmed) { sentences.append(trimmed) }
            }
        }
        return sentences
    }

    static func policyFacts(_ models: [ModelFact], in document: SyllabusDocument) -> [Fact] {
        models.flatMap { model -> [Fact] in
            let reference = SourceReference(quote: model.quote, page: document.pages.first?.number)
            guard model.quote.count <= 600, verified(reference, in: document), model.quote.evidenceContains(model.value) else { return [] }
            // Keep each substantive sentence of the model-selected evidence. This
            // preserves qualifications and distinct assertions that a short value omitted.
            return policySentences(in: model.quote).compactMap { sentence in
                let source = SourceReference(quote: sentence, page: reference.page)
                return verified(source, in: document) ? Fact(value: sentence, source: source) : nil
            }
        }
    }

    static func uncoveredWeightEvidence(in text: String) -> String {
        evidence(for: .grading, in: text).components(separatedBy: .newlines).filter { row in
            let parsed = explicitWeights(in: row, page: nil)
            return parsed.isEmpty || parsed.count != capturesAllPercentages(row).count
        }.joined(separator: "\n")
    }

    static func explicitMetadata(in text: String, page: Int?) -> SyllabusResult {
        var result = SyllabusResult.empty
        var conflicts = Set<String>()
        for line in text.components(separatedBy: .newlines) {
            let row = line.trimmingCharacters(in: .whitespaces)
            let source = SourceReference(quote: row, page: page)
            var candidate = SyllabusResult.empty
            if let parts = captures(#"^([A-Z]{2,}[ -]+\d{2,}(?:-\d+)?)\s*[:–—]\s*(.+)$"#, row) {
                candidate.courseCode = Fact(value: parts[0], source: source)
                candidate.courseName = Fact(value: parts[1], source: source)
            }
            if let parts = captures(#"(?i)\b((?:Fall|Spring|Summer|Winter|Autumn)\s+\d{4})\b"#, row) {
                candidate.semester = Fact(value: parts[0], source: source)
            }
            if let parts = captures(#"(?i)^(?:[•*]\s*)?Instructor:\s*(.+?)[.]?$"#, row) {
                candidate.instructor = Fact(value: parts[0], source: source)
            }
            SyllabusExtractor.merge(candidate, into: &result, conflicts: &conflicts)
        }
        return result
    }

    private static func capturesAllPercentages(_ text: String) -> [Double] {
        let regex = try! NSRegularExpression(pattern: #"(\d+(?:\.\d+)?)\s*%"#)
        return regex.matches(in: text, range: NSRange(text.startIndex..., in: text)).compactMap { match in
            Range(match.range(at: 1), in: text).flatMap { Double(text[$0]) }
        }
    }

    static func verified(_ source: SourceReference, in document: SyllabusDocument) -> Bool {
        guard !source.quote.evidenceText.isEmpty else { return false }
        return document.pages.contains { page in
            guard source.page == page.number else { return false }
            if source.textOrigin == .rawPDFText {
                return page.number != nil && page.rawText.evidenceContains(source.quote)
            }
            return page.text.evidenceContains(source.quote)
        }
    }

    static func supportsWeight(_ percentage: Double, category: String, quote: String) -> Bool {
        // A label and a percent appearing somewhere in a table is insufficient. Require
        // direct attribution within one row/clause, never across line or column labels.
        let escaped = NSRegularExpression.escapedPattern(for: category.evidenceText)
        let pattern = "(?i)" + escaped + #"\s*(?::|\(|[–—]|-\s+)?\s*(?:(?:counts? for|is worth|worth|weight(?:ed)?|contributes?|accounts? for|is)\s*)?([0-9]+(?:\.[0-9]+)?)\s*(?:%|percent\b)"#
        for line in quote.components(separatedBy: .newlines) {
            let text = line.evidenceText
            guard let regex = try? NSRegularExpression(pattern: pattern) else { return false }
            for match in regex.matches(in: text, range: NSRange(text.startIndex..., in: text)) {
                if let range = Range(match.range(at: 1), in: text), let number = Double(text[range]), abs(number - percentage) < 0.00001 { return true }
            }
        }
        return false
    }

    private static func sameEventRow(title: String, date: String, quote: String) -> Bool {
        for row in quote.components(separatedBy: .newlines) {
            let text = row.evidenceText.lowercased()
            guard let titleRange = text.range(of: title.evidenceText.lowercased()),
                  let dateRange = text.range(of: date.evidenceText.lowercased()) else { continue }
            let gap: String
            if titleRange.upperBound <= dateRange.lowerBound { gap = String(text[titleRange.upperBound..<dateRange.lowerBound]) }
            else if dateRange.upperBound <= titleRange.lowerBound { gap = String(text[dateRange.upperBound..<titleRange.lowerBound]) }
            else { continue }
            // Stop cross-associations like "Exam 1 Sep 29; Exam 2 Nov 3" and
            // unconnected columns. Only schedule-linking words may intervene.
            let allowed = #"(?i)\b(is|on|due|by|at|will|be|held|scheduled|for|tentative|tentatively|planned|date|deadline|the|report|exam)\b|[\s:.,()\-–—]"#
            if gap.count < 100 && gap.replacingOccurrences(of: allowed, with: "", options: .regularExpression).isEmpty { return true }
        }
        return false
    }

    private static func schedulesEvent(_ quote: String) -> Bool {
        isAssessment(quote) && matches(#"\b(due|scheduled|deadline|tba|tbd|announced|date (?:is )?(?:unknown|unspecified|not set))\b"#, quote)
            && !matches(#"\b(no |not |never |make[ -]?up|makeups|policy|allowed|prohibited)\b"#, quote)
    }

    static func dateIsValid(_ value: String) -> Bool {
        let months = ["jan": 1, "feb": 2, "mar": 3, "apr": 4, "may": 5, "jun": 6,
                      "jul": 7, "aug": 8, "sep": 9, "oct": 10, "nov": 11, "dec": 12]
        let text = value.evidenceText.lowercased()
        let named = #"^(?:(?:mon(?:day)?|m|tue(?:s(?:day)?)?|tu|wed(?:nesday)?|w|thu(?:rs(?:day)?)?|th|fri(?:day)?|f|sat(?:urday)?|sun(?:day)?)[.,]?\s+)?(jan(?:uary)?|feb(?:ruary)?|mar(?:ch)?|apr(?:il)?|may|jun(?:e)?|jul(?:y)?|aug(?:ust)?|sep(?:t(?:ember)?)?|oct(?:ober)?|nov(?:ember)?|dec(?:ember)?)[.]?\s+(\d{1,2})(?:st|nd|rd|th)?(?:,?\s+(\d{4}))?[.]?$"#
        if let groups = captures(named, text), let month = months[String(groups[0].prefix(3))], let day = Int(groups[1]) {
            return validComponents(year: Int(groups[2]), month: month, day: day)
        }
        if let groups = captures(#"^(\d{4})-(\d{1,2})-(\d{1,2})$"#, text), let year = Int(groups[0]), let month = Int(groups[1]), let day = Int(groups[2]) {
            return validComponents(year: year, month: month, day: day)
        }
        if let groups = captures(#"^(\d{1,2})/(\d{1,2})(?:/(\d{4}))?$"#, text), let month = Int(groups[0]), let day = Int(groups[1]) {
            // 03/04 cannot tell us March 4 vs April 3. Do not guess a locale.
            guard day > 12 || month == day else { return false }
            return validComponents(year: Int(groups[2]), month: month, day: day)
        }
        return false
    }
    private static func validComponents(year: Int?, month: Int, day: Int) -> Bool {
        guard (1...12).contains(month), (1...31).contains(day), year == nil || (1...9999).contains(year!) else { return false }
        let calendar = Calendar(identifier: .gregorian)
        // Leap-year sentinel tests a yearless Feb 29 without inventing a year in output.
        let components = DateComponents(year: year ?? 2000, month: month, day: day)
        guard let date = calendar.date(from: components) else { return false }
        let checked = calendar.dateComponents([.year, .month, .day], from: date)
        return checked.year == components.year && checked.month == month && checked.day == day
    }
    private static func captures(_ pattern: String, _ text: String) -> [String]? {
        guard let regex = try? NSRegularExpression(pattern: pattern), let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) else { return nil }
        return (1..<match.numberOfRanges).map { Range(match.range(at: $0), in: text).map { String(text[$0]) } ?? "" }
    }
    private static func matches(_ pattern: String, _ text: String) -> Bool {
        text.range(of: pattern, options: [.regularExpression, .caseInsensitive]) != nil
    }
    private static func isAssessment(_ text: String) -> Bool {
        matches(#"\b(exams?|midterms?|final(?: exam)?|quizzes|quiz|tests?|projects?|assignments?|homework|essays?|papers?|presentations?|participation|attendance|labs?|reports?|problem sets?|portfolios?|exercises?|discussions?|reading checks?)\b"#, text)
    }
    private static func isPolicy(_ text: String) -> Bool {
        matches(#"\b(drop(?:ped|s)?|lowest|late|make[ -]?up|makeups|extra credit|calculators?|formula(?:s| sheets)?|penalt(?:y|ies)|allowed|permitted|prohibited|forbidden|collect(?:ed|ion)?|submitted|submission|ungraded|count(?:s)? (?:as|toward))\b"#, text)
            && text.evidenceText.split(separator: " ").count >= 4
    }
    private static func isRecurring(_ text: String) -> Bool {
        let activity = isAssessment(text) || matches(#"\b(class(?:es)?|lectures?|office hours|seminars?|tutorials?)\b"#, text)
        let explicitCadence = matches(#"\b(weekly|daily|biweekly|mondays|tuesdays|wednesdays|thursdays|fridays|saturdays|sundays)\b|\b(every|each)\s+(week|day|month|semester|term|class|session|other week|monday|tuesday|wednesday|thursday|friday|saturday|sunday)\b"#, text)
        let regularMeeting = matches(#"\b(class(?:es)?|lectures?|office hours|seminars?|tutorials?)\b"#, text)
            && matches(#"\b(mondays?|tuesdays?|wednesdays?|thursdays?|fridays?|mon|tue|tu|wed|thu|th|fri|m|w|f)\b"#, text)
        let cadence = explicitCadence || regularMeeting
        let prohibited = matches(#"\b(calculator|formula|not allowed|prohibited|forbidden|makeups?|make-up|grade scale|classroom|no|not|never)\b"#, text)
        return activity && cadence && !prohibited
    }

    static func semanticKey(_ value: String) -> String {
        var text = value.evidenceText.lowercased()
        // Drop a short redundant heading only when followed by a full substantive rule.
        if let period = text.firstIndex(of: "."), text[..<period].split(separator: " ").count <= 7,
           text[text.index(after: period)...].split(separator: " ").count >= 7 {
            text = String(text[text.index(after: period)...])
        }
        for (pattern, replacement) in [
            (#"\b(not allowed|not permitted|prohibited|forbidden)\b"#, "forbidden"),
            (#"\bformula sheets?\b"#, "formula"), (#"\bformulas\b"#, "formula"),
            (#"\bexaminations?\b"#, "exam"), (#"\bexams\b"#, "exam"),
            (#"\bquizzes\b"#, "quiz"), (#"\bcalculators\b"#, "calculator"),
            (#"\battend(?:ance)?\b"#, "attendance"),
            (#"\b(dropped|drops)\b"#, "drop"), (#"\bquiz scores?\b"#, "quiz"),
            (#"\btwo\b"#, "2"), (#"\bone\b"#, "1")
        ] { text = text.replacingOccurrences(of: pattern, with: replacement, options: .regularExpression) }
        let stopwords: Set<String> = ["a", "an", "the", "are", "is", "and", "in", "during", "on", "of", "to", "for"]
        let tokens = text.components(separatedBy: CharacterSet.alphanumerics.inverted).filter { !$0.isEmpty && !stopwords.contains($0) }
        // Preserve negations, numbers, scopes, and exceptions to avoid merging conflicts.
        return tokens.joined(separator: " ")
    }
    private static func deduplicate(_ facts: [Fact]) -> [Fact] {
        var keys = Set<String>()
        return facts.filter { keys.insert(semanticKey($0.value)).inserted }
    }
}
