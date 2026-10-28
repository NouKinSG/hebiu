import HebiuKit
import AppKit
import ImageIO

/// 一帧画面：按显示尺寸缩放后的图 + 一张低分辨率的不透明区域图（判断点击是否落在人物身上）
struct Frame {
    let image: CGImage
    let mask: [UInt8]
    static let maskSide = 96

    func isOpaque(atUnit p: CGPoint) -> Bool {
        let x = Int(p.x * CGFloat(Frame.maskSide)), y = Int((1 - p.y) * CGFloat(Frame.maskSide))
        guard x >= 0, y >= 0, x < Frame.maskSide, y < Frame.maskSide else { return false }
        return mask[y * Frame.maskSide + x] > 40
    }
}

enum FrameStore {
    /// 读取形象包 frames/ 里的 webp、png，缩放到 pixelSide 像素见方
    static func load(pixelSide: Int) -> [String: Frame] {
        guard let dir = Character.framesDir,
              let files = try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) else {
            Log.write("character frames missing")
            return [:]
        }
        var frames: [String: Frame] = [:]
        for url in files where ["webp", "png"].contains(url.pathExtension.lowercased()) {
            guard let src = CGImageSourceCreateWithURL(url as CFURL, nil),
                  let full = CGImageSourceCreateImageAtIndex(src, 0, nil),
                  let scaled = scale(full, to: pixelSide) else {
                Log.write("failed to load \(url.lastPathComponent)")
                continue
            }
            frames[url.deletingPathExtension().lastPathComponent] = Frame(image: scaled, mask: alphaMask(full))
        }
        return frames
    }

    private static func scale(_ image: CGImage, to side: Int) -> CGImage? {
        guard let ctx = CGContext(data: nil, width: side, height: side, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        ctx.interpolationQuality = .high
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: side, height: side))
        return ctx.makeImage()
    }

    private static func alphaMask(_ image: CGImage) -> [UInt8] {
        let side = Frame.maskSide
        var rgba = [UInt8](repeating: 0, count: side * side * 4)
        rgba.withUnsafeMutableBytes { raw in
            guard let ctx = CGContext(data: raw.baseAddress, width: side, height: side, bitsPerComponent: 8, bytesPerRow: side * 4,
                                      space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return }
            ctx.draw(image, in: CGRect(x: 0, y: 0, width: side, height: side))
        }
        // 位图内存第一行对应画面最上方
        return stride(from: 3, to: rgba.count, by: 4).map { rgba[$0] }
    }
}
