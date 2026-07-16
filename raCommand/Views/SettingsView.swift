//
//  SettingsView.swift
//  raCommand
//
//  App memory, build notes, and idea inbox in warmer editorial cards.
//

import SwiftUI
import SwiftData

private enum SettingsSection: String, CaseIterable, Identifiable {
    case general
    case sync
    case diagnostics
    case aiUsage
    case notes

    var id: String { rawValue }

    var label: String {
        switch self {
        case .general: return "General"
        case .sync: return "Sync"
        case .diagnostics: return "Diagnostics"
        case .aiUsage: return "AI Usage"
        case .notes: return "Notes"
        }
    }
}

struct SettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var appMetas: [AppMeta]
    @Query(sort: \BuildNote.date, order: .reverse) private var buildNotes: [BuildNote]
    @Query(sort: \IdeaNote.createdAt, order: .reverse) private var ideaNotes: [IdeaNote]

    @State private var section: SettingsSection = .general

    private var appMeta: AppMeta? {
        appMetas.first
    }

    var body: some View {
        NavigationStack {
            HStack(spacing: 0) {
                settingsSubNav

                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 18) {
                        sectionContent
                    }
                    .padding(.horizontal, 24)
                    .padding(.top, 20)
                    .padding(.bottom, 36)
                    .frame(maxWidth: 640, alignment: .leading)
                }
                .frame(maxWidth: .infinity)
            }
            .whisperShell()
            .quickIdeaToolbar()
            .navigationTitle("Settings")
            .platformNavigationTitleDisplayMode(.large)
        }
    }

    private var settingsSubNav: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Settings")
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(WhisperTheme.ink)
                .padding(.horizontal, 8)
                .padding(.bottom, 10)

            ForEach(SettingsSection.allCases) { item in
                let isActive = section == item
                Button {
                    section = item
                } label: {
                    Text(item.label)
                        .font(.system(size: 13, weight: isActive ? .semibold : .regular))
                        .foregroundStyle(isActive ? WhisperTheme.info : Color(red: 0.655, green: 0.671, blue: 0.702))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 10)
                        .frame(height: 32)
                        .background(
                            isActive ? WhisperTheme.accent.opacity(0.10) : .clear,
                            in: RoundedRectangle(cornerRadius: 7, style: .continuous)
                        )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(24)
        .frame(width: 200, alignment: .leading)
        .frame(maxHeight: .infinity, alignment: .top)
        .overlay(alignment: .trailing) {
            Rectangle()
                .fill(Color.white.opacity(0.06))
                .frame(width: 1)
        }
    }

    @ViewBuilder
    private var sectionContent: some View {
        switch section {
        case .general:
            hero

            if let meta = appMeta {
                editorPanel(
                    eyebrow: "About raCommand",
                    title: "What this app is for",
                    text: Binding(
                        get: { meta.appDescription },
                        set: { meta.appDescription = $0; meta.updatedAt = Date() }
                    ),
                    prompt: "Describe the app in one or two grounded paragraphs."
                )

                editorPanel(
                    eyebrow: "Current focus",
                    title: "What the build is chasing now",
                    text: Binding(
                        get: { meta.currentFocus },
                        set: { meta.currentFocus = $0; meta.updatedAt = Date() }
                    ),
                    prompt: "Capture the current build focus and what should ship next."
                )
            } else {
                WhisperEmptyState(
                    icon: "gearshape.2",
                    title: "Settings data missing",
                    message: "Launch the app shell once so the single-row metadata record can be seeded."
                )
            }
        case .sync:
            AdminSyncKeyPanelView()
            GitHubTokenPanelView()
            VercelTokenPanelView()
        case .diagnostics:
            SystemDiagnosticsPanelView()
        case .aiUsage:
            AIUsagePanelView()
        case .notes:
            buildNotesPanel
            ideaInboxPanel
        }
    }

    private var hero: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 8) {
                Text("APP MEMORY")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(WhisperTheme.accent)
                Text("Context, ship notes, and loose ideas.")
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(WhisperTheme.ink)
                Text("This space holds the story of the app so product direction, build history, and rough ideas stay close together.")
                    .font(.callout)
                    .foregroundStyle(WhisperTheme.mutedInk)
            }

            HStack(spacing: 12) {
                WhisperMetricPill(label: "Build notes", value: "\(buildNotes.count)", tone: WhisperTheme.info)
                WhisperMetricPill(label: "Ideas", value: "\(ideaNotes.count)", tone: WhisperTheme.accent)
            }
        }
        .whisperPanel(padding: 16, radius: 10)
    }

    private func editorPanel(eyebrow: String, title: String, text: Binding<String>, prompt: String) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            WhisperSectionTitle(eyebrow: eyebrow, title: title, detail: nil)
            TextEditor(text: text)
                .frame(minHeight: 110)
                .padding(12)
                .background(WhisperTheme.input, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(WhisperTheme.border, lineWidth: 1)
                )
            Text(prompt)
                .font(.caption)
                .foregroundStyle(WhisperTheme.mutedInk)
        }
        .whisperPanel()
    }

    private var buildNotesPanel: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                WhisperSectionTitle(
                    eyebrow: "Release log",
                    title: "Build notes",
                    detail: buildNotes.isEmpty ? "No build notes yet." : "\(buildNotes.count) entries in the ship log."
                )
                Spacer()
                addPill(title: "Add", icon: "plus") {
                    addBuildNote()
                }
            }

            if buildNotes.isEmpty {
                WhisperEmptyState(
                    icon: "doc.text",
                    title: "No build notes",
                    message: "Start a note when you want to track a release, a milestone, or a change batch."
                )
            } else {
                ForEach(buildNotes) { note in
                    HStack(alignment: .top, spacing: 12) {
                        NavigationLink {
                            BuildNoteDetailView(note: note)
                        } label: {
                            VStack(alignment: .leading, spacing: 6) {
                                Text("v\(note.versionString) (\(note.buildNumber))")
                                    .font(.system(.headline, design: .rounded).weight(.bold))
                                    .foregroundStyle(WhisperTheme.ink)
                                if !note.summary.isEmpty {
                                    Text(note.summary)
                                        .font(.subheadline)
                                        .foregroundStyle(WhisperTheme.mutedInk)
                                        .lineLimit(2)
                                }
                                Text(note.date.formatted(date: .abbreviated, time: .omitted))
                                    .font(.caption.weight(.medium))
                                    .foregroundStyle(WhisperTheme.mutedInk)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .buttonStyle(.plain)

                        Button(role: .destructive) {
                            modelContext.delete(note)
                        } label: {
                            Image(systemName: "trash")
                                .font(.footnote.weight(.bold))
                                .foregroundStyle(WhisperTheme.danger)
                                .padding(10)
                                .background(WhisperTheme.danger.opacity(0.1), in: Circle())
                        }
                        .buttonStyle(.plain)
                    }
                    .whisperPanel(padding: 16, radius: 22)
                }
            }
        }
        .whisperPanel()
    }

    private var ideaInboxPanel: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                WhisperSectionTitle(
                    eyebrow: "Idea inbox",
                    title: "Loose product signals",
                    detail: ideaNotes.isEmpty ? "No ideas captured yet." : "\(ideaNotes.count) notes waiting to be shaped."
                )
                Spacer()
                addPill(title: "New", icon: "plus") {
                    addIdeaNote()
                }
            }

            if ideaNotes.isEmpty {
                WhisperEmptyState(
                    icon: "lightbulb",
                    title: "No ideas captured",
                    message: "Drop rough thoughts here before they harden into projects or release notes."
                )
            } else {
                ForEach(ideaNotes) { note in
                    HStack(alignment: .top, spacing: 12) {
                        NavigationLink {
                            IdeaNoteDetailView(ideaNote: note)
                        } label: {
                            VStack(alignment: .leading, spacing: 6) {
                                Text(previewLine(for: note))
                                    .font(.system(.headline, design: .rounded).weight(.bold))
                                    .foregroundStyle(WhisperTheme.ink)
                                    .lineLimit(2)
                                Text(note.createdAt.formatted(date: .abbreviated, time: .shortened))
                                    .font(.caption.weight(.medium))
                                    .foregroundStyle(WhisperTheme.mutedInk)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .buttonStyle(.plain)

                        Button(role: .destructive) {
                            modelContext.delete(note)
                        } label: {
                            Image(systemName: "trash")
                                .font(.footnote.weight(.bold))
                                .foregroundStyle(WhisperTheme.danger)
                                .padding(10)
                                .background(WhisperTheme.danger.opacity(0.1), in: Circle())
                        }
                        .buttonStyle(.plain)
                    }
                    .whisperPanel(padding: 16, radius: 22)
                }
            }
        }
        .whisperPanel()
    }

    private func addPill(title: String, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: icon)
                .font(.caption.weight(.bold))
                .foregroundStyle(WhisperTheme.accent)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(WhisperTheme.accentSoft.opacity(0.8), in: Capsule())
        }
        .buttonStyle(.plain)
    }

    private func addBuildNote() {
        let note = BuildNote(
            versionString: "0",
            buildNumber: "\(buildNotes.count + 1)",
            date: Date(),
            summary: "",
            changes: "",
            nextSteps: ""
        )
        modelContext.insert(note)
    }

    private func previewLine(for note: IdeaNote) -> String {
        if !note.title.isEmpty { return note.title }
        let first = note.text.split(separator: "\n").first.map(String.init) ?? ""
        return first.isEmpty ? "No text" : first
    }

    private func addIdeaNote() {
        let note = IdeaNote(createdAt: Date(), text: "", title: "", tags: "", project: nil)
        modelContext.insert(note)
    }
}

#Preview {
    SettingsView()
        .modelContainer(for: [AppMeta.self, BuildNote.self, IdeaNote.self, Project.self], inMemory: true)
}
