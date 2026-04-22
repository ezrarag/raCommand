//
//  ProjectDetailView.swift
//  raCommand
//
//  Created by E. Haugabrooks on 1/11/26.
//

import SwiftUI
import SwiftData

struct ProjectDetailView: View {
    @Bindable var project: Project
    @State private var playback = AudioPlaybackService()
    @State private var playingFilename: String?
    @State private var showAddVoiceNote = false
    @State private var showCreateRepoSheet = false
    @State private var copiedMessage: String?
    @State private var isStartingThread = false
    @State private var workspaceActionError: String?
    @State private var showPeopleView = false

    private var sortedVoiceNotes: [VoiceNote] {
        project.voiceNotes.sorted(by: { $0.createdAt > $1.createdAt })
    }

    private var targetDateBinding: Binding<Date>? {
        guard project.targetDate != nil else { return nil }
        return Binding(
            get: { project.targetDate ?? Date() },
            set: { project.targetDate = $0 }
        )
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 18) {
                overviewCard
                projectDetailsPanel
                nextActionPanel
                additionalPanel
                notesPanel
                linksPanel
                developerActionsPanel
                voiceNotesPanel
                timestampsPanel
            }
            .frame(maxWidth: 920, alignment: .leading)
            .padding(.horizontal, 20)
            .padding(.top, 14)
            .padding(.bottom, 40)
            .frame(maxWidth: .infinity, alignment: .center)
        }
        .whisperShell()
        .navigationTitle("Project")
        .platformNavigationTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .platformNavigationTrailing) {
                NavigationLink {
                    ProjectClientNotesView(project: project)
                } label: {
                    Label("Notes", systemImage: "bubble.left.and.bubble.right.fill")
                        .labelStyle(.iconOnly)
                        .foregroundStyle(WhisperTheme.accent)
                }
                NavigationLink {
                    ProjectPeopleView(project: project)
                } label: {
                    Label("People", systemImage: "person.2.fill")
                        .labelStyle(.iconOnly)
                        .foregroundStyle(WhisperTheme.accent)
                }
            }
        }
        .sheet(isPresented: $showAddVoiceNote) {
            AddVoiceNoteView(project: project)
        }
        .sheet(isPresented: $showCreateRepoSheet) {
            CreateRepoSheet(projectName: project.name) { createdURL in
                project.repoURL = createdURL
                touchProject()
                showCopied("Repo created and URL saved")
            }
        }
        .alert("Workspace Error", isPresented: Binding(
            get: { workspaceActionError != nil },
            set: { newValue in
                if !newValue { workspaceActionError = nil }
            }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(workspaceActionError ?? "")
        }
        .onDisappear {
            playback.stop()
            playingFilename = nil
        }
        .onChange(of: project.name) { touchProject() }
        .onChange(of: project.clientName) { touchProject() }
        .onChange(of: project.category) { touchProject() }
        .onChange(of: project.status) { touchProject() }
        .onChange(of: project.valueScore) { touchProject() }
        .onChange(of: project.notes) { touchProject() }
        .onChange(of: project.nextAction) { touchProject() }
        .onChange(of: project.targetDate) { touchProject() }
        .onChange(of: project.delegatable) { touchProject() }
        .onChange(of: project.repoURL) { touchProject() }
        .onChange(of: project.vercelURL) { touchProject() }
        .onChange(of: project.isActiveThread) { touchProject() }
        .onChange(of: project.localPath) { touchProject() }
    }

    private var overviewCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 14) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(project.name.isEmpty ? "Untitled project" : project.name)
                        .font(.system(.largeTitle, design: .rounded).weight(.bold))
                        .foregroundStyle(WhisperTheme.ink)

                    if !project.clientName.isEmpty {
                        Label(project.clientName, systemImage: "building.2")
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(WhisperTheme.mutedInk)
                    }

                    if !project.nextAction.isEmpty {
                        Text(project.nextAction)
                            .font(.subheadline)
                            .foregroundStyle(WhisperTheme.mutedInk)
                            .lineLimit(2)
                    }
                }

                Spacer(minLength: 12)

                Text(project.category.rawValue.capitalized)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(project.category.whisperColor)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(project.category.whisperColor.opacity(0.12), in: Capsule())
            }

            ViewThatFits(in: .horizontal) {
                HStack(spacing: 10) {
                    overviewPill(label: project.status.rawValue.capitalized, color: project.status.whisperColor, icon: "smallcircle.filled.circle")
                    overviewPill(label: "Value \(project.valueScore)", color: WhisperTheme.accent, icon: "star.fill")
                    if project.delegatable {
                        overviewPill(label: "Delegatable", color: WhisperTheme.success, icon: "arrow.triangle.branch")
                    }
                    if project.isActiveThread {
                        overviewPill(label: "Thread", color: WhisperTheme.info, icon: "rectangle.stack")
                    }
                    if project.targetDate != nil {
                        overviewPill(label: "Target set", color: WhisperTheme.info, icon: "calendar")
                    }
                }

                VStack(alignment: .leading, spacing: 10) {
                    overviewPill(label: project.status.rawValue.capitalized, color: project.status.whisperColor, icon: "smallcircle.filled.circle")
                    overviewPill(label: "Value \(project.valueScore)", color: WhisperTheme.accent, icon: "star.fill")
                    if project.delegatable {
                        overviewPill(label: "Delegatable", color: WhisperTheme.success, icon: "arrow.triangle.branch")
                    }
                    if project.isActiveThread {
                        overviewPill(label: "Thread", color: WhisperTheme.info, icon: "rectangle.stack")
                    }
                    if project.targetDate != nil {
                        overviewPill(label: "Target set", color: WhisperTheme.info, icon: "calendar")
                    }
                }
            }
        }
        .whisperPanel(padding: 22, radius: 28)
    }

    private var projectDetailsPanel: some View {
        fieldSection("Core fields", "Project details", detail: "Tighter contrast and input chrome for editing imported projects.") {
            VStack(spacing: 14) {
                labeledField("Name") {
                    TextField("Project name", text: $project.name)
                        .whisperInsetField()
                }

                labeledField("Client") {
                    TextField("Client or stakeholder", text: $project.clientName)
                        .whisperInsetField()
                }

                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .top, spacing: 12) {
                        categoryMenu
                        statusMenu
                    }

                    VStack(spacing: 14) {
                        categoryMenu
                        statusMenu
                    }
                }

                labeledField("Value score") {
                    HStack(spacing: 14) {
                        scoreButton(systemName: "minus") {
                            guard project.valueScore > 1 else { return }
                            project.valueScore -= 1
                        }

                        VStack(alignment: .leading, spacing: 2) {
                            Text("Current score")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(WhisperTheme.ink)
                            Text("How much leverage this project carries right now.")
                                .font(.caption)
                                .foregroundStyle(WhisperTheme.mutedInk)
                        }

                        Spacer()

                        Text("\(project.valueScore)")
                            .font(.system(.title2, design: .rounded).weight(.bold))
                            .foregroundStyle(WhisperTheme.accent)
                            .monospacedDigit()

                        scoreButton(systemName: "plus") {
                            guard project.valueScore < 10 else { return }
                            project.valueScore += 1
                        }
                    }
                    .whisperInsetField()
                }
            }
        }
    }

    private var nextActionPanel: some View {
        fieldSection("Execution", "Next action", detail: "Keep the next concrete move visible.") {
            TextField("What needs to happen next?", text: $project.nextAction, axis: .vertical)
                .lineLimit(3...6)
                .whisperInsetField()
        }
    }

    private var additionalPanel: some View {
        fieldSection("Tracking", "Additional", detail: "Deadlines and delegation settings.") {
            VStack(spacing: 14) {
                labeledField("Target date") {
                    if let targetDateBinding {
                        HStack(spacing: 12) {
                            DatePicker("Target date", selection: targetDateBinding, displayedComponents: .date)
                                .labelsHidden()
                                .datePickerStyle(.compact)
                                .tint(WhisperTheme.accent)

                            Spacer()

                            Button("Clear") {
                                project.targetDate = nil
                            }
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(WhisperTheme.danger)
                        }
                        .whisperInsetField()
                    } else {
                        Button {
                            project.targetDate = Date()
                        } label: {
                            HStack {
                                Text("Set target date")
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(WhisperTheme.ink)
                                Spacer()
                                Image(systemName: "calendar.badge.plus")
                                    .foregroundStyle(WhisperTheme.accent)
                            }
                        }
                        .buttonStyle(.plain)
                        .whisperInsetField()
                    }
                }

                labeledField("Delegation") {
                    Toggle(isOn: $project.delegatable) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Delegatable")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(WhisperTheme.ink)
                            Text("Marks this project as safe to hand off.")
                                .font(.caption)
                                .foregroundStyle(WhisperTheme.mutedInk)
                        }
                    }
                    .tint(WhisperTheme.accent)
                    .whisperInsetField()
                }
            }
        }
    }

    private var notesPanel: some View {
        fieldSection("Context", "Notes", detail: "Capture context, risks, and reminders.") {
            ZStack(alignment: .topLeading) {
                if project.notes.isEmpty {
                    Text("Add context, constraints, or loose notes for this project.")
                        .font(.subheadline)
                        .foregroundStyle(WhisperTheme.mutedInk.opacity(0.82))
                        .padding(.horizontal, 18)
                        .padding(.top, 16)
                }

                TextEditor(text: $project.notes)
                    .scrollContentBackground(.hidden)
                    .frame(minHeight: 160)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .foregroundStyle(WhisperTheme.ink)
            }
            .background(WhisperTheme.input, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .stroke(WhisperTheme.border, lineWidth: 1)
            )
        }
    }

    private var linksPanel: some View {
        fieldSection("Links", "Repos and deploys", detail: "Project source and deployment destinations.") {
            VStack(spacing: 14) {
                labeledField("Repo URL") {
                    TextField("https://github.com/org/repo", text: $project.repoURL)
                        .platformDisableTextInputAutocapitalization()
                        .autocorrectionDisabled()
                        .whisperInsetField()
                }

                labeledField("Vercel URL") {
                    TextField("https://your-app.vercel.app", text: $project.vercelURL)
                        .platformDisableTextInputAutocapitalization()
                        .autocorrectionDisabled()
                        .whisperInsetField()
                }

                if !project.localPath.isEmpty {
                    labeledField("Local workspace") {
                        Text(project.localPath)
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(WhisperTheme.mutedInk)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 14)
                            .background(WhisperTheme.input, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 20, style: .continuous)
                                    .stroke(WhisperTheme.border, lineWidth: 1)
                            )
                    }
                }
            }
        }
    }

    private var developerActionsPanel: some View {
        fieldSection("Actions", "Developer actions", detail: "Fast links for the imported repo and deployment.") {
            VStack(spacing: 12) {
                if let copiedMessage {
                    HStack(spacing: 10) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(WhisperTheme.success)
                        Text(copiedMessage)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(WhisperTheme.success)
                        Spacer()
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                    .background(WhisperTheme.success.opacity(0.08), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .stroke(WhisperTheme.success.opacity(0.22), lineWidth: 1)
                    )
                }

                if project.isActiveThread || LocalWorkspaceService.workspaceExists(at: project.localPath) {
                    HStack(spacing: 10) {
                        Image(systemName: "rectangle.stack.badge.checkmark")
                            .foregroundStyle(WhisperTheme.success)
                        Text("This project has a local active-thread workspace.")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(WhisperTheme.success)
                        Spacer()
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                    .background(WhisperTheme.success.opacity(0.08), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .stroke(WhisperTheme.success.opacity(0.22), lineWidth: 1)
                    )
                }

                if let repoURL = URL(string: project.repoURL), !project.repoURL.isEmpty {
                    Button {
                        Task { await startActiveThread() }
                    } label: {
                        actionRow(
                            icon: isStartingThread ? "hourglass" : "rectangle.stack.badge.play",
                            title: project.isActiveThread ? "Open Active Thread in Codex" : "Start Active Thread in Codex",
                            subtitle: project.isActiveThread
                                ? "Opens the local workspace in Codex Desktop."
                                : "Clones locally if needed, marks the project active, then opens Codex.",
                            tint: WhisperTheme.info
                        )
                    }
                    .buttonStyle(.plain)
                    .disabled(isStartingThread)

                    Button {
                        PlatformSystemServices.open(repoURL)
                    } label: {
                        actionRow(
                            icon: "safari",
                            title: "Open Repo on GitHub",
                            subtitle: project.repoURL,
                            tint: WhisperTheme.info
                        )
                    }
                    .buttonStyle(.plain)

                    Button {
                        let command = GitHubActionsService.cloneCommand(repoURL: project.repoURL)
                        PlatformSystemServices.copyToPasteboard(command)
                        showCopied("Clone command copied")
                    } label: {
                        actionRow(
                            icon: "doc.on.doc",
                            title: "Copy Clone Command",
                            subtitle: "Copies a ready-to-run `git clone` command.",
                            tint: WhisperTheme.accent
                        )
                    }
                    .buttonStyle(.plain)

                    if LocalWorkspaceService.workspaceExists(at: project.localPath) {
                        Button {
                            PlatformSystemServices.open(URL(fileURLWithPath: project.localPath))
                        } label: {
                            actionRow(
                                icon: "folder",
                                title: "Reveal Local Workspace",
                                subtitle: project.localPath,
                                tint: WhisperTheme.success
                            )
                        }
                        .buttonStyle(.plain)
                    }

                    Button {
                        if let settingsURL = URL(string: project.repoURL + "/settings") {
                            PlatformSystemServices.open(settingsURL)
                        }
                    } label: {
                        actionRow(
                            icon: "archivebox",
                            title: "Archive Repo",
                            subtitle: "Opens GitHub settings for this repository.",
                            tint: WhisperTheme.warning
                        )
                    }
                    .buttonStyle(.plain)
                }

                if let vercelURL = URL(string: project.vercelURL), !project.vercelURL.isEmpty {
                    Button {
                        PlatformSystemServices.open(vercelURL)
                    } label: {
                        actionRow(
                            icon: "globe",
                            title: "Open Vercel Deployment",
                            subtitle: project.vercelURL,
                            tint: WhisperTheme.success
                        )
                    }
                    .buttonStyle(.plain)
                }

                Button {
                    showCreateRepoSheet = true
                } label: {
                    actionRow(
                        icon: "plus.rectangle.on.folder",
                        title: "Create GitHub Repo for This Project",
                        subtitle: "Uses the current project name as a starting point.",
                        tint: WhisperTheme.accent
                    )
                }
                .buttonStyle(.plain)

                if project.repoURL.isEmpty && project.vercelURL.isEmpty {
                    Text("Add a repo or deployment URL above to unlock the quick actions here.")
                        .font(.subheadline)
                        .foregroundStyle(WhisperTheme.mutedInk)
                        .padding(.horizontal, 4)
                }
            }
        }
    }

    private var voiceNotesPanel: some View {
        fieldSection("Audio", "Voice notes", detail: "Recent recordings tied to this project.") {
            VStack(spacing: 12) {
                if sortedVoiceNotes.isEmpty {
                    HStack(spacing: 12) {
                        Image(systemName: "waveform")
                            .foregroundStyle(WhisperTheme.mutedInk)
                        Text("No voice notes yet.")
                            .font(.subheadline)
                            .foregroundStyle(WhisperTheme.mutedInk)
                        Spacer()
                    }
                    .whisperInsetField()
                } else {
                    ForEach(sortedVoiceNotes, id: \.persistentModelID) { note in
                        NavigationLink {
                            VoiceNoteDetailView(voiceNote: note)
                        } label: {
                            HStack(spacing: 12) {
                                Button {
                                    let isThisPlaying = playingFilename == note.audioFilename && playback.isPlaying
                                    if isThisPlaying {
                                        playback.pause()
                                        playingFilename = nil
                                    } else {
                                        playback.play(filename: note.audioFilename)
                                        playingFilename = note.audioFilename
                                    }
                                } label: {
                                    ZStack {
                                        Circle()
                                            .fill(WhisperTheme.accentSoft)
                                            .frame(width: 38, height: 38)
                                        Image(systemName: (playingFilename == note.audioFilename && playback.isPlaying) ? "pause.fill" : "play.fill")
                                            .font(.system(size: 14, weight: .bold))
                                            .foregroundStyle(WhisperTheme.accent)
                                    }
                                }
                                .buttonStyle(.plain)

                                VStack(alignment: .leading, spacing: 4) {
                                    Text(note.title)
                                        .font(.subheadline.weight(.semibold))
                                        .foregroundStyle(WhisperTheme.ink)
                                        .lineLimit(1)
                                    Text(note.createdAt.formatted(date: .abbreviated, time: .shortened))
                                        .font(.caption)
                                        .foregroundStyle(WhisperTheme.mutedInk)
                                }

                                Spacer()

                                Text(formatDuration(note.durationSeconds))
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(WhisperTheme.mutedInk)
                                    .monospacedDigit()

                                Image(systemName: "chevron.right")
                                    .font(.caption.weight(.bold))
                                    .foregroundStyle(WhisperTheme.mutedInk.opacity(0.8))
                            }
                            .padding(.horizontal, 14)
                            .padding(.vertical, 12)
                            .background(WhisperTheme.input, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 18, style: .continuous)
                                    .stroke(WhisperTheme.border, lineWidth: 1)
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }

                Button {
                    showAddVoiceNote = true
                } label: {
                    actionRow(
                        icon: "plus.circle.fill",
                        title: "Add Voice Note",
                        subtitle: "Record a quick update, idea, or transcript.",
                        tint: WhisperTheme.accent
                    )
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var timestampsPanel: some View {
        fieldSection("History", "Activity", detail: "Recent update metadata for this project.") {
            VStack(spacing: 12) {
                metadataRow(label: "Last updated", value: project.lastUpdated.formatted(date: .abbreviated, time: .shortened))
                metadataRow(label: "Last reviewed", value: project.lastReviewed.formatted(date: .abbreviated, time: .shortened))
            }
        }
    }

    private var categoryMenu: some View {
        labeledField("Category") {
            Menu {
                ForEach(ProjectCategory.allCases, id: \.self) { category in
                    Button {
                        project.category = category
                    } label: {
                        HStack {
                            Text(category.rawValue.capitalized)
                            Spacer()
                            if category == project.category {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            } label: {
                selectionField(value: project.category.rawValue.capitalized, tint: project.category.whisperColor)
            }
            .buttonStyle(.plain)
        }
    }

    private var statusMenu: some View {
        labeledField("Status") {
            Menu {
                ForEach(ProjectStatus.allCases, id: \.self) { status in
                    Button {
                        project.status = status
                    } label: {
                        HStack {
                            Text(status.rawValue.capitalized)
                            Spacer()
                            if status == project.status {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            } label: {
                selectionField(value: project.status.rawValue.capitalized, tint: project.status.whisperColor)
            }
            .buttonStyle(.plain)
        }
    }

    private func touchProject() {
        let now = Date()
        project.lastUpdated = now
        project.lastReviewed = now
    }

    private func showCopied(_ message: String) {
        copiedMessage = message
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
            copiedMessage = nil
        }
    }

    private func startActiveThread() async {
        guard !isStartingThread else { return }
        isStartingThread = true
        workspaceActionError = nil

        defer { isStartingThread = false }

        do {
            let existingThreadState = project.isActiveThread
            let workspacePath = try LocalWorkspaceService.ensureLocalClone(
                repoURL: project.repoURL,
                preferredPath: project.localPath.isEmpty ? nil : project.localPath
            )

            project.localPath = workspacePath
            project.isActiveThread = true
            touchProject()

            try LocalWorkspaceService.openInCodex(path: workspacePath)
            showCopied(existingThreadState ? "Opened thread in Codex" : "Thread started in Codex")
        } catch {
            workspaceActionError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    private func formatDuration(_ seconds: Double) -> String {
        let minutes = Int(seconds) / 60
        let remainingSeconds = Int(seconds) % 60
        return String(format: "%d:%02d", minutes, remainingSeconds)
    }

    private func fieldSection<Content: View>(
        _ eyebrow: String,
        _ title: String,
        detail: String? = nil,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            WhisperSectionTitle(eyebrow: eyebrow, title: title, detail: detail)
            content()
        }
        .whisperPanel()
    }

    private func labeledField<Content: View>(
        _ label: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(label.uppercased())
                .font(.caption2.weight(.bold))
                .tracking(0.9)
                .foregroundStyle(WhisperTheme.mutedInk)
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func selectionField(value: String, tint: Color) -> some View {
        HStack(spacing: 12) {
            Circle()
                .fill(tint.opacity(0.18))
                .frame(width: 12, height: 12)
                .overlay(
                    Circle()
                        .stroke(tint.opacity(0.6), lineWidth: 1)
                )

            Text(value)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(WhisperTheme.ink)

            Spacer()

            Image(systemName: "chevron.up.chevron.down")
                .font(.caption.weight(.bold))
                .foregroundStyle(WhisperTheme.mutedInk)
        }
        .whisperInsetField()
    }

    private func scoreButton(systemName: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(WhisperTheme.accent)
                .frame(width: 30, height: 30)
                .background(WhisperTheme.accentSoft, in: Circle())
        }
        .buttonStyle(.plain)
    }

    private func metadataRow(label: String, value: String) -> some View {
        HStack {
            Text(label)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(WhisperTheme.ink)
            Spacer()
            Text(value)
                .font(.caption.weight(.semibold))
                .foregroundStyle(WhisperTheme.mutedInk)
                .multilineTextAlignment(.trailing)
        }
        .whisperInsetField()
    }

    private func actionRow(icon: String, title: String, subtitle: String, tint: Color) -> some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(tint.opacity(0.14))
                    .frame(width: 38, height: 38)
                Image(systemName: icon)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(tint)
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(WhisperTheme.ink)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(WhisperTheme.mutedInk)
                    .lineLimit(2)
            }

            Spacer()

            Image(systemName: "arrow.up.right")
                .font(.footnote.weight(.bold))
                .foregroundStyle(WhisperTheme.mutedInk)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(WhisperTheme.input, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(WhisperTheme.border, lineWidth: 1)
        )
    }

    private func overviewPill(label: String, color: Color, icon: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
            Text(label)
        }
        .font(.caption.weight(.bold))
        .foregroundStyle(color)
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(color.opacity(0.1), in: Capsule())
    }
}

// MARK: - Create Repo Sheet
struct CreateRepoSheet: View {
    @Environment(\.dismiss) private var dismiss
    let projectName: String
    let onCreated: (String) -> Void

    @State private var repoName: String = ""
    @State private var description: String = ""
    @State private var isPrivate: Bool = false
    @State private var isLoading: Bool = false
    @State private var errorMessage: String? = nil

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Repo name", text: $repoName)
                        .platformDisableTextInputAutocapitalization()
                        .autocorrectionDisabled()

                    TextField("Description (optional)", text: $description)

                    Toggle("Private repo", isOn: $isPrivate)
                }
                header: {
                    WhisperSectionTitle(eyebrow: "Repository", title: "New GitHub repository", detail: nil)
                }
                .listRowBackground(WhisperTheme.panel.opacity(0.9))

                if let error = errorMessage {
                    Section {
                        Text(error)
                            .foregroundStyle(.red)
                            .font(.caption)
                    }
                    .listRowBackground(WhisperTheme.panel.opacity(0.9))
                }
            }
            .whisperFormChrome()
            .platformListRowSpacing(12)
            .navigationTitle("Create Repo")
            .platformNavigationTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    if isLoading {
                        ProgressView()
                    } else {
                        Button("Create") {
                            Task { await createRepo() }
                        }
                        .disabled(repoName.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .onAppear {
                repoName = projectName
                    .lowercased()
                    .replacingOccurrences(of: " ", with: "-")
            }
        }
    }

    private func createRepo() async {
        isLoading = true
        errorMessage = nil

        guard let token = KeychainService.loadGitHubToken(), !token.isEmpty else {
            errorMessage = "No GitHub token found. Add one in GitHub Import settings."
            isLoading = false
            return
        }

        do {
            let result = try await GitHubActionsService.createRepo(
                name: repoName.trimmingCharacters(in: .whitespaces),
                description: description,
                isPrivate: isPrivate,
                token: token
            )
            onCreated(result.htmlURL)
            dismiss()
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? "Could not create repo. Check your token has 'repo' scope."
        }

        isLoading = false
    }
}
