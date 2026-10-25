import XCTest
import CoreGraphics
import PDFKit
#if canImport(AppKit)
import AppKit
#else
import UIKit
#endif
@testable import Studyday

@MainActor
final class IntegrationTests: XCTestCase {
    private func fixture(_ code: String = "BIO 210", weight: Double = 30) -> ImportedSyllabus {
        let text = """
        \(code): Laboratory Methods
        Fall 2026
        Instructor: Dr. Example.
        Exam 2 \(Int(weight))%
        Class Schedule: Mon & Wed 9-10 AM.
        Exam 2 October 29, 2026
        Weekly quizzes cover the material.
        A missed quiz counts toward dropped scores.
        """
        var result = ResultValidator.explicitMetadata(in: text, page: nil)
        result.grading = ResultValidator.explicitWeights(in: text, page: nil)
        result.classSchedules = ResultValidator.explicitClassSchedules(in: text, page: nil)
        result.events = [.init(title: "Exam 2", dateText: "October 29, 2026", certainty: "explicit", source: .init(quote: "Exam 2 October 29, 2026", page: nil))]
        result.recurringRules = [.init(value: "Weekly quizzes cover the material.", source: .init(quote: "Weekly quizzes cover the material.", page: nil))]
        return ImportedSyllabus(result: result, document: .pasted(text))
    }

    func testLocalWorkspaceDoesNotPretendToAuthenticateAnExternalAccount() async throws {
        let model = AppModel()
        XCTAssertFalse(model.isSignedIn)
        await model.startWorkspace(demo: false)
        XCTAssertEqual(model.session?.provider, .onDevice)
        XCTAssertEqual(model.session?.displayName, "Student")
        XCTAssertTrue(model.courses.isEmpty)
    }

    func testVerifiedDemoPreservesCanonicalDataAndIsExplicitlyLabeled() async throws {
        let model = AppModel()
        await model.startWorkspace(demo: true)
        let course = try XCTUnwrap(model.selectedCourse)
        XCTAssertTrue(course.isDemo)
        XCTAssertEqual(course.syllabus, try DemoSyllabus.load())
        XCTAssertEqual(course.exams.count, 3)
        XCTAssertTrue(course.quizzes.isEmpty)
        XCTAssertTrue(course.assignments.isEmpty)
        XCTAssertEqual(course.syllabus.gradeScale.count, 9)
        XCTAssertTrue(course.meetingTimes.contains("Tuesday and Thursday"))
        XCTAssertFalse(course.syllabus.events.contains { $0.title.contains("Final") })
        XCTAssertEqual(model.selectedTab, .home)
        try model.loadDemo()
        XCTAssertEqual(model.courses.count, 1)
    }

    func testRealURLAndCanonicalResultReachTheViewModelWithoutFilenameMocks() async throws {
        let imported = fixture("CHEM 320", weight: 40)
        let extractor = FixtureExtractor(imported)
        let model = AppModel(extractor: extractor)
        await model.startWorkspace(demo: false)
        let url = URL(fileURLWithPath: "/tmp/MATH141_looks_like_a_demo.pdf")
        await model.importSyllabus(url: url)
        XCTAssertEqual(extractor.urls, [url])
        XCTAssertEqual(model.selectedCourse?.code, "CHEM 320")
        XCTAssertEqual(model.selectedCourse?.syllabus, imported.result)
        XCTAssertEqual(model.selectedCourse?.isDemo, false)
        XCTAssertNil(model.pendingSyllabusName)
        XCTAssertFalse(model.isChatBusy)
    }

    func testCourseSelectionScopesChatAndKeepsModeAndSourceQuotes() async throws {
        let extractor = FixtureExtractor(fixture("BIO 210", weight: 30))
        let chat = RecordingChat()
        let model = AppModel(extractor: extractor, chat: chat)
        await model.startWorkspace(demo: false)
        await model.importSyllabus(url: URL(fileURLWithPath: "/tmp/biology.pdf"))
        let first = try XCTUnwrap(model.selectedCourseID)
        extractor.imported = fixture("CHEM 320", weight: 40)
        await model.importSyllabus(url: URL(fileURLWithPath: "/tmp/chemistry.pdf"))
        await model.send("How much is Exam 2 worth?")
        XCTAssertEqual(chat.courseCodes.last, "CHEM 320")
        XCTAssertTrue(model.messages.last?.text.contains("40%") == true)
        XCTAssertEqual(model.messages.last?.mode, .unavailable)
        XCTAssertFalse(model.messages.last?.sources.isEmpty ?? true)
        model.selectCourse(first)
        XCTAssertFalse(model.messages.contains { $0.text.contains("40%") })
        await model.send("How much is Exam 2 worth?")
        XCTAssertEqual(chat.courseCodes.last, "BIO 210")
        XCTAssertTrue(model.messages.last?.text.contains("30%") == true)
    }

    func testImportFailureNeverSubstitutesDemoDataOrAddsACourse() async throws {
        let extractor = FixtureExtractor(fixture())
        extractor.fail = true
        let model = AppModel(extractor: extractor)
        await model.startWorkspace(demo: false)
        await model.importSyllabus(url: URL(fileURLWithPath: "/tmp/not-readable.pdf"))
        XCTAssertTrue(model.courses.isEmpty)
        XCTAssertNotNil(model.chatError)
        XCTAssertTrue(model.messages.last?.text.contains("No course or sample data was substituted") == true)
    }

    func testDemoLoadingDoesNotReplaceAnImportedCourse() async throws {
        let model = AppModel(extractor: FixtureExtractor(fixture("CHEM 320")))
        await model.startWorkspace(demo: false)
        await model.importSyllabus(url: URL(fileURLWithPath: "/tmp/chemistry.pdf"))
        let realID = try XCTUnwrap(model.selectedCourseID)
        try model.loadDemo()
        XCTAssertEqual(model.courses.count, 2)
        XCTAssertEqual(model.courses.first { $0.id == realID }?.code, "CHEM 320")
        XCTAssertEqual(model.courses.first { $0.id == realID }?.isDemo, false)
        XCTAssertEqual(model.selectedCourse?.isDemo, true)
    }

    func testEditingValidatesAgainstTheImportedDocumentAndPreservesUnknownDates() async throws {
        let model = AppModel(extractor: FixtureExtractor(fixture()))
        await model.startWorkspace(demo: false)
        await model.importSyllabus(url: URL(fileURLWithPath: "/tmp/course.pdf"))
        let id = try XCTUnwrap(model.selectedCourseID)
        var changed = try XCTUnwrap(model.selectedCourse?.syllabus)
        changed.grading[0].percentage = 99
        changed.events[0].dateText = "October 30, 2026"
        let validated = try model.applyCorrections(courseID: id, json: changed.json)
        XCTAssertNil(validated.grading.first?.percentage)
        XCTAssertFalse(validated.events.contains { $0.dateText == "October 30, 2026" })
        XCTAssertEqual(validated.classSchedules.count, 1)
        XCTAssertTrue(validated.warnings.contains { $0.contains("percentage") })
        XCTAssertThrowsError(try model.applyCorrections(courseID: id, json: "invalid JSON"))
    }

    func testEndingWorkspacePreventsLateRepliesFromReappearing() async throws {
        let chat = SlowChat()
        let model = AppModel(extractor: FixtureExtractor(fixture()), chat: chat)
        await model.startWorkspace(demo: false)
        await model.importSyllabus(url: URL(fileURLWithPath: "/tmp/course.pdf"))
        let pending = Task { await model.send("How much is Exam 2 worth?") }
        while !model.isChatBusy { await Task.yield() }
        await model.endWorkspace()
        await pending.value
        XCTAssertNil(model.session)
        XCTAssertTrue(model.courses.isEmpty)
        XCTAssertFalse(model.messages.contains { $0.text.contains("stale reply") })
    }

    func testUnsupportedFilesAndQuestionsWithoutASyllabusAreHonest() async throws {
        do {
            _ = try await LocalSyllabusExtractor().extract(from: URL(fileURLWithPath: "/tmp/syllabus.docx"))
            XCTFail("Only PDF import is supported")
        } catch { XCTAssertTrue(error.localizedDescription.contains("PDF")) }
        let model = AppModel()
        await model.startWorkspace(demo: false)
        await model.send("When is my final exam?")
        XCTAssertTrue(model.messages.last?.text.contains("No syllabus is selected") == true)
        XCTAssertTrue(model.messages.last?.sources.isEmpty ?? false)
    }

    private func makePDF() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("MATH141-\(UUID().uuidString).pdf")
        var box = CGRect(x: 0, y: 0, width: 612, height: 792)
        let context = try XCTUnwrap(CGContext(url as CFURL, mediaBox: &box, nil))
        context.beginPDFPage(nil)
        #if canImport(AppKit)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
        let font = NSFont.systemFont(ofSize: 15)
        #else
        UIGraphicsPushContext(context)
        let font = UIFont.systemFont(ofSize: 15)
        #endif
        let rows = ["CHEM 320: Laboratory Methods", "Fall 2026", "Instructor: Dr. Example.", "Lab reports 65%", "Final Exam 35%", "Class Schedule: Mon & Wed 9-10 AM.", "Final Exam: December 15, 2026.", "Calculators and formula sheets are not allowed in exams."]
        for (index, row) in rows.enumerated() {
            (row as NSString).draw(at: CGPoint(x: 45, y: 700-index*35), withAttributes: [.font: font])
        }
        #if canImport(AppKit)
        NSGraphicsContext.restoreGraphicsState()
        #else
        UIGraphicsPopContext()
        #endif
        context.endPDFPage(); context.closePDF()
        return url
    }

    func testPlatformPDFAdapterReadsActualTextWithoutAModel() async throws {
        let url = try makePDF()
        defer { try? FileManager.default.removeItem(at: url) }
        let document = try SyllabusDocument.pdf(at: url)
        XCTAssertEqual(document.pages.count, 1)
        XCTAssertTrue(document.pages[0].text.contains("CHEM 320"))
        XCTAssertTrue(document.pages[0].text.contains("65%"))
        XCTAssertEqual(document.pages[0].number, 1)
    }

    #if os(iOS)
    func testImageOnlyPDFUsesTheUIKitVisionAdapter() async throws {
        let size = CGSize(width: 612, height: 792)
        let image = UIGraphicsImageRenderer(size: size).image { context in
            UIColor.white.setFill()
            context.fill(CGRect(origin: .zero, size: size))
            ("CHEM 320 Laboratory Methods" as NSString).draw(at: CGPoint(x: 45, y: 100), withAttributes: [.font: UIFont.systemFont(ofSize: 24), .foregroundColor: UIColor.black])
        }
        let pdf = PDFDocument()
        pdf.insert(try XCTUnwrap(PDFPage(image: image)), at: 0)
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".pdf")
        defer { try? FileManager.default.removeItem(at: url) }
        XCTAssertTrue(pdf.write(to: url))
        let document = try SyllabusDocument.pdf(at: url)
        XCTAssertEqual(document.pages.first?.method, "Vision OCR")
        XCTAssertTrue(document.pages.first?.rawText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == true)
        XCTAssertTrue(document.pages.first?.text.evidenceContains("CHEM 320 Laboratory Methods") == true)
    }
    #endif

    func testLivePDFExtractionAndAssistantWhenAvailable() async throws {
        guard ModelAvailability.isAvailable else { throw XCTSkip(ModelAvailability.message) }
        let url = try makePDF()
        defer { try? FileManager.default.removeItem(at: url) }
        let model = AppModel()
        await model.startWorkspace(demo: false)
        await model.importSyllabus(url: url)
        let course = try XCTUnwrap(model.selectedCourse, model.chatError ?? "No course was imported")
        XCTAssertEqual(course.code, "CHEM 320")
        XCTAssertEqual(course.syllabus.grading.compactMap(\.percentage).sorted(), [35,65])
        XCTAssertEqual(course.syllabus.classSchedules.first?.days, ["Monday", "Wednesday"])
        XCTAssertEqual(course.syllabus.events.count, 1)
        await model.send("How much is Final Exam worth?")
        XCTAssertTrue(model.messages.last?.text.contains("35%") == true)
        XCTAssertFalse(model.messages.last?.sources.isEmpty ?? true)
        await model.send("Are formula sheets allowed during an assessment?")
        XCTAssertEqual(model.messages.last?.mode, .localModel)
        XCTAssertFalse(model.messages.last?.sources.isEmpty ?? true)
    }
}

@MainActor
private final class FixtureExtractor: SyllabusExtractorProtocol {
    var imported: ImportedSyllabus
    var urls: [URL] = []
    var fail = false
    init(_ imported: ImportedSyllabus) { self.imported = imported }
    func extract(from url: URL) async throws -> ImportedSyllabus {
        urls.append(url)
        if fail { throw ServiceError.unavailable("The selected PDF could not be read.") }
        return imported
    }
}

@MainActor
private final class RecordingChat: ChatServiceProtocol {
    var courseCodes: [String] = []
    func reply(to userMessage: String, syllabus: SyllabusResult) async -> AssistantReply {
        courseCodes.append(syllabus.courseCode?.value ?? "unknown")
        return await SyllabusAssistant.answer(userMessage, result: syllabus, allowModel: false)
    }
}

@MainActor
private final class SlowChat: ChatServiceProtocol {
    func reply(to userMessage: String, syllabus: SyllabusResult) async -> AssistantReply {
        try? await Task.sleep(for: .milliseconds(30))
        return AssistantReply(text: "stale reply", sources: [], mode: .deterministic)
    }
}
