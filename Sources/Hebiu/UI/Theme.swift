import AppKit
import ImageIO
import SwiftUI

/// 全局只用一个强调色（她的粉），其余都是系统的黑白灰
enum Theme {
    static let accent = Color(red: 0.93, green: 0.36, blue: 0.52)
    static let overdue = Color(red: 0.86, green: 0.30, blue: 0.26)
    static let radius: CGFloat = 12
    static let pagePadding: CGFloat = 28
    static let contentWidth: CGFloat = 640
}

/// 每一页统一的外框：大标题 + 一行说明 + 内容，内容最宽 640，居中
struct Page<Content: View>: View {
    let title: String
    var subtitle: String? = nil
    var trailing: AnyView? = nil
    @ViewBuilder let content: Content

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(title).font(.system(size: 26, weight: .bold))
                        if let subtitle {
                            Text(subtitle).font(.callout).foregroundStyle(.secondary)
                        }
                    }
                    Spacer()
                    if let trailing { trailing }
                }
                content
            }
            .frame(maxWidth: Theme.contentWidth, alignment: .leading)
            .padding(Theme.pagePadding)
            .frame(maxWidth: .infinity)
        }
    }
}

/// 卡片：浅一层的底 + 细边，把一组东西收在一起
struct Card<Content: View>: View {
    var padding: CGFloat = 16
    @ViewBuilder let content: Content

    var body: some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: Theme.radius).fill(Color(nsColor: .controlBackgroundColor)))
            .overlay(RoundedRectangle(cornerRadius: Theme.radius).stroke(Color(nsColor: .separatorColor).opacity(0.6)))
    }
}

/// 卡片上方的小标题
struct SectionLabel: View {
    let text: String
    var trailing: String? = nil

    var body: some View {
        HStack {
            Text(text).font(.system(size: 12, weight: .semibold)).foregroundStyle(.secondary)
            Spacer()
            if let trailing {
                Text(trailing).font(.system(size: 12)).foregroundStyle(.secondary).monospacedDigit()
            }
        }
        .padding(.horizontal, 4)
    }
}

/// 卡片里的一行设置：左边标题和说明，右边控件
struct SettingRow<Control: View>: View {
    let title: String
    var detail: String? = nil
    /// 上一行开关下面的子选项：缩进、字小一号
    var sub = false
    @ViewBuilder let control: Control

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(sub ? .callout : .body).foregroundStyle(sub ? Color.secondary : Color.primary)
                if let detail {
                    Text(detail).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 16)
            control
        }
        .padding(.vertical, 2)
        .padding(.leading, sub ? 16 : 0)
    }
}

/// 形象包里某一帧的缩略图（缩到 256 像素），读一次后缓存；没有这一帧就用平时那一帧。
/// 只存缩略图：29 张原图（768 像素）全解码要 70 MB，缩略图不到 8 MB
enum PetImages {
    private static var cache: [String: NSImage] = [:]

    static func clear() { cache = [:] }

    static func image(_ frame: String) -> NSImage? {
        if let hit = cache[frame] { return hit }
        guard let dir = Character.framesDir else { return nil }
        let candidates = [frame, Character.pack.idle.frame].flatMap { name in ["webp", "png"].map { dir.appendingPathComponent("\(name).\($0)") } }
        guard let url = candidates.first(where: { FileManager.default.fileExists(atPath: $0.path) }),
              let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let thumb = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                  kCGImageSourceCreateThumbnailFromImageAlways: true,
                  kCGImageSourceThumbnailMaxPixelSize: 256,
              ] as CFDictionary) else { return nil }
        let image = NSImage(cgImage: thumb, size: NSSize(width: 128, height: 128))
        cache[frame] = image
        return image
    }
}

struct PetThumb: View {
    let frame: String
    var size: CGFloat = 72

    var body: some View {
        Group {
            if let image = PetImages.image(frame) {
                Image(nsImage: image).resizable().interpolation(.high).aspectRatio(contentMode: .fit)
            } else {
                Image(systemName: "leaf.fill").foregroundStyle(Theme.accent)
            }
        }
        .frame(width: size, height: size)
    }
}
