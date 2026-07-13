//
//  PeopleView.swift
//  raCommand
//
//  Read-only mirror of readyaimgo admin's client/people directory.
//

import SwiftUI

struct PeopleView: View {
    @State private var people: [DesktopClient] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var searchText = ""

    private var filteredPeople: [DesktopClient] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return people }
        return people.filter { person in
            person.displayName.localizedCaseInsensitiveContains(query)
                || (person.email ?? "").localizedCaseInsensitiveContains(query)
        }
    }

    private var gridColumns: [GridItem] {
        [GridItem(.adaptive(minimum: 280, maximum: 340), spacing: 14, alignment: .top)]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            header

            TextField("Search people…", text: $searchText)
                .platformDisableTextInputAutocapitalization()
                .autocorrectionDisabled()
                .foregroundStyle(WhisperTheme.ink)
                .whisperInsetField()
                .frame(maxWidth: 360)

            if let errorMessage {
                Text(errorMessage)
                    .font(.callout)
                    .foregroundStyle(WhisperTheme.danger)
                    .whisperPanel()
            }

            if isLoading && people.isEmpty {
                ProgressView()
                    .tint(WhisperTheme.accent)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 40)
            } else if filteredPeople.isEmpty {
                WhisperEmptyState(
                    icon: "person.2",
                    title: people.isEmpty ? "No people yet" : "No matches",
                    message: people.isEmpty
                        ? "People created in the readyaimgo admin will show up here."
                        : "Try a different search term."
                )
            } else {
                LazyVGrid(columns: gridColumns, spacing: 14) {
                    ForEach(filteredPeople) { person in
                        personCard(person)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .task { await load() }
    }

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                Text("People")
                    .font(.system(size: 24, weight: .bold))
                    .foregroundStyle(WhisperTheme.ink)
                Text(people.isEmpty ? "Clients tracked in readyaimgo admin" : "\(people.count) \(people.count == 1 ? "person" : "people") synced")
                    .font(.system(size: 13))
                    .foregroundStyle(WhisperTheme.mutedInk)
            }

            Spacer(minLength: 12)

            Button {
                Task { await load() }
            } label: {
                Image(systemName: "arrow.clockwise")
                    .foregroundStyle(WhisperTheme.mutedInk)
            }
            .buttonStyle(.plain)
            .disabled(isLoading)
        }
    }

    private func personCard(_ person: DesktopClient) -> some View {
        VStack(alignment: .leading, spacing: 11) {
            HStack(alignment: .center, spacing: 10) {
                Circle()
                    .fill(WhisperTheme.accentSoft)
                    .frame(width: 34, height: 34)
                    .overlay(
                        Text(person.initials)
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(WhisperTheme.accent)
                    )

                VStack(alignment: .leading, spacing: 1) {
                    Text(person.displayName)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(WhisperTheme.ink)
                        .lineLimit(1)

                    Text(person.email ?? person.storyId ?? "No email on file")
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundStyle(WhisperTheme.mutedInk)
                        .lineLimit(1)
                }

                Spacer(minLength: 8)

                if let status = person.status, !status.isEmpty {
                    Text(status.uppercased())
                        .font(.system(size: 10, weight: .semibold, design: .monospaced))
                        .padding(.horizontal, 7)
                        .frame(height: 19)
                        .background(statusColor(status).opacity(0.14), in: RoundedRectangle(cornerRadius: 5, style: .continuous))
                        .foregroundStyle(statusColor(status))
                }
            }

            Rectangle()
                .fill(Color.white.opacity(0.06))
                .frame(height: 1)

            HStack {
                if let workspaceId = person.workspaceId, !workspaceId.isEmpty {
                    Text(workspaceId)
                        .font(.system(size: 10, weight: .semibold, design: .monospaced))
                        .padding(.horizontal, 7)
                        .frame(height: 18)
                        .background(WhisperTheme.accent.opacity(0.10), in: RoundedRectangle(cornerRadius: 5, style: .continuous))
                        .foregroundStyle(WhisperTheme.info)
                        .lineLimit(1)
                } else if !person.activeProducts.isEmpty {
                    Text(person.activeProducts.joined(separator: ", "))
                        .font(.system(size: 10, weight: .semibold, design: .monospaced))
                        .foregroundStyle(WhisperTheme.info)
                        .lineLimit(1)
                } else {
                    Text("No workspace")
                        .font(.system(size: 11))
                        .foregroundStyle(WhisperTheme.mutedInk)
                }

                Spacer(minLength: 8)

                Text(lastActivityLabel(for: person))
                    .font(.system(size: 11))
                    .foregroundStyle(WhisperTheme.mutedInk)
            }
        }
        .padding(14)
        .background(
            LinearGradient(colors: [WhisperTheme.panel, WhisperTheme.panelStrong], startPoint: .topLeading, endPoint: .bottomTrailing),
            in: RoundedRectangle(cornerRadius: 11, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .stroke(Color.white.opacity(0.07), lineWidth: 1)
        )
    }

    private func statusColor(_ status: String) -> Color {
        switch status.lowercased() {
        case "active", "onboarding": return WhisperTheme.success
        case "archived", "churned": return WhisperTheme.mutedInk
        default: return WhisperTheme.info
        }
    }

    private func lastActivityLabel(for person: DesktopClient) -> String {
        guard let updatedAt = person.updatedAt, let date = ISO8601DateFormatter().date(from: updatedAt) else {
            return "—"
        }
        let days = Calendar.current.dateComponents([.day], from: date, to: Date()).day ?? 0
        if days <= 0 { return "Today" }
        if days == 1 { return "1 day ago" }
        return "\(days) days ago"
    }

    @MainActor
    private func load() async {
        isLoading = true
        errorMessage = nil
        do {
            people = try await ClientNoteService.fetchDesktopClients()
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
        isLoading = false
    }
}
