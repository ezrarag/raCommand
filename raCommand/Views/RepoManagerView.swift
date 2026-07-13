//
//  RepoManagerView.swift
//  raCommand
//
//  Linear-dark repo manager shell using the existing GitHub/local workspace actions.
//

import Foundation
import SwiftData
import SwiftUI

struct RepoWithLocalState: Identifiable, Hashable {
    let repo: GitHubRepo
    let localPath: String?

    var isClonedLocally: Bool { localPath != nil }
    var id: Int { repo.id }
}

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

struct RepoManagerView: View {
    @Environment(\.modelContext) private var context
    @Query private var projects: [Project]

    @State private var repos: [RepoWithLocalState] = []
    @State private var selectedRepo: RepoWithLocalState?
    @State private var isLoading = false
    @State private var loadStage = "Fetching repos from GitHub…"
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
        case notCloned = "Remote"
    }

    private var filteredRepos: [RepoWithLocalState] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        return repos
            .filter { item in
                guard !query.isEmpty else { return true }
                return item.repo.name.localizedCaseInsensitiveContains(query) ||
                    (item.repo.description ?? "").localizedCaseInsensitiveContains(query)
            }
            .filter { item in
                switch filterMode {
                case .all:
                    return true
                case .cloned:
                    return item.isClonedLocally
                case .notCloned:
                    return !item.isClonedLocally
                }
            }
            .sorted { lhs, rhs in
                if lhs.isClonedLocally != rhs.isClonedLocally {
                    return lhs.isClonedLocally
                }
                return lhs.repo.name.localizedCaseInsensitiveCompare(rhs.repo.name) == .orderedAscending
            }
    }

    private var repoStats: String {
        "\(repos.count) repos · \(repos.filter(\.isClonedLocally).count) local"
    }

    var body: some View {
        HStack(spacing: 0) {
            repoListPane
            repoDetailPane
        }
        .background(Color.clear)
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
            if repos.isEmpty {
                await loadRepos()
            }
        }
    }

    private var repoListPane: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Repos")
                            .font(.system(size: 20, weight: .bold))
                            .foregroundStyle(Color(red: 0.941, green: 0.949, blue: 0.961))
                        Text(repoStats)
                            .font(.system(size: 12))
                            .foregroundStyle(Color(red: 0.541, green: 0.561, blue: 0.596))
                    }

                    Spacer(minLength: 12)

                    Button {
                        Task { await loadRepos() }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(Color(red: 0.541, green: 0.561, blue: 0.596))
                            .frame(width: 24, height: 24)
                    }
                    .buttonStyle(.plain)
                    .disabled(isLoading)
                }

                repoSearchField

                HStack(spacing: 6) {
                    ForEach(FilterMode.allCases, id: \.self) { mode in
                        repoFilterChip(for: mode)
                    }
                }
            }
            .padding(.top, 20)
            .padding(.horizontal, 18)
            .padding(.bottom, 14)

            Group {
                if isLoading && repos.isEmpty {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 10) {
                            HStack(spacing: 8) {
                                ProgressView()
                                    .controlSize(.small)
                                    .tint(WhisperTheme.accent)
                                Text(loadStage)
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundStyle(Color(red: 0.541, green: 0.561, blue: 0.596))
                            }
                            .padding(.bottom, 4)

                            VStack(spacing: 2) {
                                ForEach(Array(repoSkeletonWidths.enumerated()), id: \.offset) { _, width in
                                    RepoSkeletonRow(nameWidth: width)
                                }
                            }
                        }
                        .padding(.horizontal, 10)
                        .padding(.top, 4)
                        .padding(.bottom, 12)
                    }
                } else if filteredRepos.isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        Text(repos.isEmpty ? "No repos loaded" : "No repos match this filter")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(WhisperTheme.ink)
                        Text(repos.isEmpty ? "Connect GitHub import to populate this list." : "Try another search or switch the Local/Remote filter.")
                            .font(.system(size: 12))
                            .foregroundStyle(WhisperTheme.mutedInk)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .padding(.horizontal, 18)
                    .padding(.top, 10)
                } else {
                    ScrollView {
                        LazyVStack(spacing: 2) {
                            ForEach(filteredRepos) { item in
                                RepoListRow(
                                    item: item,
                                    isSelected: selectedRepo?.id == item.id,
                                    statusLabel: repoRowStatus(item),
                                    secondaryLabel: repoRowSecondary(item)
                                ) {
                                    selectedRepo = item
                                }
                            }
                        }
                        .padding(.horizontal, 10)
                        .padding(.bottom, 12)
                    }
                }
            }
        }
        .frame(width: 340)
        .background(Color.clear)
        .overlay(alignment: .trailing) {
            Rectangle()
                .fill(Color.white.opacity(0.06))
                .frame(width: 1)
        }
    }

    private var repoDetailPane: some View {
        ScrollView {
            Group {
                if let selectedRepo {
                    RepoWorkbenchView(
                        item: selectedRepo,
                        description: selectedRepo.repo.description,
                        statusText: repoStatusBadgeText(for: selectedRepo),
                        statusColor: repoStatusColor(for: selectedRepo),
                        statusBackground: repoStatusBackground(for: selectedRepo),
                        branchValue: repoBranchValue(for: selectedRepo),
                        sizeValue: repoSizeValue(for: selectedRepo),
                        lastSyncValue: repoLastSyncValue(for: selectedRepo),
                        details: detailRows(for: selectedRepo),
                        cloneOutput: cloneOutput[selectedRepo.repo.id] ?? "",
                        gitActionOutput: gitActionOutput(for: selectedRepo),
                        cloneButton: cloneButtonConfiguration(for: selectedRepo),
                        codexButton: codexButtonConfiguration(for: selectedRepo),
                        pushButton: pushButtonConfiguration(for: selectedRepo),
                        removeButton: removeButtonConfiguration(for: selectedRepo),
                        onClone: { Task { await cloneRepo(selectedRepo) } },
                        onOpenCodex: { Task { await openInCodex(selectedRepo) } },
                        onPush: { requestPush(selectedRepo) },
                        onRemove: { requestLocalRemoval(selectedRepo) },
                        onOpenGitHub: {
                            if let url = URL(string: selectedRepo.repo.htmlURL) {
                                PlatformSystemServices.open(url)
                            }
                        },
                        onTrackOnly: {
                            if !isTracked(selectedRepo) {
                                trackAsProject(selectedRepo)
                            }
                        }
                    )
                } else {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Select a repo")
                            .font(.system(size: 19, weight: .bold))
                            .foregroundStyle(Color(red: 0.941, green: 0.949, blue: 0.961))
                        Text("Use the left pane to inspect local mirrors, open a Codex workspace, or push and remove safely.")
                            .font(.system(size: 12))
                            .foregroundStyle(Color(red: 0.541, green: 0.561, blue: 0.596))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(32)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var repoSearchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Color(red: 0.361, green: 0.380, blue: 0.416))

            TextField("Search repos…", text: $searchText)
                .textFieldStyle(.plain)
                .font(.system(size: 12))
                .foregroundStyle(WhisperTheme.ink)
        }
        .padding(.horizontal, 10)
        .frame(height: 32)
        .background(Color(red: 0.075, green: 0.078, blue: 0.090), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(Color.white.opacity(0.10), lineWidth: 1)
        )
    }

    private func repoFilterChip(for mode: FilterMode) -> some View {
        let isSelected = filterMode == mode

        return Button {
            filterMode = mode
        } label: {
            Text(mode.rawValue)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(isSelected ? Color(red: 0.498, green: 0.690, blue: 1.000) : Color(red: 0.541, green: 0.561, blue: 0.596))
                .padding(.horizontal, 10)
                .frame(height: 24)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(isSelected ? WhisperTheme.accent.opacity(0.12) : .clear)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .stroke(isSelected ? WhisperTheme.accent.opacity(0.40) : Color.white.opacity(0.08), lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
    }

    private var removalConfirmationMessage: String {
        guard let item = pendingRemovalRepo,
              let path = resolvedWorkspacePath(for: item) else {
            return "raCommand will move this local workspace to Trash."
        }
        return "raCommand will update this local workspace to its newest upstream version, archive matching Codex threads, then move the folder to Trash:\n\(path)"
    }

    private func repoRowStatus(_ item: RepoWithLocalState) -> String {
        if let gitAction = compactGitActionLabel(for: item) {
            return gitAction
        }
        if item.isClonedLocally {
            if let snapshot = gitSnapshots[item.repo.id] {
                if snapshot.changedFileCount > 0 {
                    return "Dirty"
                }
                if let ahead = snapshot.aheadCount, ahead > 0 {
                    return "Ahead \(ahead)"
                }
                if let behind = snapshot.behindCount, behind > 0 {
                    return "Behind \(behind)"
                }
            }
            return "Local"
        }
        return "Remote"
    }

    private func repoRowSecondary(_ item: RepoWithLocalState) -> String {
        if item.isClonedLocally, let workspaceSize = workspaceSizes[item.repo.id] {
            return ByteCountFormatter.string(fromByteCount: workspaceSize, countStyle: .file)
        }
        if let snapshot = gitSnapshots[item.repo.id], !snapshot.branch.isEmpty {
            return snapshot.branch
        }
        return item.repo.description?.isEmpty == false ? item.repo.description! : "GitHub"
    }

    private func repoStatusBadgeText(for item: RepoWithLocalState) -> String {
        if let snapshot = gitSnapshots[item.repo.id], snapshot.changedFileCount > 0 {
            return "Pending"
        }
        if let gitStatusErrors = gitStatusErrors[item.repo.id], !gitStatusErrors.isEmpty {
            return "Needs Attention"
        }
        return item.isClonedLocally ? "Synced" : "Remote"
    }

    private func repoStatusColor(for item: RepoWithLocalState) -> Color {
        if let snapshot = gitSnapshots[item.repo.id], snapshot.changedFileCount > 0 {
            return WhisperTheme.warning
        }
        if let gitStatusErrors = gitStatusErrors[item.repo.id], !gitStatusErrors.isEmpty {
            return WhisperTheme.danger
        }
        return item.isClonedLocally ? WhisperTheme.success : WhisperTheme.info
    }

    private func repoStatusBackground(for item: RepoWithLocalState) -> Color {
        repoStatusColor(for: item).opacity(0.14)
    }

    private func repoBranchValue(for item: RepoWithLocalState) -> String {
        gitSnapshots[item.repo.id]?.branch ?? (item.isClonedLocally ? "local" : "remote")
    }

    private func repoSizeValue(for item: RepoWithLocalState) -> String {
        guard let workspaceSize = workspaceSizes[item.repo.id] else { return item.isClonedLocally ? "Unknown" : "Not cloned" }
        return ByteCountFormatter.string(fromByteCount: workspaceSize, countStyle: .file)
    }

    private func repoLastSyncValue(for item: RepoWithLocalState) -> String {
        guard let commit = gitSnapshots[item.repo.id]?.recentCommits.first else {
            return item.isClonedLocally ? "Local" : "GitHub"
        }
        return commit.relativeDate
    }

    private func compactGitActionLabel(for item: RepoWithLocalState) -> String? {
        switch gitActionStates[item.repo.id] ?? .idle {
        case .running(.push):
            return "Pushing"
        case .running(.removeLocal):
            return "Removing"
        case .success(.push, _):
            return "Pushed"
        case .success(.removeLocal, _):
            return "Removed"
        case .failed(.push, _), .failed(.removeLocal, _):
            return "Error"
        case .idle:
            return nil
        }
    }

    private func detailRows(for item: RepoWithLocalState) -> [(String, String)] {
        var rows: [(String, String)] = []

        if let path = resolvedWorkspacePath(for: item), !path.isEmpty {
            rows.append(("Workspace", path))
        }

        if let origin = gitSnapshots[item.repo.id]?.originURL, !origin.isEmpty {
            rows.append(("Origin", origin))
        }

        if let snapshot = gitSnapshots[item.repo.id] {
            rows.append(("Changes", "\(snapshot.changedFileCount) files"))
            rows.append(("Staged", "\(snapshot.stagedCount)"))
            rows.append(("Unstaged", "\(snapshot.unstagedCount)"))
            rows.append(("Untracked", "\(snapshot.untrackedCount)"))

            if let ahead = snapshot.aheadCount {
                rows.append(("Ahead", "\(ahead)"))
            }

            if let behind = snapshot.behindCount {
                rows.append(("Behind", "\(behind)"))
            }

            if let commit = snapshot.recentCommits.first {
                rows.append(("Latest", "\(commit.shortSHA) \(commit.message)"))
            }
        } else if let error = gitStatusErrors[item.repo.id], !error.isEmpty {
            rows.append(("Git", error))
        }

        if hasCodexThread(for: item) {
            rows.append(("Codex", "Existing thread detected"))
        } else if project(for: item.repo)?.isActiveThread == true {
            rows.append(("Codex", "Marked as active thread"))
        }

        if isTracked(item) {
            rows.append(("Projects", "Tracked in raCommand"))
        }

        return rows
    }

    private func cloneButtonConfiguration(for item: RepoWithLocalState) -> RepoActionButtonConfiguration {
        let cloneState = cloneStates[item.repo.id] ?? .idle
        switch cloneState {
        case .idle:
            return RepoActionButtonConfiguration(
                title: item.isClonedLocally ? "Local Ready" : "Clone",
                tone: .secondary,
                disabled: item.isClonedLocally
            )
        case .cloning:
            return RepoActionButtonConfiguration(title: "Cloning…", tone: .secondary, disabled: true)
        case .success:
            return RepoActionButtonConfiguration(title: "Cloned", tone: .secondary, disabled: true)
        case .failed:
            return RepoActionButtonConfiguration(title: "Retry Clone", tone: .secondary, disabled: false)
        }
    }

    private func codexButtonConfiguration(for item: RepoWithLocalState) -> RepoActionButtonConfiguration {
        RepoActionButtonConfiguration(
            title: codexOpeningRepoID == item.repo.id ? "Opening…" : "Open in Codex",
            tone: .primary,
            disabled: codexOpeningRepoID == item.repo.id
        )
    }

    private func pushButtonConfiguration(for item: RepoWithLocalState) -> RepoActionButtonConfiguration {
        RepoActionButtonConfiguration(
            title: pushButtonTitle(for: item),
            tone: .secondary,
            disabled: pushDisabledReason(for: item) != nil || gitActionStates[item.repo.id]?.isRunning == true
        )
    }

    private func removeButtonConfiguration(for item: RepoWithLocalState) -> RepoActionButtonConfiguration {
        RepoActionButtonConfiguration(
            title: removeButtonTitle(for: item),
            tone: .danger,
            disabled: removalDisabledReason(for: item) != nil || gitActionStates[item.repo.id]?.isRunning == true
        )
    }

    private func pushButtonTitle(for item: RepoWithLocalState) -> String {
        switch gitActionStates[item.repo.id] ?? .idle {
        case .running(.push):
            return "Pushing…"
        case .success(.push, _):
            return "Pushed"
        case .failed(.push, _):
            return "Retry Push"
        default:
            return "Push"
        }
    }

    private func removeButtonTitle(for item: RepoWithLocalState) -> String {
        switch gitActionStates[item.repo.id] ?? .idle {
        case .running(.removeLocal):
            return "Removing…"
        case .success(.removeLocal, _):
            return "Removed"
        case .failed(.removeLocal, _):
            return "Retry Remove"
        default:
            return "Remove"
        }
    }

    private func gitActionOutput(for item: RepoWithLocalState) -> String {
        switch gitActionStates[item.repo.id] ?? .idle {
        case .success(_, let output), .failed(_, let output):
            return output
        case .idle, .running:
            return ""
        }
    }

    private func loadRepos() async {
        guard let token = KeychainService.loadGitHubToken(), !token.isEmpty else {
            showTokenAlert = true
            return
        }

        isLoading = true
        loadStage = "Fetching repos from GitHub…"
        defer { isLoading = false }

        do {
            let fetched = try await GitHubService.fetchRepos(token: token)

            loadStage = "Checking local clones…"
            let devPath = localDevPath
            let activeCodexPaths = await Task.detached(priority: .userInitiated) {
                LocalWorkspaceService.activeCodexWorkspacePaths(rootPathPrefix: devPath)
            }.value
            let nextRepos = fetched
                .map { repo in
                    RepoWithLocalState(repo: repo, localPath: detectedLocalWorkspacePath(for: repo))
                }
                .sorted { lhs, rhs in
                    if lhs.isClonedLocally != rhs.isClonedLocally {
                        return lhs.isClonedLocally
                    }
                    return lhs.repo.name.localizedCaseInsensitiveCompare(rhs.repo.name) == .orderedAscending
                }

            repos = nextRepos
            codexWorkspacePaths = activeCodexPaths

            if let current = selectedRepo,
               let updated = nextRepos.first(where: { $0.id == current.id }) {
                selectedRepo = updated
            } else {
                selectedRepo = nextRepos.first
            }

            loadStage = "Reading git status…"
            await refreshGitSnapshots()
        } catch {
            workspaceActionError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
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

    private func cloneRepo(_ item: RepoWithLocalState) async {
        cloneStates[item.repo.id] = .cloning
        cloneOutput[item.repo.id] = ""

        let destination = "\(localDevPath)/\(item.repo.name)"
        if FileManager.default.fileExists(atPath: destination) {
            cloneStates[item.repo.id] = .success
            cloneOutput[item.repo.id] = "Already exists at local dev."
            await loadRepos()
            return
        }

        #if os(macOS)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = ["clone", item.repo.htmlURL, destination]

        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr

        do {
            try process.run()
            process.waitUntilExit()

            let outputData = stdout.fileHandleForReading.readDataToEndOfFile()
            let errorData = stderr.fileHandleForReading.readDataToEndOfFile()
            let output = String(data: outputData, encoding: .utf8) ?? ""
            let errorOutput = String(data: errorData, encoding: .utf8) ?? ""
            let combined = [output, errorOutput].filter { !$0.isEmpty }.joined(separator: "\n")

            await MainActor.run {
                cloneOutput[item.repo.id] = combined.isEmpty ? "Clone complete." : combined
                if process.terminationStatus == 0 {
                    cloneStates[item.repo.id] = .success
                    attachLocalWorkspace(destination, to: item.repo)
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
            cloneOutput[item.repo.id] = "Run `git clone \(item.repo.htmlURL) \\\"\(destination)\\\"` from Terminal instead."
        }
        #endif
    }

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
            await refreshGitSnapshot(for: item)
        } catch {
            let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            gitActionStates[item.repo.id] = .failed(.push, message)
            workspaceActionError = message
            await refreshGitSnapshot(for: item)
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
            await refreshGitSnapshot(for: item)
        }
    }

    /// Scans every cloned repo's disk size and git status. Each repo means a
    /// recursive filesystem walk plus ~5 `git` subprocess spawns, so this
    /// always runs off the main thread via Task.detached — doing this
    /// synchronously on the main actor is what causes the spinning-beachball
    /// cursor after a load or refresh (the run loop can't process events
    /// while blocked on dozens of subprocess waits).
    private func refreshGitSnapshots() async {
        let targets: [(id: Int, path: String?)] = repos
            .filter { $0.isClonedLocally }
            .map { ($0.repo.id, resolvedWorkspacePath(for: $0)) }

        // Each repo's scan is independent (its own subprocess, its own
        // filesystem subtree), so run them concurrently rather than one at
        // a time — with 22 local repos, sequential scanning multiplies
        // subprocess-spawn latency by 22 for no reason.
        let result = await Task.detached(priority: .userInitiated) { () -> ([Int: LocalGitSnapshot], [Int: String], [Int: Int64]) in
            await withTaskGroup(of: (Int, Int64?, LocalGitSnapshot?, String?).self) { group in
                for (id, path) in targets {
                    group.addTask {
                        guard let path else {
                            return (id, nil, nil, "The local workspace path could not be resolved.")
                        }
                        let size = await LocalWorkspaceService.directorySizeCached(at: path)
                        do {
                            let snapshot = try LocalGitCommandService.status(at: path)
                            return (id, size, snapshot, nil)
                        } catch {
                            let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                            return (id, size, nil, message)
                        }
                    }
                }

                var nextSnapshots: [Int: LocalGitSnapshot] = [:]
                var nextErrors: [Int: String] = [:]
                var nextSizes: [Int: Int64] = [:]

                for await (id, size, snapshot, error) in group {
                    if let size { nextSizes[id] = size }
                    if let snapshot { nextSnapshots[id] = snapshot }
                    if let error { nextErrors[id] = error }
                }

                return (nextSnapshots, nextErrors, nextSizes)
            }
        }.value

        gitSnapshots = result.0
        gitStatusErrors = result.1
        workspaceSizes = result.2
    }

    private func refreshGitSnapshot(for item: RepoWithLocalState) async {
        guard item.isClonedLocally, let path = resolvedWorkspacePath(for: item) else {
            gitSnapshots[item.repo.id] = nil
            gitStatusErrors[item.repo.id] = nil
            workspaceSizes[item.repo.id] = nil
            return
        }

        // Always recompute fresh here (not the cached variant) — this runs
        // right after a push/remove specifically to reflect what just
        // changed, so serving a stale cached size would defeat the point.
        let result = await Task.detached(priority: .userInitiated) { () -> (Int64?, LocalGitSnapshot?, String?) in
            let size = LocalWorkspaceService.directorySize(at: path)
            do {
                let snapshot = try LocalGitCommandService.status(at: path)
                return (size, snapshot, nil)
            } catch {
                return (size, nil, (error as? LocalizedError)?.errorDescription ?? error.localizedDescription)
            }
        }.value

        if let freshSize = result.0 {
            await DirectorySizeCache.shared.store(freshSize, at: LocalWorkspaceService.normalizedWorkspacePath(path))
        } else {
            await DirectorySizeCache.shared.invalidate(LocalWorkspaceService.normalizedWorkspacePath(path))
        }

        workspaceSizes[item.repo.id] = result.0
        gitSnapshots[item.repo.id] = result.1
        gitStatusErrors[item.repo.id] = result.2
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

private let repoSkeletonWidths: [CGFloat] = [150, 110, 175, 130, 95, 160, 120, 145, 105, 165]

private struct RepoSkeletonRow: View {
    let nameWidth: CGFloat
    @State private var isPulsing = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Circle()
                    .fill(WhisperTheme.mutedInk.opacity(0.25))
                    .frame(width: 6, height: 6)

                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(WhisperTheme.mutedInk.opacity(0.18))
                    .frame(width: nameWidth, height: 12)

                Spacer(minLength: 0)
            }

            RoundedRectangle(cornerRadius: 3, style: .continuous)
                .fill(WhisperTheme.mutedInk.opacity(0.12))
                .frame(width: 100, height: 9)
                .padding(.leading, 14)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color(red: 0.075, green: 0.078, blue: 0.090))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(Color.white.opacity(0.05), lineWidth: 1)
        )
        .opacity(isPulsing ? 1.0 : 0.45)
        .onAppear {
            withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) {
                isPulsing = true
            }
        }
    }
}

private struct RepoListRow: View {
    let item: RepoWithLocalState
    let isSelected: Bool
    let statusLabel: String
    let secondaryLabel: String
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Circle()
                        .fill(item.isClonedLocally ? WhisperTheme.success : WhisperTheme.info)
                        .frame(width: 6, height: 6)

                    Text(item.repo.name)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(WhisperTheme.ink)
                        .lineLimit(1)

                    Spacer(minLength: 0)
                }

                HStack(spacing: 8) {
                    Text(statusLabel.uppercased())
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .foregroundStyle(Color(red: 0.361, green: 0.380, blue: 0.416))
                    Circle()
                        .fill(Color(red: 0.247, green: 0.263, blue: 0.290))
                        .frame(width: 2, height: 2)
                    Text(secondaryLabel)
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .foregroundStyle(Color(red: 0.361, green: 0.380, blue: 0.416))
                        .lineLimit(1)
                }
                .padding(.leading, 14)
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(isSelected ? WhisperTheme.accent.opacity(0.08) : Color(red: 0.075, green: 0.078, blue: 0.090))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(isSelected ? WhisperTheme.accent.opacity(0.35) : Color.white.opacity(0.05), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}

private struct RepoActionButtonConfiguration {
    enum Tone {
        case primary
        case secondary
        case danger
    }

    let title: String
    let tone: Tone
    let disabled: Bool
}

private struct RepoWorkbenchView: View {
    let item: RepoWithLocalState
    let description: String?
    let statusText: String
    let statusColor: Color
    let statusBackground: Color
    let branchValue: String
    let sizeValue: String
    let lastSyncValue: String
    let details: [(String, String)]
    let cloneOutput: String
    let gitActionOutput: String
    let cloneButton: RepoActionButtonConfiguration
    let codexButton: RepoActionButtonConfiguration
    let pushButton: RepoActionButtonConfiguration
    let removeButton: RepoActionButtonConfiguration
    let onClone: () -> Void
    let onOpenCodex: () -> Void
    let onPush: () -> Void
    let onRemove: () -> Void
    let onOpenGitHub: () -> Void
    let onTrackOnly: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            HStack(alignment: .top, spacing: 16) {
                VStack(alignment: .leading, spacing: 5) {
                    Text(item.repo.name)
                        .font(.system(size: 19, weight: .bold))
                        .foregroundStyle(Color(red: 0.941, green: 0.949, blue: 0.961))

                    Text(item.repo.htmlURL)
                        .font(.system(size: 12, weight: .medium, design: .monospaced))
                        .foregroundStyle(Color(red: 0.361, green: 0.380, blue: 0.416))
                        .textSelection(.enabled)

                    if let description, !description.isEmpty {
                        Text(description)
                            .font(.system(size: 12))
                            .foregroundStyle(Color(red: 0.541, green: 0.561, blue: 0.596))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                Spacer(minLength: 0)

                Text(statusText)
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .foregroundStyle(statusColor)
                    .padding(.horizontal, 9)
                    .frame(height: 22)
                    .background(statusBackground, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
            }

            HStack(spacing: 10) {
                RepoStatCard(label: "BRANCH", value: branchValue)
                RepoStatCard(label: "SIZE", value: sizeValue)
                RepoStatCard(label: "LAST SYNC", value: lastSyncValue)
            }

            Rectangle()
                .fill(Color.white.opacity(0.06))
                .frame(height: 1)

            VStack(alignment: .leading, spacing: 8) {
                Text("ACTIONS")
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .foregroundStyle(Color(red: 0.541, green: 0.561, blue: 0.596))

                HStack(spacing: 8) {
                    repoActionButton(codexButton, action: onOpenCodex)
                    repoActionButton(pushButton, action: onPush)
                    repoActionButton(removeButton, action: onRemove)
                }

                HStack(spacing: 8) {
                    repoActionButton(cloneButton, action: onClone)
                    repoActionButton(
                        RepoActionButtonConfiguration(title: "GitHub", tone: .secondary, disabled: false),
                        action: onOpenGitHub
                    )
                    repoActionButton(
                        RepoActionButtonConfiguration(title: "Track Only", tone: .secondary, disabled: false),
                        action: onTrackOnly
                    )
                }
            }

            if !details.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    Text("DETAILS")
                        .font(.system(size: 11, weight: .semibold, design: .monospaced))
                        .foregroundStyle(Color(red: 0.541, green: 0.561, blue: 0.596))

                    ForEach(Array(details.enumerated()), id: \.offset) { _, detail in
                        HStack(alignment: .top, spacing: 14) {
                            Text(detail.0.uppercased())
                                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                                .foregroundStyle(Color(red: 0.361, green: 0.380, blue: 0.416))
                                .frame(width: 70, alignment: .leading)

                            Text(detail.1)
                                .font(.system(size: 12))
                                .foregroundStyle(WhisperTheme.ink)
                                .textSelection(.enabled)
                                .fixedSize(horizontal: false, vertical: true)

                            Spacer(minLength: 0)
                        }
                    }
                }
            }

            if !cloneOutput.isEmpty {
                RepoOutputPanel(title: "CLONE OUTPUT", text: cloneOutput)
            }

            if !gitActionOutput.isEmpty {
                RepoOutputPanel(title: "GIT ACTION", text: gitActionOutput)
            }
        }
        .padding(32)
        .frame(maxWidth: 640, alignment: .leading)
    }

    private func repoActionButton(_ configuration: RepoActionButtonConfiguration, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(configuration.title)
                .font(.system(size: 13, weight: configuration.tone == .primary ? .semibold : .medium))
                .foregroundStyle(foregroundColor(for: configuration))
                .frame(maxWidth: configuration.tone == .danger ? nil : .infinity)
                .frame(height: 34)
                .padding(.horizontal, configuration.tone == .danger ? 14 : 12)
                .background(background(for: configuration), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(border(for: configuration), lineWidth: configuration.tone == .primary ? 0 : 1)
                )
        }
        .buttonStyle(.plain)
        .disabled(configuration.disabled)
        .opacity(configuration.disabled ? 0.55 : 1)
    }

    private func foregroundColor(for configuration: RepoActionButtonConfiguration) -> Color {
        switch configuration.tone {
        case .primary:
            return .white
        case .secondary:
            return WhisperTheme.ink
        case .danger:
            return WhisperTheme.danger
        }
    }

    private func background(for configuration: RepoActionButtonConfiguration) -> Color {
        switch configuration.tone {
        case .primary:
            return WhisperTheme.accent
        case .secondary:
            return Color.white.opacity(0.04)
        case .danger:
            return WhisperTheme.danger.opacity(0.06)
        }
    }

    private func border(for configuration: RepoActionButtonConfiguration) -> Color {
        switch configuration.tone {
        case .primary:
            return .clear
        case .secondary:
            return Color.white.opacity(0.12)
        case .danger:
            return WhisperTheme.danger.opacity(0.25)
        }
    }
}

private struct RepoStatCard: View {
    let label: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                .foregroundStyle(Color(red: 0.361, green: 0.380, blue: 0.416))
            Text(value)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(WhisperTheme.ink)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(Color(red: 0.075, green: 0.078, blue: 0.090), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .stroke(Color.white.opacity(0.06), lineWidth: 1)
        )
    }
}

private struct RepoOutputPanel: View {
    let title: String
    let text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .foregroundStyle(Color(red: 0.541, green: 0.561, blue: 0.596))
            Text(text)
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .foregroundStyle(WhisperTheme.ink)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
                .background(Color(red: 0.075, green: 0.078, blue: 0.090), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .stroke(Color.white.opacity(0.06), lineWidth: 1)
                )
        }
    }
}
