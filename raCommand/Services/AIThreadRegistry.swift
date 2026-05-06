//
//  AIThreadRegistry.swift
//  raCommand
//
//  Central observable that aggregates AI threads from every source lane
//  (Claude Code, imported Claude exports, Anthropic API continuations,
//  Codex, manual entries).
//
//  This is the in-app registry used by the Threads tab. Persisted records
//  (SwiftData / readyaimgo-admin sync) plug in via `merge(...)`.
//

import Foundation
import Combine

@MainActor
final class AIThreadRegistry: ObservableObject {

    // MARK: Published state

    @Published private(set) var threads: [AIThreadRecord] = []
    @Published private(set) var isLoading = false
    @Published private(set) var lastError: String?

    // MARK: Inputs

    /// Project list used for project/client/repo resolution.
    /// The view layer is expected to wire this each time SwiftData refreshes.
    var projects: [Project] = []

    // MARK: Lifecycle

    init() {}

    // MARK: - Discovery

    /// Walk every local Claude Code transcript and refresh the registry.
    func refreshLocalClaudeCodeSessions() async {
        isLoading = true
        lastError = nil
        defer { isLoading = false }

        do {
            let raw = try await Task.detached(priority: .utility) {
                try ClaudeCodeIndexer.indexAllSessions()
            }.value

            let resolved = raw.map { self.resolveProjectMapping(for: $0) }
            self.merge(records: resolved)
        } catch {
            self.lastError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    /// Replace any existing record that shares an id; otherwise append.
    func merge(records: [AIThreadRecord]) {
        var byId: [String: AIThreadRecord] = [:]
        for r in threads { byId[r.id] = r }
        for r in records { byId[r.id] = r }
        threads = byId.values.sorted {
            ($0.lastActivityAt ?? .distantPast) > ($1.lastActivityAt ?? .distantPast)
        }
    }

    /// Remove a thread (e.g. user-deleted continuation).
    func remove(threadId: String) {
        threads.removeAll { $0.id == threadId }
    }

    // MARK: - Grouping

    /// Returns threads grouped by `groupKey`, in recency order.
    var grouped: [(key: String, label: String, threads: [AIThreadRecord])] {
        var buckets: [String: [AIThreadRecord]] = [:]
        for t in threads {
            buckets[t.groupKey, default: []].append(t)
        }
        return buckets
            .map { (key, list) in
                let label = AIThreadRegistry.label(for: key, sample: list.first, projects: projects)
                return (key: key, label: label, threads: list)
            }
            .sorted { a, b in
                if a.key == "uncategorized" { return false }
                if b.key == "uncategorized" { return true }
                let aDate = a.threads.first?.lastActivityAt ?? .distantPast
                let bDate = b.threads.first?.lastActivityAt ?? .distantPast
                return aDate > bDate
            }
    }

    // MARK: - Project resolution

    /// Resolution order from CLAUDE.md:
    /// 1. exact workspacePath ↔ Project.localPath
    /// 2. exact repoURL / repo name ↔ Project.repoURL
    /// 3. exact projectId ↔ Project.clientFeedbackProjectId
    /// 4. exact/high-confidence client match ↔ Project.clientName
    /// 5. fallback similarity (mark inferred → confidence < 1.0)
    func resolveProjectMapping(for record: AIThreadRecord) -> AIThreadRecord {
        guard !projects.isEmpty else { return record }
        var out = record

        // 1. Workspace path
        if let workspace = record.workspacePath?.lowercased() {
            if let match = projects.first(where: { p in
                let lp = p.localPath.lowercased()
                guard !lp.isEmpty else { return false }
                return workspace == lp || workspace.hasPrefix(lp) || lp.hasPrefix(workspace)
            }) {
                out.projectId = match.clientFeedbackProjectId
                out.repoURL = match.repoURL.isEmpty ? out.repoURL : match.repoURL
                out.clientId = match.clientName.isEmpty ? out.clientId : match.clientName
                out.confidence = 1.0
                return out
            }
        }

        // 2. Repo URL / repo name match (workspace path may include repo name)
        if let workspace = record.workspacePath {
            for p in projects where !p.repoURL.isEmpty {
                if let repoName = repoName(from: p.repoURL),
                   !repoName.isEmpty,
                   workspace.lowercased().contains(repoName.lowercased()) {
                    out.projectId = p.clientFeedbackProjectId
                    out.repoURL = p.repoURL
                    out.clientId = p.clientName.isEmpty ? out.clientId : p.clientName
                    out.confidence = 0.9
                    return out
                }
            }
        }

        // 3. Title contains a project name
        let titleLower = record.title.lowercased()
        for p in projects {
            let name = p.name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            guard !name.isEmpty else { continue }
            if titleLower.contains(name) {
                out.projectId = p.clientFeedbackProjectId
                out.clientId = p.clientName.isEmpty ? out.clientId : p.clientName
                out.confidence = 0.7
                return out
            }
        }

        // 4. Client name in title
        for p in projects {
            let client = p.clientName.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            guard !client.isEmpty else { continue }
            if titleLower.contains(client) {
                out.clientId = p.clientName
                out.confidence = 0.5
                return out
            }
        }

        // 5. No match — keep record uncategorized.
        out.confidence = max(0.2, out.confidence * 0.5)
        return out
    }

    // MARK: - Helpers

    private func repoName(from repoURL: String) -> String? {
        let stripped = repoURL
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: ".git", with: "")
        guard let last = stripped.split(separator: "/").last else { return nil }
        return String(last)
    }

    private static func label(for key: String, sample: AIThreadRecord?, projects: [Project]) -> String {
        if key.hasPrefix("project:") {
            let id = String(key.dropFirst("project:".count))
            // Prefer human-readable project name if we have one.
            if let p = projects.first(where: { $0.clientFeedbackProjectId == id }) {
                return p.name
            }
            return sample?.projectId ?? id
        }
        if key.hasPrefix("client:") {
            let id = String(key.dropFirst("client:".count))
            return sample?.clientId ?? id
        }
        return "Uncategorized"
    }
}
