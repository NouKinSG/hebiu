import AppKit
import Combine
import HebiuKit
import SwiftUI

/// Shared by SwiftUI views and AppKit bubbles. Stored with Hebiu's other local data.
final class TypographySettings: ObservableObject {
    static let shared = TypographySettings()
    static let families = NSFontManager.shared.availableFontFamilies
        .filter { !$0.hasPrefix(".") }.sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    static let scaleRange = 0.85...1.25

    private struct Preferences: Codable { var family: String; var scale: Double }
    private let url: URL
    @Published var family: String {
        didSet {
            if !family.isEmpty && !Self.families.contains(family) { family = ""; return }
            save()
        }
    }
    @Published var scale: Double {
        didSet {
            let valid = Self.validScale(scale)
            if scale != valid { scale = valid; return }
            save()
        }
    }
    @Published private(set) var saveError: String?

    init(url: URL = Paths.dataDir.appendingPathComponent("typography.json")) {
        self.url = url
        let saved = (try? Data(contentsOf: url)).flatMap { try? JSONDecoder().decode(Preferences.self, from: $0) }
        family = saved.map { Self.families.contains($0.family) ? $0.family : "" } ?? ""
        scale = Self.validScale(saved?.scale ?? 1)
    }
    private static func validScale(_ value: Double) -> Double {
        value.isFinite ? min(max(value, scaleRange.lowerBound), scaleRange.upperBound) : 1
    }
    private func save() {
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try JSONEncoder().encode(Preferences(family: family, scale: scale)).write(to: url, options: .atomic)
            saveError = nil
        } catch { saveError = "字体设置暂未保存，请检查数据文件夹是否可写。" }
    }
    func reset() { family = ""; scale = 1 }
    func font(size: CGFloat, weight: Font.Weight = .regular, design: Font.Design = .default) -> Font {
        let points = size * scale
        guard !family.isEmpty else { return .system(size: points, weight: weight, design: design) }
        return .custom(family, fixedSize: points).weight(weight)
    }
    func nsFont(size: CGFloat, weight: NSFont.Weight = .regular) -> NSFont {
        let points = size * scale
        guard !family.isEmpty, let base = NSFontManager.shared.font(withFamily: family, traits: [], weight: 5, size: points) else {
            return .systemFont(ofSize: points, weight: weight)
        }
        let descriptor = base.fontDescriptor.addingAttributes([.traits: [NSFontDescriptor.TraitKey.weight: weight.rawValue]])
        return NSFont(descriptor: descriptor, size: points) ?? base
    }
}

extension Font {
    static func hebiuSystem(size: CGFloat, weight: Font.Weight = .regular, design: Font.Design = .default) -> Font {
        TypographySettings.shared.font(size: size, weight: weight, design: design)
    }
    static func hebiuStyle(_ style: Font.TextStyle) -> Font {
        let size: CGFloat
        let weight: Font.Weight
        switch style {
        case .largeTitle: size = 34; weight = .regular
        case .title: size = 28; weight = .regular
        case .title2: size = 22; weight = .regular
        case .title3: size = 20; weight = .regular
        case .headline: size = 13; weight = .semibold
        case .subheadline, .callout: size = 12; weight = .regular
        case .footnote, .caption: size = 10; weight = .regular
        case .caption2: size = 10; weight = .regular
        default: size = 13; weight = .regular
        }
        return .hebiuSystem(size: size, weight: weight)
    }
}

struct TypographySettingsSection: View {
    @ObservedObject private var typography = TypographySettings.shared
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionLabel(text: "字体")
            Card {
                VStack(alignment: .leading, spacing: 12) {
                    SettingRow(title: "字体", detail: "用于主窗口、专注页和桌宠气泡；系统图标保持原样") {
                        Picker("字体", selection: $typography.family) {
                            Text("系统默认").tag("")
                            ForEach(TypographySettings.families, id: \.self) { family in Text(family).tag(family) }
                        }
                        .labelsHidden().frame(width: 200)
                    }
                    Divider()
                    SettingRow(title: "字号", detail: "按原字号比例调整，计时数字保持等宽") {
                        HStack(spacing: 10) {
                            Slider(value: $typography.scale, in: TypographySettings.scaleRange, step: 0.05)
                                .accessibilityLabel("字号比例").frame(width: 145)
                            Text("\(Int((typography.scale * 100).rounded()))%")
                                .monospacedDigit().frame(width: 48, alignment: .trailing)
                        }
                    }
                    Divider()
                    Text("把今天最重要的事做完 · Focus on yourself")
                        .font(.hebiuSystem(size: 15)).fixedSize(horizontal: false, vertical: true)
                        .accessibilityLabel("字体预览：把今天最重要的事做完")
                    HStack {
                        Text("Aa 你好 0123456789").font(.hebiuSystem(size: 13)).foregroundStyle(.secondary)
                        Spacer()
                        Button("恢复默认字体") { typography.reset() }
                    }
                    if let error = typography.saveError { Text(error).font(.hebiuStyle(.caption)).foregroundStyle(Theme.overdue) }
                }
            }
        }
    }
}
