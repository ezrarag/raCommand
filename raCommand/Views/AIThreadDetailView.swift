//
//  AIThreadDetailView.swift
//  raCommand
//
//  Detail view for a single AIThreadRecord.
//
//  Loads message content lazily — `Load Transcript` is a deliberate user
//  action, in line with the security/privacy contract that raw transcripts
//  are not pulled or surfaced silently.
//

import SwiftUI
#if os(macOS)
import AppKit
#endif

struct AIThreadDetailView: View {
    let thread: AIThreadRecord

    @State private var messages: [AIThreadMessageRecord] = []
    @State private var loadError: String?
    @State private var isLoading = false
    @State private var didLoad = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header
                Divider()
                metadataBox
                if !thread.summary.isEmpty {
                    GroupBox("Summary") {
                        Text(thread.summary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                actionsBox
                transcriptBox
            }
            .padding(24)
        }
        .navigationTitle(thread.displayTitle)
    }

    // MARK: Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(thread.displayTitle)
                .font(.title2.bold())
            HStack(spacing: 8) {
                SourceBadge(source: thread.source)
                CapabilityBadges(capabilities: thread.capabilities)
                Spacer()
                if let activity = thread.lastActivityAt {
                    Label(activity.formatted(date: .abbreviated, time: .shortened),
                          systemImage: "clock")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var metadataBox: some View {
        GroupBox("Metadata") {
            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 4) {
                metaRow("Thread ID", thread.id)
                if let ext = thread.externalId { metaRow("Session ID", ext) }
                if let workspace = thread.workspacePath { metaRow("Workspace", workspace) }
                if let branch = thread.gitBranch { metaRow("Git Branch", branch) }
                if let model = thread.model { metaRow("Model", model) }
                if let project = thread.projectId { metaRow("Project", project) }
                if let client = thread.clientId { metaRow("Client", client) }
                if let path = thread.localTranscriptPath { metaRow("Transcript", path) }
                metaRow("Confidence", String(format: "%.0f%%", thread.confidence * 100))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: Actions

    private var actionsBox: some View {
        GroupBox("Actions") {
            HStack(spacing: 12) {
                if thread.capabilities.contains(.canResumeOriginal),
                   let workspace = thread.workspacePath,
                   let session = thread.externalId {
                    Button {
                        resumeInTerminal(workspacePath: workspace, sessionId: session)
                    } label: {
                        Label("Resume in Terminal", systemImage: "terminal")
                    }
                }

                if thread.capabilities.contains(.canImportTranscript) {
                    Button {
                        Task { await loadTranscript() }
                    } label: {
                        Label(didLoad ? "Reload Transcript" : "Load Transcript",
                              systemImage: "doc.text")
                    }
                    .disabled(isLoading)
                }

                if let path = thread.localTranscriptPath {
                    Button {
                        revealInFinder(path: path)
                    } label: {
                        Label("Reveal JSONL", systemImage: "folder")
                    }
                }

                if let url = thread.sourceURL, let parsed = URL(string: url) {
                    Link(destination: parsed) {
                        Label("Open Original", systemImage: "arrow.up.right.square")
                    }
                }

                Spacer()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: Transcript

    private var transcriptBox: some View {
        GroupBox("Transcript") {
            if isLoading {
                ProgressView("Reading JSONL…")
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding()
            } else if let err = loadError {
                Label(err, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.red)
            } else if !didLoad {
                Text("Transcript not loaded.\nClick Load Transcript to read raw messages from disk.")
                    .foregroundStyle(.secondary)
                    .font(.callout)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else if messages.isEmpty {
                Text("No user/assistant messages found in this session.")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                LazyVStack(alignment: .leading, spacing: 12) {
                    ForEach(messages) { message in
                        TranscriptMessageView(message: message)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    // MARK: Helpers

    private func metaRow(_ label: String, _ value: String) -> some View {
        GridRow {
            Text(label)
                .foregroundStyle(.secondary)
                .gridColumnAlignment(.trailing)
            Text(value)
                .lineLimit(2)
                .truncationMode(.middle)
                .textSelection(.enabled)
                .gridColumnAlignment(.leading)
        }
        .font(.caption)
    }

    private func loadTranscript() async {
        isLoading = true
        loadError = nil
        defer { isLoading = false }
        do {
            let result = try await Task.detached(priority: .utility) {
                try ClaudeCodeIndexer.loadMessages(for: thread)
            }.value
            self.messages = result
            self.didLoad = true
        } catch {
            self.loadError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    private func resumeInTerminal(workspacePath: String, sessionId: String) {
        #if os(macOS)
        let escaped = workspacePath.replacingOccurrences(of: "\"", with: "\\\"")
        let command = "cd \"\(escaped)\" && claude --resume \"\(sessionId)\"\n"
        let script = """
        tell application "Terminal"
            activate
            do script "\(command.replacingOccurrences(of: "\"", with: "\\\""))"
        end tell
        """
        if let appleScript = NSAppleScript(source: script) {
            var error: NSDictionary?
            appleScript.executeAndReturnError(&error)
        }
        #endif
    }

    private func revealInFinder(path: String) {
        #if os(macOS)
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
        #endif
    }
}

// MARK: - Capability badges

private struct CapabilityBadges: View {
    let capabilities: AIThreadCapabilities

    var body: some View {
        HStack(spacing: 4) {
            if capabilities.contains(.canResumeOriginal)    { tag("Resumable", .green) }
            if capabilities.contains(.canImportTranscript)  { tag("Transcript", .blue) }
            if capabilities.contains(.canImportArtifacts)   { tag("Artifacts", .orange) }
            if capabilities.contains(.canShadowChat)        { tag("Shadow chat", .purple) }
            if capabilities.contains(.canSyncIncrementally) { tag("Live sync", .teal) }
        }
    }

    private func tag(_ text: String, _ color: Color) -> some View {
        Text(text)
            .font(.caption2)
            .padding(.horizontal, 5)
            .padding(.vertical, 1)
            .background(color.opacity(0.12), in: Capsule())
            .foregroundStyle(color)
    }
}

// MARK: - Message renderer

private struct TranscriptMessageView: View {
    let message: AIThreadMessageRecord

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(message.role.uppercased())
                    .font(.caption.bold())
                    .foregroundStyle(roleColor)
                if message.hasToolUse {
                    Image(systemName: "wrench.and.screwdriver")
                        .foregroundStyle(.orange)
                        .font(.caption2)
                }
                Spacer()
                if let date = message.createdAt {
                    Text(date.formatted(date: .omitted, time: .shortened))
                        .foregroundStyle(.tertiary)
                        .font(.caption2)
                }
            }
            Text(message.text)
                .font(.callout)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(8)
                .background(roleColor.opacity(0.06), in: RoundedRectangle(cornerRadius: 6))
                .textSelection(.enabled)
        }
    }

    private var roleColor: Color {
        switch message.role.lowercased() {
        case "user": return .blue
        case "assistant": return .purple
        case "system": return .gray
        default: return .secondary
        }
    }
}
