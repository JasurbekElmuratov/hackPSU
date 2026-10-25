# Local College Assistant and Syllabus Parser

Latest targeted changes and evidence: [detail extraction verification](Diagnostics/details-verification.md).

Existing native SwiftUI macOS 26 application using PDFKit, local Vision OCR, and Apple's on-device Foundation Models. No network client, backend, cloud model, or third-party dependency. Text stays in memory unless the user explicitly exports PDF diagnostics. Structured JSON is written only on Save.

## College assistant demo

The existing parser now feeds a **Dashboard** with upcoming/past/unknown events, source-cited grading bars and thresholds, policies, class schedules, and **Ask Assistant**. Open `.build/CollegeAssistantDemo/SyllabusParser.app` or run the existing Xcode scheme. Click **Load Verified Demo** for the bundled verified Calculus JSON; it is explicitly labeled and asks before replacing working data. Choose **Syllabus Parser** for the original PDF workflow. Successful parsing opens the dashboard automatically.

Exact answers to common questions use deterministic stored values. Other questions can use Apple Foundation Models to select relevant source facts, with mode labels and safe deterministic fallback. All processing remains local; chat stays in memory. See [the college assistant verification report](Diagnostics/dashboard-verification.md) for the actual end-to-end checks and limits.

## Run

Open `SyllabusParser.xcodeproj` in Xcode 26, select **SyllabusParser / My Mac**, and Run. Enable Apple Intelligence and wait for its model to download. PDF import, diagnostics, and manual editing also work without the model.

Upload a PDF, load a fictional sample, or paste text. The text editor shows the page-numbered text actually used for inference. **Export PDF Text** writes a diagnostic text file containing, for every page:

- The untouched PDFKit text layer, including blank pages and broken glyph mappings.
- The effective extraction text, its origin (PDFKit or local Vision OCR), and diagnostics.

Damaged text such as `Sec8on` and `prac]ce` is a PDF font-encoding problem, not a word substitution the model should guess. Pages with suspicious embedded characters or no text layer are rendered and recognized locally using Vision. OCR observations are grouped by vertical position, then ordered horizontally; tabs preserve separate table cells. Unicode ligatures and whitespace are normalized for evidence comparison. Letters and digits are never globally substituted. OCR can still omit or misread text; use the diagnostic export and original PDF to review it. Arbitrary multi-column prose and tables with merged/wrapped cells are not guaranteed to have correct reading order. Validation refuses to associate labels with weights across different rows.

If imported text is edited, it becomes pasted text with unknown (`null`) page references; the original diagnostic export remains available. Import and parsing disable source edits until they finish so results retain their source document.

## Extraction and validation

Small independent guided-generation requests handle course metadata, grading weights, assessment policies, dated academic events, and recurring schedules. Policy requests use complete candidate sentences with wrapped lines joined and structural boundaries preserved. Other requests see only relevant candidate source lines, rather than a mixture of headings, policies, grade scales, and topics. Requests use bounded arrays and small source chunks. Context-limit failures retry smaller chunks. An undecodable response produces an explicit warning and no generated entries from that pass.

Literal course-heading/instructor/term anchors and direct component-percentage rows are recovered deterministically, then subjected to the same validation. Thus an explicit assessment table does not depend on a model's ability to finish its JSON reply. Letter-grade thresholds are excluded from component extraction and preserved separately in `gradeScale`. Explicit meeting rows are preserved in `classSchedules`. Model weight extraction is skipped when explicit rows cover all the percentage evidence. Models can supply other supported entries, but cannot override those explicit rows with a guessed percentage.

Every accepted entry requires a nonempty supporting quote on its exact PDF page (or a null page for pasted text). Validation checks the **value's support**, not just the presence of some quote:

- Identity values must occur in appropriate identity evidence. Conflicting identities stay unknown.
- Weights must be finite, between 0 and 100, and explicitly attached to their own component in the same row/clause. Unknown, unsupported, or conflicting weights stay null. Incomplete totals warn; missing categories are never filled in.
- Events must be specific academic assessments or supported milestones, with a literal valid date tied to that event, or explicit evidence of an unknown deadline. Metadata, topic lists, policies, and page labels are rejected. Calendar checks reject impossible days, unsupported years, and ambiguous numeric dates. A missing year is never inferred from the semester. Conflicting dates become unknown.
- Recurring activities need both an actual activity and a stated cadence. A bare heading is insufficient; when its verified quote contains the full schedule, that literal quote can be retained instead. Classroom locations, calculator restrictions, makeup policies, and grade scales are excluded.
- Policies use conservative deterministic semantic keys to merge capitalization, punctuation, redundant headings, and selected wording variants. Negation, numbers, assessment scope, and exceptions remain significant; this is not general semantic entailment.

JSON keeps the existing field names and can still read old result files. Unknown fields now encode explicitly as null. Applying manual JSON corrections runs the same validation before saving. Quotes normally refer to the effective extraction text. Grade-table rows recovered from intact raw PDFKit text explicitly set `source.textOrigin` to `rawPDFText`; source validation checks that origin on the cited page. The diagnostic export preserves both text versions. New `gradeScale` and `classSchedules` arrays default to empty when decoding older JSON.

## Tests

Deterministic synthetic regressions run without Apple Intelligence:

```sh
swift test
```

Four opt-in integration tests are skipped by default (real PDF diagnostics, real/pasted model extraction, synthetic written-policy inference, and local assistant source selection). For the supplied four-page Calculus II PDF:

```sh
SYLLABUS_TEST_PDF=/absolute/path/to/MATH_141-005_Syllabus_F26-1.pdf \
SYLLABUS_MODEL_SMOKE=1 \
SYLLABUS_POLICY_SMOKE=1 \
SYLLABUS_ASSISTANT_SMOKE=1 \
SYLLABUS_DIAGNOSTIC_OUTPUT=/tmp/calculus-page-text.txt \
SYLLABUS_MODEL_OUTPUT=/tmp/calculus-result.json \
swift test
```

With `SYLLABUS_MODEL_SMOKE=1` but no PDF path, the model check uses synthetic sample A. PDF diagnostics and model JSON are only written when their output environment variables are explicitly supplied. The PDF-specific integration check asserts the supplied fixture's page count, repaired title/text, five exact grading weights, three exam dates, course identity, and a supported recurring quiz schedule.

## Current verification

All 58 tests passed with all four integration flags enabled, including fresh PDF extraction through dashboard projection and assistant answers, the existing synthetic policy model fixture, and actual on-device assistant source selection. The native Xcode Debug build and strict code-signature check passed. Core extraction sources remain unchanged in this extension.

See [the college assistant report](Diagnostics/dashboard-verification.md) for runtime/UI evidence and remaining testing. Earlier parser improvements and their source-provenance details remain documented in [the detail extraction report](Diagnostics/details-verification.md). The final application for this extension is `.build/CollegeAssistantDemo/SyllabusParser.app`.
