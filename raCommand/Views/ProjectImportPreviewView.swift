//
//  ProjectImportPreviewView.swift
//  raCommand
//
//  Created by E. Haugabrooks on 2/1/26.
//

import SwiftUI

struct ProjectImportPreviewView: View {
    let title: String
    let rows: [ProjectImportRow]
    let onConfirm: () -> Void

    @Environment(\.dismiss) private var dismiss

    private var validRows: [ProjectImportRow] {
        ProjectImportService.validRows(from: rows)
    }

    private var previewRows: [ProjectImportRow] {
        Array(validRows.prefix(10))
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack {
                        Text("Rows")
                        Spacer()
                        Text("\(rows.count)")
                            .foregroundStyle(.secondary)
                    }

                    HStack {
                        Text("Ready to import")
                        Spacer()
                        Text("\(validRows.count)")
                            .foregroundStyle(.secondary)
                    }
                }
                header: {
                    WhisperSectionTitle(eyebrow: "Summary", title: "Import summary", detail: nil)
                }
                .listRowBackground(WhisperTheme.panel.opacity(0.9))

                Section {
                    if previewRows.isEmpty {
                        Text("No valid rows found.")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(previewRows) { row in
                            VStack(alignment: .leading, spacing: 4) {
                                Text(row.name.isEmpty ? "Untitled Project" : row.name)
                                    .font(.headline)
                                Text("Status: \(row.status.rawValue.capitalized) • Value: \(row.valueScore)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                header: {
                    WhisperSectionTitle(eyebrow: "Preview", title: "First 10 rows", detail: nil)
                }
                .listRowBackground(WhisperTheme.panel.opacity(0.9))
            }
            .whisperFormChrome()
            .platformListRowSpacing(12)
            .navigationTitle(title)
            .platformNavigationTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Import") {
                        onConfirm()
                        dismiss()
                    }
                    .disabled(validRows.isEmpty)
                }

                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }
}
