//
//  GitHubTokenPanelView.swift
//  raCommand
//
//  Settings field for the GitHub Personal Access Token used by
//  GitHubActionsService (repo creation) and GitHubService (repo listing).
//  A token field already existed inside the Workspaces > Import > "Import
//  from GitHub" sheet, but that's a non-obvious place to look for a
//  credential — this surfaces the same Keychain entry (KeychainService's
//  githubToken account) in Settings, next to the other API keys.
//

import SwiftUI

struct GitHubTokenPanelView: View {
    @State private var hasToken = false
    @State private var showTokenField = false
    @State private var tokenInput = ""
    @State private var savedMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            WhisperSectionTitle(
                eyebrow: "GitHub",
                title: "Personal access token",
                detail: "Needs the `repo` scope to create repositories. Read-only tokens can list repos but not create them."
            )

            HStack(alignment: .center, spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    if hasToken {
                        Text("Token saved")
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(WhisperTheme.success)
                    } else {
                        Text("No token saved — creating repos and Codex workspaces will fail")
                            .font(.subheadline)
                            .foregroundStyle(WhisperTheme.warning)
                    }
                    if let savedMessage {
                        Text(savedMessage)
                            .font(.caption2)
                            .foregroundStyle(WhisperTheme.mutedInk)
                    }
                }

                Spacer(minLength: 8)

                Button("Generate on GitHub") {
                    PlatformSystemServices.open(URL(string: "https://github.com/settings/tokens/new?scopes=repo&description=raCommand")!)
                }
                .buttonStyle(.plain)
                .font(.caption.weight(.semibold))
                .foregroundStyle(WhisperTheme.mutedInk)

                Button(hasToken ? "Change token" : "Add token") {
                    showTokenField.toggle()
                }
                .buttonStyle(.plain)
                .font(.caption.weight(.semibold))
                .foregroundStyle(WhisperTheme.accent)

                if hasToken {
                    Button("Remove", role: .destructive) {
                        KeychainService.deleteGitHubToken()
                        hasToken = false
                        savedMessage = nil
                    }
                    .buttonStyle(.plain)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(WhisperTheme.danger)
                }
            }

            if showTokenField {
                HStack(spacing: 8) {
                    SecureField("ghp_xxxxxxxxxxxx", text: $tokenInput)
                        .platformDisableTextInputAutocapitalization()
                        .autocorrectionDisabled()
                        .foregroundStyle(WhisperTheme.ink)
                        .whisperInsetField()

                    Button("Save") {
                        let trimmed = tokenInput.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !trimmed.isEmpty else { return }
                        KeychainService.saveGitHubToken(trimmed)
                        tokenInput = ""
                        hasToken = true
                        showTokenField = false
                        savedMessage = "Saved just now"
                    }
                    .buttonStyle(.plain)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(WhisperTheme.accent)
                    .disabled(tokenInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
        .whisperPanel()
        .task {
            hasToken = KeychainService.hasGitHubToken()
        }
    }
}
