//
//  BuildNoteDetailView.swift
//  raCommand
//
//  Add or edit a build note.
//

import SwiftUI
import SwiftData

struct BuildNoteDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable var note: BuildNote

    var body: some View {
        Form {
            Section("Version") {
                TextField("Version (e.g. 0.1)", text: $note.versionString)
                TextField("Build number (e.g. 2)", text: $note.buildNumber)
                DatePicker("Date", selection: $note.date, displayedComponents: .date)
            }
            Section("Summary") {
                TextField("Short summary", text: $note.summary, axis: .vertical)
                    .lineLimit(2...4)
            }
            Section("Changes") {
                TextEditor(text: $note.changes)
                    .frame(minHeight: 100)
            }
            Section("Next steps") {
                TextEditor(text: $note.nextSteps)
                    .frame(minHeight: 100)
            }
        }
        .navigationTitle("Build Note")
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
