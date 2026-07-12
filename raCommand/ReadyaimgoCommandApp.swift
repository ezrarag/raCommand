//
//  ReadyaimgoCommandApp.swift
//  raCommand
//
//  Created by E. Haugabrooks on 1/11/26.
//

import SwiftUI
import SwiftData

@main
struct ReadyaimgoCommandApp: App {
    private let sharedModelContainer: ModelContainer
    private let sharedModelContext: ModelContext

    init() {
        WhisperAppAppearance.configure()

        let schema = Schema([
            Project.self,
            AppMeta.self,
            BuildNote.self,
            VoiceNote.self,
            IdeaNote.self
        ])

        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)

        do {
            let container = try ModelContainer(for: schema, configurations: [configuration])
            sharedModelContainer = container
            sharedModelContext = ModelContext(container)
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }

    var body: some Scene {
        WindowGroup {
            MainTabView()
                .environment(\.modelContext, sharedModelContext)
        }
        #if os(macOS)
        .windowStyle(.hiddenTitleBar)
        #endif
        .modelContainer(sharedModelContainer)
    }
}
