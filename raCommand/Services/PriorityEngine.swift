//
//  PriorityEngine.swift
//  raCommand
//
//  Created by E. Haugabrooks on 1/11/26.
//

import Foundation

struct PriorityEngine {
    /// Calculate priority score for a project
    /// Higher score = higher priority
    static func calculateScore(for project: Project, feedbackBoost: Int = 0) -> Int {
        var score = 0
        
        // Status-based scoring
        switch project.status {
        case .red:
            score += 50
        case .yellow:
            score += 20
        case .green:
            score += 0
        }
        
        // Value score multiplier
        score += project.valueScore * 2
        
        // Recency penalties
        let daysSinceUpdate = Calendar.current.dateComponents([.day], from: project.lastUpdated, to: Date()).day ?? 0
        if daysSinceUpdate > 7 {
            score += 30
        } else if daysSinceUpdate > 3 {
            score += 15
        }
        
        // Missing next action penalty
        if project.nextAction.isEmpty {
            score += 25
        }
        
        // Delegatable bonus
        if project.delegatable {
            score += 10
        }

        score += feedbackBoost
        
        return score
    }
    
    /// Generate explanation text for why a project ranked high
    static func generateExplanation(for project: Project, score: Int, feedbackBoost: Int = 0) -> String {
        var reasons: [String] = []
        
        switch project.status {
        case .red:
            reasons.append("Red status requires immediate attention")
        case .yellow:
            reasons.append("Yellow status indicates active work needed")
        case .green:
            break
        }
        
        let daysSinceUpdate = Calendar.current.dateComponents([.day], from: project.lastUpdated, to: Date()).day ?? 0
        if daysSinceUpdate > 7 {
            reasons.append("Not updated in over a week")
        } else if daysSinceUpdate > 3 {
            reasons.append("Not updated in several days")
        }
        
        if project.nextAction.isEmpty {
            reasons.append("Missing next action")
        }
        
        if project.valueScore >= 8 {
            reasons.append("High value project")
        }
        
        if project.delegatable {
            reasons.append("Can be delegated")
        }

        if feedbackBoost > 0 {
            reasons.append("Open client feedback raised urgency")
        }
        
        if reasons.isEmpty {
            return "High priority based on overall score"
        }
        
        return reasons.joined(separator: " • ")
    }
    
    /// Get top N prioritized projects
    static func getTopProjects(
        _ projects: [Project],
        limit: Int = 3,
        feedbackBoosts: [String: Int] = [:]
    ) -> [(project: Project, score: Int, explanation: String)] {
        let scored = projects.map { project in
            let feedbackBoost = feedbackBoosts[project.name] ?? 0
            let score = calculateScore(for: project, feedbackBoost: feedbackBoost)
            let explanation = generateExplanation(for: project, score: score, feedbackBoost: feedbackBoost)
            return (project: project, score: score, explanation: explanation)
        }
        
        return Array(scored.sorted { $0.score > $1.score }.prefix(limit))
    }
}
