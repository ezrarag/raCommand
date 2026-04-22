//
//  AppMeta.swift
//  raCommand
//
//  Single-row settings: app description and current focus.
//

import SwiftData
import Foundation

@Model
final class AppMeta {
    var appDescription: String
    var currentFocus: String
    var updatedAt: Date

    init(
        appDescription: String = "",
        currentFocus: String = "",
        updatedAt: Date = Date()
    ) {
        self.appDescription = appDescription
        self.currentFocus = currentFocus
        self.updatedAt = updatedAt
    }
}
