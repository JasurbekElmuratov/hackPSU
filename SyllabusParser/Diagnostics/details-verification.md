# Targeted syllabus-detail extraction verification

Verified on 2026-10-24 using Xcode 26.6 and the Mac's on-device Apple Foundation Models. The app UI, PDF importer/OCR implementation, package dependencies, and entitlements were not changed.

## Why correct weights and a failure warning appeared together

The previous `extractChunk` always called a separate Foundation Models `GradingPass`, then independently called `ResultValidator.explicitWeights`. The saved five rows, including their exact table-row quotes, came from that deterministic parser. Matching model categories could not replace those rows.

The model call threw `LanguageModelSession.GenerationError.decodingFailure`. Its catch block unconditionally added “those fields remain unknown.” The warning was appended even after all five deterministic rows validated successfully. It described a failed model response as if the final grading result had failed. The old saved JSON does not record the underlying malformed response, so it does not establish the precise cause of that decoding failure.

The new code requests model weight extraction only for percentage evidence not fully covered by explicit rows. Failure diagnostics are assembled after candidate validation: they report the number of retained deterministic weights or explicitly state when no table weights were recovered. Synthetic tests exercise both cases. The real-PDF run had no grading-model failure warning because its five component rows were fully handled deterministically.

## Targeted changes

- `gradeScale` is separate from assessment-component `grading`. It preserves the literal range, numeric bounds, inclusive/exclusive limits, and a source reference. Grade-first and range-first rows are parsed generically. Open bounds stay unbounded; missing grade letters and gaps are not reconstructed.
- Some letters in the supplied grade table were lost by OCR even though PDFKit's raw table rows were intact. Raw-table references explicitly set `source.textOrigin` to `rawPDFText`; references without this field continue to mean effective extraction text. Validation checks the declared text origin on the exact page.
- `classSchedules` holds normalized written weekday names, the literal time range, and a source reference. Explicit class/lecture meeting rows are parsed independently of model output and also retained in the existing recurring-rules display. Missing AM/PM or timezone information is not inferred. Office locations, office hours, dated exams, malformed clocks, day ranges, and multiple distinct time slots are excluded from this simple parser.
- Written policies still use Foundation Models. Candidate selection includes collection/submission status and missed-work/drop language. Complete source sentences are processed independently of weight extraction, with PDF line wraps joined but table/header boundaries preserved. Each substantive sentence in a verified model-selected quote is preserved, including negation, conditions, and separate missed-work/drop assertions.
- Existing result files decode with empty arrays for the new fields. New thresholds and schedules are validated again when applying manual JSON corrections.

No MATH 141 identifiers, percentages, grade thresholds, meeting days/times, or policy rules are encoded in the extraction logic. Real-course expectations exist only in the integration fixture assertions. Synthetic fixtures use different course identities, weights, thresholds, days/times, and lab policies.

## What was actually verified

- **44 tests passed, zero failures and zero skips** in the full integration run: 41 deterministic checks, one real-PDF/OCR check, one real-PDF Foundation Models check, and one synthetic written-policy Foundation Models check.
- The native macOS Debug application built successfully with local ad hoc signing. Strict code-signature verification passed.
- The supplied PDF still returned five weights totaling 100%: Quizzes 20%, Exam 1 25%, Exam 2 25%, Exam 3 25%, Participation/Attendance 5%.
- All nine letter-grade rows were recovered: A 93–100; A- 90–92.99; B+ 87–89.99; B 83–86.99; B- 80–82.99; C+ 77–79.99; C 70–76.99; D 60–69.99; F under 60. The F upper bound is exclusive. No absent lower limit is fabricated.
- The class schedule is Tuesday and Thursday with literal time text `6 - 7:55 PM`, cited to page one. The parser does not silently add AM/PM to the starting clock.
- Page-two policies separately preserve homework not being collected, the two lowest quizzes being dropped, missed quizzes automatically counting as one of those drops, and the no-makeup rule. The full collection sentence keeps its qualification about some homework problems being studied in class.
- All three exam dates remained yearless: `Tu Sep 29th`, `Tu Nov 3rd`, `Th Dec 3rd`.
- The synthetic course recovered different weights, thresholds, a Monday/Wednesday meeting, uncollected practice exercises, three dropped lab scores, missed labs consuming those drops, and no make-up labs.
- Source-page/origin mismatch, edited unsupported bounds/days, malformed ranges/clocks, redundant model-weight requests, wrapped policy text, distinct policy assertions, legacy decoding, and recovered-vs-unknown warning wording have deterministic regressions.

The latest generated artifacts are `calculus-details-result.json`, `calculus-details-page-text.txt`, `details-regression-tests.log`, and `details-native-build.log` in this directory. The originally supplied `syllabus-result.json` and the previous `calculus-verified-result.json` remain unchanged for comparison. The verified app is `.build/Verified/SyllabusParser.app` in the project.

## Limits and remaining testing

The GUI interaction flow was not manually exercised in this run; verification covers native compilation/signing and the extraction/validation pipeline. Other PDFs, OCR quality, merged/wrapped tables, additional schedule notation, and more complex policy exceptions still need broader testing. Table parsing is intentionally conservative. Policy deduplication remains conservative; a short prohibition heading can remain alongside a more detailed policy sentence. Model/OCR omissions and rejected entries can still occur and must be reviewed against their cited sources.
