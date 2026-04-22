//
//  Project.swift
//  raCommand
//
//  Created by E. Haugabrooks on 1/11/26.
//

import SwiftData
import Foundation

enum ProjectCategory: String, Codable, CaseIterable {
    case app
    case website
    case infra
    case legal
    case finance
    case content
}

enum ProjectStatus: String, Codable, CaseIterable {
    case green
    case yellow
    case red
}

@Model
class Project {
    var name: String = ""
    var status: ProjectStatus = ProjectStatus.yellow
    var valueScore: Int = 5
    var notes: String = ""
    var lastUpdated: Date = Date()
    
    // Stored-property defaults let SwiftData backfill new columns during migration.
    var clientName: String = ""
    var category: ProjectCategory = ProjectCategory.app
    var nextAction: String = ""
    var targetDate: Date?
    var delegatable: Bool = false
    var lastReviewed: Date = Date()
    var repoURL: String = ""
    var vercelURL: String = ""
    var isActiveThread: Bool = false
    var localPath: String = ""

    @Relationship(deleteRule: .cascade, inverse: \VoiceNote.project)
    var voiceNotes: [VoiceNote] = []

    init(
        name: String,
        status: ProjectStatus = .yellow,
        valueScore: Int = 5,
        notes: String = "",
        clientName: String = "",
        category: ProjectCategory = .app,
        nextAction: String = "",
        targetDate: Date? = nil,
        delegatable: Bool = false,
        repoURL: String = "",
        vercelURL: String = "",
        isActiveThread: Bool = false,
        localPath: String = ""
    ) {
        self.name = name
        self.status = status
        self.valueScore = valueScore
        self.notes = notes
        self.lastUpdated = Date()
        self.clientName = clientName
        self.category = category
        self.nextAction = nextAction
        self.targetDate = targetDate
        self.delegatable = delegatable
        self.lastReviewed = Date()
        self.repoURL = repoURL
        self.vercelURL = vercelURL
        self.isActiveThread = isActiveThread
        self.localPath = localPath
    }
}

extension Project {
    var clientFeedbackProjectId: String {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmedName.isEmpty ? "unknown" : trimmedName
    }
}
