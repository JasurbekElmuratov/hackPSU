# College assistant demo — implementation and verification

## Run the demo

Open `.build/CollegeAssistantDemo/SyllabusParser.app` in this project, or run the existing **SyllabusParser / My Mac** Xcode scheme. The Dashboard opens empty. Click **Load Verified Demo** to explicitly load the existing verified Calculus JSON. If any working syllabus or result exists, loading the demo requires confirmation. Demo data is visibly labeled and no saved file is overwritten.

Choose **Syllabus Parser** to use the original PDF/paste/sample workflow. Successful parsing automatically opens the Dashboard. The original text inspection, raw/OCR text export, JSON corrections, and JSON save controls remain available.

## Implementation

Only `App.swift` was changed among the existing application sources. `Extractor.swift`, `Document.swift`, `Validation.swift`, `Models.swift`, and `Samples.swift` are byte-for-byte unchanged from the start of this task. Three small modules were added:

- `DashboardData.swift`: read-only projections of `SyllabusResult`, date normalization/sorting/grouping, verified percentage formatting, and bundled demo loading.
- `DashboardView.swift`: upcoming/past/unknown event groups, percentage bars, thresholds, source disclosures, policies, class schedule, and an in-memory question/answer view.
- `LocalAssistant.swift`: common deterministic answers, bounded retrieval of relevant stored facts, optional Apple Foundation Models source selection, and deterministic response rendering.

The JSON resource is an exact copy of `Diagnostics/calculus-details-result.json`. It is bundled in both SwiftPM and native Xcode builds. No course-specific extraction or assistant rules were added. Saved JSON files remain unchanged. No dependencies, network clients, backend services, network entitlements, or additional frameworks were added.

## Date and uncertainty behavior

Only actual extracted academic events become calendar rows. Recurring homework/quiz rules never generate dated events. Events without a supported date are displayed separately.

Explicit years are retained. A missing year can be taken from a supported `Fall/Autumn`, `Spring`, or `Summer` term/year only when its month is compatible with that term. The UI and assistant explicitly label the derived year and expose both the event quote and semester quote. Winter/cross-year ambiguity, absent semester years, impossible dates, ambiguous numeric dates, or contradictory weekdays remain unknown. Stored extraction data is not modified.

Sorting and past/upcoming grouping use the device's current date/calendar/timezone. An event dated today stays upcoming for the whole day because an event time is not supplied. The dashboard refreshes its clock once per minute. Class meeting times remain exactly as stored, including any unstated starting meridiem or timezone.

## Assistant behavior and privacy

The five common questions have deterministic source-backed answers, whether or not Apple Intelligence is available. Exact dates come from the date projection; percentages must be supported by the stored component row. The app explicitly states that student scores are unavailable. A last numbered exam is never assumed to be a final exam.

Other questions retrieve a small relevant subset of stored syllabus facts. The local model receives a bounded JSON context and can return only IDs of those facts. The app validates the IDs and renders the corresponding stored text with source references. It does not accept model-authored factual prose, dates, percentages, policies, or assignments. This intentionally narrow design provides semantic retrieval while keeping factual answers grounded.

Each response displays its actual mode: deterministic, deterministic with the model unavailable, deterministic after a failed model response, or on-device model source selection. Common answers do not falsely claim that model inference occurred. Unavailable information is stated explicitly. A failed or unavailable model uses deterministic source-backed output; no AI inference is simulated.

The question and syllabus JSON are treated as untrusted data, with no tool execution. Chat is held only in memory for the dashboard session and clears when its course/session changes. Questions are independent; this demo does not infer follow-up pronoun references from prior turns. All processing is on-device.

## What was actually verified on 2026-10-24

- **58 tests passed, zero failures, zero skips** with all four opt-in integration checks enabled. The previous parser regressions still pass.
- The fresh real PDF passed PDFKit/Vision import, Foundation Models extraction, existing deterministic validation, dashboard projection, and a source-backed assistant answer in the same integration test.
- The verified JSON loads from the compiled SwiftPM resource bundle and the native application's bundle.
- On an injected October 24, 2026 clock, the demo places Exam 1 (September 29) in Past and lists Exam 2 (November 3) then Exam 3 (December 3) as Upcoming. All original yearless dates remain unchanged in the result. Day-boundary, unknown/ambiguous dates, invalid leap dates, weekday contradictions, and no generated weekly deadlines have regressions.
- All five example questions passed with model use explicitly disabled. They preserve the 25% Exam 2 weight, both missed-quiz/drop rules plus the no-makeup policy, the unknown final-exam identity, and the Tuesday/Thursday meeting.
- Actual on-device assistant inference selected the calculator/formula-sheet policy. An injected instruction to invent a score/deadline could not add those facts to the rendered response. Invalid/repeated model IDs and irrelevant retrieval candidates have regressions.
- Native Xcode Debug build succeeded with local ad hoc signing. Strict code-signature verification passed, and the final app includes the JSON resource.
- In the running native app, manually exercised empty launch → explicit demo loading → labeled dashboard; upcoming/past groups; five percentage bars; thresholds; grading policies; the Tuesday/Thursday schedule; next-exam, Exam 2 weight, and missed-quiz answers; a real model-selected formula-sheet answer; the replacement confirmation dialog; cancellation preserving working data/chat; and access to the original parser screen.
- The native PDF picker opened and selected the real PDF. UI automation timed out after it closed. A process sample showed an idle event loop rather than an extraction deadlock. A subsequent responsive window displayed the regular, non-demo Calculus dashboard. The complete PDF pipeline is verified by integration tests; the file-picker interaction itself was not fully observed through automation. Existing working data was left intact.

The signed app is `.build/CollegeAssistantDemo/SyllabusParser.app`. `dashboard-regression-tests.log`, `dashboard-native-build.log`, and `dashboard-fresh-extraction.json` in this directory preserve the run evidence. Earlier saved JSON files and parser verification artifacts are unchanged.

## Remaining coverage

Additional institution/locale date formats, merged or damaged PDF layouts, other Macs/model availability states, and broader natural-language question phrasing need more testing. Semester inference is deliberately conservative. Retrieval is bounded and lexical before local model selection, so unfamiliar wording can yield an unavailable answer. Model-unavailable behavior was tested by explicitly disabling model use; device eligibility and OS installation states were not changed. No current-grade calculation is performed because student scores are absent.
