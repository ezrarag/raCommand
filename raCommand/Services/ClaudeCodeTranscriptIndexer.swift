//
//  ClaudeCodeTranscriptIndexer.swift
//  raCommand
//
//  Indexes Claude Code JSONL transcripts under ~/.claude/projects/.
//
//  This service is METADATA-ONLY by default. It walks JSONL files line by
//  line, decodes each line as generic JSON (tolerating unknown fields),
//  and produces an `AIThreadRecord` per session without ever uploading
//  raw transcript content.
//
//  Full message text is only loaded by an explicit call to
//  `loadMessages(for:)`. Artifact import is a separate explicit action.
//
//  Reference: https://code.claude.com/docs/en/sessions
//

import Foundation

enum ClaudeCodeIndexerError: LocalizedError {
    case projectsRootMissing(String)

    var errorDescription: String? {
        switch self {
        case .projectsRootMissing(let path):
            return "Claude Code projects root not found at \(path). Open Claude Code at least once."
        }
    }
}

struct ClaudeCodeIndexer {

    /// Default location: ~/.claude/projects
    static var defaultProjectsRoot: String {
        NSHomeDirectory() + "/.claude/projects"
    }

    // MARK: - Public API

    /// Index every session under `projectsRoot`. Returns one record per JSONL.
    /// Subagent transcripts (under `subagents/`) are skipped at this layer.
    static func indexAllSessions(projectsRoot: String = defaultProjectsRoot) throws -> [AIThreadRecord] {
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: projectsRoot, isDirectory: &isDir), isDir.boolValue else {
            throw ClaudeCodeIndexerError.projectsRootMissing(projectsRoot)
        }

        let rootURL = URL(fileURLWithPath: projectsRoot, isDirectory: true)
        guard let enumerator = FileManager.default.enumerator(
            at: rootURL,
            includingPropertiesForKeys: [.isRegularFileKey, .contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }

        var records: [AIThreadRecord] = []
        for case let url as URL in enumerator {
            guard url.pathExtension == "jsonl" else { continue }
            // Skip subagent transcripts at first pass.
            if url.path.contains("/subagents/") { continue }
            // Best-effort per-file; never let one bad file kill the whole index.
            if let record = try? indexSession(at: url.path) {
                records.append(record)
            }
        }
        return records.sorted { ($0.lastActivityAt ?? .distantPast) > ($1.lastActivityAt ?? .distantPast) }
    }

    /// Index a single JSONL file.  METADATA ONLY.
    static func indexSession(at jsonlPath: String) throws -> AIThreadRecord {
        let url = URL(fileURLWithPath: jsonlPath)
        let metadata = try parseSessionMetadata(at: url)

        let sessionId = metadata.sessionId ?? url.deletingPathExtension().lastPathComponent
        let workspace = metadata.cwd ?? Self.decodeWorkspacePath(from: url)
        let title = metadata.summary
            ?? metadata.firstUserPrompt
            ?? sessionId

        return AIThreadRecord(
            id: "claudeCode:\(sessionId)",
            source: .claudeCode,
            externalId: sessionId,
            title: Self.shorten(title, max: 140),
            summary: metadata.summary ?? Self.shorten(metadata.firstUserPrompt ?? "", max: 320),
            sourceURL: nil,
            localTranscriptPath: jsonlPath,
            workspacePath: workspace,
            repoURL: nil,
            clientId: nil,
            projectId: nil,
            createdAt: metadata.firstTimestamp,
            lastActivityAt: metadata.lastTimestamp ?? Self.fileModified(at: url),
            messageCount: metadata.messageCount,
            artifactCount: 0,
            capabilities: .claudeCodeDefault,
            confidence: 1.0,
            model: metadata.model,
            gitBranch: metadata.gitBranch
        )
    }

    /// Load ALL message records for a session. This reads the full transcript;
    /// only call this from an explicit user action.
    static func loadMessages(for record: AIThreadRecord) throws -> [AIThreadMessageRecord] {
        guard let path = record.localTranscriptPath else { return [] }
        let url = URL(fileURLWithPath: path)
        let content = try String(contentsOf: url, encoding: .utf8)

        var messages: [AIThreadMessageRecord] = []
        var offset = 0
        for line in content.split(separator: "\n", omittingEmptySubsequences: true) {
            offset += 1
            guard let data = String(line).data(using: .utf8),
                  let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
            else { continue }

            guard let type = obj["type"] as? String,
                  type == "user" || type == "assistant" || type == "system"
            else { continue }

            let createdAt = (obj["timestamp"] as? String).flatMap(parseISO8601)
            let messageDict = obj["message"] as? [String: Any]
            let role = (messageDict?["role"] as? String) ?? type
            let text = Self.extractText(from: messageDict?["content"] ?? obj["content"] as Any)
            let hasToolUse = Self.detectToolUse(in: messageDict?["content"] ?? obj["content"] as Any)
            let id = (obj["uuid"] as? String) ?? (obj["promptId"] as? String) ?? UUID().uuidString

            messages.append(AIThreadMessageRecord(
                id: id,
                threadId: record.id,
                role: role,
                text: Self.shorten(text, max: 16_000),  // protective ceiling per message
                createdAt: createdAt,
                sourceOffset: offset,
                hasToolUse: hasToolUse,
                redactionState: "raw"
            ))
        }
        return messages
    }

    // MARK: - Metadata extraction

    /// What we pull out of a JSONL during the metadata pass.
    fileprivate struct SessionMetadata {
        var sessionId: String?
        var cwd: String?
        var model: String?
        var gitBranch: String?
        var firstUserPrompt: String?
        var summary: String?            // explicit "summary" lines if present
        var firstTimestamp: Date?
        var lastTimestamp: Date?
        var messageCount: Int = 0
    }

    /// Walk a JSONL once; decode each line independently. Tolerate unknown fields.
    fileprivate static func parseSessionMetadata(at url: URL) throws -> SessionMetadata {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }

        var meta = SessionMetadata()

        // Stream by reading the whole file in one shot — Claude Code transcripts
        // are routinely <10 MB; if they grow we can switch to chunked reading.
        let data = handle.readDataToEndOfFile()
        guard let text = String(data: data, encoding: .utf8) else { return meta }

        for substring in text.split(separator: "\n", omittingEmptySubsequences: true) {
            let line = String(substring)
            guard let lineData = line.data(using: .utf8),
                  let obj = (try? JSONSerialization.jsonObject(with: lineData)) as? [String: Any]
            else { continue }

            // Capture the first sessionId we see (queue-operation lines have it early).
            if meta.sessionId == nil, let sid = obj["sessionId"] as? String {
                meta.sessionId = sid
            }
            if meta.cwd == nil, let cwd = obj["cwd"] as? String {
                meta.cwd = cwd
            }
            if meta.gitBranch == nil, let branch = obj["gitBranch"] as? String {
                meta.gitBranch = branch
            }

            let type = obj["type"] as? String

            // Explicit summary records.
            if type == "summary", meta.summary == nil {
                meta.summary = obj["summary"] as? String
            }

            // Capture user/assistant message stats and timestamps.
            if type == "user" || type == "assistant" {
                meta.messageCount += 1
                if let ts = (obj["timestamp"] as? String).flatMap(parseISO8601) {
                    if meta.firstTimestamp == nil { meta.firstTimestamp = ts }
                    meta.lastTimestamp = ts
                }
                if meta.model == nil, let messageDict = obj["message"] as? [String: Any] {
                    meta.model = messageDict["model"] as? String
                }
                if meta.firstUserPrompt == nil, type == "user" {
                    let messageDict = obj["message"] as? [String: Any]
                    let text = Self.extractText(from: messageDict?["content"] ?? obj["content"] as Any)
                    if !text.isEmpty {
                        meta.firstUserPrompt = text
                    }
                }
            }

            // queue-operation lines also carry timestamps (treat as fallback activity).
            if type == "queue-operation",
               let ts = (obj["timestamp"] as? String).flatMap(parseISO8601) {
                if meta.firstTimestamp == nil { meta.firstTimestamp = ts }
                meta.lastTimestamp = ts
            }
        }

        return meta
    }

    // MARK: - Helpers

    /// Best-effort decoding of the workspace path from a Claude Code project
    /// directory name. Claude Code encodes paths by replacing `/` and spaces
    /// with `-`, which is ambiguous; we only use this as a fallback when the
    /// JSONL itself has no `cwd` field.
    static func decodeWorkspacePath(from url: URL) -> String? {
        // The JSONL lives at .../<encoded-project>/<sessionId>.jsonl
        let dirName = url.deletingLastPathComponent().lastPathComponent
        guard !dirName.isEmpty else { return nil }
        // Naïve: replace dashes with slashes. Caller should prefer JSONL `cwd`.
        let candidate = "/" + dirName
            .trimmingCharacters(in: CharacterSet(charactersIn: "-"))
            .replacingOccurrences(of: "--", with: "/.")
            .replacingOccurrences(of: "-", with: "/")
        return candidate
    }

    /// Recursively extract printable text from a Claude message `content` value
    /// (which may be a string, an array of blocks, or a nested dict).
    fileprivate static func extractText(from content: Any) -> String {
        if let s = content as? String { return s }
        if let arr = content as? [Any] {
            return arr.compactMap { item -> String? in
                if let s = item as? String { return s }
                if let dict = item as? [String: Any] {
                    if let t = dict["text"] as? String { return t }
                    if let t = dict["content"] as? String { return t }
                    if dict["type"] as? String == "tool_use" { return nil }   // skip tool calls
                    if dict["type"] as? String == "tool_result", let r = dict["content"] {
                        return Self.extractText(from: r)
                    }
                }
                return nil
            }.joined(separator: "\n")
        }
        if let dict = content as? [String: Any] {
            if let t = dict["text"] as? String { return t }
            if let t = dict["content"] { return Self.extractText(from: t) }
        }
        return ""
    }

    fileprivate static func detectToolUse(in content: Any) -> Bool {
        if let arr = content as? [Any] {
            for item in arr {
                if let dict = item as? [String: Any],
                   let type = dict["type"] as? String,
                   type == "tool_use" || type == "tool_result" {
                    return true
                }
            }
        }
        return false
    }

    fileprivate static func parseISO8601(_ value: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = formatter.date(from: value) { return d }
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: value)
    }

    fileprivate static func fileModified(at url: URL) -> Date? {
        (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
    }

    fileprivate static func shorten(_ s: String, max: Int) -> String {
        guard s.count > max else { return s }
        return String(s.prefix(max)) + "…"
    }
}
