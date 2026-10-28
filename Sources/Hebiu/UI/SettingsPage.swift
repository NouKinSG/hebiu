import AppKit
import HebiuKit
import SwiftUI

/// 设置：只放「设一次就不管」的东西
struct SettingsPage: View {
    @ObservedObject var model: SettingsModel

    private var showDetail: String {
        switch model.showMode {
        case .everywhere: return "一直在桌面上"
        case .apps: return "只在勾选的 App 在最前面时出来；打开 hebiu 自己的窗口时也在"
        case .popup: return "平时藏起来，只在下面勾的事情发生时出来；打开 hebiu 自己的窗口时也在"
        }
    }

    var body: some View {
        Page(title: "设置", subtitle: "改完自动保存") {
            group("\(Her.she)在桌面上") {
                SettingRow(title: "形象", detail: (model.characters.first { $0.id == model.character }?.summary).map { $0.isEmpty ? "自己做形象：看项目里的 docs/CHARACTERS.md" : $0 }) {
                    Picker("", selection: $model.character) {
                        ForEach(model.characters, id: \.id) { c in Text(c.name == c.id ? c.name : "\(c.name)（\(c.id)）").tag(c.id) }
                    }
                    .labelsHidden().fixedSize()
                }
                Divider()
                SettingRow(title: "显示\(Her.she)") {
                    Toggle("", isOn: Binding(get: { !model.petHidden }, set: { model.petHidden = !$0 })).labelsHidden().toggleStyle(.switch)
                }
                Divider()
                SettingRow(title: "在哪显示", detail: showDetail) {
                    Picker("", selection: $model.showMode) {
                        Text("任何地方").tag(ShowIn.Mode.everywhere)
                        Text("选中的 App").tag(ShowIn.Mode.apps)
                        Text("平时不显示").tag(ShowIn.Mode.popup)
                    }
                    .labelsHidden().pickerStyle(.segmented).frame(width: 300)
                }
                if model.showMode == .apps {
                    AppPicker(selected: $model.showApps).padding(.leading, 16)
                }
                if model.showMode != .everywhere {
                    SettingRow(title: "藏起来时在屏幕边露个头", detail: "滑到最近的左右屏幕边，只露一小半；点\(Her.she)就出来一会儿", sub: true) {
                        Toggle("", isOn: $model.peek).labelsHidden().toggleStyle(.switch)
                    }
                    .padding(.leading, 16)
                    VStack(alignment: .leading, spacing: 6) {
                        Text("不显示的时候，这些事也让\(Her.she)出来").font(.callout).foregroundStyle(.secondary)
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 8)], alignment: .leading, spacing: 6) {
                            ForEach(ShowIn.PopKind.allCases, id: \.self) { kind in
                                Toggle(kind.title + (kind.waitsForClick ? "" : "（露几秒）"), isOn: Binding(
                                    get: { model.popKinds.contains(kind) },
                                    set: { if $0 { model.popKinds.insert(kind) } else { model.popKinds.remove(kind) } }))
                                    .toggleStyle(.checkbox)
                            }
                        }
                        Text("提醒类的会等你点\(Her.she)一下再回去").font(.caption).foregroundStyle(.secondary)
                    }
                    .padding(.leading, 16)
                }
                Divider()
                SettingRow(title: "跟着鼠标看你", detail: "闲着时身子往鼠标那边歪一点") {
                    Toggle("", isOn: $model.followCursor).labelsHidden().toggleStyle(.switch)
                }
                Divider()
                SettingRow(title: "闲着会睡觉", detail: "你不动电脑一会儿\(Her.she)就打瞌睡，动一下鼠标\(Her.she)会吓一跳醒来") {
                    Picker("", selection: $model.sleepMinutes) {
                        Text("不睡").tag(0)
                        ForEach([1, 2, 5, 10], id: \.self) { Text("\($0) 分钟后").tag($0) }
                    }
                    .labelsHidden().fixedSize()
                }
                Divider()
                SettingRow(title: "大小") {
                    Picker("", selection: $model.side) {
                        Text("小").tag(CGFloat(160))
                        Text("中").tag(CGFloat(220))
                        Text("大").tag(CGFloat(300))
                    }
                    .labelsHidden().pickerStyle(.segmented).frame(width: 180)
                }
                Divider()
                SettingRow(title: "位置", detail: "拖动\(Her.she)就能换位置，会记住") {
                    Button("回到右下角") { model.resetPetPosition() }
                }
            }

            group("说话") {
                SettingRow(title: "\(Her.she)说话", detail: "关掉后不弹任何气泡，动作照做；待办到点的提醒还会弹") {
                    Toggle("", isOn: $model.talk).labelsHidden().toggleStyle(.switch)
                }
                Divider()
                SettingRow(title: "点\(Her.she)时说话频率", detail: "平时只做表情，偶尔冒一句；连戳\(Her.she)时的「别戳啦」每次都说") {
                    Picker("", selection: $model.tapTalkEvery) {
                        Text("不说话").tag(0)
                        Text("大约 10 次说一句").tag(10)
                        Text("大约 5 次说一句").tag(5)
                        Text("大约 3 次说一句").tag(3)
                        Text("每次都说").tag(1)
                        if ![0, 1, 3, 5, 10].contains(model.tapTalkEvery) {
                            Text("大约 \(model.tapTalkEvery) 次说一句").tag(model.tapTalkEvery)
                        }
                    }
                    .labelsHidden().fixedSize()
                }
                Divider()
                SettingRow(title: "\(Her.she)提到你时说", detail: "写进给 AI 的话里，比如「TA 今天的待办」；影响\(Her.she)写日记、记住你时用的字") {
                    Picker("", selection: $model.userPronoun) {
                        Text("TA").tag("TA")
                        Text("他").tag("他")
                        Text("她").tag("她")
                        if !["TA", "他", "她"].contains(model.userPronoun) { Text(model.userPronoun).tag(model.userPronoun) }
                    }
                    .labelsHidden().fixedSize()
                }
            }

            group("打扰") {
                SettingRow(title: "勿扰模式", detail: "只在你点\(Her.she)时有反应；Claude 的动静和陪伴提醒都不打扰，待办到点照样提醒") {
                    Toggle("", isOn: $model.quiet).labelsHidden().toggleStyle(.switch)
                }
                Divider()
                SettingRow(title: "安静时段", detail: QuietHours(model.quietHours) == nil && !model.quietHours.isEmpty
                           ? "没认出来，写成 12:00-13:30, 22:30-08:00"
                           : "每天这些时间自动勿扰，比如午休、开会；可以写几段，用逗号隔开") {
                    TextField("如 12:00-13:30", text: $model.quietHours).frame(width: 200).multilineTextAlignment(.trailing)
                }
            }

            group("陪伴提醒") {
                SettingRow(title: "休息提醒", detail: "Claude 连续有动静这么久后鼓嘴提醒；中间停 15 分钟算休息过") {
                    Toggle("", isOn: $model.restOn).labelsHidden().toggleStyle(.switch)
                }
                if model.restOn {
                    SettingRow(title: "连续忙多久", sub: true) {
                        Stepper("\(model.restMinutes) 分钟", value: $model.restMinutes, in: 30...300, step: 15).fixedSize()
                    }
                }
                Divider()
                SettingRow(title: "深夜提醒", detail: "到凌晨 5 点为止，还在用 Claude 时每小时最多一次") {
                    Toggle("", isOn: $model.nightOn).labelsHidden().toggleStyle(.switch)
                }
                if model.nightOn {
                    SettingRow(title: "几点以后", sub: true) {
                        Picker("", selection: $model.nightHour) {
                            ForEach(21...23, id: \.self) { Text("晚上 \($0) 点").tag($0) }
                        }
                        .labelsHidden().fixedSize()
                    }
                }
                Divider()
                SettingRow(title: "番茄钟", detail: "在主页开始；专心时\(Her.she)不催休息、Claude 的动静只做动作不说话") {
                    HStack(spacing: 12) {
                        Stepper("专心 \(model.focusMinutes) 分钟", value: $model.focusMinutes, in: 5...120, step: 5).fixedSize()
                        Stepper("休息 \(model.breakMinutes) 分钟", value: $model.breakMinutes, in: 0...30, step: 1).fixedSize()
                    }
                }
                Divider()
                SettingRow(title: "天气", detail: "填城市后，主页显示天气，早报里提醒带伞、多穿；只把城市名发给 Open-Meteo（免费天气服务，不用账号）。空着就不查") {
                    TextField("如 上海", text: $model.weatherCity).frame(width: 120).multilineTextAlignment(.trailing)
                }
                Divider()
                SettingRow(title: "晚上问问心情", detail: "到点了今天还没记心情，\(Her.she)问一句") {
                    Picker("", selection: $model.moodAskHour) {
                        Text("不问").tag(0)
                        ForEach(19...23, id: \.self) { Text("晚上 \($0) 点").tag($0) }
                    }
                    .labelsHidden().fixedSize()
                }
                Divider()
                HStack {
                    Spacer()
                    Button("试试休息提醒") { model.tryOut("rest") }
                    Button("试试深夜提醒") { model.tryOut("night") }
                }
                .controlSize(.small)
            }

            group("待办提醒") {
                SettingRow(title: "早上汇总", detail: "每天第一次用电脑时（6 点以后）说说今天有哪些事") {
                    Toggle("", isOn: $model.morningSummary).labelsHidden().toggleStyle(.switch)
                }
                Divider()
                SettingRow(title: "下班前提醒", detail: "到这个时间今天还有没做完的，提醒一次") {
                    Toggle("", isOn: $model.eveningOn).labelsHidden().toggleStyle(.switch)
                }
                if model.eveningOn {
                    SettingRow(title: "几点提醒", sub: true) {
                        DatePicker("", selection: $model.eveningTime, displayedComponents: .hourAndMinute).labelsHidden()
                    }
                }
                Divider()
                SettingRow(title: "到点时也发系统通知", detail: "屏幕角落被挡住、人不在电脑前也不会错过") {
                    Toggle("", isOn: $model.notify).labelsHidden().toggleStyle(.switch)
                }
            }

            group("其他") {
                SettingRow(title: "开机自动启动") {
                    Toggle("", isOn: $model.launchAtLogin).labelsHidden().toggleStyle(.switch)
                }
                Divider()
                SettingRow(title: "数据文件夹", detail: "待办、台词和设置都在 ~/.hebiu，可以直接改、直接备份") {
                    Button("在访达中打开") { NSWorkspace.shared.open(Paths.dataDir) }
                }
                Divider()
                SettingRow(title: "版本") {
                    Text(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "dev")
                        .foregroundStyle(.secondary).monospacedDigit()
                }
            }
        }
    }

    private func group<Content: View>(_ title: String, @ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionLabel(text: title)
            Card { VStack(spacing: 10) { content() } }
        }
    }
}

/// 选 App：正开着的 + 已经选过的，带图标，可多选
struct AppPicker: View {
    @Binding var selected: Set<String>

    private struct App: Identifiable {
        let id: String
        let name: String
        let icon: NSImage?
    }

    var body: some View {
        let apps = candidates()
        VStack(alignment: .leading, spacing: 6) {
            if selected.isEmpty {
                Text("还没选：一个都不选时平时哪里都不显示，只在下面勾的事情发生时出来").font(.caption).foregroundStyle(Theme.overdue)
            }
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 170), spacing: 8)], alignment: .leading, spacing: 6) {
                ForEach(apps) { app in
                    Toggle(isOn: Binding(get: { selected.contains(app.id) },
                                         set: { if $0 { selected.insert(app.id) } else { selected.remove(app.id) } })) {
                        HStack(spacing: 6) {
                            if let icon = app.icon { Image(nsImage: icon).resizable().frame(width: 18, height: 18) }
                            Text(app.name).lineLimit(1)
                        }
                    }
                    .toggleStyle(.checkbox)
                }
            }
            Text("列表里是现在开着的 App；想要的没在里面，先把它打开再回来勾").font(.caption).foregroundStyle(.secondary)
        }
    }

    private func candidates() -> [App] {
        let own = Bundle.main.bundleIdentifier
        var ids = Set(NSWorkspace.shared.runningApplications.filter { $0.activationPolicy == .regular }.compactMap(\.bundleIdentifier))
        ids.formUnion(selected)
        ids.remove(own ?? "")
        return ids.compactMap { id -> App? in
            guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id) else {
                return selected.contains(id) ? App(id: id, name: id, icon: nil) : nil
            }
            let name = FileManager.default.displayName(atPath: url.path).replacingOccurrences(of: ".app", with: "")
            return App(id: id, name: name, icon: NSWorkspace.shared.icon(forFile: url.path))
        }
        .sorted { (selected.contains($0.id) ? 0 : 1, $0.name) < (selected.contains($1.id) ? 0 : 1, $1.name) }
    }
}
