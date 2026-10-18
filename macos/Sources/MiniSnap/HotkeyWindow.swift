import AppKit
import Carbon

/// Click it, press a key combination, and it shows/stores that combination.
/// While focused, a local event monitor swallows every key (even ⌘Q) so any combo can be recorded.
@MainActor
final class HotkeyField: NSView {
    var value: Hotkey = Hotkey.empty {
        didSet { needsDisplay = true }
    }
    var onChange: (() -> Void)?

    private var recording = false
    private var transient: String?
    private var transientIsError = false
    private var monitor: Any?
    private var revertTask: Task<Void, Never>?

    override var acceptsFirstResponder: Bool { true }
    override var intrinsicContentSize: NSSize { NSSize(width: 190, height: 26) }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
    }

    override func becomeFirstResponder() -> Bool {
        recording = true
        transient = nil
        installMonitor()
        needsDisplay = true
        return true
    }

    override func resignFirstResponder() -> Bool {
        recording = false
        transient = nil
        removeMonitor()
        needsDisplay = true
        return true
    }

    override func viewWillMove(toWindow newWindow: NSWindow?) {
        if newWindow == nil { removeMonitor() }
        super.viewWillMove(toWindow: newWindow)
    }

    func clearKey() {
        value = Hotkey.empty
        onChange?()
    }

    private func installMonitor() {
        removeMonitor()
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged]) { [weak self] event in
            var consumed = false
            MainActor.assumeIsolated {
                consumed = self?.handle(event) ?? false
            }
            return consumed ? nil : event
        }
    }

    private func removeMonitor() {
        if let m = monitor { NSEvent.removeMonitor(m) }
        monitor = nil
    }

    private func handle(_ event: NSEvent) -> Bool {
        guard recording, window?.isKeyWindow == true else { return false }
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let mods = Hotkey.carbonMods(from: flags)
        if event.type == .flagsChanged {
            transient = mods == 0 ? nil : Hotkey.modifierSymbols(mods) + " …"
            transientIsError = false
            needsDisplay = true
            return true
        }
        let code = UInt32(event.keyCode)
        if KeyNames.isModifierKey(event.keyCode) { return true }
        if mods == 0 && (code == UInt32(kVK_Delete) || code == UInt32(kVK_ForwardDelete)) {
            clearKey()
            return true
        }
        if mods == 0 && code == UInt32(kVK_Escape) {
            transient = nil
            window?.makeFirstResponder(nil)
            return true
        }
        if mods == 0 && code == UInt32(kVK_Tab) { return false }
        let candidate = Hotkey(mods: mods, keyCode: code)
        if !candidate.hasCommandLikeModifier && !Hotkey.allowedAlone(code) {
            showError(L.t("Cần kèm ⌘, ⌥ hoặc ⌃"))
            return true
        }
        transient = nil
        revertTask?.cancel()
        value = candidate
        // Done: leave recording mode at once so the new combination shows (and is saved by onChange).
        window?.makeFirstResponder(nil)
        flashSaved()
        onChange?()
        return true
    }

    /// A short green outline after a combination was recorded.
    private var savedFlash = false

    private func flashSaved() {
        savedFlash = true
        needsDisplay = true
        revertTask?.cancel()
        revertTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 1_200_000_000)
            if Task.isCancelled { return }
            self?.savedFlash = false
            self?.needsDisplay = true
        }
    }

    private func showError(_ text: String) {
        transient = text
        transientIsError = true
        needsDisplay = true
        revertTask?.cancel()
        revertTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 1_600_000_000)
            if Task.isCancelled { return }
            self?.transient = nil
            self?.needsDisplay = true
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        let r = bounds.insetBy(dx: 1, dy: 1)
        let path = NSBezierPath(roundedRect: r, xRadius: 6, yRadius: 6)
        let bg: NSColor = recording
            ? NSColor(calibratedRed: 1.0, green: 0.97, blue: 0.88, alpha: 1)
            : NSColor.textBackgroundColor
        bg.setFill()
        path.fill()
        (recording ? NSColor.controlAccentColor : savedFlash ? NSColor.systemGreen : NSColor.separatorColor).setStroke()
        path.lineWidth = recording || savedFlash ? 2 : 1
        path.stroke()

        let text: String
        var color: NSColor = recording ? NSColor.black : NSColor.labelColor
        if let t = transient {
            text = t
            if transientIsError { color = NSColor.systemRed }
        } else if recording {
            text = L.t("Nhấn tổ hợp phím...")
            color = NSColor.darkGray
        } else {
            text = value.displayText
            if value.isNone { color = NSColor.secondaryLabelColor }
        }
        let para = NSMutableParagraphStyle()
        para.alignment = .center
        para.lineBreakMode = .byTruncatingTail
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 13, weight: .medium),
            .foregroundColor: color,
            .paragraphStyle: para
        ]
        let s = NSAttributedString(string: text, attributes: attrs)
        let h = s.size().height
        s.draw(in: NSRect(x: r.minX + 4, y: r.midY - h / 2, width: r.width - 8, height: h))
    }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .pointingHand)
    }
}

/// "Keyboard shortcuts" window: one row per action with a recorder field, clear button and status.
@MainActor
final class HotkeySettingsWindow: NSObject, NSWindowDelegate {
    let window: NSWindow
    private var fields: [HotkeyAction: HotkeyField] = [:]
    private var statuses: [HotkeyAction: NSTextField] = [:]
    private var saveButton = NSButton()
    private let footer = NSTextField(labelWithString: "")
    private var body: NSView?
    private let apply: ([HotkeyAction: Hotkey]) -> [HotkeyAction]
    var onClose: (() -> Void)?

    /// apply: saves + registers the map, returns the actions whose key could not be registered.
    init(current: [HotkeyAction: Hotkey], apply: @escaping ([HotkeyAction: Hotkey]) -> [HotkeyAction]) {
        self.apply = apply
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 760, height: 420),
                          styleMask: [.titled, .closable],
                          backing: .buffered, defer: false)
        super.init()
        window.isReleasedWhenClosed = false
        window.title = L.t("Cài đặt phím tắt — MiniSnap")
        window.level = .floating
        window.delegate = self
        applyGlassWindowStyle(window)
        build(current)
        refreshStatus()
    }

    private func build(_ current: [HotkeyAction: Hotkey]) {
        let (root, content) = makeGlassWindowBackground()

        let intro = NSTextField(wrappingLabelWithString: L.t("Bấm vào ô bên phải rồi nhấn tổ hợp phím mới, ví dụ ⌥⇧2 hoặc F9.\nDelete để bỏ phím tắt, Esc để giữ phím cũ. Phím tắt dùng được ở mọi nơi, kể cả khi đang ở app khác."))
        intro.preferredMaxLayoutWidth = 480
        intro.textColor = .secondaryLabelColor

        var rows: [[NSView]] = []
        for a in HotkeyAction.allCases {
            let icon = NSImageView()
            icon.image = symbol(a.symbolName, size: 15)
            icon.contentTintColor = .controlAccentColor
            let name = NSTextField(labelWithString: a.label)
            let field = HotkeyField()
            field.value = current[a] ?? Hotkey.empty
            field.onChange = { [weak self] in self?.changed(a) }
            let clear = NSButton(title: "✕", target: self, action: #selector(clearPressed(_:)))
            clear.tag = a.rawValue
            clear.toolTip = L.t("Bỏ phím tắt này")
            styleGlassButton(clear, prominent: false, tint: nil)
            if !glassAvailable() {
                clear.translatesAutoresizingMaskIntoConstraints = false
                clear.widthAnchor.constraint(equalToConstant: 28).isActive = true
                clear.heightAnchor.constraint(equalToConstant: 24).isActive = true
            }
            let status = NSTextField(labelWithString: "")
            status.textColor = .secondaryLabelColor
            status.lineBreakMode = .byTruncatingTail
            status.translatesAutoresizingMaskIntoConstraints = false
            status.alignment = .center
            status.font = NSFont.systemFont(ofSize: 13, weight: .semibold)
            // Just a ✓ or ⚠ (details in its tooltip and the line at the bottom), so no empty column widens the window.
            status.widthAnchor.constraint(equalToConstant: 20).isActive = true
            fields[a] = field
            statuses[a] = status
            rows.append([icon, name, field, clear, status])
        }
        let grid = NSGridView(views: rows)
        grid.rowSpacing = 8
        grid.columnSpacing = 10
        grid.yPlacement = .center
        grid.column(at: 0).xPlacement = .center

        let reset = NSButton(title: L.t("Khôi phục mặc định"), target: self, action: #selector(resetPressed))
        styleGlassButton(reset, prominent: false, tint: nil)
        saveButton = NSButton(title: L.t("Lưu"), target: self, action: #selector(savePressed))
        saveButton.keyEquivalent = "\r"
        styleGlassButton(saveButton, prominent: true, tint: NSColor.systemBlue)
        let close = NSButton(title: L.t("Đóng"), target: self, action: #selector(closePressed))
        styleGlassButton(close, prominent: false, tint: nil)
        for b in [reset, saveButton, close] where !glassAvailable() {
            b.translatesAutoresizingMaskIntoConstraints = false
            b.heightAnchor.constraint(equalToConstant: 30).isActive = true
            b.widthAnchor.constraint(greaterThanOrEqualToConstant: 96).isActive = true
        }
        footer.textColor = .systemRed
        footer.lineBreakMode = .byWordWrapping
        footer.maximumNumberOfLines = 2
        footer.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        let spacer = NSView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        let buttons = NSStackView(views: [reset, footer, spacer, saveButton, close])
        buttons.orientation = .horizontal
        buttons.spacing = 10

        let stack = NSStackView(views: [intro, grid, buttons])
        body = stack
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 14
        stack.edgeInsets = NSEdgeInsets(top: 40, left: 20, bottom: 18, right: 20)
        stack.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            stack.topAnchor.constraint(equalTo: content.topAnchor),
            stack.bottomAnchor.constraint(equalTo: content.bottomAnchor),
            buttons.widthAnchor.constraint(equalTo: grid.widthAnchor),
            intro.widthAnchor.constraint(equalTo: grid.widthAnchor)
        ])
        window.contentView = root
        root.layoutSubtreeIfNeeded()
        // The stack's own size: the glass background does not report it, which cut off the right side.
        window.setContentSize(stack.fittingSize)
        window.center()
    }

    func show() {
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        // Start with nothing focused so a stray key press can't overwrite the first shortcut.
        window.makeFirstResponder(nil)
    }

    var values: [HotkeyAction: Hotkey] {
        var m: [HotkeyAction: Hotkey] = [:]
        for (a, f) in fields { m[a] = f.value }
        return m
    }

    private func mark(_ st: NSTextField, _ symbol: String, _ color: NSColor, _ message: String?) {
        st.stringValue = symbol
        st.textColor = color
        st.toolTip = message
    }

    /// Marks duplicates and enables Save only when every shortcut is unique.
    @discardableResult
    private func refreshStatus() -> Bool {
        var ok = true
        let v = values
        for a in HotkeyAction.allCases {
            let h = v[a] ?? Hotkey.empty
            var clash: HotkeyAction?
            if !h.isNone {
                for other in HotkeyAction.allCases where other != a && v[other] == h {
                    clash = other
                    break
                }
            }
            guard let st = statuses[a] else { continue }
            if let c = clash {
                ok = false
                mark(st, "⚠", .systemRed, L.t("⚠ Trùng: ") + c.label)
            } else {
                mark(st, "", .secondaryLabelColor, h.isNone ? L.t("Chỉ dùng từ menu") : nil)
            }
        }
        saveButton.isEnabled = ok
        footer.textColor = .systemRed
        footer.stringValue = ok ? "" : L.t("Mỗi phím tắt chỉ được gán cho một chức năng.")
        return ok
    }

    /// Every change is saved and applied at once (when no two actions share a key), like System Settings,
    /// so a recorded combination is visibly done. `action` nil = all rows changed (Restore defaults).
    private func changed(_ action: HotkeyAction?) {
        guard refreshStatus() else { return }
        let failed = apply(values)
        for a in HotkeyAction.allCases {
            guard let st = statuses[a] else { continue }
            if failed.contains(a) {
                mark(st, "⚠", .systemRed, L.t("⚠ App khác đang dùng phím này"))
            } else if (action == nil || action == a), !(fields[a]?.value.isNone ?? true) {
                mark(st, "✓", .systemGreen, L.t("✓ Đã lưu"))
            }
        }
        if failed.isEmpty {
            footer.textColor = .systemGreen
            footer.stringValue = L.t("Đã lưu và áp dụng.")
        } else {
            footer.textColor = .systemRed
            footer.stringValue = L.t("Đã lưu, nhưng ") + String(failed.count) + L.t(" phím đang bị app khác chiếm — hãy chọn phím khác.")
        }
    }

    @objc private func clearPressed(_ sender: NSButton) {
        guard let a = HotkeyAction(rawValue: sender.tag) else { return }
        fields[a]?.clearKey()
    }

    @objc private func resetPressed() {
        let d = HotkeySettings.defaults()
        for (a, f) in fields { f.value = d[a] ?? Hotkey.empty }
        changed(nil)
    }

    @objc private func savePressed() {
        window.makeFirstResponder(nil)
        guard refreshStatus() else { return }
        let failed = apply(values)
        for a in HotkeyAction.allCases {
            guard let st = statuses[a] else { continue }
            if failed.contains(a) {
                mark(st, "⚠", .systemRed, L.t("⚠ App khác đang dùng phím này"))
            } else if !(fields[a]?.value.isNone ?? true) {
                mark(st, "✓", .systemGreen, L.t("✓ Đã lưu"))
            }
        }
        if failed.isEmpty {
            footer.textColor = .systemGreen
            footer.stringValue = L.t("Đã lưu và áp dụng.")
            window.close()
        } else {
            footer.textColor = .systemRed
            footer.stringValue = L.t("Đã lưu, nhưng ") + String(failed.count) + L.t(" phím đang bị app khác chiếm — hãy chọn phím khác.")
        }
    }

    /// CI screenshot of the window (see writeWindowSnapshot).
    func writeSnapshot(to url: URL) -> Bool {
        guard let view = body else { return false }
        return writeWindowSnapshot(window, content: view, to: url)
    }

    @objc private func closePressed() {
        window.close()
    }

    func windowWillClose(_ notification: Notification) {
        window.makeFirstResponder(nil)
        onClose?()
    }
}
