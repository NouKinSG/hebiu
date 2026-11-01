import HebiuKit

import AppKit
import SwiftUI
import FocusCore

/// 桌宠、菜单栏、主页卡片和专注页共用的计时控制器。
@preconcurrency @MainActor
final class IntegratedFocusController: ObservableObject {
    enum Event {
        case started
        case completed(FocusCore.FocusSession, recovered: Bool)
        case restDone
    }
    let model: FocusModel
    private let defaults: UserDefaults
    var breakMinutes: () -> Int = { 0 }
    var onEvent: ((Event) throws -> Void)?
    @Published private(set) var deliveryError: String?
    private var nextDeliveryRetry = Date.distantPast
    var onRestDone: (() -> Void)?
    @Published var restEnd: Date? {
        didSet {
            if let restEnd { defaults.set(restEnd, forKey: "foy.restEnd") }
            else { defaults.removeObject(forKey: "foy.restEnd") }
        }
    }
    init(model: FocusModel? = nil) {
        let m = model ?? FocusModel(defaults: FocusModel.defaultDefaults)
        self.model = m
        self.defaults = m.integrationDefaults
        self.restEnd = defaults.object(forKey: "foy.restEnd") as? Date
        if m.engine.isRunning || m.engine.phase == .paused {
            self.restEnd = nil
            defaults.removeObject(forKey: "foy.restEnd")
            defaults.removeObject(forKey: "foy.pendingRestDone")
        }
        m.onStart = { [weak self] in
            self?.cancelRest()
            try? self?.onEvent?(.started)
        }
        m.onReset = { [weak self] in self?.cancelRest() }
        m.onSessionCompleted = { [weak self] session in
            guard let self, let event = self.model.pendingCompletions.first(where: { $0.session.id == session.id }) else { return }
            self.complete(event)
        }
    }
    var isFocusing: Bool { model.engine.isRunning }
    var menuTitle: String {
        if let restEnd { return " 休息 " + clock(max(0, restEnd.timeIntervalSince(model.engine.now()))) }
        switch model.engine.phase {
        case .running: return " " + model.engine.formattedTime
        case .paused: return " 暂停 " + model.engine.formattedTime
        default: return ""
        }
    }
    func start(minutes: Int) {
        restEnd = nil
        model.setMode(.countdown)
        model.selectPreset(minutes: minutes)
        model.startPause()
    }
    func stop() { model.reset() }
    func tick() {
        // 下游统计成功落盘前保留事件，连续崩溃后仍可重试。
        if model.engine.now() >= nextDeliveryRetry {
            for event in model.pendingCompletions { complete(event) }
        }
        model.tick()
        if let end = restEnd, model.engine.now() >= end {
            defaults.set(true, forKey: "foy.pendingRestDone")
            restEnd = nil
        }
        if defaults.bool(forKey: "foy.pendingRestDone"), onEvent != nil || onRestDone != nil {
            do {
                try onEvent?(.restDone)
                onRestDone?()
                defaults.removeObject(forKey: "foy.pendingRestDone")
            } catch { deliveryError = "休息提醒暂未送达，会自动重试。" }
        }
    }
    private func cancelRest() {
        restEnd = nil
        model.cancelPendingBreaks()
        defaults.removeObject(forKey: "foy.pendingRestDone")
    }
    private func complete(_ event: FocusModel.CompletionNotice) {
        guard let onEvent else { return }
        let session = event.session
        let minutes = max(0, min(30, breakMinutes()))
        // 旧完成事件不能覆盖新计时或显式重置。
        if !event.breakCancelled && !model.engine.isRunning && model.engine.phase != .paused, minutes > 0 {
            let end = session.endedAt.addingTimeInterval(Double(minutes) * 60)
            if end > model.engine.now() { restEnd = end }
        }
        do {
            try onEvent(.completed(session, recovered: event.recovered))
            model.acknowledgeCompletion(session.id)
            deliveryError = nil
        } catch {
            nextDeliveryRetry = model.engine.now().addingTimeInterval(5)
            deliveryError = "专注统计暂未保存，完成事件已保留，会自动重试。"
        }
    }
    private func clock(_ seconds: Double) -> String {
        let n = Int(seconds.rounded(.up))
        return String(format: "%d:%02d", n / 60, n % 60)
    }
}

struct IntegratedFocusPage: View {
    @ObservedObject private var appTypography = TypographySettings.shared
    @ObservedObject var focus: IntegratedFocusController
    @ObservedObject var model: FocusModel
    init(focus: IntegratedFocusController) { self.focus = focus; self.model = focus.model }
    var body: some View {
        GeometryReader { geometry in
            ScrollView([.horizontal, .vertical]) {
                Group {
                    if geometry.size.width >= 820 {
                        HStack(alignment: .top, spacing: 0) {
                            TimerPanel(model: model).frame(width: 460, height: 680)
                            if model.isDashboardVisible {
                                Divider().frame(height: 680)
                                DashboardView(model: model)
                            }
                        }
                    } else {
                        VStack(spacing: 0) {
                            TimerPanel(model: model).frame(width: 460, height: 680)
                            if model.isDashboardVisible {
                                Divider().frame(width: 460)
                                DashboardView(model: model)
                            }
                        }
                    }
                }
                .frame(minWidth: geometry.size.width, alignment: .center)
            }
        }
        .background(FocusTheme.canvas)
        .overlay(alignment: .top) {
            if let error = model.persistenceError ?? focus.deliveryError {
                Label(error, systemImage: "exclamationmark.triangle")
                    .font(.hebiuStyle(.callout)).padding(10)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10)).padding(8)
            }
        }
        .overlay(alignment: .bottom) {
            if let end = focus.restEnd {
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    HStack {
                        Image(systemName: "cup.and.saucer")
                        Text("休息中 · " + HebiuKit.FocusClock.clock(max(0, end.timeIntervalSince(context.date))))
                        Button("跳过休息") { focus.restEnd = nil }
                    }
                    .padding(12)
                    .background(.regularMaterial, in: Capsule())
                    .padding(12)
                }
            }
        }
    }
}

struct IntegratedFocusCard: View {
    @ObservedObject private var appTypography = TypographySettings.shared
    @ObservedObject var focus: IntegratedFocusController
    let open: () -> Void
    var body: some View { FocusSummary(model: focus.model, focus: focus, open: open) }
}

private struct FocusSummary: View {
    @ObservedObject private var appTypography = TypographySettings.shared
    @ObservedObject var model: FocusModel
    @ObservedObject var focus: IntegratedFocusController
    let open: () -> Void
    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { _ in
            Card {
                HStack {
                    VStack(alignment: .leading, spacing: 6) {
                        Label("专注", systemImage: "timer").font(.hebiuStyle(.headline))
                        Text(model.focusTitle.isEmpty ? "留一段时间，做最重要的事" : model.focusTitle)
                            .font(.hebiuStyle(.callout)).foregroundStyle(.secondary).lineLimit(1)
                        Text(focus.menuTitle.isEmpty ? "今日完成 \(model.todayCount) 轮" : focus.menuTitle.trimmingCharacters(in: .whitespaces))
                            .monospacedDigit().foregroundStyle(Theme.accent)
                    }
                    Spacer()
                    Button("打开专注", action: open).buttonStyle(.bordered)
                    Button(model.engine.isRunning ? "暂停" : model.engine.phase == .paused ? "继续" : "开始") { model.startPause() }
                        .buttonStyle(.borderedProminent)
                }
            }
        }
    }
}
