//
//  AdminSyncKeyPanelView.swift
//  raCommand
//
//  Settings field for the readyaimgo admin API key. This is what
//  ClientNoteService.applyDesktopAuthorization(to:) sends as a Bearer
//  token to every /api/desktop/*, /api/admin/*, and /api/contracts call
//  (People/Invoices/Contracts tabs, workspace-create sync). Before this
//  panel existed, the only way to set it was the RAG_INTERNAL_API_KEY /
//  READYAIMGO_INTERNAL_API_KEY env vars — which a GUI-launched app never
//  sees, only a Terminal-launched one. Keychain storage here takes
//  priority over both env vars (see applyDesktopAuthorization).
//

import SwiftUI

struct AdminSyncKeyPanelView: View {
    @State private var hasKey = false
    @State private var showKeyField = false
    @State private var keyInput = ""
    @State private var savedMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            WhisperSectionTitle(
                eyebrow: "readyaimgo admin",
                title: "Sync API key",
                detail: "Required for People, Invoices, Contracts, and pushing new workspaces to admin."
            )

            HStack(alignment: .center, spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    if hasKey {
                        Text("Key saved")
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(WhisperTheme.success)
                    } else {
                        Text("No key saved — People/Invoices/Contracts will fail to load")
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

                Button(hasKey ? "Change key" : "Add key") {
                    showKeyField.toggle()
                }
                .buttonStyle(.plain)
                .font(.caption.weight(.semibold))
                .foregroundStyle(WhisperTheme.accent)

                if hasKey {
                    Button("Remove", role: .destructive) {
                        KeychainService.deleteDesktopSessionToken()
                        hasKey = false
                        savedMessage = nil
                    }
                    .buttonStyle(.plain)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(WhisperTheme.danger)
                }
            }

            if showKeyField {
                HStack(spacing: 8) {
                    SecureField("READYAIMGO_INTERNAL_API_KEY value", text: $keyInput)
                        .platformDisableTextInputAutocapitalization()
                        .autocorrectionDisabled()
                        .foregroundStyle(WhisperTheme.ink)
                        .whisperInsetField()

                    Button("Save") {
                        let trimmed = keyInput.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !trimmed.isEmpty else { return }
                        KeychainService.saveDesktopSessionToken(trimmed)
                        keyInput = ""
                        hasKey = true
                        showKeyField = false
                        savedMessage = "Saved just now"
                    }
                    .buttonStyle(.plain)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(WhisperTheme.accent)
                    .disabled(keyInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
        .whisperPanel()
        .task {
            hasKey = KeychainService.loadDesktopSessionToken() != nil
        }
    }
}
