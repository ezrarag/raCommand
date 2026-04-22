//
//  ProjectImportService.swift
//  raCommand
//
//  Created by E. Haugabrooks on 2/1/26.
//

import Foundation
import SwiftData

struct ProjectImportRow: Identifiable {
    let id = UUID()
    var name: String
    var clientName: String
    var status: ProjectStatus
    var valueScore: Int
    var notes: String
    var repoURL: String
    var vercelURL: String
}

enum ProjectImportError: LocalizedError {
    case emptyFile
    case invalidCSV
    case invalidJSON

    var errorDescription: String? {
        switch self {
        case .emptyFile:
            return "The selected file is empty."
        case .invalidCSV:
            return "Could not parse the CSV file. Make sure it has a header row."
        case .invalidJSON:
            return "Could not parse the JSON file. Expect an array or {\"projects\": [...] }."
        }
    }
}

struct ProjectImportService {
    static func parseCSV(data: Data) throws -> [ProjectImportRow] {
        guard let text = decodedString(from: data) else {
            throw ProjectImportError.invalidCSV
        }
        let rows = parseCSVRows(text)
        guard let header = rows.first else {
            throw ProjectImportError.emptyFile
        }

        let headerMap = header.enumerated().reduce(into: [String: Int]()) { result, entry in
            let key = normalizeHeader(entry.element)
            if !key.isEmpty {
                result[key] = entry.offset
            }
        }

        guard headerMap["name"] != nil else {
            throw ProjectImportError.invalidCSV
        }

        var parsed: [ProjectImportRow] = []
        for row in rows.dropFirst() {
            let name = value(for: "name", in: row, headerMap: headerMap)
            let clientName = value(for: "clientname", in: row, headerMap: headerMap)
            let status = statusFromString(value(for: "status", in: row, headerMap: headerMap))
            let valueScore = valueScoreFromString(value(for: "valuescore", in: row, headerMap: headerMap))
            let notes = value(for: "notes", in: row, headerMap: headerMap)
            let repoURL = value(for: "repourl", in: row, headerMap: headerMap)
            let vercelURL = value(for: "vercelurl", in: row, headerMap: headerMap)

            parsed.append(ProjectImportRow(
                name: name,
                clientName: clientName,
                status: status,
                valueScore: valueScore,
                notes: notes,
                repoURL: repoURL,
                vercelURL: vercelURL
            ))
        }

        return parsed
    }

    static func parseJSON(data: Data) throws -> [ProjectImportRow] {
        let json = try JSONSerialization.jsonObject(with: data, options: [])
        let objects: [[String: Any]]

        if let array = json as? [[String: Any]] {
            objects = array
        } else if let dict = json as? [String: Any],
                  let array = dict["projects"] as? [[String: Any]] {
            objects = array
        } else {
            throw ProjectImportError.invalidJSON
        }

        return objects.map { object in
            let name = stringValue(object["name"])
            let clientName = stringValue(object["clientName"])
            let status = statusFromString(stringValue(object["status"]))
            let valueScore = valueScoreFromString(stringValue(object["valueScore"]))
            let notes = stringValue(object["notes"])
            let repoURL = stringValue(object["repoURL"])
            let vercelURL = stringValue(object["vercelURL"])

            return ProjectImportRow(
                name: name,
                clientName: clientName,
                status: status,
                valueScore: valueScore,
                notes: notes,
                repoURL: repoURL,
                vercelURL: vercelURL
            )
        }
    }

    static func parsePaste(text: String) -> [ProjectImportRow] {
        let lines = text
            .split(whereSeparator: \.isNewline)
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        return lines.map { parsePasteLine($0) }
    }

    static func insert(rows: [ProjectImportRow], into context: ModelContext) -> Int {
        let validRows = rows.filter { !$0.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

        for row in validRows {
            let project = Project(
                name: row.name.trimmingCharacters(in: .whitespacesAndNewlines),
                status: row.status,
                valueScore: row.valueScore,
                notes: row.notes,
                clientName: row.clientName,
                repoURL: row.repoURL,
                vercelURL: row.vercelURL
            )
            context.insert(project)
        }

        return validRows.count
    }

    static func validRows(from rows: [ProjectImportRow]) -> [ProjectImportRow] {
        rows.filter { !$0.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }

    private static func decodedString(from data: Data) -> String? {
        if let text = String(data: data, encoding: .utf8) {
            return text
        }
        if let text = String(data: data, encoding: .windowsCP1252) {
            return text
        }
        return nil
    }

    private static func parseCSVRows(_ text: String) -> [[String]] {
        var rows: [[String]] = []
        var currentRow: [String] = []
        var currentField = ""
        var inQuotes = false

        var index = text.startIndex
        while index < text.endIndex {
            let char = text[index]

            if char == "\"" {
                if inQuotes {
                    let nextIndex = text.index(after: index)
                    if nextIndex < text.endIndex && text[nextIndex] == "\"" {
                        currentField.append("\"")
                        index = nextIndex
                    } else {
                        inQuotes = false
                    }
                } else {
                    inQuotes = true
                }
            } else if char == "," && !inQuotes {
                currentRow.append(currentField)
                currentField = ""
            } else if (char == "\n" || char == "\r") && !inQuotes {
                currentRow.append(currentField)
                currentField = ""

                if currentRow.contains(where: { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) {
                    rows.append(currentRow)
                }
                currentRow = []

                if char == "\r" {
                    let nextIndex = text.index(after: index)
                    if nextIndex < text.endIndex && text[nextIndex] == "\n" {
                        index = nextIndex
                    }
                }
            } else {
                currentField.append(char)
            }

            index = text.index(after: index)
        }

        if !currentField.isEmpty || !currentRow.isEmpty {
            currentRow.append(currentField)
            if currentRow.contains(where: { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) {
                rows.append(currentRow)
            }
        }

        return rows
    }

    private static func normalizeHeader(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\u{FEFF}", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: " ", with: "")
    }

    private static func value(for key: String, in row: [String], headerMap: [String: Int]) -> String {
        guard let index = headerMap[key], index < row.count else {
            return ""
        }
        return row[index].trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func statusFromString(_ value: String) -> ProjectStatus {
        let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return ProjectStatus(rawValue: normalized) ?? .yellow
    }

    private static func valueScoreFromString(_ value: String) -> Int {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if let score = Int(trimmed) {
            return min(max(score, 1), 10)
        }
        return 5
    }

    private static func stringValue(_ value: Any?) -> String {
        if let value = value as? String {
            return value.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if let value = value as? NSNumber {
            return value.stringValue
        }
        return ""
    }

    private static func parsePasteLine(_ line: String) -> ProjectImportRow {
        let separators = [" — ", " – ", " - ", " | "]
        var components: [String] = []

        for separator in separators where line.contains(separator) {
            components = line.components(separatedBy: separator).map {
                $0.trimmingCharacters(in: .whitespacesAndNewlines)
            }
            break
        }

        if components.isEmpty {
            components = [line]
        }

        var name = components.first ?? line
        var clientName = ""
        var status: ProjectStatus = .yellow
        var valueScore = 5

        if components.count >= 4 {
            name = components[0]
            clientName = components[1]
            status = statusFromString(components[2])
            valueScore = valueScoreFromString(components[3])
        } else if components.count == 3 {
            name = components[0]
            if ProjectStatus(rawValue: components[1].lowercased()) != nil {
                status = statusFromString(components[1])
                valueScore = valueScoreFromString(components[2])
            } else if ProjectStatus(rawValue: components[2].lowercased()) != nil {
                clientName = components[1]
                status = statusFromString(components[2])
            } else {
                clientName = components[1]
                valueScore = valueScoreFromString(components[2])
            }
        } else if components.count == 2 {
            name = components[0]
            if ProjectStatus(rawValue: components[1].lowercased()) != nil {
                status = statusFromString(components[1])
            } else if Int(components[1].trimmingCharacters(in: .whitespacesAndNewlines)) != nil {
                valueScore = valueScoreFromString(components[1])
            } else {
                clientName = components[1]
            }
        }

        return ProjectImportRow(
            name: name,
            clientName: clientName,
            status: status,
            valueScore: valueScore,
            notes: "",
            repoURL: "",
            vercelURL: ""
        )
    }
}
