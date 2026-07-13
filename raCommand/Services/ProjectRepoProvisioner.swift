//
//  ProjectRepoProvisioner.swift
//  raCommand
//
//  Single home for "create GitHub repo -> clone locally -> sync to
//  readyaimgo admin -> open Codex thread", shared by AddProjectView and
//  ProjectDetailView's CreateProjectRepositorySheet so the sequence only
//  has to be written (and changed) once.
//

import Foundation
import SwiftData

enum ProjectRepoProvisionStage {
    case creatingRepo
    case cloning
    case openingCodex
}

struct ProjectRepoProvisionError: Error {
    let stage: ProjectRepoProvisionStage
    let underlying: Error
}

@MainActor
enum ProjectRepoProvisioner {
    /// Runs the full provisioning sequence against an already-inserted `Project`.
    /// Mutates `project` in place and saves at each stage so a mid-sequence
    /// failure leaves whatever succeeded (repo URL, local path, ...) intact.
    /// The readyaimgo admin sync step is best-effort: it never throws and
    /// never blocks the local git/Codex pipeline.
    static func provision(
        project: Project,
        repoName: String,
        description: String = "",
        preferredPath: String,
        githubToken: String,
        modelContext: ModelContext,
        target: LaunchTarget = .codex,
        onStage: (String) -> Void
    ) async throws {
        onStage("Creating GitHub repository...")
        let repo: GitHubCreateRepoResponse
        do {
            repo = try await GitHubActionsService.createRepo(
                name: repoName,
                description: description,
                isPrivate: false,
                token: githubToken
            )
        } catch {
            throw ProjectRepoProvisionError(stage: .creatingRepo, underlying: error)
        }

        project.repoURL = repo.htmlURL
        if project.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            project.name = repo.name
        }
        project.lastUpdated = Date()
        try? modelContext.save()

        onStage("Cloning into local dev...")
        let workspacePath: String
        do {
            workspacePath = try LocalWorkspaceService.ensureLocalClone(
                repoURL: repo.cloneURL,
                preferredPath: preferredPath,
                rootPath: LocalWorkspaceService.defaultWorkspaceRoot
            )
        } catch {
            throw ProjectRepoProvisionError(stage: .cloning, underlying: error)
        }
        project.localPath = workspacePath
        project.lastUpdated = Date()
        try? modelContext.save()

        onStage("Syncing workspace to readyaimgo admin...")
        await syncWorkspaceToAdmin(project: project, modelContext: modelContext)

        onStage("Opening \(target.rawValue) thread...")
        do {
            switch target {
            case .codex:
                try LocalWorkspaceService.openInCodex(path: workspacePath)
            case .antigravity:
                try LocalWorkspaceService.openInAntigravity(path: workspacePath)
            case .claude:
                try LocalWorkspaceService.openInClaude(path: workspacePath)
            }
        } catch {
            throw ProjectRepoProvisionError(stage: .openingCodex, underlying: error)
        }

        project.isActiveThread = true
        project.lastUpdated = Date()
        project.lastReviewed = Date()
        try? modelContext.save()
    }

    static func syncWorkspaceToAdmin(project: Project, modelContext: ModelContext) async {
        project.workspaceSyncStatus = .pending
        do {
            let workspace = try await ClientNoteService.createRemoteWorkspace(
                name: project.name,
                repoUrl: project.repoURL
            )
            project.remoteWorkspaceId = workspace.id
            project.workspaceSyncStatus = .synced
        } catch {
            project.workspaceSyncStatus = .error
        }
        try? modelContext.save()
    }

    /// User-facing message that preserves the "how far did we get" context
    /// each call site previously wrote out by hand.
    static func describe(_ error: ProjectRepoProvisionError) -> String {
        let underlyingMessage = (error.underlying as? LocalizedError)?.errorDescription ?? error.underlying.localizedDescription
        switch error.stage {
        case .creatingRepo:
            return underlyingMessage
        case .cloning:
            return "GitHub repo created, but cloning into local dev failed: \(underlyingMessage)"
        case .openingCodex:
            return "GitHub repo created and cloned, but the agent thread could not be opened: \(underlyingMessage)"
        }
    }
}
