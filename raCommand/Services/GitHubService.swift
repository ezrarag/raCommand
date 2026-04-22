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
            if let httpResponse = response as? HTTPURLResponse,
               httpResponse.statusCode == 401 {
                throw URLError(.userAuthenticationRequired)
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
