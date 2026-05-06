//
//  AIThreadModels.swift
//  raCommand
//
//  Unified AI Thread Registry — source-agnostic models that describe
//  a single conversation/session regardless of producer (Claude Code,
//  Claude chat export, Anthropic API, Codex, …).
//
//  See CLAUDE_CODE_PROMPT_CLAUDE_THREADS_ARCHITECTURE.md for the
//  full architectural contract.
//

import Foundation

// MARK: - Source

/// Where this thread originated.
enum AIThreadSource: String, Codable, CaseIterable, Identifiable, Hashable {
    case claudeCode               // Local Claude Code JSONL transcripts (~/.claude/projects)
    case claudeChatExport         // User-imported Claude data export
    case claudeChatSharedLink     // Read-only snapshot of a shared chat URL
    case claudeEnterpriseCompliance  // Backend sync via Enterprise Compliance API
    case anthropicAPI             // raCommand-owned Anthropic Messages API conversation
    case codex                    // Codex sessions
    case manual                   // User-authored/curated thread

    var id: String { rawValue }

    /// Short label used in badges / source pickers.
    var displayLabel: String {
        switch self {
        case .claudeCode: return "Claude Code"
        case .claudeChatExport: return "Claude Export"
        case .claudeChatSharedLink: return "Shared Link"
        case .claudeEnterpriseCompliance: return "Compliance API"
        case .anthropicAPI: return "Anthropic API"
        case .codex: return "Codex"
        case .manual: return "Manual"
        }
    }
}

// MARK: - Capabilities

/// What raCommand can do with a given thread.
struct AIThreadCapabilities: OptionSet, Codable, Hashable {
    let rawValue: Int
    init(rawValue: Int) { self.rawValue = rawValue }

    /// External link/path to the original thread (e.g. claude.ai URL, JSONL path).
    static let canOpenOriginal       = AIThreadCapabilities(rawValue: 1 << 0)
    /// Full message text can be pulled into local SwiftData / displayed.
    static let canImportTranscript   = AIThreadCapabilities(rawValue: 1 << 1)
    /// Generated files / artifacts can be copied into the workspace.
    static let canImportArtifacts    = AIThreadCapabilities(rawValue: 1 << 2)
    /// The original session can be resumed in-place (e.g. `claude --resume`).
    static let canResumeOriginal     = AIThreadCapabilities(rawValue: 1 << 3)
    /// raCommand can host a "shadow" continuation in a new thread.
    static let canShadowChat         = AIThreadCapabilities(rawValue: 1 << 4)
    /// New activity can be pulled incrementally (e.g. compliance API).
    static let canSyncIncrementally  = AIThreadCapabilities(rawValue: 1 << 5)

    /// Capability set for a freshly-discovered local Claude Code session.
    static let claudeCodeDefault: AIThreadCapabilities = [
        .canOpenOriginal, .canImportTranscript, .canImportArtifacts,
        .canResumeOriginal, .canShadowChat
    ]

    /// Imported Claude chat exports: never resumable.
    static let claudeChatExportDefault: AIThreadCapabilities = [
        .canImportTranscript, .canShadowChat
    ]

    /// Read-only snapshots from shared links.
    static let sharedLinkDefault: AIThreadCapabilities = [
        .canOpenOriginal, .canImportTranscript, .canShadowChat
    ]
}

extension AIThreadCapabilities {
    /// Stable label set used by ragIntelligence / backend DTOs.
    var stringLabels: [String] {
        var labels: [String] = []
        if contains(.canOpenOriginal)      { labels.append("canOpenOriginal") }
        if contains(.canImportTranscript)  { labels.append("canImportTranscript") }
        if contains(.canImportArtifacts)   { labels.append("canImportArtifacts") }
        if contains(.canResumeOriginal)    { labels.append("canResumeOriginal") }
        if contains(.canShadowChat)        { labels.append("canShadowChat") }
        if contains(.canSyncIncrementally) { labels.append("canSyncIncrementally") }
        return labels
    }
}

// MARK: - Thread Record

/// One discovered/imported conversation.
struct AIThreadRecord: Identifiable, Codable, Hashable {
    var id: String                    // raCommand-stable id (typically "<source>:<externalId>")
    var source: AIThreadSource
    var externalId: String?           // session id, conversation uuid, etc.
    var title: String
    var summary: String
    var sourceURL: String?            // external link if available
    var localTranscriptPath: String?  // absolute path to JSONL / export file
    var workspacePath: String?        // cwd / repo root the conversation targeted
    var repoURL: String?
    var clientId: String?
    var projectId: String?
    var parentThreadId: String?       // for shadow continuations
    var createdAt: Date?
    var lastActivityAt: Date?
    var importedAt: Date?
    var messageCount: Int
    var artifactCount: Int
    var capabilities: AIThreadCapabilities
    var confidence: Double            // [0, 1] — used when project mapping is inferred
    var model: String?
    var gitBranch: String?

    init(
        id: String,
        source: AIThreadSource,
        externalId: String? = nil,
        title: String,
        summary: String = "",
        sourceURL: String? = nil,
        localTranscriptPath: String? = nil,
        workspacePath: String? = nil,
        repoURL: String? = nil,
        clientId: String? = nil,
        projectId: String? = nil,
        parentThreadId: String? = nil,
        createdAt: Date? = nil,
        lastActivityAt: Date? = nil,
        importedAt: Date? = nil,
        messageCount: Int = 0,
        artifactCount: Int = 0,
        capabilities: AIThreadCapabilities = [],
        confidence: Double = 1.0,
        model: String? = nil,
        gitBranch: String? = nil
    ) {
        self.id = id
        self.source = source
        self.externalId = externalId
        self.title = title
        self.summary = summary
        self.sourceURL = sourceURL
        self.localTranscriptPath = localTranscriptPath
        self.workspacePath = workspacePath
        self.repoURL = repoURL
        self.clientId = clientId
        self.projectId = projectId
        self.parentThreadId = parentThreadId
        self.createdAt = createdAt
        self.lastActivityAt = lastActivityAt
        self.importedAt = importedAt
        self.messageCount = messageCount
        self.artifactCount = artifactCount
        self.capabilities = capabilities
        self.confidence = confidence
        self.model = model
        self.gitBranch = gitBranch
    }

    var displayTitle: String {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty { return trimmed }
        if let ext = externalId { return ext }
        return id
    }

    var groupKey: String {
        if let p = projectId, !p.isEmpty { return "project:\(p)" }
        if let c = clientId, !c.isEmpty  { return "client:\(c)" }
        return "uncategorized"
    }
}

// MARK: - Message Record

/// One message inside a thread.
struct AIThreadMessageRecord: Identifiable, Codable, Hashable {
    var id: String
    var threadId: String
    var role: String                  // "user", "assistant", "system", "tool"
    var text: String
    var createdAt: Date?
    var sourceOffset: Int?            // line offset in JSONL / index in export
    var hasToolUse: Bool
    var redactionState: String        // "raw", "redacted", "summarized"

    init(
        id: String,
        threadId: String,
        role: String,
        text: String,
        createdAt: Date? = nil,
        sourceOffset: Int? = nil,
        hasToolUse: Bool = false,
        redactionState: String = "raw"
    ) {
        self.id = id
        self.threadId = threadId
        self.role = role
        self.text = text
        self.createdAt = createdAt
        self.sourceOffset = sourceOffset
        self.hasToolUse = hasToolUse
        self.redactionState = redactionState
    }
}

// MARK: - Artifact Record

struct AIThreadArtifactRecord: Identifiable, Codable, Hashable {
    var id: String
    var threadId: String
    var kind: String                  // "file", "image", "markdown", "code", "screenshot"
    var title: String
    var sourcePath: String?           // original path the producer wrote it to
    var importedPath: String?         // path inside .raCommand/claude-threads/<id>/
    var url: String?

    init(
        id: String,
        threadId: String,
        kind: String,
        title: String,
        sourcePath: String? = nil,
        importedPath: String? = nil,
        url: String? = nil
    ) {
        self.id = id
        self.threadId = threadId
        self.kind = kind
        self.title = title
        self.sourcePath = sourcePath
        self.importedPath = importedPath
        self.url = url
    }
}
