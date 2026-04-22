//
//  AddVoiceNoteView.swift
//  raCommand
//
//  Created by E. Haugabrooks on 2/1/26.
//

import SwiftUI
import SwiftData
import UniformTypeIdentifiers
import AVFoundation

struct AddVoiceNoteView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    var project: Project

    @State private var recorder = AudioRecorderService()
    @State private var recordingFilename: String?
    @State private var recordedDuration: Double = 0
    @State private var showFileImporter = false
    @State private var importedURL: URL?
    @State private var importedDuration: Double = 0
    @State private var importError: String?
    @State private var isSaving = false

    private var hasRecording: Bool {
        if let _ = recordingFilename { return true }
        if importedURL != nil { return true }
        return false
    }

    private var canSave: Bool {
        hasRecording && !isSaving
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    if recorder.state == .idle && !hasRecording {
                        Button {
                            startRecording()
                        } label: {
                            HStack {
                                Image(systemName: "mic.circle.fill")
                                    .font(.system(size: 56))
                                Text("Record Voice Note")
                                    .font(.headline)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 24)
                        }
                        .buttonStyle(.plain)

                        Button {
                            showFileImporter = true
                        } label: {
                            HStack {
                                Image(systemName: "square.and.arrow.down")
                                Text("Import Audio File")
                            }
                        }
                        if let err = importError {
                            Text(err)
                                .font(.caption)
                                .foregroundStyle(.red)
                        }
                    } else if case .recording = recorder.state {
                        VStack(spacing: 16) {
                            Image(systemName: "stop.circle.fill")
                                .font(.system(size: 72))
                                .foregroundStyle(.red)
                            Text("Recording… \(formatDuration(recorder.currentDurationSeconds))")
                                .font(.headline)
                            Button("Stop") {
                                stopRecording()
                            }
                            .buttonStyle(.borderedProminent)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 24)
                    } else if hasRecording {
                        VStack(alignment: .leading, spacing: 8) {
                            Label("Recording ready", systemImage: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                            if let name = recordingFilename {
                                Text("File: \(name)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            if let url = importedURL {
                                Text("Imported: \(url.lastPathComponent)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Text("Duration: \(formatDuration(recordedDuration > 0 ? recordedDuration : importedDuration))")
                                .font(.caption)
                        }
                        .padding(.vertical, 8)

                        Button("Record another") {
                            discardAndReset()
                        }
                        Button("Import another file") {
                            showFileImporter = true
                        }
                    }
                } header: {
                    Text("Add Voice Note")
                }
            }
            .navigationTitle("Add Voice Note")
            .platformNavigationTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        recorder.reset()
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        saveAndDismiss()
                    }
                    .disabled(!canSave)
                }
            }
            .fileImporter(
                isPresented: $showFileImporter,
                allowedContentTypes: [.audio, .mpeg4Audio, UTType(filenameExtension: "caf") ?? .audio, UTType(filenameExtension: "wav") ?? .audio],
                allowsMultipleSelection: false
            ) { result in
                switch result {
                case .success(let urls):
                    guard let url = urls.first else { return }
                    if url.startAccessingSecurityScopedResource() {
                        defer { url.stopAccessingSecurityScopedResource() }
                        handleImportedFile(url: url)
                    } else {
                        handleImportedFile(url: url)
                    }
                case .failure(let error):
                    importError = error.localizedDescription
                }
            }
            .onDisappear {
                recorder.reset()
            }
        }
    }

    private func startRecording() {
        importError = nil
        importedURL = nil
        importedDuration = 0
        recordingFilename = recorder.startRecording()
    }

    private func stopRecording() {
        if let result = recorder.stopRecording() {
            recordingFilename = result.filename
            recordedDuration = result.durationSeconds
        }
    }

    private func discardAndReset() {
        recordingFilename = nil
        recordedDuration = 0
        importedURL = nil
        importedDuration = 0
        importError = nil
        recorder.reset()
    }

    private func handleImportedFile(url: URL) {
        importError = nil
        recordingFilename = nil
        recordedDuration = 0

        let filename = "imported_\(UUID().uuidString).\(url.pathExtension)"
        let destURL = AudioRecorderService.fileURL(for: filename)
        do {
            if FileManager.default.fileExists(atPath: destURL.path) {
                try FileManager.default.removeItem(at: destURL)
            }
            try FileManager.default.copyItem(at: url, to: destURL)
            recordingFilename = filename
            importedURL = url
            importedDuration = durationOfAudioFile(at: destURL) ?? 0
        } catch {
            importError = error.localizedDescription
        }
    }

    private func durationOfAudioFile(at url: URL) -> Double? {
        do {
            let player = try AVAudioPlayer(contentsOf: url)
            return player.duration
        } catch {
            return nil
        }
    }

    private func saveAndDismiss() {
        guard canSave else { return }
        isSaving = true

        let filename: String
        let duration: Double
        if let name = recordingFilename, recordedDuration > 0 {
            filename = name
            duration = recordedDuration
        } else if let name = recordingFilename, importedDuration > 0 {
            filename = name
            duration = importedDuration
        } else {
            isSaving = false
            return
        }

        let note = VoiceNote(
            title: "Voice Note",
            audioFilename: filename,
            durationSeconds: duration,
            transcript: "",
            project: project
        )
        modelContext.insert(note)
        project.voiceNotes.append(note)
        recorder.reset()
        dismiss()
    }

    private func formatDuration(_ seconds: Double) -> String {
        let m = Int(seconds) / 60
        let s = Int(seconds) % 60
        return String(format: "%d:%02d", m, s)
    }
}
