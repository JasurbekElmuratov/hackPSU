import SwiftUI

struct CourseEditView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var json: String
    @State private var error: String?
    let onSave: (String) throws -> Void

    init(course: CourseItem, onSave: @escaping (String) throws -> Void) {
        _json = State(initialValue: course.syllabus.json)
        self.onSave = onSave
    }
    var body: some View {
        NavigationStack {
            Form {
                Section("Source-backed corrections") {
                    Text("Edit the structured JSON, keeping source quotes and page references accurate. Missing dates stay null. Saving runs the existing validator; unsupported changes are rejected or left unknown. Review extraction notes afterward.")
                        .font(.callout).foregroundStyle(StudydayTheme.muted)
                    TextEditor(text: $json).font(.system(.caption, design: .monospaced)).frame(minHeight: 360)
                }
                if let error { Text(error).foregroundStyle(StudydayTheme.danger) }
            }
            .navigationTitle("Edit course")
            .studydayInlineTitle()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Validate and Save") {
                        do { try onSave(json); dismiss() }
                        catch { self.error = error.localizedDescription }
                    }
                }
            }
        }.studydaySheetSize()
    }
}
