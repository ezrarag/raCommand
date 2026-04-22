//
//  RepoManagerView.swift
//  raCommand
//
//  MacWhisper-inspired design: dark sidebar feel, two-panel layout,
//  clean rows, pill badges, in-app git clone via Process.
//

import Foundation
import SwiftUI
import SwiftData

// MARK: - Repo with local state
struct RepoWithLocalState: Identifiable, Hashable {
    let repo: GitHubRepo
    let isClonedLocally: Bool
    var id: Int { repo.id }
}

// MARK: - Clone operation state
enum CloneState: Equatable {
    case idle
    case cloning
    case success
    case failed(String)
}

// MARK: - Main View
struct RepoManagerView: View {
    @Environment(\.modelContext) private var context
    @Query private var projects: [Project]

    @State private var repos: [RepoWithLocalState] = []
    @State private var selectedRepo: RepoWithLocalState? = nil
    @State private var isLoading = false
    @State private var searchText = ""
    @State private var filterMode: FilterMode = .all
    @State private var showTokenAlert = false
    @State private var cloneStates: [Int: CloneState] = [:]
    @State private var cloneOutput: [Int: String] = [:]
    @State private var codexOpeningRepoID: Int?
    @State private var workspaceActionError: String?
    @State private var codexWorkspacePaths = Set<String>()
    @State private var trackedRepoIDs = Set<Int>()

    private let localDevPath = "/Users/ehauga/Desktop/local dev"

    enum FilterMode: String, CaseIterable {
        case all = "All"
        case cloned = "Local"
        case notCloned = "Remote Only"
    }

    var filteredRepos: [RepoWithLocalState] {
        var result = repos
        if !searchText.isEmpty {
            result = result.filter {
                $0.repo.name.localizedCaseInsensitiveContains(searchText) ||
                ($0.repo.description ?? "").localizedCaseInsensitiveContains(searchText)
            }
        }
        switch filterMode {
        case .cloned: result = result.filter { $0.isClonedLocally }
        case .notCloned: result = result.filter { !$0.isClonedLocally }
        case .all: break
        }
        return result
    }

    var body: some View {
        NavigationSplitView {
            // MARK: Sidebar
            sidebarContent
                .navigationTitle("Repos")
                .platformNavigationTitleDisplayMode(.large)
                .toolbar { toolbarContent }
                .platformSearchable(text: $searchText, placement: .alwaysDrawer, prompt: "Search repos")
        } detail: {
            // MARK: Detail Panel
            if let selected = selectedRepo {
                let trackedProject = project(for: selected.repo)
                let hasCodexThread = hasCodexThread(for: selected)
                RepoDetailPanel(
                    item: selected,
                    cloneState: cloneStates[selected.repo.id] ?? .idle,
                    cloneOutput: cloneOutput[selected.repo.id] ?? "",
                    localDevPath: localDevPath,
                    workspacePath: resolvedWorkspacePath(for: selected),
                    isTracked: isTracked(selected),
                    hasActiveThread: trackedProject?.isActiveThread == true,
                    hasCodexThread: hasCodexThread,
                    isOpeningInCodex: codexOpeningRepoID == selected.repo.id,
                    onClone: { await cloneRepo(selected) },
                    onTrack: { trackAsProject(selected) },
                    onOpenInCodex: { await openInCodex(selected) }
                )
            } else {
                emptyDetail
            }
        }
        .whisperShell()
        .alert("No GitHub Token", isPresented: $showTokenAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Save your GitHub token via Projects → Import → GitHub Import.")
        }
        .alert("Workspace Error", isPresented: Binding(
            get: { workspaceActionError != nil },
            set: { newValue in
                if !newValue { workspaceActionError = nil }
            }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(workspaceActionError ?? "")
        }
        .task {
            if repos.isEmpty { await loadRepos() }
        }
    }

    // MARK: - Sidebar Content
    private var sidebarContent: some View {
        Group {
            if isLoading {
                VStack(spacing: 14) {
                    ProgressView()
                        .tint(.secondary)
                    Text("Fetching repos…")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if repos.isEmpty {
                emptyState
            } else {
                List(filteredRepos, selection: $selectedRepo) { item in
                    RepoSidebarRow(
                        item: item,
                        hasCodexThread: hasCodexThread(for: item),
                        isTracked: isTracked(item)
                    )
                        .tag(item)
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)
                .safeAreaInset(edge: .top) {
                    statsBar
                        .padding(.horizontal)
                        .padding(.vertical, 8)
                }
            }
        }
    }

    // MARK: - Stats Bar
    private var statsBar: some View {
        HStack(spacing: 8) {
            statChip(value: repos.count, label: "Total", color: .blue)
            statChip(value: repos.filter { $0.isClonedLocally }.count, label: "Local", color: .green)
            statChip(value: repos.filter { !$0.isClonedLocally }.count, label: "Remote", color: .orange)
        }
        .whisperPanel(padding: 10, radius: 22)
    }

    private func statChip(value: Int, label: String, color: Color) -> some View {
        HStack(spacing: 4) {
            Text("\(value)")
                .font(.subheadline.bold())
                .foregroundStyle(color)
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(color.opacity(0.1), in: Capsule())
        .frame(maxWidth: .infinity)
    }

    // MARK: - Toolbar
    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .platformNavigationLeading) {
            Menu {
                ForEach(FilterMode.allCases, id: \.self) { mode in
                    Button {
                        filterMode = mode
                    } label: {
                        if filterMode == mode {
                            Label(mode.rawValue, systemImage: "checkmark")
                        } else {
                            Text(mode.rawValue)
                        }
                    }
                }
            } label: {
                Image(systemName: "line.3.horizontal.decrease.circle")
            }
        }
        ToolbarItem(placement: .platformNavigationTrailing) {
            Button {
                Task { await loadRepos() }
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .disabled(isLoading)
        }
    }

    // MARK: - Empty States
    private var emptyState: some View {
        VStack(spacing: 16) {
            WhisperEmptyState(
                icon: "externaldrive.badge.questionmark",
                title: "No repos loaded",
                message: "Fetch from GitHub to populate the repo board and local clone status."
            )
            Button("Refresh") {
                Task { await loadRepos() }
            }
            .buttonStyle(.bordered)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptyDetail: some View {
        VStack(spacing: 12) {
            WhisperEmptyState(
                icon: "sidebar.right",
                title: "Select a repo",
                message: "Use the left rail to inspect remote repos, local clones, and project tracking actions."
            )
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Load Repos
    private func loadRepos() async {
        guard let token = KeychainService.loadGitHubToken(), !token.isEmpty else {
            showTokenAlert = true
            return
        }
        isLoading = true
        do {
            let fetched = try await GitHubService.fetchRepos(token: token)
            let localFolders = getLocalFolderNames()
            let activeCodexPaths = LocalWorkspaceService.activeCodexWorkspacePaths(rootPathPrefix: localDevPath)
            repos = fetched
                .map { RepoWithLocalState(repo: $0, isClonedLocally: localFolders.contains($0.name)) }
                .sorted { a, b in
                    a.isClonedLocally != b.isClonedLocally ? a.isClonedLocally : a.repo.name < b.repo.name
                }
            codexWorkspacePaths = activeCodexPaths
            // Refresh selected item's state if visible
            if let sel = selectedRepo, let updated = repos.first(where: { $0.id == sel.id }) {
                selectedRepo = updated
            }
        } catch {
            // silently fail — alert already shown for token issues
        }
        isLoading = false
    }

    // MARK: - Local folder check
    private func getLocalFolderNames() -> Set<String> {
        let url = URL(fileURLWithPath: localDevPath)
        guard let contents = try? FileManager.default.contentsOfDirectory(
            at: url, includingPropertiesForKeys: [.isDirectoryKey], options: .skipsHiddenFiles
        ) else { return [] }
        return Set(contents.compactMap { u -> String? in
            var isDir: ObjCBool = false
            FileManager.default.fileExists(atPath: u.path, isDirectory: &isDir)
            return isDir.boolValue ? u.lastPathComponent : nil
        })
    }

    // MARK: - In-app clone via Process (macOS)
    private func cloneRepo(_ item: RepoWithLocalState) async {
        cloneStates[item.repo.id] = .cloning
        cloneOutput[item.repo.id] = ""

        let dest = "\(localDevPath)/\(item.repo.name)"

        // Check already exists
        if FileManager.default.fileExists(atPath: dest) {
            cloneStates[item.repo.id] = .success
            cloneOutput[item.repo.id] = "Already exists at local dev."
            await loadRepos()
            return
        }

        #if os(macOS)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = ["clone", item.repo.htmlURL, dest]

        let pipe = Pipe()
        let errorPipe = Pipe()
        process.standardOutput = pipe
        process.standardError = errorPipe

        do {
            try process.run()
            process.waitUntilExit()

            let outputData = pipe.fileHandleForReading.readDataToEndOfFile()
            let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(data: outputData, encoding: .utf8) ?? ""
            let errorOutput = String(data: errorData, encoding: .utf8) ?? ""
            let combined = [output, errorOutput].filter { !$0.isEmpty }.joined(separator: "\n")

            await MainActor.run {
                cloneOutput[item.repo.id] = combined.isEmpty ? "Clone complete." : combined
                if process.terminationStatus == 0 {
                    cloneStates[item.repo.id] = .success
                    attachLocalWorkspace(dest, to: item.repo)
                } else {
                    cloneStates[item.repo.id] = .failed("git exited with code \(process.terminationStatus)")
                }
            }
            await loadRepos()
        } catch {
            await MainActor.run {
                cloneStates[item.repo.id] = .failed(error.localizedDescription)
                cloneOutput[item.repo.id] = error.localizedDescription
            }
        }
        #else
        await MainActor.run {
            cloneStates[item.repo.id] = .failed("In-app cloning is only supported on macOS.")
            cloneOutput[item.repo.id] = "Run `git clone \(item.repo.htmlURL) \\\"\(dest)\\\"` from Terminal instead."
        }
        #endif
    }

    // MARK: - Track as project
    private func trackAsProject(_ item: RepoWithLocalState) {
        let wasAlreadyTracked = project(for: item.repo) != nil
        let project = ensureProject(for: item, workspacePath: resolvedWorkspacePath(for: item))

        do {
            try context.save()
            trackedRepoIDs.insert(item.repo.id)
        } catch {
            if !wasAlreadyTracked {
                context.delete(project)
            }
            workspaceActionError = error.localizedDescription
        }
    }

    private func attachLocalWorkspace(_ path: String, to repo: GitHubRepo) {
        guard let project = project(for: repo) else { return }
        project.localPath = path
        project.lastUpdated = Date()
    }

    private func openInCodex(_ item: RepoWithLocalState) async {
        guard codexOpeningRepoID != item.repo.id else { return }

        codexOpeningRepoID = item.repo.id
        workspaceActionError = nil

        if !item.isClonedLocally {
            cloneStates[item.repo.id] = .cloning
            cloneOutput[item.repo.id] = ""
        }

        defer {
            if codexOpeningRepoID == item.repo.id {
                codexOpeningRepoID = nil
            }
        }

        do {
            let workspacePath = try LocalWorkspaceService.ensureLocalClone(
                repoURL: item.repo.htmlURL,
                preferredPath: resolvedWorkspacePath(for: item),
                rootPath: localDevPath
            )

            let project = ensureProject(for: item, workspacePath: workspacePath)
            project.isActiveThread = true
            project.localPath = workspacePath
            project.lastUpdated = Date()
            project.lastReviewed = Date()
            trackedRepoIDs.insert(item.repo.id)

            try context.save()

            try LocalWorkspaceService.openInCodex(path: workspacePath)

            cloneStates[item.repo.id] = .success
            cloneOutput[item.repo.id] = "Workspace ready at \(workspacePath)"
            await loadRepos()
        } catch {
            let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            workspaceActionError = message
            if !item.isClonedLocally {
                cloneStates[item.repo.id] = .failed(message)
                cloneOutput[item.repo.id] = message
            }
        }
    }

    private func project(for repo: GitHubRepo) -> Project? {
        projects.first(where: { $0.repoURL == repo.htmlURL })
    }

    private func isTracked(_ item: RepoWithLocalState) -> Bool {
        project(for: item.repo) != nil || trackedRepoIDs.contains(item.repo.id)
    }

    private func resolvedWorkspacePath(for item: RepoWithLocalState) -> String? {
        if let existingPath = project(for: item.repo)?.localPath.trimmingCharacters(in: .whitespacesAndNewlines),
           !existingPath.isEmpty {
            return existingPath
        }

        if item.isClonedLocally {
            return LocalWorkspaceService.suggestedLocalPath(
                for: item.repo.htmlURL,
                rootPath: localDevPath
            )
        }

        return nil
    }

    private func hasCodexThread(for item: RepoWithLocalState) -> Bool {
        guard let workspacePath = resolvedWorkspacePath(for: item) else { return false }
        let normalizedPath = LocalWorkspaceService.normalizedWorkspacePath(workspacePath)
        guard !normalizedPath.isEmpty else { return false }
        return codexWorkspacePaths.contains(normalizedPath)
    }

    @discardableResult
    private func ensureProject(for item: RepoWithLocalState, workspacePath: String?) -> Project {
        if let existing = project(for: item.repo) {
            if existing.name.isEmpty {
                existing.name = item.repo.name
            }
            if existing.notes.isEmpty {
                existing.notes = item.repo.description ?? ""
            }
            if let workspacePath, !workspacePath.isEmpty {
                existing.localPath = workspacePath
            }
            existing.lastUpdated = Date()
            existing.lastReviewed = Date()
            return existing
        }

        let project = Project(
            name: item.repo.name,
            status: .yellow,
            valueScore: 5,
            notes: item.repo.description ?? "",
            repoURL: item.repo.htmlURL,
            localPath: workspacePath ?? ""
        )
        context.insert(project)
        return project
    }
}

// MARK: - Sidebar Row
struct RepoSidebarRow: View {
    let item: RepoWithLocalState
    let hasCodexThread: Bool
    let isTracked: Bool

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: item.isClonedLocally ? "checkmark.circle.fill" : "arrow.down.circle")
                .foregroundStyle(item.isClonedLocally ? .green : .orange)
                .font(.system(size: 18))
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 4) {
                Text(item.repo.name)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(WhisperTheme.ink)
                    .lineLimit(2)
                    .layoutPriority(1)

                if hasCodexThread {
                    Label("Codex thread active", systemImage: "rectangle.stack.badge.checkmark")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(WhisperTheme.info)
                        .lineLimit(1)
                } else if isTracked {
                    Label("Tracked in Projects", systemImage: "folder.badge.plus")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(WhisperTheme.success)
                        .lineLimit(1)
                } else if let desc = item.repo.description, !desc.isEmpty {
                    Text(desc)
                        .font(.caption)
                        .foregroundStyle(WhisperTheme.mutedInk)
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Spacer()

            Text(item.isClonedLocally ? "Local" : "Remote")
                .font(.caption2.bold())
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .background(
                    (item.isClonedLocally ? Color.green : Color.orange).opacity(0.15),
                    in: Capsule()
                )
                .foregroundStyle(item.isClonedLocally ? .green : .orange)
        }
        .padding(14)
        .background(WhisperTheme.panel.opacity(0.88), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(WhisperTheme.border, lineWidth: 1)
        )
        .padding(.vertical, 4)
    }
}

// MARK: - Detail Panel
struct RepoDetailPanel: View {
    let item: RepoWithLocalState
    let cloneState: CloneState
    let cloneOutput: String
    let localDevPath: String
    let workspacePath: String?
    let isTracked: Bool
    let hasActiveThread: Bool
    let hasCodexThread: Bool
    let isOpeningInCodex: Bool
    let onClone: () async -> Void
    let onTrack: () -> Void
    let onOpenInCodex: () async -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                // Header
                VStack(alignment: .leading, spacing: 8) {
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(item.repo.name)
                                .font(.title2.bold())
                                .foregroundStyle(WhisperTheme.ink)
                            if let desc = item.repo.description, !desc.isEmpty {
                                Text(desc)
                                    .font(.subheadline)
                                    .foregroundStyle(WhisperTheme.mutedInk)
                            }
                        }
                        Spacer()
                        statusBadges
                    }
                }
                .whisperPanel()
                .padding()

                // Action buttons
                VStack(spacing: 0) {
                    codexActionRow

                    Divider().padding(.leading, 52)

                    actionRow(
                        icon: "safari",
                        label: "Open on GitHub",
                        color: .blue
                    ) {
                        if let url = URL(string: item.repo.htmlURL) {
                            PlatformSystemServices.open(url)
                        }
                    }

                    Divider().padding(.leading, 52)

                    if !item.isClonedLocally {
                        cloneActionRow
                        Divider().padding(.leading, 52)
                    }

                    actionRow(
                        icon: "folder.badge.plus",
                        label: isTracked ? "In Projects ✓" : "Add to Projects Only",
                        color: isTracked ? .green : .purple
                    ) {
                        if !isTracked {
                            onTrack()
                        }
                    }
                }
                .whisperPanel(padding: 0, radius: 24)
                .padding()

                // Clone output log
                if !cloneOutput.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Label("Output", systemImage: "terminal")
                            .font(.caption.bold())
                            .foregroundStyle(.secondary)

                        Text(cloneOutput)
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(.primary)
                            .padding(12)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(WhisperTheme.input, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    }
                    .whisperPanel()
                    .padding(.horizontal)
                }

                // Local path info
                if let workspacePath, !workspacePath.isEmpty {
                    HStack(spacing: 8) {
                        Image(systemName: "folder.fill")
                            .foregroundStyle(.secondary)
                        Text(workspacePath)
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                    .whisperPanel()
                    .padding()
                }

                Spacer(minLength: 40)
            }
        }
        .navigationTitle(item.repo.name)
        .platformNavigationTitleDisplayMode(.inline)
    }

    private var statusBadges: some View {
        VStack(alignment: .trailing, spacing: 8) {
            HStack(spacing: 4) {
                Circle()
                    .fill(item.isClonedLocally ? Color.green : Color.orange)
                    .frame(width: 8, height: 8)
                Text(item.isClonedLocally ? "Cloned Locally" : "Remote Only")
                    .font(.caption.bold())
                    .foregroundStyle(item.isClonedLocally ? .green : .orange)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(
                (item.isClonedLocally ? Color.green : Color.orange).opacity(0.12),
                in: Capsule()
            )

            if hasCodexThread {
                HStack(spacing: 4) {
                    Image(systemName: "rectangle.stack.badge.checkmark")
                    Text("Codex Thread")
                }
                .font(.caption.bold())
                .foregroundStyle(WhisperTheme.info)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(WhisperTheme.info.opacity(0.12), in: Capsule())
            }
        }
    }

    private var codexActionRow: some View {
        HStack(spacing: 16) {
            Image(systemName: codexIcon)
                .foregroundStyle(codexColor)
                .font(.system(size: 20))
                .frame(width: 36)

            VStack(alignment: .leading, spacing: 2) {
                Text(codexLabel)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(codexColor)
                Text(codexSubtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if isOpeningInCodex {
                ProgressView()
                    .tint(.secondary)
            } else {
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 14)
        .contentShape(Rectangle())
        .onTapGesture {
            if !isOpeningInCodex {
                Task { await onOpenInCodex() }
            }
        }
    }

    private var cloneActionRow: some View {
        HStack(spacing: 16) {
            Image(systemName: cloneIcon)
                .foregroundStyle(cloneColor)
                .font(.system(size: 20))
                .frame(width: 36)

            VStack(alignment: .leading, spacing: 2) {
                Text(cloneLabel)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(cloneColor)
                Text("Clones into ~/Desktop/local dev")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if cloneState == .cloning {
                ProgressView()
                    .tint(.secondary)
            } else {
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 14)
        .contentShape(Rectangle())
        .onTapGesture {
            if cloneState != .cloning {
                Task { await onClone() }
            }
        }
    }

    private var codexIcon: String {
        if isOpeningInCodex {
            return "hourglass"
        }
        return hasActiveThread ? "rectangle.stack.badge.checkmark" : "rectangle.stack.badge.play"
    }

    private var codexColor: Color {
        hasActiveThread ? .green : .blue
    }

    private var codexLabel: String {
        if isOpeningInCodex {
            return item.isClonedLocally ? "Opening in Codex…" : "Preparing Codex Workspace…"
        }
        if hasCodexThread {
            return "Open Existing Thread in Codex"
        }
        if hasActiveThread {
            return "Open Active Thread in Codex"
        }
        return item.isClonedLocally ? "Start Thread in Codex" : "Clone and Open in Codex"
    }

    private var codexSubtitle: String {
        if hasCodexThread {
            return "Detected an existing Codex thread for this local workspace."
        }
        if hasActiveThread {
            return "Opens the repo workspace in Codex Desktop."
        }
        if item.isClonedLocally {
            return "Adds it to Projects if needed, marks it active, and opens its local workspace."
        }
        return "Clones into local dev if needed, adds it to Projects, then opens the workspace in Codex."
    }

    private var cloneIcon: String {
        switch cloneState {
        case .idle: return "arrow.down.to.line.circle"
        case .cloning: return "arrow.down.to.line.circle"
        case .success: return "checkmark.circle.fill"
        case .failed: return "exclamationmark.triangle"
        }
    }

    private var cloneColor: Color {
        switch cloneState {
        case .idle: return .blue
        case .cloning: return .blue
        case .success: return .green
        case .failed: return .red
        }
    }

    private var cloneLabel: String {
        switch cloneState {
        case .idle: return "Clone to Local Dev"
        case .cloning: return "Cloning…"
        case .success: return "Cloned Successfully"
        case .failed(let msg): return "Failed: \(msg)"
        }
    }

    private func actionRow(icon: String, label: String, color: Color, action: @escaping () -> Void) -> some View {
        HStack(spacing: 16) {
            Image(systemName: icon)
                .foregroundStyle(color)
                .font(.system(size: 20))
                .frame(width: 36)

            Text(label)
                .font(.subheadline.weight(.medium))

            Spacer()

            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal)
        .padding(.vertical, 14)
        .contentShape(Rectangle())
        .onTapGesture { action() }
    }
}
