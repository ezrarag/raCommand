//
//  VoiceNoteDetailView.swift
//  raCommand
//
//  Created by E. Haugabrooks on 2/1/26.
//

import SwiftUI
import SwiftData

struct VoiceNoteDetailView: View {
    @Bindable var voiceNote: VoiceNote
    @State private var playback = AudioPlaybackService()
    @State private var transcription = TranscriptionService()
    @State private var transcriptError: String?
    @State private var isPlaying = false

    var body: some View {
        Form {
            Section("Details") {
                TextField("Title", text: $voiceNote.title)
                LabeledContent("Created", value: voiceNote.createdAt.formatted(date: .abbreviated, time: .shortened))
                LabeledContent("Duration", value: formatDuration(voiceNote.durationSeconds))
            }

            Section("Playback") {
                HStack(spacing: 16) {
                    Button {
                        if playback.isPlaying {
                            playback.pause()
                            isPlaying = false
                        } else {
                            if playback.duration == 0 || playback.currentTime >= playback.duration - 0.1 {
                                playback.play(filename: voiceNote.audioFilename)
                            } else {
                                playback.resume()
                            }
                            isPlaying = true
                        }
                    } label: {
                        Image(systemName: playback.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                            .font(.system(size: 44))
                    }
                    .buttonStyle(.plain)

                    if playback.duration > 0 {
                        VStack(alignment: .leading, spacing: 4) {
                            ProgressView(value: playback.progress)
                                .progressViewStyle(.linear)
                            Text("\(formatDuration(playback.currentTime)) / \(formatDuration(playback.duration))")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .onDisappear {
                    playback.stop()
                }
            }

            Section("Transcription") {
                Button("Transcribe") {
                    transcriptError = nil
                    Task {
                        do {
                            let text = try await transcription.transcribe(filename: voiceNote.audioFilename)
                            await MainActor.run {
                                voiceNote.transcript = text
                            }
                        } catch {
                            await MainActor.run {
                                transcriptError = error.localizedDescription
                            }
                        }
                    }
                }
                .disabled(transcription.isTranscribing)

                if transcription.isTranscribing {
                    HStack {
                        ProgressView()
                        Text(transcription.progressMessage)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                if let error = transcriptError {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                }

                if !voiceNote.transcript.isEmpty {
                    TextEditor(text: $voiceNote.transcript)
                        .frame(minHeight: 120)
                }
            }
        }
        .navigationTitle(voiceNote.title)
    }

    private func formatDuration(_ seconds: Double) -> String {
        let m = Int(seconds) / 60
        let s = Int(seconds) % 60
        return String(format: "%d:%02d", m, s)
    }
}
