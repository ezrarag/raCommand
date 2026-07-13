//
//  ProjectDetailView.swift
//  raCommand
//
//  Workbench-style project detail for the shell MVP.
//

import SwiftUI

enum ProjectDetailWorkbenchTab: String, CaseIterable, Identifiable {
    case notes
    case clientNotes
    case people
    case repos

    var id: String { rawValue }

    var title: String {
        switch self {
        case .notes: return "Notes"
        case .clientNotes: return "Client Notes"
        case .people: return "Team"
        case .repos: return "Repos"
        }
    }
}

struct ProjectDetailView: View {
    @Environment(\.modelContext) private var modelContext
    @Bindable var project: Project
    @Binding var detailTab: ProjectDetailWorkbenchTab
    let onBack: () -> Void

    @State private var showCreateRepoSheet = false
    @State private var activeLaunchTarget: LaunchTarget = .codex
    @State private var isOpeningCodex = false
    @State private var workspaceMessage: String?
    @State private var workspaceError: String?

    private var syncStatusTitle: String {
        switch project.workspaceSyncStatus ?? .local {
        case .local: return "Not yet synced"
        case .pending: return "Syncing…"
        case .synced: return "Synced to admin"
        case .error: return "Sync failed"
        }
    }

    private var syncStatusBadgeText: String {
        switch project.workspaceSyncStatus ?? .local {
        case .local: return "Local only"
        case .pending: return "Pending"
        case .synced: return project.remoteWorkspaceId ?? "Synced"
        case .error: return "Error"
        }
    }

    private var syncStatusBadgeColor: Color {
        switch project.workspaceSyncStatus ?? .local {
        case .local: return WhisperTheme.mutedInk
        case .pending: return WhisperTheme.warning
        case .synced: return WhisperTheme.success
        case .error: return WhisperTheme.danger
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            header
            tabStrip
            activeContent
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 12) {
            Button(action: onBack) {
                Image(systemName: "arrow.left")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(Color(red: 0.541, green: 0.561, blue: 0.596))
                    .frame(width: 32, height: 32)
                    .background(Color.clear, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 2) {
                Text(displayName)
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(Color(red: 0.941, green: 0.949, blue: 0.961))
                Text("\(clientLine) · \(statusLine)")
                    .font(.system(size: 12))
                    .foregroundStyle(Color(red: 0.541, green: 0.561, blue: 0.596))
            }
        }
    }

    private var tabStrip: some View {
        HStack(spacing: 1) {
            ForEach(ProjectDetailWorkbenchTab.allCases) { tab in
                Button {
                    detailTab = tab
                } label: {
                    VStack(spacing: 0) {
                        Text(tab.title)
                            .font(.system(size: 13, weight: detailTab == tab ? .semibold : .regular))
                            .foregroundStyle(detailTab == tab ? WhisperTheme.ink : Color(red: 0.541, green: 0.561, blue: 0.596))
                            .frame(height: 38)
                            .frame(minWidth: 72)

                        Rectangle()
                            .fill(detailTab == tab ? WhisperTheme.accent : .clear)
                            .frame(height: 2)
                    }
                }
                .buttonStyle(.plain)
            }
        }
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Color.white.opacity(0.06))
                .frame(height: 1)
        }
    }

    @ViewBuilder
    private var activeContent: some View {
        switch detailTab {
        case .notes:
            notesPane
        case .clientNotes:
            ProjectClientNotesView(project: project)
        case .people:
            peoplePane
        case .repos:
            reposPane
        }
    }

    private var notesPane: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("NOTES")
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .foregroundStyle(Color(red: 0.541, green: 0.561, blue: 0.596))

            fieldGrid {
                shellField("Project") {
                    TextField("Project name", text: $project.name)
                        .shellTextField()
                }

                shellField("Client") {
                    TextField("Client or stakeholder", text: $project.clientName)
                        .shellTextField()
                }

                shellField("Status") {
                    Picker("Status", selection: $project.status) {
                        ForEach(ProjectStatus.allCases, id: \.self) { status in
                            Text(status.rawValue.capitalized).tag(status)
                        }
                    }
                    .pickerStyle(.menu)
                    .labelsHidden()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .shellInputChrome()
                }

                shellField("Category") {
                    Picker("Category", selection: $project.category) {
                        ForEach(ProjectCategory.allCases, id: \.self) { category in
                            Text(category.rawValue.capitalized).tag(category)
                        }
                    }
                    .pickerStyle(.menu)
                    .labelsHidden()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .shellInputChrome()
                }

                shellField("Value") {
                    Stepper(value: $project.valueScore, in: 1...10) {
                        Text("Value \(project.valueScore)")
                            .font(.system(size: 13))
                            .foregroundStyle(WhisperTheme.ink)
                    }
                    .shellInputChrome()
                }
            }

            shellField("Next Action") {
                TextField("What needs to happen next?", text: $project.nextAction, axis: .vertical)
                    .lineLimit(2...4)
                    .shellTextField()
            }

            shellField("Notes") {
                TextEditor(text: $project.notes)
                    .scrollContentBackground(.hidden)
                    .frame(minHeight: 220)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 11)
                    .background(WhisperTheme.input, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 9, style: .continuous)
                            .stroke(WhisperTheme.border, lineWidth: 1)
                    )
                    .foregroundStyle(WhisperTheme.ink)
            }
        }
        .frame(maxWidth: 720, alignment: .leading)
    }

    private var peoplePane: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("TEAM")
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .foregroundStyle(Color(red: 0.541, green: 0.561, blue: 0.596))

            VStack(alignment: .leading, spacing: 12) {
                compactCard(
                    title: clientLine,
                    subtitle: "Primary stakeholder",
                    badgeText: project.delegatable ? "Delegatable" : "Owner-led",
                    badgeColor: project.delegatable ? WhisperTheme.success : WhisperTheme.warning
                )

                VStack(alignment: .leading, spacing: 12) {
                    Toggle(isOn: $project.delegatable) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Delegatable")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(WhisperTheme.ink)
                            Text("Marks this work as safe to hand off after context is captured.")
                                .font(.system(size: 12))
                                .foregroundStyle(WhisperTheme.mutedInk)
                        }
                    }
                    .toggleStyle(.switch)

                    HStack(spacing: 12) {
                        Text("Target date")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(WhisperTheme.ink)

                        Spacer(minLength: 8)

                        if let targetDate = Binding($project.targetDate) {
                            DatePicker("Target", selection: targetDate, displayedComponents: .date)
                                .labelsHidden()
                                .datePickerStyle(.compact)

                            Button("Clear") {
                                project.targetDate = nil
                            }
                            .buttonStyle(.plain)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(WhisperTheme.danger)
                        } else {
                            Button("Set date") {
                                project.targetDate = .now
                            }
                            .buttonStyle(.plain)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(WhisperTheme.accent)
                        }
                    }
                }
                .shellInputChrome()
            }
        }
        .frame(maxWidth: 720, alignment: .leading)
    }

    private var reposPane: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("REPOS")
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .foregroundStyle(Color(red: 0.541, green: 0.561, blue: 0.596))

            compactCard(
                title: project.repoURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "No repo linked yet" : project.repoURL,
                subtitle: "Primary repository",
                badgeText: project.isActiveThread ? "Thread active" : "Untracked",
                badgeColor: project.isActiveThread ? WhisperTheme.accent : WhisperTheme.mutedInk
            )

            compactCard(
                title: syncStatusTitle,
                subtitle: "readyaimgo admin workspace",
                badgeText: syncStatusBadgeText,
                badgeColor: syncStatusBadgeColor
            )

            fieldGrid {
                shellField("Repo URL") {
                    TextField("https://github.com/...", text: $project.repoURL)
                        .shellTextField()
                }

                shellField("Workspace") {
                    TextField("/Users/.../local dev/...", text: $project.localPath)
                        .shellTextField()
                }

                shellField("Vercel URL") {
                    TextField("https://...", text: $project.vercelURL)
                        .shellTextField()
                }
            }

            repoActionPanel

            Toggle(isOn: $project.isActiveThread) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Active Codex thread")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(WhisperTheme.ink)
                    Text("Keeps this project prioritized on the board.")
                        .font(.system(size: 12))
                        .foregroundStyle(WhisperTheme.mutedInk)
                }
            }
            .toggleStyle(.switch)
            .shellInputChrome()
            .frame(maxWidth: 720, alignment: .leading)
        }
        .frame(maxWidth: 720, alignment: .leading)
        .sheet(isPresented: $showCreateRepoSheet) {
            CreateProjectRepositorySheet(project: project, target: activeLaunchTarget) { workspacePath in
                if !workspacePath.isEmpty {
                    project.localPath = workspacePath
                    project.isActiveThread = true
                    project.lastUpdated = Date()
                    project.lastReviewed = Date()
                    workspaceMessage = "Repository ready and opened in \(activeLaunchTarget.rawValue)."
                    workspaceError = nil
                }
            }
        }
    }

    private var repoActionPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Menu {
                    ForEach(LaunchTarget.allCases) { target in
                        Button {
                            activeLaunchTarget = target
                            if project.repoURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                showCreateRepoSheet = true
                            } else {
                                Task { await openProject(target: target) }
                            }
                        } label: {
                            Label(openInTargetLabel(for: target), systemImage: systemIcon(for: target))
                        }
                    }
                } label: {
                    HStack(spacing: 8) {
                        if isOpeningCodex {
                            ProgressView()
                                .tint(.white)
                                .scaleEffect(0.8)
                        }
                        Text(openInTargetLabel(for: activeLaunchTarget))
                        Image(systemName: "chevron.down")
                            .font(.system(size: 10, weight: .bold))
                    }
                    .padding(.horizontal, 12)
                    .frame(height: 32)
                    .background(WhisperTheme.accent, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .foregroundStyle(.white)
                }
                .menuStyle(.button)
                .buttonStyle(.plain)
                .disabled(isOpeningCodex)

                if !project.repoURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Button("Create Replacement Repo") {
                        showCreateRepoSheet = true
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(WhisperTheme.mutedInk)
                }
            }

            if let workspaceMessage, !workspaceMessage.isEmpty {
                inlineBanner(message: workspaceMessage, color: WhisperTheme.success, icon: "checkmark.circle.fill", emphasizeInk: true)
            }

            if let workspaceError, !workspaceError.isEmpty {
                inlineBanner(message: workspaceError, color: WhisperTheme.danger, icon: "exclamationmark.triangle.fill", emphasizeInk: false)
            }
        }
        .frame(maxWidth: 720, alignment: .leading)
    }

    private func openInTargetLabel(for target: LaunchTarget) -> String {
        let repoURL = project.repoURL.trimmingCharacters(in: .whitespacesAndNewlines)
        if repoURL.isEmpty {
            return "Create Repo + Open \(target.rawValue)"
        }

        let localPath = LocalWorkspaceService.normalizedWorkspacePath(project.localPath)
        if !localPath.isEmpty, LocalWorkspaceService.workspaceExists(at: localPath) {
            return "Open in \(target.rawValue)"
        }

        return "Clone + Open \(target.rawValue)"
    }

    private func systemIcon(for target: LaunchTarget) -> String {
        switch target {
        case .codex:
            return "terminal"
        case .antigravity:
            return "sparkles"
        case .claude:
            return "message"
        }
    }

    private func inlineBanner(message: String, color: Color, icon: String, emphasizeInk: Bool) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .foregroundStyle(color)
            Text(message)
                .font(.system(size: 12))
                .foregroundStyle(emphasizeInk ? WhisperTheme.ink : color)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(color.opacity(0.08), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .stroke(color.opacity(0.22), lineWidth: 1)
        )
    }

    @MainActor
    private func openProject(target: LaunchTarget) async {
        let repoURL = project.repoURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !repoURL.isEmpty else {
            workspaceError = "Add or create a GitHub repository first."
            workspaceMessage = nil
            return
        }

        isOpeningCodex = true
        workspaceError = nil
        workspaceMessage = nil
        defer { isOpeningCodex = false }

        do {
            let suggestedPath = LocalWorkspaceService.suggestedLocalPath(for: repoURL)
            let preferredPath = LocalWorkspaceService.normalizedWorkspacePath(project.localPath).isEmpty
                ? suggestedPath
                : LocalWorkspaceService.normalizedWorkspacePath(project.localPath)

            let workspacePath = try LocalWorkspaceService.ensureLocalClone(
                repoURL: repoURL,
                preferredPath: preferredPath,
                rootPath: LocalWorkspaceService.defaultWorkspaceRoot
            )

            switch target {
            case .codex:
                try LocalWorkspaceService.openInCodex(path: workspacePath)
            case .antigravity:
                try LocalWorkspaceService.openInAntigravity(path: workspacePath)
            case .claude:
                try LocalWorkspaceService.openInClaude(path: workspacePath)
            }

            project.localPath = workspacePath
            project.isActiveThread = true
            project.lastUpdated = Date()
            project.lastReviewed = Date()
            try modelContext.save()

            workspaceMessage = "Workspace ready and opened in \(target.rawValue)"
        } catch {
            workspaceError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    private func shellField<Content: View>(_ label: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(label.uppercased())
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .foregroundStyle(Color(red: 0.541, green: 0.561, blue: 0.596))
            content()
        }
    }

    private func fieldGrid<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        LazyVGrid(
            columns: [GridItem(.flexible(minimum: 220), spacing: 12), GridItem(.flexible(minimum: 220), spacing: 12)],
            alignment: .leading,
            spacing: 16
        ) {
            content()
        }
    }

    private func compactCard(title: String, subtitle: String, badgeText: String, badgeColor: Color) -> some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(WhisperTheme.ink)
                Text(subtitle)
                    .font(.system(size: 12))
                    .foregroundStyle(WhisperTheme.mutedInk)
            }

            Spacer(minLength: 12)

            Text(badgeText)
                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                .padding(.horizontal, 8)
                .frame(height: 20)
                .background(badgeColor.opacity(0.14), in: RoundedRectangle(cornerRadius: 5, style: .continuous))
                .foregroundStyle(badgeColor)
        }
        .padding(12)
        .background(Color(red: 0.075, green: 0.078, blue: 0.090), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .stroke(Color.white.opacity(0.06), lineWidth: 1)
        )
    }

    private var displayName: String {
        let trimmed = project.name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Untitled project" : trimmed
    }

    private var clientLine: String {
        let trimmed = project.clientName.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "No client assigned" : trimmed
    }

    private var statusLine: String {
        switch project.status {
        case .green: return "Live"
        case .yellow: return "Build"
        case .red: return "Blocked"
        }
    }
}

private struct CreateProjectRepositorySheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    @Bindable var project: Project
    let target: LaunchTarget
    let onComplete: (String) -> Void

    @FocusState private var isRepoNameFocused: Bool

    @State private var repoName: String
    @State private var isCreating = false
    @State private var stageMessage: String?
    @State private var errorMessage: String?

    init(project: Project, target: LaunchTarget, onComplete: @escaping (String) -> Void) {
        self.project = project
        self.target = target
        self.onComplete = onComplete
        _repoName = State(initialValue: Self.defaultRepoName(for: project))
    }

    var body: some View {
        NavigationStack {
            ZStack {
                WhisperBackground()

                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("CREATE REPOSITORY")
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(WhisperTheme.accent)

                            Text("Provision GitHub, local workspace, and Codex.")
                                .font(.title3.weight(.semibold))
                                .foregroundStyle(WhisperTheme.ink)

                            Text("This restores the old raCommand flow: create the GitHub repo, clone it into `~/Desktop/local dev`, and open a Codex thread for the workspace.")
                                .font(.callout)
                                .foregroundStyle(WhisperTheme.mutedInk)
                        }
                        .whisperPanel(padding: 16, radius: 10)

                        VStack(alignment: .leading, spacing: 16) {
                            WhisperSectionTitle(
                                eyebrow: "Repository",
                                title: "GitHub repo name",
                                detail: "The project will be linked to this repo and local workspace."
                            )

                            TextField("quick-quote-scheduler", text: $repoName)
                                .platformDisableTextInputAutocapitalization()
                                .autocorrectionDisabled()
                                .focused($isRepoNameFocused)
                                .foregroundStyle(WhisperTheme.ink)
                                .whisperInsetField()
                                .onSubmit {
                                    if canSubmit {
                                        Task { await createRepositoryAndThread() }
                                    }
                                }

                            if !normalizedRepoName.isEmpty {
                                detailRow(icon: "shippingbox", label: "GitHub repo", value: normalizedRepoName)
                                detailRow(icon: "folder", label: "Local workspace", value: suggestedWorkspacePath)
                                detailRow(icon: "rectangle.stack.badge.play", label: "Next step", value: "Open a \(target.rawValue) thread for the cloned workspace")
                            }

                            if let validationMessage {
                                Text(validationMessage)
                                    .font(.caption)
                                    .foregroundStyle(WhisperTheme.warning)
                            }
                        }
                        .whisperPanel()

                        if let stageMessage, isCreating {
                            HStack(spacing: 10) {
                                ProgressView()
                                    .tint(WhisperTheme.accent)
                                Text(stageMessage)
                                    .font(.subheadline.weight(.medium))
                                    .foregroundStyle(WhisperTheme.ink)
                            }
                            .whisperPanel()
                        }

                        if let errorMessage {
                            VStack(alignment: .leading, spacing: 8) {
                                Label("Repository creation failed", systemImage: "exclamationmark.triangle.fill")
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(WhisperTheme.danger)

                                Text(errorMessage)
                                    .font(.subheadline)
                                    .foregroundStyle(WhisperTheme.mutedInk)
                            }
                            .whisperPanel()
                        }
                    }
                    .padding(24)
                }
            }
            .navigationTitle("Create Repository")
            .platformNavigationTitleDisplayMode(.inline)
            .tint(WhisperTheme.accent)
            .fontDesign(.default)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    if isCreating {
                        ProgressView()
                            .tint(WhisperTheme.accent)
                    } else {
                        Button("Create") {
                            Task { await createRepositoryAndThread() }
                        }
                        .disabled(!canSubmit)
                    }
                }

                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .onAppear {
                isRepoNameFocused = true
            }
        }
    }

    private var normalizedRepoName: String {
        slugifiedRepoName(from: repoName)
    }

    private var suggestedWorkspacePath: String {
        URL(fileURLWithPath: LocalWorkspaceService.defaultWorkspaceRoot, isDirectory: true)
            .appendingPathComponent(normalizedRepoName, isDirectory: true)
            .path
    }

    private var validationMessage: String? {
        let trimmed = repoName.trimmingCharacters(in: .whitespacesAndNewlines)

        if trimmed.isEmpty {
            return nil
        }

        if normalizedRepoName.isEmpty {
            return "Enter at least one letter or number for the repo name."
        }

        if LocalWorkspaceService.workspaceExists(at: suggestedWorkspacePath) {
            return "A local folder already exists at \(suggestedWorkspacePath). Choose a different repo name."
        }

        return nil
    }

    private var canSubmit: Bool {
        !isCreating && !normalizedRepoName.isEmpty && validationMessage == nil
    }

    @ViewBuilder
    private func detailRow(icon: String, label: String, value: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon)
                .foregroundStyle(WhisperTheme.accent)
                .frame(width: 18)

            VStack(alignment: .leading, spacing: 4) {
                Text(label.uppercased())
                    .font(.caption2.weight(.bold))
                    .tracking(0.8)
                    .foregroundStyle(WhisperTheme.mutedInk)

                Text(value)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(WhisperTheme.ink)
                    .textSelection(.enabled)
            }
        }
    }

    @MainActor
    private func createRepositoryAndThread() async {
        guard canSubmit else { return }

        guard let token = KeychainService.loadGitHubToken(), !token.isEmpty else {
            errorMessage = "No GitHub token found. Add one in Workspaces > Import > Import from GitHub."
            return
        }

        isCreating = true
        errorMessage = nil
        defer {
            stageMessage = nil
            isCreating = false
        }

        do {
            try await ProjectRepoProvisioner.provision(
                project: project,
                repoName: normalizedRepoName,
                description: project.name.trimmingCharacters(in: .whitespacesAndNewlines),
                preferredPath: suggestedWorkspacePath,
                githubToken: token,
                modelContext: modelContext,
                target: target,
                onStage: { stageMessage = $0 }
            )
            onComplete(project.localPath)
            dismiss()
        } catch let error as ProjectRepoProvisionError {
            errorMessage = ProjectRepoProvisioner.describe(error)
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    private func slugifiedRepoName(from rawValue: String) -> String {
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }

        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-._"))
        let unicodeScalars = trimmed.lowercased().unicodeScalars.map { scalar -> String in
            if allowed.contains(scalar) {
                return String(scalar)
            }
            if CharacterSet.whitespacesAndNewlines.contains(scalar) {
                return "-"
            }
            return "-"
        }

        return unicodeScalars.joined()
            .replacingOccurrences(of: "-{2,}", with: "-", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet(charactersIn: "-."))
    }

    private static func defaultRepoName(for project: Project) -> String {
        let trimmedName = project.name.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedName.isEmpty {
            return trimmedName
        }

        if let repoName = LocalWorkspaceService.repoName(from: project.repoURL) {
            return repoName
        }

        return ""
    }
}

private extension View {
    func shellInputChrome() -> some View {
        padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(WhisperTheme.input, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .stroke(WhisperTheme.border, lineWidth: 1)
            )
    }

    func shellTextField() -> some View {
        textFieldStyle(.plain)
            .font(.system(size: 13))
            .foregroundStyle(WhisperTheme.ink)
            .shellInputChrome()
    }
}
