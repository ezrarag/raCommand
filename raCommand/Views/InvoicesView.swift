//
//  InvoicesView.swift
//  raCommand
//
//  Interactive mirror and status controller for readyaimgo admin's client invoices.
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
    @State private var selectedInvoice: AdminInvoice?

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
        .sheet(item: $selectedInvoice) { invoice in
            InvoiceDetailSheet(invoice: invoice, onStatusChanged: {
                Task { await load() }
            })
        }
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
                    VStack(alignment: .leading, spacing: 2) {
                        Text(invoice.title)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(WhisperTheme.ink)
                            .lineLimit(1)
                        Text(invoice.invoiceNumber)
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(WhisperTheme.mutedInk)
                            .lineLimit(1)
                    }

                    Text(invoice.workspaceId ?? "—")
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundStyle(WhisperTheme.mutedInk)
                        .lineLimit(1)

                    Text(invoice.displayAmount)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(WhisperTheme.ink)

                    Text(String(invoice.dueDate.prefix(10)))
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
                .contentShape(Rectangle())
                .onTapGesture {
                    selectedInvoice = invoice
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

// MARK: - Invoice Detail Sheet

struct InvoiceDetailSheet: View {
    let invoice: AdminInvoice
    var onStatusChanged: (() -> Void)? = nil

    @Environment(\.dismiss) private var dismiss
    @State private var isUpdating = false
    @State private var alertMessage: String?
    @State private var isSuccess = false

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(invoice.invoiceNumber)
                        .font(.system(size: 20, weight: .bold, design: .monospaced))
                        .foregroundStyle(WhisperTheme.ink)
                    Text(invoice.title)
                        .font(.system(size: 13, weight: .medium))
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

            // Summary Grid
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 16) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("CLIENT ID")
                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                            .foregroundStyle(WhisperTheme.mutedInk)
                        Text(invoice.clientId)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(WhisperTheme.ink)
                    }

                    Spacer()

                    VStack(alignment: .trailing, spacing: 2) {
                        Text("AMOUNT")
                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                            .foregroundStyle(WhisperTheme.mutedInk)
                        Text(invoice.displayAmount)
                            .font(.system(size: 16, weight: .bold, design: .monospaced))
                            .foregroundStyle(WhisperTheme.accent)
                    }
                }

                HStack(spacing: 16) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("WORKSPACE")
                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                            .foregroundStyle(WhisperTheme.mutedInk)
                        Text(invoice.workspaceId ?? "—")
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundStyle(WhisperTheme.ink)
                    }

                    Spacer()

                    VStack(alignment: .trailing, spacing: 2) {
                        Text("DUE DATE")
                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                            .foregroundStyle(WhisperTheme.mutedInk)
                        Text(String(invoice.dueDate.prefix(10)))
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundStyle(WhisperTheme.ink)
                    }
                }
            }
            .padding(16)
            .background(WhisperTheme.panel, in: RoundedRectangle(cornerRadius: 10))

            Spacer()

            // Status Actions
            VStack(spacing: 10) {
                if invoice.status == "draft" {
                    Button {
                        updateStatus("client_review")
                    } label: {
                        HStack {
                            if isUpdating {
                                ProgressView().tint(.white).controlSize(.small)
                            } else {
                                Image(systemName: "paperplane.fill")
                            }
                            Text(isUpdating ? "Publishing..." : "Mark as Sent & Publish")
                                .font(.system(size: 13, weight: .semibold))
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 11)
                        .background(WhisperTheme.success, in: RoundedRectangle(cornerRadius: 9))
                        .foregroundStyle(.white)
                    }
                    .buttonStyle(.plain)
                    .disabled(isUpdating)
                }

                if invoice.status != "paid" {
                    Button {
                        updateStatus("paid")
                    } label: {
                        HStack {
                            if isUpdating {
                                ProgressView().tint(.white).controlSize(.small)
                            } else {
                                Image(systemName: "checkmark.seal.fill")
                            }
                            Text(isUpdating ? "Updating..." : "Mark as Paid")
                                .font(.system(size: 13, weight: .semibold))
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 11)
                        .background(WhisperTheme.accent, in: RoundedRectangle(cornerRadius: 9))
                        .foregroundStyle(.white)
                    }
                    .buttonStyle(.plain)
                    .disabled(isUpdating)
                }
            }
        }
        .padding(24)
        .frame(minWidth: 420, minHeight: 380)
        .background(WhisperTheme.background)
    }

    private func updateStatus(_ newStatus: String) {
        guard let contractId = invoice.workspaceId ?? invoice.clientId.components(separatedBy: "/").first else { return }
        Task {
            isUpdating = true
            alertMessage = nil
            do {
                _ = try await ClientNoteService.updateInvoiceStatus(contractId: contractId, invoiceId: invoice.id, status: newStatus)
                isSuccess = true
                alertMessage = "Invoice updated to \(newStatus)!"
                onStatusChanged?()
            } catch {
                isSuccess = false
                alertMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            }
            isUpdating = false
        }
    }
}
