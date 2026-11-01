import FocusCore
import SwiftUI

struct TimerRingView: View {
    @ObservedObject private var appTypography = TypographySettings.shared
    @ObservedObject var engine: TimerEngine
    let durationMinutes: Int

    private let diameter: CGFloat = 274
    private let lineWidth: CGFloat = 12

    var body: some View {
        ZStack {
            Circle()
                .stroke(FocusTheme.track, lineWidth: lineWidth)
                .frame(width: diameter, height: diameter)

            Circle()
                .trim(from: 0, to: min(max(engine.progress, 0), 1))
                .stroke(
                    FocusTheme.ink,
                    style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .frame(width: diameter, height: diameter)
                .animation(.linear(duration: 0.12), value: engine.progress)

            progressDot

            centerContent
        }
        .frame(width: 304, height: 304)
        .help(engine.mode == .countUp ? "正计时时，外圈每分钟走完一圈" : "外圈是这一轮专注的进度")
    }

    @ViewBuilder
    private var progressDot: some View {
        if engine.progress > 0.002 {
            Circle()
                .fill(FocusTheme.canvas)
                .overlay(Circle().strokeBorder(FocusTheme.ink, lineWidth: 2))
                .frame(width: 10, height: 10)
                .offset(y: -diameter / 2)
                .rotationEffect(.degrees(engine.progress * 360))
                .animation(.linear(duration: 0.12), value: engine.progress)
        }
    }

    private var centerContent: some View {
        VStack(spacing: 6) {
            Text(engine.formattedTime)
                .font(timeFont)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .monospacedDigit()
                .foregroundStyle(FocusTheme.textPrimary)
                .accessibilityLabel(accessibilityTime)

            Text(subtitle)
                .font(Typography.caption)
                .foregroundStyle(FocusTheme.textSecondary)
                .lineLimit(1)
                .minimumScaleFactor(0.85)
                .padding(.top, 2)
        }
        .frame(width: 220)
    }

    private var timeFont: Font {
        let size: CGFloat = engine.displaySeconds >= 3600 ? 53 : 66
        // 使用装饰字体或符号字体时，计时数字仍保持清晰和等宽。
        return .system(size: size * appTypography.scale, weight: .light, design: .default)
    }

    private var subtitle: String {
        switch engine.phase {
        case .finished:
            return "休息一下，准备下一轮"
        case .paused:
            #if os(macOS)
            return "按 ⌘↩ 继续"
            #else
            return "点「继续专注」接着计时" // iPhone / iPad 没有快捷键提示
            #endif
        case .running:
            if engine.mode == .countdown {
                let minutes = Int(ceil(engine.countdownRemaining / 60))
                return minutes <= 1 ? "还剩不到 1 分钟" : "还剩 \(minutes) 分钟"
            } else {
                let minutes = Int(engine.elapsed) / 60
                return minutes < 1 ? "保持节奏，专注当下" : "已投入 \(minutes) 分钟"
            }
        case .idle:
            return engine.mode == .countdown ? "\(durationMinutes) 分钟专注" : "从 0 开始，专注当下"
        }
    }

    private var accessibilityTime: String {
        let minutes = engine.displaySeconds / 60
        let seconds = engine.displaySeconds % 60
        return "\(engine.mode.displayName)，\(minutes) 分 \(seconds) 秒"
    }
}
