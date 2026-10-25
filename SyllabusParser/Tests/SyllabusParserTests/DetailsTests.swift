import XCTest
@testable import SyllabusParser

final class DetailsTests: XCTestCase {
    func testLetterGradeRowsKeepDecimalAndOpenBoundsSeparateFromWeights() throws {
        let text = "Grade scale\nA = 94.5–100\n90-94.49 A-\nBelow 52 F\nB >= 81"
        let scale = ResultValidator.explicitGradeScale(in: text, page: 3)
        XCTAssertEqual(scale.map(\.grade), ["A", "A-", "F", "B"])
        XCTAssertEqual(scale[0].lowerBound, 94.5)
        XCTAssertEqual(scale[0].upperBound, 100)
        XCTAssertEqual(scale[1].upperBound, 94.49)
        XCTAssertNil(scale[2].lowerBound)
        XCTAssertEqual(scale[2].upperBound, 52)
        XCTAssertEqual(scale[2].upperInclusive, false)
        XCTAssertEqual(scale[3].lowerBound, 81)
        XCTAssertEqual(scale[3].lowerInclusive, true)
        XCTAssertNil(scale[3].upperBound)
        XCTAssertTrue(scale.allSatisfy { $0.source.page == 3 })
        XCTAssertTrue(ResultValidator.explicitWeights(in: text, page: 3).isEmpty)
    }

    func testMalformedScaleRowsAreNotFilledInOrGuessed() {
        let text = "94–100\n100–90 A\n80–125 B\nQuizzes 20%\nChapter 8 C\n90-94.49 A-"
        let scale = ResultValidator.explicitGradeScale(in: text, page: nil)
        XCTAssertEqual(scale.map(\.grade), ["A-"])
        XCTAssertFalse(scale.contains { $0.grade == "A" })
    }

    func testRawTableFallbackRequiresExplicitOriginAndCorrectPage() throws {
        let raw = "Grade scale\n94–100 A\n90–93.99 A-"
        let effective = "Grade scale\n94-100\n90-93.99"
        let document = SyllabusDocument(pages: [.init(number: 4, text: effective, rawText: raw, method: "Vision OCR")])
        var result = SyllabusResult.empty
        result.gradeScale = ResultValidator.explicitGradeScale(in: raw, page: 4, origin: .rawPDFText)
        ResultValidator.validate(&result, against: document)
        XCTAssertEqual(result.gradeScale.count, 2)
        let reference = try XCTUnwrap(result.gradeScale.first?.source)
        XCTAssertEqual(reference.textOrigin, .rawPDFText)
        XCTAssertTrue(ResultValidator.verified(reference, in: document))
        XCTAssertFalse(ResultValidator.verified(.init(quote: reference.quote, page: 4), in: document))
        XCTAssertFalse(ResultValidator.verified(.init(quote: reference.quote, page: 5, textOrigin: .rawPDFText), in: document))
        XCTAssertFalse(ResultValidator.verified(.init(quote: raw, page: nil, textOrigin: .rawPDFText), in: .pasted(raw)))
        XCTAssertEqual(try JSONDecoder().decode(SyllabusResult.self, from: Data(result.json.utf8)), result)
        result.gradeScale[0].lowerBound = 91 // A manual edit cannot manufacture a threshold.
        ResultValidator.validate(&result, against: document)
        XCTAssertEqual(result.gradeScale.map(\.grade), ["A-"])
    }

    func testScaleDeduplicatesRepeatedRowsButFlagsConflicts() {
        let text = "A = 95–100\n95-100 A\n94–100 A"
        var result = SyllabusResult.empty
        result.gradeScale = ResultValidator.explicitGradeScale(in: text, page: nil)
        ResultValidator.validate(&result, against: .pasted(text))
        XCTAssertEqual(result.gradeScale.count, 2)
        XCTAssertTrue(result.warnings.contains { $0.contains("Conflicting letter-grade thresholds") })
    }

    func testExplicitMeetingScheduleExpandsOnlyWrittenDayAliases() throws {
        let text = "Class Schedule: Mon & Wed 9:10 - 10:25 AM.\nLectures: Fridays 14:00–15:20"
        let schedules = ResultValidator.explicitClassSchedules(in: text, page: 8)
        XCTAssertEqual(schedules.count, 2)
        XCTAssertEqual(schedules[0].days, ["Monday", "Wednesday"])
        XCTAssertEqual(schedules[0].timeText, "9:10 - 10:25 AM")
        XCTAssertEqual(schedules[1].days, ["Friday"])
        XCTAssertEqual(schedules[1].timeText, "14:00–15:20")
        XCTAssertEqual(schedules[0].source.page, 8)
        let missingMeridiem = ResultValidator.explicitClassSchedules(in: "Classes: Mon 9-10", page: nil)
        XCTAssertEqual(missingMeridiem.first?.timeText, "9-10")
    }

    func testSchedulesRejectOfficeLocationsDatesInvalidClocksAndDayRanges() {
        for row in ["Office hours: Mon 9-10 AM.", "Classroom: Monday Hall 9-10 AM.", "Exam Monday October 12 9-10 AM.",
                    "Class Schedule: Mon 9:99-10 AM.", "Class Schedule: Mon 29-30 PM.", "Class Schedule: Mon-Fri 9-10 AM.",
                    "Class Schedule: Mon 9-10 AM and Wed 2-3 PM."] {
            XCTAssertTrue(ResultValidator.explicitClassSchedules(in: row, page: 1).isEmpty, row)
        }
        let row = "Class Schedule: Mon & Wed 9:10 - 10:25 AM."
        var result = SyllabusResult.empty
        result.classSchedules = ResultValidator.explicitClassSchedules(in: row, page: nil)
        result.classSchedules[0].days = ["Friday"]
        ResultValidator.validate(&result, against: .pasted(row))
        XCTAssertTrue(result.classSchedules.isEmpty)
    }

    func testPolicyEvidenceRetainsCollectionStatusAndWrappedMissedWorkSentence() {
        let text = "Practice exercises will not be\ncollected. No make-up labs are offered. A missed lab\ncounts as one of the dropped scores."
        let units = ResultValidator.policySentences(in: text)
        XCTAssertEqual(units.count, 3)
        XCTAssertEqual(units[0], "Practice exercises will not be collected.")
        XCTAssertEqual(units[2], "A missed lab counts as one of the dropped scores.")
        XCTAssertTrue(ResultValidator.evidence(for: .policies, in: text).contains("will not be collected"))
    }

    func testPolicySentencesDoNotAbsorbHeadersTablesOrUnrelatedMissedTopics() {
        let text = """
        BIO 210: Laboratory Skills
        Class Schedule: Mondays 10-11 AM.
        Lab reports 75%
        Final exam 25%
        Grade scale
        A = 94–100
        Below 52 F
        Course Policies and Procedures
        Practice exercises will not be collected.
        Students catch up on missed topics.
        Calculators: Calculators are forbidden during exams.
        """
        XCTAssertEqual(ResultValidator.policySentences(in: text), ["Practice exercises will not be collected.", "Calculators are forbidden during exams."])
    }

    func testModelSelectedPolicyQuotePreservesDistinctAssertionsAndNegation() {
        let text = "No make-up labs are offered. A missed lab counts as one of the dropped scores."
        let models = [ModelFact(value: "No make-up labs are offered.", quote: text)]
        let facts = ResultValidator.policyFacts(models, in: .pasted(text))
        XCTAssertEqual(facts.map(\.value), ["No make-up labs are offered.", "A missed lab counts as one of the dropped scores."])
        var result = SyllabusResult.empty
        result.gradingPolicies = facts
        ResultValidator.validate(&result, against: .pasted(text))
        XCTAssertEqual(result.gradingPolicies.count, 2)
        let collection = "Practice exercises will not be collected unless a review is requested."
        let preserved = ResultValidator.policyFacts([ModelFact(value: "Practice exercises", quote: collection)], in: .pasted(collection))
        XCTAssertEqual(preserved.first?.value, collection)
        XCTAssertTrue(ResultValidator.policyFacts([ModelFact(value: "Practice exercises will be collected.", quote: collection)], in: .pasted(collection)).isEmpty)
    }

    func testModelPolicyQuotesCannotCrossPagesOrInventRules() {
        let text = "Practice exercises will not be collected."
        let document = SyllabusDocument(pages: [.init(number: 2, text: text)])
        let facts = ResultValidator.policyFacts([ModelFact(value: text, quote: text)], in: document)
        XCTAssertEqual(facts.first?.source.page, 2)
        XCTAssertTrue(ResultValidator.policyFacts([ModelFact(value: "Late work loses 7%.", quote: "Late work loses 7%.")], in: document).isEmpty)
    }

    func testCoveredTableRowsDoNotRequestRedundantModelExtraction() {
        let table = "Lab reports 65%\nFinal exam 35%"
        XCTAssertEqual(ResultValidator.uncoveredWeightEvidence(in: table), "")
        let prose = "Presentations contribute 15% of the overall course grade."
        XCTAssertEqual(ResultValidator.uncoveredWeightEvidence(in: table + "\n" + prose), prose)
    }

    func testWeightFailureWarningDescribesWhatWasActuallyRetained() {
        let recovered = SyllabusExtractor.modelFailureWarning(task: .grading, page: 6, retainedTableWeights: 3)
        XCTAssertTrue(recovered.contains("Retained 3 validated deterministic table"))
        XCTAssertFalse(recovered.contains("remain unknown"))
        let missing = SyllabusExtractor.modelFailureWarning(task: .grading, page: 6, retainedTableWeights: 0)
        XCTAssertTrue(missing.contains("weights remain unknown"))
        let policies = SyllabusExtractor.modelFailureWarning(task: .policies, page: 6, retainedTableWeights: 3)
        XCTAssertFalse(policies.contains("weights remain unknown"))
    }

    func testLegacyJSONDefaultsNewDetailsToEmptyArrays() throws {
        let legacy = #"{"grading":[],"gradingPolicies":[],"events":[],"recurringRules":[],"warnings":[]}"#
        let result = try JSONDecoder().decode(SyllabusResult.self, from: Data(legacy.utf8))
        XCTAssertTrue(result.gradeScale.isEmpty)
        XCTAssertTrue(result.classSchedules.isEmpty)
    }

    func testSyntheticWrittenPoliciesOnDeviceWhenRequested() async throws {
        guard ProcessInfo.processInfo.environment["SYLLABUS_POLICY_SMOKE"] == "1" else { throw XCTSkip("Set SYLLABUS_POLICY_SMOKE=1 for synthetic on-device policy integration.") }
        guard ModelAvailability.isAvailable else { throw XCTSkip(ModelAvailability.message) }
        let text = """
        CHEM 220: Laboratory Methods
        Class Schedule: Mon & Wed 9:10 - 10:25 AM.
        Lab reports 65%
        Final exam 35%
        Grade scale
        A = 94.5–100
        Below 52 F
        Practice exercises will not be collected.
        The lowest three lab scores are dropped.
        A missed lab counts as one of those drops.
        No make-up labs are offered.
        """
        let result = try await SyllabusExtractor.extract(.pasted(text))
        print("SYNTHETIC POLICY RESULT:\n\(result.json)")
        XCTAssertEqual(result.grading.compactMap(\.percentage).sorted(), [35,65])
        XCTAssertEqual(result.gradeScale.count, 2)
        XCTAssertEqual(result.classSchedules.first?.days, ["Monday", "Wednesday"])
        XCTAssertTrue(result.gradingPolicies.contains { $0.value.evidenceContains("will not be collected") })
        XCTAssertTrue(result.gradingPolicies.contains { $0.value.evidenceContains("lowest three lab scores") })
        XCTAssertTrue(result.gradingPolicies.contains { $0.value.evidenceContains("missed lab") && $0.value.evidenceContains("those drops") })
        XCTAssertTrue(result.gradingPolicies.contains { $0.value.evidenceContains("No make-up labs") })
    }
}
