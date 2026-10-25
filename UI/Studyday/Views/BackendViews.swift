import SwiftUI

extension View {
    @ViewBuilder func studydayInlineTitle() -> some View {
        #if os(iOS)
        navigationBarTitleDisplayMode(.inline)
        #else
        self
        #endif
    }
    @ViewBuilder func studydaySheetSize() -> some View {
        #if os(macOS)
        frame(minWidth: 650, minHeight: 560)
        #else
        self
        #endif
    }
}

struct SyllabusSourceView: View {
    let source: SourceReference
    var body: some View {
        DisclosureGroup("Syllabus source\(source.page.map { " · page \($0)" } ?? " · pasted text")\(source.textOrigin == .rawPDFText ? " · raw PDF" : "")") {
            Text(source.quote).font(.caption).textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }.font(.caption).foregroundStyle(StudydayTheme.muted)
    }
}

struct CourseGradingView: View {
    let syllabus: SyllabusResult
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Grading overview").font(.headline).foregroundStyle(StudydayTheme.ink)
            Text("Syllabus weights. Your actual scores are unavailable.").font(.caption).foregroundStyle(StudydayTheme.muted)
            if syllabus.grading.isEmpty { Text("Weights are unknown.") }
            ForEach(Array(syllabus.grading.enumerated()), id: \.offset) { _, grade in
                VStack(alignment: .leading, spacing: 5) {
                    HStack {
                        Text(grade.category)
                        Spacer()
                        Text(DashboardSnapshot.percentage(grade).map(DashboardSnapshot.percentText) ?? "Unknown")
                    }.font(.subheadline).foregroundStyle(StudydayTheme.ink)
                    if let weight = DashboardSnapshot.percentage(grade) { ProgressView(value: weight, total: 100).tint(StudydayTheme.accent) }
                    SyllabusSourceView(source: grade.source)
                }
            }
            if !syllabus.gradeScale.isEmpty {
                DisclosureGroup("Letter-grade thresholds") {
                    ForEach(Array(syllabus.gradeScale.sorted { ($0.lowerBound ?? -.infinity) > ($1.lowerBound ?? -.infinity) }.enumerated()), id: \.offset) { _, row in
                        VStack(alignment: .leading) {
                            Text("\(row.grade): \(row.rangeText)").foregroundStyle(StudydayTheme.ink)
                            SyllabusSourceView(source: row.source)
                        }.padding(.vertical, 3)
                    }
                }.foregroundStyle(StudydayTheme.ink)
            }
            if !syllabus.gradingPolicies.isEmpty {
                DisclosureGroup("Grading policies (\(syllabus.gradingPolicies.count))") {
                    ForEach(Array(syllabus.gradingPolicies.enumerated()), id: \.offset) { _, policy in
                        VStack(alignment: .leading, spacing: 3) {
                            Text(policy.value).foregroundStyle(StudydayTheme.ink)
                            SyllabusSourceView(source: policy.source)
                        }.padding(.vertical, 5)
                    }
                }.foregroundStyle(StudydayTheme.ink)
            }
        }
        .padding(16)
        .background(StudydayTheme.paperElevated, in: RoundedRectangle(cornerRadius: StudydayTheme.cornerCard))
    }
}
