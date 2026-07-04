//
//  ProjectListView.swift
//  raCommand
//
//  Compact project command center with native macOS utility chrome.
//

import SwiftUI
import SwiftData
import UniformTypeIdentifiers

struct ProjectListView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \Project.lastUpdated, order: .reverse) private var projects: [Project]

    @State private var showAdd = false
    @State private var showCSVImporter = false
    @State private var showJSONImporter = false
    @State private var showPasteSheet = false
    @State private var showGitHubSheet = false
    @State private var showPreview = false
    @State private var previewTitle = ""
    @State private var previewRows: [ProjectImportRow] = []
    @State private var importErrorMessage: String?
    @State private var searchText = ""

    private var filteredProjects: [Project] {
        let base = searchText.isEmpty ? projects : projects.filter {
            $0.name.localizedCaseInsensitiveContains(searchText) ||
            $0.clientName.localizedCaseInsensitiveContains(searchText)
        }
        return base.sorted { lhs, rhs in
            if lhs.isActiveThread != rhs.isActiveThread {
                return lhs.isActiveThread && !rhs.isActiveThread
            }
            return lhs.lastUpdated > rhs.lastUpdated
        }
    }

    private var gridColumns: [GridItem] {
        [GridItem(.adaptive(minimum: 320, maximum: 440), spacing: 16, alignment: .top)]
    }

    private var summaryColumns: [GridItem] {
        [GridItem(.adaptive(minimum: 130, maximum: 180), spacing: 12)]
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 18) {
                    heroPanel

                    if projects.isEmpty {
                        WhisperEmptyState(
                            icon: "folder.badge.plus",
                            title: "No projects yet",
                            message: "Start with a single project or pull your repos in from GitHub to build the command desk."
                        )
                    } else if filteredProjects.isEmpty {
                        WhisperEmptyState(
                            icon: "magnifyingglass",
                            title: "No matches",
                            message: "Try a broader search or clear the filter to bring the full project board back."
                        )
                    } else {
                        WhisperSectionTitle(
                            eyebrow: "Live board",
                            title: "Project board",
                            detail: "\(filteredProjects.count) tracked projects. Active Codex threads float to the top."
                        )
                        .padding(.horizontal, 4)

                        LazyVGrid(columns: gridColumns, spacing: 16) {
                            ForEach(filteredProjects) { project in
                                NavigationLink {
                                    ProjectDetailView(project: project)
                                } label: {
                                    ProjectCard(project: project)
                                }
                                .buttonStyle(.plain)
                                .contextMenu {
                                    Button(role: .destructive) {
                                        delete(project)
                                    } label: {
                                        Label("Delete Project", systemImage: "trash")
                                    }
                                }
                            }
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 14)
                .padding(.bottom, 36)
            }
            .whisperShell()
            .quickIdeaToolbar()
            .navigationTitle("Projects")
            .platformNavigationTitleDisplayMode(.large)
            .platformSearchable(text: $searchText, prompt: "Search projects")
            .toolbar {
                ToolbarItemGroup(placement: .platformNavigationTrailing) {
                    Menu {
                        Button {
                            showCSVImporter = true
                        } label: {
                            Label("Import CSV", systemImage: "doc.text")
                        }
                        Button {
                            showJSONImporter = true
                        } label: {
                            Label("Import JSON", systemImage: "curlybraces")
                        }
                        Button {
                            showPasteSheet = true
                        } label: {
                            Label("Paste List", systemImage: "doc.on.clipboard")
                        }
                        Button {
                            showGitHubSheet = true
                        } label: {
                            Label("Import from GitHub", systemImage: "arrow.down.circle")
                        }
                    } label: {
                        Image(systemName: "square.and.arrow.down")
                    }

                    Button {
                        showAdd = true
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
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
                    _ = ProjectImportService.insert(rows: previewRows, into: context)
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
        }
    }

    private var heroPanel: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 8) {
                Text("COMMAND DESK")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(WhisperTheme.accent)
                Text("Projects and threads that need a clear next move.")
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(WhisperTheme.ink)
                Text("Tracked repos live here, and active Codex threads rise to the top so the board matches the actual workflow.")
                    .font(.callout)
                    .foregroundStyle(WhisperTheme.mutedInk)
            }

            LazyVGrid(columns: summaryColumns, spacing: 12) {
                WhisperMetricPill(label: "Total", value: "\(projects.count)", tone: WhisperTheme.info)
                WhisperMetricPill(label: "Threads", value: "\(projects.filter { $0.isActiveThread }.count)", tone: WhisperTheme.success)
                WhisperMetricPill(label: "Moving", value: "\(projects.filter { $0.status == .yellow }.count)", tone: WhisperTheme.warning)
                WhisperMetricPill(label: "Blocked", value: "\(projects.filter { $0.status == .red }.count)", tone: WhisperTheme.danger)
            }

            HStack(spacing: 8) {
                Label("Use search to narrow the board", systemImage: "magnifyingglass")
                Spacer(minLength: 12)
                Label("Long-press a card to delete", systemImage: "hand.tap")
            }
            .font(.caption.weight(.medium))
            .foregroundStyle(WhisperTheme.mutedInk)
        }
        .whisperPanel(padding: 16, radius: 10)
    }

    private func delete(_ project: Project) {
        context.delete(project)
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

struct ProjectCard: View {
    let project: Project

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 8) {
                        Circle()
                            .fill(project.status.whisperColor)
                            .frame(width: 9, height: 9)
                        Text(project.status.rawValue.capitalized)
                            .font(.caption.weight(.bold))
                            .foregroundStyle(project.status.whisperColor)
                    }

                    Text(project.name)
                        .font(.system(.title3, design: .rounded).weight(.bold))
                        .foregroundStyle(WhisperTheme.ink)
                        .multilineTextAlignment(.leading)
                }

                Spacer(minLength: 12)

                Text(project.category.rawValue.capitalized)
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(project.category.whisperColor)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(project.category.whisperColor.opacity(0.12), in: Capsule())
            }

            HStack(spacing: 14) {
                if !project.clientName.isEmpty {
                    Label(project.clientName, systemImage: "building.2")
                        .lineLimit(1)
                }

                Label(project.lastUpdated.formatted(date: .abbreviated, time: .omitted), systemImage: "clock")
                    .lineLimit(1)
            }
            .font(.caption.weight(.medium))
            .foregroundStyle(WhisperTheme.mutedInk)

            VStack(alignment: .leading, spacing: 8) {
                Text("Next move")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(WhisperTheme.mutedInk)
                Text(project.nextAction.isEmpty ? "Define the next action to keep this thread moving." : project.nextAction)
                    .font(.subheadline)
                    .foregroundStyle(project.nextAction.isEmpty ? WhisperTheme.mutedInk : WhisperTheme.ink)
                    .lineLimit(3)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .background(project.status.whisperColor.opacity(0.08), in: RoundedRectangle(cornerRadius: 18, style: .continuous))

            HStack(spacing: 10) {
                metaPill(icon: "star.fill", text: "V \(project.valueScore)", color: WhisperTheme.accent)

                if let targetDate = project.targetDate {
                    metaPill(icon: "calendar", text: targetDate.formatted(date: .abbreviated, time: .omitted), color: WhisperTheme.info)
                }

                if project.delegatable {
                    metaPill(icon: "arrow.triangle.branch", text: "Delegatable", color: WhisperTheme.success)
                }

                if project.isActiveThread {
                    metaPill(icon: "rectangle.stack", text: "Thread", color: WhisperTheme.info)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .whisperPanel()
    }

    private func metaPill(icon: String, text: String, color: Color) -> some View {
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
