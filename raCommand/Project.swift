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

    // readyaimgo admin workspace sync — nil remoteWorkspaceId means this
    // Project has never been pushed to the admin `workspaces` collection.
    // workspaceSyncStatus must stay Optional: a non-optional enum property
    // crashes SwiftData's automatic lightweight migration on rows that
    // predate this column ("Passed nil for a non-optional keypath").
    // Treat nil as .local (never synced) everywhere this is read.
    var remoteWorkspaceId: String?
    var workspaceSyncStatus: WorkspaceSyncStatus?

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
        localPath: String = "",
        remoteWorkspaceId: String? = nil,
        workspaceSyncStatus: WorkspaceSyncStatus? = .local
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
        self.remoteWorkspaceId = remoteWorkspaceId
        self.workspaceSyncStatus = workspaceSyncStatus
    }
}

enum WorkspaceSyncStatus: String, Codable, CaseIterable {
    case local
    case synced
    case pending
    case error
}

extension Project {
    var clientFeedbackProjectId: String {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmedName.isEmpty ? "unknown" : trimmedName
    }
}
