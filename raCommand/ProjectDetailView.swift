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
    @Bindable var project: Project
    @Binding var detailTab: ProjectDetailWorkbenchTab
    let onBack: () -> Void

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
