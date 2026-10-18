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
            Entry(action: .ocr, title: L.t("Chụp và trích chữ (OCR)"), symbolName: "text.viewfinder", tint: .systemPurple),
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
        let b = NSButton(title: e.title, target: self, action: #selector(tilePressed(_:)))
        b.tag = tag
        b.image = symbol(e.symbolName, size: 18, weight: .semibold)
        b.imagePosition = .imageLeading
        b.imageHugsTitle = true
        b.font = NSFont.systemFont(ofSize: 13, weight: .semibold)
        b.toolTip = shortcut.map { e.title + " (" + $0 + ")" } ?? e.title
        styleGlassButton(b, prominent: true, tint: e.tint)
        let para = NSMutableParagraphStyle()
        para.alignment = .left
        let title = NSMutableAttributedString(string: e.title, attributes: [
            .foregroundColor: NSColor.white, .font: NSFont.systemFont(ofSize: 13, weight: .semibold), .paragraphStyle: para])
        if let s = shortcut {
            title.append(NSAttributedString(string: "\n" + s, attributes: [
                .foregroundColor: NSColor.white.withAlphaComponent(0.78), .font: NSFont.systemFont(ofSize: 11), .paragraphStyle: para]))
        }
        b.attributedTitle = title
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
