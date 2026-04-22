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
    static let canvasTop = Color(red: 0.91, green: 0.88, blue: 0.83)
    static let canvasBottom = Color(red: 0.98, green: 0.96, blue: 0.92)
    static let halo = Color(red: 0.87, green: 0.54, blue: 0.34)
    static let haloAlt = Color(red: 0.45, green: 0.58, blue: 0.76)

    static let panel = Color(red: 0.98, green: 0.96, blue: 0.93)
    static let panelStrong = Color(red: 0.95, green: 0.92, blue: 0.88)
    static let input = Color.white.opacity(0.7)
    static let border = Color.white.opacity(0.82)

    static let ink = Color(red: 0.18, green: 0.15, blue: 0.12)
    static let mutedInk = Color(red: 0.42, green: 0.38, blue: 0.33)
    static let accent = Color(red: 0.76, green: 0.41, blue: 0.23)
    static let accentSoft = Color(red: 0.95, green: 0.86, blue: 0.78)

    static let success = Color(red: 0.29, green: 0.55, blue: 0.44)
    static let warning = Color(red: 0.82, green: 0.56, blue: 0.22)
    static let danger = Color(red: 0.74, green: 0.34, blue: 0.29)
    static let info = Color(red: 0.33, green: 0.47, blue: 0.72)
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
                .fill(WhisperTheme.halo.opacity(0.18))
                .frame(width: 360, height: 360)
                .blur(radius: 24)
                .offset(x: 150, y: -260)

            Circle()
                .fill(WhisperTheme.haloAlt.opacity(0.12))
                .frame(width: 300, height: 300)
                .blur(radius: 18)
                .offset(x: -150, y: 260)
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
        VStack(alignment: .leading, spacing: 6) {
            Text(label.uppercased())
                .font(.caption2.weight(.semibold))
                .tracking(0.8)
                .foregroundStyle(WhisperTheme.mutedInk)
            Text(value)
                .font(.system(.title3, design: .rounded).weight(.bold))
                .foregroundStyle(WhisperTheme.ink)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(tone.opacity(0.08), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(tone.opacity(0.18), lineWidth: 1)
        )
    }
}

struct WhisperEmptyState: View {
    let icon: String
    let title: String
    let message: String

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 34, weight: .medium))
                .foregroundStyle(WhisperTheme.accent)
            Text(title)
                .font(.system(.title3, design: .rounded).weight(.bold))
                .foregroundStyle(WhisperTheme.ink)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(WhisperTheme.mutedInk)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 34)
        .padding(.horizontal, 18)
        .whisperPanel()
    }
}

struct WhisperSectionTitle: View {
    let eyebrow: String
    let title: String
    var detail: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(eyebrow.uppercased())
                .font(.caption2.weight(.bold))
                .tracking(1.0)
                .foregroundStyle(WhisperTheme.accent)
            Text(title)
                .font(.system(.title3, design: .rounded).weight(.bold))
                .foregroundStyle(WhisperTheme.ink)
            if let detail, !detail.isEmpty {
                Text(detail)
                    .font(.subheadline)
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
            .shadow(color: Color.black.opacity(0.07), radius: 20, x: 0, y: 10)
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
        .fontDesign(.rounded)
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
        .fontDesign(.rounded)
    }
}

extension View {
    func whisperPanel(padding: CGFloat = 18, radius: CGFloat = 24) -> some View {
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
            .padding(.vertical, 12)
            .background(WhisperTheme.input, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
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
        case .content: return Color.purple
        }
    }
}

enum WhisperAppAppearance {
    static func configure() {
        #if canImport(UIKit)
        let accent = UIColor(red: 0.76, green: 0.41, blue: 0.23, alpha: 1)
        let ink = UIColor(red: 0.18, green: 0.15, blue: 0.12, alpha: 1)
        let muted = UIColor(red: 0.42, green: 0.38, blue: 0.33, alpha: 1)
        let tabBackground = UIColor(red: 0.95, green: 0.92, blue: 0.88, alpha: 0.98)

        let tabAppearance = UITabBarAppearance()
        tabAppearance.configureWithOpaqueBackground()
        tabAppearance.backgroundColor = tabBackground
        tabAppearance.shadowColor = UIColor.white.withAlphaComponent(0.35)

        [tabAppearance.stackedLayoutAppearance, tabAppearance.inlineLayoutAppearance, tabAppearance.compactInlineLayoutAppearance].forEach { layout in
            layout.normal.iconColor = muted
            layout.normal.titleTextAttributes = [.foregroundColor: muted]
            layout.selected.iconColor = accent
            layout.selected.titleTextAttributes = [.foregroundColor: accent]
        }

        UITabBar.appearance().standardAppearance = tabAppearance
        UITabBar.appearance().scrollEdgeAppearance = tabAppearance

        let navAppearance = UINavigationBarAppearance()
        navAppearance.configureWithTransparentBackground()
        navAppearance.backgroundEffect = UIBlurEffect(style: .systemUltraThinMaterialLight)
        navAppearance.shadowColor = .clear
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
