//
//  GitHubActionsService.swift
//  raCommand
//
//  Handles GitHub repo creation and clone command generation.
//

import Foundation

struct GitHubCreateRepoResponse: Decodable {
    let htmlURL: String
    let cloneURL: String
    let name: String

    enum CodingKeys: String, CodingKey {
        case htmlURL = "html_url"
        case cloneURL = "clone_url"
        case name
    }
}

private struct GitHubErrorResponse: Decodable {
    let message: String
}

enum GitHubActionsError: LocalizedError {
    case authenticationRequired
    case insufficientTokenPermissions
    case apiError(String)
    case invalidResponse

    var errorDescription: String? {
        switch self {
        case .authenticationRequired:
            return "No GitHub token found, or the saved token no longer works."
        case .insufficientTokenPermissions:
            return "This GitHub token can read repos but cannot create new ones. Use a classic PAT with `public_repo` or `repo`, or a fine-grained PAT for your personal account with repository Administration permission set to write."
        case .apiError(let message):
            return message
        case .invalidResponse:
            return "GitHub returned an unexpected response."
        }
    }
}

enum GitHubActionsService {

    // MARK: - Create a new repo on GitHub
    static func createRepo(
        name: String,
        description: String = "",
        isPrivate: Bool = false,
        token: String
    ) async throws -> GitHubCreateRepoResponse {
        guard let url = URL(string: "https://api.github.com/user/repos") else {
            throw URLError(.badURL)
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("token \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
        request.setValue("raCommand", forHTTPHeaderField: "User-Agent")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: Any] = [
            "name": name,
            "description": description,
            "private": isPrivate,
            "auto_init": true
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw GitHubActionsError.invalidResponse
        }

        guard (200..<300).contains(httpResponse.statusCode) else {
            let message = (try? JSONDecoder().decode(GitHubErrorResponse.self, from: data).message)
                ?? HTTPURLResponse.localizedString(forStatusCode: httpResponse.statusCode)
            let normalizedMessage = message.lowercased()

            if httpResponse.statusCode == 401 {
                throw GitHubActionsError.authenticationRequired
            }

            if normalizedMessage.contains("resource not accessible by personal access token") {
                throw GitHubActionsError.insufficientTokenPermissions
            }

            throw GitHubActionsError.apiError(message)
        }

        return try JSONDecoder().decode(GitHubCreateRepoResponse.self, from: data)
    }

    // MARK: - Clone command string for clipboard
    static func cloneCommand(repoURL: String) -> String {
        guard !repoURL.isEmpty else { return "" }
        let escaped = "~/Desktop/local\\ dev"
        return "git clone \(repoURL) \(escaped)"
    }

    // MARK: - New repo script command for clipboard
    static func newRepoCommand(repoName: String) -> String {
        guard !repoName.isEmpty else { return "" }
        return "bash ~/scripts/new-repo.sh \"\(repoName)\""
    }
}
