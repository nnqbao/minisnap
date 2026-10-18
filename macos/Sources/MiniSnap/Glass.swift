import AppKit

// Liquid Glass (macOS 26 Tahoe) with a classic NSVisualEffectView fallback for macOS 14–15.
// Every macOS 26 API is behind both `#if compiler(>=6.2)` (so older Xcode still compiles this file)
// and `#available(macOS 26.0, *)` (so the app still runs on macOS 14/15).

enum GlassMaterial {
    case hud       // dark floating bars (overlay pills, recorder bar)
    case popover   // light panels (window backgrounds)
    case menu      // toolbar strips

    var fallback: NSVisualEffectView.Material {
        switch self {
        case .hud: return .hudWindow
        case .popover: return .popover
        case .menu: return .menu
        }
    }
}

/// True when the running system draws Liquid Glass.
func glassAvailable() -> Bool {
    #if compiler(>=6.2)
    if #available(macOS 26.0, *) { return true }
    #endif
    return false
}

/// A stretchable rounded-rect mask for NSVisualEffectView (layer corner radius does not clip behind-window blur).
@MainActor
func roundedMaskImage(radius: CGFloat) -> NSImage {
    let r = max(1, radius)
    let edge = 2 * r + 1
    let img = NSImage(size: NSSize(width: edge, height: edge), flipped: false) { rect in
        NSColor.black.setFill()
        NSBezierPath(roundedRect: rect, xRadius: r, yRadius: r).fill()
        return true
    }
    img.capInsets = NSEdgeInsets(top: r, left: r, bottom: r, right: r)
    img.resizingMode = .stretch
    return img
}

/// Creates a glass (or visual-effect) background. Add your views to `content`; `content` is pinned to all
/// edges of `container`, so constraints inside `content` decide the container's size.
@MainActor
func makeGlassContainer(cornerRadius: CGFloat, tint: NSColor? = nil, material: GlassMaterial = .hud) -> (container: NSView, content: NSView) {
    let content = NSView()
    content.translatesAutoresizingMaskIntoConstraints = false

    #if compiler(>=6.2)
    if #available(macOS 26.0, *) {
        let glass = NSGlassEffectView()
        glass.translatesAutoresizingMaskIntoConstraints = false
        glass.cornerRadius = cornerRadius
        glass.style = .regular
        if let t = tint { glass.tintColor = t }
        glass.contentView = content
        NSLayoutConstraint.activate([
            content.leadingAnchor.constraint(equalTo: glass.leadingAnchor),
            content.trailingAnchor.constraint(equalTo: glass.trailingAnchor),
            content.topAnchor.constraint(equalTo: glass.topAnchor),
            content.bottomAnchor.constraint(equalTo: glass.bottomAnchor)
        ])
        return (glass, content)
    }
    #endif

    let fx = NSVisualEffectView()
    fx.translatesAutoresizingMaskIntoConstraints = false
    fx.material = material.fallback
    fx.blendingMode = .behindWindow
    fx.state = .active
    if cornerRadius > 0 { fx.maskImage = roundedMaskImage(radius: cornerRadius) }
    if material == .hud { fx.appearance = NSAppearance(named: .vibrantDark) }
    fx.addSubview(content)
    if let t = tint {
        content.wantsLayer = true
        content.layer?.backgroundColor = t.withAlphaComponent(0.18).cgColor
        content.layer?.cornerRadius = cornerRadius
    }
    NSLayoutConstraint.activate([
        content.leadingAnchor.constraint(equalTo: fx.leadingAnchor),
        content.trailingAnchor.constraint(equalTo: fx.trailingAnchor),
        content.topAnchor.constraint(equalTo: fx.topAnchor),
        content.bottomAnchor.constraint(equalTo: fx.bottomAnchor)
    ])
    return (fx, content)
}

/// Wraps several glass buttons so that, on macOS 26, their glass shapes merge (NSGlassEffectContainerView).
/// On older systems this returns `inner` unchanged.
@MainActor
func wrapInGlassGroup(_ inner: NSView) -> NSView {
    #if compiler(>=6.2)
    if #available(macOS 26.0, *) {
        let group = NSGlassEffectContainerView()
        group.translatesAutoresizingMaskIntoConstraints = false
        inner.translatesAutoresizingMaskIntoConstraints = false
        group.contentView = inner
        NSLayoutConstraint.activate([
            inner.leadingAnchor.constraint(equalTo: group.leadingAnchor),
            inner.trailingAnchor.constraint(equalTo: group.trailingAnchor),
            inner.topAnchor.constraint(equalTo: group.topAnchor),
            inner.bottomAnchor.constraint(equalTo: group.bottomAnchor)
        ])
        return group
    }
    #endif
    return inner
}

/// Styles a button as Liquid Glass on macOS 26 (prominent = tinted glass), or as a rounded filled /
/// subtle button on older systems.
@MainActor
func styleGlassButton(_ b: NSButton, prominent: Bool, tint: NSColor?) {
    #if compiler(>=6.2)
    if #available(macOS 26.0, *) {
        b.bezelStyle = .glass
        b.isBordered = true
        if prominent {
            b.bezelColor = tint ?? NSColor.controlAccentColor
            b.contentTintColor = NSColor.white
            setButtonTitleColor(b, NSColor.white)
        }
        return
    }
    #endif
    b.isBordered = false
    b.wantsLayer = true
    b.layer?.cornerRadius = prominent ? 9 : 7
    if prominent {
        b.layer?.backgroundColor = (tint ?? NSColor.controlAccentColor).cgColor
        b.contentTintColor = NSColor.white
        setButtonTitleColor(b, NSColor.white)
    } else {
        b.layer?.backgroundColor = NSColor.gray.withAlphaComponent(0.16).cgColor
    }
}

/// Marks a (non-prominent) glass button as the active choice, e.g. the current editor tool.
@MainActor
func setGlassButtonSelected(_ b: NSButton, _ selected: Bool) {
    #if compiler(>=6.2)
    if #available(macOS 26.0, *) {
        b.bezelColor = selected ? NSColor.controlAccentColor : nil
        b.contentTintColor = selected ? NSColor.white : nil
        setButtonTitleColor(b, selected ? NSColor.white : NSColor.labelColor)
        return
    }
    #endif
    b.wantsLayer = true
    b.layer?.backgroundColor = selected
        ? NSColor.controlAccentColor.withAlphaComponent(0.35).cgColor
        : NSColor.gray.withAlphaComponent(0.16).cgColor
}

@MainActor
func setButtonTitleColor(_ b: NSButton, _ color: NSColor, font: NSFont? = nil) {
    let para = NSMutableParagraphStyle()
    para.alignment = .center
    let f = font ?? b.font ?? NSFont.systemFont(ofSize: NSFont.systemFontSize)
    b.attributedTitle = NSAttributedString(string: b.title, attributes: [
        .foregroundColor: color,
        .font: f,
        .paragraphStyle: para
    ])
}

/// Applies the transparent-titlebar look used by every MiniSnap window so the glass background reads well.
@MainActor
func applyGlassWindowStyle(_ w: NSWindow) {
    w.titlebarAppearsTransparent = true
    w.styleMask.insert(.fullSizeContentView)
}

/// Builds a window content view with a glass/visual-effect background filling the whole window.
/// Returns (root, content) — put your UI in `content`.
@MainActor
func makeGlassWindowBackground() -> (root: NSView, content: NSView) {
    let root = NSView()
    let (bg, content) = makeGlassContainer(cornerRadius: 0, tint: nil, material: .popover)
    root.addSubview(bg)
    NSLayoutConstraint.activate([
        bg.leadingAnchor.constraint(equalTo: root.leadingAnchor),
        bg.trailingAnchor.constraint(equalTo: root.trailingAnchor),
        bg.topAnchor.constraint(equalTo: root.topAnchor),
        bg.bottomAnchor.constraint(equalTo: root.bottomAnchor)
    ])
    return (root, content)
}

/// Creates a symbol image, or nil when the symbol does not exist on this system.
@MainActor
func symbol(_ name: String, size: CGFloat = 15, weight: NSFont.Weight = .regular) -> NSImage? {
    guard let img = NSImage(systemSymbolName: name, accessibilityDescription: nil) else { return nil }
    let cfg = NSImage.SymbolConfiguration(pointSize: size, weight: weight)
    return img.withSymbolConfiguration(cfg) ?? img
}

/// A small always-on-top glass panel that never takes focus (recording bar, scrolling-capture status).
/// Our own windows are excluded from ScreenCaptureKit captures by the content filter (excluding this app).
@MainActor
class FloatingBar: NSPanel {
    let stack = NSStackView()

    // A convenience init keeps NSWindow's designated initializers inherited (no init(coder:) boilerplate).
    convenience init() {
        self.init(contentRect: NSRect(x: 0, y: 0, width: 300, height: 48),
                  styleMask: [.borderless, .nonactivatingPanel],
                  backing: .buffered, defer: false)
        setUpBar()
    }

    private func setUpBar() {
        isFloatingPanel = true
        level = .statusBar
        hidesOnDeactivate = false
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        isMovableByWindowBackground = true
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        sharingType = .none

        let (container, content) = makeGlassContainer(cornerRadius: 14, tint: nil, material: .hud)
        container.appearance = NSAppearance(named: .darkAqua)
        stack.orientation = .horizontal
        stack.spacing = 8
        stack.alignment = .centerY
        stack.edgeInsets = NSEdgeInsets(top: 8, left: 12, bottom: 8, right: 8)
        stack.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            stack.topAnchor.constraint(equalTo: content.topAnchor),
            stack.bottomAnchor.constraint(equalTo: content.bottomAnchor)
        ])
        let host = NSView()
        host.addSubview(container)
        NSLayoutConstraint.activate([
            container.leadingAnchor.constraint(equalTo: host.leadingAnchor),
            container.trailingAnchor.constraint(equalTo: host.trailingAnchor),
            container.topAnchor.constraint(equalTo: host.topAnchor),
            container.bottomAnchor.constraint(equalTo: host.bottomAnchor)
        ])
        contentView = host
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    func makeButton(_ title: String, symbolName: String, target: AnyObject?, action: Selector) -> NSButton {
        let b = NSButton(title: title, target: target, action: action)
        b.image = symbol(symbolName, size: 13, weight: .semibold)
        b.imagePosition = .imageLeading
        b.controlSize = .large
        styleGlassButton(b, prominent: false, tint: nil)
        if !glassAvailable() {
            b.translatesAutoresizingMaskIntoConstraints = false
            b.heightAnchor.constraint(equalToConstant: 30).isActive = true
            b.widthAnchor.constraint(greaterThanOrEqualToConstant: 80).isActive = true
        }
        return b
    }

    func makeLabel(_ text: String, bold: Bool = false) -> NSTextField {
        let l = NSTextField(labelWithString: text)
        l.textColor = .white
        l.font = bold ? NSFont.monospacedDigitSystemFont(ofSize: 15, weight: .bold) : NSFont.systemFont(ofSize: 13)
        return l
    }

    /// Fits the panel to its content and puts it just below (or above, or inside) `target` (Cocoa coordinates).
    func place(near target: NSRect, on screen: NSScreen?) {
        guard let cv = contentView else { return }
        cv.layoutSubtreeIfNeeded()
        let size = cv.fittingSize
        let vf = (screen ?? NSScreen.main)?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let gap: CGFloat = 8
        var x = target.midX - size.width / 2
        x = max(vf.minX, min(x, vf.maxX - size.width))
        var y = target.minY - gap - size.height           // below
        if y < vf.minY { y = target.maxY + gap }          // above
        if y + size.height > vf.maxY { y = target.minY + gap } // inside, bottom edge
        setFrame(NSRect(x: x, y: y, width: size.width, height: size.height), display: true)
    }
}

/// Renders `content` (a view filling the window) to a PNG without showing the window, over a plain
/// window-coloured background since the glass only draws on screen. Used for CI screenshots.
@MainActor
func writeWindowSnapshot(_ window: NSWindow, content view: NSView, to url: URL) -> Bool {
    window.contentView?.layoutSubtreeIfNeeded()
    guard let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return false }
    view.cacheDisplay(in: view.bounds, to: rep)
    let size = view.bounds.size
    guard let out = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: rep.pixelsWide, pixelsHigh: rep.pixelsHigh,
                                     bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                     colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) else { return false }
    out.size = size
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: out)
    window.effectiveAppearance.performAsCurrentDrawingAppearance {
        NSColor.windowBackgroundColor.setFill()
        NSRect(origin: .zero, size: size).fill()
    }
    rep.draw(in: NSRect(origin: .zero, size: size))
    NSGraphicsContext.restoreGraphicsState()
    guard let data = out.representation(using: .png, properties: [:]) else { return false }
    return (try? data.write(to: url)) != nil
}
