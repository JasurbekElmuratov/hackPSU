# Studyday — UI v1 + local syllabus backend

UI v1 is connected to the existing PDFKit, Vision, Apple Foundation Models, deterministic validation, date projection, and syllabus assistant in the sibling `SyllabusParser` project. The welcome design, mint/sky theme, chat, Home, and course navigation are retained. Runtime extraction and chat mocks have been removed.

## Open and run

Open **`UI/Studyday.xcodeproj`**, select the **Studyday** scheme, then **My Mac** or an iPhone Simulator. The shared backend requires **Xcode 26+, macOS 26+, or iOS 26+**. Keep `UI` and `SyllabusParser` as sibling folders: the Xcode project references the shared backend source files directly, so there is one parser implementation.

The built native app is `.build/macOS/Studyday.app` in this folder. A clean Simulator build is under `.build/iOSSimulator/Studyday.app`.

1. **Get started → Continue on this device** opens an empty local workspace. This is not Google, Apple ID, or campus authentication; no external account is signed in.
2. **Try the verified demo** explicitly loads the existing verified Calculus JSON and marks the course Demo. Loading it later adds/selects its own course; imported courses are preserved.
3. **AI Chat → Add syllabus** opens a real PDF picker. The selected URL is read with security-scoped access, then processed by the actual local parser. Failed import/model availability never substitutes sample data.
4. **Home → course** shows actual extracted exams/quizzes/deadlines grouped into upcoming, past, and unknown dates, plus class schedules, grading weights, thresholds, policies, source quotes, and warnings. Weekly activities do not create invented quiz/deadline entries.
5. **Ask about course** selects that course's canonical result for chat. The chat course picker switches contexts and starts a separate conversation, preventing stale answers from a different syllabus.
6. **Edit** opens the complete structured JSON. Saving uses the existing validator against the imported document where available. Unsupported dates/weights remain unknown or are rejected; missing deadlines never default to today.

Course data, source text, and chat remain in memory for the workspace. Ending the workspace clears that memory and asks for confirmation. Saved files and earlier parser JSON artifacts are unchanged. No server, external LLM API, API keys, authentication SDK, or third-party packages are used. The macOS app reuses the backend's existing file-access sandbox entitlements without network access.

## Backend integration

| UI integration | Real implementation |
| --- | --- |
| `LocalWorkspaceService` | Explicit on-device workspace; no pretend OAuth identity |
| `LocalSyllabusExtractor` | Selected PDF URL → `SyllabusDocument.pdf` → `SyllabusExtractor.extract` |
| `LocalChatService` | Selected course's `SyllabusResult` → `SyllabusAssistant.answer` |
| `CourseItem` | Keeps the complete canonical result; exposes read-only course/event projections |
| Course corrections | Existing `ResultValidator`, with original page text retained in memory |

`ExtractedSyllabus`'s lossy flat fields were replaced with `SyllabusResult`; source references, uncertainty, policies, and letter-grade thresholds survive the round trip. Chat displays the real answer mode and citations. Common questions use deterministic stored values; other questions can use Foundation Models for source selection. If the local model is unavailable, deterministic answers for a loaded syllabus still work, and new extraction reports the actual unavailability.

Shared source references include `Models.swift`, `Document.swift`, `Extractor.swift`, `Validation.swift`, `DashboardData.swift`, `LocalAssistant.swift`, and `Samples.swift`. The only shared backend implementation change is conditional AppKit/UIKit import and thumbnail-to-CGImage conversion in `Document.swift`; extraction instructions, parsing, and validation logic were not rewritten. The original `SyllabusParser` app and test harness remain available for parser inspection and raw-text export.

## Verification

See [the merge verification report](Verification/merge-verification.md) for exact checks, logs, and remaining coverage.

- Clean macOS and iOS Simulator builds succeeded.
- All **58 existing backend tests** passed with the real PDF and model integrations enabled.
- All **11 shared UI/backend integration tests** passed on macOS and iPhone 17 Pro Simulator, including actual local extraction and model-selected replies.
- The additional **iOS-only image-PDF OCR regression** passed, exercising the new UIKit/Vision branch.
- Native UI walkthrough verified welcome/demo loading, course detail and source evidence, course-scoped deterministic and model-selected answers, and real external-PDF import without replacing the demo.

Run shared UI/backend tests:

```sh
xcodebuild -project Studyday.xcodeproj -scheme Studyday \
  -destination 'platform=macOS' CODE_SIGN_IDENTITY=- test
```

For iOS, choose an installed Simulator destination in Xcode or use `xcodebuild` with that simulator's ID. The real-model integration checks availability and skips honestly on unsupported devices. Physical iPhone testing, wider PDF/policy coverage, and external account authentication are not part of the verified results.
