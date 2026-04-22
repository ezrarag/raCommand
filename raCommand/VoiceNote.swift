//
//  VoiceNote.swift
//  raCommand
//
//  Created by E. Haugabrooks on 2/1/26.
//

import SwiftData
import Foundation

@Model
final class VoiceNote {
    var createdAt: Date
    var title: String
    var audioFilename: String
    var durationSeconds: Double
    var transcript: String
    var project: Project?

    init(
        createdAt: Date = Date(),
        title: String = "Voice Note",
        audioFilename: String,
        durationSeconds: Double,
        transcript: String = "",
        project: Project? = nil
    ) {
        self.createdAt = createdAt
        self.title = title
        self.audioFilename = audioFilename
        self.durationSeconds = durationSeconds
        self.transcript = transcript
        self.project = project
    }
}
