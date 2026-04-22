//
//  PulseView.swift
//  raCommand
//
//  Priority dashboard with an Ask Pulse query panel.
//

import SwiftUI
import SwiftData

struct PulseView: View {
    @Query(sort: \Project.lastUpdated, order: .reverse) private var projects: [Project]
    @State private var feedbackSignals: [String: Int] = [:]
    @State private var selectedProjectKey = ""
    @State private var pulseQuestion = ""
    @State private var queryAnswer: PulseQueryAnswer?
    @State private var queryLoading = false
    @State private var loadingSignals = false
    @State private var copiedMessage: String?

    private var topProjects: [(project: Project, score: Int, explanation: String)] {
        PriorityEngine.getTopProjects(projects, limit: 6, feedbackBoosts: feedbackSignals)
    }

    private var gridColumns: [GridItem] {
        [GridItem(.adaptive(minimum: 320, maximum: 440), spacing: 16, alignment: .top)]
    }

    private var projectOptions: [Project] {
        projects.sorted { lhs, rhs in
            let lhsName = lhs.name.trimmingCharacters(in: .whitespacesAndNewlines)
            let rhsName = rhs.name.trimmingCharacters(in: .whitespacesAndNewlines)
            return lhsName.localizedCaseInsensitiveCompare(rhsName) == .orderedAscending
        }
    }

    private var selectedProject: Project? {
        projectOptions.first(where: { selectionKey(for: $0) == selectedProjectKey })
    }

    private var askButtonTitle: String {
        queryLoading ? "Inspecting…" : "Ask Pulse"
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 18) {
                    hero
                    askPulsePanel

                    if let queryAnswer {
                        pulseAnswerPanel(queryAnswer)
                    }

                    if topProjects.isEmpty {
                        WhisperEmptyState(
                            icon: "waveform.path.ecg",
                            title: "No brief available",
                            message: "Add a few projects and Pulse will surface the work that needs attention first."
                        )
                    } else {
                        WhisperSectionTitle(
                            eyebrow: "Priority board",
                            title: "Ranked pressure points",
                            detail: "The highest-scoring projects float to the top so you can work from heat, not guesswork."
                        )
                        .padding(.horizontal, 4)

                        LazyVGrid(columns: gridColumns, spacing: 16) {
                            ForEach(Array(topProjects.enumerated()), id: \.element.project.id) { index, item in
                                PriorityCard(
                                    project: item.project,
                                    rank: index + 1,
                                    score: item.score,
                                    explanation: item.explanation
                                )
                            }
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 14)
                .padding(.bottom, 36)
            }
            .whisperShell()
            .navigationTitle("Pulse")
            .platformNavigationTitleDisplayMode(.large)
            .task { await loadFeedbackSignals() }
        }
    }

    private func loadFeedbackSignals() async {
        guard !projects.isEmpty else { return }
        loadingSignals = true
        var boosts: [String: Int] = [:]
        await withTaskGroup(of: (String, Int).self) { group in
            for project in projects where !project.repoURL.isEmpty {
                group.addTask {
                    let id = project.clientFeedbackProjectId
                    let feedback = (try? await ClientNoteService.fetchFeedback(projectId: id, status: "open")) ?? []
                    let boost = feedback.map { $0.priorityBoost }.max() ?? 0
                    return (project.name, boost)
                }
            }
            for await (name, boost) in group {
                if boost > 0 {
                    boosts[name] = boost
                }
            }
        }
        feedbackSignals = boosts
        loadingSignals = false
    }

    private func runPulseQuery() async {
        let trimmedQuestion = pulseQuestion.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedQuestion.isEmpty else { return }

        queryLoading = true
        copiedMessage = nil
        queryAnswer = await PulseQueryService.answer(
            question: trimmedQuestion,
            selectedProject: selectedProject,
            allProjects: projects
        )
        queryLoading = false
    }

    private func selectionKey(for project: Project) -> String {
        let repoComponent = project.repoURL.trimmingCharacters(in: .whitespacesAndNewlines)
        if !repoComponent.isEmpty {
            return repoComponent
        }
        return "\(project.name)|\(project.localPath)"
    }

    private func copy(_ value: String, confirmation: String) {
        PlatformSystemServices.copyToPasteboard(value)
        copiedMessage = confirmation
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
            copiedMessage = nil
        }
    }

    private var hero: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 8) {
                Text("DAILY BRIEF")
                    .font(.caption2.weight(.bold))
                    .tracking(1.4)
                    .foregroundStyle(WhisperTheme.accent)
                Text("Your ranked project pressure map.")
                    .font(.system(.largeTitle, design: .rounded).weight(.bold))
                    .foregroundStyle(WhisperTheme.ink)
                Text("Pulse now answers targeted project questions using tracked metadata, local git state, and GitHub snapshots.")
                    .font(.subheadline)
                    .foregroundStyle(WhisperTheme.mutedInk)
            }

            HStack(spacing: 12) {
                WhisperMetricPill(label: "Scored", value: "\(topProjects.count)", tone: WhisperTheme.info)
                WhisperMetricPill(label: "Highest", value: "\(topProjects.first?.score ?? 0)", tone: WhisperTheme.accent)
                WhisperMetricPill(label: "Signals", value: loadingSignals ? "…" : "\(feedbackSignals.count)", tone: WhisperTheme.success)
            }
        }
        .whisperPanel(padding: 20, radius: 28)
    }

    private var askPulsePanel: some View {
        VStack(alignment: .leading, spacing: 16) {
            WhisperSectionTitle(
                eyebrow: "Ask Pulse",
                title: "Inspect a specific project",
                detail: "Read-only answers only. Pulse will generate drafts, but it will not send anything for you."
            )

            if let copiedMessage {
                HStack(spacing: 10) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(WhisperTheme.success)
                    Text(copiedMessage)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(WhisperTheme.success)
                    Spacer()
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .background(WhisperTheme.success.opacity(0.08), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(WhisperTheme.success.opacity(0.22), lineWidth: 1)
                )
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("PROJECT")
                    .font(.caption2.weight(.bold))
                    .tracking(0.9)
                    .foregroundStyle(WhisperTheme.mutedInk)
                HStack {
                    Picker("Project", selection: $selectedProjectKey) {
                        Text("Auto-detect from question").tag("")
                        ForEach(projectOptions) { project in
                            Text(project.name.isEmpty ? "Untitled project" : project.name)
                                .tag(selectionKey(for: project))
                        }
                    }
                    .pickerStyle(.menu)
                    .labelsHidden()

                    Spacer()
                }
                .whisperInsetField()
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("QUESTION")
                    .font(.caption2.weight(.bold))
                    .tracking(0.9)
                    .foregroundStyle(WhisperTheme.mutedInk)

                TextField(
                    "Ask about sync, repo health, or draft a client / engineer update…",
                    text: $pulseQuestion,
                    axis: .vertical
                )
                .lineLimit(3...6)
                .whisperInsetField()
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    suggestionChip("Is this project ahead of GitHub locally?")
                    suggestionChip("Summarize repo health and next move")
                    suggestionChip("Draft a client update")
                    suggestionChip("Draft an engineer handoff")
                }
                .padding(.vertical, 2)
            }

            HStack(spacing: 10) {
                Button {
                    Task { await runPulseQuery() }
                } label: {
                    HStack(spacing: 8) {
                        if queryLoading {
                            ProgressView()
                                .tint(.white)
                                .scaleEffect(0.8)
                        }
                        Text(askButtonTitle)
                            .font(.subheadline.weight(.semibold))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(WhisperTheme.accent, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .foregroundStyle(.white)
                }
                .buttonStyle(.plain)
                .disabled(queryLoading || projects.isEmpty || pulseQuestion.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                Button {
                    pulseQuestion = ""
                    queryAnswer = nil
                    copiedMessage = nil
                } label: {
                    Text("Clear")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(WhisperTheme.info.opacity(0.14), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                        .foregroundStyle(WhisperTheme.info)
                }
                .buttonStyle(.plain)
            }
        }
        .whisperPanel()
    }

    private func pulseAnswerPanel(_ answer: PulseQueryAnswer) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            WhisperSectionTitle(
                eyebrow: "Ask Result",
                title: answer.projectName.isEmpty ? "Pulse answer" : answer.projectName,
                detail: answer.wasProjectInferred ? "Project inferred from your question." : "Answer built from the selected project."
            )

            VStack(alignment: .leading, spacing: 12) {
                Text(answer.summary)
                    .font(.system(.title3, design: .rounded).weight(.bold))
                    .foregroundStyle(WhisperTheme.ink)

                if !answer.sourceLabels.isEmpty {
                    FlowRow(spacing: 8) {
                        ForEach(answer.sourceLabels, id: \.self) { label in
                            Text(label)
                                .font(.caption.weight(.bold))
                                .foregroundStyle(WhisperTheme.info)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 7)
                                .background(WhisperTheme.info.opacity(0.1), in: Capsule())
                        }
                    }
                }

                Button {
                    copy(answer.summary, confirmation: "Summary copied")
                } label: {
                    Label("Copy summary", systemImage: "doc.on.doc")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(WhisperTheme.accent)
                }
                .buttonStyle(.plain)
            }
            .whisperInsetField()

            if !answer.facts.isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                    WhisperSectionTitle(
                        eyebrow: "Facts",
                        title: "What Pulse found",
                        detail: nil
                    )

                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(Array(answer.facts.enumerated()), id: \.offset) { _, fact in
                            HStack(alignment: .top, spacing: 10) {
                                Circle()
                                    .fill(WhisperTheme.accent)
                                    .frame(width: 7, height: 7)
                                    .padding(.top, 6)
                                Text(fact)
                                    .font(.subheadline)
                                    .foregroundStyle(WhisperTheme.ink)
                            }
                        }
                    }
                }
                .whisperPanel()
            }

            if !answer.warnings.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    WhisperSectionTitle(
                        eyebrow: "Warnings",
                        title: "Missing or partial signals",
                        detail: "Pulse answered with the data it could reach."
                    )

                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(Array(answer.warnings.enumerated()), id: \.offset) { _, warning in
                            HStack(alignment: .top, spacing: 10) {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .foregroundStyle(WhisperTheme.warning)
                                    .padding(.top, 2)
                                Text(warning)
                                    .font(.subheadline)
                                    .foregroundStyle(WhisperTheme.warning)
                            }
                        }
                    }
                }
                .whisperPanel()
            }

            if !answer.drafts.isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                    WhisperSectionTitle(
                        eyebrow: "Drafts",
                        title: "Copyable communications",
                        detail: "Pulse generated drafts only. Nothing here is sent automatically."
                    )

                    ForEach(answer.drafts) { draft in
                        draftCard(draft)
                    }
                }
            }
        }
        .whisperPanel()
    }

    private func draftCard(_ draft: PulseDraft) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(draft.title)
                        .font(.system(.title3, design: .rounded).weight(.bold))
                        .foregroundStyle(WhisperTheme.ink)
                    Text("\(draft.audienceLabel) recipient suggestion: \(draft.recipientSuggestion)")
                        .font(.caption)
                        .foregroundStyle(WhisperTheme.mutedInk)
                }

                Spacer()

                Text(draft.audienceLabel)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(WhisperTheme.accent)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .background(WhisperTheme.accentSoft.opacity(0.8), in: Capsule())
            }

            Text(draft.body)
                .font(.system(.subheadline, design: .monospaced))
                .foregroundStyle(WhisperTheme.ink)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(14)
                .background(WhisperTheme.input, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(WhisperTheme.border, lineWidth: 1)
                )

            HStack(spacing: 10) {
                Button {
                    copy(draft.body, confirmation: "\(draft.title) copied")
                } label: {
                    Label("Copy draft", systemImage: "doc.on.doc")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(WhisperTheme.accent)
                }
                .buttonStyle(.plain)

                Button {
                    copy(draft.recipientSuggestion, confirmation: "Recipient suggestion copied")
                } label: {
                    Label("Copy recipient", systemImage: "person.crop.circle.badge.checkmark")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(WhisperTheme.info)
                }
                .buttonStyle(.plain)
            }
        }
        .whisperPanel()
    }

    private func suggestionChip(_ prompt: String) -> some View {
        Button {
            pulseQuestion = prompt
        } label: {
            Text(prompt)
                .font(.caption.weight(.semibold))
                .foregroundStyle(WhisperTheme.mutedInk)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(WhisperTheme.input, in: Capsule())
                .overlay(
                    Capsule()
                        .stroke(WhisperTheme.border, lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
    }
}

struct PriorityCard: View {
    let project: Project
    let rank: Int
    let score: Int
    let explanation: String

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top) {
                Text("#\(rank)")
                    .font(.system(.headline, design: .rounded).weight(.bold))
                    .foregroundStyle(.white)
                    .frame(width: 38, height: 38)
                    .background(rankColor, in: Circle())

                VStack(alignment: .leading, spacing: 6) {
                    Text(project.name)
                        .font(.system(.title3, design: .rounded).weight(.bold))
                        .foregroundStyle(WhisperTheme.ink)
                        .lineLimit(2)
                    HStack(spacing: 8) {
                        Circle()
                            .fill(project.status.whisperColor)
                            .frame(width: 8, height: 8)
                        Text(project.status.rawValue.capitalized)
                            .font(.caption.weight(.bold))
                            .foregroundStyle(project.status.whisperColor)
                    }
                }

                Spacer(minLength: 12)

                Text("Score \(score)")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(WhisperTheme.accent)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .background(WhisperTheme.accentSoft.opacity(0.85), in: Capsule())
            }

            HStack(spacing: 10) {
                meta(icon: "star.fill", text: "Value \(project.valueScore)", color: WhisperTheme.warning)
                if project.delegatable {
                    meta(icon: "arrow.triangle.branch", text: "Delegatable", color: WhisperTheme.success)
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Next move")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(WhisperTheme.mutedInk)
                Text(project.nextAction.isEmpty ? "No next action defined yet." : project.nextAction)
                    .font(.subheadline)
                    .foregroundStyle(project.nextAction.isEmpty ? WhisperTheme.mutedInk : WhisperTheme.ink)
                    .lineLimit(3)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(project.status.whisperColor.opacity(0.08), in: RoundedRectangle(cornerRadius: 18, style: .continuous))

            Text(explanation)
                .font(.caption)
                .foregroundStyle(WhisperTheme.mutedInk)
                .lineLimit(3)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .whisperPanel()
    }

    private var rankColor: Color {
        switch rank {
        case 1: return WhisperTheme.danger
        case 2: return WhisperTheme.warning
        case 3: return WhisperTheme.info
        default: return WhisperTheme.mutedInk
        }
    }

    private func meta(icon: String, text: String, color: Color) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
            Text(text)
        }
        .font(.caption.weight(.bold))
        .foregroundStyle(color)
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(color.opacity(0.1), in: Capsule())
    }
}

private struct FlowRow<Content: View>: View {
    let spacing: CGFloat
    @ViewBuilder let content: Content

    var body: some View {
        HStack(spacing: spacing) {
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

#Preview {
    PulseView()
        .modelContainer(for: Project.self, inMemory: true)
}
