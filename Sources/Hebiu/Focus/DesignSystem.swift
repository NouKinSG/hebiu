import FocusCore
import SwiftUI
#if os(macOS)
import AppKit
#else
import UIKit
#endif

// MARK: - Palette

extension Color {
    init(hex: UInt32, opacity: Double = 1) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: opacity
        )
    }
}

extension Color {
    /// 随系统深浅色切换的颜色（浅色 / 深色各一个值）。
    static func adaptive(
        light: UInt32,
        dark: UInt32,
        lightOpacity: Double = 1,
        darkOpacity: Double = 1
    ) -> Color {
        func components(_ isDark: Bool) -> (CGFloat, CGFloat, CGFloat, CGFloat) {
            let hex = isDark ? dark : light
            return (
                CGFloat((hex >> 16) & 0xFF) / 255,
                CGFloat((hex >> 8) & 0xFF) / 255,
                CGFloat(hex & 0xFF) / 255,
                isDark ? darkOpacity : lightOpacity
            )
        }
        #if os(macOS)
        return Color(nsColor: NSColor(name: nil) { appearance in
            let (r, g, b, a) = components(appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua)
            return NSColor(srgbRed: r, green: g, blue: b, alpha: a)
        })
        #else
        return Color(uiColor: UIColor { traits in
            let (r, g, b, a) = components(traits.userInterfaceStyle == .dark)
            return UIColor(red: r, green: g, blue: b, alpha: a)
        })
        #endif
    }
}

/// 平台相关的版面常量。
enum Layout {
    #if os(macOS)
    /// Mac 隐藏标题栏，内容顶到窗口最上方，需要让出红绿灯按钮的位置。
    static let panelTopInset: CGFloat = 46
    /// 侧栏页眉与计时栏页眉对齐（计时栏内容在 680 高度里垂直居中）。
    static let dashboardTopInset: CGFloat = 34.5
    #else
    /// iOS 由安全区负责避让刘海 / 状态栏，这里只留常规间距。
    static let panelTopInset: CGFloat = 12
    static let dashboardTopInset: CGFloat = 12
    #endif
}

/// 黑白灰单色主题，跟随系统深浅色。所有颜色只从这里取。
enum FocusTheme {
    // Backgrounds
    static let canvas = Color(nsColor: .windowBackgroundColor)
    static let surface = Color.adaptive(light: 0x000000, dark: 0xFFFFFF, lightOpacity: 0.04, darkOpacity: 0.06)
    static let surfaceStrong = Color.adaptive(light: 0x000000, dark: 0xFFFFFF, lightOpacity: 0.07, darkOpacity: 0.10)
    static let stroke = Color.adaptive(light: 0x000000, dark: 0xFFFFFF, lightOpacity: 0.09, darkOpacity: 0.11)
    static let strokeStrong = Color.adaptive(light: 0x000000, dark: 0xFFFFFF, lightOpacity: 0.18, darkOpacity: 0.20)

    // Type
    static let textPrimary = Color.adaptive(light: 0x111111, dark: 0xF5F5F5)
    static let textSecondary = Color.adaptive(light: 0x6B6B6B, dark: 0xA3A3A3)
    static let textTertiary = Color(nsColor: .secondaryLabelColor)

    /// 唯一的「强调」：墨色，即正文主色。
    static let ink = Theme.accent
    static let track = stroke
}

// MARK: - Typography

enum Typography {
    static var timer: Font { Font.hebiuSystem(size: 66, weight: .light, design: .default) }
    static var wordmark: Font { Font.hebiuSystem(size: 16, weight: .semibold, design: .default) }
    static var eyebrow: Font { Font.hebiuSystem(size: 10.5, weight: .semibold, design: .default) }
    static var body: Font { Font.hebiuSystem(size: 13.5, weight: .regular, design: .default) }
    static var bodyMedium: Font { Font.hebiuSystem(size: 13.5, weight: .medium, design: .default) }
    static var button: Font { Font.hebiuSystem(size: 15, weight: .semibold, design: .default) }
    static var chip: Font { Font.hebiuSystem(size: 12.5, weight: .medium, design: .default) }
    static var caption: Font { Font.hebiuSystem(size: 11, weight: .regular, design: .default) }
}

// MARK: - App background

struct AppBackground: View {
    @ObservedObject private var appTypography = TypographySettings.shared
    var body: some View {
        FocusTheme.canvas.ignoresSafeArea()
    }
}

// MARK: - Surfaces

struct SurfaceBackground: ViewModifier {
    @ObservedObject private var appTypography = TypographySettings.shared
    var cornerRadius: CGFloat = 18
    var strong = false

    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(strong ? FocusTheme.surfaceStrong : FocusTheme.surface)
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(FocusTheme.stroke, lineWidth: 1)
            )
    }
}

extension View {
    func surface(cornerRadius: CGFloat = 18, strong: Bool = false) -> some View {
        modifier(SurfaceBackground(cornerRadius: cornerRadius, strong: strong))
    }
}

// MARK: - Primary button

struct PrimaryTimerButtonStyle: ButtonStyle {
    @ObservedObject private var appTypography = TypographySettings.shared
    var isHighlighted: Bool = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Typography.button)
            .foregroundStyle(Color.white)
            .padding(.horizontal, 30)
            .frame(height: 56)
            .background(
                Capsule(style: .continuous)
                    .fill(FocusTheme.ink)
                    .overlay(
                        Capsule(style: .continuous)
                            .strokeBorder(Color.white.opacity(0.22), lineWidth: 1)
                    )
            )
            .scaleEffect(configuration.isPressed ? 0.965 : 1)
            .brightness(configuration.isPressed ? -0.04 : 0)
            .animation(.easeOut(duration: 0.16), value: configuration.isPressed)
    }
}

// MARK: - Circular icon button

struct CircleIconButtonStyle: ButtonStyle {
    @ObservedObject private var appTypography = TypographySettings.shared
    var size: CGFloat = 56
    var emphasized = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.hebiuSystem(size: 16, weight: .semibold))
            .foregroundStyle(emphasized ? FocusTheme.textPrimary : FocusTheme.textSecondary)
            .frame(width: size, height: size)
            .background(
                Circle()
                    .fill(emphasized ? FocusTheme.surfaceStrong : FocusTheme.surface)
            )
            .overlay(
                Circle().strokeBorder(FocusTheme.stroke, lineWidth: 1)
            )
            .scaleEffect(configuration.isPressed ? 0.94 : 1)
            .animation(.easeOut(duration: 0.14), value: configuration.isPressed)
    }
}

// MARK: - App mark

/// 页眉里的品牌标记（日晷之人）：资源目录里的 `BrandMark`，由 `Scripts/make-icon.py` 生成，三端一致。
struct AppMark: View {
    @ObservedObject private var appTypography = TypographySettings.shared
    var size: CGFloat = 32

    var body: some View {
        Image(systemName: "timer")
            .resizable()
            .foregroundStyle(Theme.accent)
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }
}
