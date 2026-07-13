//
//  LocalGitInspector.swift
//  raCommand
//
//  Read-only inspection of a local git workspace for Pulse queries.
//

import Foundation

struct LocalGitCommitSummary: Hashable {
    let shortSHA: String
    let message: String
    let relativeDate: String
}

enum LocalGitChangedFileKind: Hashable {
    case added
    case modified
    case deleted
    case renamed
    case untracked
}

struct LocalGitChangedFile: Hashable {
    let path: String
    let kind: LocalGitChangedFileKind
}

struct LocalGitSnapshot {
    let path: String
    let branch: String
    let originURL: String?
    let aheadCount: Int?
    let behindCount: Int?
    let changedFileCount: Int
    let stagedCount: Int
    let unstagedCount: Int
    let untrackedCount: Int
    let changedFiles: [LocalGitChangedFile]
    let recentCommits: [LocalGitCommitSummary]

    var isDirty: Bool { changedFileCount > 0 }
}

enum LocalGitInspectorError: LocalizedError {
    case missingWorkspace
    case notGitRepository
    case unsupportedPlatform
    case commandFailed(String)

    var errorDescription: String? {
        switch self {
        case .missingWorkspace:
            return "The local workspace could not be found."
        case .notGitRepository:
            return "The local workspace exists, but it is not a git repository."
        case .unsupportedPlatform:
            return "Local git inspection is only available on macOS."
        case .commandFailed(let output):
            return output.isEmpty ? "Git inspection failed." : output
        }
    }
}

enum LocalGitInspector {
    static func inspect(at path: String) throws -> LocalGitSnapshot {
        let trimmedPath = path.trimmingCharacters(in: .whitespacesAndNewlines)
        guard LocalWorkspaceService.workspaceExists(at: trimmedPath) else {
            throw LocalGitInspectorError.missingWorkspace
        }

        #if os(macOS)
        // A single `git status --porcelain=v2 --branch` covers what used to be
        // three separate calls: the repo-existence check (non-zero exit with
        // "not a git repository" on failure), the current branch name
        // (`# branch.head`), and ahead/behind vs. upstream (`# branch.ab`) —
        // all read from the same process's output instead of one spawn each.
        let branchStatusResult = try runGit(["status", "--porcelain=v2", "--branch"], at: trimmedPath)
        guard branchStatusResult.status == 0 else {
            if branchStatusResult.output.lowercased().contains("not a git repository") {
                throw LocalGitInspectorError.notGitRepository
            }
            throw LocalGitInspectorError.commandFailed(branchStatusResult.output)
        }

        let branchHeaders = parseBranchHeaders(output: branchStatusResult.output)

        let branchName: String = {
            if let head = branchHeaders.head, head != "(detached)" {
                return head
            }

            if let head = try? runGit(["rev-parse", "--short", "HEAD"], at: trimmedPath),
               head.status == 0 {
                let trimmed = head.output.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty { return "detached@\(trimmed)" }
            }

            return "detached HEAD"
        }()

        // File-level status (staged/unstaged/untracked counts, changed-file
        // list) keeps using the original --porcelain (v1) parser unchanged —
        // that logic feeds commit-message generation and push/removal safety
        // checks, so it's not worth touching just to shave one more spawn.
        let statusOutput = try runGit(["status", "--porcelain"], at: trimmedPath)
        let statusCounts = parseStatus(output: statusOutput.output)

        let aheadBehind: (behind: Int?, ahead: Int?) = (branchHeaders.behind, branchHeaders.ahead)

        let recentCommits: [LocalGitCommitSummary] = {
            guard let result = try? runGit(
                ["log", "--pretty=format:%h%x1f%s%x1f%cr", "-n", "3"],
                at: trimmedPath
            ), result.status == 0 else {
                return []
            }
            return parseRecentCommits(output: result.output)
        }()

        let originURL: String? = {
            guard let result = try? runGit(["remote", "get-url", "origin"], at: trimmedPath),
                  result.status == 0 else {
                return nil
            }
            let trimmed = result.output.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        }()

        return LocalGitSnapshot(
            path: trimmedPath,
            branch: branchName,
            originURL: originURL,
            aheadCount: aheadBehind.ahead,
            behindCount: aheadBehind.behind,
            changedFileCount: statusCounts.changedFileCount,
            stagedCount: statusCounts.stagedCount,
            unstagedCount: statusCounts.unstagedCount,
            untrackedCount: statusCounts.untrackedCount,
            changedFiles: statusCounts.changedFiles,
            recentCommits: recentCommits
        )
        #else
        throw LocalGitInspectorError.unsupportedPlatform
        #endif
    }

    #if os(macOS)
    private static func runGit(_ arguments: [String], at path: String) throws -> (status: Int32, output: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = ["-C", path] + arguments

        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr

        do {
            try process.run()
        } catch {
            throw LocalGitInspectorError.commandFailed(error.localizedDescription)
        }

        process.waitUntilExit()

        let outputData = stdout.fileHandleForReading.readDataToEndOfFile()
        let errorData = stderr.fileHandleForReading.readDataToEndOfFile()
        let output = String(data: outputData, encoding: .utf8) ?? ""
        let errorOutput = String(data: errorData, encoding: .utf8) ?? ""
        let combined = [output, errorOutput]
            .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .joined(separator: "\n")

        return (process.terminationStatus, combined)
    }

    private static func parseStatus(output: String) -> (changedFileCount: Int, stagedCount: Int, unstagedCount: Int, untrackedCount: Int, changedFiles: [LocalGitChangedFile]) {
        let lines = output
            .split(separator: "\n", omittingEmptySubsequences: true)
            .map(String.init)

        var staged = 0
        var unstaged = 0
        var untracked = 0
        var changedFiles: [LocalGitChangedFile] = []

        for line in lines {
            if line.hasPrefix("??") {
                untracked += 1
                if let file = changedFile(from: line, kind: .untracked) {
                    changedFiles.append(file)
                }
                continue
            }

            let characters = Array(line)
            guard characters.count >= 2 else { continue }

            if characters[0] != " " {
                staged += 1
            }

            if characters[1] != " " {
                unstaged += 1
            }

            if let file = changedFile(from: line, kind: changedFileKind(indexStatus: characters[0], workTreeStatus: characters[1])) {
                changedFiles.append(file)
            }
        }

        return (lines.count, staged, unstaged, untracked, Array(changedFiles.prefix(12)))
    }

    private static func changedFileKind(indexStatus: Character, workTreeStatus: Character) -> LocalGitChangedFileKind {
        if indexStatus == "R" || workTreeStatus == "R" {
            return .renamed
        }
        if indexStatus == "D" || workTreeStatus == "D" {
            return .deleted
        }
        if indexStatus == "A" || workTreeStatus == "A" {
            return .added
        }
        return .modified
    }

    private static func changedFile(from statusLine: String, kind: LocalGitChangedFileKind) -> LocalGitChangedFile? {
        guard statusLine.count > 3 else { return nil }
        var path = String(statusLine.dropFirst(3))
        if kind == .renamed, let renamedPath = path.components(separatedBy: " -> ").last {
            path = renamedPath
        }
        path = path.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !path.isEmpty else { return nil }
        return LocalGitChangedFile(path: path, kind: kind)
    }

    /// Parses the `# branch.*` header lines from `git status --porcelain=v2 --branch`.
    /// `branch.ab` (ahead/behind) is only present when an upstream is configured,
    /// so ahead/behind correctly stay nil with no upstream — same semantics as
    /// the old `rev-list --left-right --count @{upstream}...HEAD` call.
    private static func parseBranchHeaders(output: String) -> (head: String?, ahead: Int?, behind: Int?) {
        var head: String?
        var ahead: Int?
        var behind: Int?

        for line in output.split(separator: "\n", omittingEmptySubsequences: true) {
            guard line.hasPrefix("# branch.") else { continue }
            let content = line.dropFirst("# branch.".count)

            if content.hasPrefix("head ") {
                head = String(content.dropFirst("head ".count))
            } else if content.hasPrefix("ab ") {
                for part in content.dropFirst("ab ".count).split(separator: " ") {
                    if part.hasPrefix("+") {
                        ahead = Int(part.dropFirst())
                    } else if part.hasPrefix("-") {
                        behind = Int(part.dropFirst())
                    }
                }
            }
        }

        return (head, ahead, behind)
    }

    private static func parseRecentCommits(output: String) -> [LocalGitCommitSummary] {
        output
            .split(separator: "\n", omittingEmptySubsequences: true)
            .map(String.init)
            .compactMap { line in
                let parts = line.components(separatedBy: "\u{1F}")
                guard parts.count >= 3 else { return nil }
                return LocalGitCommitSummary(
                    shortSHA: parts[0],
                    message: parts[1],
                    relativeDate: parts[2]
                )
            }
    }
    #endif
}

// MARK: - Local git mutations

struct LocalGitCommandResult {
    let output: String
}

enum LocalGitCommandError: LocalizedError {
    case missingWorkspace
    case notGitRepository
    case unsupportedPlatform
    case missingOrigin
    case missingUpstream
    case behindRemote(Int)
    case divergentBranch(ahead: Int, behind: Int)
    case dirtyWithoutCommitMessage
    case unresolvedDirtyState
    case unsafeToRemove(String)
    case commandFailed(String)
    case trashFailed(String)

    var errorDescription: String? {
        switch self {
        case .missingWorkspace:
            return "The local workspace could not be found."
        case .notGitRepository:
            return "The local workspace exists, but it is not a git repository."
        case .unsupportedPlatform:
            return "Local git actions are only available on macOS."
        case .missingOrigin:
            return "This repository has no origin remote."
        case .missingUpstream:
            return "This branch has no upstream. Set an upstream before pushing from raCommand."
        case .behindRemote(let count):
            return "This branch is behind its upstream by \(count) commit\(count == 1 ? "" : "s"). Pull or resolve outside raCommand before pushing."
        case .divergentBranch(let ahead, let behind):
            return "This branch has diverged from upstream (\(ahead) ahead, \(behind) behind). Resolve the branch outside raCommand before removing the local copy."
        case .dirtyWithoutCommitMessage:
            return "Enter a commit message before committing local changes."
        case .unresolvedDirtyState:
            return "The workspace still has local changes after preparation. Resolve them before removing this local copy."
        case .unsafeToRemove(let reason):
            return reason
        case .commandFailed(let output):
            return output.isEmpty ? "The git command failed." : output
        case .trashFailed(let output):
            return output.isEmpty ? "Could not move the local workspace to Trash." : output
        }
    }
}

enum LocalGitCommandService {
    static func status(at path: String) throws -> LocalGitSnapshot {
        try LocalGitInspector.inspect(at: path)
    }

    static func suggestedCommitMessage(
        for snapshot: LocalGitSnapshot?,
        repoName: String,
        isRemovalFlow: Bool = false
    ) -> String {
        let fallback = "Update \(repoName)"
        guard let snapshot, snapshot.isDirty, !snapshot.changedFiles.isEmpty else {
            return isRemovalFlow ? "\(fallback) before removal" : fallback
        }

        let baseMessage: String = {
            if snapshot.changedFiles.count == 1, let change = snapshot.changedFiles.first {
                return "\(actionVerb(for: change.kind)) \(displayName(for: change.path))"
            }

            if isGitSyncChange(snapshot.changedFiles) {
                return "Update git sync workflow"
            }

            let topLevelDirectories = Set(snapshot.changedFiles.compactMap(topLevelDirectory))
            if topLevelDirectories.count == 1, let directory = topLevelDirectories.first {
                return groupedMessage(for: directory)
            }

            return fallback
        }()

        if isRemovalFlow, baseMessage == fallback {
            return "\(baseMessage) before removal"
        }
        return baseMessage
    }

    static func commitAndPush(at path: String, commitMessage: String?) throws -> LocalGitCommandResult {
        #if os(macOS)
        var snapshot = try validatedSnapshot(at: path)
        try validatePushPreconditions(snapshot)

        var output: [String] = []
        if snapshot.isDirty {
            let message = commitMessage?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard !message.isEmpty else {
                throw LocalGitCommandError.dirtyWithoutCommitMessage
            }

            let addResult = try runGit(["add", "-A"], at: snapshot.path)
            guard addResult.status == 0 else {
                throw LocalGitCommandError.commandFailed(addResult.output)
            }
            if !addResult.output.isEmpty { output.append(addResult.output) }

            let commitResult = try runGit(["commit", "-m", message], at: snapshot.path)
            guard commitResult.status == 0 else {
                throw LocalGitCommandError.commandFailed(commitResult.output)
            }
            if !commitResult.output.isEmpty { output.append(commitResult.output) }

            snapshot = try validatedSnapshot(at: path)
            try validatePushPreconditions(snapshot)
        }

        let pushResult = try runGit(["push"], at: snapshot.path)
        guard pushResult.status == 0 else {
            throw LocalGitCommandError.commandFailed(pushResult.output)
        }
        output.append(pushResult.output.isEmpty ? "Already up to date." : pushResult.output)

        return LocalGitCommandResult(output: output.joined(separator: "\n\n"))
        #else
        throw LocalGitCommandError.unsupportedPlatform
        #endif
    }

    static func prepareForRemoval(at path: String, commitMessage: String?) throws -> LocalGitCommandResult {
        #if os(macOS)
        var snapshot = try validatedSnapshot(at: path)
        try validateRemoteTracking(snapshot)

        var output: [String] = []
        if snapshot.isDirty {
            let message = commitMessage?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard !message.isEmpty else {
                throw LocalGitCommandError.dirtyWithoutCommitMessage
            }

            let addResult = try runGit(["add", "-A"], at: snapshot.path)
            guard addResult.status == 0 else {
                throw LocalGitCommandError.commandFailed(addResult.output)
            }
            if !addResult.output.isEmpty { output.append(addResult.output) }

            let commitResult = try runGit(["commit", "-m", message], at: snapshot.path)
            guard commitResult.status == 0 else {
                throw LocalGitCommandError.commandFailed(commitResult.output)
            }
            if !commitResult.output.isEmpty { output.append(commitResult.output) }
        }

        let fetchResult = try runGit(["fetch", "--prune"], at: snapshot.path)
        guard fetchResult.status == 0 else {
            throw LocalGitCommandError.commandFailed(fetchResult.output)
        }
        if !fetchResult.output.isEmpty { output.append(fetchResult.output) }

        snapshot = try validatedSnapshot(at: path)
        try validateRemoteTracking(snapshot)

        let ahead = snapshot.aheadCount ?? 0
        let behind = snapshot.behindCount ?? 0
        if ahead > 0 && behind > 0 {
            throw LocalGitCommandError.divergentBranch(ahead: ahead, behind: behind)
        }

        if ahead > 0 {
            let pushResult = try runGit(["push"], at: snapshot.path)
            guard pushResult.status == 0 else {
                throw LocalGitCommandError.commandFailed(pushResult.output)
            }
            output.append(pushResult.output.isEmpty ? "Pushed local commits." : pushResult.output)
        }

        if behind > 0 {
            let pullResult = try runGit(["pull", "--ff-only"], at: snapshot.path)
            guard pullResult.status == 0 else {
                throw LocalGitCommandError.commandFailed(pullResult.output)
            }
            output.append(pullResult.output.isEmpty ? "Fast-forwarded local workspace." : pullResult.output)
        }

        let finalSnapshot = try validatedSnapshot(at: path)
        try validateRemoteTracking(finalSnapshot)
        guard !finalSnapshot.isDirty else {
            throw LocalGitCommandError.unresolvedDirtyState
        }
        guard finalSnapshot.aheadCount == 0, finalSnapshot.behindCount == 0 else {
            let ahead = finalSnapshot.aheadCount ?? 0
            let behind = finalSnapshot.behindCount ?? 0
            if ahead > 0 && behind > 0 {
                throw LocalGitCommandError.divergentBranch(ahead: ahead, behind: behind)
            }
            throw LocalGitCommandError.unsafeToRemove("The workspace is not fully synchronized with upstream.")
        }

        if output.isEmpty {
            output.append("Workspace already matched upstream.")
        }
        return LocalGitCommandResult(output: output.joined(separator: "\n\n"))
        #else
        throw LocalGitCommandError.unsupportedPlatform
        #endif
    }

    static func moveCleanWorkspaceToTrash(at path: String) throws -> LocalGitCommandResult {
        #if os(macOS)
        let snapshot = try validatedSnapshot(at: path)
        try validateRemovalPreconditions(snapshot)

        let url = URL(fileURLWithPath: snapshot.path, isDirectory: true)
        do {
            var trashedURL: NSURL?
            try FileManager.default.trashItem(at: url, resultingItemURL: &trashedURL)
            let destination = trashedURL?.path ?? "Trash"
            return LocalGitCommandResult(output: "Moved local workspace to \(destination).")
        } catch {
            throw LocalGitCommandError.trashFailed(error.localizedDescription)
        }
        #else
        throw LocalGitCommandError.unsupportedPlatform
        #endif
    }

    private static func validatedSnapshot(at path: String) throws -> LocalGitSnapshot {
        let trimmedPath = path.trimmingCharacters(in: .whitespacesAndNewlines)
        guard LocalWorkspaceService.workspaceExists(at: trimmedPath) else {
            throw LocalGitCommandError.missingWorkspace
        }

        do {
            return try LocalGitInspector.inspect(at: trimmedPath)
        } catch LocalGitInspectorError.notGitRepository {
            throw LocalGitCommandError.notGitRepository
        } catch LocalGitInspectorError.unsupportedPlatform {
            throw LocalGitCommandError.unsupportedPlatform
        } catch {
            throw LocalGitCommandError.commandFailed(error.localizedDescription)
        }
    }

    private static func validatePushPreconditions(_ snapshot: LocalGitSnapshot) throws {
        try validateRemoteTracking(snapshot)
        guard snapshot.behindCount == 0 else {
            throw LocalGitCommandError.behindRemote(snapshot.behindCount ?? 0)
        }
    }

    private static func validateRemoteTracking(_ snapshot: LocalGitSnapshot) throws {
        guard snapshot.originURL != nil else {
            throw LocalGitCommandError.missingOrigin
        }
        guard snapshot.behindCount != nil,
              snapshot.aheadCount != nil else {
            throw LocalGitCommandError.missingUpstream
        }
    }

    private static func validateRemovalPreconditions(_ snapshot: LocalGitSnapshot) throws {
        guard !snapshot.isDirty else {
            throw LocalGitCommandError.unsafeToRemove("Commit or discard local changes before removing this local copy.")
        }
        try validateRemoteTracking(snapshot)
        guard snapshot.aheadCount == 0 else {
            let ahead = snapshot.aheadCount ?? 0
            throw LocalGitCommandError.unsafeToRemove("Push \(ahead) unpushed commit\(ahead == 1 ? "" : "s") before removing this local copy.")
        }
        guard snapshot.behindCount == 0 else {
            let behind = snapshot.behindCount ?? 0
            throw LocalGitCommandError.unsafeToRemove("Pull \(behind) upstream commit\(behind == 1 ? "" : "s") before removing this local copy.")
        }
    }

    private static func actionVerb(for kind: LocalGitChangedFileKind) -> String {
        switch kind {
        case .added, .untracked:
            return "Add"
        case .deleted:
            return "Remove"
        case .modified, .renamed:
            return "Update"
        }
    }

    private static func displayName(for path: String) -> String {
        let lastComponent = URL(fileURLWithPath: path).deletingPathExtension().lastPathComponent
        let cleaned = lastComponent
            .replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: "-", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard !cleaned.isEmpty else { return "workspace files" }
        return cleaned
    }

    private static func topLevelDirectory(for change: LocalGitChangedFile) -> String? {
        let components = change.path.split(separator: "/").map(String.init)
        guard components.count > 1 else { return nil }
        if let appArea = components.first(where: { ["Views", "Services"].contains($0) }) {
            return appArea
        }
        if components.first == "raCommand", components.count > 2 {
            return components[1]
        }
        return components.first
    }

    private static func groupedMessage(for directory: String) -> String {
        switch directory.lowercased() {
        case "views":
            return "Update project views"
        case "services":
            return "Update local workspace services"
        case "tests", "racommandtests", "racommanduitests":
            return "Update tests"
        default:
            return "Update \(displayName(for: directory))"
        }
    }

    private static func isGitSyncChange(_ files: [LocalGitChangedFile]) -> Bool {
        let gitSyncTerms = [
            "git",
            "repo",
            "repository",
            "workspace",
            "sync",
            "codex"
        ]

        return files.contains { file in
            let lowercasedPath = file.path.lowercased()
            return gitSyncTerms.contains { lowercasedPath.contains($0) }
        }
    }

    #if os(macOS)
    private static func runGit(_ arguments: [String], at path: String) throws -> (status: Int32, output: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = ["-C", path] + arguments

        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr

        do {
            try process.run()
        } catch {
            throw LocalGitCommandError.commandFailed(error.localizedDescription)
        }

        process.waitUntilExit()

        let outputData = stdout.fileHandleForReading.readDataToEndOfFile()
        let errorData = stderr.fileHandleForReading.readDataToEndOfFile()
        let output = String(data: outputData, encoding: .utf8) ?? ""
        let errorOutput = String(data: errorData, encoding: .utf8) ?? ""
        let combined = [output, errorOutput]
            .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .joined(separator: "\n")

        return (process.terminationStatus, combined)
    }
    #endif
}
