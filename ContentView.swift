//
//  ContentView.swift
//  bespokeDua
//
//  Created by Hassan Kambala on 25/03/2026.
//

import SwiftUI
#if canImport(UIKit)
import UIKit
#endif
#if canImport(AppKit)
import AppKit
#endif

// MARK: - Reflection modal (presented from dua cards via environment)

private struct PresentReflectionModalKey: EnvironmentKey {
    static var defaultValue: (([ExplanationModel]) -> Void)? { nil }
}

extension EnvironmentValues {
    var presentReflectionModal: (([ExplanationModel]) -> Void)? {
        get { self[PresentReflectionModalKey.self] }
        set { self[PresentReflectionModalKey.self] = newValue }
    }
}

struct ContentView: View {
    @Environment(AppSession.self) private var session
    @State private var requestText = ""
    @State private var generated: [DuaReceiver] = []
    @State private var generateInFlight = false
    @State private var generateError: String?
    @State private var selectedTab: MainTab = .home
    @State private var emptyRequestWarning = false
    @State private var showAimModal = false
    @State private var savedDuaIDs: Set<UUID> = []
    /// Server `SavedDuas` id for each generated card, required to DELETE when unsaving.
    @State private var savedDuaServerIdByLocalId: [UUID: String] = [:]
    @FocusState private var duaFieldFocused: Bool
    @State private var showAccountDrawer = false
    @State private var showUpgradeInfoModal = false
    @State private var showReflectionModal = false
    @State private var reflectionModalExplanations: [ExplanationModel] = []

    private enum MainTab: Hashable {
        case home
        case saved
    }

    var body: some View {
        TabView(selection: $selectedTab) {
            NavigationStack {
                ScrollView {
                    VStack(spacing: 0) {
                        inputSection
                        Rectangle()
                            .fill(BespokeColor.sectionRule)
                            .frame(maxWidth: .infinity)
                            .frame(height: 1)
                            .padding(.vertical, 12)
                        duaResultsSection
                    }
                }
                .scrollDismissesKeyboard(.interactively)
                .background(BespokeColor.pageBackground)
                .navigationTitle("BespokeDua")
                .navigationBarTitleDisplayMode(.large)
                .toolbarBackground(LinearGradient.bespokeNavBar, for: .navigationBar)
                .toolbarBackground(.visible, for: .navigationBar)
                .toolbarColorScheme(.dark, for: .navigationBar)
                .toolbar {
                    accountLeadingToolbar()
                }
            }
            .tabItem {
                Label("Home", systemImage: "house.fill")
            }
            .tag(MainTab.home)

            NavigationStack {
                SavedDuasPageView()
                    .background(BespokeColor.pageBackground)
                    .navigationTitle("BespokeDua")
                    .navigationBarTitleDisplayMode(.inline)
                .toolbarBackground(LinearGradient.bespokeNavBar, for: .navigationBar)
                .toolbarBackground(.visible, for: .navigationBar)
                .toolbarColorScheme(.dark, for: .navigationBar)
                .toolbar {
                    accountLeadingToolbar()
                }
            }
            .tabItem {
                Label("Saved", systemImage: "bookmark.fill")
            }
            .tag(MainTab.saved)
        }
        .tint(BespokeColor.forest)
        .environment(\.presentReflectionModal) { explanations in
            reflectionModalExplanations = explanations
            showReflectionModal = true
        }
        .overlay {
            accountDrawerOverlay
        }
        .overlay {
            if showUpgradeInfoModal {
                UpgradeInfoModalView(isPresented: $showUpgradeInfoModal)
                    .transition(.opacity)
            }
        }
        .overlay {
            if showAimModal {
                BespokeCardModalView(isPresented: $showAimModal, title: "The aim") {
                    Text(
                        "We often hear, “Make du'a with yaqeen (full conviction),” but how do we do this? By calling upon Allah through His names and attributes, we remind ourselves of His mercy, power, and wisdom."
                    )
                    .font(BespokeFont.inter(16, weight: .regular))
                    .foregroundStyle(BespokeColor.bodyText)
                    .fixedSize(horizontal: false, vertical: true)

                    Text(
                        "Bespoke Dua is built on this idea, connecting your personal du'as to the reassuring ropes our Lord has hung down, so you can ask with certainty, hope, and sincerity."
                    )
                    .font(BespokeFont.inter(16, weight: .regular))
                    .foregroundStyle(BespokeColor.bodyText)
                    .fixedSize(horizontal: false, vertical: true)
                }
                .transition(.opacity)
            }
        }
        .overlay {
            if showReflectionModal {
                BespokeCardModalView(
                    isPresented: Binding(
                        get: { showReflectionModal },
                        set: { newValue in
                            showReflectionModal = newValue
                            if !newValue { reflectionModalExplanations = [] }
                        }
                    ),
                    title: "Reflection"
                ) {
                    VStack(alignment: .leading, spacing: 20) {
                        ForEach(reflectionModalExplanations) { exp in
                            VStack(alignment: .leading, spacing: 8) {
                                Text(exp.name)
                                    .font(BespokeFont.inter(16, weight: .semibold))
                                    .foregroundStyle(BespokeColor.nameGold)
                                Text(exp.explanation)
                                    .font(BespokeFont.inter(15, weight: .regular))
                                    .foregroundStyle(BespokeColor.bodyText)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.vertical, 4)
                        }
                    }
                }
                .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.28), value: showUpgradeInfoModal)
        .animation(.easeInOut(duration: 0.28), value: showAimModal)
        .animation(.easeInOut(duration: 0.28), value: showReflectionModal)
        .onChange(of: session.isLoggedIn) { _, loggedIn in
            if !loggedIn {
                selectedTab = .home
            }
        }
        .fullScreenCover(isPresented: Binding(
            get: { session.showAuthSheet },
            set: { session.showAuthSheet = $0 }
        )) {
            AuthModalView()
                .environment(session)
        }
    }

    // MARK: - Account drawer

    private func accountDrawerToolbarButton() -> some View {
        Button {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.86)) {
                showAccountDrawer = true
            }
        } label: {
            Image(systemName: "line.3.horizontal")
                .font(.system(size: 20, weight: .medium))
                .symbolRenderingMode(.monochrome)
                .foregroundStyle(.white)
        }
        .buttonStyle(.plain)
        .tint(.white)
        .accessibilityLabel("Menu")
    }

    @ToolbarContentBuilder
    private func accountLeadingToolbar() -> some ToolbarContent {
        if #available(iOS 26.0, macOS 26.0, visionOS 26.0, *) {
            ToolbarItem(placement: .topBarLeading) {
                accountDrawerToolbarButton()
            }
            .sharedBackgroundVisibility(.hidden)
        } else {
            ToolbarItem(placement: .topBarLeading) {
                accountDrawerToolbarButton()
            }
        }
    }

    private var accountDrawerOverlay: some View {
        GeometryReader { geo in
            let panelWidth = min(296, geo.size.width * 0.88)
            ZStack(alignment: .leading) {
                Color.black.opacity(showAccountDrawer ? 0.38 : 0)
                    .ignoresSafeArea()
                    .contentShape(Rectangle())
                    .onTapGesture {
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.86)) {
                            showAccountDrawer = false
                        }
                    }

                accountDrawerPanel(width: panelWidth)
                    .frame(maxHeight: .infinity)
                    .background(BespokeColor.pageBackground)
                    .shadow(color: .black.opacity(0.18), radius: 16, x: 6, y: 0)
                    .offset(x: showAccountDrawer ? 0 : -panelWidth)
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
        .allowsHitTesting(showAccountDrawer)
        .animation(.spring(response: 0.35, dampingFraction: 0.86), value: showAccountDrawer)
    }

    private func accountDrawerPanel(width: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack {
                Spacer(minLength: 0)
                Button {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.86)) {
                        showAccountDrawer = false
                    }
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title2)
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(BespokeColor.muted)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Close")
            }

            VStack(spacing: 16) {
                Image(systemName: session.isLoggedIn ? "person.crop.circle.fill" : "person.crop.circle.badge.plus")
                    .font(.system(size: 72))
                    .foregroundStyle(BespokeColor.forest)
                    .accessibilityHidden(true)

                if session.isLoggedIn {
                    VStack(spacing: 8) {
                        Text(session.currentUser?.username ?? "Account")
                            .font(BespokeFont.display(22))
                            .foregroundStyle(BespokeColor.bodyText)
                            .multilineTextAlignment(.center)
                            .padding(.bottom, 10)

                        if let user = session.currentUser {
                            Text(accountDrawerPlanHeadline(plan: user.plan))
                                .font(BespokeFont.inter(15, weight: .semibold))
                                .foregroundStyle(BespokeColor.forest)
                                .multilineTextAlignment(.center)

                            if let subtitle = accountDrawerPlanSubtitle(plan: user.plan) {
                                Text(subtitle)
                                    .font(BespokeFont.inter(13, weight: .regular))
                                    .foregroundStyle(BespokeColor.muted)
                                    .multilineTextAlignment(.center)
                                    .fixedSize(horizontal: false, vertical: true)

                                Button {
                                    withAnimation(.spring(response: 0.35, dampingFraction: 0.86)) {
                                        showAccountDrawer = false
                                    }
                                    showUpgradeInfoModal = true
                                } label: {
                                    Label("Upgrade", systemImage: "sparkles")
                                        .font(BespokeFont.inter(16, weight: .semibold))
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, 12)
                                }
                                .buttonStyle(.borderedProminent)
                                .tint(BespokeColor.gold)
                                .padding(.top, 4)
                            }
                        }
                    }
                } else {
                    Text("Not signed in")
                        .font(BespokeFont.inter(16, weight: .medium))
                        .foregroundStyle(BespokeColor.muted)
                }
            }
            .frame(maxWidth: .infinity)

            Spacer(minLength: 0)

            if session.isLoggedIn {
                Button(role: .destructive) {
                    session.logout()
                    generated = []
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.86)) {
                        showAccountDrawer = false
                    }
                } label: {
                    Label("Log out", systemImage: "rectangle.portrait.and.arrow.right")
                        .font(BespokeFont.inter(16, weight: .semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                }
                .buttonStyle(.bordered)
                .tint(BespokeColor.error)
            } else {
                Button {
                    showAccountDrawer = false
                    session.presentAuth()
                } label: {
                    Text("Sign in")
                        .font(BespokeFont.inter(17, weight: .semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                }
                .buttonStyle(.borderedProminent)
                .tint(BespokeColor.forest)
            }
        }
        .padding(24)
        .padding(.top, 8)
        .frame(width: width)
        .frame(maxHeight: .infinity, alignment: .top)
    }

    private func accountDrawerPlanHeadline(plan: String) -> String {
        let p = plan.trimmingCharacters(in: .whitespacesAndNewlines)
        if p.isEmpty || p.caseInsensitiveCompare("free") == .orderedSame {
            return "Free Plan"
        }
        if p.lowercased().hasSuffix("plan") {
            return "✨ \(p)"
        }
        return "✨ \(p) Plan"
    }

    private func accountDrawerPlanSubtitle(plan: String) -> String? {
        let p = plan.trimmingCharacters(in: .whitespacesAndNewlines)
        if p.isEmpty || p.caseInsensitiveCompare("free") == .orderedSame {
            return "Upgrade for unlimited duas"
        }
        return nil
    }

    // MARK: - Input (`input-section.scss`)

    private var inputSection: some View {
        VStack(spacing: 16) {
            VStack(spacing: 8) {
                Text("Write your heart’s dua")
                    .font(BespokeFont.display(26))
                    .foregroundStyle(BespokeColor.forest)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)

                Button {
                    showAimModal = true
                } label: {
                    Label("The aim ?", systemImage: "sparkles")
                        .font(BespokeFont.inter(14, weight: .medium))
                        .foregroundStyle(BespokeColor.nameGold)
                }
                .buttonStyle(.plain)
            }
            .padding(.top, 11)

            VStack(alignment: .leading, spacing: 12) {

                ZStack(alignment: .topLeading) {
                    if requestText.isEmpty {
                        Text("Type your dua here…")
                            .font(BespokeFont.inter(16, weight: .regular))
                            .foregroundStyle(BespokeColor.subtle)
                            .padding(.top, 12)
                            .padding(.leading, 10)
                            .allowsHitTesting(false)
                    }
                    TextEditor(text: $requestText)
                        .font(BespokeFont.inter(16, weight: .regular))
                        .foregroundStyle(BespokeColor.bodyText)
                        .scrollContentBackground(.hidden)
                        .frame(minHeight: 120)
                        .focused($duaFieldFocused)
                }
                .padding(12)
                .background(BespokeColor.inputSurface)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(duaFieldFocused ? BespokeColor.gold : BespokeColor.forest.opacity(0.12), lineWidth: duaFieldFocused ? 2 : 1)
                )
                .shadow(color: duaFieldFocused ? BespokeColor.gold.opacity(0.12) : .black.opacity(0.04), radius: 8, x: 0, y: 2)

                Text("Example: “O Allah, grant me success in…”")
                    .font(BespokeFont.inter(13, weight: .regular))
                    .foregroundStyle(BespokeColor.muted)
            }
            .padding(18)
            .frame(maxWidth: .infinity)
            .background(Color.white)
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .stroke(BespokeColor.cardBorder, lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.06), radius: 16, x: 0, y: 6)

            Button {
                submitGenerate()
            } label: {
                HStack(spacing: 10) {
                    if generateInFlight {
                        ProgressView()
                            .tint(.white)
                        Text("Generating…")
                            .font(BespokeFont.inter(17, weight: .semibold))
                    } else {
                        Text("Bespoke my dua")
                            .font(BespokeFont.inter(17, weight: .semibold))
                    }
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(LinearGradient.bespokeGold)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .shadow(color: generateInFlight ? .clear : .black.opacity(0.14), radius: 12, x: 0, y: 6)
            }
            .buttonStyle(.plain)
            .disabled(generateInFlight)
            .opacity(generateInFlight ? 0.72 : 1)

            if emptyRequestWarning {
                Label("Please write your dua first.", systemImage: "exclamationmark.circle.fill")
                    .font(BespokeFont.inter(14, weight: .medium))
                    .foregroundStyle(BespokeColor.error)
            }

            if generateError != nil {
                Label("Something went wrong. Try again.", systemImage: "wifi.exclamationmark")
                    .font(BespokeFont.inter(14, weight: .medium))
                    .foregroundStyle(BespokeColor.error)
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 8)
        .padding(.bottom, 24)
        .frame(maxWidth: .infinity)
    }

    // MARK: - Results (`dua-result` + list + card)

    private var duaResultsSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Your duas")
                    .font(BespokeFont.inter(20, weight: .semibold))
                    .foregroundStyle(BespokeColor.forest)
//                Text("Personalised with His names and attributes")
//                    .font(BespokeFont.inter(14, weight: .regular))
//                    .foregroundStyle(BespokeColor.muted)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 4)

            if generateInFlight {
                VStack(spacing: 14) {
                    BespokeLoaderDots()
                    Text("Crafting your duas…")
                        .font(BespokeFont.inter(15, weight: .medium))
                        .foregroundStyle(BespokeColor.muted)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 36)
                .padding(.horizontal, 20)
                .background(Color.white.opacity(0.65))
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(BespokeColor.cardBorder, lineWidth: 1)
                )
            } else if generated.isEmpty {
                ContentUnavailableView {
                    Label("No duas yet", systemImage: "text.book.closed")
                } description: {
                    Text("Write what is in your heart, then tap Bespoke my dua to generate options you can save or copy.")
                        .font(BespokeFont.inter(15, weight: .regular))
                        .foregroundStyle(BespokeColor.muted)
                        .multilineTextAlignment(.center)
                }
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(BespokeColor.muted)
                .padding(.vertical, 28)
                .padding(.horizontal, 16)
                .frame(maxWidth: .infinity)
                .background(Color.white)
                .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .stroke(BespokeColor.cardBorder, lineWidth: 1)
                )
            } else {
                LazyVStack(spacing: 14) {
                    ForEach(generated) { dua in
                        BespokeDuaCard(
                            dua: dua,
                            isSavedVisual: savedDuaIDs.contains(dua.id)
                        ) {
                            Task { await toggleSaveDua(dua) }
                        }
                    }

                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            generated = []
                            savedDuaIDs = []
                            savedDuaServerIdByLocalId = [:]
                        }
                    } label: {
                        Text("Clear results")
                            .font(BespokeFont.inter(15, weight: .semibold))
                            .foregroundStyle(BespokeColor.forest)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(BespokeColor.cream.opacity(0.9))
                            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .stroke(BespokeColor.forest.opacity(0.15), lineWidth: 1)
                            )
                    }
                    .buttonStyle(.plain)
                    .padding(.top, 4)
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 32)
    }

    private func submitGenerate() {
        guard session.isLoggedIn else {
            session.presentAuth()
            return
        }
        let trimmed = requestText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            emptyRequestWarning = true
            return
        }
        emptyRequestWarning = false
        generateError = nil
        Task {
            await runGenerate(trimmed: trimmed)
        }
    }

    private func runGenerate(trimmed: String) async {
        generateInFlight = true
        defer { generateInFlight = false }
        let uid = session.currentUser?.userId
        do {
            let duas = try await session.api().generateDuas(text: trimmed, userId: uid)
            generated = duas
            savedDuaIDs = []
            savedDuaServerIdByLocalId = [:]
            requestText = ""
        } catch {
            generateError = "x"
        }
    }

    private func toggleSaveDua(_ dua: DuaReceiver) async {
        guard let uid = session.currentUser?.userId else {
            session.presentAuth()
            return
        }
        if savedDuaIDs.contains(dua.id) {
            guard let serverId = savedDuaServerIdByLocalId[dua.id] else {
                savedDuaIDs.remove(dua.id)
                return
            }
            do {
                try await session.api().deleteSavedDua(id: serverId)
                savedDuaIDs.remove(dua.id)
                savedDuaServerIdByLocalId[dua.id] = nil
                SavedDuaReflectionsCache.remove(userId: uid, duaId: serverId)
            } catch {
                generateError = "x"
            }
            return
        }
        do {
            let stored = Self.jsonForSavedDuaField(dua)
            let saved = try await session.api().saveDua(userId: uid, duaText: stored)
            savedDuaIDs.insert(dua.id)
            savedDuaServerIdByLocalId[dua.id] = saved.duaId
            SavedDuaReflectionsCache.store(userId: uid, duaId: saved.duaId, explanations: dua.explanations)
        } catch {
            generateError = "x"
        }
    }

    /// Embeds reflections in the `dua` string when the API keeps JSON; `SavedDuaReflectionsCache` also stores them by server id when the API only keeps plain text.
    private static func jsonForSavedDuaField(_ dua: DuaReceiver) -> String {
        guard !dua.explanations.isEmpty else { return dua.duaText }
        struct Payload: Encodable {
            /// Some backends only persist `duaText` (matches rows in Supabase); keep both so text survives normalization.
            let dua: String
            let duaText: String
            let explanations: [Row]
            struct Row: Encodable {
                let name: String
                let explanation: String
            }
        }
        let rows = dua.explanations.map { Payload.Row(name: $0.name, explanation: $0.explanation) }
        let text = dua.duaText
        let payload = Payload(dua: text, duaText: text, explanations: rows)
        guard let data = try? JSONEncoder().encode(payload),
              let str = String(data: data, encoding: .utf8) else {
            return dua.duaText
        }
        return str
    }
}

// MARK: - Loader (`dua-result-list.scss`)

private struct BespokeLoaderDots: View {
    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 30, paused: false)) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            HStack(spacing: 8) {
                ForEach(0 ..< 3, id: \.self) { i in
                    let phase = (t * 1.2 + Double(i) * 0.15).truncatingRemainder(dividingBy: 1)
                    let s = abs(sin(phase * .pi * 2))
                    let scale = 0.9 + 0.3 * s
                    let opacity = 0.3 + 0.7 * s
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [BespokeColor.loaderIndigo, BespokeColor.loaderGreen],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 10, height: 10)
                        .scaleEffect(scale)
                        .opacity(opacity)
                }
            }
        }
    }
}

// MARK: - Dua card (`dua-result-card.scss`)

private struct BespokeDuaCard: View {
    @Environment(\.presentReflectionModal) private var presentReflectionModal

    let dua: DuaReceiver
    var isSavedVisual: Bool
    var onSave: () -> Void

    @State private var copied = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(dua.duaText)
                .font(BespokeFont.inter(15, weight: .regular))
                .foregroundStyle(BespokeColor.bodyText)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 8) {
                Spacer(minLength: 0)
                Button {
                    presentReflectionModal?(dua.explanations)
                } label: {
                    Image(systemName: "lightbulb")
                        .font(.system(size: 16))
                        .foregroundStyle(BespokeColor.nameGold)
                        .padding(6)
                        .background(BespokeColor.cardBorder.opacity(0.35))
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
                .buttonStyle(.plain)

                Button(action: onSave) {
                    Image(systemName: isSavedVisual ? "bookmark.fill" : "bookmark")
                        .font(.system(size: 16))
                        .foregroundStyle(BespokeColor.nameGold)
                        .padding(6)
                        .background(BespokeColor.cardBorder.opacity(0.35))
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
                .buttonStyle(.plain)

                Button {
                    copyToClipboard(dua.duaText)
                    copied = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                        copied = false
                    }
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "doc.on.doc")
                            .font(.system(size: 15))
                        Text(copied ? "Copied!" : "Copy")
                            .font(BespokeFont.inter(13, weight: .regular))
                    }
                    .foregroundStyle(BespokeColor.clearBtnText)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Color(red: 242 / 255, green: 242 / 255, blue: 242 / 255))
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(18)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(BespokeColor.cardBorder, lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.07), radius: 14, x: 0, y: 6)
    }

    private func copyToClipboard(_ text: String) {
        #if canImport(UIKit)
        UIPasteboard.general.string = text
        #elseif canImport(AppKit)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        #endif
    }
}

// MARK: - Bespoke card modal (upgrade, aim, reflection)

private struct BespokeCardModalView<Content: View>: View {
    @Binding var isPresented: Bool
    let title: String
    @ViewBuilder var content: () -> Content

    var body: some View {
        ZStack {
            BespokeColor.authBackdrop
                .ignoresSafeArea()
                .background(.ultraThinMaterial.opacity(0.2))
                .onTapGesture {
                    isPresented = false
                }

            VStack(spacing: 0) {
                HStack {
                    Spacer(minLength: 0)
                    Button {
                        isPresented = false
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.title2)
                            .symbolRenderingMode(.hierarchical)
                            .foregroundStyle(BespokeColor.muted)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Close")
                }
                .padding(.horizontal, 20)
                .padding(.top, 12)

                VStack(alignment: .leading, spacing: 18) {
                    Text(title)
                        .font(BespokeFont.inter(29.6, weight: .semibold))
                        .foregroundStyle(BespokeColor.forest)
                    content()
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 24)
                .padding(.bottom, 24)
            }
            .frame(maxWidth: 540)
            .fixedSize(horizontal: false, vertical: true)
            .background(BespokeColor.authCard)
            .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .stroke(BespokeColor.forest.opacity(0.18), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.18), radius: 35, x: 0, y: 25)
            .padding(16)
        }
    }
}

// MARK: - Upgrade info (full-screen modal)

private struct UpgradeInfoModalView: View {
    @Binding var isPresented: Bool

    private static let instagramURL = URL(string: "https://www.instagram.com/bespoke_dua/")!

    var body: some View {
        BespokeCardModalView(isPresented: $isPresented, title: "Upgrade") {
            Text(
                "To keep BespokeDua sustainable and thoughtful for everyone, we'll introduce fair usage limits, with an option to upgrade for unlimited access."
            )
            .font(BespokeFont.inter(16, weight: .regular))
            .foregroundStyle(BespokeColor.bodyText)
            .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: 8) {
                Text("Stay up to date by following us on Instagram")
                    .font(BespokeFont.inter(16, weight: .regular))
                    .foregroundStyle(BespokeColor.bodyText)
                    .fixedSize(horizontal: false, vertical: true)

                Link(destination: Self.instagramURL) {
                    Text("@bespoke_dua")
                        .font(BespokeFont.inter(16, weight: .semibold))
                        .foregroundStyle(BespokeColor.forest)
                }
            }
        }
    }
}

// MARK: - Auth password (UIKit; SwiftUI SecureField misbehaves with keyboard / fullScreenCover)

#if canImport(UIKit)
private struct AuthSecureUITextField: UIViewRepresentable {
    @Binding var text: String

    func makeUIView(context: Context) -> UITextField {
        let tf = UITextField()
        tf.isSecureTextEntry = true
        tf.autocapitalizationType = .none
        tf.autocorrectionType = .no
        // `password` / `newPassword` often triggers AutoFill + “strong password” UI that replaces text and
        // breaks two-way SwiftUI bridges. Typing must work first; users can still paste from the keychain.
        tf.textContentType = nil
        tf.passwordRules = nil
        tf.keyboardType = .asciiCapable
        tf.borderStyle = .none
        tf.backgroundColor = .clear
        let font = UIFont(name: "Inter-Regular", size: 16) ?? .systemFont(ofSize: 16)
        tf.font = font
        tf.textColor = Self.bodyText
        tf.tintColor = Self.forest
        tf.attributedPlaceholder = NSAttributedString(
            string: "Password",
            attributes: [
                .foregroundColor: Self.subtle,
                .font: font,
            ]
        )
        tf.delegate = context.coordinator
        tf.addTarget(context.coordinator, action: #selector(Coordinator.editingChanged(_:)), for: .editingChanged)
        context.coordinator.text = $text
        tf.text = text
        return tf
    }

    func updateUIView(_ uiView: UITextField, context: Context) {
        context.coordinator.text = $text
        // Do not touch `textContentType` / `passwordRules` here — reapplying can reset secure fields on iOS 18+.

        if context.coordinator.isUserEditing || uiView.isFirstResponder {
            return
        }
        if uiView.text != text {
            uiView.text = text
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    final class Coordinator: NSObject, UITextFieldDelegate {
        var text = Binding.constant("")

        /// `isFirstResponder` is unreliable for secure fields; delegate callbacks match actual editing sessions.
        var isUserEditing = false

        @objc func editingChanged(_ sender: UITextField) {
            text.wrappedValue = sender.text ?? ""
        }

        func textFieldDidBeginEditing(_ textField: UITextField) {
            isUserEditing = true
        }

        func textFieldDidEndEditing(_ textField: UITextField) {
            isUserEditing = false
            text.wrappedValue = textField.text ?? ""
        }
    }

    private static let bodyText = UIColor(red: 51 / 255, green: 51 / 255, blue: 51 / 255, alpha: 1)
    private static let subtle = UIColor(red: 136 / 255, green: 136 / 255, blue: 136 / 255, alpha: 1)
    private static let forest = UIColor(red: 15 / 255, green: 61 / 255, blue: 46 / 255, alpha: 1)
}
#endif

/// Isolated from `AppSession` so `@Observable` invalidation does not recreate the UIKit password field every render.
private struct AuthPasswordInputRow: View {
    @Binding var password: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Password")
                .font(BespokeFont.inter(15.2, weight: .bold))
                .foregroundStyle(BespokeColor.fieldLabel)
            Group {
                #if canImport(UIKit)
                AuthSecureUITextField(text: $password)
                    .id("authSecurePassword")
                #else
                SecureField("Password", text: $password)
                    .font(BespokeFont.inter(16, weight: .regular))
                    .foregroundStyle(BespokeColor.bodyText)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                #endif
            }
            .padding(16)
            .frame(maxWidth: .infinity, minHeight: 48, alignment: .leading)
            .background(BespokeColor.inputSurface)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(BespokeColor.forest.opacity(0.18), lineWidth: 1)
            )
        }
    }
}

// MARK: - Auth modal (`auth-page.scss` + forms)

private struct AuthModalView: View {
    @Environment(AppSession.self) private var session
    @State private var mode: AuthTab = .login
    @State private var username = ""
    @State private var email = ""
    @State private var password = ""

    private enum AuthTab {
        case login, register
    }

    var body: some View {
        ZStack {
            BespokeColor.authBackdrop
                .ignoresSafeArea()
                .background(.ultraThinMaterial.opacity(0.2))
                .onTapGesture {
                    session.dismissAuth()
                }

            VStack(spacing: 0) {
                Spacer(minLength: 0)
                VStack(spacing: 0) {
                HStack(spacing: 6) {
                    authToggleButton(title: "Login", tab: .login)
                    authToggleButton(title: "Register", tab: .register)
                }
                .padding(6)
                .background(BespokeColor.authToggleBg)
                .clipShape(RoundedRectangle(cornerRadius: 999, style: .continuous))
                .padding(.horizontal, 6)
                .padding(.top, 6)

                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        if mode == .login {
                            Text("Login")
                                .font(BespokeFont.inter(29.6, weight: .semibold))
                                .foregroundStyle(BespokeColor.forest)
                        } else {
                            Text("Create an Account")
                                .font(BespokeFont.inter(29.6, weight: .semibold))
                                .foregroundStyle(BespokeColor.forest)
                        }

                        if mode == .register {
                            authField(
                                label: "Username",
                                content: {
                                    TextField("", text: $username, prompt: Text("Username").foregroundStyle(BespokeColor.subtle))
                                        .textContentType(.username)
                                        .autocorrectionDisabled()
                                }
                            )
                            Text("2–100 characters. Letters, numbers, underscores, or hyphens.")
                                .font(BespokeFont.inter(12.8, weight: .regular))
                                .foregroundStyle(BespokeColor.fieldLabel.opacity(0.65))
                        }

                        authField(
                            label: "Email",
                            content: {
                                TextField("", text: $email, prompt: Text("Email").foregroundStyle(BespokeColor.subtle))
                                    .textContentType(.emailAddress)
                                    .keyboardType(.emailAddress)
                                    .autocorrectionDisabled()
                            }
                        )

                        AuthPasswordInputRow(password: $password)

                        if let err = session.authError {
                            HStack(alignment: .top, spacing: 10) {
                                Text("!")
                                    .font(.system(size: 12, weight: .heavy))
                                    .foregroundStyle(.white)
                                    .frame(width: 24, height: 24)
                                    .background(Color(red: 181 / 255, green: 47 / 255, blue: 49 / 255))
                                    .clipShape(Circle())
                                Text(err)
                                    .font(BespokeFont.inter(14.7, weight: .semibold))
                                    .foregroundStyle(Color(red: 107 / 255, green: 29 / 255, blue: 31 / 255))
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            .padding(14)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(
                                LinearGradient(
                                    colors: [
                                        Color(red: 181 / 255, green: 47 / 255, blue: 49 / 255).opacity(0.1),
                                        Color(red: 181 / 255, green: 47 / 255, blue: 49 / 255).opacity(0.04),
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 16, style: .continuous)
                                    .stroke(Color(red: 181 / 255, green: 47 / 255, blue: 49 / 255).opacity(0.28), lineWidth: 1)
                            )
                            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                        }

                        Button {
                            Task { await submit() }
                        } label: {
                            Text(mode == .login ? "Login" : "Register")
                                .font(BespokeFont.inter(17, weight: .bold))
                                .foregroundStyle(BespokeColor.cream)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 17)
                                .background(BespokeColor.forest)
                                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                        }
                        .buttonStyle(.plain)
                        .disabled(session.authInFlight || !canSubmit)
                        .opacity(session.authInFlight || !canSubmit ? 0.65 : 1)
                    }
                    .padding(24)
                }
                .scrollDismissesKeyboard(.never)

                if let user = session.currentUser {
                    HStack(alignment: .center) {
                        HStack(spacing: 0) {
                            Text("Signed in as ")
                                .font(BespokeFont.inter(15, weight: .regular))
                            Text(user.username)
                                .font(BespokeFont.inter(15, weight: .bold))
                        }
                        .foregroundStyle(BespokeColor.forest)
                        Spacer()
                        Button {
                            session.logout()
                        } label: {
                            Text("Logout")
                                .font(BespokeFont.inter(15, weight: .semibold))
                                .foregroundStyle(BespokeColor.cream)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 12)
                                .background(BespokeColor.forest)
                                .clipShape(RoundedRectangle(cornerRadius: 15, style: .continuous))
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(16)
                    .frame(maxWidth: .infinity)
                    .background(BespokeColor.forest.opacity(0.05))
                    .overlay(alignment: .top) {
                        Rectangle()
                            .fill(BespokeColor.forest.opacity(0.08))
                            .frame(height: 1)
                    }
                }
                }
                .frame(maxWidth: 540, maxHeight: mode == .login ? 500 : 650)
                .background(BespokeColor.authCard)
                .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .stroke(BespokeColor.forest.opacity(0.18), lineWidth: 1)
                )
                .shadow(color: .black.opacity(0.18), radius: 35, x: 0, y: 25)
                .padding(16)
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .ignoresSafeArea(.keyboard)
    }

    private func authToggleButton(title: String, tab: AuthTab) -> some View {
        Button {
            mode = tab
            session.authError = nil
        } label: {
            Text(title)
                .font(BespokeFont.inter(15, weight: .bold))
                .foregroundStyle(mode == tab ? Color.white : BespokeColor.forest)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 15)
                .background(mode == tab ? BespokeColor.gold : Color.clear)
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    private func authField<Content: View>(label: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(BespokeFont.inter(15.2, weight: .bold))
                .foregroundStyle(BespokeColor.fieldLabel)
            content()
                .font(BespokeFont.inter(16, weight: .regular))
                .foregroundStyle(BespokeColor.bodyText)
                .padding(16)
                .frame(maxWidth: .infinity, minHeight: 48, alignment: .leading)
                .background(BespokeColor.inputSurface)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(BespokeColor.forest.opacity(0.18), lineWidth: 1)
                )
        }
    }

    private var canSubmit: Bool {
        let e = email.trimmingCharacters(in: .whitespacesAndNewlines)
        let p = password
        if mode == .register {
            return !username.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !e.isEmpty && !p.isEmpty
        }
        return !e.isEmpty && !p.isEmpty
    }

    private func submit() async {
        let e = email.trimmingCharacters(in: .whitespacesAndNewlines)
        let p = password
        switch mode {
        case .login:
            await session.login(email: e, password: p)
        case .register:
            await session.register(username: username.trimmingCharacters(in: .whitespacesAndNewlines), email: e, password: p)
        }
    }
}

// MARK: - Saved dua reflections cache

/// The API may only persist plain `dua` text; we keep reflections locally by server `duaId` so the Saved tab can still show them.
private enum SavedDuaReflectionsCache {
    private static func storageKey(userId: Int, duaId: String) -> String {
        "bespoke.savedDua.reflections.\(userId).\(duaId)"
    }

    static func store(userId: Int, duaId: String, explanations: [ExplanationModel]) {
        if explanations.isEmpty {
            remove(userId: userId, duaId: duaId)
            return
        }
        struct Row: Codable {
            let name: String
            let explanation: String
        }
        let rows = explanations.map { Row(name: $0.name, explanation: $0.explanation) }
        guard let data = try? JSONEncoder().encode(rows) else { return }
        UserDefaults.standard.set(data, forKey: storageKey(userId: userId, duaId: duaId))
    }

    static func explanations(userId: Int, duaId: String) -> [ExplanationModel]? {
        guard let data = UserDefaults.standard.data(forKey: storageKey(userId: userId, duaId: duaId)) else { return nil }
        struct Row: Codable {
            let name: String
            let explanation: String
        }
        guard let rows = try? JSONDecoder().decode([Row].self, from: data) else { return nil }
        return rows.map { ExplanationModel(name: $0.name, explanation: $0.explanation) }
    }

    static func remove(userId: Int, duaId: String) {
        UserDefaults.standard.removeObject(forKey: storageKey(userId: userId, duaId: duaId))
    }
}

// MARK: - Saved duas page (same content as web modal, full screen)

private struct SavedDuasPageView: View {
    @Environment(AppSession.self) private var session
    @State private var items: [SavedDuaDTO] = []
    @State private var loading = false
    @State private var error: String?

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .short
        return f
    }()

    private var savedDuasSignedOutContent: some View {
        GeometryReader { geo in
            ScrollView {
                VStack(spacing: 0) {
                    Spacer(minLength: 0)
                    savedDuasSignedOutCard
                    Spacer(minLength: 0)
                }
                .frame(minHeight: geo.size.height)
                .frame(maxWidth: .infinity)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var savedDuasSignedOutCard: some View {
        VStack(spacing: 28) {
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [BespokeColor.forest.opacity(0.14), BespokeColor.forest.opacity(0.06)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 96, height: 96)
                Image(systemName: "bookmark.fill")
                    .font(.system(size: 38, weight: .medium))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [BespokeColor.forest, BespokeColor.forest.opacity(0.75)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .accessibilityHidden(true)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Bookmarks")

            VStack(spacing: 12) {
                Text("My heart's duas")
                    .font(BespokeFont.display(30))
                    .foregroundStyle(BespokeColor.forest)
                    .multilineTextAlignment(.center)

                Text("Sign in to keep your favourite duas in one place, so you can return to them anytime.")
                    .font(BespokeFont.inter(16, weight: .regular))
                    .foregroundStyle(BespokeColor.muted)
                    .multilineTextAlignment(.center)
                    .lineSpacing(4)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 4)

            Button {
                session.presentAuth()
            } label: {
                Text("Sign in")
                    .font(BespokeFont.inter(17, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
            }
            .buttonStyle(.plain)
            .background(LinearGradient.bespokeGold)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .shadow(color: .black.opacity(0.14), radius: 14, x: 0, y: 6)
        }
        .padding(32)
        .frame(maxWidth: 480)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(BespokeColor.cardBorder, lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.06), radius: 20, x: 0, y: 8)
        .padding(.horizontal, 20)
    }

    /// Matches home `inputSection` title styling (`Write your heart’s dua`).
    private var savedPageHeading: some View {
        Text("My heart’s dua")
            .font(BespokeFont.display(26))
            .foregroundStyle(BespokeColor.forest)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
            .padding(.top, 11)
            .padding(.horizontal, 20)
            .padding(.bottom, 16)
    }

    var body: some View {
        Group {
            if !session.isLoggedIn {
                savedDuasSignedOutContent
            } else {
                VStack(spacing: 0) {
                    savedPageHeading

                    Group {
                        if loading && items.isEmpty {
                            VStack(spacing: 16) {
                                ProgressView()
                                    .tint(BespokeColor.forest)
                                    .scaleEffect(1.1)
                                Text("Loading your saved duas…")
                                    .font(BespokeFont.inter(16, weight: .medium))
                                    .foregroundStyle(BespokeColor.muted)
                            }
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .padding(24)
                        } else if let error {
                            ContentUnavailableView {
                                Label("Couldn’t load", systemImage: "exclamationmark.triangle")
                            } description: {
                                Text(error)
                                    .font(BespokeFont.inter(15, weight: .regular))
                                    .foregroundStyle(BespokeColor.muted)
                                    .multilineTextAlignment(.center)
                            }
                            .symbolRenderingMode(.hierarchical)
                            .foregroundStyle(BespokeColor.error.opacity(0.85))
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .padding(24)
                        } else if items.isEmpty {
                            ContentUnavailableView {
                                Label("Nothing saved yet", systemImage: "bookmark")
                            } description: {
                                Text("When you bookmark a generated dua, it appears here.")
                                    .font(BespokeFont.inter(15, weight: .regular))
                                    .foregroundStyle(BespokeColor.muted)
                                    .multilineTextAlignment(.center)
                            }
                            .symbolRenderingMode(.hierarchical)
                            .foregroundStyle(BespokeColor.muted)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .padding(24)
                        } else {
                            VStack(alignment: .leading, spacing: 0) {
                                Text("Newest first")
                                    .font(BespokeFont.inter(13, weight: .semibold))
                                    .foregroundStyle(BespokeColor.muted)
                                    .textCase(.none)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(.horizontal, 20)
                                    .padding(.bottom, 10)

                                List {
                                    ForEach(items) { row in
                                        VStack(alignment: .leading, spacing: 10) {
                                            Text(Self.dateFormatter.string(from: row.createdAt))
                                                .font(BespokeFont.inter(13, weight: .semibold))
                                                .foregroundStyle(BespokeColor.muted)
                                                .textCase(.uppercase)
                                                .tracking(0.3)

                                            BespokeDuaCard(
                                                dua: Self.duaReceiver(from: row, userId: session.currentUser?.userId),
                                                isSavedVisual: true
                                            ) {
                                                Task { await delete(row) }
                                            }
                                        }
                                        .listRowInsets(EdgeInsets(top: 14, leading: 16, bottom: 14, trailing: 16))
                                        .listRowSeparator(.hidden)
                                        .listRowBackground(Color.clear)
                                        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                            Button(role: .destructive) {
                                                Task { await delete(row) }
                                            } label: {
                                                Label("Delete", systemImage: "trash")
                                            }
                                        }
                                    }
                                }
                                .listStyle(.plain)
                                .scrollContentBackground(.hidden)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task(id: session.currentUser?.userId) {
            await load()
        }
    }

    /// `SavedDuas.dua` may be plain text, JSON we encoded, or JSON from the server; reflections also come from `SavedDuaReflectionsCache` when the API drops them.
    private static func duaReceiver(from row: SavedDuaDTO, userId: Int?) -> DuaReceiver {
        let raw = row.dua.trimmingCharacters(in: .whitespacesAndNewlines)
        var text = raw
        var exps: [ExplanationModel] = []

        if raw.hasPrefix("{"), let data = raw.data(using: .utf8) {
            struct FlexibleSavedDuaJSON: Decodable {
                let dua: String?
                let duaText: String?
                let explanations: [GeneratedExplanationDTO]?
            }
            if let flex = try? JSONDecoder().decode(FlexibleSavedDuaJSON.self, from: data) {
                text = flex.dua ?? flex.duaText ?? raw
                exps = (flex.explanations ?? []).map {
                    ExplanationModel(name: $0.name, explanation: $0.explanation)
                }
            }
        }

        if exps.isEmpty, let uid = userId, let cached = SavedDuaReflectionsCache.explanations(userId: uid, duaId: row.duaId), !cached.isEmpty {
            exps = cached
        }

        return DuaReceiver(duaText: text, explanations: exps)
    }

    private func load() async {
        guard let uid = session.currentUser?.userId else { return }
        loading = true
        error = nil
        defer { loading = false }
        do {
            items = try await session.api().savedDuas(forUserId: uid)
        } catch {
            self.error = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    private func delete(_ row: SavedDuaDTO) async {
        do {
            try await session.api().deleteSavedDua(id: row.duaId)
            items.removeAll { $0.duaId == row.duaId }
            if let uid = session.currentUser?.userId {
                SavedDuaReflectionsCache.remove(userId: uid, duaId: row.duaId)
            }
        } catch {
            self.error = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }
}

#Preview {
    ContentView()
        .environment(AppSession())
}
