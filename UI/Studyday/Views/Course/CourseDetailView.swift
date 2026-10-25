import SwiftUI

struct CourseDetailView: View {
    @EnvironmentObject private var appModel: AppModel
    let courseID: String
    @State private var segment: TaskSegment = .exams
    @State private var showEdit = false
    private var course: CourseItem? { appModel.courses.first { $0.id == courseID } }

    var body: some View {
        Group {
            if let course {
                TimelineView(.periodic(from: .now, by: 60)) { context in
                    ZStack {
                        StudydayBackground()
                        ScrollView {
                            VStack(alignment: .leading, spacing: 18) {
                                header(course)
                                Picker("Section", selection: $segment) {
                                    ForEach(TaskSegment.allCases) { Text($0.title).tag($0) }
                                }.pickerStyle(.segmented)
                                taskList(course, now: context.date)
                                CourseGradingView(syllabus: course.syllabus)
                                if !course.syllabus.warnings.isEmpty {
                                    DisclosureGroup("Extraction notes (\(course.syllabus.warnings.count))") {
                                        ForEach(course.syllabus.warnings, id: \.self) { Text($0).font(.caption).foregroundStyle(StudydayTheme.muted).padding(.vertical, 3) }
                                    }.foregroundStyle(StudydayTheme.ink)
                                }
                            }.padding(16).frame(maxWidth: 1000).frame(maxWidth: .infinity)
                        }
                    }
                }
                .navigationTitle(course.code)
                .studydayInlineTitle()
                .toolbar {
                    ToolbarItem(placement: .primaryAction) {
                        Button("Ask about course") { appModel.selectCourse(course.id); appModel.selectedTab = .chat }.disabled(appModel.isChatBusy)
                    }
                    ToolbarItem(placement: .primaryAction) { Button("Edit") { showEdit = true }.disabled(appModel.isChatBusy) }
                }
                .sheet(isPresented: $showEdit) {
                    CourseEditView(course: course) { json in _ = try appModel.applyCorrections(courseID: course.id, json: json) }
                }
            } else { ContentUnavailableView("Course removed", systemImage: "trash") }
        }
    }
    private func header(_ course: CourseItem) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(course.title).font(.system(size: 24, weight: .semibold, design: .rounded)).foregroundStyle(StudydayTheme.ink)
            if course.isDemo { Label("Verified demo", systemImage: "play.rectangle").foregroundStyle(StudydayTheme.accent) }
            Label(course.instructor, systemImage: "person.fill")
            Label(course.term, systemImage: "calendar")
            Label(course.meetingTimes, systemImage: "clock")
            ForEach(Array(course.syllabus.classSchedules.enumerated()), id: \.offset) { _, schedule in SyllabusSourceView(source: schedule.source) }
        }
        .font(.subheadline).foregroundStyle(StudydayTheme.muted)
        .frame(maxWidth: .infinity, alignment: .leading).padding(16)
        .background(StudydayTheme.paperElevated, in: RoundedRectangle(cornerRadius: StudydayTheme.cornerCard))
    }
    private func taskList(_ course: CourseItem, now: Date) -> some View {
        let all = course.tasks(now: now).filter { task in
            switch segment {
            case .exams: DashboardSnapshot.isExam(task.title)
            case .quizzes: task.title.range(of: #"\b(quiz|quizzes)\b"#, options: [.regularExpression, .caseInsensitive]) != nil
            case .assignments: !DashboardSnapshot.isExam(task.title) && task.title.range(of: #"\b(quiz|quizzes)\b"#, options: [.regularExpression, .caseInsensitive]) == nil
            }
        }
        let today = Calendar.current.startOfDay(for: now)
        return VStack(alignment: .leading, spacing: 12) {
            if all.isEmpty {
                Text("No \(segment.title.lowercased()) with specific dates or explicit unknown deadlines were extracted. Weekly activities do not create dated tasks.")
                    .font(.subheadline).foregroundStyle(StudydayTheme.muted)
            }
            taskGroup("Upcoming", tasks: all.filter { ($0.dueDate ?? .distantPast) >= today })
            taskGroup("Past", tasks: all.filter { $0.dueDate != nil && $0.dueDate! < today })
            taskGroup("Dates unknown", tasks: all.filter { $0.dueDate == nil })
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
    @ViewBuilder private func taskGroup(_ title: String, tasks: [CourseTask]) -> some View {
        if !tasks.isEmpty {
            Text(title).font(.headline).foregroundStyle(StudydayTheme.ink)
            ForEach(tasks) { task in
                VStack(alignment: .leading, spacing: 5) {
                    Label(task.title, systemImage: segment.icon).font(.headline).foregroundStyle(StudydayTheme.ink)
                    if let date = task.dueDate { Text(date, style: .date).foregroundStyle(StudydayTheme.muted) }
                    else { Text("Date unavailable or ambiguous: \(task.writtenDate ?? "not provided")").foregroundStyle(StudydayTheme.muted) }
                    if task.certainty == "tentative" { Text("Tentative").foregroundStyle(StudydayTheme.accent) }
                    if let basis = task.yearSource { Text("Year from \(basis.value); written date: \(task.writtenDate ?? "unknown")").font(.caption).foregroundStyle(StudydayTheme.muted); SyllabusSourceView(source: basis.source) }
                    SyllabusSourceView(source: task.source)
                }.frame(maxWidth: .infinity, alignment: .leading).padding(14)
                    .background(StudydayTheme.paperElevated, in: RoundedRectangle(cornerRadius: 14))
            }
        }
    }
}

enum TaskSegment: String, CaseIterable, Identifiable {
    case exams, quizzes, assignments
    var id: String { rawValue }
    var title: String { rawValue.capitalized }
    var icon: String {
        switch self {
        case .exams: "graduationcap.fill"
        case .quizzes: "questionmark.circle.fill"
        case .assignments: "checklist"
        }
    }
}
