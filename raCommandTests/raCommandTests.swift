//
//  raCommandTests.swift
//  raCommandTests
//
//  Created by E. Haugabrooks on 1/11/26.
//

import Testing
@testable import raCommand

struct raCommandTests {

    @Test func example() async throws {
        // Write your test here and use APIs like `#expect(...)` to check expected conditions.
    }

    @Test func commitMessageUsesSingleModifiedFileName() async throws {
        let snapshot = makeSnapshot(changedFiles: [
            LocalGitChangedFile(path: "raCommand/Views/RepoManagerView.swift", kind: .modified)
        ])

        let message = LocalGitCommandService.suggestedCommitMessage(for: snapshot, repoName: "raCommand")

        #expect(message == "Update RepoManagerView")
    }

    @Test func commitMessageUsesSingleUntrackedFileName() async throws {
        let snapshot = makeSnapshot(changedFiles: [
            LocalGitChangedFile(path: "raCommand/Views/ProjectNotesView.swift", kind: .untracked)
        ])

        let message = LocalGitCommandService.suggestedCommitMessage(for: snapshot, repoName: "raCommand")

        #expect(message == "Add ProjectNotesView")
    }

    @Test func commitMessageUsesSingleDeletedFileName() async throws {
        let snapshot = makeSnapshot(changedFiles: [
            LocalGitChangedFile(path: "raCommand/Views/OldSettingsView.swift", kind: .deleted)
        ])

        let message = LocalGitCommandService.suggestedCommitMessage(for: snapshot, repoName: "raCommand")

        #expect(message == "Remove OldSettingsView")
    }

    @Test func commitMessageGroupsGitSyncChanges() async throws {
        let snapshot = makeSnapshot(changedFiles: [
            LocalGitChangedFile(path: "raCommand/Services/LocalGitInspector.swift", kind: .modified),
            LocalGitChangedFile(path: "raCommand/Views/RepoManagerView.swift", kind: .modified)
        ])

        let message = LocalGitCommandService.suggestedCommitMessage(for: snapshot, repoName: "raCommand")

        #expect(message == "Update git sync workflow")
    }

    @Test func commitMessageGroupsProjectViews() async throws {
        let snapshot = makeSnapshot(changedFiles: [
            LocalGitChangedFile(path: "raCommand/Views/TodayView.swift", kind: .modified),
            LocalGitChangedFile(path: "raCommand/Views/PulseView.swift", kind: .modified)
        ])

        let message = LocalGitCommandService.suggestedCommitMessage(for: snapshot, repoName: "raCommand")

        #expect(message == "Update project views")
    }

    @Test func commitMessageFallsBackForMixedChanges() async throws {
        let snapshot = makeSnapshot(changedFiles: [
            LocalGitChangedFile(path: "raCommand/Project.swift", kind: .modified),
            LocalGitChangedFile(path: "README.md", kind: .modified)
        ])

        let message = LocalGitCommandService.suggestedCommitMessage(for: snapshot, repoName: "raCommand")

        #expect(message == "Update raCommand")
    }

    @Test func removalFlowAddsContextOnlyToFallbackMessage() async throws {
        let snapshot = makeSnapshot(changedFiles: [
            LocalGitChangedFile(path: "raCommand/Project.swift", kind: .modified),
            LocalGitChangedFile(path: "README.md", kind: .modified)
        ])

        let message = LocalGitCommandService.suggestedCommitMessage(
            for: snapshot,
            repoName: "raCommand",
            isRemovalFlow: true
        )

        #expect(message == "Update raCommand before removal")
    }

    private func makeSnapshot(changedFiles: [LocalGitChangedFile]) -> LocalGitSnapshot {
        LocalGitSnapshot(
            path: "/tmp/raCommand",
            branch: "main",
            originURL: "git@github.com:example/raCommand.git",
            aheadCount: 0,
            behindCount: 0,
            changedFileCount: changedFiles.count,
            stagedCount: 0,
            unstagedCount: changedFiles.count,
            untrackedCount: changedFiles.filter { $0.kind == .untracked }.count,
            changedFiles: changedFiles,
            recentCommits: []
        )
    }

}
