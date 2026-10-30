import FocusCore
import SwiftUI

// MARK: - 模式文字

extension TimerMode {
    var displayName: String {
        switch self {
        case .countdown: return "倒计时"
        case .countUp: return "正计时"
        }
    }
}

// MARK: - 计时面板

/// 计时栏：页眉、标题、模式切换、环形计时、时长预设、控制按钮、页脚。
/// Mac 与 iPad 放在左栏，iPhone 作为「专注」标签页。
struct TimerPanel: View {
    @ObservedObject private var appTypography = TypographySettings.shared
    @ObservedObject var model: FocusModel
    @ObservedObject private var engine: TimerEngine
    /// 页眉是否显示「统计」切换按钮（iPhone 由标签栏切换，不显示）。
    let showsDashboardToggle: Bool

    @FocusState private var titleFocused: Bool
    @Namespace private var modeNamespace

    init(model: FocusModel, showsDashboardToggle: Bool = true) {
        self.model = model
        self.engine = model.engine
        self.showsDashboardToggle = showsDashboardToggle
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Spacer().frame(height: 18)
            focusTitleCard
            Spacer().frame(height: 14)
            modeSwitcher
            Spacer().frame(height: 20)
            TimerRingView(engine: engine, durationMinutes: model.durationMinutes)
            Spacer().frame(height: 18)
            presetRow
            Spacer().frame(height: 20)
            controls
            Spacer().frame(height: 14)
            footer
        }
        .padding(.horizontal, 28)
        .padding(.top, Layout.panelTopInset)
        .padding(.bottom, 22)
    }

    // MARK: 页眉

    private var header: some View {
        HStack(spacing: 10) {
            AppMark(size: 34)

            Text("FocusOnYourself")
                .font(Typography.wordmark)
                .foregroundStyle(FocusTheme.textPrimary)
                .lineLimit(1)

            Spacer()

            if showsDashboardToggle {
                Button {
                    model.toggleDashboard()
                } label: {
                    Image(systemName: "chart.bar.xaxis")
                        .font(.hebiuSystem(size: 11.5, weight: .semibold))
                        .foregroundStyle(model.isDashboardVisible ? FocusTheme.ink : FocusTheme.textSecondary)
                }
                .buttonStyle(CircleIconButtonStyle(size: 28))
                .keyboardShortcut("d", modifiers: .command)
                .help("显示/隐藏统计（⌘D）")
                #if os(iOS)
                .keyboardShortcut("d", modifiers: .command) // iPad 外接键盘；Mac 由菜单项提供
                #endif
            }

            StatusPill(phase: engine.phase)
        }
        .frame(height: 30)
    }

    // MARK: 专注标题

    private var focusTitleCard: some View {
        HStack(spacing: 11) {
            Image(systemName: "pencil.line")
                .font(.hebiuSystem(size: 14, weight: .medium))
                .foregroundStyle(titleFocused ? FocusTheme.ink : FocusTheme.textSecondary)
                .frame(width: 17)

            TextField("这次要专注什么？", text: $model.focusTitle)
                .textFieldStyle(.plain)
                .font(Typography.bodyMedium)
                .foregroundStyle(FocusTheme.textPrimary)
                .focused($titleFocused)
                .onSubmit { titleFocused = false }
                .onChange(of: model.focusTitle) { _, newValue in
                    if newValue.count > 60 {
                        model.focusTitle = String(newValue.prefix(60))
                    }
                }

            if !model.focusTitle.isEmpty {
                Button {
                    model.focusTitle = ""
                    titleFocused = true
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.hebiuSystem(size: 13))
                        .foregroundStyle(FocusTheme.textTertiary)
                }
                .buttonStyle(.plain)
                .help("清空标题")
            }
        }
        .padding(.horizontal, 16)
        .frame(height: 52)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(FocusTheme.surface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(
                    titleFocused ? FocusTheme.ink.opacity(0.55) : FocusTheme.stroke,
                    lineWidth: 1
                )
        )
        .animation(.easeOut(duration: 0.18), value: titleFocused)
    }

    // MARK: 模式切换

    private var modeSwitcher: some View {
        HStack(spacing: 3) {
            ForEach(TimerMode.allCases, id: \.self) { mode in
                Button {
                    model.setMode(mode)
                } label: {
                    Text(mode.displayName)
                        .font(.hebiuSystem(size: 12.5, weight: .semibold, design: .default))
                        .foregroundStyle(engine.mode == mode ? FocusTheme.ink : FocusTheme.textSecondary)
                        .frame(width: 106, height: 30)
                        .background {
                            if engine.mode == mode {
                                Capsule(style: .continuous)
                                    .fill(FocusTheme.ink.opacity(0.14))
                                    .overlay(
                                        Capsule(style: .continuous)
                                            .strokeBorder(FocusTheme.ink.opacity(0.34), lineWidth: 1)
                                    )
                                    .matchedGeometryEffect(id: "selectedMode", in: modeNamespace)
                            }
                        }
                }
                .buttonStyle(.plain)
                .help(mode == .countdown ? "设置一个终点，倒着数" : "没有终点，记录已经投入的时间")
            }
        }
        .padding(3)
        .background(Capsule(style: .continuous).fill(FocusTheme.surface))
        .overlay(Capsule(style: .continuous).strokeBorder(FocusTheme.stroke, lineWidth: 1))
    }

    // MARK: 时长预设

    private var presetRow: some View {
        Group {
            if engine.mode == .countdown {
                HStack(spacing: 7) {
                    ForEach(FocusModel.presets, id: \.self) { minutes in
                        DurationChip(
                            title: "\(minutes)",
                            unit: "分",
                            selected: model.durationMinutes == minutes
                        ) {
                            model.selectPreset(minutes: minutes)
                        }
                    }

                    customDurationChip
                }
            } else {
                Text("正计时没有终点 · 随时暂停，记录每一分钟")
                    .font(Typography.caption)
                    .foregroundStyle(FocusTheme.textTertiary)
                    .frame(maxWidth: .infinity)
            }
        }
        .frame(height: 38)
    }

    private var customDurationChip: some View {
        Button {
            model.openCustomEditor()
        } label: {
            HStack(spacing: 5) {
                Text(model.isCustomDuration ? "\(model.durationMinutes) 分" : "自定义")
                Image(systemName: "slider.horizontal.3")
                    .font(.hebiuSystem(size: 10, weight: .semibold))
            }
            .font(Typography.chip)
            .foregroundStyle(model.isCustomDuration ? FocusTheme.ink : FocusTheme.textSecondary)
            .padding(.horizontal, 12)
            .frame(height: 32)
            .background(
                Capsule(style: .continuous)
                    .fill(model.isCustomDuration ? FocusTheme.ink.opacity(0.13) : FocusTheme.surface)
            )
            .overlay(
                Capsule(style: .continuous)
                    .strokeBorder(
                        model.isCustomDuration ? FocusTheme.ink.opacity(0.34) : FocusTheme.stroke,
                        lineWidth: 1
                    )
            )
        }
        .buttonStyle(.plain)
        .help("自定义 1–180 分钟")
        .popover(isPresented: $model.isCustomEditorPresented, arrowEdge: .bottom) {
            CustomDurationEditor(model: model)
                .presentationCompactAdaptation(.sheet) // iPhone：底部 sheet；iPad / Mac：popover
                .presentationDetents([.height(320)])
        }
    }

    // MARK: 操作按钮

    private var controls: some View {
        HStack(spacing: 12) {
            Button {
                model.reset()
            } label: {
                Image(systemName: "arrow.counterclockwise")
            }
            .buttonStyle(CircleIconButtonStyle(size: 56))
            .disabled(!model.canReset)
            .opacity(model.canReset ? 1 : 0.38)
            .keyboardShortcut("r", modifiers: .command)
            .help("重置（⌘R）")

            Button {
                model.startPause()
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: primaryIcon)
                        .font(.hebiuSystem(size: 14, weight: .bold))
                    Text(primaryTitle)
                }
                .frame(minWidth: 178)
            }
            .buttonStyle(PrimaryTimerButtonStyle())
            .keyboardShortcut(.return, modifiers: .command)
            .help("开始 / 暂停（⌘↩）")
        }
    }

    private var primaryIcon: String {
        switch engine.phase {
        case .running: return "pause.fill"
        case .finished: return "arrow.clockwise"
        default: return "play.fill"
        }
    }

    private var primaryTitle: String {
        switch engine.phase {
        case .running: return "暂停"
        case .paused: return "继续专注"
        case .finished: return "再来一轮"
        case .idle: return "开始专注"
        }
    }

    // MARK: 页脚

    private var footer: some View {
        HStack {
            Spacer()
            if model.todayCount > 0 {
                Text("今日完成 \(model.todayCount)")
                    .font(Typography.caption)
                    .foregroundStyle(FocusTheme.textTertiary)
            }
        }
        .frame(height: 16)
    }
}

// MARK: - 状态标签

struct StatusPill: View {
    @ObservedObject private var appTypography = TypographySettings.shared
    let phase: TimerPhase

    private var color: Color {
        switch phase {
        case .running, .finished: return FocusTheme.ink
        case .paused: return FocusTheme.textSecondary
        case .idle: return FocusTheme.textTertiary
        }
    }

    private var label: String {
        switch phase {
        case .running: return "专注中"
        case .paused: return "已暂停"
        case .finished: return "已完成"
        case .idle: return "准备开始"
        }
    }

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(color)
                .frame(width: 6, height: 6)
            Text(label)
                .font(.hebiuSystem(size: 11, weight: .medium, design: .default))
                .foregroundStyle(FocusTheme.textSecondary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(Capsule(style: .continuous).fill(FocusTheme.surface))
        .overlay(Capsule(style: .continuous).strokeBorder(FocusTheme.stroke, lineWidth: 1))
    }
}

// MARK: - 时长按钮

struct DurationChip: View {
    @ObservedObject private var appTypography = TypographySettings.shared
    let title: String
    let unit: String
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(title)
                    .font(.hebiuSystem(size: 13, weight: .semibold, design: .default))
                Text(unit)
                    .font(.hebiuSystem(size: 9.5, weight: .medium, design: .default))
                    .opacity(0.7)
            }
            .foregroundStyle(selected ? FocusTheme.ink : FocusTheme.textSecondary)
            .frame(width: 48, height: 32)
            .background(
                Capsule(style: .continuous)
                    .fill(selected ? FocusTheme.ink.opacity(0.13) : FocusTheme.surface)
            )
            .overlay(
                Capsule(style: .continuous)
                    .strokeBorder(
                        selected ? FocusTheme.ink.opacity(0.34) : FocusTheme.stroke,
                        lineWidth: 1
                    )
            )
        }
        .buttonStyle(.plain)
        .help("专注 \(title) 分钟")
    }
}

// MARK: - 自定义时长弹窗

struct CustomDurationEditor: View {
    @ObservedObject private var appTypography = TypographySettings.shared
    @ObservedObject var model: FocusModel
    @State private var draft: String
    @FocusState private var fieldFocused: Bool

    init(model: FocusModel) {
        self.model = model
        _draft = State(initialValue: "\(model.durationMinutes)")
    }

    private var parsedMinutes: Int {
        min(max(Int(draft) ?? model.durationMinutes, 1), 180)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 15) {
            VStack(alignment: .leading, spacing: 4) {
                Text("自定义专注时长")
                    .font(.hebiuSystem(size: 15, weight: .semibold, design: .default))
                    .foregroundStyle(FocusTheme.textPrimary)
                Text("1–180 分钟，适合更长的深度工作")
                    .font(Typography.caption)
                    .foregroundStyle(FocusTheme.textTertiary)
            }

            HStack(spacing: 10) {
                stepButton(systemName: "minus", step: -5)

                HStack(spacing: 5) {
                    TextField("25", text: $draft)
                        #if os(iOS)
                        .keyboardType(.numberPad)
                        #endif
                        .textFieldStyle(.plain)
                        .font(.hebiuSystem(size: 23, weight: .semibold, design: .default))
                        .foregroundStyle(FocusTheme.textPrimary)
                        .multilineTextAlignment(.center)
                        .focused($fieldFocused)
                        .frame(width: 60, height: 40)
                        .onChange(of: draft) { _, newValue in
                            let digits = String(newValue.filter(\.isNumber).prefix(3))
                            if digits != newValue { draft = digits }
                        }
                    Text("分钟")
                        .font(.hebiuSystem(size: 12, weight: .medium, design: .default))
                        .foregroundStyle(FocusTheme.textSecondary)
                }
                .padding(.horizontal, 8)
                .background(
                    RoundedRectangle(cornerRadius: 11, style: .continuous)
                        .fill(FocusTheme.surfaceStrong)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 11, style: .continuous)
                        .strokeBorder(fieldFocused ? FocusTheme.ink.opacity(0.5) : FocusTheme.stroke, lineWidth: 1)
                )

                stepButton(systemName: "plus", step: 5)
            }
            .frame(maxWidth: .infinity, alignment: .center)

            HStack(spacing: 10) {
                Spacer()
                Button("取消") {
                    model.cancelCustomEditor()
                }
                .buttonStyle(.plain)
                .font(Typography.chip)
                .foregroundStyle(FocusTheme.textSecondary)
                .keyboardShortcut(.cancelAction)

                Button {
                    model.customMinutes = parsedMinutes
                    model.applyCustomDuration()
                } label: {
                    // 单色主题下按钮底是墨色（深色模式为白），文字必须用底色，否则白字白底
                    Text("确定").foregroundStyle(Color.white)
                }
                .buttonStyle(.borderedProminent)
                .tint(FocusTheme.ink)
                .font(Typography.chip)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        #if os(macOS)
        .frame(width: 292)
        .background(FocusTheme.canvas)
        #else
        .frame(maxWidth: .infinity, maxHeight: .infinity) // iPhone 上作为 sheet 铺满
        .background(FocusTheme.canvas)
        #endif
        .onAppear { fieldFocused = true }
    }

    private func stepButton(systemName: String, step: Int) -> some View {
        Button {
            let next = min(max(parsedMinutes + step, 1), 180)
            draft = "\(next)"
        } label: {
            Image(systemName: systemName)
                .font(.hebiuSystem(size: 11, weight: .bold))
                .foregroundStyle(FocusTheme.textSecondary)
                .frame(width: 30, height: 30)
                .background(Circle().fill(FocusTheme.surface))
                .overlay(Circle().strokeBorder(FocusTheme.stroke, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }
}
