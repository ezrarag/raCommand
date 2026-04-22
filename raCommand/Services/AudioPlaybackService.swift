//
//  AudioPlaybackService.swift
//  raCommand
//
//  Created by E. Haugabrooks on 2/1/26.
//

import AVFoundation
import Foundation

@Observable
final class AudioPlaybackService {
    private var player: AVAudioPlayer?
    private var periodicObserver: Any?

    var isPlaying: Bool { player?.isPlaying ?? false }
    var currentTime: TimeInterval { player?.currentTime ?? 0 }
    var duration: TimeInterval { player?.duration ?? 0 }
    var progress: Double {
        let d = duration
        guard d > 0 else { return 0 }
        return currentTime / d
    }

    /// Play audio from app Documents (VoiceNotes subfolder). Uses filename only; path is resolved internally.
    func play(filename: String) {
        let url = AudioRecorderService.fileURL(for: filename)
        play(url: url)
    }

    func play(url: URL) {
        stop()
        do {
#if os(iOS) || os(tvOS) || os(watchOS) || os(visionOS)
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .default)
            try session.setActive(true)
#endif
            player = try AVAudioPlayer(contentsOf: url)
            player?.prepareToPlay()
            player?.play()
        } catch {
            // Playback failed
        }
    }

    func pause() {
        player?.pause()
    }

    func resume() {
        player?.play()
    }

    func stop() {
        player?.stop()
        player?.currentTime = 0
        player = nil
    }

    func seek(to time: TimeInterval) {
        player?.currentTime = min(max(0, time), duration)
    }
}
