//
//  GitHubImportView.swift
//  raCommand
//
//  Token entry with explicit save confirmation + WhisperTheme styling.
//

import SwiftUI
import SwiftData

struct GitHubImportView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context

    @State private var token = ""
    @State private var repos: [GitHubRepo] = []
    @State private var selectedRepoIds = Set<Int>()
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var tokenSaveState: TokenSaveState = .idle
    @State private var hasExistingToken = false

    enum TokenSaveState {
        case idle, saved, failed
        var label: String {
            switch self {
            case .idle: return "Save Token"
            case .saved: return "Saved ✓"
            case .failed: return "Save Failed"
            }
        }
        var color: Color {
            switch self {
            case .idle: return WhisperTheme.accent
            case .saved: return WhisperTheme.success
            case .failed: return WhisperTheme.danger
            }
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    // Token Section
                    VStack(alignment: .leading, spacing: 14) {
                        WhisperSectionTitle(
                            eyebrow: "Credentials",
                            title: "GitHub Token",
                            detail: hasExistingToken ? "A token is saved. Enter a new one to replace it." : "Enter your Personal Access Token with 'repo' scope."
                        )

                        // Existing token indicator
                        if hasExistingToken && token.isEmpty {
                            HStack(spacing: 8) {
                                Image(systemName: "checkmark.seal.fill")
                                    .foregroundStyle(WhisperTheme.success)
                                Text("Token saved in Keychain")
                                    .font(.subheadline.weight(.medium))
                                    .foregroundStyle(WhisperTheme.success)
                                Spacer()
                                Button("Clear") {
                                    KeychainService.deleteGitHubToken()
                                    hasExistingToken = false
                                    tokenSaveState = .idle
                                }
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(WhisperTheme.danger)
                            }
                            .padding(14)
                            .background(WhisperTheme.success.opacity(0.08), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 16, style: .continuous)
                                    .stroke(WhisperTheme.success.opacity(0.2), lineWidth: 1)
                            )
                        }

                        // Token input
                        SecureField("ghp_xxxxxxxxxxxx", text: $token)
                            .platformDisableTextInputAutocapitalization()
                            .autocorrectionDisabled()
                            .whisperInsetField()
                            .onChange(of: token) { tokenSaveState = .idle }

                        // Save / Fetch row
                        HStack(spacing: 12) {
                            Button {
                                saveToken()
                            } label: {
                                HStack(spacing: 6) {
                                    Image(systemName: tokenSaveState == .saved ? "checkmark" : "key.fill")
                                    Text(tokenSaveState.label)
                                        .fontWeight(.semibold)
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 13)
                                .background(tokenSaveState.color, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                                .foregroundStyle(.white)
                            }
                            .disabled(token.trimmingCharacters(in: .whitespaces).isEmpty)

                            Button {
                                Task { await fetchRepos() }
                            } label: {
                                HStack(spacing: 6) {
                                    if isLoading {
                                        ProgressView()
                                            .tint(.white)
                                            .scaleEffect(0.8)
                                    } else {
                                        Image(systemName: "arrow.down.circle.fill")
                                    }
                                    Text(isLoading ? "Fetching…" : "Fetch Repos")
                                        .fontWeight(.semibold)
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 13)
                                .background(WhisperTheme.info, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                                .foregroundStyle(.white)
                            }
                            .disabled((token.isEmpty && !hasExistingToken) || isLoading)
                        }
                    }
                    .whisperPanel()

                    // Repos Section
                    if !repos.isEmpty {
                        VStack(alignment: .leading, spacing: 14) {
                            WhisperSectionTitle(
                                eyebrow: "Source",
                                title: "Repositories",
                                detail: "\(repos.count) repos found. Select to import as projects."
                            )

                            VStack(spacing: 0) {
                                ForEach(repos) { repo in
                                    HStack(spacing: 12) {
                                        Image(systemName: selectedRepoIds.contains(repo.id) ? "checkmark.circle.fill" : "circle")
                                            .foregroundStyle(selectedRepoIds.contains(repo.id) ? WhisperTheme.accent : WhisperTheme.mutedInk)
                                            .font(.system(size: 20))

                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(repo.name)
                                                .font(.subheadline.weight(.semibold))
                                                .foregroundStyle(WhisperTheme.ink)
                                            if let desc = repo.description, !desc.isEmpty {
                                                Text(desc)
                                                    .font(.caption)
                                                    .foregroundStyle(WhisperTheme.mutedInk)
                                                    .lineLimit(1)
                                            }
                                        }
                                        Spacer()
                                    }
                                    .padding(.vertical, 12)
                                    .contentShape(Rectangle())
                                    .onTapGesture {
                                        if selectedRepoIds.contains(repo.id) {
                                            selectedRepoIds.remove(repo.id)
                                        } else {
                                            selectedRepoIds.insert(repo.id)
                                        }
                                    }

                                    if repo.id != repos.last?.id {
                                        Divider()
                                    }
                                }
                            }
                        }
                        .whisperPanel()
                    } else if isLoading {
                        ProgressView("Loading repos…")
                            .tint(WhisperTheme.accent)
                            .frame(maxWidth: .infinity)
                            .whisperPanel()
                    }

                    if let error = errorMessage {
                        HStack(spacing: 8) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundStyle(WhisperTheme.danger)
                            Text(error)
                                .font(.subheadline)
                                .foregroundStyle(WhisperTheme.danger)
                        }
                        .whisperPanel()
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 16)
            }
            .whisperShell()
            .navigationTitle("GitHub Import")
            .platformNavigationTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Import \(selectedRepoIds.count > 0 ? "(\(selectedRepoIds.count))" : "")") {
                        importSelected()
                        dismiss()
                    }
                    .disabled(selectedRepoIds.isEmpty)
                    .fontWeight(.semibold)
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
            .task {
                hasExistingToken = KeychainService.hasGitHubToken()
                if token.isEmpty, let saved = KeychainService.loadGitHubToken() {
                    token = saved
                }
            }
        }
    }

    // MARK: - Save Token
    private func saveToken() {
        let trimmed = token.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        let success = KeychainService.saveGitHubToken(trimmed)
        tokenSaveState = success ? .saved : .failed
        hasExistingToken = success

        // Reset label after delay
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
            if tokenSaveState == .saved { tokenSaveState = .idle }
        }
    }

    // MARK: - Fetch Repos
    private func fetchRepos() async {
        isLoading = true
        errorMessage = nil

        // Save token first if it's been entered
        let trimmed = token.trimmingCharacters(in: .whitespaces)
        if !trimmed.isEmpty {
            KeychainService.saveGitHubToken(trimmed)
            hasExistingToken = true
        }

        let activeToken = trimmed.isEmpty ? (KeychainService.loadGitHubToken() ?? "") : trimmed
        guard !activeToken.isEmpty else {
            errorMessage = "No token available. Enter and save your PAT first."
            isLoading = false
            return
        }

        do {
            repos = try await GitHubService.fetchRepos(token: activeToken)
            selectedRepoIds = []
        } catch {
            errorMessage = "Could not fetch repos. Check your token has 'repo' scope."
        }
        isLoading = false
    }

    // MARK: - Import Selected
    private func importSelected() {
        let selected = repos.filter { selectedRepoIds.contains($0.id) }
        for repo in selected {
            let project = Project(
                name: repo.name,
                status: .yellow,
                valueScore: 5,
                notes: repo.description ?? "",
                repoURL: repo.htmlURL
            )
            context.insert(project)
        }
    }
}
