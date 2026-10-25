import XCTest
import PDFKit
import AppKit
@testable import SyllabusParser

final class ValidationTests: XCTestCase {
    private func source(_ quote: String, page: Int? = nil) -> SourceReference { .init(quote: quote, page: page) }
    private func validate(_ result: inout SyllabusResult, text: String) { ResultValidator.validate(&result, against: .pasted(text)) }

    func testUnrelatedMetadataQuotesAreRejected() {
        var result = SyllabusResult.empty
        let quote = source("Fall 2026 Syllabus", page: 1)
        result.courseCode = Fact(value: "MATH 141-005", source: quote)
        result.courseName = Fact(value: "Calculus II", source: quote)
        result.instructor = Fact(value: "Dr. Example", source: quote)
        result.semester = Fact(value: "Fall 2026", source: quote)
        ResultValidator.validate(&result, against: .init(pages: [.init(number: 1, text: quote.quote)]))
        XCTAssertNil(result.courseCode)
        XCTAssertNil(result.courseName)
        XCTAssertNil(result.instructor)
        XCTAssertEqual(result.semester?.value, "Fall 2026")
    }

    func testFinalGradeOnePercentAndLetterThresholdsAreNotWeights() {
        let text = "The following scale will be used to assign final grades.\nPercentage Range Grade\n93–100 A\n90–92.99 A-"
        var result = SyllabusResult.empty
        result.grading = [.init(category: "Final Grade", percentage: 1, source: source("The following scale will be used to assign final grades.")),
                          .init(category: "A", percentage: 93, source: source("93–100 A"))]
        validate(&result, text: text)
        XCTAssertTrue(result.grading.isEmpty)
    }

    func testAssessmentTableWeightsAreSupportedOnTheirOwnRows() {
        let rows = [("Quizzes", 20.0), ("Exam 1", 25.0), ("Exam 2", 25.0), ("Exam 3", 25.0), ("Participation/Attendance", 5.0)]
        let text = rows.map { "\($0.0)\t\(Int($0.1))%" }.joined(separator: "\n")
        var result = SyllabusResult.empty
        result.grading = rows.map { .init(category: $0.0, percentage: $0.1, source: source("\($0.0)\t\(Int($0.1))%")) }
        validate(&result, text: text)
        XCTAssertEqual(result.grading.compactMap(\.percentage), [20,25,25,25,5])
        XCTAssertFalse(result.warnings.contains { $0.contains("total") })
    }

    func testWrongTableRowAndExamNumberCannotSupplyWeight() {
        var result = SyllabusResult.empty
        let text = "Quizzes 20%\nExam 1 25%"
        result.grading = [.init(category: "Quizzes", percentage: 25, source: source(text)),
                          .init(category: "Exam 1", percentage: 1, source: source("Exam 1 25%"))]
        validate(&result, text: text)
        XCTAssertEqual(result.grading.count, 2)
        XCTAssertTrue(result.grading.allSatisfy { $0.percentage == nil })
        XCTAssertFalse(ResultValidator.supportsWeight(25, category: "Quizzes", quote: "Quizzes\n20%\nExam 1\n25%"))
    }

    func testExplicitTableRecoveryDoesNotDependOnModelJSON() {
        let text = "Component Weight\nQuizzes\t20%\nExam 1\t25%\nExam 2\t25%\nExam 3\t25%\nParticipation/Attendance\t5%\n93–100 A\nLate penalty 10%"
        let grades = ResultValidator.explicitWeights(in: text, page: 2)
        XCTAssertEqual(grades.compactMap(\.percentage), [20,25,25,25,5])
        XCTAssertTrue(grades.allSatisfy { $0.source.page == 2 })
    }

    func testExplicitMetadataKeepsContradictionsUnknown() {
        let text = "MATH 141-005: Calculus II\nFall 2026\nSpring 2027\nInstructor: Dr. Example."
        let result = ResultValidator.explicitMetadata(in: text, page: 1)
        XCTAssertEqual(result.courseCode?.value, "MATH 141-005")
        XCTAssertEqual(result.courseName?.value, "Calculus II")
        XCTAssertNil(result.semester)
        XCTAssertTrue(result.warnings.contains { $0.contains("Conflicting semester") })
    }

    func testUnknownValuesEncodeAsNullAndLegacyJSONStillDecodes() throws {
        var result = SyllabusResult.empty
        result.grading = [.init(category: "Project", percentage: nil, source: source("Project weight unspecified."))]
        result.events = [.init(title: "Project", dateText: nil, certainty: "unspecified", source: source("Project due date TBA."))]
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(result.json.utf8)) as? [String: Any])
        XCTAssertTrue(object["courseCode"] is NSNull)
        let grade = try XCTUnwrap((object["grading"] as? [[String: Any]])?.first)
        XCTAssertTrue(grade["percentage"] is NSNull)
        let event = try XCTUnwrap((object["events"] as? [[String: Any]])?.first)
        XCTAssertTrue(event["dateText"] is NSNull)
        XCTAssertEqual(try JSONDecoder().decode(SyllabusResult.self, from: Data(result.json.utf8)), result)
        let legacy = #"{"grading":[],"gradingPolicies":[],"events":[],"recurringRules":[],"warnings":[]}"#
        XCTAssertEqual(try JSONDecoder().decode(SyllabusResult.self, from: Data(legacy.utf8)), .empty)
    }

    func testEachTaskReceivesOnlyRelevantEvidence() {
        let text = "Instructor: Dr. Example.\nFall 2026\nPercentage Range Grade\n93–100 A\nQuizzes 20%\nExam 1 Tu Sep 29th\nClassroom: W338\nWeekly quizzes occur on Fridays.\nNo Calculators and No Formulas."
        let grading = ResultValidator.evidence(for: .grading, in: text)
        XCTAssertTrue(grading.contains("Quizzes 20%"))
        XCTAssertFalse(grading.contains("93–100"))
        let events = ResultValidator.evidence(for: .events, in: text)
        XCTAssertEqual(events, "Exam 1 Tu Sep 29th")
        XCTAssertEqual(ResultValidator.evidence(for: .recurrence, in: text), "Weekly quizzes occur on Fridays.")
        XCTAssertFalse(ResultValidator.evidence(for: .metadata, in: text).contains("Classroom"))
        XCTAssertFalse(ResultValidator.supportsWeight(5, category: "Quizzes", quote: "Quizzes -5%"))
    }

    func testInvalidPercentagesAreRemovedAndUnknownDoesNotBecomeZero() {
        var result = SyllabusResult.empty
        let text = "Homework 120%; Quizzes: weight -5%; Participation weight unspecified."
        result.grading = [.init(category: "Homework", percentage: 120, source: source("Homework 120%")),
                          .init(category: "Quizzes", percentage: -5, source: source("Quizzes: weight -5%")),
                          .init(category: "Participation", percentage: nil, source: source("Participation weight unspecified."))]
        validate(&result, text: text)
        XCTAssertEqual(result.grading.count, 3)
        XCTAssertTrue(result.grading.allSatisfy { $0.percentage == nil })
        XCTAssertTrue(result.warnings.contains { $0.contains("Invalid percentage") })
    }

    func testPartialKnownTotalWarnsWithoutFillingMissingCategories() {
        var result = SyllabusResult.empty
        result.grading = [.init(category: "Essays", percentage: 40, source: source("Essays 40%")),
                          .init(category: "Participation", percentage: 20, source: source("Participation 20%"))]
        validate(&result, text: "Essays 40%\nParticipation 20%")
        XCTAssertEqual(result.grading.count, 2)
        XCTAssertTrue(result.warnings.contains { $0.contains("total 60") })
        XCTAssertNil(result.courseCode)
    }

    func testInstructorAndTopicHeadingsAreRejectedAsEvents() {
        var result = SyllabusResult.empty
        let text = "Instructor: Dr. Example.\nSec8on Topic(s)\n5.4 Fundamental Theorem"
        result.events = [.init(title: "Instructor Information", dateText: "Fall 2026", certainty: "explicit", source: source("Instructor: Dr. Example.")),
                         .init(title: "Sec8on Topic(s)", dateText: "PDF page 4", certainty: "recurring", source: source("Sec8on Topic(s)"))]
        validate(&result, text: text)
        XCTAssertTrue(result.events.isEmpty)
    }

    func testExamDatesRemainYearlessAndTentativeComesFromSource() {
        var result = SyllabusResult.empty
        result.events = [.init(title: "Exam 1", dateText: "Tu Sep 29th", certainty: "explicit", source: source("Exam 1 Tu Sep 29th")),
                         .init(title: "Midterm", dateText: "March 11, 2027", certainty: "explicit", source: source("Midterm is tentatively scheduled for March 11, 2027."))]
        validate(&result, text: "Exam 1 Tu Sep 29th\nMidterm is tentatively scheduled for March 11, 2027.")
        XCTAssertEqual(result.events.count, 2)
        XCTAssertEqual(result.events[0].dateText, "Tu Sep 29th")
        XCTAssertEqual(result.events[1].certainty, "tentative")
    }

    func testInvalidCalendarDatesAndAmbiguousNumbers() {
        for date in ["February 30, 2026", "April 31", "February 29, 2025", "13/24/2026", "03/04/2026", "Fall 2026", "PDF page 4", "Monday", "March 0", "March 11, 0000"] {
            XCTAssertFalse(ResultValidator.dateIsValid(date), date)
        }
        for date in ["February 29", "February 29, 2028", "Tu Sep 29th", "Th Dec 3rd", "2026-10-24", "9/29/2026"] {
            XCTAssertTrue(ResultValidator.dateIsValid(date), date)
        }
    }

    func testUnsupportedYearAndDateAreUnknown() {
        var result = SyllabusResult.empty
        result.events = [.init(title: "Project", dateText: "September 24, 2026", certainty: "explicit", source: source("Project due September 24.")),
                         .init(title: "Exam 1", dateText: "Nov 3", certainty: "explicit", source: source("Exam 1 Sep 29; Exam 2 Nov 3"))]
        validate(&result, text: "Project due September 24.\nExam 1 Sep 29; Exam 2 Nov 3")
        XCTAssertEqual(result.events.count, 1)
        XCTAssertNil(result.events[0].dateText)
        XCTAssertEqual(result.events[0].certainty, "unspecified")
    }

    func testExplicitlyUnknownDeadlineIsPreserved() {
        var result = SyllabusResult.empty
        let text = "A final project will be due near the end of term; the exact date will be announced later."
        result.events = [.init(title: "final project", dateText: nil, certainty: "unspecified", source: source(text))]
        validate(&result, text: text)
        XCTAssertEqual(result.events.count, 1)
        XCTAssertNil(result.events[0].dateText)
    }

    func testPoliciesAndLocationsAreNotRecurringSchedules() {
        let invalid = ["Classroom: Building W338.", "No Calculators and No Formulas.", "Final Grade Scale", "Makeups for exams are only allowed under true emergencies.", "Quizzes."]
        var result = SyllabusResult.empty
        result.recurringRules = invalid.map { Fact(value: $0, source: source($0)) }
        validate(&result, text: invalid.joined(separator: "\n"))
        XCTAssertTrue(result.recurringRules.isEmpty)
    }

    func testFullRecurringScheduleSentencesAreAccepted() {
        let rules = ["Weekly quizzes will cover material from the previous week.", "Homework is assigned approximately every week.", "Class Schedule: Tu & Th 6 – 7:55 PM.", "Office hours Mondays 2-4 PM."]
        var result = SyllabusResult.empty
        result.recurringRules = rules.map { Fact(value: $0, source: source($0)) }
        validate(&result, text: rules.joined(separator: "\n"))
        XCTAssertEqual(result.recurringRules.count, 4)
    }

    func testRecurringHeadingCanOnlyRecoverVerbatimSupportedSchedule() {
        var result = SyllabusResult.empty
        result.recurringRules = [Fact(value: "Quizzes", source: source("Weekly quizzes will cover material from the previous week."))]
        validate(&result, text: "Weekly quizzes will cover material from the previous week.")
        XCTAssertEqual(result.recurringRules.first?.value, "Weekly quizzes will cover material from the previous week.")
    }

    func testSemanticPolicyDeduplicationPreservesScopesAndExceptions() {
        let policies = ["Calculators and formula sheets are not allowed in exams and quizzes.",
                        "No Calculators and No Formulas. Calculators and formula sheets are not allowed during exams and quizzes.",
                        "Calculators and formula sheets are permitted in exams and quizzes.",
                        "Calculators and formula sheets are not allowed in exams except with permission."]
        var result = SyllabusResult.empty
        result.gradingPolicies = policies.map { Fact(value: $0, source: source($0)) }
        validate(&result, text: policies.joined(separator: "\n"))
        XCTAssertEqual(result.gradingPolicies.count, 3)
    }

    func testPolicyDeduplicationPreservesWhichNumberBelongsToWhichActivity() {
        let policies = ["The lowest one quiz and two homework scores are dropped.", "The lowest two quiz and one homework scores are dropped."]
        var result = SyllabusResult.empty
        result.gradingPolicies = policies.map { Fact(value: $0, source: source($0)) }
        validate(&result, text: policies.joined(separator: "\n"))
        XCTAssertEqual(result.gradingPolicies.count, 2)
    }

    func testSourceRequiresExactPDFPageAndNonemptyQuote() {
        let document = SyllabusDocument(pages: [.init(number: 2, text: "Exam 1 October 15")])
        XCTAssertTrue(ResultValidator.verified(source("October 15", page: 2), in: document))
        XCTAssertFalse(ResultValidator.verified(source("October 15", page: 1), in: document))
        XCTAssertFalse(ResultValidator.verified(source("October 15"), in: document))
        XCTAssertFalse(ResultValidator.verified(source("", page: 2), in: document))
        XCTAssertFalse(ResultValidator.verified(source("Invented", page: 2), in: document))
    }

    func testConflictingDatesAndWeightsStayUnknown() {
        var result = SyllabusResult.empty
        let text = "Exam 1 March 11\nExam 1 March 18\nQuizzes 20%\nQuizzes 25%"
        result.events = (["March 11", "March 18"] as [String]).map { .init(title: "Exam 1", dateText: $0, certainty: "tentative", source: source("Exam 1 \($0)")) }
        result.grading = [20.0,25.0].map { .init(category: "Quizzes", percentage: $0, source: source("Quizzes \(Int($0))%")) }
        validate(&result, text: text)
        XCTAssertTrue(result.events.allSatisfy { $0.dateText == nil && $0.certainty == "unspecified" })
        XCTAssertEqual(result.grading.count, 1)
        XCTAssertNil(result.grading[0].percentage)
        XCTAssertTrue(result.warnings.contains { $0.contains("Conflicting dates") })
    }

    func testMetadataConflictsDoNotReturnFirstAnswer() {
        var result = SyllabusResult.empty
        var conflicts = Set<String>()
        for name in ["Dr. A", "Dr. B", "Dr. A"] {
            var incoming = SyllabusResult.empty
            incoming.instructor = Fact(value: name, source: source(name))
            SyllabusExtractor.merge(incoming, into: &result, conflicts: &conflicts)
        }
        XCTAssertNil(result.instructor)
        XCTAssertTrue(conflicts.contains("instructor"))
    }

    func testUnicodeNormalizationDoesNotRepairCorruptedWords() {
        XCTAssertTrue("Oﬃce\u{00A0}Hours".evidenceContains("Office Hours"))
        XCTAssertTrue(SyllabusDocument.hasDamagedText("Sec8on Topic(s)"))
        XCTAssertTrue(SyllabusDocument.hasDamagedText("prac]ce and Par]cipa]on"))
        XCTAssertFalse(SyllabusDocument.hasDamagedText("Room W338; Exam 8; x[8]; X axis"))
        XCTAssertFalse("prac]ce".evidenceContains("practice"))
    }

    func testOCRRowsKeepTableAndColumnCellsTogether() {
        let fragments: [SyllabusDocument.TextFragment] = [
            .init(text: "Exam 1", x: 0.1, y: 0.8, height: 0.02), .init(text: "25%", x: 0.6, y: 0.801, height: 0.02),
            .init(text: "Quizzes", x: 0.1, y: 0.7, height: 0.02), .init(text: "20%", x: 0.6, y: 0.7, height: 0.02)]
        XCTAssertEqual(SyllabusDocument.readingRows(fragments), "Exam 1\t25%\nQuizzes\t20%")
    }

    func testChunkBoundariesPreserveRowsAndNeverDropLongLines() {
        let text = "Quizzes 20%\nExam 1 25%\n" + String(repeating: "x", count: 100)
        let chunks = text.extractionChunks(maxLength: 30)
        XCTAssertTrue(chunks.contains { $0.contains("Quizzes 20%\n") })
        XCTAssertTrue(chunks.allSatisfy { $0.count <= 30 })
        XCTAssertEqual(chunks.joined(), text + "\n")
    }

    func testDiagnosticExportIncludesRawAndEffectiveTextForEveryPage() {
        let document = SyllabusDocument(pages: [.init(number: 1, text: "Section", rawText: "Sec8on", method: "Vision OCR"), .init(number: 2, text: "")])
        XCTAssertTrue(document.diagnosticText.contains("Sec8on"))
        XCTAssertTrue(document.diagnosticText.contains("Section"))
        XCTAssertTrue(document.diagnosticText.contains("Page 2"))
        XCTAssertFalse(document.displayText.contains("Raw PDFKit"))
    }

    func testSyntheticPDFImportPreservesPageNumbersAndTables() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".pdf")
        defer { try? FileManager.default.removeItem(at: url) }
        var box = CGRect(x: 0, y: 0, width: 612, height: 792)
        let context = try XCTUnwrap(CGContext(url as CFURL, mediaBox: &box, nil))
        context.beginPDFPage(nil)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
        for (row, label) in ["Component     Weight", "Quizzes           20%", "Exam 1            25%"].enumerated() {
            (label as NSString).draw(at: CGPoint(x: 50, y: 700 - row * 30), withAttributes: [.font: NSFont.systemFont(ofSize: 16)])
        }
        NSGraphicsContext.restoreGraphicsState()
        context.endPDFPage()
        context.beginPDFPage(nil)
        context.endPDFPage()
        context.closePDF()
        let document = try SyllabusDocument.pdf(at: url)
        XCTAssertEqual(document.pages.map(\.number), [1,2])
        XCTAssertTrue(document.pages[0].rawText.contains("Quizzes"))
        XCTAssertTrue(document.pages[0].text.contains("20%"))
        XCTAssertEqual(document.pages[0].method, "PDFKit")
        XCTAssertTrue(document.diagnosticText.contains("Page 2"))
    }

    // Optional integration checks use local files and the actual on-device model only.
    // Normal regressions above are deterministic and never require Apple Intelligence.
    func testLocalPDFDiagnostics() throws {
        guard let path = ProcessInfo.processInfo.environment["SYLLABUS_TEST_PDF"] else { throw XCTSkip("Set SYLLABUS_TEST_PDF for local PDF verification.") }
        let document = try SyllabusDocument.pdf(at: URL(fileURLWithPath: path))
        XCTAssertFalse(document.pages.isEmpty)
        if let output = ProcessInfo.processInfo.environment["SYLLABUS_DIAGNOSTIC_OUTPUT"] {
            try document.diagnosticText.write(toFile: output, atomically: true, encoding: .utf8)
        }
        for page in document.pages { print("PDF page \(page.number ?? 0): \(page.method), \(page.text.count) characters, \(page.warnings)") }
        // Expectations for the supplied four-page Calculus II syllabus.
        XCTAssertEqual(document.pages.count, 4)
        XCTAssertTrue(document.pages[0].text.contains("Analytic Geometry II"))
        XCTAssertTrue(document.pages[1].text.evidenceContains("Quizzes"))
        XCTAssertTrue(document.pages[1].text.contains("20%"))
        XCTAssertFalse(SyllabusDocument.hasDamagedText(document.pages[1].text))
    }

    func testOnDeviceExtractionWhenRequested() async throws {
        guard ProcessInfo.processInfo.environment["SYLLABUS_MODEL_SMOKE"] == "1" else { throw XCTSkip("Set SYLLABUS_MODEL_SMOKE=1 for on-device inference.") }
        guard ModelAvailability.isAvailable else { throw XCTSkip(ModelAvailability.message) }
        let document: SyllabusDocument
        if let path = ProcessInfo.processInfo.environment["SYLLABUS_TEST_PDF"] { document = try SyllabusDocument.pdf(at: URL(fileURLWithPath: path)) }
        else { document = .pasted(SampleSyllabi.simple.text) }
        let result = try await SyllabusExtractor.extract(document)
        print("ON-DEVICE RESULT:\n\(result.json)")
        if let output = ProcessInfo.processInfo.environment["SYLLABUS_MODEL_OUTPUT"] { try result.json.write(toFile: output, atomically: true, encoding: .utf8) }
        XCTAssertFalse(result.grading.contains { $0.category == "Final Grade" })
        XCTAssertFalse(result.events.contains { $0.title == "Instructor Information" })
        XCTAssertFalse(result.recurringRules.contains { $0.value == "Classroom" || $0.value == "No Calculators" })
        if ProcessInfo.processInfo.environment["SYLLABUS_TEST_PDF"] != nil {
            XCTAssertEqual(result.grading.compactMap(\.percentage).sorted(), [5,20,25,25,25])
            var dashboardCalendar = Calendar(identifier: .gregorian)
            dashboardCalendar.timeZone = TimeZone(identifier: "America/New_York")!
            let demoToday = dashboardCalendar.date(from: DateComponents(year: 2026, month: 10, day: 24, hour: 12))!
            let dashboard = DashboardSnapshot(result: result, now: demoToday, calendar: dashboardCalendar)
            XCTAssertEqual(dashboard.upcoming.map { $0.event.title }, ["Exam 2", "Exam 3"])
            XCTAssertEqual(dashboard.past.map { $0.event.title }, ["Exam 1"])
            let assistant = await SyllabusAssistant.answer("When is my next exam?", result: result, now: demoToday, calendar: dashboardCalendar, allowModel: false)
            XCTAssertTrue(assistant.text.contains("Exam 2"))
            XCTAssertEqual(assistant.mode, .unavailable)

            XCTAssertEqual(result.events.compactMap(\.dateText).count, 3)
            XCTAssertTrue(result.recurringRules.contains { $0.value.evidenceContains("Weekly quizzes") })
            XCTAssertEqual(result.courseCode?.value, "MATH 141-005")
            XCTAssertEqual(result.courseName?.value, "Calculus with Analytic Geometry II")
            XCTAssertEqual(result.gradeScale.count, 9)
            XCTAssertEqual(result.gradeScale.first(where: { $0.grade == "A" })?.lowerBound, 93)
            XCTAssertEqual(result.gradeScale.first(where: { $0.grade == "A-" })?.upperBound, 92.99)
            XCTAssertEqual(result.classSchedules.first?.days, ["Tuesday", "Thursday"])
            XCTAssertTrue(result.classSchedules.first?.timeText.contains("7:55 PM") == true)
            XCTAssertTrue(result.gradingPolicies.contains { $0.value.evidenceContains("Homework will not be collected") })
            XCTAssertTrue(result.gradingPolicies.contains { $0.value.evidenceContains("missed quiz") && $0.value.evidenceContains("one of your drops") })
            XCTAssertFalse(result.warnings.contains { $0.contains("grading response") && $0.contains("those fields remain unknown") })
        } else { XCTAssertEqual(result.grading.compactMap(\.percentage).sorted(), [10,25,30,35]) }
    }
}
