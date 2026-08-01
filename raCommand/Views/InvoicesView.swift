//
//  InvoicesView.swift
//  raCommand
//
//  Read-only mirror of readyaimgo admin's per-client invoices.
//

import SwiftUI

private let invoiceColumns: [GridItem] = [
    GridItem(.flexible(minimum: 160), spacing: 12, alignment: .leading),
    GridItem(.fixed(110), spacing: 12, alignment: .leading),
    GridItem(.fixed(90), spacing: 12, alignment: .trailing),
    GridItem(.fixed(100), spacing: 12, alignment: .leading),
    GridItem(.fixed(90), spacing: 0, alignment: .trailing),
]

struct InvoicesView: View {
    @State private var invoices: [AdminInvoice] = []
    @State private var transactions: [AdminRetainerTransaction] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var searchText = ""

    private var filteredInvoices: [AdminInvoice] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return invoices }
        return invoices.filter { invoice in
            invoice.title.localizedCaseInsensitiveContains(query)
                || invoice.invoiceNumber.localizedCaseInsensitiveContains(query)
                || invoice.clientId.localizedCaseInsensitiveContains(query)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            header

            TextField("Search invoices…", text: $searchText)
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

            if isLoading && invoices.isEmpty && transactions.isEmpty {
                ProgressView()
                    .tint(WhisperTheme.accent)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 40)
            } else if filteredInvoices.isEmpty && transactions.isEmpty {
                WhisperEmptyState(
                    icon: "doc.text",
                    title: invoices.isEmpty ? "No invoices yet" : "No matches",
                    message: invoices.isEmpty
                        ? "Invoices created in the readyaimgo admin will show up here."
                        : "Try a different search term."
                )
            } else {
                table

                if !transactions.isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("RETAINER VAULT & LEDGER")
                            .font(.system(size: 11, weight: .bold, design: .monospaced))
                            .foregroundStyle(WhisperTheme.mutedInk)

                        VStack(spacing: 0) {
                            ForEach(transactions) { tx in
                                HStack(spacing: 12) {
                                    Text(tx.displayChannel)
                                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(tx.type == "deposit" ? WhisperTheme.success.opacity(0.15) : WhisperTheme.warning.opacity(0.15), in: RoundedRectangle(cornerRadius: 4))
                                        .foregroundStyle(tx.type == "deposit" ? WhisperTheme.success : WhisperTheme.warning)

                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(tx.displayPurpose)
                                            .font(.system(size: 12, weight: .medium))
                                            .foregroundStyle(WhisperTheme.ink)
                                        if let date = tx.createdAt {
                                            Text(String(date.prefix(10)))
                                                .font(.system(size: 10, design: .monospaced))
                                                .foregroundStyle(WhisperTheme.mutedInk)
                                        }
                                    }

                                    Spacer()

                                    VStack(alignment: .trailing, spacing: 2) {
                                        Text(tx.displayAmount)
                                            .font(.system(size: 12, weight: .bold, design: .monospaced))
                                            .foregroundStyle(tx.type == "deposit" ? WhisperTheme.success : WhisperTheme.warning)
                                        Text("Bal: \(tx.displayBalance)")
                                            .font(.system(size: 10, design: .monospaced))
                                            .foregroundStyle(WhisperTheme.mutedInk)
                                    }
                                }
                                .padding(.horizontal, 14)
                                .padding(.vertical, 10)
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
                    }
                    .padding(.top, 10)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .task { await load() }
    }

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Invoices & Retainer Ledger")
                    .font(.system(size: 24, weight: .bold))
                    .foregroundStyle(WhisperTheme.ink)
                Text(invoices.isEmpty ? "Billing tracked in readyaimgo admin" : "\(invoices.count) \(invoices.count == 1 ? "invoice" : "invoices") synced")
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
            LazyVGrid(columns: invoiceColumns, spacing: 12) {
                Text("TITLE").tableHeader()
                Text("WORKSPACE").tableHeader()
                Text("AMOUNT").tableHeader(alignment: .trailing)
                Text("DUE").tableHeader()
                Text("STATUS").tableHeader(alignment: .trailing)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 9)
            .background(Color.white.opacity(0.03))
            .overlay(alignment: .bottom) {
                Rectangle().fill(Color.white.opacity(0.06)).frame(height: 1)
            }

            ForEach(filteredInvoices) { invoice in
                LazyVGrid(columns: invoiceColumns, spacing: 12) {
                    Text(invoice.title)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(WhisperTheme.ink)
                        .lineLimit(1)

                    Text(invoice.workspaceId ?? "—")
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundStyle(WhisperTheme.mutedInk)
                        .lineLimit(1)

                    Text(invoice.displayAmount)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(WhisperTheme.ink)

                    Text(invoice.dueDate.prefix(10))
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundStyle(WhisperTheme.mutedInk)

                    Text(invoice.status.uppercased())
                        .font(.system(size: 10, weight: .semibold, design: .monospaced))
                        .padding(.horizontal, 8)
                        .frame(height: 20)
                        .background(statusColor(invoice.status).opacity(0.14), in: RoundedRectangle(cornerRadius: 5, style: .continuous))
                        .foregroundStyle(statusColor(invoice.status))
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

    private func statusColor(_ status: String) -> Color {
        switch status {
        case "paid": return WhisperTheme.success
        case "accepted", "client_review": return WhisperTheme.info
        case "cancelled": return WhisperTheme.danger
        default: return WhisperTheme.mutedInk
        }
    }

    @MainActor
    private func load() async {
        isLoading = true
        errorMessage = nil
        do {
            async let invTask = ClientNoteService.fetchInvoices()
            async let txTask = ClientNoteService.fetchRetainerLedger()
            let (invs, txs) = try await (invTask, txTask)
            invoices = invs
            transactions = txs
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
        isLoading = false
    }
}

extension Text {
    func tableHeader(alignment: Alignment = .leading) -> some View {
        self
            .font(.system(size: 10, weight: .semibold, design: .monospaced))
            .tracking(0.6)
            .foregroundStyle(WhisperTheme.mutedInk)
            .frame(maxWidth: .infinity, alignment: alignment)
    }
}
