# Old raCommand Parity Audit

Reference inspected:

- `/Users/ehauga/Desktop/local dev/Style and Reference/Old raCommand`

The reference is a compiled macOS app bundle, not source. This audit is based on bundle metadata, bundled resources, and binary strings, then compared against the current source tree.

## Current Coverage

| Area observed in old bundle | Current coverage | Notes |
| --- | --- | --- |
| Projects | Present | `Project`, `ProjectListView`, and `ProjectDetailView` cover project tracking, status, value, client, dates, notes, repo URLs, and local paths. |
| Repos / GitHub | Present | GitHub import, repo creation, collaborators, repo snapshots, clone/open flows, local git status, push, and local removal are present. |
| Codex threads | Present | Current app can open workspaces in Codex, detect active Codex workspaces, and archive matching Codex threads before local removal. |
| Pulse | Present | Pulse reads project metadata, local git state, GitHub state, collaborators, and client feedback to answer project questions and draft updates. |
| Today | Present | Current app has a focused priority/action view. |
| Settings | Present | Current app stores app context, build notes, and idea notes. |
| Build notes | Present | `BuildNote` model and settings UI are present. |
| Idea notes | Present | `IdeaNote` model and settings UI are present. |
| Voice notes / transcripts | Present | `VoiceNote`, recording, playback, and speech transcription services are present. |
| Client feedback | Present | Current app connects to `clients.readyaimgo.biz` for feedback, Loom/page context, status changes, and client portal links. |
| RAG notes / client portal | Present | Current app can fetch and send RAG notes and provision client portal handoff access. |

## Differences

- The old bundle includes Firebase and Firestore frameworks plus `GoogleService-Info.plist`.
- The current app does not use Firebase. It uses HTTP services for `clients.readyaimgo.biz` and `readyaimgo.biz` instead.
- No old source files were available, so exact old data models, view layout, and hidden workflows could not be compared line-by-line.

## Recommendation

Do not add Firebase back unless a concrete missing workflow is identified. The current HTTP service layer appears to cover the client feedback and portal capabilities indicated by the old bundle, while keeping the app simpler and avoiding extra SDK/signing complexity.
