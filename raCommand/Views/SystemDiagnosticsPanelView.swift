//
//  SystemDiagnosticsPanelView.swift
//  raCommand
//
//  Disk space + local-dev folder staleness, plus a live CPU/memory
//  snapshot. Everything here only samples while this panel is on screen —
//  no background timers, no launch agents.
//

import SwiftUI
import SwiftData
#if os(macOS)
import AppKit
#endif

private let lowDiskFreeFractionThreshold: Double = 0.15
private let staleFolderDayThreshold: Int = 30

struct SystemDiagnosticsPanelView: View {
    @Query private var projects: [Project]

    @State private var diskSummary: DiskSummary?
    @State private var folders: [LocalFolderUsage] = []
    @State private var isScanning = false
    @State private var lastScannedAt: Date?

    @State private var loadSnapshot: SystemLoadSnapshot?
    @State private var refreshTimer: Timer?
    #if os(macOS)
    private let sampler = SystemDiagnosticsService.LoadSampler()
    #endif

    private var isLowOnDisk: Bool {
        guard let diskSummary else { return false }
        return diskSummary.freeFraction < lowDiskFreeFractionThreshold
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            WhisperSectionTitle(
                eyebrow: "System",
                title: "Disk space & live load",
                detail: "Samples only while this panel is open — no background monitoring."
            )

            if isLowOnDisk, let diskSummary {
                lowDiskBanner(diskSummary)
            }

            diskBar

            loadRow

            HStack {
                Text("Local dev folders")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(WhisperTheme.ink)
                Spacer()
                if let lastScannedAt {
                    Text("Scanned \(lastScannedAt.formatted(date: .omitted, time: .shortened))")
                        .font(.caption2)
                        .foregroundStyle(WhisperTheme.mutedInk)
                }
                Button {
                    Task { await scan() }
                } label: {
                    if isScanning {
                        ProgressView().controlSize(.small)
                    } else {
                        Image(systemName: "arrow.clockwise")
                    }
                }
                .buttonStyle(.plain)
                .foregroundStyle(WhisperTheme.mutedInk)
                .disabled(isScanning)
            }

            if folders.isEmpty && !isScanning {
                WhisperEmptyState(
                    icon: "externaldrive",
                    title: "No scan yet",
                    message: "Scan \(LocalWorkspaceService.defaultWorkspaceRoot) to see which project folders are largest and staled out."
                )
            } else {
                VStack(spacing: 1) {
                    ForEach(folders.prefix(25)) { folder in
                        folderRow(folder)
                    }
                }
                .whisperPanel(padding: 8, radius: 10)
            }
        }
        .whisperPanel()
        .onAppear { startSampling() }
        .onDisappear { stopSampling() }
        .task {
            diskSummary = SystemDiagnosticsService.diskSummary()
            if folders.isEmpty {
                await scan()
            }
        }
    }

    private func lowDiskBanner(_ summary: DiskSummary) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(WhisperTheme.warning)
            VStack(alignment: .leading, spacing: 2) {
                Text("Only \(SystemDiagnosticsService.formatBytes(summary.freeBytes)) free")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(WhisperTheme.ink)
                Text("Review the folders below — anything untouched for \(staleFolderDayThreshold)+ days is a good candidate to push and remove locally from the Repos tab.")
                    .font(.caption)
                    .foregroundStyle(WhisperTheme.mutedInk)
            }
        }
        .padding(12)
        .background(WhisperTheme.warning.opacity(0.1), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(WhisperTheme.warning.opacity(0.3), lineWidth: 1)
        )
    }

    private var diskBar: some View {
        VStack(alignment: .leading, spacing: 6) {
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .fill(WhisperTheme.input)
                    if let diskSummary {
                        RoundedRectangle(cornerRadius: 5, style: .continuous)
                            .fill(isLowOnDisk ? WhisperTheme.danger : WhisperTheme.accent)
                            .frame(width: geometry.size.width * (1 - diskSummary.freeFraction))
                    }
                }
            }
            .frame(height: 10)

            if let diskSummary {
                Text("\(SystemDiagnosticsService.formatBytes(diskSummary.usedBytes)) used of \(SystemDiagnosticsService.formatBytes(diskSummary.totalBytes)) — \(SystemDiagnosticsService.formatBytes(diskSummary.freeBytes)) free")
                    .font(.caption)
                    .foregroundStyle(WhisperTheme.mutedInk)
            } else {
                Text("Disk usage unavailable")
                    .font(.caption)
                    .foregroundStyle(WhisperTheme.mutedInk)
            }
        }
    }

    private var loadRow: some View {
        HStack(spacing: 20) {
            loadMetric(
                label: "CPU",
                valueText: loadSnapshot?.cpuUsagePercent.map { String(format: "%.0f%%", $0) } ?? "—",
                fraction: (loadSnapshot?.cpuUsagePercent ?? 0) / 100
            )
            loadMetric(
                label: "Memory",
                valueText: loadSnapshot.map { "\(SystemDiagnosticsService.formatBytes($0.usedMemoryBytes)) / \(SystemDiagnosticsService.formatBytes($0.totalMemoryBytes))" } ?? "—",
                fraction: loadSnapshot?.memoryFraction ?? 0
            )
        }
    }

    private func loadMetric(label: String, valueText: String, fraction: Double) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label.uppercased())
                .font(.caption2.weight(.semibold))
                .foregroundStyle(WhisperTheme.mutedInk)
            Text(valueText)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(WhisperTheme.ink)
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .fill(WhisperTheme.input)
                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .fill(WhisperTheme.info)
                        .frame(width: geometry.size.width * max(0, min(1, fraction)))
                }
            }
            .frame(width: 110, height: 6)
        }
    }

    private func folderRow(_ folder: LocalFolderUsage) -> some View {
        HStack(alignment: .center, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(folder.name)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(WhisperTheme.ink)
                Text(staleLabel(for: folder))
                    .font(.caption2)
                    .foregroundStyle(staleColor(for: folder))
            }

            Spacer(minLength: 8)

            Text(SystemDiagnosticsService.formatBytes(folder.sizeBytes))
                .font(.caption.weight(.medium))
                .foregroundStyle(WhisperTheme.mutedInk)

            Button {
                revealInFinder(folder.path)
            } label: {
                Image(systemName: "arrow.up.forward.square")
                    .foregroundStyle(WhisperTheme.mutedInk)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
    }

    private func matchedProject(for folder: LocalFolderUsage) -> Project? {
        let target = LocalWorkspaceService.normalizedWorkspacePath(folder.path)
        guard !target.isEmpty else { return nil }
        return projects.first { LocalWorkspaceService.normalizedWorkspacePath($0.localPath) == target }
    }

    private func daysSinceActivity(for folder: LocalFolderUsage) -> Int? {
        guard let project = matchedProject(for: folder) else { return nil }
        let reference = max(project.lastReviewed, project.lastUpdated)
        return Calendar.current.dateComponents([.day], from: reference, to: Date()).day
    }

    private func staleLabel(for folder: LocalFolderUsage) -> String {
        guard let days = daysSinceActivity(for: folder) else { return "Not tracked as a project" }
        if days <= 0 { return "Touched today" }
        return "Last touched \(days) day\(days == 1 ? "" : "s") ago"
    }

    private func staleColor(for folder: LocalFolderUsage) -> Color {
        guard let days = daysSinceActivity(for: folder) else { return WhisperTheme.mutedInk }
        return days >= staleFolderDayThreshold ? WhisperTheme.warning : WhisperTheme.mutedInk
    }

    private func revealInFinder(_ path: String) {
        #if os(macOS)
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
        #endif
    }

    @MainActor
    private func scan() async {
        isScanning = true
        folders = await SystemDiagnosticsService.scanLocalDevFolders(root: LocalWorkspaceService.defaultWorkspaceRoot)
        lastScannedAt = Date()
        isScanning = false
    }

    private func startSampling() {
        #if os(macOS)
        loadSnapshot = sampler.sample()
        refreshTimer?.invalidate()
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { _ in
            Task { @MainActor in
                loadSnapshot = sampler.sample()
            }
        }
        #endif
    }

    private func stopSampling() {
        refreshTimer?.invalidate()
        refreshTimer = nil
    }
}
