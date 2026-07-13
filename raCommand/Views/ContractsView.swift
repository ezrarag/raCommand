//
//  ContractsView.swift
//  raCommand
//
//  Read-only mirror of readyaimgo admin's contracts collection.
//

import SwiftUI

private let contractColumns: [GridItem] = [
    GridItem(.flexible(minimum: 160), spacing: 12, alignment: .leading),
    GridItem(.fixed(120), spacing: 12, alignment: .leading),
    GridItem(.fixed(110), spacing: 12, alignment: .leading),
    GridItem(.fixed(90), spacing: 0, alignment: .trailing),
]

struct ContractsView: View {
    @State private var contracts: [AdminContract] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var searchText = ""

    private var filteredContracts: [AdminContract] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return contracts }
        return contracts.filter { contract in
            contract.displayTitle.localizedCaseInsensitiveContains(query)
                || (contract.clientId ?? "").localizedCaseInsensitiveContains(query)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            header

            TextField("Search contracts…", text: $searchText)
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

            if isLoading && contracts.isEmpty {
                ProgressView()
                    .tint(WhisperTheme.accent)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 40)
            } else if filteredContracts.isEmpty {
                WhisperEmptyState(
                    icon: "doc.plaintext",
                    title: contracts.isEmpty ? "No contracts yet" : "No matches",
                    message: contracts.isEmpty
                        ? "Contracts created in the readyaimgo admin will show up here."
                        : "Try a different search term."
                )
            } else {
                table
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .task { await load() }
    }

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Contracts")
                    .font(.system(size: 24, weight: .bold))
                    .foregroundStyle(WhisperTheme.ink)
                Text(contracts.isEmpty ? "Agreements tracked in readyaimgo admin" : "\(contracts.count) \(contracts.count == 1 ? "contract" : "contracts") synced")
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

    private var table: some View {
        VStack(spacing: 0) {
            LazyVGrid(columns: contractColumns, spacing: 12) {
                Text("TITLE").tableHeader()
                Text("TYPE").tableHeader()
                Text("WORKSPACE").tableHeader()
                Text("STATUS").tableHeader(alignment: .trailing)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 9)
            .background(Color.white.opacity(0.03))
            .overlay(alignment: .bottom) {
                Rectangle().fill(Color.white.opacity(0.06)).frame(height: 1)
            }

            ForEach(filteredContracts) { contract in
                LazyVGrid(columns: contractColumns, spacing: 12) {
                    HStack(spacing: 8) {
                        Image(systemName: contract.fileUrl != nil ? "doc.fill" : "doc")
                            .font(.system(size: 11))
                            .foregroundStyle(WhisperTheme.accent)
                        Text(contract.displayTitle)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(WhisperTheme.ink)
                            .lineLimit(1)
                    }

                    Text(contract.displayType)
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundStyle(WhisperTheme.mutedInk)
                        .lineLimit(1)

                    Text(contract.workspaceId ?? "—")
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundStyle(WhisperTheme.mutedInk)
                        .lineLimit(1)

                    Text(contract.displayStatus.uppercased())
                        .font(.system(size: 10, weight: .semibold, design: .monospaced))
                        .padding(.horizontal, 8)
                        .frame(height: 20)
                        .background(statusColor(contract.status).opacity(0.14), in: RoundedRectangle(cornerRadius: 5, style: .continuous))
                        .foregroundStyle(statusColor(contract.status))
                        .frame(maxWidth: .infinity, alignment: .trailing)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .overlay(alignment: .bottom) {
                    Rectangle().fill(Color.white.opacity(0.04)).frame(height: 1)
                }
            }
        }
        .background(WhisperTheme.panel, in: RoundedRectangle(cornerRadius: 11, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .stroke(Color.white.opacity(0.07), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
    }

    private func statusColor(_ status: String?) -> Color {
        switch status {
        case "active", "signed": return WhisperTheme.success
        case "expired", "cancelled": return WhisperTheme.danger
        default: return WhisperTheme.mutedInk
        }
    }

    @MainActor
    private func load() async {
        isLoading = true
        errorMessage = nil
        do {
            contracts = try await ClientNoteService.fetchContracts()
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
        isLoading = false
    }
}
