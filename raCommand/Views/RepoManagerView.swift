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
    let localPath: String?

    var isClonedLocally: Bool { localPath != nil }
    var id: Int { repo.id }
}

// MARK: - Clone operation state
enum CloneState: Equatable {
    case idle
    case cloning
    case success
    case failed(String)
}

enum GitActionKind: Equatable {
    case push
    case removeLocal
}

enum GitActionState: Equatable {
    case idle
    case running(GitActionKind)
    case success(GitActionKind, String)
    case failed(GitActionKind, String)

    var isRunning: Bool {
        if case .running = self { return true }
        return false
    }
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
    @State private var gitSnapshots: [Int: LocalGitSnapshot] = [:]
    @State private var gitStatusErrors: [Int: String] = [:]
    @State private var workspaceSizes: [Int: Int64] = [:]
    @State private var gitActionStates: [Int: GitActionState] = [:]
    @State private var pendingPushRepo: RepoWithLocalState?
    @State private var pendingRemovalRepo: RepoWithLocalState?
    @State private var pendingRemovalCommitRepo: RepoWithLocalState?
    @State private var commitMessage = ""

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
        case .cloned:
            result = result.filter { $0.isClonedLocally }
        case .notCloned:
            result = result.filter { !$0.isClonedLocally }
        case .all:
            break
        }
        return result
    }

    private var localRepos: [RepoWithLocalState] {
        filteredRepos
            .filter(\.isClonedLocally)
            .sorted { lhs, rhs in
                let lhsSize = workspaceSizes[lhs.repo.id] ?? -1
                let rhsSize = workspaceSizes[rhs.repo.id] ?? -1
                if lhsSize != rhsSize {
                    return lhsSize > rhsSize
                }
                return lhs.repo.name.localizedCaseInsensitiveCompare(rhs.repo.name) == .orderedAscending
            }
    }

    private var remoteRepos: [RepoWithLocalState] {
        filteredRepos
            .filter { !$0.isClonedLocally }
            .sorted {
                $0.repo.name.localizedCaseInsensitiveCompare($1.repo.name) == .orderedAscending
            }
    }

    private var removalConfirmationMessage: String {
        guard let item = pendingRemovalRepo,
              let path = resolvedWorkspacePath(for: item) else {
            return "raCommand will move this local workspace to Trash."
        }
        return "raCommand will update this local workspace to its newest upstream version, archive matching Codex threads, then move the folder to Trash:\n\(path)"
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
                    gitSnapshot: gitSnapshots[selected.repo.id],
                    gitStatusError: gitStatusErrors[selected.repo.id],
                    workspaceSize: workspaceSizes[selected.repo.id],
                    gitActionState: gitActionStates[selected.repo.id] ?? .idle,
                    pushDisabledReason: pushDisabledReason(for: selected),
                    removalDisabledReason: removalDisabledReason(for: selected),
                    workspacePath: resolvedWorkspacePath(for: selected),
                    suggestedCommitMessage: gitSnapshots[selected.repo.id].map {
                        LocalGitCommandService.suggestedCommitMessage(
                            for: $0,
                            repoName: selected.repo.name
                        )
                    },
                    isTracked: isTracked(selected),
                    hasActiveThread: trackedProject?.isActiveThread == true,
                    hasCodexThread: hasCodexThread,
	                    isOpeningInCodex: codexOpeningRepoID == selected.repo.id,
	                    onClone: { await cloneRepo(selected) },
	                    onTrack: { trackAsProject(selected) },
	                    onOpenInCodex: { await openInCodex(selected) },
	                    onPush: { requestPush(selected) },
	                    onRemoveLocal: { requestLocalRemoval(selected) },
	                    onRefreshGitStatus: { refreshGitSnapshot(for: selected) }
	                )
            } else {
                emptyDetail
            }
        }
        .whisperShell()
        .quickIdeaToolbar()
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
        .alert("Commit and Push", isPresented: Binding(
	            get: { pendingPushRepo != nil },
	            set: { newValue in
	                if !newValue {
	                    pendingPushRepo = nil
	                    commitMessage = ""
	                }
	            }
	        )) {
	            TextField("Commit message", text: $commitMessage)
	            Button("Commit & Push") {
	                let item = pendingPushRepo
	                let message = commitMessage
	                pendingPushRepo = nil
	                commitMessage = ""
	                if let item {
	                    Task { await pushRepo(item, commitMessage: message) }
	                }
	            }
	            .disabled(commitMessage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
	            Button("Cancel", role: .cancel) {
	                pendingPushRepo = nil
	                commitMessage = ""
	            }
        } message: {
            Text("This repo has local changes. Enter a commit message; raCommand will run git add -A, commit, then push.")
        }
        .alert("Commit, Update, and Remove", isPresented: Binding(
            get: { pendingRemovalCommitRepo != nil },
            set: { newValue in
                if !newValue {
                    pendingRemovalCommitRepo = nil
                    commitMessage = ""
                }
            }
        )) {
            TextField("Commit message", text: $commitMessage)
            Button("Commit, Update & Remove", role: .destructive) {
                let item = pendingRemovalCommitRepo
                let message = commitMessage
                pendingRemovalCommitRepo = nil
                commitMessage = ""
                if let item {
                    Task { await removeLocalCopy(item, commitMessage: message) }
                }
            }
            .disabled(commitMessage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            Button("Cancel", role: .cancel) {
                pendingRemovalCommitRepo = nil
                commitMessage = ""
            }
        } message: {
            Text("This repo has local changes. Enter a commit message; raCommand will commit, synchronize with upstream, archive matching Codex threads, then move the selected folder to Trash.")
        }
        .alert("Remove Local Copy?", isPresented: Binding(
	            get: { pendingRemovalRepo != nil },
	            set: { newValue in
	                if !newValue { pendingRemovalRepo = nil }
	            }
	        )) {
	            Button("Move to Trash", role: .destructive) {
                let item = pendingRemovalRepo
                pendingRemovalRepo = nil
                if let item {
                    Task { await removeLocalCopy(item, commitMessage: nil) }
                }
	            }
	            Button("Cancel", role: .cancel) {
	                pendingRemovalRepo = nil
	            }
	        } message: {
	            Text(removalConfirmationMessage)
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
                List(selection: $selectedRepo) {
                    if !localRepos.isEmpty {
                        Section {
                            ForEach(localRepos) { item in
                                RepoSidebarRow(
                                    item: item,
                                    hasCodexThread: hasCodexThread(for: item),
                                    isTracked: isTracked(item),
                                    gitSnapshot: gitSnapshots[item.repo.id],
                                    gitStatusError: gitStatusErrors[item.repo.id],
                                    workspaceSize: workspaceSizes[item.repo.id],
                                    isOpeningInCodex: codexOpeningRepoID == item.repo.id,
                                    gitActionState: gitActionStates[item.repo.id] ?? .idle,
                                    onOpenInCodex: { Task { await openInCodex(item) } },
                                    pushDisabledReason: pushDisabledReason(for: item),
                                    removalDisabledReason: removalDisabledReason(for: item),
                                    onPush: { requestPush(item) },
                                    onRemoveLocal: { requestLocalRemoval(item) }
                                )
                                .tag(item)
                            }
                        } header: {
                            sectionHeader(title: "Local", count: localRepos.count, color: .green)
                        }
                    }

                    if !remoteRepos.isEmpty {
                        Section {
                            ForEach(remoteRepos) { item in
                                RepoSidebarRow(
                                    item: item,
                                    hasCodexThread: hasCodexThread(for: item),
                                    isTracked: isTracked(item),
                                    gitSnapshot: nil,
                                    gitStatusError: nil,
                                    workspaceSize: nil,
                                    isOpeningInCodex: false,
                                    gitActionState: .idle,
                                    onOpenInCodex: nil,
                                    pushDisabledReason: nil,
                                    removalDisabledReason: nil,
                                    onPush: nil,
                                    onRemoveLocal: nil
                                )
                                .tag(item)
                            }
                        } header: {
                            sectionHeader(title: "Remote Only", count: remoteRepos.count, color: .orange)
                        }
                    }
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

    private func sectionHeader(title: String, count: Int, color: Color) -> some View {
        HStack {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(WhisperTheme.mutedInk)
            Spacer()
            Text("\(count)")
                .font(.caption2.weight(.bold))
                .foregroundStyle(color)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(color.opacity(0.12), in: Capsule())
        }
        .textCase(nil)
    }

    // MARK: - Stats Bar
    private var statsBar: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                statChip(value: repos.count, label: "Total", color: .blue)
                statChip(value: repos.filter { $0.isClonedLocally }.count, label: "Local", color: .green)
                statChip(value: repos.filter { !$0.isClonedLocally }.count, label: "Remote", color: .orange)
            }

            Picker("Repo filter", selection: $filterMode) {
                ForEach(FilterMode.allCases, id: \.self) { mode in
                    Text(mode.rawValue).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
        }
        .whisperPanel(padding: 10, radius: 10)
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
            let activeCodexPaths = LocalWorkspaceService.activeCodexWorkspacePaths(rootPathPrefix: localDevPath)
            repos = fetched
                .map { repo in
                    RepoWithLocalState(
                        repo: repo,
                        localPath: detectedLocalWorkspacePath(for: repo)
                    )
                }
                .sorted { a, b in
                    if a.isClonedLocally != b.isClonedLocally {
                        return a.isClonedLocally
                    }
                    return a.repo.name.localizedCaseInsensitiveCompare(b.repo.name) == .orderedAscending
                }
            codexWorkspacePaths = activeCodexPaths
            if let sel = selectedRepo, let updated = repos.first(where: { $0.id == sel.id }) {
                selectedRepo = updated
            }
            refreshGitSnapshots()
        } catch {
            // silently fail — alert already shown for token issues
        }
        isLoading = false
    }

    private func detectedLocalWorkspacePath(for repo: GitHubRepo) -> String? {
        if let storedPath = project(for: repo)?.localPath,
           !storedPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let normalizedStoredPath = LocalWorkspaceService.normalizedWorkspacePath(storedPath)
            if LocalWorkspaceService.workspaceExists(at: normalizedStoredPath) {
                return normalizedStoredPath
            }
        }

        guard let suggestedPath = LocalWorkspaceService.suggestedLocalPath(
            for: repo.htmlURL,
            rootPath: localDevPath
        ) else {
            return nil
        }

        let normalizedSuggestedPath = LocalWorkspaceService.normalizedWorkspacePath(suggestedPath)
        guard LocalWorkspaceService.workspaceExists(at: normalizedSuggestedPath) else {
            return nil
        }
        return normalizedSuggestedPath
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

    private func requestPush(_ item: RepoWithLocalState) {
        if let reason = pushDisabledReason(for: item) {
            workspaceActionError = reason
            return
        }

        if gitSnapshots[item.repo.id]?.isDirty == true {
            commitMessage = LocalGitCommandService.suggestedCommitMessage(
                for: gitSnapshots[item.repo.id],
                repoName: item.repo.name
            )
            pendingPushRepo = item
        } else {
            Task { await pushRepo(item, commitMessage: nil) }
        }
    }

    private func pushRepo(_ item: RepoWithLocalState, commitMessage: String?) async {
        guard let path = resolvedWorkspacePath(for: item) else {
            workspaceActionError = "The local workspace path could not be resolved."
            return
        }

        gitActionStates[item.repo.id] = .running(.push)
        do {
            let result = try await Task.detached(priority: .userInitiated) {
                try LocalGitCommandService.commitAndPush(at: path, commitMessage: commitMessage)
            }.value

            gitActionStates[item.repo.id] = .success(.push, result.output)
            refreshGitSnapshot(for: item)
            await loadRepos()
        } catch {
            let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            gitActionStates[item.repo.id] = .failed(.push, message)
            workspaceActionError = message
            refreshGitSnapshot(for: item)
        }
    }

    private func requestLocalRemoval(_ item: RepoWithLocalState) {
        if let reason = removalDisabledReason(for: item) {
            workspaceActionError = reason
            return
        }

        if gitSnapshots[item.repo.id]?.isDirty == true {
            commitMessage = LocalGitCommandService.suggestedCommitMessage(
                for: gitSnapshots[item.repo.id],
                repoName: item.repo.name,
                isRemovalFlow: true
            )
            pendingRemovalCommitRepo = item
            return
        }

        pendingRemovalRepo = item
    }

    private func removeLocalCopy(_ item: RepoWithLocalState, commitMessage: String?) async {
        guard let path = resolvedWorkspacePath(for: item) else {
            workspaceActionError = "The local workspace path could not be resolved."
            return
        }

        gitActionStates[item.repo.id] = .running(.removeLocal)
        do {
            let result = try await Task.detached(priority: .userInitiated) {
                let prepare = try LocalGitCommandService.prepareForRemoval(at: path, commitMessage: commitMessage)
                let archive = try LocalWorkspaceService.archiveCodexThreads(forWorkspacePath: path)
                let trash = try LocalGitCommandService.moveCleanWorkspaceToTrash(at: path)
                return LocalGitCommandResult(output: [
                    prepare.output,
                    archive.message,
                    trash.output
                ]
                    .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
                    .joined(separator: "\n\n"))
            }.value

            clearProjectPathIfNeeded(for: item, removedPath: path)
            gitSnapshots[item.repo.id] = nil
            gitStatusErrors[item.repo.id] = nil
            gitActionStates[item.repo.id] = .success(.removeLocal, result.output)
            await loadRepos()
        } catch {
            let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            gitActionStates[item.repo.id] = .failed(.removeLocal, message)
            workspaceActionError = message
            refreshGitSnapshot(for: item)
        }
    }

    private func refreshGitSnapshots() {
        var nextSnapshots: [Int: LocalGitSnapshot] = [:]
        var nextErrors: [Int: String] = [:]
        var nextSizes: [Int: Int64] = [:]

        for item in repos where item.isClonedLocally {
            guard let path = resolvedWorkspacePath(for: item) else {
                nextErrors[item.repo.id] = "The local workspace path could not be resolved."
                continue
            }

            if let size = LocalWorkspaceService.directorySize(at: path) {
                nextSizes[item.repo.id] = size
            }

            do {
                nextSnapshots[item.repo.id] = try LocalGitCommandService.status(at: path)
            } catch {
                nextErrors[item.repo.id] = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            }
        }

        gitSnapshots = nextSnapshots
        gitStatusErrors = nextErrors
        workspaceSizes = nextSizes
    }

    private func refreshGitSnapshot(for item: RepoWithLocalState) {
        guard item.isClonedLocally, let path = resolvedWorkspacePath(for: item) else {
            gitSnapshots[item.repo.id] = nil
            gitStatusErrors[item.repo.id] = nil
            workspaceSizes[item.repo.id] = nil
            return
        }

        workspaceSizes[item.repo.id] = LocalWorkspaceService.directorySize(at: path)

        do {
            gitSnapshots[item.repo.id] = try LocalGitCommandService.status(at: path)
            gitStatusErrors[item.repo.id] = nil
        } catch {
            gitSnapshots[item.repo.id] = nil
            gitStatusErrors[item.repo.id] = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    private func pushDisabledReason(for item: RepoWithLocalState) -> String? {
        guard item.isClonedLocally else { return "Clone this repository before pushing." }
        if gitActionStates[item.repo.id]?.isRunning == true { return "A git action is already running." }
        if let error = gitStatusErrors[item.repo.id] { return "Git status unavailable: \(error)" }
        guard let snapshot = gitSnapshots[item.repo.id] else { return "Git status is still loading." }
        guard snapshot.originURL != nil else { return "This repository has no origin remote." }
        guard let behind = snapshot.behindCount, snapshot.aheadCount != nil else {
            return "This branch has no upstream. Set an upstream before pushing from raCommand."
        }
        guard behind == 0 else {
            return "This branch is behind its upstream by \(behind) commit\(behind == 1 ? "" : "s"). Pull outside raCommand before pushing."
        }
        return nil
    }

    private func removalDisabledReason(for item: RepoWithLocalState) -> String? {
        guard item.isClonedLocally else { return "There is no local copy to remove." }
        if gitActionStates[item.repo.id]?.isRunning == true { return "A git action is already running." }
        if let error = gitStatusErrors[item.repo.id] { return "Git status unavailable: \(error)" }
        guard let snapshot = gitSnapshots[item.repo.id] else { return "Git status is still loading." }
        guard snapshot.originURL != nil else {
            return "This repository has no origin remote, so raCommand cannot verify whether local work is backed up."
        }
        guard let ahead = snapshot.aheadCount else {
            return "This branch has no upstream, so raCommand cannot verify whether local commits are pushed."
        }
        let behind = snapshot.behindCount ?? 0
        if ahead > 0 && behind > 0 {
            return "This branch has diverged from upstream. Resolve it outside raCommand before removing this local copy."
        }
        return nil
    }

    private func clearProjectPathIfNeeded(for item: RepoWithLocalState, removedPath: String) {
        guard let project = project(for: item.repo) else { return }
        let savedPath = LocalWorkspaceService.normalizedWorkspacePath(project.localPath)
        let deletedPath = LocalWorkspaceService.normalizedWorkspacePath(removedPath)
        guard savedPath == deletedPath else { return }

        project.localPath = ""
        project.isActiveThread = false
        project.lastUpdated = Date()

        do {
            try context.save()
        } catch {
            workspaceActionError = error.localizedDescription
        }
    }

	    private func project(for repo: GitHubRepo) -> Project? {
	        projects.first(where: { $0.repoURL == repo.htmlURL })
	    }

    private func isTracked(_ item: RepoWithLocalState) -> Bool {
        project(for: item.repo) != nil || trackedRepoIDs.contains(item.repo.id)
    }

    private func resolvedWorkspacePath(for item: RepoWithLocalState) -> String? {
        if let localPath = item.localPath {
            return localPath
        }

        if let existingPath = project(for: item.repo)?.localPath.trimmingCharacters(in: .whitespacesAndNewlines),
           !existingPath.isEmpty {
            return LocalWorkspaceService.normalizedWorkspacePath(existingPath)
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
    let gitSnapshot: LocalGitSnapshot?
    let gitStatusError: String?
    let workspaceSize: Int64?
    let isOpeningInCodex: Bool
    let gitActionState: GitActionState
    let onOpenInCodex: (() -> Void)?
    let pushDisabledReason: String?
    let removalDisabledReason: String?
    let onPush: (() -> Void)?
    let onRemoveLocal: (() -> Void)?

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

                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(subtitleColor)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Spacer()

            VStack(alignment: .trailing, spacing: 6) {
                HStack(spacing: 8) {
                    if item.isClonedLocally {
                        quickActionButton(
                            icon: isOpeningInCodex ? "rectangle.stack.badge.play.fill" : "rectangle.stack.badge.play",
                            color: .blue,
                            help: hasCodexThread ? "Open the existing Codex thread" : "Open this local repo in Codex",
                            isDisabled: isOpeningInCodex,
                            action: onOpenInCodex
                        )

                        quickActionButton(
                            icon: pushQuickActionIcon,
                            color: pushDisabledReason == nil ? .blue : .secondary,
                            help: pushDisabledReason ?? pushQuickActionHelp,
                            isDisabled: pushDisabledReason != nil || gitActionState.isRunning,
                            action: onPush
                        )

                        quickActionButton(
                            icon: removeQuickActionIcon,
                            color: removalDisabledReason == nil ? .red : .secondary,
                            help: removalDisabledReason ?? removeQuickActionHelp,
                            isDisabled: removalDisabledReason != nil || gitActionState.isRunning,
                            action: onRemoveLocal
                        )
                    }

                    if hasCodexThread {
                        Image(systemName: "rectangle.stack.badge.checkmark")
                            .foregroundStyle(WhisperTheme.info)
                    } else if isTracked {
                        Image(systemName: "folder.badge.plus")
                            .foregroundStyle(WhisperTheme.success)
                    }

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

                if let workspaceSizeLabel {
                    Text(workspaceSizeLabel)
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(14)
        .background(WhisperTheme.panel.opacity(0.88), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(WhisperTheme.border, lineWidth: 1)
        )
        .padding(.vertical, 4)
    }

    private var subtitle: String {
        var fragments: [String] = []

        if hasCodexThread {
            fragments.append("Codex thread")
        } else if isTracked {
            fragments.append("Tracked")
        }

        if item.isClonedLocally {
            if let gitStatusError, !gitStatusError.isEmpty {
                fragments.append("Git status unavailable")
            } else if let gitSnapshot {
                if gitSnapshot.changedFileCount > 0 {
                    fragments.append("\(gitSnapshot.changedFileCount) changed")
                }
                if let ahead = gitSnapshot.aheadCount, ahead > 0 {
                    fragments.append("\(ahead) ahead")
                }
                if let behind = gitSnapshot.behindCount, behind > 0 {
                    fragments.append("\(behind) behind")
                }
                if fragments.isEmpty {
                    fragments.append("Clean")
                }
                if let commit = gitSnapshot.recentCommits.first {
                    fragments.append("\(commit.shortSHA) \(commit.message)")
                }
            }
        }

        if fragments.isEmpty, let desc = item.repo.description, !desc.isEmpty {
            fragments.append(desc)
        }

        return fragments.isEmpty ? item.repo.htmlURL : fragments.joined(separator: " • ")
    }

    private var subtitleColor: Color {
        if item.isClonedLocally, gitStatusError != nil {
            return WhisperTheme.danger
        }
        if item.isClonedLocally, let gitSnapshot, gitSnapshot.changedFileCount > 0 {
            return WhisperTheme.warning
        }
        if hasCodexThread {
            return WhisperTheme.info
        }
        if isTracked {
            return WhisperTheme.success
        }
        return WhisperTheme.mutedInk
    }

    private var workspaceSizeLabel: String? {
        guard item.isClonedLocally, let workspaceSize else { return nil }
        return ByteCountFormatter.string(fromByteCount: workspaceSize, countStyle: .file)
    }

    private var pushQuickActionIcon: String {
        switch gitActionState {
        case .running(.push):
            return "arrow.up.circle.fill"
        case .success(.push, _):
            return "checkmark.circle.fill"
        case .failed(.push, _):
            return "exclamationmark.triangle.fill"
        case .idle, .running(.removeLocal), .success(.removeLocal, _), .failed(.removeLocal, _):
            return "arrow.up.circle"
        }
    }

    private var removeQuickActionIcon: String {
        switch gitActionState {
        case .running(.removeLocal):
            return "trash.circle.fill"
        case .success(.removeLocal, _):
            return "checkmark.circle.fill"
        case .failed(.removeLocal, _):
            return "exclamationmark.triangle.fill"
        case .idle, .running(.push), .success(.push, _), .failed(.push, _):
            return "trash.circle"
        }
    }

    private var pushQuickActionHelp: String {
        if let gitSnapshot, gitSnapshot.isDirty {
            return "Commit and push local changes"
        }
        return "Push this local repo"
    }

    private var removeQuickActionHelp: String {
        "Push if needed, archive matching Codex threads, then remove the local copy"
    }

    @ViewBuilder
    private func quickActionButton(
        icon: String,
        color: Color,
        help: String,
        isDisabled: Bool,
        action: (() -> Void)?
    ) -> some View {
        if let action {
            Button(action: action) {
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(color)
                    .frame(width: 28, height: 28)
                    .background(color.opacity(0.12), in: Circle())
            }
            .buttonStyle(.plain)
            .help(help)
            .disabled(isDisabled)
            .opacity(isDisabled ? 0.55 : 1)
        }
    }
}

// MARK: - Detail Panel
struct RepoDetailPanel: View {
    let item: RepoWithLocalState
    let cloneState: CloneState
    let cloneOutput: String
    let gitSnapshot: LocalGitSnapshot?
    let gitStatusError: String?
    let workspaceSize: Int64?
    let gitActionState: GitActionState
    let pushDisabledReason: String?
    let removalDisabledReason: String?
    let workspacePath: String?
    let suggestedCommitMessage: String?
    let isTracked: Bool
    let hasActiveThread: Bool
    let hasCodexThread: Bool
    let isOpeningInCodex: Bool
    let onClone: () async -> Void
    let onTrack: () -> Void
    let onOpenInCodex: () async -> Void
    let onPush: () -> Void
    let onRemoveLocal: () -> Void
    let onRefreshGitStatus: () -> Void

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

                if item.isClonedLocally {
                    gitStatusPanel
                        .padding(.horizontal)
                        .padding(.bottom, 12)

                    if hasWorkspaceSummary {
                        workspaceSummaryPanel
                            .padding(.horizontal)
                            .padding(.bottom, 12)
                    }

                    if hasRecentCommits {
                        recentCommitsPanel
                            .padding(.horizontal)
                            .padding(.bottom, 12)
                    }
                }

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

                    if item.isClonedLocally {
                        pushActionRow
                        Divider().padding(.leading, 52)

                        removeLocalActionRow
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
                .whisperPanel(padding: 0, radius: 10)
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

                if let gitActionOutput, !gitActionOutput.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Label("Git Action", systemImage: "terminal")
                            .font(.caption.bold())
                            .foregroundStyle(.secondary)

                        Text(gitActionOutput)
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

    private var gitStatusPanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("Git Status", systemImage: "point.3.connected.trianglepath.dotted")
                    .font(.caption.bold())
                    .foregroundStyle(.secondary)

                Spacer()

                Button {
                    onRefreshGitStatus()
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.caption.weight(.semibold))
                }
                .buttonStyle(.plain)
            }

            if let gitStatusError {
                Text(gitStatusError)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            } else if let gitSnapshot {
                HStack(spacing: 8) {
                    gitChip(label: "Branch", value: gitSnapshot.branch, color: .blue)
                    gitChip(label: "Dirty", value: "\(gitSnapshot.changedFileCount)", color: gitSnapshot.isDirty ? .orange : .green)
                    gitChip(label: "Ahead", value: countLabel(gitSnapshot.aheadCount), color: (gitSnapshot.aheadCount ?? 0) > 0 ? .orange : .secondary)
                    gitChip(label: "Behind", value: countLabel(gitSnapshot.behindCount), color: (gitSnapshot.behindCount ?? 0) > 0 ? .red : .secondary)
                }

                Text(gitSnapshot.originURL ?? "No origin remote")
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            } else {
                Text("Inspecting local git status...")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .whisperPanel(padding: 14, radius: 18)
    }

    private var workspaceSummaryPanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Local Workspace", systemImage: "externaldrive")
                .font(.caption.bold())
                .foregroundStyle(.secondary)

            if let workspacePath, !workspacePath.isEmpty {
                Text(workspacePath)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }

            if let workspaceSize {
                infoRow(label: "Size", value: ByteCountFormatter.string(fromByteCount: workspaceSize, countStyle: .file))
            }

            if let suggestedCommitMessage, let gitSnapshot, gitSnapshot.isDirty {
                infoRow(label: "Suggested commit", value: suggestedCommitMessage)
            }
        }
        .whisperPanel(padding: 14, radius: 18)
    }

    private var recentCommitsPanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Recent Commits", systemImage: "text.append")
                .font(.caption.bold())
                .foregroundStyle(.secondary)

            ForEach(gitSnapshot?.recentCommits ?? [], id: \.self) { commit in
                HStack(alignment: .top, spacing: 10) {
                    Text(commit.shortSHA)
                        .font(.system(.caption, design: .monospaced).weight(.semibold))
                        .foregroundStyle(WhisperTheme.accent)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 5)
                        .background(WhisperTheme.accentSoft, in: Capsule())

                    VStack(alignment: .leading, spacing: 2) {
                        Text(commit.message)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(WhisperTheme.ink)
                        Text(commit.relativeDate)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()
                }
                .padding(.vertical, 2)
            }
        }
        .whisperPanel(padding: 14, radius: 18)
    }

    private var hasWorkspaceSummary: Bool {
        workspacePath != nil || workspaceSize != nil || (gitSnapshot?.isDirty == true && suggestedCommitMessage != nil)
    }

    private var hasRecentCommits: Bool {
        !(gitSnapshot?.recentCommits.isEmpty ?? true)
    }

    private func gitChip(label: String, value: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label.uppercased())
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.caption.weight(.semibold))
                .foregroundStyle(color)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(color.opacity(0.1), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private func infoRow(label: String, value: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text(label.uppercased())
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(width: 92, alignment: .leading)

            Text(value)
                .font(.caption.weight(.medium))
                .foregroundStyle(WhisperTheme.ink)

            Spacer(minLength: 0)
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

    private var pushActionRow: some View {
        gitActionRow(
            icon: pushIcon,
            label: pushLabel,
            subtitle: pushSubtitle,
            color: pushDisabledReason == nil ? .blue : .secondary,
            isRunning: gitActionState.isRunning,
            isBlocked: pushDisabledReason != nil,
            action: onPush
        )
    }

    private var removeLocalActionRow: some View {
        gitActionRow(
            icon: "trash",
            label: removeLocalLabel,
            subtitle: removeLocalSubtitle,
            color: removalDisabledReason == nil ? .red : .secondary,
            isRunning: gitActionState.isRunning,
            isBlocked: removalDisabledReason != nil,
            action: onRemoveLocal
        )
    }

    private func gitActionRow(
        icon: String,
        label: String,
        subtitle: String,
        color: Color,
        isRunning: Bool,
        isBlocked: Bool,
        action: @escaping () -> Void
    ) -> some View {
        HStack(spacing: 16) {
            Image(systemName: icon)
                .foregroundStyle(color)
                .font(.system(size: 20))
                .frame(width: 36)

            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(color)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            Spacer()

            if isRunning {
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
        .opacity(isBlocked ? 0.7 : 1)
        .onTapGesture {
            if !isRunning {
                action()
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

    private var pushIcon: String {
        switch gitActionState {
        case .running(.push): return "arrow.up.circle"
        case .success(.push, _): return "checkmark.circle.fill"
        case .failed(.push, _): return "exclamationmark.triangle"
        case .idle: return "arrow.up.circle"
        case .running(.removeLocal), .success(.removeLocal, _), .failed(.removeLocal, _):
            return "arrow.up.circle"
        }
    }

    private var pushLabel: String {
        switch gitActionState {
        case .running(.push): return "Pushing to Remote..."
        case .success(.push, _): return "Push Complete"
        case .failed(.push, _): return "Push Failed"
        case .idle: return "Push to Remote"
        case .running(.removeLocal), .success(.removeLocal, _), .failed(.removeLocal, _):
            return "Push to Remote"
        }
    }

    private var removeLocalLabel: String {
        switch gitActionState {
        case .running(.removeLocal): return "Updating and Removing..."
        case .success(.removeLocal, _): return "Folder Removed"
        case .failed(.removeLocal, _): return "Remove Failed"
        case .idle, .running(.push), .success(.push, _), .failed(.push, _):
            return "Remove Local Copy"
        }
    }

    private var pushSubtitle: String {
        if let pushDisabledReason { return pushDisabledReason }
        guard let gitSnapshot else { return "Pushes this branch to its upstream remote." }
        if gitSnapshot.isDirty {
            return "Commits \(gitSnapshot.changedFileCount) changed file\(gitSnapshot.changedFileCount == 1 ? "" : "s"), then pushes."
        }
        if let ahead = gitSnapshot.aheadCount, ahead > 0 {
            return "Pushes \(ahead) local commit\(ahead == 1 ? "" : "s") to upstream."
        }
        return "Checks the upstream and pushes the current branch."
    }

    private var removeLocalSubtitle: String {
        if let removalDisabledReason { return removalDisabledReason }
        guard let gitSnapshot else {
            return "Updates upstream, archives matching Codex threads, then moves this folder to Trash."
        }
        if gitSnapshot.isDirty {
            return "Prompts for a commit, syncs upstream, archives matching Codex threads, then moves this folder to Trash."
        }
        if let ahead = gitSnapshot.aheadCount, ahead > 0 {
            return "Pushes \(ahead) local commit\(ahead == 1 ? "" : "s"), archives matching Codex threads, then moves this folder to Trash."
        }
        if let behind = gitSnapshot.behindCount, behind > 0 {
            return "Fast-forward pulls \(behind) upstream commit\(behind == 1 ? "" : "s"), archives matching Codex threads, then moves this folder to Trash."
        }
        return "Archives matching Codex threads, then moves this up-to-date folder to Trash."
    }

    private var gitActionOutput: String? {
        switch gitActionState {
        case .success(_, let output), .failed(_, let output):
            return output
        case .idle, .running:
            return nil
        }
    }

    private func countLabel(_ count: Int?) -> String {
        count.map(String.init) ?? "-"
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
