//
//  TodayView.swift
//  raCommand
//
//  Focus board for the next concrete actions.
//

import SwiftUI
import SwiftData

struct TodayView: View {
    @Query(sort: \Project.lastUpdated, order: .reverse) private var projects: [Project]

    private var topProjects: [(project: Project, score: Int, explanation: String)] {
        PriorityEngine.getTopProjects(projects, limit: 6)
    }

    private var gridColumns: [GridItem] {
        [GridItem(.adaptive(minimum: 320, maximum: 440), spacing: 16, alignment: .top)]
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 18) {
                    hero

                    if topProjects.isEmpty {
                        WhisperEmptyState(
                            icon: "checkmark.circle",
                            title: "No actions staged",
                            message: "Once projects exist, Today turns the top priorities into a sharper action list."
                        )
                    } else {
                        WhisperSectionTitle(
                            eyebrow: "Execution queue",
                            title: "What to push today",
                            detail: "Direct links into the projects that need the clearest next action."
                        )
                        .padding(.horizontal, 4)

                        LazyVGrid(columns: gridColumns, spacing: 16) {
                            ForEach(Array(topProjects.enumerated()), id: \.element.project.id) { index, item in
                                NavigationLink {
                                    ProjectDetailView(project: item.project)
                                } label: {
                                    ActionCard(
                                        project: item.project,
                                        rank: index + 1,
                                        explanation: item.explanation
                                    )
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 14)
                .padding(.bottom, 36)
            }
            .whisperShell()
            .navigationTitle("Today")
            .platformNavigationTitleDisplayMode(.large)
        }
    }

    private var hero: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 8) {
                Text("FOCUS BOARD")
                    .font(.caption2.weight(.bold))
                    .tracking(1.4)
                    .foregroundStyle(WhisperTheme.accent)
                Text("Turn ranked work into clear actions.")
                    .font(.system(.largeTitle, design: .rounded).weight(.bold))
                    .foregroundStyle(WhisperTheme.ink)
                Text("Today compresses the priority stack into action cards you can open and work from immediately.")
                    .font(.subheadline)
                    .foregroundStyle(WhisperTheme.mutedInk)
            }

            HStack(spacing: 12) {
                WhisperMetricPill(label: "Queued", value: "\(topProjects.count)", tone: WhisperTheme.info)
                WhisperMetricPill(label: "Missing next step", value: "\(topProjects.filter { $0.project.nextAction.isEmpty }.count)", tone: WhisperTheme.warning)
            }
        }
        .whisperPanel(padding: 20, radius: 28)
    }
}

struct ActionCard: View {
    let project: Project
    let rank: Int
    let explanation: String

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 12) {
                Text("\(rank)")
                    .font(.system(.headline, design: .rounded).weight(.bold))
                    .foregroundStyle(.white)
                    .frame(width: 38, height: 38)
                    .background(rankColor, in: Circle())

                VStack(alignment: .leading, spacing: 8) {
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

                Image(systemName: "arrow.up.right")
                    .font(.footnote.weight(.bold))
                    .foregroundStyle(WhisperTheme.accent)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Next action")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(WhisperTheme.mutedInk)
                Text(project.nextAction.isEmpty ? "Define the next action for this project." : project.nextAction)
                    .font(.subheadline)
                    .foregroundStyle(project.nextAction.isEmpty ? WhisperTheme.warning : WhisperTheme.ink)
                    .lineLimit(3)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(project.nextAction.isEmpty ? WhisperTheme.warning.opacity(0.08) : WhisperTheme.success.opacity(0.08), in: RoundedRectangle(cornerRadius: 18, style: .continuous))

            Text(explanation)
                .font(.caption)
                .foregroundStyle(WhisperTheme.mutedInk)
                .lineLimit(2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .whisperPanel()
    }

    private var rankColor: Color {
        switch rank {
        case 1: return WhisperTheme.accent
        case 2: return WhisperTheme.warning
        case 3: return WhisperTheme.info
        default: return WhisperTheme.mutedInk
        }
    }
}

#Preview {
    TodayView()
        .modelContainer(for: Project.self, inMemory: true)
}
