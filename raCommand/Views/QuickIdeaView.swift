//
//  QuickIdeaView.swift
//  raCommand
//
//  Linear-style capture modal for routing raw ideas into the client workspace.
//

import SwiftUI

struct QuickIdeaView: View {
    @Environment(\.dismiss) private var dismiss

    let onSaved: (DesktopClient) -> Void

    @State private var clients: [DesktopClient] = []
    @State private var selectedClientId: String?
    @State private var ideaText = ""
    @State private var isLoading = false
    @State private var isSaving = false
    @State private var errorMessage: String?

    private var selectedClient: DesktopClient? {
        clients.first(where: { $0.id == selectedClientId })
    }

    private var canSave: Bool {
        selectedClient != nil &&
        !ideaText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !isSaving
    }

    private var columns: [GridItem] {
        [GridItem(.adaptive(minimum: 120, maximum: 140), spacing: 10, alignment: .top)]
    }

    var body: some View {
        NavigationStack {
            ZStack {
                WhisperBackground()

                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        header

                        if let errorMessage {
                            errorBanner(errorMessage)
                                .padding(.horizontal, 16)
                                .padding(.top, 14)
                        }

                        clientGrid
                        composer
                        footer
                    }
                    .frame(maxWidth: 452)
                    .background(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(
                                LinearGradient(
                                    colors: [WhisperTheme.panelStrong, WhisperTheme.panel],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .stroke(Color.white.opacity(0.10), lineWidth: 1)
                    )
                    .shadow(color: .black.opacity(0.42), radius: 36, x: 0, y: 18)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 24)
                }
            }
            .navigationTitle("Quick Idea")
            .platformNavigationTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
            .task { await loadClientsIfNeeded() }
        }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(WhisperTheme.accent.opacity(0.14))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .stroke(WhisperTheme.accent.opacity(0.28), lineWidth: 1)
                    )
                Circle()
                    .fill(WhisperTheme.accent)
                    .frame(width: 8, height: 8)
                    .shadow(color: WhisperTheme.accent.opacity(0.75), radius: 8)
            }
            .frame(width: 30, height: 30)

            VStack(alignment: .leading, spacing: 2) {
                Text("Quick Idea")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(WhisperTheme.ink)
                Text("Drop a raw thought into a client stream.")
                    .font(.caption)
                    .foregroundStyle(WhisperTheme.mutedInk)
            }

            Spacer()

            Text("esc")
                .font(.system(.caption2, design: .monospaced).weight(.medium))
                .foregroundStyle(WhisperTheme.mutedInk)
                .padding(.horizontal, 6)
                .padding(.vertical, 4)
                .background(WhisperTheme.sidebarSelected, in: RoundedRectangle(cornerRadius: 5, style: .continuous))
        }
        .padding(16)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(WhisperTheme.border)
                .frame(height: 1)
        }
    }

    private var clientGrid: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Text("CLIENT")
                    .font(.system(.caption2, design: .monospaced).weight(.bold))
                    .tracking(0.8)
                    .foregroundStyle(WhisperTheme.mutedInk)
                Text("\(clients.count)")
                    .font(.system(.caption2, design: .monospaced).weight(.medium))
                    .foregroundStyle(WhisperTheme.mutedInk)
                Spacer()
                Text("⌘K to search")
                    .font(.system(.caption2, design: .monospaced).weight(.medium))
                    .foregroundStyle(WhisperTheme.mutedInk.opacity(0.78))
            }

            if isLoading && clients.isEmpty {
                HStack(spacing: 10) {
                    ProgressView()
                        .tint(WhisperTheme.accent)
                    Text("Loading clients…")
                        .font(.subheadline)
                        .foregroundStyle(WhisperTheme.mutedInk)
                }
                .whisperInsetField()
            } else if clients.isEmpty {
                WhisperEmptyState(
                    icon: "person.3",
                    title: "No clients available",
                    message: "The desktop directory returned no client records."
                )
            } else {
                LazyVGrid(columns: columns, spacing: 10) {
                    ForEach(clients) { client in
                        Button {
                            selectedClientId = client.id
                        } label: {
                            QuickIdeaClientTile(
                                client: client,
                                isSelected: selectedClientId == client.id
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .padding(16)
    }

    private var composer: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("IDEA")
                .font(.system(.caption2, design: .monospaced).weight(.bold))
                .tracking(0.8)
                .foregroundStyle(WhisperTheme.mutedInk)

            TextField("What should not get lost?", text: $ideaText, axis: .vertical)
                .lineLimit(2...4)
                .textFieldStyle(.plain)
                .padding(.horizontal, 12)
                .padding(.vertical, 11)
                .background(WhisperTheme.input, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(canSave ? WhisperTheme.accent.opacity(0.45) : WhisperTheme.border, lineWidth: 1)
                )
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .padding(.bottom, 12)
    }

    private var footer: some View {
        HStack(spacing: 12) {
            HStack(spacing: 8) {
                Circle()
                    .fill(selectedClient == nil ? WhisperTheme.sidebarSelected : WhisperTheme.accentSoft)
                    .frame(width: 22, height: 22)
                    .overlay {
                        Text(selectedClient?.initials ?? "")
                            .font(.system(.caption2, design: .rounded).weight(.bold))
                            .foregroundStyle(selectedClient == nil ? WhisperTheme.mutedInk : WhisperTheme.accent)
                    }

                Text("→ \(selectedClient?.displayName ?? "Select a client")")
                    .font(.caption)
                    .foregroundStyle(WhisperTheme.mutedInk)
                    .lineLimit(1)
            }

            Spacer()

            Button {
                Task { await saveIdea() }
            } label: {
                HStack(spacing: 8) {
                    if isSaving {
                        ProgressView()
                            .tint(.white)
                            .scaleEffect(0.8)
                    }
                    Text(isSaving ? "Saving…" : "Save")
                        .font(.subheadline.weight(.semibold))
                    Text("⌘↵")
                        .font(.system(.caption2, design: .monospaced).weight(.bold))
                        .foregroundStyle(Color.white.opacity(0.76))
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 9)
                .background(WhisperTheme.accent, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                .foregroundStyle(.white)
            }
            .buttonStyle(.plain)
            .disabled(!canSave)
            .opacity(canSave ? 1 : 0.6)
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .padding(.bottom, 16)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(WhisperTheme.border)
                .frame(height: 1)
        }
    }

    private func errorBanner(_ message: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(WhisperTheme.danger)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(WhisperTheme.danger)
            Spacer()
        }
        .padding(14)
        .background(WhisperTheme.danger.opacity(0.08), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private func loadClientsIfNeeded() async {
        guard clients.isEmpty else { return }

        isLoading = true
        errorMessage = nil

        do {
            let fetchedClients = try await ClientNoteService.fetchDesktopClients()
            clients = fetchedClients
            selectedClientId = fetchedClients.first?.id
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }

        isLoading = false
    }

    private func saveIdea() async {
        guard let selectedClient else { return }

        let trimmed = ideaText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        isSaving = true
        errorMessage = nil

        do {
            try await ClientNoteService.submitIdea(clientId: selectedClient.id, text: trimmed)
            onSaved(selectedClient)
            dismiss()
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }

        isSaving = false
    }
}

private struct QuickIdeaClientTile: View {
    let client: DesktopClient
    let isSelected: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ZStack {
                Circle()
                    .fill(isSelected ? WhisperTheme.accent.opacity(0.16) : WhisperTheme.info.opacity(0.10))
                    .frame(width: 30, height: 30)

                Text(client.initials)
                    .font(.system(.caption, design: .rounded).weight(.bold))
                    .foregroundStyle(isSelected ? WhisperTheme.accent : WhisperTheme.info)
            }

            Text(client.displayName)
                .font(.caption.weight(.semibold))
                .foregroundStyle(WhisperTheme.ink)
                .lineLimit(2)

            if let storyId = client.storyId, !storyId.isEmpty {
                Text(storyId)
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundStyle(WhisperTheme.mutedInk)
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 104, alignment: .topLeading)
        .padding(11)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(isSelected ? WhisperTheme.accent.opacity(0.09) : WhisperTheme.input)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(isSelected ? WhisperTheme.accent.opacity(0.55) : WhisperTheme.border, lineWidth: 1)
        )
    }
}

private struct QuickIdeaConfirmationBanner: View {
    let message: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(WhisperTheme.success)
            Text(message)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(WhisperTheme.ink)
            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(WhisperTheme.panel, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(WhisperTheme.success.opacity(0.2), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.12), radius: 16, x: 0, y: 6)
        .padding(.horizontal, 20)
        .padding(.bottom, 18)
    }
}

private struct QuickIdeaToolbarModifier: ViewModifier {
    @State private var showingQuickIdea = false
    @State private var confirmationMessage: String?

    func body(content: Content) -> some View {
        content
            .toolbar {
                ToolbarItem(placement: .platformNavigationTrailing) {
                    Button {
                        showingQuickIdea = true
                    } label: {
                        Image(systemName: "lightbulb.max")
                            .foregroundStyle(WhisperTheme.accent)
                    }
                    .help("Quick idea")
                }
            }
            .sheet(isPresented: $showingQuickIdea) {
                QuickIdeaView { client in
                    confirmationMessage = "Saved to \(client.displayName)"
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2.2) {
                        confirmationMessage = nil
                    }
                }
            }
            .overlay(alignment: .bottom) {
                if let confirmationMessage {
                    QuickIdeaConfirmationBanner(message: confirmationMessage)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .animation(.easeInOut(duration: 0.2), value: confirmationMessage != nil)
    }
}

extension View {
    func quickIdeaToolbar() -> some View {
        modifier(QuickIdeaToolbarModifier())
    }
}
