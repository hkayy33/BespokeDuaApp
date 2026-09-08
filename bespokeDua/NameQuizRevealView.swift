import SwiftUI

struct NameQuizRevealView: View {
    let link: NameQuizDeepLink
    var onBrowseAllNames: () -> Void = {}

    @Environment(\.dismiss) private var dismiss
    @Environment(\.mainTabBarClearance) private var mainTabBarClearance

    @State private var name: AllahNameDetail?
    @State private var loading = true
    @State private var errorMessage: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                if loading && name == nil {
                    loadingState
                } else if let name {
                    revealCard(name)
                    browseButton
                } else {
                    errorState
                }
            }
            .bespokeLibraryContentFrame()
            .padding(.horizontal, BespokeLayout.libraryHorizontalPadding)
            .padding(.top, 16)
            .padding(.bottom, 28 + mainTabBarClearance)
        }
        .scrollIndicators(.hidden, axes: .vertical)
        .background(BespokeColor.pageBackground)
        .toolbar(.hidden, for: .navigationBar)
        .navigationBarBackButtonHidden(true)
        .safeAreaInset(edge: .top, spacing: 0) {
            BespokeFlowBackHeader(title: "Daily 99 name", onBack: { dismiss() })
        }
        .bespokeEdgeBackNavigation(hidesNavigationBar: true)
        .task(id: link.nameNumber) {
            await loadName()
        }
    }

    private func revealCard(_ name: AllahNameDetail) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(spacing: 8) {
                Text("Daily 99 name")
                    .font(BespokeFont.inter(13, weight: .semibold))
                    .foregroundStyle(BespokeColor.muted)

                Text(name.arabic)
                    .font(BespokeFont.display(40))
                    .foregroundStyle(BespokeColor.forest)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
                    .minimumScaleFactor(0.7)
                    .environment(\.layoutDirection, .rightToLeft)

                Text(name.transliteration)
                    .font(BespokeFont.inter(16, weight: .semibold))
                    .foregroundStyle(BespokeColor.nameGold)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)

                Text(name.translation)
                    .font(BespokeFont.display(22))
                    .foregroundStyle(BespokeColor.forest)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 24)
            .frame(maxWidth: .infinity)
            .background(
                LinearGradient(
                    colors: [
                        BespokeColor.cream,
                        BespokeColor.cream.opacity(0.35),
                        Color.white
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )

            VStack(alignment: .leading, spacing: 12) {
                if let feeling = feelingTitle(for: name) {
                    Text(feeling)
                        .font(BespokeFont.inter(12, weight: .semibold))
                        .foregroundStyle(BespokeColor.forest)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(BespokeColor.homeMintIcon)
                        .clipShape(Capsule())
                }

                Capsule()
                    .fill(BespokeColor.gold.opacity(0.45))
                    .frame(width: 28, height: 2)

                Text(name.meaning.isEmpty ? name.translation : name.meaning)
                    .font(BespokeFont.inter(16, weight: .regular))
                    .foregroundStyle(BespokeColor.bodyText)
                    .lineSpacing(4)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 18)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(BespokeColor.forest.opacity(0.07), lineWidth: 1)
        }
        .shadow(color: BespokeColor.forest.opacity(0.07), radius: 14, x: 0, y: 6)
    }

    private var browseButton: some View {
        Button(action: onBrowseAllNames) {
            Text("Open the 99 names")
                .font(BespokeFont.inter(15, weight: .semibold))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(BespokeColor.forest)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .bespokeButtonHitArea(cornerRadius: 16)
        }
        .buttonStyle(BespokePlainButtonStyle())
    }

    private var loadingState: some View {
        VStack(spacing: 16) {
            ProgressView()
                .tint(BespokeColor.forest)
            Text("Opening this name…")
                .font(BespokeFont.inter(15, weight: .medium))
                .foregroundStyle(BespokeColor.muted)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 32)
    }

    private var errorState: some View {
        VStack(spacing: 12) {
            Text(errorMessage ?? "Couldn't open this name just now.")
                .font(BespokeFont.inter(15, weight: .regular))
                .foregroundStyle(BespokeColor.muted)
                .multilineTextAlignment(.center)

            Button("Try again") {
                Task { await loadName() }
            }
            .font(BespokeFont.inter(15, weight: .semibold))
            .foregroundStyle(BespokeColor.forest)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
    }

    private func feelingTitle(for name: AllahNameDetail) -> String? {
        let title = name.feelingLabel
            .components(separatedBy: ",")
            .first?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !title.isEmpty else { return nil }
        return "When you are \(title.lowercased())"
    }

    @MainActor
    private func loadName() async {
        loading = true
        errorMessage = nil
        defer { loading = false }

        do {
            name = try await HomeNameOfTheDayService.name(number: link.nameNumber)
        } catch {
            name = nil
            errorMessage = "Check your connection and try again."
        }
    }
}

struct NameQuizWhatsNewModal: View {
    @Binding var isPresented: Bool

    var body: some View {
        ZStack {
            BespokeColor.authBackdrop
                .ignoresSafeArea()
                .background(.ultraThinMaterial.opacity(0.35))
                .onTapGesture { isPresented = false }

            ScrollView {
                VStack(spacing: 0) {
                    header
                    bodyContent
                }
                .frame(maxWidth: 420)
                .background(BespokeColor.pageBackground)
                .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 28, style: .continuous)
                        .stroke(Color.white.opacity(0.55), lineWidth: 1)
                }
                .shadow(color: BespokeColor.forest.opacity(0.22), radius: 36, x: 0, y: 22)
                .padding(.horizontal, 20)
                .padding(.vertical, 24)
                .frame(maxWidth: .infinity)
            }
            .scrollIndicators(.hidden)
        }
    }

    private var header: some View {
        ZStack(alignment: .topTrailing) {
            LinearGradient(
                colors: [
                    Color(red: 0.10, green: 0.28, blue: 0.22),
                    BespokeColor.forest,
                    Color(red: 0.16, green: 0.38, blue: 0.28)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            Circle()
                .fill(BespokeColor.gold.opacity(0.18))
                .frame(width: 160, height: 160)
                .blur(radius: 8)
                .offset(x: 110, y: -46)

            Circle()
                .fill(Color.white.opacity(0.06))
                .frame(width: 120, height: 120)
                .offset(x: -130, y: 54)

            VStack(alignment: .leading, spacing: 14) {
                Text("WHAT'S NEW")
                    .font(BespokeFont.inter(11, weight: .semibold))
                    .tracking(1.1)
                    .foregroundStyle(BespokeColor.iconHandGold)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Color.white.opacity(0.1))
                    .clipShape(Capsule())

                Text("Today's name")
                    .font(BespokeFont.display(32))
                    .foregroundStyle(.white)

                Text("One name each morning, with its meaning, so the 99 names stay close.")
                    .font(BespokeFont.inter(15, weight: .regular))
                    .foregroundStyle(Color.white.opacity(0.82))
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 22)
            .padding(.top, 28)
            .padding(.bottom, 22)

            Button {
                isPresented = false
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(.white.opacity(0.9))
                    .frame(width: 32, height: 32)
                    .background(Color.white.opacity(0.14))
                    .clipShape(Circle())
            }
            .buttonStyle(BespokePlainButtonStyle())
            .padding(14)
            .accessibilityLabel("Close")
        }
        .clipped()
    }

    private var bodyContent: some View {
        VStack(alignment: .leading, spacing: 16) {
            notificationPreview

            VStack(spacing: 0) {
                whatsNewRow(
                    icon: "sun.horizon.fill",
                    title: "Each morning",
                    detail: "A new name arrives at 9:00."
                )
                divider
                whatsNewRow(
                    icon: "text.book.closed.fill",
                    title: "Name and meaning",
                    detail: "The reminder shows both, no extra searching."
                )
                divider
                whatsNewRow(
                    icon: "hand.tap.fill",
                    title: "Open the name",
                    detail: "Tap the notification to read it in full."
                )
            }
            .background(Color.white)
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(BespokeColor.cardBorder, lineWidth: 1)
            }

            Button {
                isPresented = false
            } label: {
                Text("Continue")
                    .font(BespokeFont.inter(16, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 15)
                    .background(BespokeColor.forest)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .bespokeButtonHitArea(cornerRadius: 16)
            }
            .buttonStyle(BespokePlainButtonStyle())
        }
        .padding(18)
    }

    private var notificationPreview: some View {
        HStack(alignment: .top, spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(BespokeColor.forest)
                Image(systemName: "moon.stars.fill")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(BespokeColor.iconHandGold)
            }
            .frame(width: 38, height: 38)

            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline) {
                    Text("BESPOKEDUA")
                        .font(BespokeFont.inter(11, weight: .semibold))
                        .tracking(0.4)
                        .foregroundStyle(BespokeColor.muted)
                    Spacer(minLength: 8)
                    Text("now")
                        .font(BespokeFont.inter(11, weight: .medium))
                        .foregroundStyle(BespokeColor.subtle)
                }

                Text("Today's name")
                    .font(BespokeFont.inter(13, weight: .semibold))
                    .foregroundStyle(BespokeColor.forest)

                Text("Ar-Rahman")
                    .font(BespokeFont.display(22))
                    .foregroundStyle(BespokeColor.forest)

                Text("The Most Merciful. He who wills goodness and mercy for all His creation.")
                    .font(BespokeFont.inter(13, weight: .regular))
                    .foregroundStyle(BespokeColor.bodyText.opacity(0.88))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(14)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(BespokeColor.gold.opacity(0.28), lineWidth: 1)
        }
        .shadow(color: BespokeColor.forest.opacity(0.06), radius: 12, x: 0, y: 6)
    }

    private var divider: some View {
        Rectangle()
            .fill(BespokeColor.sectionRule)
            .frame(height: 1)
            .padding(.leading, 58)
    }

    private func whatsNewRow(icon: String, title: String, detail: String) -> some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(BespokeColor.forest)
                .frame(width: 32, height: 32)
                .background(BespokeColor.homeMintIcon)
                .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(BespokeFont.inter(14, weight: .semibold))
                    .foregroundStyle(BespokeColor.forest)
                Text(detail)
                    .font(BespokeFont.inter(13, weight: .regular))
                    .foregroundStyle(BespokeColor.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 11)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct NameQuizSettingsCard: View {
    @Environment(NameQuizNotificationService.self) private var quiz

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "bell.badge")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(BespokeColor.forest)
                    .frame(width: 36, height: 36)
                    .background(BespokeColor.homeMintIcon)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

                VStack(alignment: .leading, spacing: 4) {
                    Text("Daily 99 name")
                        .font(BespokeFont.inter(17, weight: .semibold))
                        .foregroundStyle(BespokeColor.forest)

                    Text("A morning reminder with one of the 99 names and its meaning. Tap it to open that name.")
                        .font(BespokeFont.inter(14, weight: .regular))
                        .foregroundStyle(BespokeColor.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Toggle(isOn: remindersBinding) {
                Text(quiz.remindersAreOn ? "Daily reminder on" : "Daily reminder")
                    .font(BespokeFont.inter(15, weight: .medium))
                    .foregroundStyle(BespokeColor.bodyText)
            }
            .tint(BespokeColor.forest)
            .disabled(quiz.isUpdating)

            if quiz.prefersReminders {
                DatePicker(
                    "Reminder time",
                    selection: reminderDate,
                    displayedComponents: .hourAndMinute
                )
                .font(BespokeFont.inter(15, weight: .medium))
                .foregroundStyle(BespokeColor.bodyText)
                .disabled(quiz.isUpdating || !quiz.isAuthorized)
            }

            if let statusMessage = quiz.statusMessage, !statusMessage.isEmpty {
                Text(statusMessage)
                    .font(BespokeFont.inter(13, weight: .medium))
                    .foregroundStyle(BespokeColor.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if quiz.prefersReminders && quiz.authorizationStatus == .denied {
                Button("Open Settings") {
                    quiz.openSystemSettings()
                }
                .font(BespokeFont.inter(14, weight: .semibold))
                .foregroundStyle(BespokeColor.forest)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(BespokeColor.cardBorder, lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.04), radius: 10, x: 0, y: 4)
        .task {
            await quiz.refreshAuthorizationStatus()
        }
    }

    private var remindersBinding: Binding<Bool> {
        Binding(
            get: { quiz.prefersReminders && quiz.authorizationStatus != .denied },
            set: { enabled in
                BespokeHaptics.toggle()
                Task { await quiz.setRemindersEnabled(enabled) }
            }
        )
    }

    private var reminderDate: Binding<Date> {
        Binding(
            get: {
                Calendar.current.date(
                    bySettingHour: quiz.reminderHour,
                    minute: quiz.reminderMinute,
                    second: 0,
                    of: .now
                ) ?? .now
            },
            set: { newValue in
                let components = Calendar.current.dateComponents([.hour, .minute], from: newValue)
                Task {
                    await quiz.updateReminderTime(
                        hour: components.hour ?? NameQuizNotificationService.defaultHour,
                        minute: components.minute ?? NameQuizNotificationService.defaultMinute
                    )
                }
            }
        )
    }
}
