//
//  GitHubProjectInsightService.swift
//  raCommand
//
//  Read-only GitHub state inspection for Pulse queries.
//

import Foundation

struct GitHubIssueSummary: Identifiable, Hashable {
    let id: Int
    let number: Int
    let title: String
    let htmlURL: String
    let authorLogin: String
    let updatedAt: Date?
}

struct GitHubPullRequestSummary: Identifiable, Hashable {
    let id: Int
    let number: Int
    let title: String
    let htmlURL: String
    let authorLogin: String
    let updatedAt: Date?
    let isDraft: Bool
}

struct GitHubCommitSummary: Hashable {
    let sha: String
    let shortSHA: String
    let message: String
    let authorName: String?
    let date: Date?
}

struct GitHubProjectSnapshot {
    let owner: String
    let repo: String
    let defaultBranch: String
    let pushedAt: Date?
    let openIssues: [GitHubIssueSummary]
    let openPullRequests: [GitHubPullRequestSummary]
    let recentCommits: [GitHubCommitSummary]
}

enum GitHubProjectInsightError: LocalizedError {
    case invalidRepoURL
    case invalidResponse
    case forbidden
    case notFound
    case apiError(String)

    var errorDescription: String? {
        switch self {
        case .invalidRepoURL:
            return "Could not parse a valid GitHub owner and repo from the project URL."
        case .invalidResponse:
            return "GitHub returned an unexpected response."
        case .forbidden:
            return "GitHub rejected the request. Check your token and repo permissions."
        case .notFound:
            return "GitHub could not find that repository."
        case .apiError(let message):
            return message
        }
    }
}

enum GitHubProjectInsightService {
    static func fetchSnapshot(repoURL: String, token: String?) async throws -> GitHubProjectSnapshot {
        guard let (owner, repo) = GitHubCollaboratorsService.ownerRepo(from: repoURL) else {
            throw GitHubProjectInsightError.invalidRepoURL
        }

        async let repoResponse: RepoResponse = request(
            path: "/repos/\(owner)/\(repo)",
            token: token
        )
        async let pullResponses: [PullResponse] = request(
            path: "/repos/\(owner)/\(repo)/pulls?state=open&per_page=5",
            token: token
        )
        async let issueResponses: [IssueResponse] = request(
            path: "/repos/\(owner)/\(repo)/issues?state=open&per_page=10",
            token: token
        )
        async let commitResponses: [CommitResponse] = request(
            path: "/repos/\(owner)/\(repo)/commits?per_page=3",
            token: token
        )

        let repoMetadata = try await repoResponse
        let pulls = try await pullResponses
        let issues = try await issueResponses
        let commits = try await commitResponses

        return GitHubProjectSnapshot(
            owner: owner,
            repo: repo,
            defaultBranch: repoMetadata.defaultBranch,
            pushedAt: repoMetadata.pushedAt,
            openIssues: issues
                .filter { !$0.isPullRequest }
                .map {
                    GitHubIssueSummary(
                        id: $0.id,
                        number: $0.number,
                        title: $0.title,
                        htmlURL: $0.htmlURL,
                        authorLogin: $0.user.login,
                        updatedAt: $0.updatedAt
                    )
                },
            openPullRequests: pulls.map {
                GitHubPullRequestSummary(
                    id: $0.id,
                    number: $0.number,
                    title: $0.title,
                    htmlURL: $0.htmlURL,
                    authorLogin: $0.user.login,
                    updatedAt: $0.updatedAt,
                    isDraft: $0.draft
                )
            },
            recentCommits: commits.map {
                GitHubCommitSummary(
                    sha: $0.sha,
                    shortSHA: String($0.sha.prefix(7)),
                    message: $0.commit.message.components(separatedBy: "\n").first ?? $0.commit.message,
                    authorName: $0.commit.author.name,
                    date: $0.commit.author.date
                )
            }
        )
    }

    private static func request<T: Decodable>(path: String, token: String?) async throws -> T {
        guard let url = URL(string: "https://api.github.com\(path)") else {
            throw GitHubProjectInsightError.invalidResponse
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("raCommand", forHTTPHeaderField: "User-Agent")
        if let token, !token.isEmpty {
            request.setValue("token \(token)", forHTTPHeaderField: "Authorization")
        }

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw GitHubProjectInsightError.invalidResponse
        }

        switch http.statusCode {
        case 200...299:
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            return try decoder.decode(T.self, from: data)
        case 401, 403:
            throw GitHubProjectInsightError.forbidden
        case 404:
            throw GitHubProjectInsightError.notFound
        default:
            let message = (try? JSONDecoder().decode([String: String].self, from: data))?["message"]
                ?? "GitHub returned HTTP \(http.statusCode)."
            throw GitHubProjectInsightError.apiError(message)
        }
    }
}

private struct RepoResponse: Decodable {
    let defaultBranch: String
    let pushedAt: Date?

    enum CodingKeys: String, CodingKey {
        case defaultBranch = "default_branch"
        case pushedAt = "pushed_at"
    }
}

private struct GitHubUserResponse: Decodable {
    let login: String
}

private struct IssueResponse: Decodable {
    struct PullRequestMarker: Decodable {}

    let id: Int
    let number: Int
    let title: String
    let htmlURL: String
    let user: GitHubUserResponse
    let updatedAt: Date?
    let pullRequest: PullRequestMarker?

    var isPullRequest: Bool { pullRequest != nil }

    enum CodingKeys: String, CodingKey {
        case id
        case number
        case title
        case htmlURL = "html_url"
        case user
        case updatedAt = "updated_at"
        case pullRequest = "pull_request"
    }
}

private struct PullResponse: Decodable {
    let id: Int
    let number: Int
    let title: String
    let htmlURL: String
    let user: GitHubUserResponse
    let updatedAt: Date?
    let draft: Bool

    enum CodingKeys: String, CodingKey {
        case id
        case number
        case title
        case htmlURL = "html_url"
        case user
        case updatedAt = "updated_at"
        case draft
    }
}

private struct CommitResponse: Decodable {
    struct CommitPayload: Decodable {
        struct AuthorPayload: Decodable {
            let name: String?
            let date: Date?
        }

        let message: String
        let author: AuthorPayload
    }

    let sha: String
    let commit: CommitPayload
}
