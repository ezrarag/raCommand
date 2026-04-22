//
//  PasteImportView.swift
//  raCommand
//
//  Created by E. Haugabrooks on 2/1/26.
//

import SwiftUI

struct PasteImportView: View {
    let onPreview: (_ rows: [ProjectImportRow]) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var pastedText = ""

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 16) {
                Text("Paste one project per line. Optional format: name — client — status — value.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                TextEditor(text: $pastedText)
                    .frame(minHeight: 240)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color.secondary.opacity(0.2))
                    )
            }
            .padding()
            .navigationTitle("Paste List")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Preview") {
                        let rows = ProjectImportService.parsePaste(text: pastedText)
                        onPreview(rows)
                        dismiss()
                    }
                    .disabled(pastedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }

                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }
}
