# UI v1 / backend merge — verified 2026-10-24

## Scope

Read the supplied iOS UI, model/service protocols, mock implementations, views, theme, and Xcode project, then connected it to the existing on-device backend. The UI now builds natively for macOS 26 and iOS 26. The existing parser application was preserved.

The merged project compiles the sibling backend's source files directly. It does not maintain a second parser copy or introduce an HTTP service. The original `Document.swift` Mac code is retained inside `#if canImport(AppKit)`; the UIKit branch supplies the CGImage needed by Vision on iOS. Existing extraction, schema, validation, date projection, and assistant logic are reused.

## Behavior now connected

- Real PDF URL selection and local PDFKit/Vision/Foundation Models extraction.
- Complete canonical course data, including source quotes/pages/origin, unknown values, grade thresholds, schedules, and policies.
- Read-only UI task projections using the existing deterministic semester/date handling; no invented recurring deadlines and no default-today editor behavior.
- Course-specific assistant context, real mode labels and citations, deterministic common answers, and local model source selection.
- Explicit verified demo loading that preserves imported courses and does not choose facts based on a filename.
- Source-validated JSON corrections and failure states that do not substitute demo courses.
- Cancellation/operation tokens preventing late replies from leaking into a new or ended workspace.
- Honest local workspace onboarding. The original fake Google/Apple/campus sessions and invented user identities were removed; real OAuth is not claimed.
- Desktop width constraints preserve readability while retaining UI v1's design tokens and phone layout.

## Build and test evidence

- Clean native macOS build: succeeded; ad hoc signature verified using `codesign --verify --deep --strict`.
- Clean iOS Simulator build: succeeded with the installed iOS 26.5 SDK/runtime.
- Backend regression suite: **58 tests, zero failures, zero skips**, including the real four-page Calculus PDF, local OCR, extraction, synthetic policies, date projection, deterministic fallback, and actual assistant source selection.
- Shared UI integration suite on macOS: **11 tests, zero failures, zero skips**.
- The same shared suite on iPhone 17 Pro Simulator: **11 tests, zero failures, zero skips**.
- Additional iOS-only scanned/image PDF check: **1 test, zero failures**, run separately after adding it. It created an image-only PDF, confirmed an empty raw text layer, then recovered its text through the UIKit/Vision adapter.

The UI integration suite tests canonical demo decoding, real URL plumbing, content-vs-filename behavior, course-specific answers and source preservation, no fake course on failure, demo/import coexistence, invalid correction rejection, no stale replies after ending a workspace, unsupported document types, actual PDF text reading, and real PDF → extraction → course → assistant execution. The live fixture deliberately uses a MATH-looking filename while containing a different synthetic course and verifies that the document content wins.

The model-backed shared test produced the expected 65/35 weights and Monday/Wednesday schedule, then obtained an exact 35% final-exam answer and a genuinely model-selected formula-sheet policy. No inference was skipped on the tested Mac or Simulator. Device/model availability is still checked at runtime rather than assumed.

## Native UI walkthrough

Manually verified in the merged macOS UI:

1. UI v1 welcome design and explicit local-workspace / verified-demo choices.
2. Verified demo in Home, labeled Demo, with the actual instructor, three exams, and no invented dated quizzes or assignments.
3. Course Detail: Tuesday/Thursday 6–7:55 PM, Exam 2 / Exam 3 upcoming, Exam 1 past, all five weights, threshold/policy disclosures and page references.
4. Course-scoped chat answering Exam 2 = 25%, with page-two citation and deterministic-mode label.
5. Actual Foundation Models source selection answering the formula-sheet question from the calculator policy, with page-one citation and model-mode label.
6. Real PDF picker selecting the supplied Calculus PDF from Desktop. The app completed local extraction, added a second non-demo course, kept the demo, and selected the imported course.
7. The freshly imported course answered “When is my next exam?” with Exam 2, November 3, 2026, plus the event and semester references. Demo and imported contexts remained separate.

The final deliverable has only small desktop width/label adjustments beyond the walkthrough build; its code was compiled for both platforms. The current working app session and saved syllabus artifacts were left intact.

## Artifacts

- `UI/.build/macOS/Studyday.app`: clean signed native build.
- `UI/.build/iOSSimulator/Studyday.app`: clean Simulator build; physical-device signing is still required for an iPhone.
- `macOS-build.log`, `iOS-build.log`, `macOS-integration.log`, `iOS-integration.log`, `iOS-ocr.log`, and `backend-regressions.log`: command evidence alongside this report.
- The shared verified JSON remains at `SyllabusParser/Sources/SyllabusParser/Resources/VerifiedCalculus.json` and is bundled into both app builds.

## Remaining coverage

Physical iPhone operation/signing, more scanned or complex PDF layouts, broader policy/question phrasing, and long sessions with many courses need further testing. External OAuth is not implemented; the app explicitly uses a local workspace. Course/source/chat data remain in memory and are cleared when that workspace ends. The original parser app remains the raw-text debugging/export interface.
