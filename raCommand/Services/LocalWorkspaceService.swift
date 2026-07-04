//
//  LocalWorkspaceService.swift
//  raCommand
//
//  Handles local workspace preparation and Codex Desktop launch.
//

import Foundation

enum LocalWorkspaceError: LocalizedError {
    case missingRepoURL
    case invalidRepoURL
    case workspaceMissing
    case unsupportedPlatform
    case gitCloneFailed(String)
    case codexUnavailable
    case codexStateUnavailable
    case codexThreadArchiveFailed(String)
    case failedToLaunchCodex(String)

    var errorDescription: String? {
        switch self {
        case .missingRepoURL:
            return "Add a GitHub repo URL before starting a thread."
        case .invalidRepoURL:
            return "The repo URL could not be converted into a local workspace path."
        case .workspaceMissing:
            return "The local workspace could not be found."
        case .unsupportedPlatform:
            return "This action is only supported on macOS."
        case .gitCloneFailed(let output):
            return output.isEmpty ? "Git clone failed." : output
        case .codexUnavailable:
            return "Codex Desktop is not installed or its CLI is unavailable."
        case .codexStateUnavailable:
            return "Codex local thread state could not be found."
        case .codexThreadArchiveFailed(let details):
            return details.isEmpty ? "Could not archive matching Codex threads." : details
        case .failedToLaunchCodex(let details):
            return details.isEmpty ? "Could not launch Codex Desktop." : details
        }
    }
}

struct CodexThreadArchiveResult {
    let archivedCount: Int
    let databasePath: String

    var message: String {
        if archivedCount == 0 {
            return "No matching Codex threads were active for this folder."
        }
        return "Archived \(archivedCount) matching Codex thread\(archivedCount == 1 ? "" : "s")."
    }
}

enum LocalWorkspaceService {
    static let defaultWorkspaceRoot = "/Users/ehauga/Desktop/local dev"

    #if os(macOS)
    private static let codexCLIPath = "/Applications/Codex.app/Contents/Resources/codex"
    private static let codexHomePath = NSHomeDirectory() + "/.codex"
    #endif

    static func workspaceExists(at path: String) -> Bool {
        guard !path.isEmpty else { return false }
        var isDirectory: ObjCBool = false
        return FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory) && isDirectory.boolValue
    }

    static func normalizedWorkspacePath(_ path: String) -> String {
        let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }
        return URL(fileURLWithPath: trimmed, isDirectory: true)
            .standardizedFileURL
            .resolvingSymlinksInPath()
            .path
    }

    static func directorySize(at path: String) -> Int64? {
        let normalizedPath = normalizedWorkspacePath(path)
        guard workspaceExists(at: normalizedPath) else { return nil }

        let resourceKeys: Set<URLResourceKey> = [
            .isRegularFileKey,
            .fileSizeKey,
            .fileAllocatedSizeKey,
            .totalFileAllocatedSizeKey
        ]

        guard let enumerator = FileManager.default.enumerator(
            at: URL(fileURLWithPath: normalizedPath, isDirectory: true),
            includingPropertiesForKeys: Array(resourceKeys),
            options: [],
            errorHandler: { _, _ in true }
        ) else {
            return nil
        }

        var totalBytes: Int64 = 0

        for case let fileURL as URL in enumerator {
            guard let values = try? fileURL.resourceValues(forKeys: resourceKeys),
                  values.isRegularFile == true else {
                continue
            }

            if let allocatedSize = values.totalFileAllocatedSize ?? values.fileAllocatedSize ?? values.fileSize {
                totalBytes += Int64(allocatedSize)
            }
        }

        return totalBytes
    }

    static func suggestedLocalPath(for repoURL: String, rootPath: String = defaultWorkspaceRoot) -> String? {
        guard let repoName = repoName(from: repoURL) else { return nil }
        return URL(fileURLWithPath: rootPath, isDirectory: true)
            .appendingPathComponent(repoName, isDirectory: true)
            .path
    }

    static func repoName(from repoURL: String) -> String? {
        let trimmed = repoURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        var tail = trimmed
        if let lastSlash = tail.lastIndex(of: "/") {
            tail = String(tail[tail.index(after: lastSlash)...])
        }
        if let query = tail.firstIndex(of: "?") {
            tail = String(tail[..<query])
        }
        if tail.hasSuffix(".git") {
            tail.removeLast(4)
        }

        let sanitized = tail.trimmingCharacters(in: .whitespacesAndNewlines)
        return sanitized.isEmpty ? nil : sanitized
    }

    static func ensureLocalClone(
        repoURL: String,
        preferredPath: String? = nil,
        rootPath: String = defaultWorkspaceRoot
    ) throws -> String {
        let trimmedURL = repoURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedURL.isEmpty else { throw LocalWorkspaceError.missingRepoURL }

        let destination = preferredPath?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
            ? preferredPath!.trimmingCharacters(in: .whitespacesAndNewlines)
            : suggestedLocalPath(for: trimmedURL, rootPath: rootPath)

        guard let destination, !destination.isEmpty else {
            throw LocalWorkspaceError.invalidRepoURL
        }

        if workspaceExists(at: destination) {
            return destination
        }

        #if os(macOS)
        try FileManager.default.createDirectory(
            atPath: rootPath,
            withIntermediateDirectories: true,
            attributes: nil
        )

        let result = try runProcess(
            executablePath: "/usr/bin/git",
            arguments: ["clone", trimmedURL, destination]
        )

        guard result.status == 0 else {
            throw LocalWorkspaceError.gitCloneFailed(result.output)
        }

        return destination
        #else
        throw LocalWorkspaceError.unsupportedPlatform
        #endif
    }

    static func openInCodex(path: String) throws {
        let trimmedPath = path.trimmingCharacters(in: .whitespacesAndNewlines)
        guard workspaceExists(at: trimmedPath) else {
            throw LocalWorkspaceError.workspaceMissing
        }

        #if os(macOS)
        guard FileManager.default.isExecutableFile(atPath: codexCLIPath) else {
            throw LocalWorkspaceError.codexUnavailable
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: codexCLIPath)
        process.arguments = ["app", trimmedPath]

        do {
            try process.run()
        } catch {
            throw LocalWorkspaceError.failedToLaunchCodex(error.localizedDescription)
        }
        #else
        throw LocalWorkspaceError.unsupportedPlatform
        #endif
    }

    static func activeCodexWorkspacePaths(rootPathPrefix: String? = nil) -> Set<String> {
        #if os(macOS)
        guard let databasePath = latestCodexStateDatabasePath() else {
            return []
        }

        let prefix = rootPathPrefix?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "'", with: "''")

        let whereClause: String
        if let prefix, !prefix.isEmpty {
            whereClause = "WHERE archived = 0 AND cwd LIKE '\(prefix)%'"
        } else {
            whereClause = "WHERE archived = 0"
        }

        let query = "SELECT DISTINCT cwd FROM threads \(whereClause) ORDER BY updated_at DESC;"

        guard let result = try? runProcess(
            executablePath: "/usr/bin/sqlite3",
            arguments: ["-noheader", databasePath, query]
        ), result.status == 0 else {
            return []
        }

        return Set(
            result.output
                .split(separator: "\n")
                .map(String.init)
                .map(normalizedWorkspacePath)
                .filter { !$0.isEmpty }
        )
        #else
        return []
        #endif
    }

    static func archiveCodexThreads(forWorkspacePath path: String) throws -> CodexThreadArchiveResult {
        #if os(macOS)
        guard let databasePath = latestCodexStateDatabasePath() else {
            throw LocalWorkspaceError.codexStateUnavailable
        }

        let normalizedPath = normalizedWorkspacePath(path)
        guard !normalizedPath.isEmpty else {
            return CodexThreadArchiveResult(archivedCount: 0, databasePath: databasePath)
        }

        let escapedPath = sqliteEscaped(normalizedPath)
        let countQuery = "SELECT COUNT(*) FROM threads WHERE archived = 0 AND cwd = '\(escapedPath)';"
        let countResult = try runProcess(
            executablePath: "/usr/bin/sqlite3",
            arguments: ["-noheader", databasePath, countQuery]
        )
        guard countResult.status == 0 else {
            throw LocalWorkspaceError.codexThreadArchiveFailed(countResult.output)
        }

        let count = Int(countResult.output.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0
        guard count > 0 else {
            return CodexThreadArchiveResult(archivedCount: 0, databasePath: databasePath)
        }

        let now = Int(Date().timeIntervalSince1970)
        let updateQuery = "UPDATE threads SET archived = 1, archived_at = \(now) WHERE archived = 0 AND cwd = '\(escapedPath)';"
        let updateResult = try runProcess(
            executablePath: "/usr/bin/sqlite3",
            arguments: [databasePath, updateQuery]
        )
        guard updateResult.status == 0 else {
            throw LocalWorkspaceError.codexThreadArchiveFailed(updateResult.output)
        }

        return CodexThreadArchiveResult(archivedCount: count, databasePath: databasePath)
        #else
        throw LocalWorkspaceError.unsupportedPlatform
        #endif
    }

    #if os(macOS)
    private static func latestCodexStateDatabasePath() -> String? {
        let codexHomeURL = URL(fileURLWithPath: codexHomePath, isDirectory: true)
        guard let contents = try? FileManager.default.contentsOfDirectory(
            at: codexHomeURL,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else {
            return nil
        }

        let candidates = contents.filter { url in
            let name = url.lastPathComponent
            return name.hasPrefix("state_") && name.hasSuffix(".sqlite")
        }

        return candidates
            .sorted {
                let lhs = (try? $0.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                let rhs = (try? $1.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                return lhs > rhs
            }
            .first?
            .path
    }

    private static func sqliteEscaped(_ value: String) -> String {
        value.replacingOccurrences(of: "'", with: "''")
    }

    private static func runProcess(
        executablePath: String,
        arguments: [String]
    ) throws -> (status: Int32, output: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executablePath)
        process.arguments = arguments

        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = errorPipe

        try process.run()
        process.waitUntilExit()

        let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
        let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
        let output = String(data: outputData, encoding: .utf8) ?? ""
        let errorOutput = String(data: errorData, encoding: .utf8) ?? ""
        let combined = [output, errorOutput]
            .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .joined(separator: "\n")

        return (process.terminationStatus, combined)
    }
    #endif
}
