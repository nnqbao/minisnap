import AppKit

/// The window shown when MiniSnap is opened (and again when it is opened while already running), so people
/// can see the app is running: big buttons for every capture, and where to find the menu-bar icon.
/// MiniSnap itself lives in the menu bar; closing this window keeps it running there.
@MainActor
final class LauncherWindow: NSObject, NSWindowDelegate {
    struct Entry {
        let action: HotkeyAction?
        let title: String
        let symbolName: String
        let tint: NSColor
    }

    let window: NSWindow
    var onClose: (() -> Void)?
    private let keys: [HotkeyAction: Hotkey]
    private let recording: Bool
    private let perform: (HotkeyAction?) -> Void
    private var entries: [Entry] = []
    private var body: NSView?

    /// `perform(nil)` means "Open image...".
    init(keys: [HotkeyAction: Hotkey], recording: Bool, perform: @escaping (HotkeyAction?) -> Void) {
        self.keys = keys
        self.recording = recording
        self.perform = perform
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 520, height: 520),
                          styleMask: [.titled, .closable, .miniaturizable],
                          backing: .buffered, defer: false)
        super.init()
        window.isReleasedWhenClosed = false
        window.title = "MiniSnap"
        window.delegate = self
        applyGlassWindowStyle(window)
        build()
        window.center()
    }

    private func build() {
        let (root, content) = makeGlassWindowBackground()

        let icon = NSImageView()
        icon.image = NSApp.applicationIconImage
        icon.imageScaling = .scaleProportionallyUpOrDown
        icon.translatesAutoresizingMaskIntoConstraints = false
        icon.widthAnchor.constraint(equalToConstant: 56).isActive = true
        icon.heightAnchor.constraint(equalToConstant: 56).isActive = true
        let name = NSTextField(labelWithString: "MiniSnap")
        name.font = NSFont.systemFont(ofSize: 24, weight: .bold)
        let tagline = NSTextField(labelWithString: L.t("Chụp ảnh, quay video màn hình và trích chữ"))
        tagline.textColor = .secondaryLabelColor
        let titles = NSStackView(views: [name, tagline])
        titles.orientation = .vertical
        titles.alignment = .leading
        titles.spacing = 2
        let header = NSStackView(views: [icon, titles])
        header.spacing = 14
        header.alignment = .centerY

        entries = [
            Entry(action: .captureRegion, title: L.t("Chụp vùng / cửa sổ"), symbolName: "camera.viewfinder", tint: .systemBlue),
            Entry(action: .captureFullScreen, title: L.t("Chụp toàn màn hình"), symbolName: "macwindow", tint: .systemBlue),
            Entry(action: .captureDelayed, title: L.t("Chụp sau 3 giây"), symbolName: "timer", tint: .systemGray),
            Entry(action: .scrollCapture, title: L.t("Chụp cuộn trang dài"), symbolName: "arrow.down.doc", tint: .systemOrange),
            Entry(action: .recordVideo, title: recording ? L.t("Dừng quay video") : L.t("Quay video màn hình"),
                  symbolName: recording ? "stop.circle" : "record.circle", tint: .systemRed),
            Entry(action: .ocr, title: L.t("Trích chữ (OCR)"), symbolName: "text.viewfinder", tint: .systemPurple),
            Entry(action: .library, title: L.t("Thư viện ảnh & video"), symbolName: "photo.on.rectangle", tint: .systemGreen),
            Entry(action: nil, title: L.t("Mở ảnh..."), symbolName: "folder", tint: .systemTeal),
        ]
        var rows: [[NSView]] = []
        for (i, e) in entries.enumerated() {
            let tile = makeTile(e, tag: i)
            if i % 2 == 0 { rows.append([tile]) } else { rows[rows.count - 1].append(tile) }
        }
        let grid = NSGridView(views: rows)
        grid.rowSpacing = 10
        grid.columnSpacing = 10
        for c in 0..<grid.numberOfColumns { grid.column(at: c).width = LauncherWindow.tileWidth }

        // Where MiniSnap lives once this window is closed.
        let hintIcon = NSImageView()
        hintIcon.image = symbol("camera.viewfinder", size: 16, weight: .medium)
        hintIcon.contentTintColor = .controlAccentColor
        let hintText = NSTextField(wrappingLabelWithString: L.t("MiniSnap chạy trên thanh menu: bấm biểu tượng này ở góc trên bên phải màn hình để chụp bất cứ lúc nào, kể cả khi đã đóng cửa sổ này."))
        hintText.preferredMaxLayoutWidth = 2 * LauncherWindow.tileWidth - 20
        hintText.textColor = .secondaryLabelColor
        let hint = NSStackView(views: [hintIcon, hintText])
        hint.spacing = 10
        hint.alignment = .top

        let showAtStart = NSButton(checkboxWithTitle: L.t("Hiện cửa sổ này khi mở MiniSnap"), target: self, action: #selector(toggleShowAtStart(_:)))
        showAtStart.state = Prefs.showLauncherAtStart ? .on : .off
        let close = NSButton(title: L.t("Đóng"), target: self, action: #selector(closePressed))
        close.keyEquivalent = "\u{1b}"
        styleGlassButton(close, prominent: false, tint: nil)
        if !glassAvailable() {
            close.translatesAutoresizingMaskIntoConstraints = false
            close.heightAnchor.constraint(equalToConstant: 28).isActive = true
            close.widthAnchor.constraint(greaterThanOrEqualToConstant: 90).isActive = true
        }
        let spacer = NSView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        let footer = NSStackView(views: [showAtStart, spacer, close])
        footer.alignment = .centerY

        let stack = NSStackView(views: [header, grid, hint, footer])
        body = stack
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 18
        stack.edgeInsets = NSEdgeInsets(top: 40, left: 24, bottom: 20, right: 24)
        stack.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            stack.topAnchor.constraint(equalTo: content.topAnchor),
            stack.bottomAnchor.constraint(equalTo: content.bottomAnchor),
            footer.widthAnchor.constraint(equalTo: grid.widthAnchor),
        ])
        window.contentView = root
        root.layoutSubtreeIfNeeded()
        window.setContentSize(root.fittingSize)
    }

    static let tileWidth: CGFloat = 250

    /// A big tinted button: symbol and name, with the global shortcut (when set) on a second, smaller line.
    private func makeTile(_ e: Entry, tag: Int) -> NSView {
        let shortcut = e.action.flatMap { keys[$0]?.shortText }
        let b = LauncherTile(title: e.title, shortcut: shortcut, image: symbol(e.symbolName, size: 18, weight: .semibold), tint: e.tint)
        b.target = self
        b.action = #selector(tilePressed(_:))
        b.tag = tag
        b.toolTip = shortcut.map { e.title + " (" + $0 + ")" } ?? e.title
        b.setAccessibilityLabel(e.title)
        b.translatesAutoresizingMaskIntoConstraints = false
        b.widthAnchor.constraint(equalToConstant: LauncherWindow.tileWidth).isActive = true
        b.heightAnchor.constraint(equalToConstant: 50).isActive = true
        return b
    }

    func show() {
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    /// The capture must not show this window: it goes away first, then the action runs.
    @objc private func tilePressed(_ sender: NSButton) {
        guard sender.tag >= 0 && sender.tag < entries.count else { return }
        let action = entries[sender.tag].action
        let run = perform      // closing may release this window controller
        window.close()
        run(action)
    }

    @objc private func toggleShowAtStart(_ sender: NSButton) { Prefs.showLauncherAtStart = sender.state == .on }
    @objc private func closePressed() { window.close() }

    func windowWillClose(_ notification: Notification) { onClose?() }

    /// Renders the window's content to a PNG without showing it (CI screenshots). The glass background only
    /// draws on screen, so the content is drawn over a plain window-coloured background instead.
    func writeSnapshot(to url: URL) -> Bool {
        guard let root = window.contentView, let view = body else { return false }
        root.layoutSubtreeIfNeeded()
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
}

/// A launcher button drawn by hand: a rounded tile in its colour with a white symbol, the name and the shortcut.
/// Drawn rather than a glass bezel so it looks the same on every macOS version (and in CI snapshots).
@MainActor
final class LauncherTile: NSButton {
    private let label: String
    private let shortcut: String?
    private let glyph: NSImage?
    private let tint: NSColor
    private var hovering = false

    init(title: String, shortcut: String?, image: NSImage?, tint: NSColor) {
        label = title
        self.shortcut = shortcut
        glyph = image
        self.tint = tint
        super.init(frame: NSRect(x: 0, y: 0, width: 250, height: 50))
        self.title = title
        isBordered = false
        setButtonType(.momentaryChange)
        focusRingType = .default
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        for t in trackingAreas { removeTrackingArea(t) }
        addTrackingArea(NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect],
                                       owner: self, userInfo: nil))
    }

    override var isFlipped: Bool { false }     // y up, as the layout below assumes

    override func mouseEntered(with event: NSEvent) { hovering = true; needsDisplay = true }
    override func mouseExited(with event: NSEvent) { hovering = false; needsDisplay = true }

    override func draw(_ dirtyRect: NSRect) {
        let r = bounds.insetBy(dx: 0.5, dy: 0.5)
        let base = tint.usingColorSpace(.sRGB) ?? tint
        let fill = isHighlighted ? base.blended(withFraction: 0.25, of: .black) ?? base
            : hovering ? base.blended(withFraction: 0.12, of: .white) ?? base : base
        fill.setFill()
        NSBezierPath(roundedRect: r, xRadius: 12, yRadius: 12).fill()

        var x: CGFloat = 14
        if let g = glyph {
            let tinted = NSImage(size: g.size, flipped: false) { rect in
                g.draw(in: rect)
                NSColor.white.set()
                rect.fill(using: .sourceAtop)
                return true
            }
            let gr = NSRect(x: x, y: (bounds.height - g.size.height) / 2, width: g.size.width, height: g.size.height)
            tinted.draw(in: gr)
            x += max(24, g.size.width) + 10
        }
        let width = bounds.width - x - 10
        let titleAttrs: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 13, weight: .semibold), .foregroundColor: NSColor.white]
        let titleSize = (label as NSString).size(withAttributes: titleAttrs)
        if let s = shortcut {
            let subAttrs: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 11), .foregroundColor: NSColor.white.withAlphaComponent(0.8)]
            let subSize = (s as NSString).size(withAttributes: subAttrs)
            let top = (bounds.height + titleSize.height + subSize.height) / 2
            (label as NSString).draw(with: NSRect(x: x, y: top - titleSize.height, width: width, height: titleSize.height),
                                     options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine], attributes: titleAttrs)
            (s as NSString).draw(with: NSRect(x: x, y: top - titleSize.height - subSize.height, width: width, height: subSize.height),
                                 options: [.usesLineFragmentOrigin], attributes: subAttrs)
        } else {
            (label as NSString).draw(with: NSRect(x: x, y: (bounds.height - titleSize.height) / 2, width: width, height: titleSize.height),
                                     options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine], attributes: titleAttrs)
        }
        if window?.firstResponder === self && NSApp.isActive {
            NSColor.keyboardFocusIndicatorColor.setStroke()
            let ring = NSBezierPath(roundedRect: bounds.insetBy(dx: 1.5, dy: 1.5), xRadius: 11, yRadius: 11)
            ring.lineWidth = 3
            ring.stroke()
        }
    }
}
