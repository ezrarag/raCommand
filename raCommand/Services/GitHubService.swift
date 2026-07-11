//
//  GitHubService.swift
//  raCommand
//
//  Created by E. Haugabrooks on 2/1/26.
//

import Foundation

struct GitHubRepo: Identifiable, Decodable, Hashable {
    let id: Int
    let name: String
    let description: String?
    let htmlURL: String

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case description
        case htmlURL = "html_url"
    }
}

private struct GitHubAPIErrorResponse: Decodable {
    let message: String
}

enum GitHubServiceError: LocalizedError {
    case authenticationRequired
    case insufficientPermissions(String)
    case apiError(String)
    case invalidResponse

    var errorDescription: String? {
        switch self {
        case .authenticationRequired:
            return "GitHub rejected the saved token. It may be expired, revoked, or missing SSO authorization."
        case .insufficientPermissions(let message):
            return message
        case .apiError(let message):
            return message
        case .invalidResponse:
            return "GitHub returned an unexpected response."
        }
    }
}

enum GitHubService {
    static func fetchRepos(token: String) async throws -> [GitHubRepo] {
        var repos: [GitHubRepo] = []
        var page = 1

        while true {
            guard let url = URL(string: "https://api.github.com/user/repos?per_page=100&page=\(page)") else {
                break
            }

            var request = URLRequest(url: url)
            request.setValue("token \(token)", forHTTPHeaderField: "Authorization")
            request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
            request.setValue("raCommand", forHTTPHeaderField: "User-Agent")

            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else {
                throw GitHubServiceError.invalidResponse
            }

            guard (200..<300).contains(httpResponse.statusCode) else {
                let message = (try? JSONDecoder().decode(GitHubAPIErrorResponse.self, from: data).message)
                    ?? HTTPURLResponse.localizedString(forStatusCode: httpResponse.statusCode)
                let normalizedMessage = message.lowercased()

                if httpResponse.statusCode == 401 {
                    throw GitHubServiceError.authenticationRequired
                }

                if httpResponse.statusCode == 403 || normalizedMessage.contains("resource not accessible by personal access token") {
                    if normalizedMessage.contains("sso") {
                        throw GitHubServiceError.insufficientPermissions("This token needs SSO authorization for GitHub before raCommand can list repos.")
                    }

                    throw GitHubServiceError.insufficientPermissions("This token cannot list your repos. Use a classic PAT with `repo` or `public_repo`, or a fine-grained token with repository access plus Metadata read permission.")
                }

                throw GitHubServiceError.apiError(message)
            }

            let pageRepos = try JSONDecoder().decode([GitHubRepo].self, from: data)
            repos.append(contentsOf: pageRepos)

            if pageRepos.count < 100 {
                break
            }
            page += 1
        }

        return repos
    }
}
