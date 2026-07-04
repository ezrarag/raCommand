# CLAUDE.md: raCommand Linear UI + Permissions Audit

Use this as the implementation prompt for the Linear-style UI pass and local/offline RAG permissions pass.

## Audit Findings

- `AppShellView.swift` uses a narrow icon-only sidebar rail. A Linear-style workspace header needs a wider compact sidebar with app logo, workspace/project name, and pinned Settings.
- `IntelligenceFeedView.swift` and `AIThreadsView.swift` use standard `Section(group.label)` list headers. Replace them with custom `HStack` headers using `Font.system(size: 11, weight: .semibold)` and `.secondary` foreground color.
- `SettingsView.swift` is custom rather than `List` based, but it should become denser and less editorial: smaller section labels, lower radius, less hero weight.
- `IntelligenceFeedView` currently exposes Firestore permission failures as bright red error text. Replace with a desaturated dark-mode permission panel.
- `RagIntelligenceService` reads `ragIntelligence` globally with no Firebase Auth and no `ownerUid` filter. Local "Missing or insufficient permissions" is expected when Firestore rules deny unauthenticated global reads.
- The app session in `AccountSessionStore` is not Firebase Auth. A raCommand Keychain session token does not authenticate Firestore client reads.

## Required Implementation

1. Add a shared `LinearSectionHeader` component:

```swift
struct LinearSectionHeader: View {
    let title: String
    let count: Int?

    init(_ title: String, count: Int? = nil) {
        self.title = title
        self.count = count
    }

    var body: some View {
        HStack(spacing: 6) {
            Text(title.uppercased()).lineLimit(1)
            Spacer(minLength: 8)
            if let count {
                Text("\(count)")
                    .foregroundStyle(.tertiary)
                    .monospacedDigit()
            }
        }
        .font(.system(size: 11, weight: .semibold))
        .foregroundStyle(.secondary)
        .textCase(nil)
    }
}
```

2. Replace `Section(group.label)` in the Intelligence and AI Threads sidebars with:

```swift
Section {
    ForEach(group.threads) { thread in
        // existing row
    }
} header: {
    LinearSectionHeader(group.label, count: group.threads.count)
}
```

3. Add a workspace header to the regular-size sidebar using the app icon and `raCommand / Readyaimgo` labels. Expand the rail width to roughly 216-232 points if text labels are included.

4. Add a desaturated permission palette to `WhisperTheme`, using a dark brown-gray surface, muted border, warm title, and muted body text. Do not render Firestore permission failures with bright `.red`.

5. Add explicit RAG access mode:

```swift
enum RagAccessMode: Equatable {
    case localOffline
    case operatorDirect
    case userScoped(ownerUid: String)
}
```

In local/offline mode, do not open a Firestore listener. Return empty groups with no error. In user mode, query `whereField("ownerUid", isEqualTo: ownerUid).order(by: "updatedAt", descending: true)`.

6. If the product requirement is an Architect tab, add it explicitly to `AppTab` and keep it visible in local/offline mode. Use `AIThreadsView` as the first local/offline implementation if no dedicated `ArchitectView` exists.

## Verification

- Build the macOS target.
- Launch signed out and confirm local/offline views do not trigger Firestore permission errors.
- Confirm Architect is visible if implemented.
- Confirm custom 11-point section headers render in Intelligence and AI Threads.
- Confirm permission errors render as a restrained operational panel, not red destructive text.
