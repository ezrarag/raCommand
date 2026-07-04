//
//  TodayView.swift
//  raCommand
//
//  Linear-style daily briefing with interactive open loops.
//

import SwiftUI
import SwiftData

struct TodayView: View {
    @Query(sort: \Project.lastUpdated, order: .reverse) private var projects: [Project]

    @State private var dismissedLoopIDs = Set<String>()

    private var topProjects: [(project: Project, score: Int, explanation: String)] {
        PriorityEngine.getTopProjects(projects, limit: 6)
    }

    private var nextProject: Project? {
        topProjects.first?.project
    }

    private var activeProjects: Int {
        projects.filter { $0.status != .green }.count
    }

    private var openLoops: [TodayLoop] {
        topProjects.map { item in
            let project = item.project
            let key = String(describing: project.persistentModelID)
            let loopText = project.nextAction.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? "Define the next move for \(displayName(for: project))."
                : project.nextAction
            let tagSeed = project.clientName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? displayName(for: project)
                : project.clientName
            return TodayLoop(
                id: key,
                text: loopText,
                tag: initials(for: tagSeed),
                color: project.status.whisperColor,
                isDone: dismissedLoopIDs.contains(key)
            )
        }
    }

    private var outstandingLoops: Int {
        openLoops.filter { !$0.isDone }.count
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    briefingCard

                    if !topProjects.isEmpty {
                        queuePanel
                    }
                }
                .frame(maxWidth: 460)
                .padding(.horizontal, 20)
                .padding(.top, 18)
                .padding(.bottom, 36)
                .frame(maxWidth: .infinity)
            }
            .whisperShell()
            .quickIdeaToolbar()
            .navigationTitle("Today")
            .platformNavigationTitleDisplayMode(.large)
        }
    }

    private var briefingCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            headerSection
            divider
            nextSection
            divider
            loopsSection
        }
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [WhisperTheme.panelStrong, WhisperTheme.panel],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(WhisperTheme.border, lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.34), radius: 28, x: 0, y: 12)
    }

    private var divider: some View {
        Rectangle()
            .fill(WhisperTheme.border)
            .frame(height: 1)
    }

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(greeting)
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(WhisperTheme.ink)
                    Text(Date.now.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day().hour().minute()))
                        .font(.system(.caption, design: .monospaced).weight(.medium))
                        .foregroundStyle(WhisperTheme.mutedInk)
                }

                Spacer(minLength: 12)

                modeBadge(title: "BUILD", color: WhisperTheme.accent)
            }

            HStack(spacing: 8) {
                timeWindow(title: "Money", range: "06-09", color: WhisperTheme.success, isActive: false)
                timeWindow(title: "Build", range: "09-12:30", color: WhisperTheme.accent, isActive: true)
                timeWindow(title: "Practice", range: "13-15", color: WhisperTheme.warning, isActive: false)
            }
        }
        .padding(20)
    }

    private var nextSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("NEXT")
                .font(.system(.caption2, design: .monospaced).weight(.bold))
                .tracking(1)
                .foregroundStyle(WhisperTheme.mutedInk)

            if let nextProject {
                NavigationLink {
                    ProjectDetailView(project: nextProject)
                } label: {
                    HStack(spacing: 14) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("\(topProjects.first?.score ?? 0)")
                                .font(.system(.title3, design: .monospaced).weight(.bold))
                                .foregroundStyle(WhisperTheme.accent)
                            Text("score")
                                .font(.system(.caption2, design: .monospaced))
                                .foregroundStyle(WhisperTheme.mutedInk)
                        }
                        .frame(width: 54)

                        Rectangle()
                            .fill(WhisperTheme.border)
                            .frame(width: 1)

                        VStack(alignment: .leading, spacing: 4) {
                            Text(displayName(for: nextProject))
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(WhisperTheme.ink)
                                .lineLimit(2)
                            Text(nextSubtitle(for: nextProject))
                                .font(.caption)
                                .foregroundStyle(WhisperTheme.mutedInk)
                                .lineLimit(2)
                        }

                        Spacer(minLength: 8)

                        Text("Open")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(WhisperTheme.ink)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 7)
                            .background(WhisperTheme.sidebarSelected, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    }
                    .padding(12)
                    .background(WhisperTheme.input, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(WhisperTheme.border, lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)
            } else {
                WhisperEmptyState(
                    icon: "checkmark.circle",
                    title: "Nothing pressing",
                    message: "Once projects are tracked, Today will surface the next move automatically."
                )
            }
        }
        .padding(20)
    }

    private var loopsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Text("OPEN LOOPS")
                    .font(.system(.caption2, design: .monospaced).weight(.bold))
                    .tracking(1)
                    .foregroundStyle(WhisperTheme.mutedInk)
                Text("\(outstandingLoops)")
                    .font(.system(.caption2, design: .monospaced).weight(.medium))
                    .foregroundStyle(WhisperTheme.mutedInk)
            }

            if openLoops.isEmpty {
                Text("No open loops yet.")
                    .font(.subheadline)
                    .foregroundStyle(WhisperTheme.mutedInk)
            } else {
                ForEach(openLoops) { loop in
                    Button {
                        toggle(loop)
                    } label: {
                        HStack(spacing: 12) {
                            ZStack {
                                RoundedRectangle(cornerRadius: 5, style: .continuous)
                                    .fill(loop.isDone ? WhisperTheme.accent : Color.clear)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 5, style: .continuous)
                                            .stroke(loop.isDone ? WhisperTheme.accent : WhisperTheme.border, lineWidth: 1.5)
                                    )
                                if loop.isDone {
                                    Image(systemName: "checkmark")
                                        .font(.system(size: 10, weight: .bold))
                                        .foregroundStyle(.white)
                                }
                            }
                            .frame(width: 18, height: 18)

                            Text(loop.text)
                                .font(.subheadline)
                                .foregroundStyle(loop.isDone ? WhisperTheme.mutedInk : WhisperTheme.ink)
                                .strikethrough(loop.isDone, color: WhisperTheme.mutedInk)
                                .frame(maxWidth: .infinity, alignment: .leading)

                            Text(loop.tag)
                                .font(.system(.caption2, design: .monospaced).weight(.bold))
                                .foregroundStyle(loop.color.opacity(0.95))
                                .padding(.horizontal, 8)
                                .padding(.vertical, 5)
                                .background(loop.color.opacity(0.14), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                        }
                        .padding(.vertical, 4)
                    }
                    .buttonStyle(.plain)
                }
            }

            HStack {
                Text("Capture a new idea")
                    .font(.caption)
                    .foregroundStyle(WhisperTheme.mutedInk)
                Spacer()
                Text("⌘I")
                    .font(.system(.caption2, design: .monospaced).weight(.medium))
                    .foregroundStyle(WhisperTheme.mutedInk)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 4)
                    .background(WhisperTheme.sidebarSelected, in: RoundedRectangle(cornerRadius: 5, style: .continuous))
            }
            .padding(.top, 10)
        }
        .padding(20)
    }

    private var queuePanel: some View {
        VStack(alignment: .leading, spacing: 14) {
            WhisperSectionTitle(
                eyebrow: "Execution queue",
                title: "What still needs motion",
                detail: "\(activeProjects) active projects across the current brief."
            )

            ForEach(Array(topProjects.dropFirst().prefix(3).enumerated()), id: \.element.project.id) { index, item in
                NavigationLink {
                    ProjectDetailView(project: item.project)
                } label: {
                    HStack(alignment: .top, spacing: 12) {
                        Text("\(index + 2)")
                            .font(.system(.subheadline, design: .monospaced).weight(.bold))
                            .foregroundStyle(WhisperTheme.accent)
                            .frame(width: 26, alignment: .leading)

                        VStack(alignment: .leading, spacing: 5) {
                            Text(displayName(for: item.project))
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(WhisperTheme.ink)
                            Text(item.explanation)
                                .font(.caption)
                                .foregroundStyle(WhisperTheme.mutedInk)
                                .lineLimit(2)
                        }

                        Spacer(minLength: 10)

                        Image(systemName: "arrow.up.right")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(WhisperTheme.accent)
                    }
                    .padding(12)
                    .background(WhisperTheme.input, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                .buttonStyle(.plain)
            }
        }
        .whisperPanel(padding: 16, radius: 18)
    }

    private func modeBadge(title: String, color: Color) -> some View {
        HStack(spacing: 6) {
            Circle()
                .fill(color)
                .frame(width: 6, height: 6)
            Text(title)
                .font(.system(.caption2, design: .monospaced).weight(.bold))
                .tracking(0.8)
        }
        .foregroundStyle(color.opacity(0.95))
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(color.opacity(0.14), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(color.opacity(0.28), lineWidth: 1)
        )
    }

    private func timeWindow(title: String, range: String, color: Color, isActive: Bool) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 6) {
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(color)
                    .frame(width: 6, height: 6)
                Text(title.uppercased())
                    .font(.system(.caption2, design: .monospaced).weight(.bold))
                    .tracking(0.7)
            }
            Text(range)
                .font(.system(.caption2, design: .monospaced).weight(.medium))
                .foregroundStyle(isActive ? color.opacity(0.9) : WhisperTheme.mutedInk)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 10)
        .padding(.vertical, 9)
        .background(isActive ? color.opacity(0.12) : WhisperTheme.input.opacity(0.84), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .stroke(isActive ? color.opacity(0.28) : WhisperTheme.border, lineWidth: 1)
        )
        .opacity(isActive ? 1 : 0.72)
    }

    private func toggle(_ loop: TodayLoop) {
        if dismissedLoopIDs.contains(loop.id) {
            dismissedLoopIDs.remove(loop.id)
        } else {
            dismissedLoopIDs.insert(loop.id)
        }
    }

    private var greeting: String {
        let hour = Calendar.current.component(.hour, from: .now)
        switch hour {
        case ..<12: return "Good morning, Emmanuel"
        case 12..<17: return "Good afternoon, Emmanuel"
        default: return "Good evening, Emmanuel"
        }
    }

    private func displayName(for project: Project) -> String {
        let trimmed = project.name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Untitled project" : trimmed
    }

    private func nextSubtitle(for project: Project) -> String {
        let action = project.nextAction.trimmingCharacters(in: .whitespacesAndNewlines)
        if action.isEmpty {
            return "\(project.status.rawValue.capitalized) \(project.category.rawValue.capitalized) project. Next action still undefined."
        }
        return action
    }

    private func initials(for text: String) -> String {
        let letters = text
            .split(whereSeparator: { $0.isWhitespace || $0 == "&" || $0 == "-" })
            .prefix(2)
            .compactMap(\.first)
            .map { String($0).uppercased() }
            .joined()
        return letters.isEmpty ? "RC" : letters
    }
}

private struct TodayLoop: Identifiable {
    let id: String
    let text: String
    let tag: String
    let color: Color
    let isDone: Bool
}

#Preview {
    TodayView()
        .modelContainer(for: Project.self, inMemory: true)
}
