//
//  AIThreadsView.swift
//  raCommand
//
//  Native AI thread browser. Surfaces every thread the AIThreadRegistry
//  knows about, grouped by project / client / source.
//
//  Distinct from IntelligenceFeedView (which shows distilled
//  ragIntelligence summaries). This view shows the raw thread
//  catalogue — transcripts, sessions, and continuations.
//

import SwiftUI
import SwiftData

struct AIThreadsView: View {
    @Query private var projects: [Project]
    @StateObject private var registry = AIThreadRegistry()
    @State private var selectedThread: AIThreadRecord?
    @State private var searchText = ""
    @State private var sourceFilter: AIThreadSource? = nil

    var body: some View {
        NavigationSplitView {
            sidebar
        } detail: {
            if let thread = selectedThread {
                AIThreadDetailView(thread: thread)
            } else {
                ContentUnavailableView(
                    "Select a thread",
                    systemImage: "bubble.left.and.bubble.right",
                    description: Text("Discovered Claude Code, imported chats, and raCommand continuations appear here.")
                )
            }
        }
        .searchable(text: $searchText, prompt: "Search threads")
        .toolbar { toolbar }
        .navigationTitle("AI Threads")
        .task { await refresh() }
    }

    // MARK: Sidebar

    private var sidebar: some View {
        Group {
            if registry.isLoading && registry.threads.isEmpty {
                ProgressView("Indexing local Claude Code transcripts…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let err = registry.lastError {
                ContentUnavailableView {
                    Label("Index error", systemImage: "exclamationmark.triangle")
                } description: {
                    Text(err)
                } actions: {
                    Button("Retry") { Task { await refresh() } }
                }
            } else if filteredGroups.isEmpty {
                ContentUnavailableView(
                    "No threads",
                    systemImage: "tray",
                    description: Text("Open a Claude Code session in any workspace, or import a Claude data export from Settings.")
                )
            } else {
                List(selection: $selectedThread) {
                    ForEach(filteredGroups, id: \.key) { group in
                        Section(group.label) {
                            ForEach(group.threads) { thread in
                                ThreadRow(thread: thread).tag(thread)
                            }
                        }
                    }
                }
            }
        }
        .frame(minWidth: 320)
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .primaryAction) {
            Menu {
                Button("All sources") { sourceFilter = nil }
                Divider()
                ForEach(AIThreadSource.allCases) { src in
                    Button(src.displayLabel) { sourceFilter = src }
                }
            } label: {
                Label(sourceFilter?.displayLabel ?? "All", systemImage: "line.3.horizontal.decrease.circle")
            }
        }
        ToolbarItem(placement: .primaryAction) {
            Button {
                Task { await refresh() }
            } label: {
                Label("Refresh", systemImage: "arrow.clockwise")
            }
            .disabled(registry.isLoading)
        }
    }

    // MARK: Helpers

    private var filteredGroups: [(key: String, label: String, threads: [AIThreadRecord])] {
        let q = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return registry.grouped.compactMap { group in
            let matched = group.threads.filter { thread in
                if let filter = sourceFilter, thread.source != filter { return false }
                guard !q.isEmpty else { return true }
                if thread.title.lowercased().contains(q) { return true }
                if thread.summary.lowercased().contains(q) { return true }
                if thread.workspacePath?.lowercased().contains(q) == true { return true }
                if thread.gitBranch?.lowercased().contains(q) == true { return true }
                return false
            }
            guard !matched.isEmpty else { return nil }
            return (key: group.key, label: group.label, threads: matched)
        }
    }

    private func refresh() async {
        registry.projects = projects
        await registry.refreshLocalClaudeCodeSessions()
    }
}

// MARK: - Row

private struct ThreadRow: View {
    let thread: AIThreadRecord

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline) {
                Text(thread.displayTitle)
                    .font(.headline)
                    .lineLimit(2)
                Spacer()
                SourceBadge(source: thread.source)
            }
            if !thread.summary.isEmpty, thread.summary != thread.title {
                Text(thread.summary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            HStack(spacing: 8) {
                if let branch = thread.gitBranch {
                    Label(branch, systemImage: "arrow.triangle.branch").lineLimit(1)
                }
                if thread.messageCount > 0 {
                    Label("\(thread.messageCount)", systemImage: "text.bubble")
                }
                Spacer()
                if let date = thread.lastActivityAt {
                    Text(date.formatted(.relative(presentation: .named)))
                        .foregroundStyle(.tertiary)
                }
            }
            .font(.caption2)
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Source badge

struct SourceBadge: View {
    let source: AIThreadSource

    var body: some View {
        Text(source.displayLabel)
            .font(.caption2.bold())
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(color.opacity(0.15), in: Capsule())
            .foregroundStyle(color)
    }

    private var color: Color {
        switch source {
        case .claudeCode: return .indigo
        case .claudeChatExport: return .purple
        case .claudeChatSharedLink: return .pink
        case .claudeEnterpriseCompliance: return .teal
        case .anthropicAPI: return .orange
        case .codex: return .blue
        case .manual: return .secondary
        }
    }
}

#Preview {
    AIThreadsView()
        .modelContainer(for: [Project.self], inMemory: true)
}
