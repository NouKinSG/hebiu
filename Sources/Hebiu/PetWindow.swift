import HebiuKit
import AppKit
import QuartzCore

/// 透明、置顶、不抢焦点的小窗口
final class PetPanel: NSPanel {
    init(size: NSSize) {
        super.init(contentRect: NSRect(origin: .zero, size: size),
                   styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        isMovable = false            // 拖动由我们自己处理，区分「点一下」和「拖动」
        hidesOnDeactivate = false
        ignoresMouseEvents = true
    }
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

/// 窗口内容：下方是她，上方留出气泡的位置
final class PetView: NSView {
    let imageLayer = CALayer()
    private let bodyLayer = CALayer()
    /// 跟着鼠标歪一点的那一层（夹在呼吸和动作之间，互不覆盖）
    private let leanLayer = CALayer()
    private var leanAmount: CGFloat = 0
    let bubble = BubbleView()
    private(set) var petRect = NSRect.zero

    var onClick: (() -> Void)?
    var onDoubleClick: (() -> Void)?
    var onRightClick: (() -> Void)?
    var onMoved: (() -> Void)?
    var onMenu: ((NSPoint) -> Void)?
    var onBubbleClick: (() -> Void)?
    var frameProvider: (() -> Frame?)?

    private var dragStart: NSPoint?
    private var windowStart: NSPoint?
    private var dragged = false
    private var longPress: DispatchWorkItem?
    private var menuShown = false

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.backgroundColor = .clear
        bodyLayer.anchorPoint = CGPoint(x: 0.5, y: 0)
        imageLayer.anchorPoint = CGPoint(x: 0.5, y: 0.08)
        imageLayer.contentsGravity = .resizeAspect
        leanLayer.anchorPoint = CGPoint(x: 0.5, y: 0)
        leanLayer.addSublayer(imageLayer)
        bodyLayer.addSublayer(leanLayer)
        layer?.addSublayer(bodyLayer)
        addSubview(bubble)
        startBreathing()
    }
    required init?(coder: NSCoder) { fatalError() }

    func layoutPet(side: CGFloat, scale: CGFloat) {
        petRect = NSRect(x: bounds.width - side, y: 0, width: side, height: side)
        CATransaction.begin(); CATransaction.setDisableActions(true)
        bodyLayer.bounds = CGRect(x: 0, y: 0, width: side, height: side)
        bodyLayer.position = CGPoint(x: petRect.midX, y: 0)
        leanLayer.bounds = bodyLayer.bounds
        leanLayer.position = CGPoint(x: side / 2, y: 0)
        imageLayer.bounds = bodyLayer.bounds
        imageLayer.position = CGPoint(x: side / 2, y: side * 0.08)
        imageLayer.contentsScale = scale
        CATransaction.commit()
        bubble.anchor = NSPoint(x: petRect.minX + side * 0.62, y: side * 0.9)
    }

    /// 她身边的小角标：后台会话做完了几个（0 就收起来）
    private lazy var badge: NSTextField = {
        let t = NSTextField(labelWithString: "")
        t.font = .systemFont(ofSize: 11, weight: .bold)
        t.textColor = .white
        t.alignment = .center
        t.wantsLayer = true
        t.layer?.backgroundColor = NSColor(red: 0.88, green: 0.36, blue: 0.52, alpha: 1).cgColor
        t.layer?.cornerRadius = 9
        t.isHidden = true
        addSubview(t)
        return t
    }()

    func setBadge(_ count: Int) {
        badge.isHidden = count == 0
        guard count > 0 else { return }
        badge.stringValue = "✓\(count)"
        let side = petRect.width
        badge.frame = NSRect(x: petRect.minX + side * 0.12, y: side * 0.78, width: 30, height: 18)
        badge.toolTip = "后台有 \(count) 个会话做完了，点我看过就清掉"
    }

    /// 往鼠标那边歪：amount 在 -1（左）到 1（右）之间；0 是站直
    func lean(_ amount: CGFloat) {
        let a = max(-1, min(1, amount))
        guard abs(a - leanAmount) > 0.02 else { return }
        leanAmount = a
        let side = bodyLayer.bounds.width
        var t = CATransform3DMakeTranslation(a * side * 0.03, 0, 0)
        t = CATransform3DRotate(t, -a * 0.06, 0, 0, 1)
        CATransaction.begin()
        CATransaction.setAnimationDuration(0.45)
        CATransaction.setAnimationTimingFunction(CAMediaTimingFunction(name: .easeOut))
        leanLayer.transform = t
        CATransaction.commit()
    }

    /// 呼吸起伏交给 Core Animation 在系统渲染进程里跑，不占本程序 CPU
    private func startBreathing() {
        let a = CABasicAnimation(keyPath: "transform")
        a.fromValue = CATransform3DIdentity
        a.toValue = CATransform3DMakeScale(1.006, 0.986, 1)
        a.duration = 1.6
        a.autoreverses = true
        a.repeatCount = .infinity
        a.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        bodyLayer.add(a, forKey: "breath")
    }

    /// 这个点是否落在「能点的地方」：她身上的不透明像素，或正在显示的气泡
    func isInteractive(at p: NSPoint) -> Bool {
        if bubble.alphaValue > 0.1, bubble.frame.contains(p) { return true }
        guard petRect.contains(p), let frame = frameProvider?() else { return false }
        let unit = CGPoint(x: (p.x - petRect.minX) / petRect.width, y: (p.y - petRect.minY) / petRect.height)
        return frame.isOpaque(atUnit: unit)
    }

    var isDragging: Bool { dragStart != nil }

    // MARK: - 小手光标
    // 后台程序直接 NSCursor.set() 会被前台程序立刻改回去；用 activeAlways 的跟踪区域，
    // 鼠标在窗口上每次移动都会收到事件，在这里设置光标才算数
    private var tracking: NSTrackingArea?

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let tracking { removeTrackingArea(tracking) }
        let area = NSTrackingArea(rect: .zero, options: [.mouseMoved, .mouseEnteredAndExited, .cursorUpdate, .activeAlways, .inVisibleRect],
                                  owner: self, userInfo: nil)
        addTrackingArea(area)
        tracking = area
    }

    private func updateCursor(_ event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        (isInteractive(at: p) ? NSCursor.pointingHand : NSCursor.arrow).set()
    }

    override func cursorUpdate(with event: NSEvent) { updateCursor(event) }
    override func mouseMoved(with event: NSEvent) { updateCursor(event) }
    override func mouseEntered(with event: NSEvent) { updateCursor(event) }
    override func mouseExited(with event: NSEvent) { NSCursor.arrow.set() }

    override func mouseDown(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        // Option + 点击：直接弹出菜单（菜单栏图标被刘海挡住时也能用）
        if event.modifierFlags.contains(.option) {
            menuShown = true
            onMenu?(p)
            return
        }
        dragStart = NSEvent.mouseLocation
        windowStart = window?.frame.origin
        dragged = false
        menuShown = false
        // 按住不动超过半秒也弹出菜单
        let work = DispatchWorkItem { [weak self] in
            guard let self, !self.dragged, self.dragStart != nil else { return }
            self.menuShown = true
            self.dragStart = nil
            self.onMenu?(p)
        }
        longPress = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.55, execute: work)
    }

    override func mouseDragged(with event: NSEvent) {
        guard let start = dragStart, let origin = windowStart, let window else { return }
        let now = NSEvent.mouseLocation
        let dx = now.x - start.x, dy = now.y - start.y
        if !dragged && hypot(dx, dy) < 3 { return }
        dragged = true
        longPress?.cancel()
        window.setFrameOrigin(NSPoint(x: origin.x + dx, y: origin.y + dy))
    }

    override func mouseUp(with event: NSEvent) {
        defer { dragStart = nil; windowStart = nil }
        longPress?.cancel()
        if menuShown { menuShown = false; return }
        if dragged { onMoved?(); return }
        let p = convert(event.locationInWindow, from: nil)
        if bubble.alphaValue > 0.1, bubble.frame.contains(p) {
            bubble.hide()
            onBubbleClick?()
            return
        }
        ripple(at: convert(event.locationInWindow, from: nil))
        // 每一下都马上反应：连着快点时第 2 下冒爱心，第 3 下以后照常算点她（连戳多了她会鼓嘴）
        if event.clickCount == 2 {
            onDoubleClick?()
        } else {
            onClick?()
        }
    }

    override func rightMouseDown(with event: NSEvent) {
        ripple(at: convert(event.locationInWindow, from: nil))
        onRightClick?()
    }

    /// 点击反馈：粉色小圆圈扩散 + 一颗小爱心往上飘，0.5 秒内消失
    func ripple(at p: NSPoint) {
        guard let root = layer else { return }
        let pink = NSColor(calibratedRed: 0.95, green: 0.40, blue: 0.54, alpha: 1).cgColor

        let ring = CAShapeLayer()
        ring.path = CGPath(ellipseIn: CGRect(x: -6, y: -6, width: 12, height: 12), transform: nil)
        ring.position = p
        ring.fillColor = nil
        ring.strokeColor = pink
        ring.lineWidth = 2
        root.addSublayer(ring)

        let heart = CATextLayer()
        heart.string = "♥"
        heart.fontSize = 13
        heart.foregroundColor = pink
        heart.alignmentMode = .center
        heart.contentsScale = window?.backingScaleFactor ?? 2
        heart.frame = CGRect(x: p.x - 8, y: p.y + 2, width: 16, height: 18)
        root.addSublayer(heart)

        CATransaction.begin()
        CATransaction.setCompletionBlock { ring.removeFromSuperlayer(); heart.removeFromSuperlayer() }
        let grow = CABasicAnimation(keyPath: "transform.scale"); grow.fromValue = 0.6; grow.toValue = 2.6
        let fade = CABasicAnimation(keyPath: "opacity"); fade.fromValue = 1; fade.toValue = 0
        let group = CAAnimationGroup(); group.animations = [grow, fade]; group.duration = 0.45
        group.timingFunction = CAMediaTimingFunction(name: .easeOut)
        ring.opacity = 0
        ring.add(group, forKey: "ripple")
        let rise = CABasicAnimation(keyPath: "position.y"); rise.byValue = 18
        let fade2 = CABasicAnimation(keyPath: "opacity"); fade2.fromValue = 1; fade2.toValue = 0
        let g2 = CAAnimationGroup(); g2.animations = [rise, fade2]; g2.duration = 0.6
        g2.timingFunction = CAMediaTimingFunction(name: .easeOut)
        heart.opacity = 0
        heart.add(g2, forKey: "rise")
        CATransaction.commit()
    }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

/// 头顶的对话气泡
final class BubbleView: NSView {
    private let label = NSTextField(labelWithString: "")
    private var hideWork: DispatchWorkItem?
    var anchor = NSPoint.zero        // 气泡尾巴指向的位置（她的头顶附近）
    private let padding = NSSize(width: 14, height: 9)
    private let tail: CGFloat = 8

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        alphaValue = 0
        label.font = .systemFont(ofSize: 13, weight: .semibold)
        label.textColor = NSColor(calibratedRed: 0.16, green: 0.13, blue: 0.19, alpha: 1)
        label.maximumNumberOfLines = 3
        label.lineBreakMode = .byWordWrapping
        label.preferredMaxLayoutWidth = 200
        addSubview(label)
    }
    required init?(coder: NSCoder) { fatalError() }

    /// seconds 为 nil：一直显示，直到 hide() 或下一次 show()
    func show(_ text: String, seconds: Double? = 3.6) {
        label.stringValue = text
        let size = label.sizeThatFits(NSSize(width: 200, height: 200))
        let w = ceil(size.width) + padding.width * 2, h = ceil(size.height) + padding.height * 2
        var x = anchor.x - w + 26
        if let sv = superview { x = max(4, min(x, sv.bounds.width - w - 4)) }
        frame = NSRect(x: x, y: anchor.y, width: w, height: h + tail)
        label.frame = NSRect(x: padding.width, y: tail + padding.height, width: ceil(size.width), height: ceil(size.height))
        needsDisplay = true
        NSAnimationContext.runAnimationGroup { $0.duration = 0.2; animator().alphaValue = 1 }
        hideWork?.cancel()
        guard let seconds else { return }
        let work = DispatchWorkItem { [weak self] in
            NSAnimationContext.runAnimationGroup { $0.duration = 0.3; self?.animator().alphaValue = 0 }
        }
        hideWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds, execute: work)
    }

    func hide() {
        hideWork?.cancel()
        alphaValue = 0
    }

    override func draw(_ dirtyRect: NSRect) {
        let body = NSRect(x: 0, y: tail, width: bounds.width, height: bounds.height - tail)
        let path = NSBezierPath(roundedRect: body, xRadius: 14, yRadius: 14)
        let tx = min(max(anchor.x - frame.minX, 18), bounds.width - 18)
        path.move(to: NSPoint(x: tx - 7, y: tail + 1))
        path.line(to: NSPoint(x: tx + 2, y: 0))
        path.line(to: NSPoint(x: tx + 7, y: tail + 1))
        path.close()
        NSColor(calibratedRed: 0.984, green: 0.973, blue: 0.957, alpha: 1).setFill()
        path.fill()
    }
}
