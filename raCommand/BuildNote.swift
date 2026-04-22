//
//  BuildNote.swift
//  raCommand
//
//  Build notes: version, summary, changes, next steps.
//

import SwiftData
import Foundation

@Model
final class BuildNote {
    var versionString: String
    var buildNumber: String
    var date: Date
    var summary: String
    var changes: String
    var nextSteps: String

    init(
        versionString: String = "",
        buildNumber: String = "",
        date: Date = Date(),
        summary: String = "",
        changes: String = "",
        nextSteps: String = ""
    ) {
        self.versionString = versionString
        self.buildNumber = buildNumber
        self.date = date
        self.summary = summary
        self.changes = changes
        self.nextSteps = nextSteps
    }
}
