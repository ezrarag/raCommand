//
//  TranscriptionService.swift
//  raCommand
//
//  Created by E. Haugabrooks on 2/1/26.
//

import Foundation
import Speech

enum TranscriptionError: Error {
    case notAuthorized
    case recognitionUnavailable
    case fileNotFound
    case recognitionFailed(Error)
}

@Observable
final class TranscriptionService {
    var isTranscribing: Bool = false
    var progressMessage: String = ""

    /// Transcribe a local audio file URL on demand. Returns the transcript text or throws.
    func transcribe(url: URL) async throws -> String {
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw TranscriptionError.fileNotFound
        }

        await MainActor.run { isTranscribing = true; progressMessage = "Requesting authorization…" }
        let authStatus = SFSpeechRecognizer.authorizationStatus()
        if authStatus != .authorized {
            await MainActor.run { progressMessage = "Requesting speech recognition access…" }
            let granted = await withCheckedContinuation { (cont: CheckedContinuation<Bool, Never>) in
                SFSpeechRecognizer.requestAuthorization { status in
                    cont.resume(returning: status == .authorized)
                }
            }
            if !granted {
                await MainActor.run { isTranscribing = false; progressMessage = "" }
                throw TranscriptionError.notAuthorized
            }
        }

        guard let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US")), recognizer.isAvailable else {
            await MainActor.run { isTranscribing = false; progressMessage = "" }
            throw TranscriptionError.recognitionUnavailable
        }

        let request = SFSpeechURLRecognitionRequest(url: url)
        request.shouldReportPartialResults = false

        await MainActor.run { progressMessage = "Transcribing…" }

        return try await withCheckedThrowingContinuation { continuation in
            recognizer.recognitionTask(with: request) { [weak self] result, error in
                Task { @MainActor in
                    self?.isTranscribing = false
                    self?.progressMessage = ""
                }
                if let error = error {
                    continuation.resume(throwing: TranscriptionError.recognitionFailed(error))
                    return
                }
                guard let result = result, result.isFinal else {
                    continuation.resume(throwing: TranscriptionError.recognitionFailed(NSError(domain: "TranscriptionService", code: -1, userInfo: [NSLocalizedDescriptionKey: "Recognition did not complete"])))
                    return
                }
                continuation.resume(returning: result.bestTranscription.formattedString)
            }
        }
    }

    /// Transcribe using filename (resolved via AudioRecorderService.fileURL).
    func transcribe(filename: String) async throws -> String {
        let url = AudioRecorderService.fileURL(for: filename)
        return try await transcribe(url: url)
    }
}
