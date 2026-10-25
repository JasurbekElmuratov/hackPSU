# Studyday / hackPSU

A private, on-device college assistant: **PDF → local extraction → structured syllabus data → course dashboard → cited assistant answers**.

Studyday's SwiftUI interface is connected to a shared PDFKit, Apple Vision, and Apple Foundation Models backend. Deterministic validation preserves source quotes, grading weights, grade thresholds, policies, schedules, and uncertainty. No external LLM API, backend server, API keys, or third-party packages are required.

## Requirements

- Xcode 26 or newer
- macOS 26 or iOS 26 or newer
- Apple Intelligence enabled and its on-device model ready for new syllabus extraction and semantic source selection

The verified demo and deterministic answers for loaded syllabuses also work when the local model is unavailable. Physical iPhone deployment requires your own Xcode signing configuration.

## Run

```sh
git clone https://github.com/JasurbekElmuratov/hackPSU.git
cd hackPSU
open UI/Studyday.xcodeproj
```

Select the **Studyday** scheme, choose **My Mac** or an installed iPhone Simulator, and press **⌘R**.

- **Get started → Continue on this device** opens a local workspace. It does not authenticate Google, Apple ID, or campus accounts.
- **Try the verified demo** explicitly loads the bundled verified Calculus JSON and labels it Demo.
- **AI Chat → Add syllabus** opens a real PDF picker and invokes the shared local parser. Import failures never substitute sample data.
- **Home → course** shows extracted events, class schedules, grading bars, thresholds, policies, and source references. Missing dates stay unknown; weekly activities do not generate invented deadlines.
- **Ask about course** or the chat course picker scopes answers to the selected syllabus. Exact dates and percentages are deterministic; other questions can use Foundation Models to select source facts. Each response identifies its actual mode and citations.
- **Edit** exposes structured JSON and validates corrections against imported source text where available.

Course data, source text, and chat remain in memory for the workspace. Loading the demo preserves imported courses. Ending the workspace asks before clearing its memory; saved files are unchanged. Actual student grades are not calculated because scores are unavailable.

### Build the native Mac app from Terminal

```sh
xcodebuild -project UI/Studyday.xcodeproj -scheme Studyday \
  -destination 'platform=macOS' -derivedDataPath .build/StudydayMac \
  CODE_SIGN_IDENTITY=- build

open .build/StudydayMac/Build/Products/Debug/Studyday.app
```

Prebuilt applications and local build caches are intentionally not versioned.

## Repository layout

```text
UI/
  Studyday.xcodeproj/       Integrated macOS/iOS app and shared scheme
  Studyday/                UI v1 design, state, and real local service adapters
  StudydayTests/           UI/backend integration and platform PDF tests
  Verification/            Merge verification notes
SyllabusParser/
  Sources/SyllabusParser/  Shared extraction, validation, models, and assistant
    Resources/             Explicitly bundled verified demo JSON
  Tests/                   Parser, policy, date, and assistant regressions
  Samples/                 Synthetic syllabus text fixtures
  SyllabusParser.xcodeproj/ Original native parser/debugging app
```

Keep `UI` and `SyllabusParser` as sibling directories. The Studyday Xcode project references the backend source files directly, so there is one extraction implementation. The original parser app remains available for raw PDF/OCR text inspection, export, and structured JSON debugging.

## Tests

Run the backend's deterministic regressions:

```sh
cd SyllabusParser
swift test
```

Optional model/PDF integrations are skipped unless enabled. To run the full backend suite on a model-ready Mac:

```sh
SYLLABUS_TEST_PDF=/absolute/path/to/your/MATH_141-005_Syllabus_F26-1.pdf \
SYLLABUS_MODEL_SMOKE=1 \
SYLLABUS_POLICY_SMOKE=1 \
SYLLABUS_ASSISTANT_SMOKE=1 \
swift test
```

The PDF-specific check expects the original four-page Calculus syllabus used during development; that source PDF is not bundled. The normal regressions and synthetic on-device checks do not require publishing a personal syllabus.

From the repository root, run the UI/backend integration suite:

```sh
xcodebuild -project UI/Studyday.xcodeproj -scheme Studyday \
  -destination 'platform=macOS' CODE_SIGN_IDENTITY=- test
```

For iOS, select an installed Simulator in Xcode or use its simulator ID as the `xcodebuild` destination. Live model tests check availability and skip honestly when unsupported.

## Verified locally

On October 24, 2026:

- Clean macOS and iOS Simulator builds succeeded.
- All 58 backend tests passed with the original PDF and model integrations enabled.
- All 11 shared UI/backend integration tests passed on macOS and iPhone 17 Pro Simulator, including actual local extraction and model-selected replies.
- The additional iOS image-only PDF/OCR test passed.
- The native UI completed real PDF import, kept the verified demo as a separate course, and answered with syllabus citations.

See [UI setup](UI/README.md), [merge verification](UI/Verification/merge-verification.md), and [backend details](SyllabusParser/README.md). Verification notes are tracked; generated logs, raw text exports, duplicate result files, per-user Xcode state, and local signing material are excluded. The intentionally bundled verified JSON fixture is tracked.

Further coverage is still needed for physical iPhones, more complex/scanned PDFs, additional date formats, and broader question phrasing.
