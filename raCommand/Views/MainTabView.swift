//
//  MainTabView.swift
//  raCommand
//
//  Linear-style app shell with sidebar navigation and shared route state.
//

import SwiftUI
import SwiftData
import UniformTypeIdentifiers

private enum ShellSection: String, CaseIterable, Identifiable {
    case projects
    case repos
    case pulse
    case today
    case settings

    var id: String { rawValue }

    var title: String {
        switch self {
        case .projects: return "Projects"
        case .repos: return "Repos"
        case .pulse: return "Pulse"
        case .today: return "Today"
        case .settings: return "Settings"
        }
    }

    var shortcut: String? {
        switch self {
        case .projects: return "⌘1"
        case .repos: return "⌘2"
        case .pulse: return "⌘3"
        case .today: return "⌘4"
        case .settings: return nil
        }
    }

    var purpose: String {
        switch self {
        case .projects:
            return "Command board for active client work and the next clear move."
        case .repos:
            return "Local mirror manager and Codex workspace surface."
        case .pulse:
            return "Ranked urgency and AI next-step advisor."
        case .today:
            return "Daily briefing loop for open work and immediate actions."
        case .settings:
            return "App memory, build log, and idea inbox."
        }
    }
}

struct MainTabView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Project.lastUpdated, order: .reverse) private var projects: [Project]
    @Query private var appMetas: [AppMeta]

    @State private var activeSection: ShellSection = .projects
    @State private var selectedProjectKey: String?
    @State private var detailTab: ProjectDetailWorkbenchTab = .notes
    @State private var projectSearch = ""
    @State private var showQuickIdea = false
    @State private var quickIdeaConfirmation: String?

    @State private var showAdd = false
    @State private var showCSVImporter = false
    @State private var showJSONImporter = false
    @State private var showPasteSheet = false
    @State private var showGitHubSheet = false
    @State private var showPreview = false
    @State private var previewTitle = ""
    @State private var previewRows: [ProjectImportRow] = []
    @State private var importErrorMessage: String?

    private var filteredProjects: [Project] {
        let base = projectSearch.isEmpty ? projects : projects.filter {
            $0.name.localizedCaseInsensitiveContains(projectSearch) ||
            $0.clientName.localizedCaseInsensitiveContains(projectSearch)
        }
        return base.sorted { lhs, rhs in
            if lhs.isActiveThread != rhs.isActiveThread {
                return lhs.isActiveThread && !rhs.isActiveThread
            }
            return lhs.lastUpdated > rhs.lastUpdated
        }
    }

    private var selectedProject: Project? {
        guard let selectedProjectKey else { return nil }
        return projects.first(where: { projectKey(for: $0) == selectedProjectKey })
    }

    var body: some View {
        HStack(spacing: 0) {
            sidebar
            mainContent
        }
        .background(WhisperTheme.canvasTop)
        .whisperShell()
        .sheet(isPresented: $showAdd) { AddProjectView() }
        .sheet(isPresented: $showPasteSheet) {
            PasteImportView { rows in
                previewTitle = "Paste Preview"
                previewRows = rows
                showPreview = true
            }
        }
        .sheet(isPresented: $showGitHubSheet) { GitHubImportView() }
        .sheet(isPresented: $showPreview) {
            ProjectImportPreviewView(title: previewTitle, rows: previewRows) {
                _ = ProjectImportService.insert(rows: previewRows, into: modelContext)
            }
        }
        .fileImporter(isPresented: $showCSVImporter, allowedContentTypes: [.commaSeparatedText, .plainText]) { result in
            handleFileImport(result, kind: .csv)
        }
        .fileImporter(isPresented: $showJSONImporter, allowedContentTypes: [.json]) { result in
            handleFileImport(result, kind: .json)
        }
        .alert("Import Error", isPresented: Binding(
            get: { importErrorMessage != nil },
            set: { if !$0 { importErrorMessage = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(importErrorMessage ?? "")
        }
        .task { seedIfNeeded() }
    }

    private var sidebar: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 10) {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [Color(red: 0.176, green: 0.361, blue: 0.769), Color(red: 0.102, green: 0.227, blue: 0.525)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 32, height: 32)
                        .overlay {
                            Text("r")
                                .font(.system(size: 16, weight: .bold))
                                .foregroundStyle(Color(red: 0.875, green: 0.910, blue: 1.000))
                        }

                    VStack(alignment: .leading, spacing: 1) {
                        Text("raCommand")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(WhisperTheme.ink)
                        Text("Readyaimgo")
                            .font(.system(size: 11))
                            .foregroundStyle(Color(red: 0.361, green: 0.380, blue: 0.416))
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.top, 18)
            .padding(.bottom, 16)

            VStack(spacing: 1) {
                ForEach([ShellSection.projects, .repos, .pulse, .today], id: \.self) { section in
                    sidebarButton(for: section)
                }
            }
            .padding(.horizontal, 6)

            Spacer(minLength: 0)

            VStack(spacing: 0) {
                sidebarButton(for: .settings)
            }
            .padding(.horizontal, 6)
            .padding(.bottom, 12)
        }
        .frame(width: 224)
        .background(WhisperTheme.sidebar)
        .overlay(alignment: .trailing) {
            Rectangle()
                .fill(Color.white.opacity(0.06))
                .frame(width: 1)
        }
    }

    private func sidebarButton(for section: ShellSection) -> some View {
        let isActive = activeSection == section

        return Button {
            activate(section)
        } label: {
            HStack(spacing: 11) {
                RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                    .fill(isActive ? WhisperTheme.accent : (section == .settings ? Color(red: 0.247, green: 0.263, blue: 0.290) : Color(red: 0.361, green: 0.380, blue: 0.416)))
                    .frame(width: 5, height: 5)

                Text(section.title)
                    .font(.system(size: 13, weight: isActive ? .medium : .regular))
                    .foregroundStyle(isActive ? WhisperTheme.ink : Color(red: 0.655, green: 0.671, blue: 0.702))

                Spacer(minLength: 8)

                if let shortcut = section.shortcut, !isActive {
                    Text(shortcut)
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .foregroundStyle(Color(red: 0.435, green: 0.455, blue: 0.490))
                }
            }
            .padding(.horizontal, 10)
            .frame(height: 36)
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(isActive ? WhisperTheme.sidebarSelected : .clear)
            )
            .overlay(alignment: .leading) {
                if isActive {
                    RoundedRectangle(cornerRadius: 2, style: .continuous)
                        .fill(WhisperTheme.accent)
                        .frame(width: 2)
                        .padding(.vertical, 6)
                }
            }
        }
        .buttonStyle(.plain)
        .applyShellShortcut(for: section)
    }

    private var mainContent: some View {
        ZStack {
            VStack(spacing: 0) {
                topBar

                if activeSection == .repos {
                    RepoManagerView()
                } else {
                    ScrollView {
                        Group {
                            switch activeSection {
                            case .projects:
                                if let selectedProject {
                                    ProjectDetailView(
                                        project: selectedProject,
                                        detailTab: $detailTab,
                                        onBack: { selectedProjectKey = nil }
                                    )
                                } else {
                                    ProjectListView(
                                        projects: filteredProjects,
                                        searchText: $projectSearch,
                                        onSelectProject: openProject,
                                        onCreateProject: { showAdd = true },
                                        onImportCSV: { showCSVImporter = true },
                                        onImportJSON: { showJSONImporter = true },
                                        onPasteList: { showPasteSheet = true },
                                        onImportGitHub: { showGitHubSheet = true },
                                        onDeleteProject: deleteProject
                                    )
                                }
                            case .today:
                                TodayView(
                                    projects: projects,
                                    onOpenProject: openProject,
                                    onCaptureIdea: { showQuickIdea = true }
                                )
                            case .repos:
                                EmptyView()
                            case .pulse:
                                ShellStubView(
                                    title: "Pulse",
                                    detail: "Ranked urgency and AI next-step advisor.",
                                    eyebrow: "v1.1",
                                    description: "Pulse will inherit this shell once the core workflow is proven. For now, the redesign keeps the destination visible without carrying forward the legacy dashboard."
                                )
                            case .settings:
                                ShellStubView(
                                    title: "Settings",
                                    detail: "App memory, build log, and idea inbox.",
                                    eyebrow: "v1.1",
                                    description: "Settings remains part of the shell so the information architecture is stable, but the redesign of app memory and logs follows the MVP release."
                                )
                            }
                        }
                        .padding(.horizontal, 32)
                        .padding(.vertical, 32)
                    }
                }
            }

            if showQuickIdea {
                Color.black.opacity(0.62)
                    .ignoresSafeArea()
                    .overlay {
                        QuickIdeaView(
                            onSaved: { client in
                                quickIdeaConfirmation = "Saved to \(client.displayName)"
                                showQuickIdea = false
                                DispatchQueue.main.asyncAfter(deadline: .now() + 2.2) {
                                    quickIdeaConfirmation = nil
                                }
                            },
                            onClose: { showQuickIdea = false },
                            embedded: true
                        )
                    }
            }

            if let quickIdeaConfirmation {
                VStack {
                    Spacer()
                    ShellConfirmationBanner(message: quickIdeaConfirmation)
                        .padding(.bottom, 18)
                }
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.easeInOut(duration: 0.2), value: showQuickIdea)
        .animation(.easeInOut(duration: 0.2), value: quickIdeaConfirmation != nil)
    }

    private var topBar: some View {
        HStack(spacing: 16) {
            Spacer(minLength: 0)

            Button {
                showQuickIdea = true
            } label: {
                HStack(spacing: 8) {
                    Text("✦")
                        .font(.system(size: 12, weight: .medium))
                    Text("Quick Idea")
                        .font(.system(size: 12, weight: .medium))
                    Text("⌘I")
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .foregroundStyle(Color(red: 0.435, green: 0.455, blue: 0.490))
                }
                .padding(.horizontal, 12)
                .frame(height: 28)
                .background(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(Color.white.opacity(0.05))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .stroke(Color.white.opacity(0.08), lineWidth: 1)
                )
                .foregroundStyle(Color(red: 0.765, green: 0.780, blue: 0.804))
            }
            .buttonStyle(.plain)
            .keyboardShortcut("i", modifiers: [.command])
        }
        .padding(.horizontal, 24)
        .frame(height: 44)
        .background(Color(red: 0.051, green: 0.055, blue: 0.063))
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Color.white.opacity(0.06))
                .frame(height: 1)
        }
    }

    private func projectKey(for project: Project) -> String {
        String(describing: project.persistentModelID)
    }

    private func openProject(_ project: Project) {
        activeSection = .projects
        selectedProjectKey = projectKey(for: project)
        detailTab = .notes
    }

    private func activate(_ section: ShellSection) {
        activeSection = section
        if section != .projects {
            detailTab = .notes
        }
    }

    private func deleteProject(_ project: Project) {
        if selectedProjectKey == projectKey(for: project) {
            selectedProjectKey = nil
        }
        modelContext.delete(project)
    }

    private func seedIfNeeded() {
        guard appMetas.isEmpty else { return }
        modelContext.insert(AppMeta(
            appDescription: "Project command center for Readyaimgo.",
            currentFocus: "",
            updatedAt: Date()
        ))
        modelContext.insert(BuildNote(
            versionString: "0",
            buildNumber: "0",
            date: Date(),
            summary: "Initial build",
            changes: "Placeholder.",
            nextSteps: "Add your roadmap items."
        ))
    }

    private enum ImportKind { case csv, json }

    private func handleFileImport(_ result: Result<URL, Error>, kind: ImportKind) {
        do {
            let url = try result.get()
            let needsAccess = url.startAccessingSecurityScopedResource()
            defer { if needsAccess { url.stopAccessingSecurityScopedResource() } }
            let data = try Data(contentsOf: url)
            let rows: [ProjectImportRow]
            switch kind {
            case .csv:
                rows = try ProjectImportService.parseCSV(data: data)
                previewTitle = "CSV Preview"
            case .json:
                rows = try ProjectImportService.parseJSON(data: data)
                previewTitle = "JSON Preview"
            }
            previewRows = rows
            showPreview = true
        } catch {
            importErrorMessage = (error as? ProjectImportError)?.errorDescription ?? "Unable to import that file."
        }
    }
}

private extension View {
    @ViewBuilder
    func applyShellShortcut(for section: ShellSection) -> some View {
        switch section {
        case .projects:
            keyboardShortcut("1", modifiers: [.command])
        case .repos:
            keyboardShortcut("2", modifiers: [.command])
        case .pulse:
            keyboardShortcut("3", modifiers: [.command])
        case .today:
            keyboardShortcut("4", modifiers: [.command])
        case .settings:
            self
        }
    }
}

private struct ShellStubView: View {
    let title: String
    let detail: String
    let eyebrow: String
    let description: String

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 24, weight: .bold))
                    .foregroundStyle(WhisperTheme.ink)
                Text(detail)
                    .font(.system(size: 13))
                    .foregroundStyle(Color(red: 0.541, green: 0.561, blue: 0.596))
            }

            VStack(alignment: .leading, spacing: 12) {
                Text(eyebrow.uppercased())
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .foregroundStyle(WhisperTheme.accent)

                Text(description)
                    .font(.system(size: 13))
                    .foregroundStyle(Color(red: 0.765, green: 0.780, blue: 0.804))
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: 540, alignment: .leading)
            .whisperPanel(padding: 16, radius: 11)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct ShellConfirmationBanner: View {
    let message: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(WhisperTheme.success)
            Text(message)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(WhisperTheme.ink)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(WhisperTheme.panel, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(WhisperTheme.success.opacity(0.2), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.12), radius: 16, x: 0, y: 6)
    }
}

#Preview {
    MainTabView()
        .modelContainer(for: [Project.self, AppMeta.self, BuildNote.self, VoiceNote.self, IdeaNote.self], inMemory: true)
}
