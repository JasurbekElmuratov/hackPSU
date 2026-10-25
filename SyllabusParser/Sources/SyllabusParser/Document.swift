import Foundation
import PDFKit
import Vision
#if canImport(AppKit)
import AppKit
#else
import UIKit
#endif

struct SyllabusDocument: Sendable {
    struct Page: Sendable {
        let number: Int?
        let text: String
        let rawText: String
        let method: String
        let warnings: [String]

        init(number: Int?, text: String, rawText: String? = nil, method: String = "text", warnings: [String] = []) {
            self.number = number
            self.text = text
            self.rawText = rawText ?? text
            self.method = method
            self.warnings = warnings
        }
    }
    var pages: [Page]
    var displayText: String {
        pages.map { page in
            if let number = page.number { return "[Page \(number)]\n\(page.text)" }
            return page.text
        }.joined(separator: "\n\n")
    }
    // Diagnostic text is never sent to the model. It preserves the untouched PDFKit output,
    // even on blank pages, alongside the text actually used as extraction evidence.
    var diagnosticText: String {
        pages.map { page in
            """
            === Page \(page.number.map(String.init) ?? "unknown") | method: \(page.method) ===
            Warnings: \(page.warnings.joined(separator: " "))
            --- Raw PDFKit text ---
            \(page.rawText)
            --- Text used for extraction ---
            \(page.text)
            """
        }.joined(separator: "\n\n")
    }
    var warnings: [String] {
        pages.flatMap { page in page.warnings.map { "Page \(page.number.map(String.init) ?? "unknown"): \($0)" } }
    }
    static func pasted(_ text: String) -> SyllabusDocument {
        SyllabusDocument(pages: [Page(number: nil, text: text)])
    }
    static func pdf(at url: URL) throws -> SyllabusDocument {
        let accessed = url.startAccessingSecurityScopedResource()
        defer { if accessed { url.stopAccessingSecurityScopedResource() } }
        guard let pdf = PDFDocument(url: url) else { throw DocumentError.unreadable }
        var pages: [Page] = []
        for index in 0..<pdf.pageCount {
            guard let page = pdf.page(at: index) else { continue }
            let raw = page.string ?? ""
            let suspicious = hasDamagedText(raw)
            let empty = raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            var text = raw.precomposedStringWithCompatibilityMapping
            var method = "PDFKit"
            var warnings: [String] = []
            if suspicious || empty {
                warnings.append(empty ? "No PDF text layer; attempted local OCR." : "Possible font encoding damage in PDF text; attempted local OCR.")
                do {
                    let recognized = try recognize(page)
                    if !recognized.isEmpty {
                        text = recognized
                        method = "Vision OCR"
                        warnings.append("OCR is evidence from the page image and may contain errors. Compare with the PDF and raw text.")
                    } else { warnings.append("OCR found no confident text; retained the PDF text layer.") }
                } catch { warnings.append("Local OCR failed; retained the PDF text layer.") }
            }
            if hasDamagedText(text) { warnings.append("Unresolved suspicious characters; do not guess word replacements.") }
            pages.append(Page(number: index + 1, text: text, rawText: raw, method: method, warnings: warnings))
        }
        guard pages.contains(where: { !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) else { throw DocumentError.noText }
        return SyllabusDocument(pages: pages)
    }

    static func hasDamagedText(_ text: String) -> Bool {
        if text.contains("\u{FFFD}") { return true }
        // Do not globally replace 8, ], or X: they are legitimate in section numbers,
        // mathematics, room numbers, and URLs. OCR the page image instead.
        let pattern = #"\p{L}[8\]\\]\p{Ll}|\p{Ll}X\p{Ll}"#
        return text.range(of: pattern, options: .regularExpression) != nil
    }

    private static func recognize(_ page: PDFPage) throws -> String {
        let bounds = page.bounds(for: .mediaBox)
        let scale = min(3, 2400 / max(bounds.width, bounds.height))
        let size = CGSize(width: bounds.width * scale, height: bounds.height * scale)
        let image = page.thumbnail(of: size, for: .mediaBox)
        #if canImport(AppKit)
        var rect = CGRect(origin: .zero, size: size)
        guard let cgImage = image.cgImage(forProposedRect: &rect, context: nil, hints: nil) else { return "" }
        #else
        guard let cgImage = image.cgImage else { return "" }
        #endif
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.recognitionLanguages = ["en-US"]
        request.usesLanguageCorrection = false // Avoid silently rewriting names or mathematical text.
        try VNImageRequestHandler(cgImage: cgImage).perform([request])
        let observations = (request.results ?? []).compactMap { observation -> TextFragment? in
            guard let candidate = observation.topCandidates(1).first, candidate.confidence >= 0.5 else { return nil }
            return TextFragment(text: candidate.string, x: observation.boundingBox.minX, y: observation.boundingBox.midY,
                                height: observation.boundingBox.height)
        }
        return readingRows(observations)
    }

    struct TextFragment {
        let text: String
        let x: CGFloat
        let y: CGFloat
        let height: CGFloat
    }
    // Keep table cells on their visual row instead of emitting all labels then all weights.
    // Tabs expose separate cells/columns; evidence validation never joins unrelated rows.
    static func readingRows(_ fragments: [TextFragment]) -> String {
        var rows: [[TextFragment]] = []
        for fragment in fragments.sorted(by: { $0.y > $1.y }) {
            if let index = rows.indices.last, let anchor = rows[index].first,
               abs(anchor.y - fragment.y) < min(anchor.height, fragment.height) * 0.45 {
                rows[index].append(fragment)
            } else { rows.append([fragment]) }
        }
        return rows.map { $0.sorted { $0.x < $1.x }.map(\.text).joined(separator: "\t") }.joined(separator: "\n")
    }

    enum DocumentError: LocalizedError {
        case unreadable, noText
        var errorDescription: String? {
            switch self {
            case .unreadable: "Could not read this PDF. Check that it is valid and unlocked."
            case .noText: "No text could be recovered from this PDF, including local OCR."
            }
        }
    }
}

extension String {
    // Whitespace and Unicode presentation normalization only; no spelling repair.
    var evidenceText: String {
        precomposedStringWithCompatibilityMapping.split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }
    func evidenceContains(_ value: String) -> Bool {
        !value.evidenceText.isEmpty && evidenceText.localizedCaseInsensitiveContains(value.evidenceText)
    }
}
