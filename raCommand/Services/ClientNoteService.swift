//
//  ClientNoteService.swift
//  raCommand
//
//  Reads client feedback and RAG notes from clients.readyaimgo.biz.
//  Also provisions new client portal accounts directly from raCommand.
//

import Foundation

// MARK: - Feedback Model

struct ClientFeedback: Identifiable, Decodable, Hashable {
    let id: String
    let projectId: String
    let projectTitle: String?
    let projectType: String?
    let workspaceId: String?
    let clientName: String
    let clientEmail: String?
    let rawText: String?
    let loomUrl: String?
    let pageUrl: String?
    let summary: String
    let category: String
    let urgency: String
    let actionable: Bool
    let suggestedAction: String
    let pulseScore: Int
    let status: String
    let source: String
    let agentContextStatus: String?
    let createdAt: String?

    var urgencyLevel: UrgencyLevel { UrgencyLevel(rawValue: urgency) ?? .medium }
    var isProjectSuggestion: Bool { source == "workspace-project-suggestion" }

    enum UrgencyLevel: String {
        case low, medium, high
        var label: String { rawValue.capitalized }
    }
}

// MARK: - Portal Client Model

struct PortalClient: Identifiable, Decodable, Hashable {
    let email: String
    let name: String
    let companyName: String?
    let planType: String?
    let onboardingStatus: String?
    let serviceInterests: [String]?
    let hasUnreadRagNotes: Bool?
    let lastRagNoteAt: String?

    var id: String { email }
    var displayName: String { name.isEmpty ? email : name }
    var initials: String {
        let parts = name.split(separator: " ")
        if parts.count >= 2 {
            return "\(parts[0].prefix(1))\(parts[1].prefix(1))".uppercased()
        }
        return String(name.prefix(2)).uppercased()
    }
}

struct DesktopClient: Identifiable, Decodable, Hashable {
    let id: String
    let name: String
    let storyId: String?

    var displayName: String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? (storyId ?? id) : trimmed
    }

    var initials: String {
        let words = displayName.split(whereSeparator: \.isWhitespace)
        if words.count >= 2 {
            return "\(words[0].prefix(1))\(words[1].prefix(1))".uppercased()
        }

        let compact = displayName.replacingOccurrences(of: " ", with: "")
        return String(compact.prefix(2)).uppercased()
    }
}

// MARK: - RAG Note Model

struct RagNote: Identifiable, Decodable, Hashable {
    let id: String
    let subject: String
    let body: String
    let type: String        // "note" | "pulse" | "update"
    let authorName: String
    let read: Bool
    let createdAt: String?

    var typeLabel: String {
        switch type {
        case "pulse": return "Pulse summary"
        case "update": return "Project update"
        default: return "Team note"
        }
    }
}

// MARK: - Provision Input

struct ClientProvisionInput {
    let fullName: String
    let email: String
    let companyName: String
    let phone: String
    let role: String
    let organizationType: String
    let serviceInterests: [String]
    let notes: String
    let projectName: String     // used to pre-fill the handoff context
    let repoURL: String
}

// MARK: - Errors

enum ClientNoteError: LocalizedError {
    case noBaseURL
    case missingDesktopSessionToken
    case invalidResponse
    case serverError(String)
    case provisionFailed(String)

    var errorDescription: String? {
        switch self {
        case .noBaseURL:            return "Client portal URL is not configured."
        case .missingDesktopSessionToken:
            return "Desktop API token is missing. Set RAG_INTERNAL_API_KEY or save a desktop session token."
        case .invalidResponse:      return "Unexpected response from the feedback server."
        case .serverError(let m):   return m
        case .provisionFailed(let m): return m
        }
    }
}

// MARK: - Service

enum ClientNoteService {

    static var baseURL: String {
        ProcessInfo.processInfo.environment["RAG_CLIENTS_URL"]
            ?? "https://clients.readyaimgo.biz"
    }

    static var desktopBaseURL: String {
        ProcessInfo.processInfo.environment["RAG_MAIN_SITE_URL"]
            ?? "https://readyaimgo.biz"
    }

    // MARK: - Feedback

    static func fetchFeedback(projectId: String, status: String? = nil) async throws -> [ClientFeedback] {
        var components = URLComponents(string: "\(baseURL)/api/feedback")!
        var items = [URLQueryItem(name: "projectId", value: projectId)]
        if let status { items.append(URLQueryItem(name: "status", value: status)) }
        components.queryItems = items
        guard let url = components.url else { throw ClientNoteError.invalidResponse }

        let (data, response) = try await URLSession.shared.data(from: url)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            let msg = (try? JSONDecoder().decode([String: String].self, from: data))?["error"] ?? "Unknown error"
            throw ClientNoteError.serverError(msg)
        }
        struct R: Decodable { let feedback: [ClientFeedback] }
        return try JSONDecoder().decode(R.self, from: data).feedback
    }

    static func acknowledge(feedbackId: String) async throws {
        try await updateFeedbackStatus(feedbackId: feedbackId, status: "acknowledged")
    }

    static func resolve(feedbackId: String, note: String = "") async throws {
        try await updateFeedbackStatus(feedbackId: feedbackId, status: "resolved", resolvedNote: note)
    }

    static func feedbackURL(for projectId: String) -> String {
        "\(baseURL)/feedback/\(projectId)"
    }

    private static func updateFeedbackStatus(feedbackId: String, status: String, resolvedNote: String = "") async throws {
        guard let url = URL(string: "\(baseURL)/api/feedback") else { throw ClientNoteError.noBaseURL }
        var req = URLRequest(url: url)
        req.httpMethod = "PATCH"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        var body: [String: Any] = ["feedbackId": feedbackId, "status": status]
        if !resolvedNote.isEmpty { body["resolvedNote"] = resolvedNote }
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, response) = try await URLSession.shared.data(for: req)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            let msg = (try? JSONDecoder().decode([String: String].self, from: data))?["error"] ?? "Update failed"
            throw ClientNoteError.serverError(msg)
        }
    }

    // MARK: - RAG Notes

    static func sendRagNote(
        clientEmail: String,
        subject: String,
        body: String,
        type: String = "note",
        authorName: String = "Readyaimgo Team",
        authorEmail: String = ""
    ) async throws {
        guard let url = URL(string: "\(baseURL)/api/rag-notes") else { throw ClientNoteError.noBaseURL }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let payload: [String: Any] = [
            "clientEmail": clientEmail,
            "subject": subject,
            "body": body,
            "type": type,
            "authorName": authorName,
            "authorEmail": authorEmail
        ]
        req.httpBody = try JSONSerialization.data(withJSONObject: payload)
        let (data, response) = try await URLSession.shared.data(for: req)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            let msg = (try? JSONDecoder().decode([String: String].self, from: data))?["error"] ?? "Send failed"
            throw ClientNoteError.serverError(msg)
        }
    }

    static func fetchRagNotes(clientEmail: String) async throws -> [RagNote] {
        var components = URLComponents(string: "\(baseURL)/api/rag-notes")!
        components.queryItems = [URLQueryItem(name: "clientEmail", value: clientEmail)]
        guard let url = components.url else { throw ClientNoteError.invalidResponse }
        let (data, response) = try await URLSession.shared.data(from: url)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            let msg = (try? JSONDecoder().decode([String: String].self, from: data))?["error"] ?? "Fetch failed"
            throw ClientNoteError.serverError(msg)
        }
        struct R: Decodable { let notes: [RagNote] }
        return try JSONDecoder().decode(R.self, from: data).notes
    }

    // MARK: - Desktop Ideas

    static func fetchDesktopClients() async throws -> [DesktopClient] {
        guard let url = URL(string: "\(desktopBaseURL)/api/desktop/clients") else {
            throw ClientNoteError.noBaseURL
        }

        var request = URLRequest(url: url)
        try applyDesktopAuthorization(to: &request)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            let msg = (try? JSONDecoder().decode([String: String].self, from: data))?["error"] ?? "Failed to load clients"
            throw ClientNoteError.serverError(msg)
        }

        struct Response: Decodable {
            let clients: [DesktopClient]
        }

        return try JSONDecoder().decode(Response.self, from: data).clients
    }

    static func fetchIdeaCount(clientId: String) async throws -> Int {
        guard let url = URL(string: "\(desktopBaseURL)/api/desktop/clients/\(clientId.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? clientId)/ideas") else {
            throw ClientNoteError.noBaseURL
        }

        var request = URLRequest(url: url)
        try applyDesktopAuthorization(to: &request)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            let msg = (try? JSONDecoder().decode([String: String].self, from: data))?["error"] ?? "Failed to load ideas"
            throw ClientNoteError.serverError(msg)
        }

        struct Response: Decodable {
            let count: Int
        }

        return try JSONDecoder().decode(Response.self, from: data).count
    }

    static func submitIdea(clientId: String, text: String) async throws {
        guard let url = URL(string: "\(desktopBaseURL)/api/desktop/clients/\(clientId.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? clientId)/ideas") else {
            throw ClientNoteError.noBaseURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        try applyDesktopAuthorization(to: &request)
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "text": text
        ])

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            let msg = (try? JSONDecoder().decode([String: String].self, from: data))?["error"] ?? "Failed to save idea"
            throw ClientNoteError.serverError(msg)
        }
    }

    // MARK: - Portal Account Provisioning
    //
    // Creates a handoff record on readyaimgo.biz via the client-handoff API.
    // The client then receives a signup link they can use to create their
    // portal account — no password set by us, no admin-created accounts.

    static func provisionClientPortalAccess(input: ClientProvisionInput) async throws -> String {
        // The handoff goes to the main RAG site, which creates the record
        // and returns a portal signup URL the client uses.
        let ragSiteURL = ProcessInfo.processInfo.environment["RAG_MAIN_SITE_URL"]
            ?? "https://readyaimgo.biz"

        guard let url = URL(string: "\(ragSiteURL)/api/client-handoff") else {
            throw ClientNoteError.provisionFailed("Could not build handoff URL.")
        }

        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let payload: [String: Any] = [
            "mode": "new",
            "destination": "/signup",
            "contactName": input.fullName,
            "workEmail": input.email,
            "companyName": input.companyName,
            "phone": input.phone,
            "role": input.role,
            "organizationType": input.organizationType,
            "serviceInterests": input.serviceInterests,
            "notes": input.notes.isEmpty
                ? "Added from raCommand for project: \(input.projectName)"
                : input.notes
        ]
        req.httpBody = try JSONSerialization.data(withJSONObject: payload)

        let (data, response) = try await URLSession.shared.data(for: req)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            let msg = (try? JSONDecoder().decode([String: String].self, from: data))?["error"] ?? "Provision failed"
            throw ClientNoteError.provisionFailed(msg)
        }

        struct ProvisionResponse: Decodable {
            let success: Bool
            let portalUrl: String?
            let handoffId: String?
        }
        let result = try JSONDecoder().decode(ProvisionResponse.self, from: data)
        guard let portalUrl = result.portalUrl else {
            throw ClientNoteError.provisionFailed("No portal URL returned.")
        }
        return portalUrl
    }

    private static func applyDesktopAuthorization(to request: inout URLRequest) throws {
        let token = KeychainService.loadDesktopSessionToken()
            ?? ProcessInfo.processInfo.environment["RAG_INTERNAL_API_KEY"]
            ?? ProcessInfo.processInfo.environment["READYAIMGO_INTERNAL_API_KEY"]

        guard let token, !token.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ClientNoteError.missingDesktopSessionToken
        }

        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
    }
}

// MARK: - Pulse helper

extension ClientFeedback {
    var priorityBoost: Int {
        guard status == "open" else { return 0 }
        return pulseScore
    }
    var isVideo: Bool { loomUrl != nil }
    var isFromExtension: Bool { source == "extension" }
}
