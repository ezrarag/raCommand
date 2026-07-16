//
//  VercelTokenPanelView.swift
//  raCommand
//
//  Settings field for the Vercel Personal Access Token and Team ID.
//

import SwiftUI

struct VercelTokenPanelView: View {
    @State private var hasToken = false
    @State private var showTokenField = false
    @State private var tokenInput = ""
    @State private var teamIdInput = ""
    @State private var savedMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            WhisperSectionTitle(
                eyebrow: "Vercel",
                title: "Personal access token",
                detail: "Required to fetch deployment history and project analytics directly in raCommand. Team ID is optional and only needed if your projects belong to a Vercel team."
            )

            HStack(alignment: .center, spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    if hasToken {
                        Text("Token saved")
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(WhisperTheme.success)
                    } else {
                        Text("No token saved — Vercel deployments will be unavailable")
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

                Button("Generate Token") {
                    PlatformSystemServices.open(URL(string: "https://vercel.com/account/tokens")!)
                }
                .buttonStyle(.plain)
                .font(.caption.weight(.semibold))
                .foregroundStyle(WhisperTheme.mutedInk)

                Button(hasToken ? "Change credentials" : "Add token") {
                    showTokenField.toggle()
                }
                .buttonStyle(.plain)
                .font(.caption.weight(.semibold))
                .foregroundStyle(WhisperTheme.accent)

                if hasToken {
                    Button("Remove", role: .destructive) {
                        KeychainService.deleteVercelToken()
                        KeychainService.deleteVercelTeamId()
                        hasToken = false
                        savedMessage = nil
                        tokenInput = ""
                        teamIdInput = ""
                    }
                    .buttonStyle(.plain)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(WhisperTheme.danger)
                }
            }

            if showTokenField {
                VStack(spacing: 8) {
                    SecureField("Vercel Access Token", text: $tokenInput)
                        .platformDisableTextInputAutocapitalization()
                        .autocorrectionDisabled()
                        .foregroundStyle(WhisperTheme.ink)
                        .whisperInsetField()

                    TextField("Team ID (optional, e.g. team_xxxx)", text: $teamIdInput)
                        .platformDisableTextInputAutocapitalization()
                        .autocorrectionDisabled()
                        .foregroundStyle(WhisperTheme.ink)
                        .whisperInsetField()

                    Button("Save Credentials") {
                        let trimmedToken = tokenInput.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !trimmedToken.isEmpty else { return }
                        
                        KeychainService.saveVercelToken(trimmedToken)
                        
                        let trimmedTeam = teamIdInput.trimmingCharacters(in: .whitespacesAndNewlines)
                        if !trimmedTeam.isEmpty {
                            KeychainService.saveVercelTeamId(trimmedTeam)
                        } else {
                            KeychainService.deleteVercelTeamId()
                        }
                        
                        tokenInput = ""
                        hasToken = true
                        showTokenField = false
                        savedMessage = "Credentials saved just now"
                    }
                    .buttonStyle(.plain)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(WhisperTheme.accent)
                    .disabled(tokenInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
                .padding(.top, 4)
            }
        }
        .whisperPanel()
        .task {
            hasToken = KeychainService.hasVercelToken()
            if hasToken {
                teamIdInput = KeychainService.loadVercelTeamId() ?? ""
            }
        }
    }
}
