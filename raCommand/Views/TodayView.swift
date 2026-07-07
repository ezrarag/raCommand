//
//  TodayView.swift
//  raCommand
//
//  Linear-style daily briefing with project deep links through the shell.
//

import SwiftUI

struct TodayView: View {
    let projects: [Project]
    let onOpenProject: (Project) -> Void
    let onCaptureIdea: () -> Void

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
        VStack(alignment: .leading, spacing: 18) {
            briefingCard

            if !topProjects.isEmpty {
                queuePanel
            }
        }
        .frame(maxWidth: 428, alignment: .leading)
        .frame(maxWidth: .infinity)
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
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [WhisperTheme.panelStrong, WhisperTheme.panel],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(WhisperTheme.border, lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.34), radius: 24, x: 0, y: 10)
    }

    private var divider: some View {
        Rectangle()
            .fill(WhisperTheme.border)
            .frame(height: 1)
    }

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(greeting)
                        .font(.system(size: 20, weight: .bold))
                        .foregroundStyle(WhisperTheme.ink)
                    Text(Date.now.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day().hour().minute()))
                        .font(.system(size: 12, weight: .medium, design: .monospaced))
                        .foregroundStyle(WhisperTheme.mutedInk)
                }

                Spacer(minLength: 12)

                modeBadge(title: "BUILD", color: WhisperTheme.accent)
            }

            HStack(spacing: 6) {
                timeWindow(title: "MONEY", range: "06–09", color: WhisperTheme.success, isActive: false, flex: 1.0)
                timeWindow(title: "BUILD", range: "09–12:30 · now", color: WhisperTheme.accent, isActive: true, flex: 1.15)
                timeWindow(title: "PRACTICE", range: "13–15", color: WhisperTheme.warning, isActive: false, flex: 1.0)
            }
        }
        .padding(20)
    }

    private var nextSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("NEXT")
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .foregroundStyle(WhisperTheme.mutedInk)

            if let nextProject {
                Button {
                    onOpenProject(nextProject)
                } label: {
                    HStack(spacing: 13) {
                        VStack(alignment: .center, spacing: 2) {
                            Text(nextScore)
                                .font(.system(size: 15, weight: .bold, design: .monospaced))
                                .foregroundStyle(WhisperTheme.accent)
                            Text("score")
                                .font(.system(size: 10, weight: .medium, design: .monospaced))
                                .foregroundStyle(Color(red: 0.361, green: 0.380, blue: 0.416))
                        }
                        .frame(width: 52)

                        Rectangle()
                            .fill(Color.white.opacity(0.07))
                            .frame(width: 1)

                        VStack(alignment: .leading, spacing: 3) {
                            Text(displayName(for: nextProject))
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(WhisperTheme.ink)
                                .lineLimit(1)
                            Text(nextSubtitle(for: nextProject))
                                .font(.system(size: 11))
                                .foregroundStyle(WhisperTheme.mutedInk)
                                .lineLimit(2)
                        }

                        Spacer(minLength: 8)

                        Text("Open")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(Color(red: 0.765, green: 0.780, blue: 0.804))
                            .padding(.horizontal, 10)
                            .frame(height: 26)
                            .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 7, style: .continuous)
                                    .stroke(Color.white.opacity(0.10), lineWidth: 1)
                            )
                    }
                    .padding(12)
                    .background(Color(red: 0.098, green: 0.102, blue: 0.118), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .stroke(Color.white.opacity(0.06), lineWidth: 1)
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
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Text("OPEN LOOPS")
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .foregroundStyle(WhisperTheme.mutedInk)
                Text("\(outstandingLoops)")
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundStyle(Color(red: 0.302, green: 0.322, blue: 0.357))
            }

            if openLoops.isEmpty {
                Text("No open loops yet.")
                    .font(.system(size: 13))
                    .foregroundStyle(WhisperTheme.mutedInk)
            } else {
                ForEach(openLoops) { loop in
                    Button {
                        toggle(loop)
                    } label: {
                        HStack(spacing: 11) {
                            ZStack {
                                RoundedRectangle(cornerRadius: 5, style: .continuous)
                                    .fill(loop.isDone ? WhisperTheme.accent : Color.clear)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 5, style: .continuous)
                                            .stroke(loop.isDone ? WhisperTheme.accent : Color.white.opacity(0.18), lineWidth: 1.5)
                                    )
                                if loop.isDone {
                                    Image(systemName: "checkmark")
                                        .font(.system(size: 10, weight: .bold))
                                        .foregroundStyle(.white)
                                }
                            }
                            .frame(width: 18, height: 18)

                            Text(loop.text)
                                .font(.system(size: 13))
                                .foregroundStyle(loop.isDone ? Color(red: 0.361, green: 0.380, blue: 0.416) : Color(red: 0.875, green: 0.886, blue: 0.902))
                                .strikethrough(loop.isDone, color: WhisperTheme.mutedInk)
                                .frame(maxWidth: .infinity, alignment: .leading)

                            Text(loop.tag)
                                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                                .padding(.horizontal, 7)
                                .frame(height: 18)
                                .background(loop.color.opacity(0.14), in: RoundedRectangle(cornerRadius: 5, style: .continuous))
                                .foregroundStyle(loop.color)
                        }
                        .padding(.vertical, 4)
                    }
                    .buttonStyle(.plain)
                }
            }

            Button(action: onCaptureIdea) {
                HStack {
                    Text("Capture a new idea")
                        .font(.system(size: 11))
                        .foregroundStyle(Color(red: 0.361, green: 0.380, blue: 0.416))
                    Spacer()
                    Text("⌘I")
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .foregroundStyle(WhisperTheme.mutedInk)
                        .padding(.horizontal, 6)
                        .frame(height: 18)
                        .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 5, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 5, style: .continuous)
                                .stroke(Color.white.opacity(0.08), lineWidth: 1)
                        )
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.top, 12)
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
                Button {
                    onOpenProject(item.project)
                } label: {
                    HStack(alignment: .top, spacing: 12) {
                        Text("\(index + 2)")
                            .font(.system(size: 12, weight: .bold, design: .monospaced))
                            .foregroundStyle(WhisperTheme.accent)
                            .frame(width: 26, alignment: .leading)

                        VStack(alignment: .leading, spacing: 5) {
                            Text(displayName(for: item.project))
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(WhisperTheme.ink)
                            Text(item.explanation)
                                .font(.system(size: 12))
                                .foregroundStyle(WhisperTheme.mutedInk)
                                .lineLimit(2)
                        }

                        Spacer(minLength: 10)

                        Image(systemName: "arrow.up.right")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(WhisperTheme.accent)
                    }
                    .padding(12)
                    .background(WhisperTheme.input, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
                .buttonStyle(.plain)
            }
        }
        .whisperPanel(padding: 16, radius: 14)
    }

    private func modeBadge(title: String, color: Color) -> some View {
        HStack(spacing: 6) {
            Circle()
                .fill(color)
                .frame(width: 6, height: 6)
            Text(title)
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
        }
        .foregroundStyle(color)
        .padding(.horizontal, 10)
        .frame(height: 24)
        .background(color.opacity(0.14), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .stroke(color.opacity(0.30), lineWidth: 1)
        )
    }

    private func timeWindow(title: String, range: String, color: Color, isActive: Bool, flex: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 6) {
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(color)
                    .frame(width: 6, height: 6)
                Text(title)
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .foregroundStyle(isActive ? Color(red: 0.498, green: 0.690, blue: 1.000) : Color(red: 0.541, green: 0.561, blue: 0.596))
            }

            Text(range)
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .foregroundStyle(isActive ? Color(red: 0.541, green: 0.706, blue: 1.000) : Color(red: 0.361, green: 0.380, blue: 0.416))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 9)
        .padding(.vertical, 8)
        .background(isActive ? color.opacity(0.10) : Color(red: 0.098, green: 0.102, blue: 0.118), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(isActive ? color.opacity(0.34) : Color.white.opacity(0.05), lineWidth: 1)
        )
        .opacity(isActive ? 1 : 0.62)
        .layoutPriority(flex)
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

    private var nextScore: String {
        "\(topProjects.first?.score ?? 0)"
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
