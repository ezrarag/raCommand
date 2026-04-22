//
//  GitHubCollaboratorsService.swift
//  raCommand
//
//  Fetch, invite, and remove GitHub collaborators for a repo.
//  All calls require a token with 'repo' scope.
//

import Foundation

// MARK: - Models

struct GitHubCollaborator: Identifiable, Decodable, Hashable {
    let id: Int
    let login: String
    let avatarURL: String
    let htmlURL: String
    let roleInRepo: String?          // "admin" | "write" | "read" | nil

    enum CodingKeys: String, CodingKey {
        case id
        case login
        case avatarURL  = "avatar_url"
        case htmlURL    = "html_url"
        case roleInRepo = "role_name"
    }
}

struct GitHubInvitation: Identifiable, Decodable {
    let id: Int
    let login: String?               // invitee login (if they have a GitHub account)
    let email: String?               // invitee email (if invited by email)
    let role: String                 // "read" | "write" | "admin"
    let inviter: InviterInfo

    var displayName: String { login ?? email ?? "Unknown" }

    struct InviterInfo: Decodable {
        let login: String
    }

    enum CodingKeys: String, CodingKey {
        case id
        case login
        case email
        case role
        case inviter
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id      = try container.decode(Int.self, forKey: .id)
        role    = try container.decode(String.self, forKey: .role)
        inviter = try container.decode(InviterInfo.self, forKey: .inviter)

        // Nested invitee object
        struct InviteeInfo: Decodable {
            let login: String?
            let email: String?
        }
        if let invitee = try? container.decodeIfPresent(InviteeInfo.self, forKey: .login) {
            login = invitee.login
            email = invitee.email
        } else {
            login = try? container.decodeIfPresent(String.self, forKey: .login)
            email = try? container.decodeIfPresent(String.self, forKey: .email)
        }
    }
}

enum CollaboratorPermission: String, CaseIterable, Identifiable {
    case read    = "pull"
    case write   = "push"
    case admin   = "admin"

    var id: String { rawValue }

    var label: String {
        switch self {
        case .read:  return "Read"
        case .write: return "Write"
        case .admin: return "Admin"
        }
    }

    var description: String {
        switch self {
        case .read:  return "Can view and clone the repo"
        case .write: return "Can push code and manage issues"
        case .admin: return "Full control including settings"
        }
    }
}

// MARK: - Errors

enum CollaboratorError: LocalizedError {
    case invalidRepoURL
    case notFound
    case forbidden
    case alreadyCollaborator
    case networkError(String)

    var errorDescription: String? {
        switch self {
        case .invalidRepoURL:       return "Could not parse a valid owner/repo from the URL."
        case .notFound:             return "Repo not found — check the URL and token scope."
        case .forbidden:            return "Your token doesn't have permission for this action."
        case .alreadyCollaborator:  return "That user is already a collaborator."
        case .networkError(let m):  return m
        }
    }
}

// MARK: - Service

enum GitHubCollaboratorsService {

    // MARK: Parse owner/repo from URL

    static func ownerRepo(from repoURL: String) -> (owner: String, repo: String)? {
        let cleaned = repoURL
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: ".git", with: "")

        guard let url = URL(string: cleaned) else { return nil }
        let parts = url.pathComponents.filter { $0 != "/" }
        guard parts.count >= 2 else { return nil }
        return (parts[0], parts[1])
    }

    // MARK: List collaborators

    static func fetchCollaborators(repoURL: String, token: String) async throws -> [GitHubCollaborator] {
        guard let (owner, repo) = ownerRepo(from: repoURL) else {
            throw CollaboratorError.invalidRepoURL
        }

        guard let url = URL(string: "https://api.github.com/repos/\(owner)/\(repo)/collaborators?per_page=100&affiliation=direct") else {
            throw CollaboratorError.invalidRepoURL
        }

        let request = authorizedRequest(url: url, token: token)
        let (data, response) = try await URLSession.shared.data(for: request)
        try checkStatus(response, data: data)
        return try JSONDecoder().decode([GitHubCollaborator].self, from: data)
    }

    // MARK: List pending invitations

    static func fetchInvitations(repoURL: String, token: String) async throws -> [GitHubInvitation] {
        guard let (owner, repo) = ownerRepo(from: repoURL) else {
            throw CollaboratorError.invalidRepoURL
        }

        guard let url = URL(string: "https://api.github.com/repos/\(owner)/\(repo)/invitations?per_page=100") else {
            throw CollaboratorError.invalidRepoURL
        }

        let request = authorizedRequest(url: url, token: token)
        let (data, response) = try await URLSession.shared.data(for: request)
        try checkStatus(response, data: data)
        return try JSONDecoder().decode([GitHubInvitation].self, from: data)
    }

    // MARK: Invite collaborator

    @discardableResult
    static func invite(
        username: String,
        permission: CollaboratorPermission,
        repoURL: String,
        token: String
    ) async throws -> Bool {
        guard let (owner, repo) = ownerRepo(from: repoURL) else {
            throw CollaboratorError.invalidRepoURL
        }

        let trimmed = username.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "@", with: "")
        guard !trimmed.isEmpty else { throw CollaboratorError.invalidRepoURL }

        guard let url = URL(string: "https://api.github.com/repos/\(owner)/\(repo)/collaborators/\(trimmed)") else {
            throw CollaboratorError.invalidRepoURL
        }

        var request = authorizedRequest(url: url, token: token, method: "PUT")
        let body = ["permission": permission.rawValue]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0

        // 201 = invitation sent, 204 = already a collaborator (accepted)
        if status == 201 || status == 204 { return true }
        if status == 422 { throw CollaboratorError.alreadyCollaborator }
        try checkStatus(response, data: data)
        return false
    }

    // MARK: Remove collaborator

    static func remove(username: String, repoURL: String, token: String) async throws {
        guard let (owner, repo) = ownerRepo(from: repoURL) else {
            throw CollaboratorError.invalidRepoURL
        }

        guard let url = URL(string: "https://api.github.com/repos/\(owner)/\(repo)/collaborators/\(username)") else {
            throw CollaboratorError.invalidRepoURL
        }

        let request = authorizedRequest(url: url, token: token, method: "DELETE")
        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        if status == 204 { return }
        try checkStatus(response, data: data)
    }

    // MARK: Cancel invitation

    static func cancelInvitation(id: Int, repoURL: String, token: String) async throws {
        guard let (owner, repo) = ownerRepo(from: repoURL) else {
            throw CollaboratorError.invalidRepoURL
        }

        guard let url = URL(string: "https://api.github.com/repos/\(owner)/\(repo)/invitations/\(id)") else {
            throw CollaboratorError.invalidRepoURL
        }

        let request = authorizedRequest(url: url, token: token, method: "DELETE")
        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        if status == 204 { return }
        try checkStatus(response, data: data)
    }

    // MARK: - Helpers

    private static func authorizedRequest(url: URL, token: String, method: String = "GET") -> URLRequest {
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("token \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("raCommand", forHTTPHeaderField: "User-Agent")
        if method == "PUT" || method == "POST" {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        return request
    }

    private static func checkStatus(_ response: URLResponse, data: Data) throws {
        guard let http = response as? HTTPURLResponse else { return }
        switch http.statusCode {
        case 200...299: return
        case 401, 403:  throw CollaboratorError.forbidden
        case 404:       throw CollaboratorError.notFound
        default:
            let message = (try? JSONDecoder().decode([String: String].self, from: data))?["message"] ?? "HTTP \(http.statusCode)"
            throw CollaboratorError.networkError(message)
        }
    }
}
