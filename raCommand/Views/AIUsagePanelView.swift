//
//  AIUsagePanelView.swift
//  raCommand
//
//  Settings panel for tracking token usage across AI providers. Keys are
//  Keychain-only and never leave the device except in a direct HTTPS call
//  to that provider's own usage API.
//

import SwiftUI

struct AIUsagePanelView: View {
    @State private var hasAnthropicKey = false
    @State private var hasOpenAIKey = false

    @State private var showAnthropicKeyField = false
    @State private var showOpenAIKeyField = false
    @State private var anthropicKeyInput = ""
    @State private var openAIKeyInput = ""

    @State private var anthropicUsage: AIUsageSummary?
    @State private var openAIUsage: AIUsageSummary?
    @State private var anthropicError: String?
    @State private var openAIError: String?
    @State private var isLoadingAnthropic = false
    @State private var isLoadingOpenAI = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            WhisperSectionTitle(
                eyebrow: "AI usage",
                title: "Token usage across providers",
                detail: "Needs each provider's org-level Admin API key — a different credential from a normal chat key."
            )

            providerRow(
                title: "Anthropic",
                hasKey: hasAnthropicKey,
                usage: anthropicUsage,
                error: anthropicError,
                isLoading: isLoadingAnthropic,
                keyPlaceholder: "sk-ant-admin...",
                showKeyField: $showAnthropicKeyField,
                keyInput: $anthropicKeyInput,
                onSaveKey: {
                    KeychainService.saveAnthropicAdminKey(anthropicKeyInput)
                    anthropicKeyInput = ""
                    hasAnthropicKey = true
                    showAnthropicKeyField = false
                    Task { await loadAnthropicUsage() }
                },
                onRemoveKey: {
                    KeychainService.deleteAnthropicAdminKey()
                    hasAnthropicKey = false
                    anthropicUsage = nil
                    anthropicError = nil
                },
                onRefresh: { Task { await loadAnthropicUsage() } }
            )

            Divider().background(WhisperTheme.border)

            providerRow(
                title: "OpenAI (API)",
                hasKey: hasOpenAIKey,
                usage: openAIUsage,
                error: openAIError,
                isLoading: isLoadingOpenAI,
                keyPlaceholder: "Admin API key from platform.openai.com",
                showKeyField: $showOpenAIKeyField,
                keyInput: $openAIKeyInput,
                onSaveKey: {
                    KeychainService.saveOpenAIAdminKey(openAIKeyInput)
                    openAIKeyInput = ""
                    hasOpenAIKey = true
                    showOpenAIKeyField = false
                    Task { await loadOpenAIUsage() }
                },
                onRemoveKey: {
                    KeychainService.deleteOpenAIAdminKey()
                    hasOpenAIKey = false
                    openAIUsage = nil
                    openAIError = nil
                },
                onRefresh: { Task { await loadOpenAIUsage() } }
            )

            Divider().background(WhisperTheme.border)

            VStack(alignment: .leading, spacing: 2) {
                Text("Gemini")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(WhisperTheme.ink)
                Text("Not automated — Google's usage data lives in Cloud Monitoring and needs a service-account OAuth setup, not a single API key.")
                    .font(.caption)
                    .foregroundStyle(WhisperTheme.mutedInk)
            }

            Text("This only covers pay-as-you-go API usage. ChatGPT.com's subscription message caps (Plus/Pro/Team) aren't exposed by any public API, so they can't be tracked here.")
                .font(.caption2)
                .foregroundStyle(WhisperTheme.mutedInk)
        }
        .whisperPanel()
        .task {
            hasAnthropicKey = KeychainService.loadAnthropicAdminKey() != nil
            hasOpenAIKey = KeychainService.loadOpenAIAdminKey() != nil
            if hasAnthropicKey { await loadAnthropicUsage() }
            if hasOpenAIKey { await loadOpenAIUsage() }
        }
    }

    @ViewBuilder
    private func providerRow(
        title: String,
        hasKey: Bool,
        usage: AIUsageSummary?,
        error: String?,
        isLoading: Bool,
        keyPlaceholder: String,
        showKeyField: Binding<Bool>,
        keyInput: Binding<String>,
        onSaveKey: @escaping () -> Void,
        onRemoveKey: @escaping () -> Void,
        onRefresh: @escaping () -> Void
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .center, spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(WhisperTheme.ink)

                    if let usage {
                        Text("\(usage.totalTokens.formatted()) tokens · \(usage.periodLabel)")
                            .font(.caption)
                            .foregroundStyle(WhisperTheme.mutedInk)
                    } else if let error {
                        Text(error)
                            .font(.caption)
                            .foregroundStyle(WhisperTheme.danger)
                            .lineLimit(2)
                    } else if hasKey {
                        Text("Key saved — refresh to load usage.")
                            .font(.caption)
                            .foregroundStyle(WhisperTheme.mutedInk)
                    } else {
                        Text("No admin key saved yet.")
                            .font(.caption)
                            .foregroundStyle(WhisperTheme.mutedInk)
                    }
                }

                Spacer(minLength: 8)

                if isLoading {
                    ProgressView().controlSize(.small)
                } else if hasKey {
                    Button(action: onRefresh) {
                        Image(systemName: "arrow.clockwise")
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(WhisperTheme.mutedInk)
                }

                Button(hasKey ? "Change key" : "Add key") {
                    showKeyField.wrappedValue.toggle()
                }
                .buttonStyle(.plain)
                .font(.caption.weight(.semibold))
                .foregroundStyle(WhisperTheme.accent)

                if hasKey {
                    Button("Remove", role: .destructive, action: onRemoveKey)
                        .buttonStyle(.plain)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(WhisperTheme.danger)
                }
            }

            if showKeyField.wrappedValue {
                HStack(spacing: 8) {
                    SecureField(keyPlaceholder, text: keyInput)
                        .platformDisableTextInputAutocapitalization()
                        .autocorrectionDisabled()
                        .foregroundStyle(WhisperTheme.ink)
                        .whisperInsetField()

                    Button("Save") { onSaveKey() }
                        .buttonStyle(.plain)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(WhisperTheme.accent)
                        .disabled(keyInput.wrappedValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }

    @MainActor
    private func loadAnthropicUsage() async {
        isLoadingAnthropic = true
        anthropicError = nil
        do {
            anthropicUsage = try await AIUsageService.fetchAnthropicUsage()
        } catch {
            anthropicError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
        isLoadingAnthropic = false
    }

    @MainActor
    private func loadOpenAIUsage() async {
        isLoadingOpenAI = true
        openAIError = nil
        do {
            openAIUsage = try await AIUsageService.fetchOpenAIUsage()
        } catch {
            openAIError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
        isLoadingOpenAI = false
    }
}
