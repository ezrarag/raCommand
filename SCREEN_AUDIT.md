# raCommand Screen Audit

## Primary Navigation

- `MainTabView`
  - `ProjectListView` — project board and import entry point
  - `RepoManagerView` — repo inventory, local mirror actions, Codex handoff
  - `PulseView` — priority ranking plus ask-Pulse query flow
  - `TodayView` — daily briefing and execution queue
  - `SettingsView` — app memory, build log, and idea inbox

## Project Flow

- `ProjectListView`
  - `ProjectDetailView`
    - `ProjectClientNotesView`
      - `ResolveNoteSheet`
    - `ProjectPeopleView`
      - `AddClientToPortalSheet`
      - `SendRagNoteSheet`
      - `InviteCollaboratorSheet`
    - `AddVoiceNoteView`
    - `CreateRepoSheet`

## Project Import Flow

- `AddProjectView`
- `PasteImportView`
- `GitHubImportView`
- `ProjectImportPreviewView`

## Notes / Detail Editors

- `BuildNoteDetailView`
- `IdeaNoteDetailView`
- `VoiceNoteDetailView`

## Cross-Cutting Capture

- `QuickIdeaView` — toolbar sheet for routing a raw idea into a client stream

## Recommended Critical Path Screens

1. `ProjectListView`
2. `ProjectDetailView`
3. `RepoManagerView`
4. `TodayView`
5. `QuickIdeaView`

These five screens define the product purpose most clearly: choose work, inspect work, manage the mirrored repo/admin surface, run the daily loop, and capture ideas without friction.
