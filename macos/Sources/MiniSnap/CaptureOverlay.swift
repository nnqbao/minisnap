import AppKit
import Carbon

/// What the user chose in the overlay.
enum OverlayAction {
    case screenshot
    case video
    case scroll
}

struct OverlayResult {
    let action: OverlayAction
    let shot: DisplayShot
    /// Selection in the screenshot's pixel space (top-left origin).
    let pixelRect: CGRect
    /// Same selection in points, relative to the display's top-left corner.
    let pointRect: CGRect

    /// Selection in global Quartz points (top-left origin of the primary display).
    var globalQuartzRect: CGRect {
        pointRect.offsetBy(dx: shot.display.frame.minX, dy: shot.display.frame.minY)
    }

    var croppedImage: CGImage? { ImageUtil.crop(shot.image, to: pixelRect) }
}

private let overlayAccent = NSColor(srgbRed: 1, green: 120.0 / 255.0, blue: 30.0 / 255.0, alpha: 1)

/// Borderless full-screen window that can take keyboard focus.
final class OverlayWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

/// One frozen screenshot window per display; the user picks a window or drags a region.
@MainActor
final class CaptureOverlayController {
    private var windows: [OverlayWindow] = []
    private var views: [OverlayView] = []
    private var completion: ((OverlayResult?) -> Void)?
    private var finished = false

    init(shots: [DisplayShot], windowRects: [CGRect], prompt: String?, askMode: Bool,
         defaultAction: OverlayAction, completion: @escaping (OverlayResult?) -> Void) {
        self.completion = completion
        for shot in shots {
            guard let screen = ScreenCapture.screen(for: shot.display.displayID) else { continue }
            let w = OverlayWindow(contentRect: screen.frame, styleMask: [.borderless], backing: .buffered, defer: false)
            w.isReleasedWhenClosed = false
            w.level = .screenSaver
            w.isOpaque = true
            w.backgroundColor = .black
            w.hasShadow = false
            w.ignoresMouseEvents = false
            w.acceptsMouseMovedEvents = true
            w.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
            w.setFrame(screen.frame, display: false)
            let origin = shot.display.frame.origin
            let local = windowRects.map { $0.offsetBy(dx: -origin.x, dy: -origin.y) }
            let v = OverlayView(frame: NSRect(origin: .zero, size: screen.frame.size), shot: shot,
                                windowRects: local, prompt: prompt, askMode: askMode, defaultAction: defaultAction)
            v.controller = self
            w.contentView = v
            windows.append(w)
            views.append(v)
        }
    }

    var isEmpty: Bool { windows.isEmpty }

    func show() {
        NSApp.activate(ignoringOtherApps: true)
        let mouse = NSEvent.mouseLocation
        var keyWindow: OverlayWindow?
        for w in windows {
            w.orderFrontRegardless()
            if NSMouseInRect(mouse, w.frame, false) { keyWindow = w }
        }
        let k = keyWindow ?? windows.first
        k?.makeKeyAndOrderFront(nil)
        if let v = k?.contentView { k?.makeFirstResponder(v) }
        for v in views { v.start() }
        NSCursor.crosshair.set()
    }

    /// A view started a new selection: clear the others so only one selection exists.
    func viewBeganSelection(_ v: OverlayView) {
        for other in views where other !== v { other.resetSelection() }
    }

    func cancel() { finish(nil) }

    func finish(_ result: OverlayResult?) {
        if finished { return }
        finished = true
        for w in windows { w.orderOut(nil) }
        NSCursor.arrow.set()
        let c = completion
        completion = nil
        // Let the overlay disappear from the screen before anything is captured or shown.
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 60_000_000)
            c?(result)
            self.windows.removeAll()
            self.views.removeAll()
        }
    }
}

/// A view whose layer simply shows an image (or a colour); used for the cheap backdrop layers.
final class LayerImageView: NSView {
    var image: CGImage? { didSet { needsDisplay = true } }
    var fillColor: NSColor? { didSet { needsDisplay = true } }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override var wantsUpdateLayer: Bool { true }

    override func updateLayer() {
        guard let layer = layer else { return }
        layer.contents = image
        layer.contentsGravity = .resize
        layer.magnificationFilter = .nearest
        layer.backgroundColor = fillColor?.cgColor
    }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}

/// A small rounded glass label (size label, prompt, magnifier info).
final class PillView: NSView {
    let label = NSTextField(labelWithString: "")
    let swatch = NSView()
    private let showsSwatch: Bool

    init(tint: NSColor?, font: NSFont, swatch: Bool = false, radius: CGFloat = 7) {
        showsSwatch = swatch
        super.init(frame: .zero)
        appearance = NSAppearance(named: .darkAqua)
        let (container, content) = makeGlassContainer(cornerRadius: radius, tint: tint, material: .hud)
        addSubview(container)
        label.font = font
        label.textColor = .white
        label.maximumNumberOfLines = 3
        label.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(label)
        var cs: [NSLayoutConstraint] = [
            container.leadingAnchor.constraint(equalTo: leadingAnchor),
            container.trailingAnchor.constraint(equalTo: trailingAnchor),
            container.topAnchor.constraint(equalTo: topAnchor),
            container.bottomAnchor.constraint(equalTo: bottomAnchor),
            label.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -10),
            label.topAnchor.constraint(equalTo: content.topAnchor, constant: 4),
            label.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -4)
        ]
        if swatch {
            self.swatch.wantsLayer = true
            self.swatch.layer?.borderColor = NSColor.gray.cgColor
            self.swatch.layer?.borderWidth = 1
            self.swatch.translatesAutoresizingMaskIntoConstraints = false
            content.addSubview(self.swatch)
            cs += [
                self.swatch.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 8),
                self.swatch.centerYAnchor.constraint(equalTo: content.centerYAnchor),
                self.swatch.widthAnchor.constraint(equalToConstant: 18),
                self.swatch.heightAnchor.constraint(equalToConstant: 18),
                label.leadingAnchor.constraint(equalTo: self.swatch.trailingAnchor, constant: 8)
            ]
        } else {
            cs.append(label.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 10))
        }
        NSLayoutConstraint.activate(cs)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    func setText(_ s: String) {
        if label.stringValue != s { label.stringValue = s }
    }

    var fitting: NSSize {
        layoutSubtreeIfNeeded()
        return fittingSize
    }
}

/// Crosshair, selection frame, resize handles and the zoomed magnifier image.
final class OverlayChromeView: NSView {
    var cursor: CGPoint?
    var highlight: CGRect = .zero
    var showHandles = false
    var magBox: CGRect = .zero
    var magImage: CGImage?
    var magImageRect: CGRect = .zero
    var magCenterCell: CGRect = .zero

    override var isFlipped: Bool { true }
    override var isOpaque: Bool { false }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        if let c = cursor {
            ctx.saveGState()
            ctx.setStrokeColor(NSColor(white: 1, alpha: 0.67).cgColor)
            ctx.setLineWidth(1)
            ctx.setLineDash(phase: 0, lengths: [4, 3])
            ctx.beginPath()
            ctx.move(to: CGPoint(x: 0, y: c.y + 0.5))
            ctx.addLine(to: CGPoint(x: bounds.width, y: c.y + 0.5))
            ctx.move(to: CGPoint(x: c.x + 0.5, y: 0))
            ctx.addLine(to: CGPoint(x: c.x + 0.5, y: bounds.height))
            ctx.strokePath()
            ctx.restoreGState()
        }
        let h = highlight
        if h.width > 0 && h.height > 0 {
            ctx.saveGState()
            ctx.setStrokeColor(overlayAccent.cgColor)
            ctx.setLineWidth(2)
            ctx.stroke(h.insetBy(dx: -1, dy: -1))
            if showHandles {
                let pts = [
                    CGPoint(x: h.minX, y: h.minY), CGPoint(x: h.midX, y: h.minY), CGPoint(x: h.maxX, y: h.minY),
                    CGPoint(x: h.minX, y: h.midY), CGPoint(x: h.maxX, y: h.midY),
                    CGPoint(x: h.minX, y: h.maxY), CGPoint(x: h.midX, y: h.maxY), CGPoint(x: h.maxX, y: h.maxY)
                ]
                for p in pts {
                    let r = CGRect(x: p.x - 4, y: p.y - 4, width: 8, height: 8)
                    ctx.setFillColor(NSColor.white.cgColor)
                    ctx.fill(r)
                    ctx.setLineWidth(1.5)
                    ctx.stroke(r)
                }
            }
            ctx.restoreGState()
        }
        if cursor != nil && magBox.width > 0 {
            ctx.saveGState()
            ctx.setFillColor(NSColor.black.cgColor)
            ctx.fill(magBox)
            if let img = magImage {
                ctx.interpolationQuality = .none
                ImageUtil.drawUpright(img, in: magImageRect, context: ctx)
            }
            let band = overlayAccent.withAlphaComponent(0.2).cgColor
            ctx.setFillColor(band)
            ctx.fill(CGRect(x: magBox.minX, y: magCenterCell.minY, width: magBox.width, height: magCenterCell.height))
            ctx.fill(CGRect(x: magCenterCell.minX, y: magBox.minY, width: magCenterCell.width, height: magBox.height))
            ctx.setStrokeColor(overlayAccent.cgColor)
            ctx.setLineWidth(1)
            ctx.stroke(magCenterCell)
            ctx.setStrokeColor(NSColor.white.cgColor)
            ctx.stroke(magBox.insetBy(dx: 0.5, dy: 0.5))
            ctx.restoreGState()
        }
    }
}

/// The interactive surface for one display.
@MainActor
final class OverlayView: NSView, NSTextFieldDelegate {
    private enum Phase { case selecting, adjusting }

    private struct Edges {
        var left = false, right = false, top = false, bottom = false
        var any: Bool { left || right || top || bottom }
    }

    private enum DragKind {
        case idle
        case move
        case resize(Edges)
    }

    private static let magPixels = 15
    private static let magZoom: CGFloat = 8
    private static let gap: CGFloat = 22

    let shot: DisplayShot
    weak var controller: CaptureOverlayController?
    private let windowRects: [CGRect]
    private let prompt: String?
    private let askMode: Bool
    private let defaultAction: OverlayAction

    private let srcView = LayerImageView(frame: .zero)
    private let dimView = LayerImageView(frame: .zero)
    private let litView = LayerImageView(frame: .zero)
    private let chrome = OverlayChromeView(frame: .zero)
    private let sizePill = PillView(tint: nil, font: NSFont.systemFont(ofSize: 12, weight: .bold))
    private let infoPill = PillView(tint: nil, font: NSFont.monospacedSystemFont(ofSize: 11, weight: .semibold), swatch: true)
    private let promptPill = PillView(tint: overlayAccent, font: NSFont.systemFont(ofSize: 13, weight: .bold), radius: 16)
    private let modeBarHost = NSView()
    private let widthField = NSTextField(string: "")
    private let heightField = NSTextField(string: "")
    private var trackingArea: NSTrackingArea?

    private var phase = Phase.selecting
    private var cursor: CGPoint?
    private var mouseIsDown = false
    private var dragging = false
    private var dragStart = CGPoint.zero
    private var selection = CGRect.zero
    private var hover = CGRect.zero
    private var adjustRect = CGRect.zero
    private var dragKind = DragKind.idle
    private var dragOrigRect = CGRect.zero
    private var lastLitPixelRect = CGRect.null

    init(frame: NSRect, shot: DisplayShot, windowRects: [CGRect], prompt: String?, askMode: Bool, defaultAction: OverlayAction) {
        self.shot = shot
        self.windowRects = windowRects
        self.prompt = prompt
        self.askMode = askMode
        self.defaultAction = defaultAction
        super.init(frame: frame)
        wantsLayer = true
        setUp()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    private var scale: CGFloat { CGFloat(shot.image.width) / max(1, bounds.width) }
    private var imageBounds: CGRect { CGRect(x: 0, y: 0, width: shot.image.width, height: shot.image.height) }

    // MARK: setup

    private func setUp() {
        for v in [srcView, dimView, litView, chrome] as [NSView] {
            v.frame = bounds
            v.autoresizingMask = [.width, .height]
            addSubview(v)
        }
        litView.autoresizingMask = []
        srcView.image = shot.image
        dimView.fillColor = NSColor(white: 0, alpha: 0.49)
        litView.isHidden = true

        for p in [sizePill, infoPill, promptPill] {
            p.isHidden = true
            addSubview(p)
        }
        if let pr = prompt, !pr.isEmpty {
            promptPill.setText(pr)
            let s = promptPill.fitting
            promptPill.frame = NSRect(x: (bounds.width - s.width) / 2, y: 28, width: s.width, height: s.height)
            promptPill.isHidden = false
        }
        buildModeBar()
    }

    private func iconButton(_ symbolName: String, fallback: String, tip: String, action: Selector, tint: NSColor) -> NSButton {
        let b: NSButton
        if let img = symbol(symbolName, size: 17, weight: .semibold) {
            b = NSButton(image: img, target: self, action: action)
            // NSButton(image:) keeps the placeholder title "Button"; the glass style would draw it over the icon.
            b.title = ""
            b.imagePosition = .imageOnly
        } else {
            b = NSButton(title: fallback, target: self, action: action)
        }
        b.toolTip = tip
        b.setAccessibilityLabel(tip)
        b.controlSize = .large
        styleGlassButton(b, prominent: true, tint: tint)
        b.translatesAutoresizingMaskIntoConstraints = false
        b.widthAnchor.constraint(greaterThanOrEqualToConstant: 44).isActive = true
        if !glassAvailable() {
            b.heightAnchor.constraint(equalToConstant: 34).isActive = true
        }
        return b
    }

    private func buildModeBar() {
        let blue = NSColor.systemBlue
        let gray = NSColor.systemGray
        let shotBtn = iconButton("camera.fill", fallback: "📷", tip: L.t("Chụp ảnh (Enter)"), action: #selector(modeScreenshot), tint: blue)
        let videoBtn = iconButton("video.fill", fallback: "🎥", tip: L.t("Quay video (V)"), action: #selector(modeVideo), tint: blue)
        let scrollBtn = iconButton("arrow.down.doc.fill", fallback: "⇣", tip: L.t("Chụp cuộn (S)"), action: #selector(modeScroll), tint: blue)
        let reselect = iconButton("arrow.counterclockwise", fallback: "↺", tip: L.t("Chọn lại (R)"), action: #selector(modeReselect), tint: gray)
        let cancel = iconButton("xmark", fallback: "✕", tip: L.t("Huỷ (Esc)"), action: #selector(modeCancel), tint: gray)

        for (f, tip) in [(widthField, L.t("Rộng (px)")), (heightField, L.t("Cao (px)"))] {
            f.alignment = .center
            f.font = NSFont.monospacedDigitSystemFont(ofSize: 13, weight: .medium)
            f.toolTip = tip
            f.target = self
            f.action = #selector(sizeFieldChanged(_:))
            f.delegate = self
            f.cell?.sendsActionOnEndEditing = true
            f.translatesAutoresizingMaskIntoConstraints = false
            f.widthAnchor.constraint(equalToConstant: 66).isActive = true
        }
        let times = NSTextField(labelWithString: "×")
        times.textColor = .white
        times.font = NSFont.systemFont(ofSize: 14, weight: .bold)

        let modes = NSStackView(views: [shotBtn, videoBtn, scrollBtn])
        modes.spacing = 6
        let tail = NSStackView(views: [reselect, cancel])
        tail.spacing = 6
        let sizeRow = NSStackView(views: [widthField, times, heightField])
        sizeRow.spacing = 4
        let row = NSStackView(views: [wrapInGlassGroup(modes), sizeRow, wrapInGlassGroup(tail)])
        row.orientation = .horizontal
        row.spacing = 12
        row.alignment = .centerY
        row.edgeInsets = NSEdgeInsets(top: 7, left: 8, bottom: 7, right: 8)
        row.translatesAutoresizingMaskIntoConstraints = false

        let (container, content) = makeGlassContainer(cornerRadius: 14, tint: nil, material: .hud)
        content.addSubview(row)
        modeBarHost.appearance = NSAppearance(named: .darkAqua)
        modeBarHost.addSubview(container)
        NSLayoutConstraint.activate([
            row.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            row.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            row.topAnchor.constraint(equalTo: content.topAnchor),
            row.bottomAnchor.constraint(equalTo: content.bottomAnchor),
            container.leadingAnchor.constraint(equalTo: modeBarHost.leadingAnchor),
            container.trailingAnchor.constraint(equalTo: modeBarHost.trailingAnchor),
            container.topAnchor.constraint(equalTo: modeBarHost.topAnchor),
            container.bottomAnchor.constraint(equalTo: modeBarHost.bottomAnchor)
        ])
        modeBarHost.isHidden = true
        addSubview(modeBarHost)
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let t = trackingArea { removeTrackingArea(t) }
        let t = NSTrackingArea(rect: bounds,
                               options: [.mouseMoved, .mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                               owner: self, userInfo: nil)
        addTrackingArea(t)
        trackingArea = t
    }

    func start() {
        guard let w = window else { return }
        let p = w.mouseLocationOutsideOfEventStream
        let local = convert(p, from: nil)
        if bounds.contains(local) {
            updateState(local)
        } else {
            refresh()
        }
    }

    // MARK: geometry

    private func pixelRect(_ r: CGRect) -> CGRect {
        let s = scale
        let px = CGRect(x: r.minX * s, y: r.minY * s, width: r.width * s, height: r.height * s).integral
        let clipped = px.intersection(imageBounds)
        return clipped.isNull ? .zero : clipped
    }

    private func pointRect(fromPixels px: CGRect) -> CGRect {
        let s = scale
        return CGRect(x: px.minX / s, y: px.minY / s, width: px.width / s, height: px.height / s)
    }

    private var highlight: CGRect {
        switch phase {
        case .adjusting: return adjustRect
        case .selecting: return dragging ? selection : hover
        }
    }

    private func findWindow(at p: CGPoint) -> CGRect {
        for r in windowRects where r.contains(p) {
            let c = r.intersection(bounds)
            if !c.isNull && c.width > 4 && c.height > 4 { return c }
        }
        return bounds
    }

    private func norm(_ a: CGPoint, _ b: CGPoint) -> CGRect {
        Geo.norm(a, b).intersection(bounds)
    }

    // MARK: state

    func resetSelection() {
        phase = .selecting
        mouseIsDown = false
        dragging = false
        selection = .zero
        hover = .zero
        adjustRect = .zero
        cursor = nil
        modeBarHost.isHidden = true
        refresh()
    }

    private func updateState(_ p: CGPoint) {
        cursor = p
        if mouseIsDown {
            if !dragging && (abs(p.x - dragStart.x) > 3 || abs(p.y - dragStart.y) > 3) { dragging = true }
            if dragging { selection = norm(dragStart, p) }
        }
        if !dragging { hover = findWindow(at: p) }
        refresh()
    }

    private func refresh() {
        let h = highlight
        if h.width > 0 && h.height > 0 {
            let px = pixelRect(h)
            if px.width > 0 && px.height > 0 {
                litView.frame = pointRect(fromPixels: px)
                if px != lastLitPixelRect {
                    litView.image = ImageUtil.crop(shot.image, to: px)
                    lastLitPixelRect = px
                }
                litView.isHidden = false
                sizePill.setText(String(Int(px.width)) + " × " + String(Int(px.height)))
                let s = sizePill.fitting
                var x = max(0, min(h.minX, bounds.width - s.width))
                var y = h.minY - s.height - 6
                if y < 0 { y = h.minY + 6 }
                if phase == .adjusting && y < h.minY && !modeBarHost.isHidden && modeBarHost.frame.intersects(NSRect(x: x, y: y, width: s.width, height: s.height)) {
                    x = max(0, min(h.maxX - s.width, bounds.width - s.width))
                }
                sizePill.frame = NSRect(x: x, y: y, width: s.width, height: s.height)
                sizePill.isHidden = false
            } else {
                litView.isHidden = true
                sizePill.isHidden = true
            }
        } else {
            litView.isHidden = true
            sizePill.isHidden = true
        }

        chrome.highlight = h
        chrome.showHandles = phase == .adjusting
        promptPill.isHidden = prompt == nil || prompt?.isEmpty == true || phase == .adjusting
        if phase == .selecting, let c = cursor {
            chrome.cursor = c
            updateMagnifier(c)
        } else {
            chrome.cursor = nil
            chrome.magBox = .zero
            infoPill.isHidden = true
        }
        chrome.needsDisplay = true
    }

    private func updateMagnifier(_ c: CGPoint) {
        let n = OverlayView.magPixels
        let z = OverlayView.magZoom
        let zoomSize = CGFloat(n) * z
        let half = n / 2
        let s = scale
        let pxX = Int(floor(c.x * s)), pxY = Int(floor(c.y * s))

        let col = pixelColor(pxX, pxY)
        infoPill.setText(String(pxX) + ", " + String(pxY) + "\n" + String(format: "#%02X%02X%02X", col.r, col.g, col.b))
        infoPill.swatch.layer?.backgroundColor = CGColor(srgbRed: CGFloat(col.r) / 255, green: CGFloat(col.g) / 255, blue: CGFloat(col.b) / 255, alpha: 1)
        let infoSize = infoPill.fitting
        let w = max(zoomSize, infoSize.width)
        let totalH = zoomSize + 4 + infoSize.height
        var x = c.x + OverlayView.gap
        var y = c.y + OverlayView.gap
        if x + w > bounds.width { x = c.x - OverlayView.gap - w }
        if y + totalH > bounds.height { y = c.y - OverlayView.gap - totalH }
        let box = CGRect(x: x, y: y, width: zoomSize, height: zoomSize)
        chrome.magBox = box
        chrome.magCenterCell = CGRect(x: box.minX + CGFloat(half) * z, y: box.minY + CGFloat(half) * z, width: z, height: z)
        let want = CGRect(x: pxX - half, y: pxY - half, width: n, height: n)
        let got = want.intersection(imageBounds)
        if !got.isNull && got.width > 0 && got.height > 0, let img = shot.image.cropping(to: got) {
            chrome.magImage = img
            chrome.magImageRect = CGRect(x: box.minX + (got.minX - want.minX) * z,
                                         y: box.minY + (got.minY - want.minY) * z,
                                         width: got.width * z, height: got.height * z)
        } else {
            chrome.magImage = nil
        }
        infoPill.frame = NSRect(x: x, y: y + zoomSize + 4, width: w, height: infoSize.height)
        infoPill.isHidden = false
    }

    private func pixelColor(_ x: Int, _ y: Int) -> (r: Int, g: Int, b: Int) {
        guard x >= 0, y >= 0, x < shot.image.width, y < shot.image.height,
              let one = shot.image.cropping(to: CGRect(x: x, y: y, width: 1, height: 1)),
              let px = PixelImage(one) else { return (0, 0, 0) }
        return px.color(0, 0)
    }

    // MARK: mode bar

    private func enterAdjusting(_ r: CGRect) {
        phase = .adjusting
        adjustRect = pointRect(fromPixels: pixelRect(r))
        mouseIsDown = false
        dragging = false
        cursor = nil
        modeBarHost.isHidden = false
        updateFields()
        positionModeBar()
        refresh()
        window?.makeFirstResponder(self)
    }

    private func positionModeBar() {
        modeBarHost.layoutSubtreeIfNeeded()
        let s = modeBarHost.fittingSize
        let r = adjustRect
        var x = r.midX - s.width / 2
        x = max(8, min(x, bounds.width - s.width - 8))
        var y = r.maxY + 10                                       // below
        if y + s.height > bounds.height - 4 { y = r.minY - 10 - s.height } // above
        if y < 4 { y = r.maxY - s.height - 10 }                   // inside, bottom edge
        modeBarHost.frame = NSRect(x: x, y: y, width: s.width, height: s.height)
    }

    private func updateFields() {
        let px = pixelRect(adjustRect)
        let editing = window?.firstResponder is NSText
        if !editing {
            widthField.stringValue = String(Int(px.width))
            heightField.stringValue = String(Int(px.height))
        }
    }

    @objc private func sizeFieldChanged(_ sender: NSTextField) {
        guard phase == .adjusting else { return }
        let px = pixelRect(adjustRect)
        let digits = sender.stringValue.filter { $0.isNumber }
        guard let v = Int(digits), v > 0 else { updateFields(); return }
        var w = px.width, h = px.height
        if sender === widthField {
            w = min(CGFloat(v), imageBounds.width - px.minX)
        } else {
            h = min(CGFloat(v), imageBounds.height - px.minY)
        }
        adjustRect = pointRect(fromPixels: CGRect(x: px.minX, y: px.minY, width: max(1, w), height: max(1, h)))
        widthField.stringValue = String(Int(max(1, w)))
        heightField.stringValue = String(Int(max(1, h)))
        positionModeBar()
        refresh()
    }

    func controlTextDidEndEditing(_ obj: Notification) {
        if let f = obj.object as? NSTextField { sizeFieldChanged(f) }
        window?.makeFirstResponder(self)
    }

    @objc private func modeScreenshot() { finish(.screenshot) }
    @objc private func modeVideo() { finish(.video) }
    @objc private func modeScroll() { finish(.scroll) }
    @objc private func modeCancel() { controller?.cancel() }

    @objc private func modeReselect() {
        phase = .selecting
        adjustRect = .zero
        modeBarHost.isHidden = true
        if let w = window {
            let p = convert(w.mouseLocationOutsideOfEventStream, from: nil)
            if bounds.contains(p) { updateState(p); return }
        }
        refresh()
    }

    private func finish(_ action: OverlayAction) {
        let r = phase == .adjusting ? adjustRect : (dragging ? selection : hover)
        let px = pixelRect(r)
        guard px.width >= 1, px.height >= 1 else { return }
        controller?.finish(OverlayResult(action: action, shot: shot, pixelRect: px, pointRect: pointRect(fromPixels: px)))
    }

    private func finishFullDisplay() {
        if askMode {
            enterAdjusting(bounds)
        } else {
            phase = .selecting
            dragging = false
            hover = bounds
            finish(defaultAction)
        }
    }

    // MARK: adjusting hit testing

    private func edges(at p: CGPoint) -> Edges {
        let r = adjustRect
        let t: CGFloat = 6
        var e = Edges()
        let inY = p.y >= r.minY - t && p.y <= r.maxY + t
        let inX = p.x >= r.minX - t && p.x <= r.maxX + t
        if inY && abs(p.x - r.minX) <= t { e.left = true }
        if inY && abs(p.x - r.maxX) <= t { e.right = true }
        if inX && abs(p.y - r.minY) <= t { e.top = true }
        if inX && abs(p.y - r.maxY) <= t { e.bottom = true }
        return e
    }

    private func updateAdjustCursor(_ p: CGPoint) {
        let e = edges(at: p)
        if e.any {
            let horizontal = e.left || e.right
            let vertical = e.top || e.bottom
            if horizontal && !vertical {
                NSCursor.resizeLeftRight.set()
            } else if vertical && !horizontal {
                NSCursor.resizeUpDown.set()
            } else {
                NSCursor.crosshair.set()
            }
        } else if adjustRect.contains(p) {
            NSCursor.openHand.set()
        } else {
            NSCursor.crosshair.set()
        }
    }

    private func applyAdjustDrag(_ p: CGPoint) {
        let dx = p.x - dragStart.x, dy = p.y - dragStart.y
        var r = dragOrigRect
        switch dragKind {
        case .idle:
            return
        case .move:
            r.origin.x = max(0, min(r.minX + dx, bounds.width - r.width))
            r.origin.y = max(0, min(r.minY + dy, bounds.height - r.height))
        case .resize(let e):
            var minX = r.minX, maxX = r.maxX, minY = r.minY, maxY = r.maxY
            if e.left { minX += dx }
            if e.right { maxX += dx }
            if e.top { minY += dy }
            if e.bottom { maxY += dy }
            r = CGRect(x: min(minX, maxX), y: min(minY, maxY), width: abs(maxX - minX), height: abs(maxY - minY)).intersection(bounds)
            if r.isNull { return }
            let minSize = 1 / scale
            if r.width < minSize { r.size.width = minSize }
            if r.height < minSize { r.size.height = minSize }
        }
        adjustRect = r
        updateFields()
        positionModeBar()
        refresh()
    }

    // MARK: events

    private func local(_ event: NSEvent) -> CGPoint {
        convert(event.locationInWindow, from: nil)
    }

    override func mouseEntered(with event: NSEvent) {
        if window?.isKeyWindow == false {
            window?.makeKey()
        }
        if !(window?.firstResponder is NSText) { window?.makeFirstResponder(self) }
        NSCursor.crosshair.set()
    }

    override func mouseExited(with event: NSEvent) {
        cursor = nil
        refresh()
    }

    override func mouseMoved(with event: NSEvent) {
        let p = local(event)
        if phase == .selecting {
            NSCursor.crosshair.set()
            updateState(p)
        } else {
            updateAdjustCursor(p)
        }
    }

    override func rightMouseDown(with event: NSEvent) {
        controller?.cancel()
    }

    override func mouseDown(with event: NSEvent) {
        let p = local(event)
        if window?.firstResponder is NSText { window?.makeFirstResponder(self) }
        if phase == .adjusting {
            let e = edges(at: p)
            if e.any {
                dragKind = .resize(e)
            } else if adjustRect.contains(p) {
                dragKind = .move
                NSCursor.closedHand.set()
            } else {
                dragKind = .idle
            }
            if case .idle = dragKind {
                // Outside: start a fresh selection.
                phase = .selecting
                modeBarHost.isHidden = true
                adjustRect = .zero
            } else {
                dragStart = p
                dragOrigRect = adjustRect
                mouseIsDown = true
                return
            }
        }
        controller?.viewBeganSelection(self)
        mouseIsDown = true
        dragging = false
        dragStart = p
        updateState(p)
    }

    override func mouseDragged(with event: NSEvent) {
        let p = local(event)
        if phase == .adjusting {
            applyAdjustDrag(p)
            return
        }
        updateState(p)
    }

    override func mouseUp(with event: NSEvent) {
        let p = local(event)
        if phase == .adjusting {
            dragKind = .idle
            mouseIsDown = false
            updateAdjustCursor(p)
            return
        }
        guard mouseIsDown else { return }
        mouseIsDown = false
        let r = dragging ? selection : hover
        let px = pixelRect(r)
        if px.width < 3 || px.height < 3 {
            dragging = false
            updateState(p)
            return
        }
        if askMode {
            enterAdjusting(r)
        } else {
            finish(defaultAction)
        }
        dragging = false
    }

    override func keyDown(with event: NSEvent) {
        let code = Int(event.keyCode)
        let shift = event.modifierFlags.contains(.shift)
        if code == kVK_Escape {
            controller?.cancel()
            return
        }
        if phase == .adjusting {
            switch code {
            case kVK_Return, kVK_ANSI_KeypadEnter: finish(.screenshot)
            case kVK_ANSI_V: finish(.video)
            case kVK_ANSI_S: finish(.scroll)
            case kVK_ANSI_R: modeReselect()
            default: break
            }
            return
        }
        let step: CGFloat = shift ? 10 : 1
        switch code {
        case kVK_Return, kVK_ANSI_KeypadEnter, kVK_Space: finishFullDisplay()
        case kVK_LeftArrow: nudge(-step, 0)
        case kVK_RightArrow: nudge(step, 0)
        case kVK_UpArrow: nudge(0, -step)
        case kVK_DownArrow: nudge(0, step)
        default: break
        }
    }

    private func nudge(_ dx: CGFloat, _ dy: CGFloat) {
        let base = cursor ?? CGPoint(x: bounds.midX, y: bounds.midY)
        let p = CGPoint(x: max(0, min(bounds.width - 1, base.x + dx)), y: max(0, min(bounds.height - 1, base.y + dy)))
        let global = CGPoint(x: p.x + shot.display.frame.minX, y: p.y + shot.display.frame.minY)
        _ = CGWarpMouseCursorPosition(global)
        updateState(p)
    }
}
