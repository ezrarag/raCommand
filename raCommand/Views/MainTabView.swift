//
//  MainTabView.swift
//  raCommand
//
//  MacWhisper-inspired tab bar — large SF Symbols, minimal labels.
//

import SwiftUI
import SwiftData

struct MainTabView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var appMetas: [AppMeta]

    var body: some View {
        TabView {
            ProjectListView()
                .tabItem {
                    Label("Projects", systemImage: "folder.fill")
                }

            RepoManagerView()
                .tabItem {
                    Label("Repos", systemImage: "externaldrive.connected.to.line.below.fill")
                }

            PulseView()
                .tabItem {
                    Label("Pulse", systemImage: "waveform.path.ecg")
                }

            IntelligenceFeedView()
                .tabItem {
                    Label("Intelligence", systemImage: "brain")
                }

            AIThreadsView()
                .tabItem {
                    Label("Threads", systemImage: "bubble.left.and.bubble.right")
                }

            TodayView()
                .tabItem {
                    Label("Today", systemImage: "calendar")
                }

            SettingsView()
                .tabItem {
                    Label("Settings", systemImage: "gearshape.fill")
                }
        }
        .tint(WhisperTheme.accent)
        .onAppear { seedIfNeeded() }
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
}

#Preview {
    MainTabView()
        .modelContainer(for: [Project.self, AppMeta.self, BuildNote.self, VoiceNote.self, IdeaNote.self], inMemory: true)
}
