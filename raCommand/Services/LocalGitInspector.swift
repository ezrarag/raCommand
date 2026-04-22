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
        let repoCheck = try runGit(["rev-parse", "--is-inside-work-tree"], at: trimmedPath)
        guard repoCheck.status == 0,
              repoCheck.output.trimmingCharacters(in: .whitespacesAndNewlines) == "true" else {
            throw LocalGitInspectorError.notGitRepository
        }

        let branchName: String = {
            if let branch = try? runGit(["branch", "--show-current"], at: trimmedPath),
               branch.status == 0 {
                let trimmed = branch.output.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty { return trimmed }
            }

            if let head = try? runGit(["rev-parse", "--short", "HEAD"], at: trimmedPath),
               head.status == 0 {
                let trimmed = head.output.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty { return "detached@\(trimmed)" }
            }

            return "detached HEAD"
        }()

        let statusOutput = try runGit(["status", "--porcelain"], at: trimmedPath)
        let statusCounts = parseStatus(output: statusOutput.output)

        let aheadBehind: (behind: Int?, ahead: Int?) = {
            guard let result = try? runGit(["rev-list", "--left-right", "--count", "@{upstream}...HEAD"], at: trimmedPath),
                  result.status == 0 else {
                return (nil, nil)
            }
            return parseAheadBehind(output: result.output)
        }()

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

    private static func parseStatus(output: String) -> (changedFileCount: Int, stagedCount: Int, unstagedCount: Int, untrackedCount: Int) {
        let lines = output
            .split(separator: "\n", omittingEmptySubsequences: true)
            .map(String.init)

        var staged = 0
        var unstaged = 0
        var untracked = 0

        for line in lines {
            if line.hasPrefix("??") {
                untracked += 1
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
        }

        return (lines.count, staged, unstaged, untracked)
    }

    private static func parseAheadBehind(output: String) -> (behind: Int?, ahead: Int?) {
        let parts = output
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .split(whereSeparator: \.isWhitespace)

        guard parts.count >= 2 else { return (nil, nil) }
        let behind = Int(parts[0])
        let ahead = Int(parts[1])
        return (behind, ahead)
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
