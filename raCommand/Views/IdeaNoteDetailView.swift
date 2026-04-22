//
//  IdeaNoteDetailView.swift
//  raCommand
//
//  Edit an idea note: title, text, tags, optional project link.
//

import SwiftUI
import SwiftData

struct IdeaNoteDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable var ideaNote: IdeaNote
    @Query(sort: \Project.name) private var projects: [Project]

    var body: some View {
        Form {
            Section("Title (optional)") {
                TextField("Title", text: $ideaNote.title)
            }
            Section("Notes") {
                TextEditor(text: $ideaNote.text)
                    .frame(minHeight: 120)
            }
            Section("Tags (comma-separated)") {
                TextField("Tags", text: $ideaNote.tags)
            }
            Section("Linked project (optional)") {
                Picker("Project", selection: $ideaNote.project) {
                    Text("None").tag(nil as Project?)
                    ForEach(projects) { project in
                        Text(project.name).tag(project as Project?)
                    }
                }
            }
        }
        .navigationTitle("Idea")
        .platformNavigationTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Done") {
                    dismiss()
                }
            }
        }
    }
}

#Preview {
    NavigationStack {
        IdeaNoteDetailView(ideaNote: IdeaNote(
            createdAt: Date(),
            text: "A quick build idea.",
            title: "Feature X",
            tags: "ui, v2"
        ))
    }
    .modelContainer(for: [IdeaNote.self, Project.self], inMemory: true)
}
