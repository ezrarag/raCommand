//
//  ProjectPeopleView.swift
//  raCommand
//
//  Two sections:
//  1. GitHub Collaborators — invite/remove developers on the repo
//  2. Client Portal — provision portal access, send RAG notes, copy feedback link
//

import SwiftUI

// MARK: - Main View

struct ProjectPeopleView: View {
    let project: Project

    // GitHub state
    @State private var collaborators: [GitHubCollaborator] = []
    @State private var invitations: [GitHubInvitation] = []
    @State private var ghLoading = false

    // Client Portal state
    @State private var showAddClientSheet = false
    @State private var showRagNoteSheet = false
    @State private var ragNoteClientEmail = ""
    @State private var portalLoading = false

    // Shared feedback
    @State private var successMessage: String?
    @State private var errorMessage: String?
    @State private var showInviteSheet = false
    @State private var removingLogin: String?
    @State private var cancellingInviteID: Int?

    private var token: String? { KeychainService.loadGitHubToken() }
    private var hasRepo: Bool { !project.repoURL.isEmpty }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 18) {

                // ── Header ────────────────────────────────────────────
                VStack(alignment: .leading, spacing: 8) {
                    Text("PEOPLE")
                        .font(.caption2.weight(.bold))
                        .tracking(1.4)
                        .foregroundStyle(WhisperTheme.accent)
                    Text("Who's working on \(project.name.isEmpty ? "this project" : project.name)")
                        .font(.system(.title2, design: .rounded).weight(.bold))
                        .foregroundStyle(WhisperTheme.ink)
                    Text("GitHub collaborators and client portal access.")
                        .font(.subheadline)
                        .foregroundStyle(WhisperTheme.mutedInk)
                }
                .whisperPanel(padding: 20, radius: 28)

                // ── Feedback banners ──────────────────────────────────
                if let msg = successMessage { banner(msg, isError: false) }
                if let msg = errorMessage   { banner(msg, isError: true)  }

                // ── Section 1: GitHub Collaborators ───────────────────
                githubSection

                // ── Section 2: Client Portal ──────────────────────────
                clientPortalSection
            }
            .padding(.horizontal, 20)
            .padding(.top, 14)
            .padding(.bottom, 40)
        }
        .whisperShell()
        .navigationTitle("People")
        .platformNavigationTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .platformNavigationTrailing) {
                if ghLoading || portalLoading {
                    ProgressView().tint(WhisperTheme.accent)
                } else {
                    Button { Task { await loadAll() } } label: {
                        Image(systemName: "arrow.clockwise").foregroundStyle(WhisperTheme.accent)
                    }
                }
            }
        }
        .sheet(isPresented: $showInviteSheet) {
            InviteCollaboratorSheet(repoURL: project.repoURL) { username, permission in
                await invite(username: username, permission: permission)
            }
        }
        .sheet(isPresented: $showAddClientSheet) {
            AddClientToPortalSheet(project: project) { portalURL in
                showSuccess("Signup link ready — copy it below")
                PlatformSystemServices.copyToPasteboard(portalURL)
                showSuccess("Signup link copied to clipboard!")
            }
        }
        .sheet(isPresented: $showRagNoteSheet) {
            SendRagNoteSheet(
                clientEmail: ragNoteClientEmail,
                projectName: project.name
            ) {
                showSuccess("Note sent to client portal")
            }
        }
        .task { await loadAll() }
    }

    // MARK: - GitHub Section

    private var githubSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            WhisperSectionTitle(
                eyebrow: "Developers",
                title: "GitHub collaborators",
                detail: hasRepo ? "\(collaborators.count) active · \(invitations.count) pending" : nil
            )

            if !hasRepo {
                HStack(spacing: 10) {
                    Image(systemName: "link.badge.plus").foregroundStyle(WhisperTheme.mutedInk)
                    Text("Add a repo URL in the Links section to manage collaborators.")
                        .font(.subheadline).foregroundStyle(WhisperTheme.mutedInk)
                }
                .whisperInsetField()
            } else {
                if ghLoading && collaborators.isEmpty {
                    HStack {
                        ProgressView().tint(WhisperTheme.accent)
                        Text("Loading…").font(.subheadline).foregroundStyle(WhisperTheme.mutedInk)
                    }
                    .whisperInsetField()
                } else if collaborators.isEmpty {
                    HStack(spacing: 10) {
                        Image(systemName: "person.slash").foregroundStyle(WhisperTheme.mutedInk)
                        Text("No collaborators yet.").font(.subheadline).foregroundStyle(WhisperTheme.mutedInk)
                    }
                    .whisperInsetField()
                } else {
                    VStack(spacing: 8) {
                        ForEach(collaborators) { c in
                            CollaboratorRow(collaborator: c, isRemoving: removingLogin == c.login) {
                                Task { await remove(login: c.login) }
                            }
                        }
                    }
                }

                if !invitations.isEmpty {
                    VStack(spacing: 8) {
                        ForEach(invitations) { inv in
                            InvitationRow(invitation: inv, isCancelling: cancellingInviteID == inv.id) {
                                Task { await cancelInvite(id: inv.id) }
                            }
                        }
                    }
                }

                // Invite button
                actionButton(
                    icon: "person.badge.plus",
                    title: "Invite a GitHub collaborator",
                    subtitle: "Give read, write, or admin access to this repo.",
                    color: WhisperTheme.accent
                ) { showInviteSheet = true }

                // Role legend
                roleLegend
            }
        }
        .whisperPanel()
    }

    // MARK: - Client Portal Section

    private var clientPortalSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            WhisperSectionTitle(
                eyebrow: "Clients",
                title: "Client portal access",
                detail: "Provision a signup link so a client can join their portal workspace without needing a GitHub account."
            )

            // Feedback link for this project
            let feedbackLink = ClientNoteService.feedbackURL(
                for: project.clientFeedbackProjectId
            )
            VStack(alignment: .leading, spacing: 6) {
                Text("FEEDBACK LINK")
                    .font(.caption2.weight(.bold))
                    .tracking(0.9)
                    .foregroundStyle(WhisperTheme.mutedInk)
                HStack(spacing: 8) {
                    Text(feedbackLink)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(WhisperTheme.mutedInk)
                        .lineLimit(1)
                    Spacer()
                    Button {
                        PlatformSystemServices.copyToPasteboard(feedbackLink)
                        showSuccess("Feedback link copied")
                    } label: {
                        Image(systemName: "doc.on.doc")
                            .foregroundStyle(WhisperTheme.accent)
                    }
                    .buttonStyle(.plain)
                }
                .whisperInsetField()
                Text("Share this link with your client so they can leave notes, Loom videos, or annotate their site with the extension.")
                    .font(.caption)
                    .foregroundStyle(WhisperTheme.mutedInk)
            }

            // Add client to portal
            actionButton(
                icon: "person.crop.circle.badge.plus",
                title: "Add client to portal",
                subtitle: "Enter their details and a signup link will be generated — they create their own password.",
                color: WhisperTheme.success
            ) { showAddClientSheet = true }

            // Send RAG note directly
            actionButton(
                icon: "bubble.left.and.bubble.right.fill",
                title: "Send a note to a client",
                subtitle: "Pulse summary, project update, or general message — appears in their dashboard.",
                color: WhisperTheme.info
            ) {
                ragNoteClientEmail = project.clientName   // pre-fill if available
                showRagNoteSheet = true
            }

            // Open admin impersonation
            if let adminURL = URL(string: "https://clients.readyaimgo.biz/admin/impersonate") {
                actionButton(
                    icon: "eye.fill",
                    title: "View client dashboard (admin)",
                    subtitle: "Opens the impersonation panel on clients.readyaimgo.biz.",
                    color: WhisperTheme.warning
                ) { PlatformSystemServices.open(adminURL) }
            }
        }
        .whisperPanel()
    }

    // MARK: - Helpers

    private var roleLegend: some View {
        VStack(spacing: 6) {
            ForEach(CollaboratorPermission.allCases) { perm in
                HStack(spacing: 10) {
                    Text(perm.label)
                        .font(.caption.weight(.bold))
                        .foregroundStyle(permColor(perm))
                        .frame(width: 44, alignment: .leading)
                    Text(perm.description)
                        .font(.caption)
                        .foregroundStyle(WhisperTheme.mutedInk)
                    Spacer()
                }
            }
        }
        .padding(.top, 4)
    }

    private func banner(_ msg: String, isError: Bool) -> some View {
        HStack(spacing: 10) {
            Image(systemName: isError ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                .foregroundStyle(isError ? WhisperTheme.danger : WhisperTheme.success)
            Text(msg).font(.subheadline.weight(.medium))
                .foregroundStyle(isError ? WhisperTheme.danger : WhisperTheme.success)
            Spacer()
        }
        .padding(14)
        .background((isError ? WhisperTheme.danger : WhisperTheme.success).opacity(0.08),
                    in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous)
            .stroke((isError ? WhisperTheme.danger : WhisperTheme.success).opacity(0.22), lineWidth: 1))
    }

    private func actionButton(icon: String, title: String, subtitle: String, color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                ZStack {
                    Circle().fill(color.opacity(0.12)).frame(width: 40, height: 40)
                    Image(systemName: icon).font(.system(size: 16, weight: .semibold)).foregroundStyle(color)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.subheadline.weight(.semibold)).foregroundStyle(WhisperTheme.ink)
                    Text(subtitle).font(.caption).foregroundStyle(WhisperTheme.mutedInk)
                }
                Spacer()
                Image(systemName: "arrow.up.right").font(.footnote.weight(.bold)).foregroundStyle(WhisperTheme.mutedInk)
            }
            .padding(16)
            .background(WhisperTheme.input, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(WhisperTheme.border, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    private func permColor(_ p: CollaboratorPermission) -> Color {
        switch p {
        case .read:  return WhisperTheme.info
        case .write: return WhisperTheme.accent
        case .admin: return WhisperTheme.danger
        }
    }

    // MARK: - Data

    private func loadAll() async {
        await loadGitHub()
    }

    private func loadGitHub() async {
        guard hasRepo, let token else { return }
        ghLoading = true
        do {
            async let c = GitHubCollaboratorsService.fetchCollaborators(repoURL: project.repoURL, token: token)
            async let i = GitHubCollaboratorsService.fetchInvitations(repoURL: project.repoURL, token: token)
            let (collabs, invites) = try await (c, i)
            collaborators = collabs
            invitations = invites
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            clearError()
        }
        ghLoading = false
    }

    private func invite(username: String, permission: CollaboratorPermission) async {
        guard let token else { return }
        do {
            try await GitHubCollaboratorsService.invite(username: username, permission: permission, repoURL: project.repoURL, token: token)
            showSuccess("Invitation sent to @\(username)")
            await loadGitHub()
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            clearError()
        }
    }

    private func remove(login: String) async {
        guard let token else { return }
        removingLogin = login
        do {
            try await GitHubCollaboratorsService.remove(username: login, repoURL: project.repoURL, token: token)
            showSuccess("@\(login) removed")
            await loadGitHub()
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            clearError()
        }
        removingLogin = nil
    }

    private func cancelInvite(id: Int) async {
        guard let token else { return }
        cancellingInviteID = id
        do {
            try await GitHubCollaboratorsService.cancelInvitation(id: id, repoURL: project.repoURL, token: token)
            showSuccess("Invitation cancelled")
            await loadGitHub()
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            clearError()
        }
        cancellingInviteID = nil
    }

    private func showSuccess(_ msg: String) {
        successMessage = msg
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) { successMessage = nil }
    }

    private func clearError() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 4) { errorMessage = nil }
    }
}

// MARK: - Add Client to Portal Sheet

struct AddClientToPortalSheet: View {
    @Environment(\.dismiss) private var dismiss
    let project: Project
    let onSuccess: (String) -> Void

    @State private var fullName = ""
    @State private var email = ""
    @State private var companyName = ""
    @State private var phone = ""
    @State private var role = ""
    @State private var orgType = ""
    @State private var notes = ""
    @State private var selectedServices: Set<String> = []
    @State private var isProvisioning = false
    @State private var errorMessage: String?
    @State private var generatedURL: String?

    private let serviceOptions = [
        ("web", "Web presence"),
        ("app", "Apps & portals"),
        ("transportation", "Transportation"),
        ("housing", "Housing support"),
        ("rd", "Research & development"),
        ("insurance", "Insurance"),
        ("property-ops", "Property ops"),
        ("beam-participants", "BEAM participants"),
    ]

    private let orgTypes = [
        "Transportation", "Property operations", "Retail",
        "Hospitality", "Professional services", "Community organization",
        "Real estate", "Construction", "Other"
    ]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {

                    // Header
                    VStack(alignment: .leading, spacing: 8) {
                        WhisperSectionTitle(
                            eyebrow: "Client portal",
                            title: "Add client to portal",
                            detail: "We'll generate a signup link. They create their own password — you never set it for them."
                        )
                    }
                    .whisperPanel()

                    // Success state — show generated URL
                    if let url = generatedURL {
                        VStack(alignment: .leading, spacing: 12) {
                            WhisperSectionTitle(eyebrow: "Ready", title: "Signup link generated", detail: nil)
                            Text("Send this link to \(fullName.isEmpty ? "the client" : fullName). It expires in 7 days.")
                                .font(.subheadline)
                                .foregroundStyle(WhisperTheme.mutedInk)

                            Text(url)
                                .font(.system(.caption, design: .monospaced))
                                .foregroundStyle(WhisperTheme.ink)
                                .padding(12)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(WhisperTheme.input, in: RoundedRectangle(cornerRadius: 14, style: .continuous))

                            HStack(spacing: 10) {
                                Button {
                                    PlatformSystemServices.copyToPasteboard(url)
                                } label: {
                                    Label("Copy link", systemImage: "doc.on.doc")
                                        .font(.subheadline.weight(.semibold))
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, 12)
                                        .background(WhisperTheme.accent, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                                        .foregroundStyle(.white)
                                }
                                .buttonStyle(.plain)

                                Button {
                                    if let openURL = URL(string: url) {
                                        PlatformSystemServices.open(openURL)
                                    }
                                } label: {
                                    Label("Open", systemImage: "arrow.up.right")
                                        .font(.subheadline.weight(.semibold))
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, 12)
                                        .background(WhisperTheme.info.opacity(0.15), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                                        .foregroundStyle(WhisperTheme.info)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .whisperPanel()

                        Button("Done") { onSuccess(url); dismiss() }
                            .font(.subheadline.weight(.semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(WhisperTheme.success, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                            .foregroundStyle(.white)
                            .buttonStyle(.plain)

                    } else {
                        // Form
                        formPanel
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 16)
            }
            .whisperShell()
            .navigationTitle("Add Client")
            .platformNavigationTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }

    private var formPanel: some View {
        VStack(spacing: 16) {

            // Contact info
            VStack(alignment: .leading, spacing: 12) {
                WhisperSectionTitle(eyebrow: "Contact", title: "Client details", detail: nil)

                field("Full name") {
                    TextField("Jane Smith", text: $fullName)
                        .platformDisableTextInputAutocapitalization()
                }
                field("Email") {
                    TextField("jane@company.com", text: $email)
                        .platformDisableTextInputAutocapitalization()
                }
                field("Company") {
                    TextField(project.clientName.isEmpty ? "Company name" : project.clientName, text: $companyName)
                }
                field("Phone (optional)") {
                    TextField("+1 (312) 555-0199", text: $phone)
                }
                field("Role (optional)") {
                    TextField("Founder, director, owner…", text: $role)
                }
            }
            .whisperPanel()

            // Org type
            VStack(alignment: .leading, spacing: 12) {
                WhisperSectionTitle(eyebrow: "Type", title: "Organization type", detail: nil)
                Menu {
                    ForEach(orgTypes, id: \.self) { t in
                        Button(t) { orgType = t }
                    }
                } label: {
                    HStack {
                        Text(orgType.isEmpty ? "Select…" : orgType)
                            .foregroundStyle(orgType.isEmpty ? WhisperTheme.mutedInk : WhisperTheme.ink)
                        Spacer()
                        Image(systemName: "chevron.up.chevron.down")
                            .foregroundStyle(WhisperTheme.mutedInk)
                    }
                    .whisperInsetField()
                }
                .buttonStyle(.plain)
            }
            .whisperPanel()

            // Service interests
            VStack(alignment: .leading, spacing: 12) {
                WhisperSectionTitle(eyebrow: "Services", title: "What they need", detail: "Pre-selects relevant sections in their portal.")
                VStack(spacing: 6) {
                    ForEach(serviceOptions, id: \.0) { id, label in
                        Button {
                            if selectedServices.contains(id) { selectedServices.remove(id) }
                            else { selectedServices.insert(id) }
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: selectedServices.contains(id) ? "checkmark.circle.fill" : "circle")
                                    .foregroundStyle(selectedServices.contains(id) ? WhisperTheme.accent : WhisperTheme.mutedInk)
                                Text(label).font(.subheadline).foregroundStyle(WhisperTheme.ink)
                                Spacer()
                            }
                            .padding(12)
                            .background(
                                selectedServices.contains(id) ? WhisperTheme.accent.opacity(0.07) : WhisperTheme.input,
                                in: RoundedRectangle(cornerRadius: 12, style: .continuous)
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .whisperPanel()

            // Notes
            VStack(alignment: .leading, spacing: 10) {
                WhisperSectionTitle(eyebrow: "Context", title: "Notes (optional)", detail: nil)
                TextEditor(text: $notes)
                    .frame(minHeight: 80)
                    .scrollContentBackground(.hidden)
                    .padding(12)
                    .background(WhisperTheme.input, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
            .whisperPanel()

            // Error
            if let err = errorMessage {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(WhisperTheme.danger)
                    Text(err).font(.subheadline).foregroundStyle(WhisperTheme.danger)
                }
                .padding(14)
                .background(WhisperTheme.danger.opacity(0.08), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            }

            // Submit
            Button {
                Task { await provision() }
            } label: {
                HStack(spacing: 8) {
                    if isProvisioning { ProgressView().tint(.white).scaleEffect(0.85) }
                    else { Image(systemName: "link.badge.plus") }
                    Text(isProvisioning ? "Generating link…" : "Generate Signup Link")
                        .fontWeight(.semibold)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(
                    email.contains("@") && !fullName.isEmpty
                        ? WhisperTheme.accent
                        : WhisperTheme.mutedInk.opacity(0.3),
                    in: RoundedRectangle(cornerRadius: 16, style: .continuous)
                )
                .foregroundStyle(.white)
            }
            .buttonStyle(.plain)
            .disabled(isProvisioning || !email.contains("@") || fullName.isEmpty)
        }
    }

    private func field<Content: View>(_ label: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label.uppercased())
                .font(.caption2.weight(.bold))
                .tracking(0.9)
                .foregroundStyle(WhisperTheme.mutedInk)
            content()
                .font(.subheadline)
                .autocorrectionDisabled()
                .whisperInsetField()
        }
    }

    private func provision() async {
        isProvisioning = true
        errorMessage = nil

        // Pre-fill company from project if blank
        let company = companyName.isEmpty ? project.clientName : companyName

        let input = ClientProvisionInput(
            fullName: fullName,
            email: email,
            companyName: company,
            phone: phone,
            role: role,
            organizationType: orgType,
            serviceInterests: Array(selectedServices),
            notes: notes,
            projectName: project.name,
            repoURL: project.repoURL
        )

        do {
            let url = try await ClientNoteService.provisionClientPortalAccess(input: input)
            generatedURL = url
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }

        isProvisioning = false
    }
}

// MARK: - Send RAG Note Sheet

struct SendRagNoteSheet: View {
    @Environment(\.dismiss) private var dismiss
    let clientEmail: String
    let projectName: String
    let onSuccess: () -> Void

    @State private var email = ""
    @State private var subject = ""
    @State private var messageBody = ""
    @State private var noteType = "note"
    @State private var isSending = false
    @State private var errorMessage: String?

    private let types: [(String, String)] = [
        ("note", "Team note"),
        ("pulse", "Pulse summary"),
        ("update", "Project update"),
    ]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    VStack(alignment: .leading, spacing: 8) {
                        WhisperSectionTitle(
                            eyebrow: "RAG notes",
                            title: "Send to client portal",
                            detail: "This message appears in the client's dashboard under 'From your Readyaimgo team.'"
                        )
                    }
                    .whisperPanel()

                    VStack(alignment: .leading, spacing: 14) {
                        // Client email
                        VStack(alignment: .leading, spacing: 6) {
                            Text("CLIENT EMAIL")
                                .font(.caption2.weight(.bold)).tracking(0.9)
                                .foregroundStyle(WhisperTheme.mutedInk)
                            TextField("client@email.com", text: $email)
                                .platformDisableTextInputAutocapitalization()
                                .autocorrectionDisabled()
                                .whisperInsetField()
                        }

                        // Note type
                        VStack(alignment: .leading, spacing: 8) {
                            Text("TYPE")
                                .font(.caption2.weight(.bold)).tracking(0.9)
                                .foregroundStyle(WhisperTheme.mutedInk)
                            HStack(spacing: 8) {
                                ForEach(types, id: \.0) { id, label in
                                    Button { noteType = id } label: {
                                        Text(label)
                                            .font(.caption.weight(.semibold))
                                            .padding(.horizontal, 12).padding(.vertical, 7)
                                            .background(
                                                noteType == id ? WhisperTheme.accent : WhisperTheme.input,
                                                in: Capsule()
                                            )
                                            .foregroundStyle(noteType == id ? .white : WhisperTheme.mutedInk)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }

                        // Subject
                        VStack(alignment: .leading, spacing: 6) {
                            Text("SUBJECT")
                                .font(.caption2.weight(.bold)).tracking(0.9)
                                .foregroundStyle(WhisperTheme.mutedInk)
                            TextField(
                                noteType == "pulse" ? "Weekly pulse — \(projectName)" : "Update on \(projectName)",
                                text: $subject
                            )
                            .whisperInsetField()
                        }

                        // Body
                        VStack(alignment: .leading, spacing: 6) {
                            Text("MESSAGE")
                                .font(.caption2.weight(.bold)).tracking(0.9)
                                .foregroundStyle(WhisperTheme.mutedInk)
                            TextEditor(text: $messageBody)
                                .frame(minHeight: 120)
                                .scrollContentBackground(.hidden)
                                .padding(12)
                                .background(WhisperTheme.input, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                        }
                    }
                    .whisperPanel()

                    if let err = errorMessage {
                        HStack(spacing: 8) {
                            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(WhisperTheme.danger)
                            Text(err).font(.subheadline).foregroundStyle(WhisperTheme.danger)
                        }
                        .padding(14)
                        .background(WhisperTheme.danger.opacity(0.08), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }

                    Button {
                        Task { await send() }
                    } label: {
                        HStack(spacing: 8) {
                            if isSending { ProgressView().tint(.white).scaleEffect(0.85) }
                            else { Image(systemName: "paperplane.fill") }
                            Text(isSending ? "Sending…" : "Send Note")
                                .fontWeight(.semibold)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(
                            canSend ? WhisperTheme.accent : WhisperTheme.mutedInk.opacity(0.3),
                            in: RoundedRectangle(cornerRadius: 16, style: .continuous)
                        )
                        .foregroundStyle(.white)
                    }
                    .buttonStyle(.plain)
                    .disabled(!canSend || isSending)
                }
                .padding(.horizontal, 20).padding(.vertical, 16)
            }
            .whisperShell()
            .navigationTitle("Send Note")
            .platformNavigationTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .onAppear {
                if !clientEmail.isEmpty { email = clientEmail }
            }
        }
    }

    private var canSend: Bool {
        email.contains("@") && !subject.isEmpty && !messageBody.isEmpty
    }

    private func send() async {
        isSending = true
        errorMessage = nil
        do {
            try await ClientNoteService.sendRagNote(
                clientEmail: email,
                subject: subject,
                body: messageBody,
                type: noteType,
                authorName: "Readyaimgo Team"
            )
            onSuccess()
            dismiss()
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
        isSending = false
    }
}

// MARK: - Collaborator Row (unchanged)

struct CollaboratorRow: View {
    let collaborator: GitHubCollaborator
    let isRemoving: Bool
    let onRemove: () -> Void

    @State private var showConfirm = false

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle().fill(WhisperTheme.accentSoft).frame(width: 38, height: 38)
                Text(String(collaborator.login.prefix(2)).uppercased())
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundStyle(WhisperTheme.accent)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text("@\(collaborator.login)").font(.subheadline.weight(.semibold)).foregroundStyle(WhisperTheme.ink)
                if let role = collaborator.roleInRepo {
                    Text(role.capitalized).font(.caption.weight(.medium)).foregroundStyle(WhisperTheme.mutedInk)
                }
            }
            Spacer()
            if isRemoving {
                ProgressView().tint(.secondary).scaleEffect(0.8)
            } else {
                Button { showConfirm = true } label: {
                    Image(systemName: "person.fill.xmark")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(WhisperTheme.danger)
                        .padding(8)
                        .background(WhisperTheme.danger.opacity(0.1), in: Circle())
                }
                .buttonStyle(.plain)
                .confirmationDialog("Remove @\(collaborator.login)?", isPresented: $showConfirm, titleVisibility: .visible) {
                    Button("Remove", role: .destructive) { onRemove() }
                    Button("Cancel", role: .cancel) {}
                } message: { Text("They will lose access to this repo immediately.") }
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
        .background(WhisperTheme.input, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(WhisperTheme.border, lineWidth: 1))
    }
}

// MARK: - Invitation Row (unchanged)

struct InvitationRow: View {
    let invitation: GitHubInvitation
    let isCancelling: Bool
    let onCancel: () -> Void

    @State private var showConfirm = false

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle().fill(WhisperTheme.warning.opacity(0.15)).frame(width: 38, height: 38)
                Image(systemName: "clock.badge").font(.system(size: 15, weight: .semibold)).foregroundStyle(WhisperTheme.warning)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(invitation.displayName).font(.subheadline.weight(.semibold)).foregroundStyle(WhisperTheme.ink)
                Text("Pending · \(invitation.role.capitalized)").font(.caption.weight(.medium)).foregroundStyle(WhisperTheme.mutedInk)
            }
            Spacer()
            if isCancelling {
                ProgressView().tint(.secondary).scaleEffect(0.8)
            } else {
                Button { showConfirm = true } label: {
                    Image(systemName: "xmark.circle")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(WhisperTheme.danger)
                        .padding(8)
                        .background(WhisperTheme.danger.opacity(0.1), in: Circle())
                }
                .buttonStyle(.plain)
                .confirmationDialog("Cancel invitation?", isPresented: $showConfirm, titleVisibility: .visible) {
                    Button("Cancel Invitation", role: .destructive) { onCancel() }
                    Button("Keep", role: .cancel) {}
                }
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
        .background(WhisperTheme.warning.opacity(0.06), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(WhisperTheme.warning.opacity(0.2), lineWidth: 1))
    }
}

// MARK: - Invite Collaborator Sheet (unchanged)

struct InviteCollaboratorSheet: View {
    @Environment(\.dismiss) private var dismiss
    let repoURL: String
    let onInvite: (String, CollaboratorPermission) async -> Void

    @State private var username = ""
    @State private var permission: CollaboratorPermission = .write
    @State private var isInviting = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    VStack(alignment: .leading, spacing: 8) {
                        WhisperSectionTitle(
                            eyebrow: "GitHub",
                            title: "Invite a collaborator",
                            detail: "They'll receive a GitHub invitation email and need to accept before getting access."
                        )
                    }
                    .whisperPanel()

                    VStack(alignment: .leading, spacing: 8) {
                        Text("GITHUB USERNAME")
                            .font(.caption2.weight(.bold)).tracking(0.9).foregroundStyle(WhisperTheme.mutedInk)
                        HStack(spacing: 10) {
                            Text("@").font(.subheadline.weight(.semibold)).foregroundStyle(WhisperTheme.mutedInk)
                            TextField("username", text: $username)
                                .platformDisableTextInputAutocapitalization()
                                .autocorrectionDisabled()
                                .font(.subheadline)
                        }
                        .whisperInsetField()
                    }
                    .whisperPanel()

                    VStack(alignment: .leading, spacing: 14) {
                        WhisperSectionTitle(eyebrow: "Access level", title: "Permission", detail: nil)
                        VStack(spacing: 8) {
                            ForEach(CollaboratorPermission.allCases) { perm in
                                Button { permission = perm } label: {
                                    HStack(spacing: 14) {
                                        Image(systemName: permission == perm ? "checkmark.circle.fill" : "circle")
                                            .foregroundStyle(permission == perm ? WhisperTheme.accent : WhisperTheme.mutedInk)
                                            .font(.system(size: 20))
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(perm.label).font(.subheadline.weight(.semibold)).foregroundStyle(WhisperTheme.ink)
                                            Text(perm.description).font(.caption).foregroundStyle(WhisperTheme.mutedInk)
                                        }
                                        Spacer()
                                    }
                                    .padding(14)
                                    .background(permission == perm ? WhisperTheme.accent.opacity(0.08) : WhisperTheme.input,
                                                in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                                    .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous)
                                        .stroke(permission == perm ? WhisperTheme.accent.opacity(0.3) : WhisperTheme.border, lineWidth: 1))
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                    .whisperPanel()

                    Button {
                        Task {
                            isInviting = true
                            await onInvite(username, permission)
                            isInviting = false
                            dismiss()
                        }
                    } label: {
                        HStack(spacing: 8) {
                            if isInviting { ProgressView().tint(.white).scaleEffect(0.85) }
                            else { Image(systemName: "paperplane.fill") }
                            Text(isInviting ? "Sending…" : "Send Invitation").fontWeight(.semibold)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 15)
                        .background(
                            username.trimmingCharacters(in: .whitespaces).isEmpty
                                ? WhisperTheme.mutedInk.opacity(0.3) : WhisperTheme.accent,
                            in: RoundedRectangle(cornerRadius: 18, style: .continuous)
                        )
                        .foregroundStyle(.white)
                    }
                    .disabled(username.trimmingCharacters(in: .whitespaces).isEmpty || isInviting)
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 20).padding(.vertical, 16)
            }
            .whisperShell()
            .navigationTitle("Invite")
            .platformNavigationTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            }
        }
    }
}
