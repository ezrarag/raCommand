//
//  PulseQueryService.swift
//  raCommand
//
//  Structured Ask Pulse answers built from project metadata, local git, and GitHub state.
//

import Foundation

struct PulseDraft: Identifiable, Hashable {
    let id = UUID()
    let title: String
    let audienceLabel: String
    let recipientSuggestion: String
    let body: String
}

struct PulseQueryAnswer {
    let projectName: String
    let wasProjectInferred: Bool
    let summary: String
    let facts: [String]
    let sourceLabels: [String]
    let warnings: [String]
    let drafts: [PulseDraft]
}

enum PulseQueryService {
    static func answer(
        question: String,
        selectedProject: Project?,
        allProjects: [Project]
    ) async -> PulseQueryAnswer {
        let trimmedQuestion = question.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !allProjects.isEmpty else {
            return PulseQueryAnswer(
                projectName: "",
                wasProjectInferred: false,
                summary: "There are no projects in the app yet, so Pulse has nothing to inspect.",
                facts: [],
                sourceLabels: ["Projects"],
                warnings: [],
                drafts: []
            )
        }

        guard let resolution = resolveProject(
            selectedProject: selectedProject,
            question: trimmedQuestion,
            allProjects: allProjects
        ) else {
            return PulseQueryAnswer(
                projectName: "",
                wasProjectInferred: false,
                summary: "Pick a project or mention its name in the question so Pulse knows what to inspect.",
                facts: [],
                sourceLabels: ["Projects"],
                warnings: [],
                drafts: []
            )
        }

        let project = resolution.project
        let intent = classify(question: trimmedQuestion)
        let token = KeychainService.loadGitHubToken()

        var facts: [String] = []
        var warnings: [String] = []
        var sourceLabels: [String] = ["Project"]

        facts.append(
            "Project state: \(project.status.rawValue.capitalized) status, value \(project.valueScore), category \(project.category.rawValue.capitalized)."
        )

        if project.nextAction.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            facts.append("Next action is not defined yet.")
        } else {
            facts.append("Next action: \(project.nextAction)")
        }

        if project.isActiveThread {
            facts.append("A Codex thread is already marked active for this project.")
        }

        let workspacePath = preferredWorkspacePath(for: project)
        let localSnapshot: LocalGitSnapshot? = {
            guard intent.needsLocalContext else { return nil }
            guard let workspacePath else {
                if intent.focus == .sync {
                    warnings.append("No local workspace is linked for this project yet.")
                }
                return nil
            }

            do {
                let snapshot = try LocalGitInspector.inspect(at: workspacePath)
                sourceLabels.append("Local git")
                facts.append("Local branch: \(snapshot.branch). Workspace: \(snapshot.path)")

                if snapshot.isDirty {
                    facts.append(
                        "Working tree has \(snapshot.changedFileCount) changed file(s), with \(snapshot.stagedCount) staged, \(snapshot.unstagedCount) unstaged, and \(snapshot.untrackedCount) untracked."
                    )
                } else {
                    facts.append("Working tree is clean.")
                }

                if let ahead = snapshot.aheadCount, let behind = snapshot.behindCount {
                    facts.append("Upstream sync: ahead \(ahead), behind \(behind).")
                } else {
                    facts.append("No upstream tracking branch was detected for the local repo.")
                }

                if let latestCommit = snapshot.recentCommits.first {
                    facts.append("Latest local commit: \(latestCommit.shortSHA) \(latestCommit.message) (\(latestCommit.relativeDate)).")
                }

                if let originURL = snapshot.originURL,
                   !project.repoURL.isEmpty,
                   normalizeGitRemote(originURL) != normalizeGitRemote(project.repoURL) {
                    warnings.append("The local repo origin does not match the project's saved GitHub URL.")
                }

                return snapshot
            } catch {
                warnings.append((error as? LocalizedError)?.errorDescription ?? error.localizedDescription)
                return nil
            }
        }()

        var remoteSnapshot: GitHubProjectSnapshot?
        if intent.needsGitHubContext {
            if project.repoURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                warnings.append("This project does not have a GitHub repo URL yet.")
            } else {
                do {
                    let snapshot = try await GitHubProjectInsightService.fetchSnapshot(
                        repoURL: project.repoURL,
                        token: token
                    )
                    sourceLabels.append("GitHub")
                    facts.append(
                        "GitHub shows \(snapshot.openPullRequests.count) open PR(s) and \(snapshot.openIssues.count) open issue(s) on \(snapshot.defaultBranch)."
                    )
                    if let latestCommit = snapshot.recentCommits.first {
                        let commitDate = latestCommit.date?.formatted(date: .abbreviated, time: .omitted) ?? "recently"
                        facts.append("Latest GitHub commit: \(latestCommit.shortSHA) \(latestCommit.message) (\(commitDate)).")
                    }
                    if let topPR = snapshot.openPullRequests.first {
                        facts.append("Top open PR: #\(topPR.number) \(topPR.title).")
                    }
                    if let topIssue = snapshot.openIssues.first {
                        facts.append("Top open issue: #\(topIssue.number) \(topIssue.title).")
                    }
                    remoteSnapshot = snapshot
                } catch {
                    warnings.append((error as? LocalizedError)?.errorDescription ?? error.localizedDescription)
                }
            }
        }

        var openFeedback: [ClientFeedback] = []
        if intent.needsClientContext {
            do {
                let feedback = try await ClientNoteService.fetchFeedback(
                    projectId: project.clientFeedbackProjectId,
                    status: "open"
                )
                if !feedback.isEmpty {
                    sourceLabels.append("Client feedback")
                    let highestPulse = feedback.map(\.pulseScore).max() ?? 0
                    facts.append("Open client feedback: \(feedback.count) note(s), highest pulse \(highestPulse).")
                    if let topFeedback = feedback.max(by: { $0.pulseScore < $1.pulseScore }) {
                        facts.append("Highest-pressure client note: \(topFeedback.summary)")
                    }
                }
                openFeedback = feedback
            } catch {
                warnings.append((error as? LocalizedError)?.errorDescription ?? error.localizedDescription)
            }
        }

        var collaborators: [GitHubCollaborator] = []
        if intent.needsEngineerRecipients {
            if let token, !token.isEmpty {
                if !project.repoURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    do {
                        let fetchedCollaborators = try await GitHubCollaboratorsService.fetchCollaborators(
                            repoURL: project.repoURL,
                            token: token
                        )
                        if !fetchedCollaborators.isEmpty {
                            sourceLabels.append("Collaborators")
                        }
                        collaborators = fetchedCollaborators
                    } catch {
                        warnings.append((error as? LocalizedError)?.errorDescription ?? error.localizedDescription)
                    }
                }
            } else {
                warnings.append("GitHub token not found, so engineer recipient suggestions are limited.")
            }
        }

        let summary = buildSummary(
            for: project,
            focus: intent.focus,
            localSnapshot: localSnapshot,
            remoteSnapshot: remoteSnapshot,
            feedback: openFeedback
        )

        if intent.requestsRouting {
            let routing = buildRoutingFact(
                project: project,
                feedback: openFeedback,
                collaborators: collaborators
            )
            facts.append(routing)
        }

        let drafts = buildDrafts(
            for: project,
            intent: intent,
            localSnapshot: localSnapshot,
            remoteSnapshot: remoteSnapshot,
            feedback: openFeedback,
            collaborators: collaborators
        )

        return PulseQueryAnswer(
            projectName: project.name,
            wasProjectInferred: resolution.wasInferred,
            summary: summary,
            facts: facts,
            sourceLabels: uniqueValues(in: sourceLabels),
            warnings: uniqueValues(in: warnings).filter { !$0.isEmpty },
            drafts: drafts
        )
    }

    private enum QueryFocus {
        case summary
        case sync
        case github
    }

    private struct QueryIntent {
        let focus: QueryFocus
        let needsLocalContext: Bool
        let needsGitHubContext: Bool
        let needsClientContext: Bool
        let needsEngineerRecipients: Bool
        let wantsClientDraft: Bool
        let wantsEngineerDraft: Bool
        let requestsRouting: Bool
    }

    private struct ProjectResolution {
        let project: Project
        let wasInferred: Bool
    }

    private static func resolveProject(
        selectedProject: Project?,
        question: String,
        allProjects: [Project]
    ) -> ProjectResolution? {
        if let selectedProject {
            return ProjectResolution(project: selectedProject, wasInferred: false)
        }

        let normalizedQuestion = normalize(question)

        if let matched = allProjects.first(where: { project in
            let candidates = [
                project.name,
                project.clientName,
                LocalWorkspaceService.repoName(from: project.repoURL) ?? ""
            ]
            return candidates.contains { candidate in
                let normalizedCandidate = normalize(candidate)
                return !normalizedCandidate.isEmpty && normalizedQuestion.contains(normalizedCandidate)
            }
        }) {
            return ProjectResolution(project: matched, wasInferred: true)
        }

        if allProjects.count == 1, let onlyProject = allProjects.first {
            return ProjectResolution(project: onlyProject, wasInferred: true)
        }

        return nil
    }

    private static func classify(question: String) -> QueryIntent {
        let normalized = normalize(question)

        let syncKeywords = [
            "sync", "ahead", "behind", "local", "git", "changed", "unpushed",
            "dirty", "workspace", "newer than github"
        ]
        let githubKeywords = [
            "github", "remote", "pull request", "pr", "issue", "issues", "review", "commit"
        ]
        let clientKeywords = [
            "client", "customer", "stakeholder", "feedback", "loom", "portal", "reply"
        ]
        let engineerKeywords = [
            "engineer", "engineering", "developer", "dev", "team", "handoff"
        ]
        let draftKeywords = [
            "draft", "message", "email", "respond", "response", "update", "communicate", "send"
        ]
        let routingKeywords = [
            "route", "recipient", "recipients", "who should know", "who should get", "who needs"
        ]

        let focus: QueryFocus
        if containsAny(syncKeywords, in: normalized) {
            focus = .sync
        } else if containsAny(githubKeywords, in: normalized) {
            focus = .github
        } else {
            focus = .summary
        }

        let requestsRouting = containsAny(routingKeywords, in: normalized)
        let wantsDrafts = containsAny(draftKeywords, in: normalized) || requestsRouting
        var wantsClientDraft = wantsDrafts && containsAny(clientKeywords, in: normalized)
        var wantsEngineerDraft = wantsDrafts && containsAny(engineerKeywords, in: normalized)

        if wantsDrafts && !wantsClientDraft && !wantsEngineerDraft {
            wantsClientDraft = true
            wantsEngineerDraft = true
        }

        let needsClientContext = wantsClientDraft || containsAny(clientKeywords, in: normalized)
        let needsLocalContext = focus != .github || wantsDrafts
        let needsGitHubContext = focus != .summary || wantsDrafts || requestsRouting

        return QueryIntent(
            focus: focus,
            needsLocalContext: needsLocalContext,
            needsGitHubContext: needsGitHubContext,
            needsClientContext: needsClientContext,
            needsEngineerRecipients: wantsEngineerDraft || requestsRouting,
            wantsClientDraft: wantsClientDraft,
            wantsEngineerDraft: wantsEngineerDraft,
            requestsRouting: requestsRouting
        )
    }

    private static func buildSummary(
        for project: Project,
        focus: QueryFocus,
        localSnapshot: LocalGitSnapshot?,
        remoteSnapshot: GitHubProjectSnapshot?,
        feedback: [ClientFeedback]
    ) -> String {
        switch focus {
        case .sync:
            if let localSnapshot {
                if localSnapshot.isDirty || (localSnapshot.aheadCount ?? 0) > 0 {
                    return "Local work on \(project.name) is ahead of what is published on GitHub."
                }

                if let behind = localSnapshot.behindCount, behind > 0 {
                    return "GitHub is ahead of the local workspace for \(project.name)."
                }

                if let ahead = localSnapshot.aheadCount, let behind = localSnapshot.behindCount,
                   ahead == 0, behind == 0 {
                    return "Local and upstream git state look aligned for \(project.name)."
                }

                return "Pulse can inspect the local repo for \(project.name), but upstream sync is not fully configured."
            }

            if project.repoURL.isEmpty {
                return "Pulse cannot compare local and GitHub yet because this project does not have a linked repo."
            }

            return "Pulse needs a local workspace before it can compare \(project.name) against GitHub."

        case .github:
            if let remoteSnapshot {
                return "\(project.name) currently has \(remoteSnapshot.openPullRequests.count) open PR(s) and \(remoteSnapshot.openIssues.count) open issue(s) on GitHub."
            }

            if project.repoURL.isEmpty {
                return "This project does not have a GitHub repo linked yet."
            }

            return "Pulse could not read GitHub state for \(project.name) right now."

        case .summary:
            var fragments: [String] = [
                "\(project.status.rawValue.capitalized) status"
            ]

            if project.nextAction.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                fragments.append("missing a next action")
            } else {
                fragments.append("next move is defined")
            }

            if let localSnapshot {
                if localSnapshot.isDirty || (localSnapshot.aheadCount ?? 0) > 0 {
                    fragments.append("local work is still in motion")
                } else if let behind = localSnapshot.behindCount, behind > 0 {
                    fragments.append("local repo is behind GitHub")
                }
            }

            if !feedback.isEmpty {
                fragments.append("\(feedback.count) open client note(s)")
            }

            if project.isActiveThread {
                fragments.append("Codex thread active")
            }

            return "\(project.name) is \(fragments.joined(separator: ", "))."
        }
    }

    private static func buildRoutingFact(
        project: Project,
        feedback: [ClientFeedback],
        collaborators: [GitHubCollaborator]
    ) -> String {
        let clientRecipient = clientRecipientSuggestion(for: project, feedback: feedback)
        let engineerRecipient = engineerRecipientSuggestion(collaborators: collaborators)
        return "Suggested routing: client-facing updates -> \(clientRecipient); engineering handoff -> \(engineerRecipient)."
    }

    private static func buildDrafts(
        for project: Project,
        intent: QueryIntent,
        localSnapshot: LocalGitSnapshot?,
        remoteSnapshot: GitHubProjectSnapshot?,
        feedback: [ClientFeedback],
        collaborators: [GitHubCollaborator]
    ) -> [PulseDraft] {
        var drafts: [PulseDraft] = []

        if intent.wantsClientDraft {
            drafts.append(
                PulseDraft(
                    title: "Client Update Draft",
                    audienceLabel: "Client",
                    recipientSuggestion: clientRecipientSuggestion(for: project, feedback: feedback),
                    body: clientDraftBody(
                        project: project,
                        localSnapshot: localSnapshot,
                        feedback: feedback
                    )
                )
            )
        }

        if intent.wantsEngineerDraft {
            drafts.append(
                PulseDraft(
                    title: "Engineer Handoff Draft",
                    audienceLabel: "Engineering",
                    recipientSuggestion: engineerRecipientSuggestion(collaborators: collaborators),
                    body: engineerDraftBody(
                        project: project,
                        localSnapshot: localSnapshot,
                        remoteSnapshot: remoteSnapshot,
                        feedback: feedback
                    )
                )
            )
        }

        return drafts
    }

    private static func clientDraftBody(
        project: Project,
        localSnapshot: LocalGitSnapshot?,
        feedback: [ClientFeedback]
    ) -> String {
        let recipient = clientGreetingName(for: project, feedback: feedback)
        let feedbackLine: String = {
            guard let topFeedback = feedback.max(by: { $0.pulseScore < $1.pulseScore }) else {
                return ""
            }
            return "Thanks for the note about \(topFeedback.summary.lowercased())."
        }()

        let progressLine: String = {
            guard let localSnapshot else {
                return "We have the project tracked and are tightening the next step now."
            }

            if localSnapshot.isDirty || (localSnapshot.aheadCount ?? 0) > 0 {
                return "Work is actively in progress in the local workspace and not all of it has been published yet."
            }

            if let behind = localSnapshot.behindCount, behind > 0 {
                return "We are syncing the local workspace with the latest GitHub updates before the next move."
            }

            return "The current workspace and repo state look aligned, so the next move is execution rather than cleanup."
        }()

        let nextStep = project.nextAction.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? "We are defining the sharpest next step internally now."
            : "Next step: \(project.nextAction)"

        return """
        Hi \(recipient),

        Quick update on \(project.name):

        \(feedbackLine.isEmpty ? "We reviewed the current state of the project." : feedbackLine)
        \(progressLine)
        \(nextStep)

        I’ll follow up again once the current step is complete.

        Best,
        Readyaimgo
        """
    }

    private static func engineerDraftBody(
        project: Project,
        localSnapshot: LocalGitSnapshot?,
        remoteSnapshot: GitHubProjectSnapshot?,
        feedback: [ClientFeedback]
    ) -> String {
        let syncLine: String = {
            guard let localSnapshot else {
                return "- Local git: no linked workspace yet."
            }

            let ahead = localSnapshot.aheadCount.map(String.init) ?? "?"
            let behind = localSnapshot.behindCount.map(String.init) ?? "?"
            return "- Local git: branch \(localSnapshot.branch), ahead \(ahead), behind \(behind), changed files \(localSnapshot.changedFileCount)."
        }()

        let remoteLine: String = {
            guard let remoteSnapshot else {
                return "- GitHub: remote state unavailable."
            }
            return "- GitHub: \(remoteSnapshot.openPullRequests.count) open PR(s), \(remoteSnapshot.openIssues.count) open issue(s) on \(remoteSnapshot.defaultBranch)."
        }()

        let feedbackLine: String = {
            guard !feedback.isEmpty else {
                return "- Client feedback: no open notes pulled into this query."
            }
            let highestPulse = feedback.map(\.pulseScore).max() ?? 0
            return "- Client feedback: \(feedback.count) open note(s), highest pulse \(highestPulse)."
        }()

        let nextStep = project.nextAction.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? "Define the next concrete move before coding further."
            : project.nextAction

        return """
        Team,

        Pulse snapshot for \(project.name):

        - Project status: \(project.status.rawValue.capitalized), value \(project.valueScore).
        \(syncLine)
        \(remoteLine)
        \(feedbackLine)
        - Next action: \(nextStep)

        Please pick up from this state and update the thread once the next action is complete.
        """
    }

    private static func clientRecipientSuggestion(for project: Project, feedback: [ClientFeedback]) -> String {
        if let email = feedback.compactMap(\.clientEmail).first, !email.isEmpty {
            return email
        }

        if let clientName = feedback.map(\.clientName).first, !clientName.isEmpty {
            return clientName
        }

        let trimmedClientName = project.clientName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedClientName.isEmpty {
            return trimmedClientName
        }

        return "Client contact"
    }

    private static func clientGreetingName(for project: Project, feedback: [ClientFeedback]) -> String {
        if let clientName = feedback.map(\.clientName).first,
           !clientName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return clientName
        }

        let trimmedClientName = project.clientName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedClientName.isEmpty {
            return trimmedClientName
        }

        return "there"
    }

    private static func engineerRecipientSuggestion(collaborators: [GitHubCollaborator]) -> String {
        let prioritized = collaborators
            .filter { $0.roleInRepo != "read" }
            .map(\.login)

        if !prioritized.isEmpty {
            return prioritized.prefix(3).joined(separator: ", ")
        }

        if !collaborators.isEmpty {
            return collaborators.prefix(3).map(\.login).joined(separator: ", ")
        }

        return "Engineering owner"
    }

    private static func preferredWorkspacePath(for project: Project) -> String? {
        let savedPath = project.localPath.trimmingCharacters(in: .whitespacesAndNewlines)
        if !savedPath.isEmpty, LocalWorkspaceService.workspaceExists(at: savedPath) {
            return savedPath
        }

        guard !project.repoURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              let suggested = LocalWorkspaceService.suggestedLocalPath(for: project.repoURL),
              LocalWorkspaceService.workspaceExists(at: suggested) else {
            return nil
        }

        return suggested
    }

    private static func normalize(_ value: String) -> String {
        value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
    }

    private static func normalizeGitRemote(_ value: String) -> String {
        normalize(value)
            .replacingOccurrences(of: ".git", with: "")
            .replacingOccurrences(of: "git@github.com:", with: "https://github.com/")
    }

    private static func containsAny(_ phrases: [String], in value: String) -> Bool {
        phrases.contains { value.contains($0) }
    }

    private static func uniqueValues(in values: [String]) -> [String] {
        var seen = Set<String>()
        return values.filter { value in
            let inserted = seen.insert(value).inserted
            return inserted
        }
    }
}
