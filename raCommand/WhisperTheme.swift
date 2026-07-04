import SwiftUI

#if os(macOS)
import AppKit
#elseif canImport(UIKit)
import UIKit
#endif

enum PlatformNavigationTitleMode {
    case inline
    case large
}

enum PlatformSearchPlacementStyle {
    case automaticDrawer
    case alwaysDrawer
}

enum PlatformSystemServices {
    static func open(_ url: URL) {
#if os(macOS)
        NSWorkspace.shared.open(url)
#elseif canImport(UIKit)
        UIApplication.shared.open(url)
#endif
    }

    static func copyToPasteboard(_ string: String) {
#if os(macOS)
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(string, forType: .string)
#elseif canImport(UIKit)
        UIPasteboard.general.string = string
#endif
    }
}

enum WhisperTheme {
    static let canvasTop = Color(red: 0.031, green: 0.035, blue: 0.043)
    static let canvasBottom = Color(red: 0.051, green: 0.056, blue: 0.067)
    static let halo = Color(red: 0.098, green: 0.176, blue: 0.337).opacity(0.18)
    static let haloAlt = Color(red: 0.298, green: 0.553, blue: 1.000).opacity(0.12)

    static let panel = Color(red: 0.074, green: 0.078, blue: 0.092)
    static let panelStrong = Color(red: 0.094, green: 0.098, blue: 0.114)
    static let input = Color(red: 0.098, green: 0.102, blue: 0.118)
    static let border = Color.white.opacity(0.08)

    static let ink = Color(red: 0.933, green: 0.941, blue: 0.953)
    static let mutedInk = Color(red: 0.540, green: 0.560, blue: 0.596)
    static let accent = Color(red: 0.298, green: 0.553, blue: 1.000)
    static let accentSoft = Color(red: 0.110, green: 0.165, blue: 0.290)
    static let action = Color(red: 1.000, green: 0.604, blue: 0.286)

    static let success = Color(red: 0.275, green: 0.694, blue: 0.498)
    static let warning = Color(red: 0.878, green: 0.565, blue: 0.227)
    static let danger = Color(red: 0.884, green: 0.353, blue: 0.396)
    static let info = Color(red: 0.435, green: 0.690, blue: 1.000)

    static let sidebar = Color(red: 0.043, green: 0.047, blue: 0.055)
    static let sidebarSelected = Color.white.opacity(0.06)
}

struct WhisperBackground: View {
    var body: some View {
        ZStack {
            LinearGradient(
                colors: [WhisperTheme.canvasTop, WhisperTheme.canvasBottom],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            Circle()
                .fill(WhisperTheme.halo)
                .frame(width: 420, height: 420)
                .blur(radius: 70)
                .offset(x: -180, y: -220)

            Circle()
                .fill(WhisperTheme.haloAlt)
                .frame(width: 360, height: 360)
                .blur(radius: 90)
                .offset(x: 210, y: 260)
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }
}

struct WhisperMetricPill: View {
    let label: String
    let value: String
    let tone: Color

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            Circle()
                .fill(tone)
                .frame(width: 8, height: 8)
            Text(label.uppercased())
                .font(.caption2.weight(.medium))
                .foregroundStyle(WhisperTheme.mutedInk)
            Spacer(minLength: 6)
            Text(value)
                .font(.callout.weight(.semibold))
                .foregroundStyle(WhisperTheme.ink)
        }
        .frame(maxWidth: .infinity, alignment: .center)
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(WhisperTheme.input, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .stroke(tone.opacity(0.22), lineWidth: 1)
        )
    }
}

struct WhisperEmptyState: View {
    let icon: String
    let title: String
    let message: String

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 26, weight: .medium))
                .foregroundStyle(WhisperTheme.accent)
            Text(title)
                .font(.headline.weight(.semibold))
                .foregroundStyle(WhisperTheme.ink)
            Text(message)
                .font(.callout)
                .foregroundStyle(WhisperTheme.mutedInk)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
        .padding(.horizontal, 16)
        .whisperPanel(padding: 16, radius: 10)
    }
}

struct WhisperSectionTitle: View {
    let eyebrow: String
    let title: String
    var detail: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(eyebrow.uppercased())
                .font(.caption2.weight(.semibold))
                .foregroundStyle(WhisperTheme.accent)
            Text(title)
                .font(.headline.weight(.semibold))
                .foregroundStyle(WhisperTheme.ink)
            if let detail, !detail.isEmpty {
                Text(detail)
                    .font(.callout)
                    .foregroundStyle(WhisperTheme.mutedInk)
            }
        }
    }
}

private struct WhisperPanelModifier: ViewModifier {
    let padding: CGFloat
    let radius: CGFloat

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .background(
                LinearGradient(
                    colors: [WhisperTheme.panel, WhisperTheme.panelStrong],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                in: RoundedRectangle(cornerRadius: radius, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .stroke(WhisperTheme.border, lineWidth: 1)
            )
            .shadow(color: Color.black.opacity(0.28), radius: 18, x: 0, y: 10)
    }
}

private struct WhisperShellModifier: ViewModifier {
    func body(content: Content) -> some View {
        ZStack {
            WhisperBackground()
            content
        }
        .tint(WhisperTheme.accent)
        .foregroundStyle(WhisperTheme.ink)
        .fontDesign(.default)
    }
}

private struct WhisperFormChromeModifier: ViewModifier {
    func body(content: Content) -> some View {
        ZStack {
            WhisperBackground()
            content
                .scrollContentBackground(.hidden)
        }
        .tint(WhisperTheme.accent)
        .fontDesign(.default)
    }
}

extension View {
    func whisperPanel(padding: CGFloat = 14, radius: CGFloat = 10) -> some View {
        modifier(WhisperPanelModifier(padding: padding, radius: radius))
    }

    func whisperShell() -> some View {
        modifier(WhisperShellModifier())
    }

    func whisperFormChrome() -> some View {
        modifier(WhisperFormChromeModifier())
    }

    func whisperInsetField() -> some View {
        padding(.horizontal, 14)
            .padding(.vertical, 9)
            .background(WhisperTheme.input, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(WhisperTheme.border, lineWidth: 1)
            )
    }

    @ViewBuilder
    func platformNavigationTitleDisplayMode(_ mode: PlatformNavigationTitleMode) -> some View {
#if os(iOS) || os(tvOS) || os(visionOS)
        switch mode {
        case .inline:
            self.navigationBarTitleDisplayMode(.inline)
        case .large:
            self.navigationBarTitleDisplayMode(.large)
        }
#else
        self
#endif
    }

    @ViewBuilder
    func platformListRowSpacing(_ spacing: CGFloat) -> some View {
#if os(iOS) || os(tvOS) || os(visionOS)
        if #available(iOS 17.0, tvOS 17.0, visionOS 1.0, *) {
            self.listRowSpacing(spacing)
        } else {
            self
        }
#else
        self
#endif
    }

    @ViewBuilder
    func platformSearchable(
        text: Binding<String>,
        placement: PlatformSearchPlacementStyle = .automaticDrawer,
        prompt: String
    ) -> some View {
#if os(macOS)
        self.searchable(text: text, prompt: prompt)
#else
        switch placement {
        case .automaticDrawer:
            self.searchable(text: text, placement: .navigationBarDrawer(displayMode: .automatic), prompt: prompt)
        case .alwaysDrawer:
            self.searchable(text: text, placement: .navigationBarDrawer(displayMode: .always), prompt: prompt)
        }
#endif
    }

    @ViewBuilder
    func platformDisableTextInputAutocapitalization() -> some View {
#if os(iOS) || os(tvOS) || os(visionOS)
        self.textInputAutocapitalization(.never)
#else
        self
#endif
    }
}

extension ToolbarItemPlacement {
    static var platformNavigationLeading: ToolbarItemPlacement {
#if os(macOS)
        .automatic
#else
        .navigationBarLeading
#endif
    }

    static var platformNavigationTrailing: ToolbarItemPlacement {
#if os(macOS)
        .automatic
#else
        .navigationBarTrailing
#endif
    }
}

extension ProjectStatus {
    var whisperColor: Color {
        switch self {
        case .green: return WhisperTheme.success
        case .yellow: return WhisperTheme.warning
        case .red: return WhisperTheme.danger
        }
    }
}

extension ProjectCategory {
    var whisperColor: Color {
        switch self {
        case .app: return WhisperTheme.info
        case .website: return WhisperTheme.accent
        case .infra: return WhisperTheme.warning
        case .legal: return WhisperTheme.danger
        case .finance: return WhisperTheme.success
        case .content: return Color(red: 0.783, green: 0.608, blue: 0.941)
        }
    }
}

enum WhisperAppAppearance {
    static func configure() {
        #if canImport(UIKit)
        let accent = UIColor(red: 0.298, green: 0.553, blue: 1.000, alpha: 1)
        let ink = UIColor(red: 0.933, green: 0.941, blue: 0.953, alpha: 1)
        let muted = UIColor(red: 0.540, green: 0.560, blue: 0.596, alpha: 1)
        let tabBackground = UIColor(red: 0.074, green: 0.078, blue: 0.092, alpha: 0.98)

        let tabAppearance = UITabBarAppearance()
        tabAppearance.configureWithOpaqueBackground()
        tabAppearance.backgroundColor = tabBackground
        tabAppearance.shadowColor = UIColor.white.withAlphaComponent(0.08)

        [tabAppearance.stackedLayoutAppearance, tabAppearance.inlineLayoutAppearance, tabAppearance.compactInlineLayoutAppearance].forEach { layout in
            layout.normal.iconColor = muted
            layout.normal.titleTextAttributes = [.foregroundColor: muted]
            layout.selected.iconColor = accent
            layout.selected.titleTextAttributes = [.foregroundColor: accent]
        }

        UITabBar.appearance().standardAppearance = tabAppearance
        UITabBar.appearance().scrollEdgeAppearance = tabAppearance

        let navAppearance = UINavigationBarAppearance()
        navAppearance.configureWithDefaultBackground()
        navAppearance.backgroundColor = tabBackground
        navAppearance.shadowColor = UIColor.white.withAlphaComponent(0.06)
        navAppearance.titleTextAttributes = [
            .foregroundColor: ink,
            .font: roundedFont(textStyle: .headline, weight: .semibold)
        ]
        navAppearance.largeTitleTextAttributes = [
            .foregroundColor: ink,
            .font: roundedFont(textStyle: .largeTitle, weight: .bold)
        ]

        UINavigationBar.appearance().standardAppearance = navAppearance
        UINavigationBar.appearance().compactAppearance = navAppearance
        UINavigationBar.appearance().scrollEdgeAppearance = navAppearance

        UISegmentedControl.appearance().selectedSegmentTintColor = accent
        UISegmentedControl.appearance().setTitleTextAttributes([.foregroundColor: ink], for: .normal)
        UISegmentedControl.appearance().setTitleTextAttributes([.foregroundColor: UIColor.white], for: .selected)
        #endif
    }

    #if canImport(UIKit)
    private static func roundedFont(textStyle: UIFont.TextStyle, weight: UIFont.Weight) -> UIFont {
        let base = UIFont.systemFont(ofSize: UIFont.preferredFont(forTextStyle: textStyle).pointSize, weight: weight)
        guard let rounded = base.fontDescriptor.withDesign(.rounded) else {
            return base
        }
        return UIFont(descriptor: rounded, size: 0)
    }
    #endif
}
