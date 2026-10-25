import SwiftUI

struct DashboardView: View {
    let result: SyllabusResult
    let isDemo: Bool

    var body: some View {
        TimelineView(.periodic(from: .now, by: 60)) { context in
            let snapshot = DashboardSnapshot(result: result, now: context.date)
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    VStack(alignment: .leading, spacing: 5) {
                        Text(result.courseName?.value ?? result.courseCode?.value ?? "Student dashboard").font(.largeTitle.bold())
                        Text([result.courseCode?.value, result.semester?.value].compactMap { $0 }.joined(separator: " · ")).foregroundStyle(.secondary)
                        if isDemo {
                            Label("Demo · bundled verified syllabus", systemImage: "play.rectangle").font(.callout).foregroundStyle(.orange)
                        }
                    }
                    GroupBox {
                        eventList(snapshot.upcoming, snapshot: snapshot, empty: "No upcoming dated events are listed. Weekly activities do not create deadlines.")
                    } label: { Label("Upcoming events", systemImage: "calendar") }
                    if !snapshot.past.isEmpty {
                        DisclosureGroup("Past events (\(snapshot.past.count))") { eventList(snapshot.past, snapshot: snapshot, empty: "") }
                    }
                    if !snapshot.undated.isEmpty {
                        GroupBox {
                            eventList(snapshot.undated, snapshot: snapshot, empty: "")
                        } label: { Label("Dates unavailable or ambiguous", systemImage: "questionmark.circle") }
                    }
                    grading
                    schedule
                    AssistantChatView(result: result)
                    if !result.warnings.isEmpty {
                        DisclosureGroup("Extraction notes (\(result.warnings.count))") {
                            VStack(alignment: .leading, spacing: 6) {
                                ForEach(result.warnings, id: \.self) { Text($0).font(.caption).foregroundStyle(.secondary) }
                            }.frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                }
                .frame(maxWidth: 900, alignment: .leading)
                .frame(maxWidth: .infinity)
                .padding(20)
            }
        }
    }

    private func eventList(_ events: [DashboardEvent], snapshot: DashboardSnapshot, empty: String) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            if events.isEmpty { Text(empty).foregroundStyle(.secondary) }
            ForEach(events) { item in
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(item.event.title).font(.headline)
                        Spacer()
                        if item.event.certainty == "tentative" { Text("Tentative").font(.caption).foregroundStyle(.orange) }
                        Text(item.normalized.map { snapshot.dateText($0.date) } ?? "Date unknown").fontWeight(.medium)
                    }
                    Text(item.courseName).font(.caption).foregroundStyle(.secondary)
                    if let basis = item.normalized?.yearFromSemester {
                        Text("Year from \(basis.value); written date: \(item.event.dateText ?? "unknown").").font(.caption).foregroundStyle(.secondary)
                        SourceEvidenceView(source: basis.source)
                    } else if item.normalized == nil {
                        Text("As written: \(item.event.dateText ?? "date not provided"). No date has been guessed.").font(.caption).foregroundStyle(.secondary)
                    }
                    SourceEvidenceView(source: item.event.source)
                }
            }
        }.padding(8).frame(maxWidth: .infinity, alignment: .leading)
    }

    private var grading: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 14) {
                Text("Course weights from the syllabus. Student scores are not available.").font(.callout).foregroundStyle(.secondary)
                if result.grading.isEmpty { Text("Grading weights are unavailable.").foregroundStyle(.secondary) }
                ForEach(Array(result.grading.enumerated()), id: \.offset) { _, item in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(item.category)
                            Spacer()
                            Text(DashboardSnapshot.percentage(item).map(DashboardSnapshot.percentText) ?? "Weight unknown").monospacedDigit()
                        }
                        if let value = DashboardSnapshot.percentage(item) {
                            ProgressView(value: value, total: 100).tint(.accentColor)
                                .accessibilityLabel("\(item.category): \(DashboardSnapshot.percentText(value)) of course grade")
                        }
                        SourceEvidenceView(source: item.source)
                    }
                }
                if !result.gradeScale.isEmpty {
                    Divider()
                    Text("Letter-grade thresholds").font(.headline)
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], alignment: .leading, spacing: 10) {
                        ForEach(Array(result.gradeScale.sorted { ($0.lowerBound ?? -.infinity) > ($1.lowerBound ?? -.infinity) }.enumerated()), id: \.offset) { _, threshold in
                            VStack(alignment: .leading, spacing: 2) {
                                Text("\(threshold.grade): \(threshold.rangeText)")
                                SourceEvidenceView(source: threshold.source)
                            }.frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                }
                if !result.gradingPolicies.isEmpty {
                    Divider()
                    Text("Grading policies").font(.headline)
                    ForEach(Array(result.gradingPolicies.enumerated()), id: \.offset) { _, policy in
                        VStack(alignment: .leading, spacing: 3) {
                            Text(policy.value)
                            SourceEvidenceView(source: policy.source)
                        }
                    }
                }
            }.padding(8).frame(maxWidth: .infinity, alignment: .leading)
        } label: { Label("Grading overview", systemImage: "chart.bar.xaxis") }
    }

    private var schedule: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 12) {
                if result.classSchedules.isEmpty { Text("A regular class schedule is unavailable.").foregroundStyle(.secondary) }
                ForEach(Array(result.classSchedules.enumerated()), id: \.offset) { _, schedule in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(schedule.days.joined(separator: " and ")).font(.headline)
                        Text(schedule.timeText)
                        SourceEvidenceView(source: schedule.source)
                    }
                }
            }.padding(8).frame(maxWidth: .infinity, alignment: .leading)
        } label: { Label("Course schedule", systemImage: "clock") }
    }
}

struct SourceEvidenceView: View {
    let source: SourceReference
    var body: some View {
        DisclosureGroup("Syllabus source\(source.page.map { " · page \($0)" } ?? " · pasted text")\(source.textOrigin == .rawPDFText ? " · raw PDF text" : "")") {
            Text(source.quote).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }.font(.caption).foregroundStyle(.secondary)
    }
}

private struct ChatTurn: Identifiable {
    let id = UUID()
    let question: String
    var reply: AssistantReply?
}

struct AssistantChatView: View {
    let result: SyllabusResult
    @State private var question = ""
    @State private var turns: [ChatTurn] = []
    @State private var isThinking = false
    @State private var replyTask: Task<Void, Never>?
    private let suggestions = ["When is my next exam?", "How much is Exam 2 worth?", "What happens if I miss a quiz?", "Do we have a final exam?", "What days do I have class?"]

    var body: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 12) {
                Text("Answers use this course's syllabus. Exact dates and weights are deterministic; other questions can use local model source selection. Chat stays in memory for this dashboard session.")
                    .font(.callout).foregroundStyle(.secondary)
                Text(ModelAvailability.isAvailable ? "On-device model available" : "Local model unavailable. Common questions still have deterministic answers.")
                    .font(.caption).foregroundStyle(.secondary)
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 220))], alignment: .leading) {
                    ForEach(suggestions, id: \.self) { suggestion in
                        Button(suggestion) { send(suggestion) }.buttonStyle(.bordered).disabled(isThinking)
                    }
                }
                ForEach(turns) { turn in
                    VStack(alignment: .leading, spacing: 7) {
                        Text(turn.question).fontWeight(.semibold)
                        if let reply = turn.reply {
                            Text(reply.text).textSelection(.enabled)
                            Text(reply.mode.rawValue).font(.caption).foregroundStyle(.secondary)
                            ForEach(Array(reply.sources.enumerated()), id: \.offset) { _, source in SourceEvidenceView(source: source) }
                        } else { ProgressView("Reading syllabus data…").controlSize(.small) }
                    }
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 8))
                }
                HStack {
                    TextField("Ask about exams, weights, policies, or schedules", text: $question).textFieldStyle(.roundedBorder)
                        .onSubmit { send(question) }.disabled(isThinking)
                    Button("Ask") { send(question) }.disabled(isThinking || question.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }.padding(8).frame(maxWidth: .infinity, alignment: .leading)
        } label: { Label("Ask Assistant", systemImage: "bubble.left.and.bubble.right") }
        .onDisappear { replyTask?.cancel(); isThinking = false }
    }

    private func send(_ text: String) {
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !isThinking else { return }
        let turn = ChatTurn(question: text)
        turns.append(turn)
        question = ""
        isThinking = true
        replyTask = Task {
            let reply = await SyllabusAssistant.answer(text, result: result)
            guard !Task.isCancelled else { return }
            if let index = turns.firstIndex(where: { $0.id == turn.id }) { turns[index].reply = reply }
            isThinking = false
        }
    }
}
