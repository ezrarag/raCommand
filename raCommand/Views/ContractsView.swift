//
//  ContractsView.swift
//  raCommand
//
//  Interactive mirror and management surface for readyaimgo admin contracts & milestone invoicing.
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
    @State private var selectedContract: AdminContract?

    private var filteredContracts: [AdminContract] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return contracts }
        return contracts.filter { contract in
            contract.displayTitle.localizedCaseInsensitiveContains(query)
                || (contract.clientId ?? "").localizedCaseInsensitiveContains(query)
                || (contract.clientName ?? "").localizedCaseInsensitiveContains(query)
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
        .sheet(item: $selectedContract) { contract in
            ContractDetailSheet(contract: contract, onInvoiceGenerated: {
                Task { await load() }
            })
        }
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
                        Image(systemName: contract.fileUrl != nil || contract.documentUrl != nil ? "doc.fill" : "doc")
                            .font(.system(size: 11))
                            .foregroundStyle(WhisperTheme.accent)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(contract.displayTitle)
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(WhisperTheme.ink)
                                .lineLimit(1)
                            if let clientName = contract.clientName, !clientName.isEmpty {
                                Text(clientName)
                                    .font(.system(size: 10))
                                    .foregroundStyle(WhisperTheme.mutedInk)
                                    .lineLimit(1)
                            }
                        }
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
                .contentShape(Rectangle())
                .onTapGesture {
                    selectedContract = contract
                }
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

// MARK: - Contract Detail & Invoicing Sheet

struct ContractDetailSheet: View {
    let contract: AdminContract
    var onInvoiceGenerated: (() -> Void)? = nil

    @Environment(\.dismiss) private var dismiss
    @State private var isGenerating = false
    @State private var alertMessage: String?
    @State private var isSuccess = false

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(contract.displayTitle)
                        .font(.system(size: 20, weight: .bold))
                        .foregroundStyle(WhisperTheme.ink)
                    Text(contract.displayType)
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(WhisperTheme.mutedInk)
                }

                Spacer()

                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 18))
                        .foregroundStyle(WhisperTheme.mutedInk)
                }
                .buttonStyle(.plain)
            }

            if let alertMessage {
                HStack {
                    Image(systemName: isSuccess ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                        .foregroundStyle(isSuccess ? WhisperTheme.success : WhisperTheme.danger)
                    Text(alertMessage)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(isSuccess ? WhisperTheme.success : WhisperTheme.danger)
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background((isSuccess ? WhisperTheme.success : WhisperTheme.danger).opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
            }

            // Summary / Client info
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 16) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("CLIENT")
                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                            .foregroundStyle(WhisperTheme.mutedInk)
                        Text(contract.clientName ?? contract.clientId ?? "—")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(WhisperTheme.ink)
                    }

                    Spacer()

                    VStack(alignment: .trailing, spacing: 2) {
                        Text("TOTAL VALUE")
                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                            .foregroundStyle(WhisperTheme.mutedInk)
                        Text(contract.displayTotalValue)
                            .font(.system(size: 14, weight: .bold, design: .monospaced))
                            .foregroundStyle(WhisperTheme.accent)
                    }
                }

                if let email = contract.clientEmail, !email.isEmpty {
                    Text(email)
                        .font(.system(size: 12))
                        .foregroundStyle(WhisperTheme.mutedInk)
                }

                if let summary = contract.summary, !summary.isEmpty {
                    Text(summary)
                        .font(.system(size: 13))
                        .foregroundStyle(WhisperTheme.ink)
                        .padding(12)
                        .background(WhisperTheme.panel, in: RoundedRectangle(cornerRadius: 8))
                }
            }

            // Milestones Section
            if let dates = contract.paymentDates, !dates.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    Text("CONTRACT MILESTONES")
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .foregroundStyle(WhisperTheme.mutedInk)

                    VStack(spacing: 0) {
                        ForEach(Array(dates.enumerated()), id: \.offset) { index, dateLabel in
                            HStack {
                                Text("\(index + 1). \(dateLabel)")
                                    .font(.system(size: 13, weight: .medium))
                                    .foregroundStyle(WhisperTheme.ink)

                                Spacer()

                                if let amounts = contract.milestoneAmountsCents, index < amounts.count {
                                    Text(String(format: "$%.2f", Double(amounts[index]) / 100.0))
                                        .font(.system(size: 12, weight: .semibold, design: .monospaced))
                                        .foregroundStyle(WhisperTheme.ink)
                                }
                            }
                            .padding(.horizontal, 14)
                            .padding(.vertical, 10)
                            .overlay(alignment: .bottom) {
                                Rectangle().fill(Color.white.opacity(0.04)).frame(height: 1)
                            }
                        }
                    }
                    .background(WhisperTheme.panel, in: RoundedRectangle(cornerRadius: 9))
                }
            }

            Spacer()

            // Invoicing Action
            Button {
                Task {
                    isGenerating = true
                    alertMessage = nil
                    do {
                        let invoice = try await ClientNoteService.generateNextInvoice(contractId: contract.id)
                        isSuccess = true
                        alertMessage = "Generated Invoice \(invoice.invoiceNumber) for \(invoice.title)!"
                        onInvoiceGenerated?()
                    } catch {
                        isSuccess = false
                        alertMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                    }
                    isGenerating = false
                }
            } label: {
                HStack {
                    if isGenerating {
                        ProgressView()
                            .tint(.white)
                            .controlSize(.small)
                    } else {
                        Image(systemName: "plus.circle.fill")
                    }
                    Text(isGenerating ? "Generating Invoice..." : "Generate Next Invoice")
                        .font(.system(size: 14, weight: .semibold))
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(WhisperTheme.accent, in: RoundedRectangle(cornerRadius: 10))
                .foregroundStyle(.white)
            }
            .buttonStyle(.plain)
            .disabled(isGenerating)
        }
        .padding(24)
        .frame(minWidth: 460, minHeight: 480)
        .background(WhisperTheme.background)
    }
}
