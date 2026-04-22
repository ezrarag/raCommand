//
//  AudioRecorderService.swift
//  raCommand
//
//  Created by E. Haugabrooks on 2/1/26.
//

import AVFoundation
import Foundation

enum RecordingState: Equatable {
    case idle
    case recording(startedAt: Date)
    case stopped
}

@Observable
final class AudioRecorderService {
    private var audioRecorder: AVAudioRecorder?
    private var recordingStartDate: Date?

    var state: RecordingState = .idle
    private var isRecording: Bool {
        if case .recording = state {
            return true
        }
        return false
    }

    var currentDurationSeconds: Double {
        switch state {
        case .idle, .stopped:
            return 0
        case .recording(let startedAt):
            return Date().timeIntervalSince(startedAt)
        }
    }

    /// Documents directory URL for storing recordings.
    static var documentsRecordingURL: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appending(path: "VoiceNotes", directoryHint: .isDirectory)
    }

    init() {
        ensureVoiceNotesDirectoryExists()
    }

    private func ensureVoiceNotesDirectoryExists() {
        let url = Self.documentsRecordingURL
        if !FileManager.default.fileExists(atPath: url.path) {
            try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        }
    }

    /// Generates a unique filename for a new recording (e.g. "recording_20260201120000.m4a").
    func uniqueRecordingFilename() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMddHHmmss"
        return "recording_\(formatter.string(from: Date())).m4a"
    }

    /// Full file URL for a given filename (assumes file is in VoiceNotes subfolder).
    static func fileURL(for filename: String) -> URL {
        documentsRecordingURL.appending(path: filename)
    }

    /// Start recording to a new .m4a file. Returns the filename used, or nil if recording could not start.
    @discardableResult
    func startRecording() -> String? {
        guard !isRecording else { return nil }

        let filename = uniqueRecordingFilename()
        let url = Self.fileURL(for: filename)

        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey: 44100,
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
        ]

        do {
#if os(iOS) || os(tvOS) || os(watchOS) || os(visionOS)
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker, .allowBluetooth])
            try session.setActive(true)
#endif

            audioRecorder = try AVAudioRecorder(url: url, settings: settings)
            audioRecorder?.record()
            recordingStartDate = Date()
            state = .recording(startedAt: recordingStartDate!)
            return filename
        } catch {
            state = .idle
            return nil
        }
    }

    /// Stop recording. Returns the filename that was recorded and total duration, or nil if nothing was recording.
    func stopRecording() -> (filename: String, durationSeconds: Double)? {
        guard case .recording(let startedAt) = state else { return nil }

        audioRecorder?.stop()
        let duration = Date().timeIntervalSince(startedAt)
        let url = audioRecorder?.url
        audioRecorder = nil
        recordingStartDate = nil
        state = .stopped

        guard let url = url else { return nil }
        let filename = url.lastPathComponent
        return (filename, duration)
    }

    /// Reset to idle (e.g. after saving or discarding).
    func reset() {
        if isRecording {
            audioRecorder?.stop()
            audioRecorder = nil
        }
        recordingStartDate = nil
        state = .idle
    }
}
