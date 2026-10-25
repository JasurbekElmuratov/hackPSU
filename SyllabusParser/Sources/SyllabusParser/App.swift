import SwiftUI
import AppKit
import UniformTypeIdentifiers

@main
struct SyllabusParserApp: App {
    var body: some Scene { WindowGroup("Syllabus Parser") { ContentView() }.defaultSize(width: 1000, height: 820) }
}

enum AppScreen: String, CaseIterable { case dashboard = "Dashboard", parser = "Syllabus Parser" }

struct ContentView: View {
    @State private var screen: AppScreen = .dashboard
    @State private var isDemo = false
    @State private var confirmDemo = false
    @State private var datasetRevision = UUID()
    @State private var rawText = ""
    @State private var importedDocument: SyllabusDocument?
    @State private var result: SyllabusResult?
    @State private var jsonDraft = ""
    @State private var isParsing = false
    @State private var message = ""
    @State private var selectedSample: SampleSyllabi = .simple

    private var document: SyllabusDocument {
        if let importedDocument, importedDocument.displayText == rawText { return importedDocument }
        return .pasted(rawText)
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("College Assistant").font(.headline)
                if isDemo { Text("DEMO").font(.caption.bold()).foregroundStyle(.orange) }
                Spacer()
                Picker("Screen", selection: $screen) {
                    ForEach(AppScreen.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }.pickerStyle(.segmented).frame(width: 310)
                Button("Load Verified Demo", action: requestDemo).disabled(isParsing)
            }.padding(16)
            Divider()
            if screen == .dashboard {
                if let result {
                    DashboardView(result: result, isDemo: isDemo).id(datasetRevision)
                } else {
                    ContentUnavailableView {
                        Label("Your syllabus, made useful", systemImage: "graduationcap")
                    } description: {
                        Text("Parse a syllabus PDF locally, or explicitly load the bundled verified demo. Your course data stays on this Mac.")
                    } actions: {
                        Button("Open Syllabus Parser") { screen = .parser }
                        Button("Load Verified Demo", action: requestDemo).disabled(isParsing)
                    }
                    if !message.isEmpty { Text(message).font(.callout).foregroundStyle(.secondary).padding() }
                }
            } else { parserContent }
        }
        .frame(minWidth: 900, minHeight: 650)
        .onChange(of: result) { _, _ in datasetRevision = UUID() }
        .confirmationDialog("Load the verified demo and replace the current working syllabus?", isPresented: $confirmDemo, titleVisibility: .visible) {
            Button("Load Demo and Replace Working Data", action: loadDemo)
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Unsaved working data will be replaced. Saved files are unchanged. The dashboard will be clearly labeled Demo.")
        }
    }

    private func requestDemo() {
        if result != nil || importedDocument != nil || !rawText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { confirmDemo = true }
        else { loadDemo() }
    }

    private func loadDemo() {
        do {
            let demo = try DemoSyllabus.load()
            result = demo
            jsonDraft = demo.json
            importedDocument = nil
            rawText = ""
            isDemo = true
            screen = .dashboard
            message = "Loaded the bundled verified syllabus as Demo. No PDF was parsed and no saved file was replaced."
        } catch { message = error.localizedDescription }
    }

    private var parserContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Syllabus Parser").font(.largeTitle.bold())
            Text("PDF text and model inference stay on this Mac. Raw text is held in memory; files are written only when you choose to save JSON or export PDF text.")
                .font(.subheadline).foregroundStyle(.secondary)
            HStack {
                Button("Upload Syllabus PDF", action: importPDF).disabled(isParsing)
                if importedDocument != nil { Button("Export PDF Text", action: exportPDFText) }
                Picker("Sample", selection: $selectedSample) {
                    ForEach(SampleSyllabi.allCases) { sample in Text(sample.rawValue).tag(sample) }
                }.frame(width: 210)
                Button("Load Sample") {
                    isDemo = false
                    importedDocument = nil
                    rawText = selectedSample.text
                    result = nil
                    jsonDraft = ""
                    message = "Loaded fictional sample \(selectedSample.rawValue)."
                }.disabled(isParsing)
                Spacer()
                Text(ModelAvailability.message).font(.caption).foregroundStyle(ModelAvailability.isAvailable ? .green : .orange)
            }
            Text("Syllabus text (paste here or inspect PDF extraction)").font(.headline)
            TextEditor(text: $rawText).font(.system(.body, design: .monospaced))
                .frame(minHeight: 180).border(.quaternary).disabled(isParsing)
            HStack {
                Button("Parse Syllabus") { parse() }
                    .disabled(rawText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isParsing || !ModelAvailability.isAvailable)
                Button("Create Blank Result") {
                    isDemo = false
                    let blank = SyllabusResult.empty
                    result = blank
                    jsonDraft = blank.json
                    message = "Blank structured result ready for manual editing."
                }.disabled(isParsing)
                if isParsing { ProgressView("Extracting locally…").controlSize(.small) }
                Spacer()
                if result != nil { Button("Save Corrected JSON", action: saveJSON) }
            }
            if !message.isEmpty { Text(message).foregroundStyle(.secondary).font(.callout) }
            if let result {
                ScrollView {
                    VStack(alignment: .leading, spacing: 10) {
                        Group {
                            Text("Structured results").font(.title2.bold())
                            line("Course code", result.courseCode?.value, source: result.courseCode?.source)
                            line("Course name", result.courseName?.value, source: result.courseName?.source)
                            line("Semester", result.semester?.value, source: result.semester?.source)
                            line("Instructor", result.instructor?.value, source: result.instructor?.source)
                            Text("Grading").font(.headline)
                            ForEach(Array(result.grading.enumerated()), id: \.offset) { _, item in
                                line(item.category, item.percentage.map { "\($0)%" } ?? "weight unspecified", source: item.source)
                            }
                            ForEach(Array(result.gradingPolicies.enumerated()), id: \.offset) { _, item in line("Policy", item.value, source: item.source) }
                            Text("Academic events").font(.headline)
                            ForEach(Array(result.events.enumerated()), id: \.offset) { _, item in
                                line(item.title, item.dateText ?? "date not provided", item.certainty, source: item.source)
                            }
                            Text("Recurring rules").font(.headline)
                            ForEach(Array(result.recurringRules.enumerated()), id: \.offset) { _, item in line("Rule", item.value, source: item.source) }
                            ForEach(result.warnings, id: \.self) { Text("⚠︎ \($0)").foregroundStyle(.orange) }
                        }
                        DisclosureGroup("View and correct JSON") {
                            Text("Edit any field below, then apply corrections. Keep missing values null and source quotes accurate.")
                                .font(.caption).foregroundStyle(.secondary)
                            TextEditor(text: $jsonDraft).font(.system(.caption, design: .monospaced))
                                .frame(minHeight: 260).border(.quaternary)
                            Button("Apply JSON Corrections", action: applyCorrections)
                        }
                    }.frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .padding(20)
    }

    @ViewBuilder private func line(_ label: String, _ first: String?, _ second: String? = nil, _ third: String? = nil, source: SourceReference? = nil) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("\(label): \([first, second, third].compactMap { $0 }.joined(separator: " — "))")
            if let source {
                Text("Source\(source.page.map { " · page \($0)" } ?? ""): “\(source.quote)”")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private func importPDF() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.pdf]
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        message = "Reading PDF and checking its text layer…"
        isParsing = true
        Task {
            defer { isParsing = false }
            do {
                let loaded = try await Task.detached(priority: .userInitiated) { try SyllabusDocument.pdf(at: url) }.value
                isDemo = false
                importedDocument = loaded
                rawText = loaded.displayText
                result = nil
                jsonDraft = ""
                message = "Extracted text from \(loaded.pages.count) page(s); \(loaded.warnings.count) text diagnostics. Use Export PDF Text to compare raw and processed text."
            } catch { message = error.localizedDescription }
        }
    }

    private func exportPDFText() {
        guard let importedDocument else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.plainText]
        panel.nameFieldStringValue = "syllabus-page-text.txt"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try Data(importedDocument.diagnosticText.utf8).write(to: url, options: .atomic)
            message = "Exported raw and extraction text for every PDF page."
        } catch { message = error.localizedDescription }
    }

    private func parse() {
        let snapshot = document
        isDemo = false
        isParsing = true
        result = nil
        message = "Running on-device extraction…"
        Task {
            do {
                let extracted = try await SyllabusExtractor.extract(snapshot)
                result = extracted
                jsonDraft = extracted.json
                message = "Extraction complete. Review source quotes and correct the JSON before saving."
                screen = .dashboard
            } catch { message = error.localizedDescription }
            isParsing = false
        }
    }

    private func applyCorrections() {
        do {
            var edited = try JSONDecoder().decode(SyllabusResult.self, from: Data(jsonDraft.utf8))
            ResultValidator.validate(&edited, against: isDemo ? nil : document)
            result = edited
            jsonDraft = edited.json
            message = "Corrections applied; validation warnings refreshed."
        } catch { message = "JSON could not be applied: \(error.localizedDescription)" }
    }

    private func saveJSON() {
        // Save the applied result, never raw syllabus text or an unvalidated draft.
        guard let result else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "syllabus-result.json"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try Data(result.json.utf8).write(to: url, options: .atomic)
            message = "Saved structured results to \(url.lastPathComponent)."
        } catch { message = "Could not save JSON: \(error.localizedDescription)" }
    }
}
