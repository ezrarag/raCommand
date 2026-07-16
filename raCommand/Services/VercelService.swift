//
//  VercelService.swift
//  raCommand
//
//  Communicates with the Vercel REST API to fetch project deployment status.
//

import Foundation

struct VercelCreator: Codable {
    let username: String
}

struct VercelMeta: Codable {
    let githubCommitMessage: String?
    let githubCommitRef: String?
    let githubCommitSha: String?

    enum CodingKeys: String, CodingKey {
        case githubCommitMessage = "githubCommitMessage"
        case githubCommitRef = "githubCommitRef"
        case githubCommitSha = "githubCommitSha"
    }
}

struct VercelDeployment: Codable, Identifiable {
    let uid: String
    let url: String
    let state: String // BUILDING, READY, ERROR, CANCELED
    let target: String? // production, preview
    let created: Int64
    let creator: VercelCreator?
    let meta: VercelMeta?

    var id: String { uid }

    var createdDate: Date {
        Date(timeIntervalSince1970: TimeInterval(created / 1000))
    }

    var stateColor: String {
        switch state.uppercased() {
        case "READY": return "READY"
        case "BUILDING": return "BUILDING"
        case "ERROR": return "ERROR"
        default: return "CANCELED"
        }
    }
}

struct VercelDeploymentsResponse: Codable {
    let deployments: [VercelDeployment]
}

enum VercelServiceError: LocalizedError {
    case unconfigured
    case invalidURL
    case apiError(Int, String)
    case networkError(String)

    var errorDescription: String? {
        switch self {
        case .unconfigured:
            return "Vercel Personal Access Token not configured in Settings."
        case .invalidURL:
            return "The requested Vercel API URL was invalid."
        case .apiError(let code, let msg):
            return "Vercel API error (Code \(code)): \(msg)"
        case .networkError(let msg):
            return "Network connection failed: \(msg)"
        }
    }
}

enum VercelService {
    
    /// Parses the Vercel project name/slug from the project's vercelURL,
    /// or falls back to matching the repository name if the URL is empty.
    static func resolveVercelProjectName(vercelURL: String, repoURL: String) -> String? {
        let trimmedURL = vercelURL.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedURL.isEmpty {
            // e.g. "https://vercel.com/team-name/project-name" or "project-name.vercel.app"
            let components = trimmedURL.split(separator: "/")
            if let last = components.last {
                let name = String(last)
                    .replacingOccurrences(of: ".vercel.app", with: "")
                return name.isEmpty ? nil : name
            }
        }
        
        // Fallback: use the repo name from the repoURL
        let trimmedRepo = repoURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedRepo.isEmpty else { return nil }
        
        var tail = trimmedRepo
        if let lastSlash = tail.lastIndex(of: "/") {
            tail = String(tail[tail.index(after: lastSlash)...])
        }
        if let query = tail.firstIndex(of: "?") {
            tail = String(tail[..<query])
        }
        if tail.hasSuffix(".git") {
            tail.removeLast(4)
        }
        
        let sanitized = tail.trimmingCharacters(in: .whitespacesAndNewlines)
        return sanitized.isEmpty ? nil : sanitized
    }

    /// Fetches the recent deployments for a Vercel project.
    static func fetchDeployments(projectNameOrId: String) async throws -> [VercelDeployment] {
        guard let token = KeychainService.loadVercelToken(), !token.isEmpty else {
            throw VercelServiceError.unconfigured
        }

        var urlString = "https://api.vercel.com/v6/deployments?projectId=\(projectNameOrId)&limit=10"
        
        // Add optional teamId if configured in the keychain
        if let teamId = KeychainService.loadVercelTeamId(), !teamId.isEmpty {
            urlString += "&teamId=\(teamId)"
        }

        guard let url = URL(string: urlString) else {
            throw VercelServiceError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse else {
                throw VercelServiceError.networkError("Invalid HTTP response.")
            }

            guard httpResponse.statusCode == 200 else {
                let errorBody = String(data: data, encoding: .utf8) ?? "Unknown Vercel API error"
                throw VercelServiceError.apiError(httpResponse.statusCode, errorBody)
            }

            let decoder = JSONDecoder()
            let decoded = try decoder.decode(VercelDeploymentsResponse.self, from: data)
            return decoded.deployments
        } catch let error as VercelServiceError {
            throw error
        } catch {
            throw VercelServiceError.networkError(error.localizedDescription)
        }
    }
}
