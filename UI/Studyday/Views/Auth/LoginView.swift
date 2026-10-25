import SwiftUI

/// Welcome / login matching the Studyday MHTML mockup layout and copy.
struct LoginView: View {
    @EnvironmentObject private var appModel: AppModel
    @State private var appear = false
    @State private var showProviders = false

    var body: some View {
        ZStack {
            StudydayBackground()

            VStack(spacing: 0) {
                topBar
                    .padding(.horizontal, 26)
                    .padding(.top, 18)

                ScrollView(showsIndicators: false) {
                    VStack(spacing: 0) {
                        hero
                            .padding(.top, 36)
                        if showProviders {
                            providerStack
                                .padding(.top, 28)
                                .transition(.move(edge: .bottom).combined(with: .opacity))
                        } else {
                            ctaStack
                                .padding(.top, 28)
                        }
                    }
                    .padding(.horizontal, 26)
                    .padding(.bottom, 28)
                }
            }.frame(maxWidth: 560)
        }
        .onAppear {
            withAnimation(.spring(response: 0.55, dampingFraction: 0.86)) {
                appear = true
            }
        }
    }

    private var topBar: some View {
        HStack(alignment: .center) {
            HStack(spacing: 0) {
                Text("studyday")
                    .font(.system(size: 25, weight: .semibold, design: .rounded))
                    .foregroundStyle(StudydayTheme.ink)
                    .tracking(-0.4)
                Text("·")
                    .font(.system(size: 25, weight: .semibold, design: .rounded))
                    .foregroundStyle(StudydayTheme.accent)
            }
            Spacer()
            Text("A LITTLE LESS OVERWHELM")
                .font(.system(size: 7, weight: .semibold, design: .rounded))
                .tracking(0.8)
                .foregroundStyle(StudydayTheme.sage)
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .overlay(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .stroke(StudydayTheme.badgeBorder, lineWidth: 1)
                )
        }
        .opacity(appear ? 1 : 0)
    }

    private var hero: some View {
        VStack(spacing: 0) {
            ZStack(alignment: .topTrailing) {
                RoundedRectangle(cornerRadius: StudydayTheme.cornerIcon, style: .continuous)
                    .fill(StudydayTheme.paperElevated)
                    .overlay(
                        RoundedRectangle(cornerRadius: StudydayTheme.cornerIcon, style: .continuous)
                            .stroke(StudydayTheme.borderSoft, lineWidth: 1)
                    )
                    .frame(width: 76, height: 76)
                    .overlay(
                        Image(systemName: "book.closed.fill")
                            .font(.system(size: 30, weight: .medium))
                            .foregroundStyle(StudydayTheme.ink)
                    )

                Circle()
                    .fill(StudydayTheme.accent)
                    .frame(width: 14, height: 14)
                    .offset(x: 3, y: -3)
            }
            .scaleEffect(appear ? 1 : 0.9)
            .opacity(appear ? 1 : 0)

            VStack(spacing: 15) {
                Text("Your semester.\nA little lighter.")
                    .font(.system(size: 36, weight: .semibold, design: .rounded))
                    .tracking(-0.6)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(StudydayTheme.ink)
                    .lineSpacing(2)

                Text("All your courses, deadlines, and next steps.\nOne calm place to begin.")
                    .font(.system(size: 15, weight: .regular, design: .rounded))
                    .multilineTextAlignment(.center)
                    .foregroundStyle(StudydayTheme.muted)
                    .lineSpacing(3)
            }
            .padding(.top, 28)
            .opacity(appear ? 1 : 0)
            .offset(y: appear ? 0 : 10)

            previewCard
                .padding(.top, 28)
                .opacity(appear ? 1 : 0)
        }
        .frame(maxWidth: .infinity)
    }

    private var previewCard: some View {
        ZStack {
            RoundedRectangle(cornerRadius: StudydayTheme.cornerCard, style: .continuous)
                .fill(StudydayTheme.mistDeep)
                .overlay(
                    RoundedRectangle(cornerRadius: StudydayTheme.cornerCard, style: .continuous)
                        .stroke(StudydayTheme.border, lineWidth: 1)
                )
                .rotationEffect(.degrees(-5))
                .offset(y: 8)
                .padding(.horizontal, 7)

            HStack(spacing: 13) {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(StudydayTheme.mist)
                    .frame(width: 48, height: 48)
                    .overlay(
                        Image(systemName: "doc.text.fill")
                            .font(.system(size: 20, weight: .medium))
                            .foregroundStyle(StudydayTheme.iconBlue)
                    )

                VStack(alignment: .leading, spacing: 5) {
                    Text("A clearer course")
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                        .foregroundStyle(StudydayTheme.ink)
                    Text("Your syllabus, made manageable")
                        .font(.system(size: 11, weight: .regular, design: .rounded))
                        .foregroundStyle(StudydayTheme.muted)
                }

                Spacer(minLength: 0)

                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 19, weight: .medium))
                    .foregroundStyle(StudydayTheme.softGreen)
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: StudydayTheme.cornerCard, style: .continuous)
                    .fill(StudydayTheme.paperElevated)
                    .overlay(
                        RoundedRectangle(cornerRadius: StudydayTheme.cornerCard, style: .continuous)
                            .stroke(StudydayTheme.border, lineWidth: 1)
                    )
            )
        }
        .frame(maxWidth: 340)
        .frame(height: 88)
    }

    private var ctaStack: some View {
        VStack(spacing: 12) {
            Button {
                withAnimation(.spring(response: 0.45, dampingFraction: 0.88)) {
                    showProviders = true
                }
            } label: {
                HStack(spacing: 8) {
                    Text("Get started")
                        .font(.system(size: 16, weight: .semibold, design: .rounded))
                    Image(systemName: "arrow.right")
                        .font(.system(size: 15, weight: .semibold))
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .frame(minHeight: 58)
                .background(
                    RoundedRectangle(cornerRadius: StudydayTheme.corner, style: .continuous)
                        .fill(StudydayTheme.ink)
                )
            }
            .buttonStyle(.plain)

            Button {
                appModel.tryDemo()
            } label: {
                Text("Try the verified demo")
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                    .foregroundStyle(StudydayTheme.ink)
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: 58)
                    .background(
                        RoundedRectangle(cornerRadius: StudydayTheme.corner, style: .continuous)
                            .fill(StudydayTheme.chipFill)
                    )
            }
            .buttonStyle(.plain)
            .disabled(appModel.isAuthenticating)

            if appModel.isAuthenticating {
                ProgressView()
                    .tint(StudydayTheme.ink)
            }

            if let authError = appModel.authError {
                Text(authError)
                    .font(.footnote)
                    .foregroundStyle(StudydayTheme.danger)
            }

            Text("A little structure. More room to breathe.")
                .font(.system(size: 11, weight: .regular, design: .rounded))
                .foregroundStyle(StudydayTheme.muted)
                .multilineTextAlignment(.center)
                .padding(.top, 6)
        }
    }

    private var providerStack: some View {
        VStack(spacing: 12) {
            Text("Continue with")
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .foregroundStyle(StudydayTheme.muted)

            ForEach(AuthProvider.allCases) { provider in
                Button {
                    appModel.signIn(provider: provider)
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: provider.systemImage)
                            .font(.system(size: 17, weight: .semibold))
                            .frame(width: 22)
                        Text(provider.title)
                            .font(.system(size: 16, weight: .semibold, design: .rounded))
                        Spacer()
                        if appModel.isAuthenticating {
                            ProgressView().tint(StudydayTheme.ink)
                        }
                    }
                    .foregroundStyle(StudydayTheme.ink)
                    .padding(.horizontal, 18)
                    .frame(minHeight: 58)
                    .background(
                        RoundedRectangle(cornerRadius: StudydayTheme.corner, style: .continuous)
                            .fill(StudydayTheme.paperElevated)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: StudydayTheme.corner, style: .continuous)
                            .stroke(StudydayTheme.border, lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)
                .disabled(appModel.isAuthenticating)
            }

            Button {
                withAnimation(.spring(response: 0.4, dampingFraction: 0.9)) {
                    showProviders = false
                }
            } label: {
                Text("Back")
                    .font(.system(size: 14, weight: .medium, design: .rounded))
                    .foregroundStyle(StudydayTheme.muted)
            }
            .buttonStyle(.plain)
            .padding(.top, 4)

            Text("Private local workspace. No Google, Apple ID, or campus account is signed in. No network required.")
                .font(.system(size: 11, design: .rounded))
                .foregroundStyle(StudydayTheme.muted)
                .multilineTextAlignment(.center)
        }
    }
}

#Preview {
    LoginView()
        .environmentObject(AppModel())
}
