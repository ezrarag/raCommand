//
//  AIUsageService.swift
//  raCommand
//
//  Token usage across AI providers, using each provider's *organization
//  admin* usage API — a different credential from a normal chat API key:
//
//  - Anthropic: an Admin API key (starts "sk-ant-admin...", issued from
//    the Console's admin settings), calling
//    GET https://api.anthropic.com/v1/organizations/usage_report/messages
//  - OpenAI: an org Admin API key (from platform.openai.com organization
//    settings), calling
//    GET https://api.openai.com/v1/organization/usage/completions
//    This only covers pay-as-you-go API usage. The ChatGPT.com
//    subscription (Plus/Pro/Team message caps) has no public usage API at
//    all, so it can't be tracked here.
//  - Gemini: Google's usage lives in Cloud Monitoring, which needs a
//    service-account OAuth flow rather than a single bearer key — not
//    implemented here; flagged as unsupported in the UI instead of
//    guessing at a shape.
//
//  These endpoint shapes are implemented from documentation, not tested
//  against a live Admin key. If a request fails with a decoding error,
//  the raw response body is surfaced so the shape can be corrected.
//

import Foundation

struct AIUsageSummary {
    let provider: String
    let inputTokens: Int
    let outputTokens: Int
    let requestCount: Int?
    let periodLabel: String

    var totalTokens: Int { inputTokens + outputTokens }
}

enum AIUsageError: LocalizedError {
    case missingKey(String)
    case invalidResponse
    case serverError(String)

    var errorDescription: String? {
        switch self {
        case .missingKey(let provider):
            return "No \(provider) admin API key saved yet."
        case .invalidResponse:
            return "Unexpected response shape from the usage API."
        case .serverError(let message):
            return message
        }
    }
}

enum AIUsageService {
    static func fetchAnthropicUsage(days: Int = 7) async throws -> AIUsageSummary {
        guard let key = KeychainService.loadAnthropicAdminKey(), !key.isEmpty else {
            throw AIUsageError.missingKey("Anthropic")
        }

        let endDate = Date()
        guard let startDate = Calendar.current.date(byAdding: .day, value: -days, to: endDate) else {
            throw AIUsageError.invalidResponse
        }
        let formatter = ISO8601DateFormatter()

        var components = URLComponents(string: "https://api.anthropic.com/v1/organizations/usage_report/messages")!
        components.queryItems = [
            URLQueryItem(name: "starting_at", value: formatter.string(from: startDate)),
            URLQueryItem(name: "ending_at", value: formatter.string(from: endDate)),
            URLQueryItem(name: "bucket_width", value: "1d"),
        ]
        guard let url = components.url else { throw AIUsageError.invalidResponse }

        var request = URLRequest(url: url)
        request.setValue(key, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw AIUsageError.serverError(String(data: data, encoding: .utf8) ?? "Anthropic usage request failed.")
        }

        struct UsageResult: Decodable {
            let uncached_input_tokens: Int?
            let cache_creation_input_tokens: Int?
            let cache_read_input_tokens: Int?
            let output_tokens: Int?
        }
        struct UsageBucket: Decodable {
            let results: [UsageResult]
        }
        struct UsageResponse: Decodable {
            let data: [UsageBucket]
        }

        let decoded: UsageResponse
        do {
            decoded = try JSONDecoder().decode(UsageResponse.self, from: data)
        } catch {
            throw AIUsageError.serverError("Couldn't parse Anthropic's response: \(String(data: data, encoding: .utf8)?.prefix(300) ?? "")")
        }

        let allResults = decoded.data.flatMap(\.results)
        let inputTokens = allResults.reduce(0) {
            $0 + ($1.uncached_input_tokens ?? 0) + ($1.cache_creation_input_tokens ?? 0) + ($1.cache_read_input_tokens ?? 0)
        }
        let outputTokens = allResults.reduce(0) { $0 + ($1.output_tokens ?? 0) }

        return AIUsageSummary(
            provider: "Anthropic",
            inputTokens: inputTokens,
            outputTokens: outputTokens,
            requestCount: nil,
            periodLabel: "Last \(days) days"
        )
    }

    static func fetchOpenAIUsage(days: Int = 7) async throws -> AIUsageSummary {
        guard let key = KeychainService.loadOpenAIAdminKey(), !key.isEmpty else {
            throw AIUsageError.missingKey("OpenAI")
        }

        guard let startDate = Calendar.current.date(byAdding: .day, value: -days, to: Date()) else {
            throw AIUsageError.invalidResponse
        }
        let startTime = Int(startDate.timeIntervalSince1970)

        var components = URLComponents(string: "https://api.openai.com/v1/organization/usage/completions")!
        components.queryItems = [
            URLQueryItem(name: "start_time", value: String(startTime)),
            URLQueryItem(name: "bucket_width", value: "1d"),
        ]
        guard let url = components.url else { throw AIUsageError.invalidResponse }

        var request = URLRequest(url: url)
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw AIUsageError.serverError(String(data: data, encoding: .utf8) ?? "OpenAI usage request failed.")
        }

        struct UsageResult: Decodable {
            let input_tokens: Int?
            let output_tokens: Int?
            let num_model_requests: Int?
        }
        struct UsageBucket: Decodable {
            let results: [UsageResult]
        }
        struct UsageResponse: Decodable {
            let data: [UsageBucket]
        }

        let decoded: UsageResponse
        do {
            decoded = try JSONDecoder().decode(UsageResponse.self, from: data)
        } catch {
            throw AIUsageError.serverError("Couldn't parse OpenAI's response: \(String(data: data, encoding: .utf8)?.prefix(300) ?? "")")
        }

        let allResults = decoded.data.flatMap(\.results)
        let inputTokens = allResults.reduce(0) { $0 + ($1.input_tokens ?? 0) }
        let outputTokens = allResults.reduce(0) { $0 + ($1.output_tokens ?? 0) }
        let requests = allResults.reduce(0) { $0 + ($1.num_model_requests ?? 0) }

        return AIUsageSummary(
            provider: "OpenAI (API)",
            inputTokens: inputTokens,
            outputTokens: outputTokens,
            requestCount: requests,
            periodLabel: "Last \(days) days"
        )
    }
}
