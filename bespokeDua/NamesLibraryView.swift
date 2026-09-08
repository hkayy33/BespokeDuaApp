import SwiftUI

#if canImport(UIKit)
import UIKit
#endif

enum NamesLibraryDestination: Hashable {
    case all
    case feeling(FeelingLabel)
}

struct NamesLibraryView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AppSession.self) private var session
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.mainTabBarClearance) private var mainTabBarClearance

    var onSelectCategory: (NamesLibraryDestination) -> Void = { _ in }

    @State private var searchText = ""
    @State private var allNames: [AllahNameDetail] = []
    @State private var namesLoading = false
    @FocusState private var searchFocused: Bool

    private var categoryCardColumns: [GridItem] {
        if horizontalSizeClass == .regular {
            [
                GridItem(.flexible(), spacing: 14),
                GridItem(.flexible(), spacing: 14)
            ]
        } else {
            [GridItem(.flexible(), spacing: 14)]
        }
    }

    var body: some View {
        libraryScrollContent
    }

    private var libraryScrollContent: some View {
        ScrollView {
            VStack(spacing: 0) {
                libraryHeading
                    .contentShape(Rectangle())
                    .onTapGesture(perform: dismissSearchFocus)

                namesSearchBar

                Group {
                    if isSearchActive {
                        librarySearchResults
                    } else if session.namesFeelingLabelsLoading && session.namesFeelingLabels.isEmpty && session.namesFeelingLabelsError == nil && !session.isReconnecting {
                        loadingState
                    } else if session.isReconnecting || session.namesFeelingLabelsError != nil {
                        errorState(session.namesFeelingLabelsError ?? "")
                    } else {
                        categoryCards
                    }
                }
                .padding(.bottom, 24 + mainTabBarClearance)
                .contentShape(Rectangle())
                .simultaneousGesture(TapGesture().onEnded { dismissSearchFocus() })
            }
            .bespokeLibraryContentFrame()
        }
        .scrollIndicators(.hidden, axes: .vertical)
        .scrollDismissesKeyboard(.immediately)
        .background(BespokeColor.pageBackground)
        .toolbar(.hidden, for: .navigationBar)
        .navigationBarBackButtonHidden(true)
        .safeAreaInset(edge: .top, spacing: 0) {
            BespokeFlowBackHeader(title: "99 Names", onBack: goBack)
                .simultaneousGesture(TapGesture().onEnded { dismissSearchFocus() })
        }
        .bespokeEdgeBackNavigation(hidesNavigationBar: true)
        .task {
            if session.namesFeelingLabels.isEmpty {
                await session.refreshFeelingLabels()
            }
            await loadAllNamesForSearch()
        }
    }

    private func goBack() {
        dismissSearchFocus()
        dismiss()
    }

    private func dismissSearchFocus() {
        guard searchFocused else { return }
        searchFocused = false
    }

    private var libraryHeading: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Names of Allah")
                .font(BespokeFont.display(28))
                .foregroundStyle(BespokeColor.forest)

            Text(isSearchActive ? "Search across all 99 names." : "Choose how you feel, or browse all 99 names.")
                .font(BespokeFont.inter(15, weight: .regular))
                .foregroundStyle(BespokeColor.muted)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, 16)
        .padding(.horizontal, BespokeLayout.libraryHorizontalPadding)
        .padding(.bottom, 16)
    }

    private var searchQuery: String {
        searchText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var isSearchActive: Bool {
        !searchQuery.isEmpty
    }

    private var matchingNames: [AllahNameDetail] {
        guard isSearchActive else { return [] }
        var seen = Set<Int>()
        return allNames.filter { name in
            guard nameMatchesSearch(name) else { return false }
            return seen.insert(name.number).inserted
        }
    }

    private var namesSearchBar: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(BespokeColor.subtle)

            TextField("Search by name or meaning…", text: $searchText)
                .font(BespokeFont.inter(15, weight: .regular))
                .foregroundStyle(BespokeColor.bodyText)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .focused($searchFocused)
                .submitLabel(.search)
                .onSubmit(dismissSearchFocus)

            if !searchText.isEmpty {
                Button {
                    searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 16))
                        .foregroundStyle(BespokeColor.subtle)
                }
                .buttonStyle(BespokePlainButtonStyle())
                .accessibilityLabel("Clear search")
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(searchFocused ? BespokeColor.gold : BespokeColor.inputBorder, lineWidth: searchFocused ? 2 : 1)
        }
        .padding(.horizontal, BespokeLayout.libraryHorizontalPadding)
        .padding(.bottom, 16)
    }

    @ViewBuilder
    private var librarySearchResults: some View {
        if namesLoading && allNames.isEmpty {
            loadingState
        } else if matchingNames.isEmpty {
            ContentUnavailableView {
                Label("No results", systemImage: "magnifyingglass")
            } description: {
                Text("Try a different spelling, or search by meaning.")
                    .font(BespokeFont.inter(15, weight: .regular))
                    .foregroundStyle(BespokeColor.muted)
                    .multilineTextAlignment(.center)
            } actions: {
                Button("Clear search") {
                    searchText = ""
                }
                .font(BespokeFont.inter(15, weight: .semibold))
            }
            .symbolRenderingMode(.hierarchical)
            .foregroundStyle(BespokeColor.muted)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 36)
            .padding(.horizontal, 24)
        } else {
            LazyVGrid(columns: categoryCardColumns, spacing: 16) {
                ForEach(matchingNames) { detail in
                    AllahNameCard(name: detail.summary, number: detail.number)
                }
            }
            .padding(.horizontal, BespokeLayout.libraryHorizontalPadding)
        }
    }

    private func nameMatchesSearch(_ name: AllahNameDetail) -> Bool {
        name.arabic.localizedStandardContains(searchQuery)
            || name.transliteration.localizedStandardContains(searchQuery)
            || name.translation.localizedStandardContains(searchQuery)
            || name.meaning.localizedStandardContains(searchQuery)
            || name.feelingLabel.localizedStandardContains(searchQuery)
            || "\(name.number)".contains(searchQuery)
    }

    @MainActor
    private func loadAllNamesForSearch() async {
        guard allNames.isEmpty else { return }
        namesLoading = true
        defer { namesLoading = false }
        allNames = (try? await HomeNameOfTheDayService.allNames()) ?? []
    }

    private var categoryCards: some View {
        LazyVGrid(columns: categoryCardColumns, spacing: 14) {
            categoryCardButton(
                destination: .all,
                title: "All 99 names",
                subtitle: "Browse the complete list",
                assetName: FeelingBackdrop.allAssetName,
                symbolName: FeelingBackdrop.allSymbolName,
                accentColors: FeelingBackdrop.allAccentColors
            )

            ForEach(session.namesFeelingLabels) { label in
                categoryCardButton(
                    destination: .feeling(label),
                    title: label.titleLine,
                    subtitle: label.subtitleLine,
                    assetName: FeelingBackdrop.assetName(for: label.feelingLabelId),
                    symbolName: FeelingBackdrop.symbolName(for: label.feelingLabelId),
                    accentColors: FeelingBackdrop.accentColors(for: label.feelingLabelId)
                )
            }
        }
        .padding(.horizontal, BespokeLayout.libraryHorizontalPadding)
    }

    private func categoryCardButton(
        destination: NamesLibraryDestination,
        title: String,
        subtitle: String?,
        assetName: String,
        symbolName: String,
        accentColors: [Color]
    ) -> some View {
        Button {
            onSelectCategory(destination)
        } label: {
            NamesCategoryCard(
                title: title,
                subtitle: subtitle,
                assetName: assetName,
                symbolName: symbolName,
                accentColors: accentColors
            )
        }
        .buttonStyle(CategoryCardButtonStyle())
        .bespokeButtonHitArea(cornerRadius: 20)
    }

    private var loadingState: some View {
        VStack(spacing: 16) {
            ProgressView()
                .tint(BespokeColor.forest)
                .scaleEffect(1.1)
            Text("Loading…")
                .font(BespokeFont.inter(16, weight: .medium))
                .foregroundStyle(BespokeColor.muted)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 48)
    }

    private func errorState(_ message: String) -> some View {
        NamesLibraryConnectionComfortView(
            title: "Having trouble connecting",
            message: "Check your connection and try again when you're back online.",
            onRetry: { await session.reconnectFeelingLabels() }
        )
        .padding(.bottom, 8)
    }
}

struct NamesFilteredListView: View {
    let destination: NamesLibraryDestination

    @Environment(\.dismiss) private var dismiss
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.mainTabBarClearance) private var mainTabBarClearance
    @State private var allNames: [AllahNameDetail] = []
    @State private var filteredNames: [AllahNameSummary] = []
    @State private var searchText = ""
    @State private var loading = false
    @State private var error: String?
    @State private var refreshNotice: String?

    private let client = BespokeAPIClient()

    private var nameCardColumns: [GridItem] {
        if horizontalSizeClass == .regular {
            [
                GridItem(.flexible(), spacing: 16),
                GridItem(.flexible(), spacing: 16)
            ]
        } else {
            [GridItem(.flexible(), spacing: 16)]
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            listHeader

            ScrollView {
                listContent
            }
            .scrollIndicators(.hidden, axes: .vertical)
            .scrollDismissesKeyboard(.interactively)
            .refreshable {
                await loadNames(isRefresh: true)
            }
        }
        .background(BespokeColor.pageBackground)
        .toolbar(.hidden, for: .navigationBar)
        .navigationBarBackButtonHidden(true)
        .bespokeEdgeBackNavigation(hidesNavigationBar: true)
        .task {
            await loadNames(isRefresh: false)
        }
    }

    private var listHeader: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 10) {
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(.white)
                        .shadow(color: .black.opacity(0.28), radius: 3, x: 0, y: 1)
                        .padding(8)
                        .contentShape(Rectangle())
                }
                .buttonStyle(BespokePlainButtonStyle())

                VStack(alignment: .leading, spacing: 5) {
                    Text(headerPrimaryTitle)
                        .font(BespokeFont.display(22))
                        .foregroundStyle(.white)
                        .shadow(color: .black.opacity(0.22), radius: 4, x: 0, y: 1)
                        .fixedSize(horizontal: false, vertical: true)

                    if let headerSubtitle {
                        Text(headerSubtitle)
                            .font(BespokeFont.inter(14, weight: .medium))
                            .foregroundStyle(.white.opacity(0.94))
                            .shadow(color: .black.opacity(0.22), radius: 3, x: 0, y: 1)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                namesSearchBar
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .bespokeLibraryContentFrame()
            .padding(.horizontal, BespokeLayout.libraryHorizontalPadding)
            .padding(.bottom, 16)
            .safeAreaPadding(.top, 10)
            .background {
                FeelingBackdropView(
                    assetName: headerBackdrop.assetName,
                    symbolName: headerBackdrop.symbolName,
                    accentColors: headerBackdrop.accentColors,
                    showsSymbol: false,
                    overlayStyle: .header
                )
                .ignoresSafeArea(edges: .top)
            }

            LinearGradient(
                colors: [
                    Color.black.opacity(0.18),
                    BespokeColor.pageBackground
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: 18)
        }
    }

    private var headerPrimaryTitle: String {
        switch destination {
        case .all:
            "All 99 names"
        case let .feeling(label):
            label.titleLine
        }
    }

    private var headerSubtitle: String? {
        switch destination {
        case .all:
            "Browse the complete list"
        case let .feeling(label):
            label.subtitleLine
        }
    }

    private var namesSearchBar: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(BespokeColor.subtle)

            TextField("Search by name or meaning…", text: $searchText)
                .font(BespokeFont.inter(15, weight: .regular))
                .foregroundStyle(BespokeColor.bodyText)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()

            if !searchText.isEmpty {
                Button {
                    searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 16))
                        .foregroundStyle(BespokeColor.subtle)
                }
                .buttonStyle(BespokePlainButtonStyle())
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .background(Color.white.opacity(0.94))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.white.opacity(0.55), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.12), radius: 8, x: 0, y: 3)
    }

    private var searchQuery: String {
        searchText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var isSearchActive: Bool {
        !searchQuery.isEmpty
    }

    private func nameMatchesSearch(_ name: AllahNameSummary, number: Int? = nil) -> Bool {
        guard isSearchActive else { return true }

        return name.arabic.localizedStandardContains(searchQuery)
            || name.transliteration.localizedStandardContains(searchQuery)
            || name.translation.localizedStandardContains(searchQuery)
            || name.meaning.localizedStandardContains(searchQuery)
            || (number.map { "\($0)".contains(searchQuery) } ?? false)
    }

    private var displayedAllNames: [AllahNameDetail] {
        guard isSearchActive else { return allNames }
        return allNames.filter { nameMatchesSearch($0.summary, number: $0.number) }
    }

    private var displayedFeelingNames: [AllahNameSummary] {
        guard isSearchActive else { return filteredNames }
        return filteredNames.filter { nameMatchesSearch($0) }
    }

    private var displayedNames: [AllahNameSummary] {
        switch destination {
        case .all:
            displayedAllNames.map(\.summary)
        case .feeling:
            displayedFeelingNames
        }
    }

    @ViewBuilder
    private var listContent: some View {
        if loading && displayedNames.isEmpty && error == nil {
            loadingState
        } else if let error, displayedNames.isEmpty {
            errorState(error)
        } else if displayedNames.isEmpty {
            emptyState
        } else {
            namesGrid
        }
    }

    private var loadingState: some View {
        VStack(spacing: 16) {
            ProgressView()
                .tint(BespokeColor.forest)
                .scaleEffect(1.1)
            Text("Loading names…")
                .font(BespokeFont.inter(16, weight: .medium))
                .foregroundStyle(BespokeColor.muted)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 48)
    }

    private func errorState(_ message: String) -> some View {
        NamesLibraryConnectionComfortView(
            title: "Couldn't load names right now",
            message: "Check your connection and try again in a moment.",
            onRetry: { await loadNames(isRefresh: false) }
        )
        .padding(.vertical, 16)
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label(
                isSearchActive ? "No results" : "No names found",
                systemImage: isSearchActive ? "magnifyingglass" : "text.book.closed"
            )
        } description: {
            Text(
                isSearchActive
                    ? "Try a different spelling or search another word."
                    : "Pull to refresh and try again."
            )
            .font(BespokeFont.inter(15, weight: .regular))
            .foregroundStyle(BespokeColor.muted)
            .multilineTextAlignment(.center)
        } actions: {
            if isSearchActive {
                Button("Clear search") {
                    searchText = ""
                }
                .font(BespokeFont.inter(15, weight: .semibold))
            }
        }
        .symbolRenderingMode(.hierarchical)
        .foregroundStyle(BespokeColor.muted)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 48)
        .padding(.horizontal, 24)
    }

    private var namesGrid: some View {
        LazyVGrid(columns: nameCardColumns, spacing: 16) {
            if let refreshNotice {
                refreshNoticeBanner(refreshNotice)
                    .gridCellColumns(nameCardColumns.count)
            }

            switch destination {
            case .all:
                ForEach(displayedAllNames) { detail in
                    AllahNameCard(name: detail.summary, number: detail.number)
                }
            case .feeling:
                ForEach(displayedFeelingNames) { name in
                    AllahNameCard(name: name, number: nil)
                }
            }
        }
        .bespokeLibraryContentFrame()
        .padding(.horizontal, BespokeLayout.libraryHorizontalPadding)
        .padding(.top, 8)
        .padding(.bottom, 28 + mainTabBarClearance)
    }

    private func refreshNoticeBanner(_ message: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "arrow.clockwise.circle.fill")
                .font(.system(size: 18))
                .foregroundStyle(BespokeColor.nameGold)

            Text(message)
                .font(BespokeFont.inter(14, weight: .medium))
                .foregroundStyle(BespokeColor.bodyText)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 0)
        }
        .padding(14)
        .background(BespokeColor.cream)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(BespokeColor.gold.opacity(0.25), lineWidth: 1)
        }
    }

    private var headerBackdrop: (assetName: String, symbolName: String, accentColors: [Color]) {
        switch destination {
        case .all:
            (FeelingBackdrop.allAssetName, FeelingBackdrop.allSymbolName, FeelingBackdrop.allAccentColors)
        case let .feeling(label):
            (
                FeelingBackdrop.assetName(for: label.feelingLabelId),
                FeelingBackdrop.symbolName(for: label.feelingLabelId),
                FeelingBackdrop.accentColors(for: label.feelingLabelId)
            )
        }
    }

    @MainActor
    private func loadNames(isRefresh: Bool) async {
        if isRefresh {
            refreshNotice = nil
        } else if displayedNames.isEmpty {
            loading = true
            error = nil
        }

        defer {
            if !isRefresh {
                loading = false
            }
        }

        switch destination {
        case .all:
            await loadAllNames(keepExistingOnFailure: isRefresh || !displayedNames.isEmpty)
        case let .feeling(label):
            await loadNames(for: label, keepExistingOnFailure: isRefresh || !displayedNames.isEmpty)
        }
    }

    @MainActor
    private func loadAllNames(keepExistingOnFailure: Bool) async {
        do {
            let labels = try await client.feelingLabels()
            guard !labels.isEmpty else {
                if !keepExistingOnFailure {
                    allNames = []
                }
                return
            }

            var merged: [AllahNameDetail] = []
            try await withThrowingTaskGroup(of: [AllahNameDetail].self) { group in
                for label in labels {
                    group.addTask {
                        try await self.client.names(feelingLabelId: label.feelingLabelId)
                    }
                }
                for try await batch in group {
                    merged.append(contentsOf: batch)
                }
            }
            allNames = merged.sorted { $0.number < $1.number }
            error = nil
            refreshNotice = nil
        } catch {
            guard !shouldIgnoreLoadError(error) else { return }
            handleLoadFailure(
                error,
                keepExistingOnFailure: keepExistingOnFailure,
                clearData: { allNames = [] }
            )
        }
    }

    @MainActor
    private func loadNames(for label: FeelingLabel, keepExistingOnFailure: Bool) async {
        do {
            let response = try await client.namesByFeeling(feelingLabelId: label.feelingLabelId)
            filteredNames = response.names
            error = nil
            refreshNotice = nil
        } catch {
            guard !shouldIgnoreLoadError(error) else { return }
            handleLoadFailure(
                error,
                keepExistingOnFailure: keepExistingOnFailure,
                clearData: { filteredNames = [] }
            )
        }
    }

    @MainActor
    private func handleLoadFailure(
        _ error: Error,
        keepExistingOnFailure: Bool,
        clearData: () -> Void
    ) {
        if keepExistingOnFailure {
            refreshNotice = "Couldn't refresh just now. Your list is still here — pull down to try again."
            scheduleRefreshNoticeDismissal()
            return
        }

        clearData()
        self.error = friendlyLoadErrorMessage(for: error)
    }

    @MainActor
    private func scheduleRefreshNoticeDismissal() {
        Task {
            try? await Task.sleep(for: .seconds(4))
            refreshNotice = nil
        }
    }

    private func shouldIgnoreLoadError(_ error: Error) -> Bool {
        if error is CancellationError {
            return true
        }
        if let urlError = error as? URLError, urlError.code == .cancelled {
            return true
        }
        return false
    }

    private func friendlyLoadErrorMessage(for error: Error) -> String {
        if let urlError = error as? URLError {
            switch urlError.code {
            case .notConnectedToInternet, .networkConnectionLost:
                return "Check your connection and try again."
            case .timedOut:
                return "That took too long. Please try again."
            default:
                break
            }
        }

        if let localized = error as? LocalizedError,
           let description = localized.errorDescription,
           !description.isEmpty {
            return description
        }

        return "Something went wrong. Please try again."
    }
}

private struct NamesCategoryCard: View {
    let title: String
    let subtitle: String?
    let assetName: String
    let symbolName: String
    let accentColors: [Color]

    var body: some View {
        ZStack(alignment: .leading) {
            FeelingBackdropView(
                assetName: assetName,
                symbolName: symbolName,
                accentColors: accentColors
            )
            .allowsHitTesting(false)

            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(title)
                        .font(BespokeFont.inter(20, weight: .semibold))
                        .foregroundStyle(Color.white)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)

                    if let subtitle {
                        Text(subtitle)
                            .font(BespokeFont.inter(14, weight: .regular))
                            .foregroundStyle(Color.white.opacity(0.88))
                            .multilineTextAlignment(.leading)
                            .fixedSize(horizontal: false, vertical: true)
                            .lineLimit(2)
                    }
                }

                Spacer(minLength: 8)

                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color.white.opacity(0.9))
            }
            .padding(20)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, minHeight: 112, alignment: .leading)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(Color.white.opacity(0.18), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.14), radius: 16, x: 0, y: 8)
        .contentShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
    }
}

private struct CategoryCardButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .contentShape(Rectangle())
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .opacity(configuration.isPressed ? 0.94 : 1)
            .animation(.spring(response: 0.28, dampingFraction: 0.74), value: configuration.isPressed)
    }
}

private struct AllahNameCard: View {
    let name: AllahNameSummary
    let number: Int?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ZStack(alignment: .topTrailing) {
                VStack(spacing: 8) {
                    Text(name.arabic)
                        .font(BespokeFont.display(36))
                        .foregroundStyle(BespokeColor.forest)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity)
                        .minimumScaleFactor(0.75)
                        .lineLimit(2)

                    Text(name.transliteration)
                        .font(BespokeFont.inter(14, weight: .medium))
                        .foregroundStyle(BespokeColor.nameGold)
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

                if let number {
                    Text("\(number)")
                        .font(BespokeFont.inter(11, weight: .bold))
                        .foregroundStyle(BespokeColor.goldDeep)
                        .frame(width: 30, height: 30)
                        .background(BespokeColor.gold.opacity(0.14))
                        .clipShape(Circle())
                        .overlay {
                            Circle()
                                .stroke(BespokeColor.gold.opacity(0.4), lineWidth: 1)
                        }
                        .padding(14)
                }
            }

            VStack(alignment: .leading, spacing: 12) {
                Text(name.translation)
                    .font(BespokeFont.inter(17, weight: .semibold))
                    .foregroundStyle(BespokeColor.forest)
                    .fixedSize(horizontal: false, vertical: true)

                Capsule()
                    .fill(BespokeColor.gold.opacity(0.45))
                    .frame(width: 28, height: 2)

                Text(name.meaning)
                    .font(BespokeFont.inter(15, weight: .regular))
                    .foregroundStyle(BespokeColor.bodyText.opacity(0.9))
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
}

struct NamesLibraryConnectionComfortView: View {
    let title: String
    let message: String
    let onRetry: () async -> Void

    @State private var isRetrying = false

    var body: some View {
        VStack(spacing: 20) {
            DuaCraftingDhikrCarousel(
                statusText: "Take a quiet moment while we reconnect…"
            )

            VStack(spacing: 6) {
                Text(title)
                    .font(BespokeFont.inter(16, weight: .semibold))
                    .foregroundStyle(BespokeColor.forest)

                Text(message)
                    .font(BespokeFont.inter(14, weight: .regular))
                    .foregroundStyle(BespokeColor.muted)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 8)

            Button {
                guard !isRetrying else { return }
                Task {
                    isRetrying = true
                    await onRetry()
                    isRetrying = false
                }
            } label: {
                Group {
                    if isRetrying {
                        ProgressView()
                            .tint(.white)
                    } else {
                        Text("Try again")
                            .font(BespokeFont.inter(15, weight: .semibold))
                    }
                }
                .foregroundStyle(.white)
                .frame(minWidth: 120)
                .padding(.horizontal, 24)
                .padding(.vertical, 12)
                .background(BespokeColor.forest)
                .clipShape(Capsule())
            }
            .buttonStyle(BespokePlainButtonStyle())
            .disabled(isRetrying)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, BespokeLayout.libraryHorizontalPadding)
    }
}

#Preview {
    NavigationStack {
        NamesLibraryView()
    }
}
