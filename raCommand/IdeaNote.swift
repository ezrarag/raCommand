//
//  IdeaNote.swift
//  raCommand
//
//  Lightweight idea inbox: future builds and general thoughts.
//

import SwiftData
import Foundation

@Model
final class IdeaNote {
    var createdAt: Date
    var text: String
    var title: String
    var tags: String
    var project: Project?

    init(
        createdAt: Date = Date(),
        text: String = "",
        title: String = "",
        tags: String = "",
        project: Project? = nil
    ) {
        self.createdAt = createdAt
        self.text = text
        self.title = title
        self.tags = tags
        self.project = project
    }
}
