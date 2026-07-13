# raCommand UI + Sync Audit

Supersedes an earlier draft of this file that described `AppShellView`,
`IntelligenceFeedView`, `AIThreadsView`, `RagIntelligenceService`, and
`AccountSessionStore` — none of these exist in the current codebase. That
draft assumed a Firebase-Auth-backed Firestore client inside raCommand.
`OLD_RACOMMAND_PARITY_AUDIT.md` documents the actual decision: Firebase was
deliberately dropped from raCommand in favor of plain HTTP calls to the
readyaimgo admin API. Do not reintroduce Firebase/Firestore client code to
raCommand based on the old draft — it describes a path that was rejected.

## Current architecture (accurate as of this audit)

**Shell**: `Views/MainTabView.swift` — a `private enum ShellSection` drives
a Linear-style sidebar + content switch. Current sections: Workspaces
(`.projects`), Repos, People, Invoices, Contracts, Pulse, Today, Settings.
Pulse and Settings are still `ShellStubView` placeholders tagged `v1.1` —
real `PulseView.swift`/`SettingsView.swift` exist as files but aren't wired
into the shell yet.

**Networking**: plain `URLSession`, no Firebase, no Alamofire.
`Services/ClientNoteService.swift` is the shared home for every call to
`readyaimgo.biz` / `clients.readyaimgo.biz`: client feedback, RAG notes,
the People/Invoices/Contracts directory reads, and workspace-create sync.
`Services/GitHubService*.swift` is a separate URLSession layer for the
GitHub API (repo creation, collaborators, actions).

**Auth**: a single Bearer token (`READYAIMGO_INTERNAL_API_KEY` /
`RAG_INTERNAL_API_KEY` env var, or a Keychain-stored desktop session token
via `KeychainService.loadDesktopSessionToken()`) is attached by
`ClientNoteService.applyDesktopAuthorization(to:)`. The admin backend
checks this same value via `isInternalReadAuthorized` /
`isInternalMutationAuthorized` (`lib/internal-api-auth.ts` in the admin
repo). There is no per-user Firebase Auth session and no client-side
Firestore security-rules concept in raCommand — raCommand is a single
trusted operator client, and access control lives entirely server-side on
the admin API.

**Local Git + Codex pipeline** (do not disturb): `Services/LocalWorkspaceService.swift`
owns `git clone`, launching Codex Desktop, and reading/archiving Codex
thread state from `~/.codex/state_*.sqlite`. The actual sequencing — create
GitHub repo → clone locally → **sync workspace to admin** (best effort,
non-blocking — failure only sets `Project.workspaceSyncStatus`, never
blocks the local flow) → open Codex thread — lives in one place,
`Services/ProjectRepoProvisioner.swift`. `AddProjectView.swift` and
`ProjectDetailView.swift`'s `CreateProjectRepositorySheet` both call
`ProjectRepoProvisioner.provision(...)` rather than duplicating the
sequence; each call site only owns its own pre-step (creating/finding the
`Project` record) and its own error-message copy via
`ProjectRepoProvisioner.describe(_:)`, since the two views have slightly
different partial-failure UX (`AddProjectView` allows "Done" after a
partial failure once the repo exists; the sheet blocks on any failure).

**Workspace sync**: `Project` (SwiftData model, `Project.swift`) carries
`remoteWorkspaceId: String?` and `workspaceSyncStatus: WorkspaceSyncStatus`
(`.local` / `.pending` / `.synced` / `.error`), populated by
`ClientNoteService.createRemoteWorkspace(name:clientId:repoUrl:tags:)`
which calls `POST /api/admin/workspaces` on the admin repo. The sync
status is surfaced as a badge in `ProjectDetailView`'s repo pane.

**People / Invoices / Contracts tabs**: read-only mirrors of the admin
system of record, built as `Views/PeopleView.swift`,
`Views/InvoicesView.swift`, `Views/ContractsView.swift`. They call
`ClientNoteService.fetchDesktopClients()` (`GET /api/desktop/clients`),
`fetchInvoices()` (`GET /api/admin/invoices`, a new collection-group
endpoint since invoices live at `clients/{id}/invoices` in Firestore), and
`fetchContracts()` (`GET /api/contracts`, already existed). None of these
support create/edit from raCommand yet — that's still admin-only.

## What's still genuinely open

- Pulse and Settings tabs are stubs (`v1.1` — pre-existing, not part of
  this audit's scope).
- People/Invoices/Contracts are read-only. Create/edit from raCommand
  (e.g. drafting an invoice or generating a contract with AI, per the
  original integration proposal) is not implemented.
- No visible sync-status indicator in the Workspaces list rows yet — only
  in the workspace detail view.
- No local caching/offline mode for the new directory tabs — every tab
  open triggers a fresh network fetch, with no persisted fallback if the
  admin API is unreachable.

## Verification

- `xcodebuild -project raCommand.xcodeproj -scheme raCommand -destination 'platform=macOS' build`
  must succeed (file-system-synchronized groups mean new files under
  `Views/`/`Services/` are picked up automatically — no `project.pbxproj`
  edits needed).
- Exercise the "new project" flow (`AddProjectView`) and confirm the repo
  clones locally and Codex opens even if the admin API is unreachable
  (sync failure must be silent/non-blocking).
- Open People, Invoices, and Contracts tabs against a real
  `READYAIMGO_INTERNAL_API_KEY` and confirm data loads.
