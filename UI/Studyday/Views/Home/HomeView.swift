import SwiftUI

struct HomeView: View {
    @EnvironmentObject private var appModel: AppModel

    var body: some View {
        NavigationStack {
            ZStack {
                StudydayBackground()

                if appModel.courses.isEmpty {
                    emptyState
                } else {
                    ScrollView {
                        LazyVStack(spacing: 14) {
                            headerBlurb
                            ForEach(appModel.courses) { course in
                                NavigationLink(value: course.id) {
                                    CourseRow(course: course)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(16)
                        .frame(maxWidth: 1000)
                        .frame(maxWidth: .infinity)
                    }
                }
            }
            .navigationTitle("Home")
            .navigationDestination(for: String.self) { courseID in
                CourseDetailView(courseID: courseID)
            }
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        appModel.selectedTab = .chat
                    } label: {
                        Image(systemName: "plus.bubble")
                            .foregroundStyle(StudydayTheme.accent)
                    }
                    .accessibilityLabel("Open AI chat to add syllabus")
                }
            }
        }
    }

    private var headerBlurb: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Your courses")
                .font(.system(size: 28, weight: .semibold, design: .rounded))
                .foregroundStyle(StudydayTheme.ink)
            Text("A clearer course — open for exams, quizzes, and assignments. Edit anytime if extraction missed something.")
                .font(.system(size: 15, design: .rounded))
                .foregroundStyle(StudydayTheme.muted)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.bottom, 4)
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            ZStack(alignment: .topTrailing) {
                RoundedRectangle(cornerRadius: StudydayTheme.cornerIcon, style: .continuous)
                    .fill(StudydayTheme.paperElevated)
                    .overlay(
                        RoundedRectangle(cornerRadius: StudydayTheme.cornerIcon, style: .continuous)
                            .stroke(StudydayTheme.borderSoft, lineWidth: 1)
                    )
                    .frame(width: 76, height: 76)
                    .overlay(
                        Image(systemName: "rectangle.stack.badge.plus")
                            .font(.system(size: 28, weight: .medium))
                            .foregroundStyle(StudydayTheme.ink)
                    )
                Circle()
                    .fill(StudydayTheme.accent)
                    .frame(width: 14, height: 14)
                    .offset(x: 3, y: -3)
            }
            Text("No courses yet")
                .font(.system(size: 22, weight: .semibold, design: .rounded))
                .foregroundStyle(StudydayTheme.ink)
            Text("Use AI Chat → + Add syllabus. Your syllabus, made manageable — then it shows up here.")
                .font(.system(size: 15, design: .rounded))
                .foregroundStyle(StudydayTheme.muted)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            Button {
                appModel.selectedTab = .chat
            } label: {
                Text("Open AI Chat")
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 22)
                    .frame(minHeight: 48)
                    .background(Capsule().fill(StudydayTheme.ink))
            }
            .buttonStyle(.plain)
        }
    }
}

private struct CourseRow: View {
    let course: CourseItem

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(StudydayTheme.mist)
                .frame(width: 48, height: 48)
                .overlay(
                    Text(shortCode)
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .foregroundStyle(StudydayTheme.iconBlue)
                        .multilineTextAlignment(.center)
                        .padding(4)
                )

            VStack(alignment: .leading, spacing: 4) {
                Text(course.code + (course.isDemo ? " · Demo" : ""))
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(StudydayTheme.accent)
                Text(course.title)
                    .font(.system(size: 17, weight: .semibold, design: .rounded))
                    .foregroundStyle(StudydayTheme.ink)
                    .lineLimit(2)
                Text("\(course.term) · \(course.instructor)")
                    .font(.system(size: 12, design: .rounded))
                    .foregroundStyle(StudydayTheme.muted)
                HStack(spacing: 10) {
                    metaChip(icon: "graduationcap", value: "\(course.exams.count) listed exams")
                    metaChip(icon: "questionmark.circle", value: "\(course.quizzes.count) listed quizzes")
                    metaChip(icon: "checklist", value: "\(course.assignments.count) listed tasks")
                }
                .padding(.top, 4)
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(StudydayTheme.muted)
                .padding(.top, 6)
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: StudydayTheme.cornerCard, style: .continuous)
                .fill(StudydayTheme.paperElevated)
                .overlay(
                    RoundedRectangle(cornerRadius: StudydayTheme.cornerCard, style: .continuous)
                        .stroke(StudydayTheme.border, lineWidth: 1)
                )
        )
    }

    private var shortCode: String {
        let parts = course.code.split(separator: " ")
        if parts.count >= 2 {
            return String(parts[0].prefix(3)) + "\n" + String(parts[1].prefix(3))
        }
        return String(course.code.prefix(4))
    }

    private func metaChip(icon: String, value: String) -> some View {
        Label(value, systemImage: icon)
            .font(.system(size: 11, weight: .medium, design: .rounded))
            .foregroundStyle(StudydayTheme.muted)
            .labelStyle(.titleAndIcon)
    }
}

#Preview {
    HomeView()
        .environmentObject(AppModel())
}
