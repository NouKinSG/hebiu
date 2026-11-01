import AppKit
import HebiuKit
import ImageIO
import SwiftUI

/// 在她旁边弹一张拍立得样子的合照：淡入、停几秒、淡出；点一下就收起
final class PhotoPopup {
    private var panel: NSPanel?
    private var hideWork: DispatchWorkItem?
    static let side: CGFloat = 300

    func show(_ url: URL, near anchor: NSRect) {
        guard let image = PhotoPopup.thumbnail(url, maxPixel: Int(PhotoPopup.side * 2)) else {
            Log.write("photo unreadable: \(url.lastPathComponent)")
            return
        }
        hide(animated: false)
        let caption = PhotoAlbum.date(of: url).map(PhotoPopup.dateText) ?? ""
        let view = PolaroidView(image: image, caption: caption) { [weak self] in self?.hide(animated: true) }
        let host = NSHostingView(rootView: view)
        let size = host.fittingSize
        let p = NSPanel(contentRect: NSRect(origin: .zero, size: size), styleMask: [.borderless, .nonactivatingPanel],
                        backing: .buffered, defer: false)
        p.isOpaque = false
        p.backgroundColor = .clear
        p.hasShadow = false
        p.level = .floating
        p.collectionBehavior = [.canJoinAllSpaces, .stationary]
        p.contentView = host
        p.setFrameOrigin(PhotoPopup.origin(size: size, anchor: anchor))
        p.alphaValue = 0
        p.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { $0.duration = 0.35; p.animator().alphaValue = 1 }
        panel = p
        let work = DispatchWorkItem { [weak self] in self?.hide(animated: true) }
        hideWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 8, execute: work)
    }

    func hide(animated: Bool) {
        hideWork?.cancel()
        guard let p = panel else { return }
        panel = nil
        guard animated else { p.orderOut(nil); return }
        NSAnimationContext.runAnimationGroup({ $0.duration = 0.4; p.animator().alphaValue = 0 }, completionHandler: { p.orderOut(nil) })
    }

    /// 放在她左上方；放不下就换到右边，始终留在屏幕里
    private static func origin(size: NSSize, anchor: NSRect) -> NSPoint {
        let screen = NSScreen.screens.first { $0.frame.intersects(anchor) }?.visibleFrame ?? NSScreen.main?.visibleFrame ?? .zero
        var x = anchor.minX - size.width + anchor.width * 0.25
        if x < screen.minX + 8 { x = anchor.maxX - anchor.width * 0.25 }
        var y = anchor.midY - size.height * 0.2
        x = min(max(x, screen.minX + 8), screen.maxX - size.width - 8)
        y = min(max(y, screen.minY + 8), screen.maxY - size.height - 8)
        return NSPoint(x: x, y: y)
    }

    /// 大照片先缩小再显示，几十 MB 的原图也不占内存
    static func thumbnail(_ url: URL, maxPixel: Int) -> NSImage? {
        guard let src = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        let opts: [CFString: Any] = [kCGImageSourceCreateThumbnailFromImageAlways: true,
                                     kCGImageSourceCreateThumbnailWithTransform: true,
                                     kCGImageSourceThumbnailMaxPixelSize: maxPixel]
        guard let cg = CGImageSourceCreateThumbnailAtIndex(src, 0, opts as CFDictionary) else { return nil }
        return NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height))
    }

    static func dateText(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_CN")
        f.dateFormat = "yyyy 年 M 月 d 日"
        return f.string(from: date)
    }
}

private struct PolaroidView: View {
    @ObservedObject private var appTypography = TypographySettings.shared
    let image: NSImage
    let caption: String
    let onTap: () -> Void

    var body: some View {
        let side = PhotoPopup.side
        VStack(spacing: 10) {
            Image(nsImage: image)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(width: side, height: side)
                .clipped()
            Text(caption.isEmpty ? "♥" : caption)
                .font(.hebiuSystem(size: 13, weight: .medium, design: .rounded))
                .foregroundStyle(Color(red: 0.42, green: 0.36, blue: 0.38))
                .padding(.bottom, 4)
        }
        .padding(EdgeInsets(top: 12, leading: 12, bottom: 12, trailing: 12))
        .background(RoundedRectangle(cornerRadius: 6).fill(Color(red: 1, green: 0.992, blue: 0.976)))
        .shadow(color: .black.opacity(0.22), radius: 16, y: 8)
        .rotationEffect(.degrees(-3))
        .padding(28)       // 给阴影和旋转留地方
        .contentShape(Rectangle())
        .onTapGesture(perform: onTap)
    }
}
