//
//  AddProjectView.swift
//  raCommand
//
//  Created by E. Haugabrooks on 1/11/26.
//

import SwiftUI
import SwiftData

struct AddProjectView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Query private var projects: [Project]

    @FocusState private var isRepoNameFocused: Bool

    @State private var repoName = ""
    @State private var isCreating = false
    @State private var stageMessage: String?
    @State private var errorMessage: String?
    @State private var createdProject = false

    var body: some View {
        NavigationStack {
            ZStack {
                WhisperBackground()

                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("NEW PROJECT")
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(WhisperTheme.accent)

                            Text("Create a GitHub repo and open it in Codex.")
                                .font(.title3.weight(.semibold))
                                .foregroundStyle(WhisperTheme.ink)

                            Text("Enter a repo name. raCommand will create it on GitHub, clone it into `~/Desktop/local dev`, and open a Codex thread for the new workspace.")
                                .font(.callout)
                                .foregroundStyle(WhisperTheme.mutedInk)
                        }
                        .whisperPanel(padding: 16, radius: 10)

                        VStack(alignment: .leading, spacing: 16) {
                            WhisperSectionTitle(
                                eyebrow: "Repository",
                                title: "GitHub repo name",
                                detail: "Spaces and unsupported characters are converted into a GitHub-safe slug."
                            )

                            TextField("quick-quote-scheduler", text: $repoName)
                                .platformDisableTextInputAutocapitalization()
                                .autocorrectionDisabled()
                                .focused($isRepoNameFocused)
                                .foregroundStyle(WhisperTheme.ink)
                                .whisperInsetField()
                                .onSubmit {
                                    if canSubmit {
                                        Task { await createProject() }
                                    }
                                }

                            if !normalizedRepoName.isEmpty {
                                detailRow(
                                    icon: "shippingbox",
                                    label: "GitHub repo",
                                    value: normalizedRepoName
                                )

                                detailRow(
                                    icon: "folder",
                                    label: "Local workspace",
                                    value: suggestedWorkspacePath
                                )

                                detailRow(
                                    icon: "rectangle.stack.badge.play",
                                    label: "Next step",
                                    value: "Open a Codex thread for the cloned workspace"
                                )
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

                        if createdProject, let errorMessage {
                            VStack(alignment: .leading, spacing: 8) {
                                Label("Project created with follow-up needed", systemImage: "checkmark.circle.fill")
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(WhisperTheme.success)

                                Text(errorMessage)
                                    .font(.subheadline)
                                    .foregroundStyle(WhisperTheme.mutedInk)
                            }
                            .whisperPanel()
                        } else if let errorMessage {
                            VStack(alignment: .leading, spacing: 8) {
                                Label("Could not create project", systemImage: "exclamationmark.triangle.fill")
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
            .navigationTitle("New Project")
            .platformNavigationTitleDisplayMode(.inline)
            .tint(WhisperTheme.accent)
            .fontDesign(.default)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    if isCreating {
                        ProgressView()
                            .tint(WhisperTheme.accent)
                    } else {
                        Button(createdProject ? "Done" : "Create") {
                            if createdProject {
                                dismiss()
                            } else {
                                Task { await createProject() }
                            }
                        }
                        .disabled(!canSubmit && !createdProject)
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

    private var conflictingProject: Project? {
        guard !normalizedRepoName.isEmpty else { return nil }

        return projects.first { project in
            if project.repoURL.lowercased().hasSuffix("/\(normalizedRepoName.lowercased())") {
                return true
            }

            let projectPath = LocalWorkspaceService.normalizedWorkspacePath(project.localPath)
            let targetPath = LocalWorkspaceService.normalizedWorkspacePath(suggestedWorkspacePath)
            if !projectPath.isEmpty, projectPath == targetPath {
                return true
            }

            return project.name.caseInsensitiveCompare(normalizedRepoName) == .orderedSame
        }
    }

    private var validationMessage: String? {
        let trimmed = repoName.trimmingCharacters(in: .whitespacesAndNewlines)

        if trimmed.isEmpty {
            return nil
        }

        if normalizedRepoName.isEmpty {
            return "Enter at least one letter or number for the repo name."
        }

        if let conflictingProject {
            return "A tracked project already matches this repo name: \(conflictingProject.name)."
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
    private func createProject() async {
        guard canSubmit else { return }

        let repoSlug = normalizedRepoName
        guard let token = KeychainService.loadGitHubToken(), !token.isEmpty else {
            errorMessage = "No GitHub token found. Add one in Projects > Import > GitHub Import."
            return
        }

        isCreating = true
        createdProject = false
        errorMessage = nil
        stageMessage = "Creating GitHub repository..."

        do {
            let repo = try await GitHubActionsService.createRepo(
                name: repoSlug,
                isPrivate: false,
                token: token
            )

            let project = upsertProject(name: repo.name, repoURL: repo.htmlURL)
            try context.save()
            createdProject = true

            stageMessage = "Cloning into local dev..."

            let workspacePath: String
            do {
                workspacePath = try LocalWorkspaceService.ensureLocalClone(
                    repoURL: repo.cloneURL,
                    preferredPath: suggestedWorkspacePath,
                    rootPath: LocalWorkspaceService.defaultWorkspaceRoot
                )
            } catch {
                project.lastUpdated = Date()
                try? context.save()
                errorMessage = "GitHub repo created, but cloning into local dev failed: \((error as? LocalizedError)?.errorDescription ?? error.localizedDescription)"
                stageMessage = nil
                isCreating = false
                return
            }

            project.localPath = workspacePath
            project.lastUpdated = Date()
            try context.save()

            stageMessage = "Opening Codex thread..."

            do {
                try LocalWorkspaceService.openInCodex(path: workspacePath)

                project.isActiveThread = true
                project.lastUpdated = Date()
                project.lastReviewed = Date()
                try context.save()

                dismiss()
            } catch {
                project.lastUpdated = Date()
                try? context.save()
                errorMessage = "GitHub repo created and cloned, but Codex could not open the workspace: \((error as? LocalizedError)?.errorDescription ?? error.localizedDescription)"
            }
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }

        stageMessage = nil
        isCreating = false
    }

    @MainActor
    @discardableResult
    private func upsertProject(name: String, repoURL: String) -> Project {
        if let existing = projects.first(where: { $0.repoURL == repoURL || $0.name.caseInsensitiveCompare(name) == .orderedSame }) {
            existing.name = name
            existing.repoURL = repoURL
            existing.lastUpdated = Date()
            return existing
        }

        let project = Project(
            name: name,
            status: .yellow,
            valueScore: 5,
            repoURL: repoURL
        )
        context.insert(project)
        return project
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

        let collapsed = unicodeScalars.joined()
            .replacingOccurrences(of: "-{2,}", with: "-", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet(charactersIn: "-."))

        return collapsed
    }
}
