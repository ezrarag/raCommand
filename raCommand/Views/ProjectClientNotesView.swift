//
//  ProjectClientNotesView.swift
//  raCommand
//
//  Shows client feedback, Loom videos, and AI interpretations for a project.
//  Connects to clients.readyaimgo.biz via ClientNoteService.
//

import SwiftUI

struct ProjectClientNotesView: View {
    let project: Project

    @State private var feedback: [ClientFeedback] = []
    @State private var isLoading = false
    @State private var error: String?
    @State private var filter: FeedbackFilter = .open
    @State private var resolving: String?
    @State private var resolveNote = ""
    @State private var showResolveSheet = false
    @State private var selectedFeedback: ClientFeedback?
    @State private var screenshotToShow: URL?
    @State private var successMessage: String?
    @State private var showShareSheet = false
    @State private var feedbackURL = ""
    @State private var ideaCount: Int?

    enum FeedbackFilter: String, CaseIterable {
        case open = "Open"
        case all = "All"
        case resolved = "Resolved"

        var statusParam: String? {
            switch self {
            case .open: return "open"
            case .resolved: return "resolved"
            case .all: return nil
            }
        }
    }

    private var filteredFeedback: [ClientFeedback] {
        switch filter {
        case .open: return feedback.filter { $0.status == "open" }
        case .resolved: return feedback.filter { $0.status == "resolved" }
        case .all: return feedback
        }
    }

    private var openCount: Int { feedback.filter { $0.status == "open" }.count }
    private var highUrgencyCount: Int { feedback.filter { $0.urgency == "high" && $0.status == "open" }.count }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 18) {
                headerPanel
                sharePanel
                if let msg = successMessage { successBanner(msg) }
                if let err = error { errorBanner(err) }
                statsRow
                filterRow
                feedbackList
            }
            .padding(.horizontal, 20)
            .padding(.top, 14)
            .padding(.bottom, 40)
        }
        .whisperShell()
        .navigationTitle("Client Notes")
        .platformNavigationTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .platformNavigationTrailing) {
                if isLoading {
                    ProgressView().tint(WhisperTheme.accent)
                } else {
                    Button { Task { await load() } } label: {
                        Image(systemName: "arrow.clockwise").foregroundStyle(WhisperTheme.accent)
                    }
                }
            }
        }
        .sheet(item: $selectedFeedback) { note in
            ResolveNoteSheet(note: note) { resolveText in
                Task { await resolve(note: note, resolveNote: resolveText) }
            }
        }
        .sheet(item: Binding(
            get: { screenshotToShow.map { IdentifiableURL(url: $0) } },
            set: { screenshotToShow = $0?.url }
        )) { identURL in
            ScreenshotLightboxView(url: identURL.url)
        }
        .task { await load() }
    }

    private func copyPrompt(for note: ClientFeedback) {
        let projectName = project.name.isEmpty ? "ReadyAimGo Project" : project.name
        let pageURL = note.pageUrl ?? "N/A"
        let screenshotURL = note.screenshotUrl ?? "N/A"
        let noteText = note.rawText ?? note.summary
        let action = note.suggestedAction.isEmpty ? "N/A" : note.suggestedAction

        let prompt = """
        # AI Coding Task Prompt
        **Project Name:** \(projectName)
        **Target Page URL:** \(pageURL)
        **Screenshot URL:** \(screenshotURL)

        ## Client Feedback Note
        \(noteText)

        ## AI Suggested Action
        \(action)
        """

        #if os(macOS)
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(prompt, forType: .string)
        #else
        UIPasteboard.general.string = prompt
        #endif
        
        showSuccess("Copied prompt to clipboard!")
    }

    // MARK: - Header

    private var headerPanel: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("CLIENT NOTES")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(WhisperTheme.accent)
            Text("Feedback for \(project.name.isEmpty ? "this project" : project.name)")
                .font(.title3.weight(.semibold))
                .foregroundStyle(WhisperTheme.ink)
            Text("AI-interpreted notes, Loom videos, and extension annotations from your client.")
                .font(.callout)
                .foregroundStyle(WhisperTheme.mutedInk)
        }
        .whisperPanel(padding: 16, radius: 10)
    }

    // MARK: - Share Panel

    private var sharePanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            WhisperSectionTitle(eyebrow: "Client link", title: "Share feedback portal", detail: nil)

            let url = ClientNoteService.feedbackURL(for: project.clientFeedbackProjectId)

            VStack(spacing: 10) {
                HStack(spacing: 8) {
                    Image(systemName: "link")
                        .foregroundStyle(WhisperTheme.accent)
                    Text(url)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(WhisperTheme.mutedInk)
                        .lineLimit(1)
                    Spacer()
                }
                .whisperInsetField()

                HStack(spacing: 10) {
                    Button {
                        PlatformSystemServices.copyToPasteboard(url)
                        showSuccess("Link copied")
                    } label: {
                        Label("Copy link", systemImage: "doc.on.doc")
                            .font(.subheadline.weight(.semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 11)
                            .background(WhisperTheme.accent, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                            .foregroundStyle(.white)
                    }
                    .buttonStyle(.plain)

                    if let appURL = URL(string: url) {
                        Button {
                            PlatformSystemServices.open(appURL)
                        } label: {
                            Label("Open", systemImage: "arrow.up.right")
                                .font(.subheadline.weight(.semibold))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 11)
                                .background(WhisperTheme.info.opacity(0.15), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                                .foregroundStyle(WhisperTheme.info)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .whisperPanel()
    }

    // MARK: - Stats Row

    private var statsRow: some View {
        HStack(spacing: 10) {
            statPill(value: openCount, label: "Open", color: WhisperTheme.warning)
            statPill(value: highUrgencyCount, label: "High urgency", color: WhisperTheme.danger)
            statPill(value: feedback.filter { $0.isVideo }.count, label: "Videos", color: WhisperTheme.info)
            statPill(value: ideaCount ?? 0, label: "Ideas", color: WhisperTheme.accent)
        }
    }

    private func statPill(value: Int, label: String, color: Color) -> some View {
        VStack(spacing: 3) {
            Text("\(value)").font(.title3.bold()).foregroundStyle(color)
            Text(label).font(.caption2).foregroundStyle(WhisperTheme.mutedInk)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background(color.opacity(0.08), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    // MARK: - Filter Row

    private var filterRow: some View {
        Picker("Feedback filter", selection: $filter) {
            ForEach(FeedbackFilter.allCases, id: \.self) { f in
                Text(f.rawValue).tag(f)
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
    }

    // MARK: - Feedback List

    private var feedbackList: some View {
        Group {
            if isLoading && feedback.isEmpty {
                HStack {
                    ProgressView().tint(WhisperTheme.accent)
                    Text("Loading feedback…").font(.subheadline).foregroundStyle(WhisperTheme.mutedInk)
                }
                .whisperPanel()
            } else if filteredFeedback.isEmpty {
                WhisperEmptyState(
                    icon: filter == .open ? "checkmark.bubble" : "bubble.left.and.bubble.right",
                    title: filter == .open ? "No open feedback" : "No feedback yet",
                    message: filter == .open
                        ? "All client notes have been resolved. Nice work."
                        : "Share the client link above so your client can leave notes."
                )
            } else {
                VStack(spacing: 12) {
                    ForEach(filteredFeedback) { note in
                        FeedbackCard(
                            note: note,
                            resolving: resolving == note.id,
                            onAcknowledge: {
                                Task { await acknowledge(note: note) }
                            },
                            onResolve: {
                                selectedFeedback = note
                            },
                            onCopyPrompt: {
                                copyPrompt(for: note)
                            },
                            onShowScreenshot: { url in
                                screenshotToShow = url
                            },
                            ideaCount: ideaCount.flatMap { $0 > 0 ? $0 : nil }
                        )
                    }
                }
            }
        }
    }

    // MARK: - Banners

    private func successBanner(_ msg: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "checkmark.circle.fill").foregroundStyle(WhisperTheme.success)
            Text(msg).font(.subheadline.weight(.medium)).foregroundStyle(WhisperTheme.success)
            Spacer()
        }
        .padding(14)
        .background(WhisperTheme.success.opacity(0.08), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(WhisperTheme.success.opacity(0.2), lineWidth: 1))
    }

    private func errorBanner(_ msg: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(WhisperTheme.danger)
            Text(msg).font(.subheadline).foregroundStyle(WhisperTheme.danger)
            Spacer()
        }
        .padding(14)
        .background(WhisperTheme.danger.opacity(0.08), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    // MARK: - Data

    private func load() async {
        isLoading = true
        error = nil
        do {
            let id = project.clientFeedbackProjectId
            async let fetchedFeedback = ClientNoteService.fetchFeedback(projectId: id)
            async let fetchedIdeaCount = ClientNoteService.fetchIdeaCount(clientId: id)
            feedback = try await fetchedFeedback
            ideaCount = (try? await fetchedIdeaCount) ?? ideaCount
        } catch {
            self.error = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
        isLoading = false
    }

    private func acknowledge(note: ClientFeedback) async {
        resolving = note.id
        do {
            try await ClientNoteService.acknowledge(feedbackId: note.id)
            showSuccess("Acknowledged")
            await load()
        } catch { self.error = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription }
        resolving = nil
    }

    private func resolve(note: ClientFeedback, resolveNote: String) async {
        resolving = note.id
        do {
            try await ClientNoteService.resolve(feedbackId: note.id, note: resolveNote)
            showSuccess("Marked resolved")
            await load()
        } catch { self.error = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription }
        resolving = nil
    }

    private func showSuccess(_ msg: String) {
        successMessage = msg
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) { successMessage = nil }
    }
}

// MARK: - Feedback Card

struct FeedbackCard: View {
    let note: ClientFeedback
    let resolving: Bool
    let onAcknowledge: () -> Void
    let onResolve: () -> Void
    let onCopyPrompt: () -> Void
    let onShowScreenshot: (URL) -> Void
    let ideaCount: Int?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Top row
            HStack(alignment: .top, spacing: 10) {
                // Source icon
                ZStack {
                    Circle().fill(sourceColor.opacity(0.12)).frame(width: 36, height: 36)
                    Image(systemName: sourceIcon).font(.system(size: 14, weight: .semibold)).foregroundStyle(sourceColor)
                }

                VStack(alignment: .leading, spacing: 3) {
                    Text(note.clientName).font(.subheadline.weight(.semibold)).foregroundStyle(WhisperTheme.ink)
                    if let email = note.clientEmail {
                        Text(email).font(.caption).foregroundStyle(WhisperTheme.mutedInk)
                    }
                    if let title = note.projectTitle, !title.isEmpty {
                        Text(title).font(.caption2.weight(.semibold)).foregroundStyle(WhisperTheme.accent)
                    }
                }

                Spacer()

                urgencyBadge
            }

            // AI summary
            Text(note.summary)
                .font(.subheadline)
                .foregroundStyle(WhisperTheme.ink)
                .fixedSize(horizontal: false, vertical: true)

            // Raw text if different
            if let raw = note.rawText, raw != note.summary {
                Text(raw)
                    .font(.caption)
                    .foregroundStyle(WhisperTheme.mutedInk)
                    .padding(10)
                    .background(WhisperTheme.input, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            }

            // Loom video link
            if let loomURL = note.loomUrl, let url = URL(string: loomURL) {
                Button { PlatformSystemServices.open(url) } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "play.rectangle.fill").foregroundStyle(WhisperTheme.info)
                        Text("Watch Loom video").font(.caption.weight(.semibold)).foregroundStyle(WhisperTheme.info)
                        Spacer()
                        Image(systemName: "arrow.up.right").font(.caption).foregroundStyle(WhisperTheme.mutedInk)
                    }
                    .padding(10)
                    .background(WhisperTheme.info.opacity(0.08), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
                .buttonStyle(.plain)
            }

            // Screenshot Preview
            if let screenshotStr = note.screenshotUrl, let screenshotURL = URL(string: screenshotStr) {
                Button {
                    onShowScreenshot(screenshotURL)
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "photo.fill").foregroundStyle(WhisperTheme.info)
                        Text("View Screenshot").font(.caption.weight(.semibold)).foregroundStyle(WhisperTheme.info)
                        Spacer()
                        AsyncImage(url: screenshotURL) { phase in
                            switch phase {
                            case .success(let image):
                                image.resizable().aspectRatio(contentMode: .fill)
                            default:
                                ProgressView().scaleEffect(0.5)
                            }
                        }
                        .frame(width: 32, height: 32)
                        .cornerRadius(6)
                        .clipped()
                    }
                    .padding(10)
                    .background(WhisperTheme.info.opacity(0.08), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
                .buttonStyle(.plain)
            }

            // Suggested action
            if note.actionable && !note.suggestedAction.isEmpty {
                HStack(spacing: 6) {
                    Image(systemName: "arrow.right.circle.fill").foregroundStyle(WhisperTheme.accent).font(.caption)
                    Text(note.suggestedAction).font(.caption).foregroundStyle(WhisperTheme.accent)
                }
            }

            // Pills row
            HStack(spacing: 6) {
                pill(note.category.capitalized, color: WhisperTheme.info)
                pill("Pulse \(note.pulseScore)", color: WhisperTheme.accent)
                if note.isProjectSuggestion {
                    pill("Project suggestion", color: WhisperTheme.warning)
                }
                if let projectType = note.projectType, !projectType.isEmpty {
                    pill(projectType, color: WhisperTheme.mutedInk)
                }
                if let contextStatus = note.agentContextStatus, !contextStatus.isEmpty {
                    pill("Agent \(contextStatus)", color: WhisperTheme.success)
                }
                if let ideaCount {
                    pill("Ideas \(ideaCount)", color: WhisperTheme.warning)
                }
                if note.isFromWidget {
                    pill("Widget", color: Color.indigo)
                }
                if note.isFromExtension { pill("Extension", color: Color.purple) }
                Spacer()
                // Actions
                Button(action: onCopyPrompt) {
                    HStack(spacing: 4) {
                        Image(systemName: "doc.on.doc.fill")
                        Text("Copy Prompt")
                    }
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(WhisperTheme.accent)
                    .padding(.horizontal, 10).padding(.vertical, 5)
                    .background(WhisperTheme.accent.opacity(0.1), in: Capsule())
                }
                .buttonStyle(.plain)

                if note.status == "open" {
                    if resolving {
                        ProgressView().tint(.secondary).scaleEffect(0.7)
                    } else {
                        Button("Ack", action: onAcknowledge)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(WhisperTheme.mutedInk)
                            .padding(.horizontal, 10).padding(.vertical, 5)
                            .background(WhisperTheme.input, in: Capsule())
                        Button("Resolve", action: onResolve)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(WhisperTheme.success)
                            .padding(.horizontal, 10).padding(.vertical, 5)
                            .background(WhisperTheme.success.opacity(0.1), in: Capsule())
                    }
                } else {
                    pill(note.status.capitalized, color: WhisperTheme.success)
                }
            }
        }
        .whisperPanel()
    }

    private var urgencyBadge: some View {
        Text(note.urgencyLevel.label)
            .font(.caption2.bold())
            .foregroundStyle(urgencyColor)
            .padding(.horizontal, 8).padding(.vertical, 4)
            .background(urgencyColor.opacity(0.12), in: Capsule())
    }

    private var urgencyColor: Color {
        switch note.urgencyLevel {
        case .low: return WhisperTheme.success
        case .medium: return WhisperTheme.warning
        case .high: return WhisperTheme.danger
        }
    }

    private var sourceIcon: String {
        switch note.source {
        case "loom": return "play.rectangle.fill"
        case "extension": return "puzzlepiece.extension"
        case "workspace-project-suggestion": return "lightbulb.fill"
        default: return "bubble.left.fill"
        }
    }

    private var sourceColor: Color {
        switch note.source {
        case "loom": return WhisperTheme.info
        case "extension": return Color.purple
        case "workspace-project-suggestion": return WhisperTheme.warning
        default: return WhisperTheme.accent
        }
    }

    private func pill(_ label: String, color: Color) -> some View {
        Text(label)
            .font(.caption2.bold())
            .foregroundStyle(color)
            .padding(.horizontal, 8).padding(.vertical, 4)
            .background(color.opacity(0.1), in: Capsule())
    }
}

// MARK: - Resolve Sheet

struct ResolveNoteSheet: View {
    @Environment(\.dismiss) private var dismiss
    let note: ClientFeedback
    let onResolve: (String) -> Void

    @State private var resolveNote = ""

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    VStack(alignment: .leading, spacing: 8) {
                        WhisperSectionTitle(eyebrow: "Resolve", title: "Mark as done", detail: "Add an optional note to send context back to the team record.")
                        Text(note.summary).font(.subheadline).foregroundStyle(WhisperTheme.mutedInk)
                    }
                    .whisperPanel()

                    VStack(alignment: .leading, spacing: 8) {
                        Text("RESOLUTION NOTE (OPTIONAL)")
                            .font(.caption2.weight(.bold)).tracking(0.9).foregroundStyle(WhisperTheme.mutedInk)
                        TextEditor(text: $resolveNote)
                            .frame(minHeight: 100)
                            .scrollContentBackground(.hidden)
                            .padding(12)
                            .background(WhisperTheme.input, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    }
                    .whisperPanel()

                    Button {
                        onResolve(resolveNote)
                        dismiss()
                    } label: {
                        Text("Mark Resolved")
                            .fontWeight(.semibold)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(WhisperTheme.success, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                            .foregroundStyle(.white)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 20).padding(.vertical, 16)
            }
            .whisperShell()
            .navigationTitle("Resolve Note")
            .platformNavigationTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            }
        }
    }
}

// MARK: - Lightbox Helper Structures

struct IdentifiableURL: Identifiable {
    let id = UUID()
    let url: URL
}

struct ScreenshotLightboxView: View {
    @Environment(\.dismiss) private var dismiss
    let url: URL
    @State private var scale: CGFloat = 1.0
    @State private var lastScale: CGFloat = 1.0

    var body: some View {
        NavigationStack {
            VStack {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .scaleEffect(scale)
                            .gesture(
                                MagnifyGesture()
                                    .onChanged { value in
                                        let delta = value.magnification / lastScale
                                        lastScale = value.magnification
                                        scale = min(max(scale * delta, 0.5), 4.0)
                                    }
                                    .onEnded { _ in
                                        lastScale = 1.0
                                    }
                            )
                            .onTapGesture(count: 2) {
                                withAnimation {
                                    scale = scale > 1.0 ? 1.0 : 2.0
                                }
                            }
                    case .failure:
                        VStack(spacing: 12) {
                            Image(systemName: "exclamationmark.triangle.fill").font(.largeTitle).foregroundStyle(WhisperTheme.danger)
                            Text("Failed to load screenshot").font(.subheadline)
                        }
                    case .empty:
                        ProgressView()
                    @unknown default:
                        EmptyView()
                    }
                }
                
                HStack(spacing: 20) {
                    Button(action: { scale = max(scale - 0.25, 0.5) }) {
                        Image(systemName: "minus.magnifyingglass")
                    }
                    Button(action: { scale = 1.0 }) {
                        Text("Reset Zoom")
                    }
                    Button(action: { scale = min(scale + 0.25, 4.0) }) {
                        Image(systemName: "plus.magnifyingglass")
                    }
                }
                .font(.subheadline)
                .padding(.vertical, 8)
                .foregroundColor(.white)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.black.opacity(0.9))
            .navigationTitle("Screenshot Preview")
            .platformNavigationTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
        }
    }
}
