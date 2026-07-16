//
//  ProjectVercelView.swift
//  raCommand
//
//  Displays Vercel deployments and statuses for the active project.
//

import SwiftUI

struct ProjectVercelView: View {
    let project: Project

    @State private var deployments: [VercelDeployment] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var resolvedProjectName: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                headerSection

                if !KeychainService.hasVercelToken() {
                    unconfiguredEmptyState
                } else if isLoading && deployments.isEmpty {
                    loadingSpinner
                } else if let errorMessage {
                    errorPanel(errorMessage)
                } else if deployments.isEmpty {
                    emptyDeploymentsState
                } else {
                    deploymentsList
                }
            }
            .padding(24)
        }
        .task {
            await loadDeployments()
        }
    }

    private var headerSection: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 4) {
                Text("VERCEL DEPLOYMENTS")
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .foregroundStyle(Color(red: 0.541, green: 0.561, blue: 0.596))
                
                if let name = resolvedProjectName {
                    Text(name)
                        .font(.title3.weight(.bold))
                        .foregroundStyle(WhisperTheme.ink)
                } else {
                    Text("No Project Linked")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(WhisperTheme.mutedInk)
                }
            }

            Spacer()

            if KeychainService.hasVercelToken() && resolvedProjectName != nil {
                Button {
                    Task { await loadDeployments() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(isLoading ? WhisperTheme.mutedInk : WhisperTheme.accent)
                        .rotationEffect(.degrees(isLoading ? 360 : 0))
                        .animation(isLoading ? .linear(duration: 1).repeatForever(autoreverses: false) : .default, value: isLoading)
                }
                .buttonStyle(.plain)
                .disabled(isLoading)
            }
        }
    }

    private var unconfiguredEmptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "triangle.fill")
                .font(.system(size: 32))
                .foregroundStyle(WhisperTheme.warning)
            
            Text("Vercel token missing")
                .font(.headline)
                .foregroundStyle(WhisperTheme.ink)
            
            Text("Configure your Vercel Access Token in Settings > Sync to enable deployment tracking for your workspaces.")
                .font(.subheadline)
                .foregroundStyle(WhisperTheme.mutedInk)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 16)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
        .whisperPanel()
    }

    private var loadingSpinner: some View {
        HStack(spacing: 8) {
            ProgressView()
                .tint(WhisperTheme.accent)
            Text("Fetching deployments...")
                .font(.subheadline)
                .foregroundStyle(WhisperTheme.mutedInk)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 48)
    }

    private func errorPanel(_ message: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Failed to load deployments", systemImage: "exclamationmark.triangle.fill")
                .font(.headline)
                .foregroundStyle(WhisperTheme.danger)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(WhisperTheme.mutedInk)
        }
        .padding(16)
        .whisperPanel()
    }

    private var emptyDeploymentsState: some View {
        VStack(spacing: 12) {
            Image(systemName: "cloud.fill")
                .font(.system(size: 32))
                .foregroundStyle(WhisperTheme.mutedInk)
            Text("No deployments found")
                .font(.headline)
                .foregroundStyle(WhisperTheme.ink)
            Text("No deployments have been registered on Vercel for this project.")
                .font(.subheadline)
                .foregroundStyle(WhisperTheme.mutedInk)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
        .whisperPanel()
    }

    private var deploymentsList: some View {
        LazyVStack(spacing: 12) {
            ForEach(deployments) { deployment in
                deploymentCard(for: deployment)
            }
        }
    }

    private func deploymentCard(for deployment: VercelDeployment) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                HStack(spacing: 6) {
                    Circle()
                        .fill(stateColor(for: deployment.state))
                        .frame(width: 8, height: 8)
                    
                    Text(deployment.state.uppercased())
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .foregroundStyle(stateColor(for: deployment.state))
                    
                    if deployment.target == "production" {
                        Text("PRODUCTION")
                            .font(.system(size: 9, weight: .bold, design: .monospaced))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(WhisperTheme.success.opacity(0.12), in: Capsule())
                            .foregroundStyle(WhisperTheme.success)
                    }
                }

                Spacer()

                Text(timeAgo(from: deployment.createdDate))
                    .font(.caption2)
                    .foregroundStyle(WhisperTheme.mutedInk)
            }

            if let commit = deployment.meta?.githubCommitMessage {
                Text(commit)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(WhisperTheme.ink)
                    .lineLimit(2)
            }

            HStack(spacing: 14) {
                if let ref = deployment.meta?.githubCommitRef {
                    Label(ref, systemImage: "arrow.triangle.pull")
                        .font(.system(.caption2, design: .monospaced))
                        .foregroundStyle(WhisperTheme.mutedInk)
                }

                if let creator = deployment.creator?.username {
                    Label(creator, systemImage: "person.circle")
                        .font(.caption2)
                        .foregroundStyle(WhisperTheme.mutedInk)
                }
            }

            Divider()
                .background(Color.white.opacity(0.06))

            HStack {
                Text(deployment.url)
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundStyle(WhisperTheme.accent)
                    .lineLimit(1)
                    .truncationMode(.tail)
                
                Spacer()

                Button {
                    if let url = URL(string: "https://\(deployment.url)") {
                        PlatformSystemServices.open(url)
                    }
                } label: {
                    Label("Visit Site", systemImage: "arrow.up.forward.app")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(WhisperTheme.accent)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(14)
        .background(Color.white.opacity(0.03), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(Color.white.opacity(0.06), lineWidth: 1)
        )
    }

    private func loadDeployments() async {
        let name = VercelService.resolveVercelProjectName(
            vercelURL: project.vercelURL,
            repoURL: project.repoURL
        )
        resolvedProjectName = name
        
        guard let projectName = name else {
            return
        }

        isLoading = true
        errorMessage = nil
        
        do {
            deployments = try await VercelService.fetchDeployments(projectNameOrId: projectName)
        } catch {
            errorMessage = error.localizedDescription
        }
        
        isLoading = false
    }

    private func stateColor(for state: String) -> Color {
        switch state.uppercased() {
        case "READY":
            return WhisperTheme.success
        case "BUILDING":
            return WhisperTheme.warning
        case "ERROR":
            return WhisperTheme.danger
        default:
            return WhisperTheme.mutedInk
        }
    }

    private func timeAgo(from date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}
