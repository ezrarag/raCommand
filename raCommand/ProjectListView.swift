//
//  ProjectListView.swift
//  raCommand
//
//  Linear-style project board for the app shell.
//

import SwiftUI

struct ProjectListView: View {
    let projects: [Project]
    @Binding var searchText: String
    let onSelectProject: (Project) -> Void
    let onCreateProject: () -> Void
    let onImportCSV: () -> Void
    let onImportJSON: () -> Void
    let onPasteList: () -> Void
    let onImportGitHub: () -> Void
    let onDeleteProject: (Project) -> Void

    private var gridColumns: [GridItem] {
        [GridItem(.adaptive(minimum: 300, maximum: 360), spacing: 14, alignment: .top)]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            header
            searchField

            if projects.isEmpty {
                WhisperEmptyState(
                    icon: searchText.isEmpty ? "folder.badge.plus" : "magnifyingglass",
                    title: searchText.isEmpty ? "No projects yet" : "No matches",
                    message: searchText.isEmpty
                        ? "Start with a project or import a working set to build the board."
                        : "Try a broader search or clear the filter."
                )
            } else {
                LazyVGrid(columns: gridColumns, spacing: 14) {
                    ForEach(projects) { project in
                        Button {
                            onSelectProject(project)
                        } label: {
                            ProjectCard(project: project)
                        }
                        .buttonStyle(.plain)
                        .contextMenu {
                            Button(role: .destructive) {
                                onDeleteProject(project)
                            } label: {
                                Label("Delete Project", systemImage: "trash")
                            }
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Workspaces")
                    .font(.system(size: 24, weight: .bold))
                    .foregroundStyle(Color(red: 0.941, green: 0.949, blue: 0.961))
                Text("\(projects.count) active workspace\(projects.count == 1 ? "" : "s")")
                    .font(.system(size: 13))
                    .foregroundStyle(Color(red: 0.541, green: 0.561, blue: 0.596))
            }

            Spacer(minLength: 16)

            HStack(spacing: 10) {
                Menu {
                    Button("Import CSV", action: onImportCSV)
                    Button("Import JSON", action: onImportJSON)
                    Button("Paste List", action: onPasteList)
                    Button("Import from GitHub", action: onImportGitHub)
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "square.and.arrow.down")
                        Text("Import")
                    }
                    .font(.system(size: 12, weight: .medium))
                    .padding(.horizontal, 12)
                    .frame(height: 32)
                    .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .stroke(Color.white.opacity(0.08), lineWidth: 1)
                    )
                }
                .menuStyle(.borderlessButton)
                .buttonStyle(.plain)

                Button(action: onCreateProject) {
                    HStack(spacing: 8) {
                        Text("+ New")
                        Text("⌘N")
                            .font(.system(size: 10, weight: .medium, design: .monospaced))
                            .foregroundStyle(Color.white.opacity(0.75))
                    }
                    .font(.system(size: 13, weight: .semibold))
                    .padding(.horizontal, 14)
                    .frame(height: 32)
                    .background(WhisperTheme.accent, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .foregroundStyle(.white)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var searchField: some View {
        ZStack(alignment: .leading) {
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(Color(red: 0.075, green: 0.078, blue: 0.090))
                .overlay(
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .stroke(Color.white.opacity(0.10), lineWidth: 1)
                )

            Image(systemName: "magnifyingglass")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Color(red: 0.361, green: 0.380, blue: 0.416))
                .padding(.leading, 12)

            TextField("Search workspaces…", text: $searchText)
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .foregroundStyle(WhisperTheme.ink)
                .padding(.leading, 38)
                .padding(.trailing, 12)
        }
        .frame(maxWidth: 360)
        .frame(height: 36)
    }
}

struct ProjectCard: View {
    let project: Project

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(displayName)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(WhisperTheme.ink)
                        .lineLimit(1)

                    Text(clientCode)
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundStyle(Color(red: 0.361, green: 0.380, blue: 0.416))
                }

                Spacer(minLength: 8)

                VStack(alignment: .trailing, spacing: 5) {
                    Text(statusLabel)
                        .font(.system(size: 10, weight: .semibold, design: .monospaced))
                        .padding(.horizontal, 7)
                        .frame(height: 20)
                        .background(project.status.whisperColor.opacity(0.14), in: RoundedRectangle(cornerRadius: 5, style: .continuous))
                        .foregroundStyle(project.status.whisperColor)

                    HStack(spacing: 4) {
                        Circle()
                            .fill(syncColor)
                            .frame(width: 6, height: 6)
                        Text(syncLabel)
                            .font(.system(size: 9, weight: .medium, design: .monospaced))
                            .foregroundStyle(syncColor)
                    }
                }
            }

            HStack(spacing: 8) {
                Circle()
                    .fill(Color(red: 0.541, green: 0.561, blue: 0.596))
                    .frame(width: 4, height: 4)

                Text(nextAction)
                    .font(.system(size: 12))
                    .foregroundStyle(Color(red: 0.765, green: 0.780, blue: 0.804))
                    .lineLimit(1)
            }
            .padding(8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.white.opacity(0.03), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(Color.white.opacity(0.05), lineWidth: 1)
            )

            HStack {
                Text(project.category.rawValue.capitalized)
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .padding(.horizontal, 7)
                    .frame(height: 18)
                    .background(WhisperTheme.accent.opacity(0.10), in: RoundedRectangle(cornerRadius: 5, style: .continuous))
                    .foregroundStyle(Color(red: 0.498, green: 0.690, blue: 1.000))

                Spacer(minLength: 8)

                Text(valueLabel)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color(red: 0.541, green: 0.561, blue: 0.596))
            }
            .padding(.top, 4)
        }
        .padding(16)
        .background(Color(red: 0.075, green: 0.078, blue: 0.090), in: RoundedRectangle(cornerRadius: 11, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        )
    }

    private var displayName: String {
        let trimmed = project.name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Untitled project" : trimmed
    }

    private var clientCode: String {
        let trimmed = project.clientName.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "NO CLIENT" : trimmed.uppercased()
    }

    private var statusLabel: String {
        switch project.status {
        case .green: return "LIVE"
        case .yellow: return "BUILD"
        case .red: return "BLOCKED"
        }
    }

    private var nextAction: String {
        let trimmed = project.nextAction.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Define the next action." : trimmed
    }

    private var valueLabel: String {
        "V\(project.valueScore)"
    }

    private var syncLabel: String {
        switch project.workspaceSyncStatus ?? .local {
        case .local: return "NEVER"
        case .pending: return "PENDING"
        case .synced: return "SYNCED"
        case .error: return "ERROR"
        }
    }

    private var syncColor: Color {
        switch project.workspaceSyncStatus ?? .local {
        case .local: return WhisperTheme.mutedInk
        case .pending: return WhisperTheme.warning
        case .synced: return WhisperTheme.success
        case .error: return WhisperTheme.danger
        }
    }
}
