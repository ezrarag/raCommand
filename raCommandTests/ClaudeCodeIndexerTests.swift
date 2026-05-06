//
//  ClaudeCodeIndexerTests.swift
//  raCommandTests
//
//  Synthetic-fixture tests for the Claude Code transcript indexer.
//  No reliance on the user's live ~/.claude/projects data.
//

import XCTest
@testable import raCommand

final class ClaudeCodeIndexerTests: XCTestCase {

    private var fixturesRoot: URL!

    override func setUpWithError() throws {
        fixturesRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("raCommand-claude-code-fixtures-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: fixturesRoot, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: fixturesRoot)
    }

    // MARK: - Helpers

    /// Write a JSONL file at <fixturesRoot>/<dirName>/<sessionId>.jsonl
    private func writeFixture(dirName: String, sessionId: String, lines: [[String: Any]]) throws -> URL {
        let dir = fixturesRoot.appendingPathComponent(dirName, isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let file = dir.appendingPathComponent("\(sessionId).jsonl")
        let body = lines
            .map { try! String(data: JSONSerialization.data(withJSONObject: $0), encoding: .utf8)! }
            .joined(separator: "\n")
        try body.write(to: file, atomically: true, encoding: .utf8)
        return file
    }

    // MARK: - Tests

    func testIndexSingleSession_extractsBasicMetadata() throws {
        let url = try writeFixture(
            dirName: "-Users-test-project",
            sessionId: "abc-123",
            lines: [
                ["type": "queue-operation", "operation": "enqueue",
                 "timestamp": "2026-01-01T10:00:00.000Z",
                 "sessionId": "abc-123", "content": "ignored"],
                ["type": "user", "timestamp": "2026-01-01T10:00:01.000Z",
                 "sessionId": "abc-123",
                 "cwd": "/tmp/work",
                 "gitBranch": "main",
                 "message": ["role": "user", "content": "hello there"]],
                ["type": "assistant", "timestamp": "2026-01-01T10:00:02.000Z",
                 "sessionId": "abc-123",
                 "message": ["role": "assistant", "model": "claude-sonnet-4",
                             "content": [["type": "text", "text": "hi back"]]]]
            ]
        )

        let record = try ClaudeCodeIndexer.indexSession(at: url.path)

        XCTAssertEqual(record.source, .claudeCode)
        XCTAssertEqual(record.externalId, "abc-123")
        XCTAssertEqual(record.workspacePath, "/tmp/work")
        XCTAssertEqual(record.gitBranch, "main")
        XCTAssertEqual(record.model, "claude-sonnet-4")
        XCTAssertEqual(record.messageCount, 2)
        XCTAssertTrue(record.title.contains("hello"))
        XCTAssertTrue(record.capabilities.contains(.canResumeOriginal))
    }

    func testIndexSession_tolerantOfUnknownFields() throws {
        let url = try writeFixture(
            dirName: "-Users-test-project",
            sessionId: "tolerant-1",
            lines: [
                ["type": "queue-operation", "sessionId": "tolerant-1",
                 "weird_unknown_field": "ignore me",
                 "timestamp": "2026-01-01T10:00:00.000Z"],
                ["type": "user", "sessionId": "tolerant-1",
                 "timestamp": "2026-01-01T10:00:01.000Z",
                 "message": ["role": "user", "content": "hi",
                             "future_field": ["nested": true]]]
            ]
        )
        // Should not throw; should extract sessionId successfully.
        let record = try ClaudeCodeIndexer.indexSession(at: url.path)
        XCTAssertEqual(record.externalId, "tolerant-1")
    }

    func testIndexSession_skipsToolUseInTranscriptText() throws {
        let url = try writeFixture(
            dirName: "-Users-test-project",
            sessionId: "tools-1",
            lines: [
                ["type": "user", "sessionId": "tools-1",
                 "timestamp": "2026-01-01T10:00:01.000Z",
                 "message": ["role": "user", "content": [
                     ["type": "text", "text": "please run a tool"],
                     ["type": "tool_use", "name": "Bash", "input": ["command": "ls"]]
                 ]]]
            ]
        )
        let record = try ClaudeCodeIndexer.indexSession(at: url.path)
        XCTAssertNotNil(record.summary)
        // Summary should include the user text but not the tool_use payload.
        XCTAssertTrue(record.summary.contains("please run a tool"))
        XCTAssertFalse(record.summary.contains("\"command\""))
    }

    func testLoadMessages_marksToolUseFlag() throws {
        let url = try writeFixture(
            dirName: "-Users-test-project",
            sessionId: "tools-2",
            lines: [
                ["type": "assistant", "sessionId": "tools-2",
                 "timestamp": "2026-01-01T10:00:01.000Z",
                 "message": ["role": "assistant", "content": [
                     ["type": "text", "text": "Running command"],
                     ["type": "tool_use", "name": "Bash"]
                 ]]]
            ]
        )
        let record = try ClaudeCodeIndexer.indexSession(at: url.path)
        let messages = try ClaudeCodeIndexer.loadMessages(for: record)
        XCTAssertEqual(messages.count, 1)
        XCTAssertTrue(messages[0].hasToolUse)
    }

    func testIndexAll_skipsSubagentTranscripts() throws {
        // Main session
        _ = try writeFixture(
            dirName: "-Users-test-project",
            sessionId: "main-1",
            lines: [
                ["type": "user", "sessionId": "main-1",
                 "timestamp": "2026-01-01T10:00:00.000Z",
                 "message": ["role": "user", "content": "main"]]
            ]
        )
        // Subagent session — should be skipped
        _ = try writeFixture(
            dirName: "-Users-test-project/subagents",
            sessionId: "subagent-1",
            lines: [
                ["type": "user", "sessionId": "subagent-1",
                 "timestamp": "2026-01-01T10:00:00.000Z",
                 "message": ["role": "user", "content": "sub"]]
            ]
        )

        let records = try ClaudeCodeIndexer.indexAllSessions(projectsRoot: fixturesRoot.path)
        let ids = records.compactMap(\.externalId)
        XCTAssertTrue(ids.contains("main-1"))
        XCTAssertFalse(ids.contains("subagent-1"))
    }

    func testIndexAll_missingRoot_throws() {
        let bogus = fixturesRoot.appendingPathComponent("does-not-exist").path
        XCTAssertThrowsError(try ClaudeCodeIndexer.indexAllSessions(projectsRoot: bogus))
    }

    // MARK: - Project resolution

    @MainActor
    func testRegistryResolution_workspacePathExactMatch() async {
        let project = Project(
            name: "raCommand",
            clientName: "Internal",
            repoURL: "git@github.com:foo/raCommand.git",
            localPath: "/tmp/work"
        )
        let registry = AIThreadRegistry()
        registry.projects = [project]

        let record = AIThreadRecord(
            id: "claudeCode:abc",
            source: .claudeCode,
            externalId: "abc",
            title: "Random title that doesn't mention the project",
            workspacePath: "/tmp/work/subdir",
            messageCount: 5,
            capabilities: .claudeCodeDefault
        )

        let resolved = registry.resolveProjectMapping(for: record)
        XCTAssertEqual(resolved.projectId, project.clientFeedbackProjectId)
        XCTAssertEqual(resolved.confidence, 1.0)
    }

    @MainActor
    func testRegistryResolution_repoNameFallback() async {
        let project = Project(
            name: "Other",
            clientName: "",
            repoURL: "https://github.com/foo/myrepo.git",
            localPath: "/some/other/path"
        )
        let registry = AIThreadRegistry()
        registry.projects = [project]

        let record = AIThreadRecord(
            id: "claudeCode:abc",
            source: .claudeCode,
            externalId: "abc",
            title: "x",
            workspacePath: "/Users/me/code/myrepo",
            messageCount: 0,
            capabilities: .claudeCodeDefault
        )

        let resolved = registry.resolveProjectMapping(for: record)
        XCTAssertEqual(resolved.projectId, project.clientFeedbackProjectId)
        XCTAssertEqual(resolved.confidence, 0.9)
    }

    @MainActor
    func testRegistryResolution_titleNameFallbackMarkedInferred() async {
        let project = Project(
            name: "Atlas",
            clientName: "",
            repoURL: "",
            localPath: ""
        )
        let registry = AIThreadRegistry()
        registry.projects = [project]

        let record = AIThreadRecord(
            id: "claudeCode:abc",
            source: .claudeCode,
            externalId: "abc",
            title: "Refactor Atlas auth flow",
            workspacePath: nil,
            messageCount: 0,
            capabilities: .claudeCodeDefault
        )

        let resolved = registry.resolveProjectMapping(for: record)
        XCTAssertEqual(resolved.projectId, project.clientFeedbackProjectId)
        XCTAssertLessThan(resolved.confidence, 1.0)
    }

    @MainActor
    func testRegistryResolution_noMatch_lowConfidence() async {
        let project = Project(name: "Other", clientName: "Acme", repoURL: "", localPath: "/somewhere")
        let registry = AIThreadRegistry()
        registry.projects = [project]

        let record = AIThreadRecord(
            id: "claudeCode:abc", source: .claudeCode, externalId: "abc",
            title: "Random unrelated thread",
            workspacePath: "/totally/different/path",
            capabilities: .claudeCodeDefault,
            confidence: 1.0
        )

        let resolved = registry.resolveProjectMapping(for: record)
        XCTAssertNil(resolved.projectId)
        XCTAssertLessThan(resolved.confidence, 1.0)
    }
}
