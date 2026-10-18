import AppKit
import Carbon
import UniformTypeIdentifiers

/// The annotation editor (one window per image).
@MainActor
final class EditorController: NSObject, NSWindowDelegate {
    private struct State {
        let base: CGImage
        let shapes: [Shape]
    }

    static let palette: [RGBAColor] = [
        RGBAColor(232, 38, 38), RGBAColor(255, 140, 0), RGBAColor(255, 214, 0), RGBAColor(40, 170, 70),
        RGBAColor(30, 120, 230), RGBAColor(150, 70, 200), RGBAColor(30, 30, 30), RGBAColor(255, 255, 255)
    ]
    static let widths: [CGFloat] = [2, 3, 5, 8, 12, 16]

    let window: EditorWindow
    var onClose: (() -> Void)?
    var onNewCapture: (() -> Void)?
    var onOcr: ((CGImage) -> Void)?
    var onLibrary: (() -> Void)?
    var skipSavePrompt = false

    // Document
    private var base: CGImage
    private var shapes: [Shape] = []
    private(set) var cache: CGImage?
    private var undoStack: [State] = []
    private var redoStack: [State] = []
    private var fileURL: URL?
    private var dirty = false
    /// Image pixels per screen point when the image was captured (2 for Retina captures).
    private let imageScale: CGFloat

    // Tool state
    private(set) var tool: Tool = .arrow
    private var color = EditorController.palette[0]
    private var strokeWidth: CGFloat = 5
    private var blurCell = 2
    private var blurSmooth = 0
    private(set) var current: Shape?
    private(set) var selected: Shape?
    private var mouseIsDown = false
    private var movedSelected = false
    private(set) var cropping = false
    private(set) var cropRect = CGRect.zero
    private var downPt = CGPoint.zero
    private var lastPt = CGPoint.zero

    // Text editing
    private var textView: AnnotationTextView?
    private var textPos = CGPoint.zero
    private var textColor = RGBAColor(0, 0, 0)
    private var textWidth: CGFloat = 5
    private var editingText: TextShape?
    private var editingIndex = 0

    // UI
    private let scrollView = NSScrollView()
    private let canvas = CanvasView(frame: .zero)
    private var toolButtons: [Tool: NSButton] = [:]
    private var swatches: [SwatchButton] = []
    private var customSwatch = SwatchButton(frame: .zero)
    private var widthPopup = NSPopUpButton(frame: .zero, pullsDown: false)
    private var widthViews: [NSView] = []
    private var blurViews: [NSView] = []
    private let cellSlider = NSSlider(value: 2, minValue: 1, maxValue: Double(BlurShape.maxCell), target: nil, action: nil)
    private let smoothSlider = NSSlider(value: 0, minValue: 0, maxValue: Double(BlurShape.maxSmooth), target: nil, action: nil)
    private let cellValue = NSTextField(labelWithString: "2")
    private let smoothValue = NSTextField(labelWithString: "0")
    private var sliderUndoPending = false
    private var undoButton = NSButton()
    private var redoButton = NSButton()
    private var copyButton = NSButton()
    private var saveButton = NSButton()
    private var saveAsButton = NSButton()
    private let zoomLabel = NSTextField(labelWithString: "100%")
    private let sizeLabel = NSTextField(labelWithString: "")
    private let posLabel = NSTextField(labelWithString: "")
    private let infoLabel = NSTextField(labelWithString: "")
    private var flashTasks: [ObjectIdentifier: Task<Void, Never>] = [:]
    private weak var savePanel: NSSavePanel?

    init(image: CGImage, url: URL?, imageScale: CGFloat) {
        base = image
        fileURL = url
        self.imageScale = max(1, imageScale)
        window = EditorWindow(contentRect: NSRect(x: 0, y: 0, width: 1200, height: 800),
                              styleMask: [.titled, .closable, .miniaturizable, .resizable],
                              backing: .buffered, defer: false)
        super.init()
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.minSize = NSSize(width: 980, height: 440)
        window.tabbingMode = .disallowed
        applyGlassWindowStyle(window)
        window.keyHandler = { [weak self] e in self?.handleKeyEquivalent(e) ?? false }
        buildUI()
        rerender()
        updateTitle()
        updateToolButtons()
        updateSwatches()
        updateUndoButtons()
    }

    // MARK: - Public

    private var toolsBar: NSView?
    private var toolsRow: NSView?
    private var propsBar: NSView?

    /// CI screenshot of the tools row (the glass background around it only draws on screen).
    func writeToolbarSnapshot(to url: URL) -> Bool {
        guard let row = toolsRow else { return false }
        return writeWindowSnapshot(window, content: row, to: url)
    }

    /// Where the toolbar and its buttons really are, in window points (top-left origin), for CI.
    func layoutReport() -> String {
        window.layoutIfNeeded()
        let h = window.frame.height
        func r(_ v: NSView?) -> String {
            guard let v = v else { return "nil" }
            let f = v.convert(v.bounds, to: nil)
            return String(format: "y=%.1f..%.1f x=%.1f w=%.1f", h - f.maxY, h - f.minY, f.minX, f.width)
        }
        let first = toolButtons[.select]
        var lines = [
            String(format: "window h=%.1f contentLayoutRect top=%.1f", h, h - window.contentLayoutRect.maxY),
            "toolsBar " + r(toolsBar), "toolsRow " + r(toolsRow), "selectButton " + r(first), "copyButton " + r(copyButton),
            "propsBar " + r(propsBar), "undoButton " + r(undoButton), "widthPopup " + r(widthPopup),
        ]
        if let b = first {
            lines.append(String(format: "selectButton alignmentRectInsets t=%.1f b=%.1f fitting h=%.1f bezel=%d",
                                b.alignmentRectInsets.top, b.alignmentRectInsets.bottom, b.fittingSize.height, b.bezelStyle.rawValue))
        }
        return lines.joined(separator: " | ")
    }

    var magnification: CGFloat { scrollView.magnification }
    var devicePixelsPerImagePixel: CGFloat { scrollView.magnification * (window.backingScaleFactor) }

    func show() {
        sizeWindowToImage()
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        window.layoutIfNeeded()
        fitZoom()
        window.makeFirstResponder(canvas)
    }

    // MARK: - UI construction

    private func buildUI() {
        let root = NSView()
        window.contentView = root

        // Image area
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.contentView = CenteringClipView()
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.drawsBackground = true
        scrollView.backgroundColor = NSColor(srgbRed: 62 / 255, green: 62 / 255, blue: 68 / 255, alpha: 1)
        scrollView.allowsMagnification = true
        scrollView.minMagnification = 0.05
        scrollView.maxMagnification = 8
        canvas.editor = self
        canvas.frame = NSRect(x: 0, y: 0, width: base.width, height: base.height)
        scrollView.documentView = canvas
        root.addSubview(scrollView)
        NotificationCenter.default.addObserver(self, selector: #selector(magnificationChanged),
                                               name: NSScrollView.didEndLiveMagnifyNotification, object: scrollView)

        // Top toolbar (glass)
        let (toolsBg, toolsContent) = makeGlassContainer(cornerRadius: 0, tint: nil, material: .menu)
        toolsBar = toolsBg
        root.addSubview(toolsBg)
        let toolsRow = buildToolsRow()
        self.toolsRow = toolsRow
        toolsContent.addSubview(toolsRow)

        let (propsBg, propsContent) = makeGlassContainer(cornerRadius: 0, tint: nil, material: .menu)
        propsBar = propsBg
        root.addSubview(propsBg)
        let propsRow = buildPropsRow()
        propsContent.addSubview(propsRow)

        // Status bar
        let (statusBg, statusContent) = makeGlassContainer(cornerRadius: 0, tint: nil, material: .menu)
        root.addSubview(statusBg)
        for l in [sizeLabel, posLabel, infoLabel] {
            l.font = NSFont.systemFont(ofSize: 11)
            l.textColor = .secondaryLabelColor
            l.lineBreakMode = .byTruncatingTail
        }
        posLabel.translatesAutoresizingMaskIntoConstraints = false
        posLabel.widthAnchor.constraint(equalToConstant: 90).isActive = true
        infoLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        let statusRow = NSStackView(views: [sizeLabel, posLabel, infoLabel])
        statusRow.spacing = 16
        statusRow.edgeInsets = NSEdgeInsets(top: 4, left: 12, bottom: 4, right: 12)
        statusRow.translatesAutoresizingMaskIntoConstraints = false
        statusContent.addSubview(statusRow)
        showHint()

        let topAnchor: NSLayoutYAxisAnchor
        if let guide = window.contentLayoutGuide as? NSLayoutGuide {
            topAnchor = guide.topAnchor
        } else {
            topAnchor = root.topAnchor
        }
        NSLayoutConstraint.activate([
            toolsBg.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            toolsBg.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            toolsBg.topAnchor.constraint(equalTo: topAnchor),
            toolsRow.leadingAnchor.constraint(equalTo: toolsContent.leadingAnchor),
            toolsRow.trailingAnchor.constraint(equalTo: toolsContent.trailingAnchor),
            toolsRow.topAnchor.constraint(equalTo: toolsContent.topAnchor),
            toolsRow.bottomAnchor.constraint(equalTo: toolsContent.bottomAnchor),
            // An explicit height: a centred stack view ignores its top/bottom insets, which left the 50 pt buttons
            // touching the title bar. 68 pt centres them with 9 pt above and below.
            toolsRow.heightAnchor.constraint(equalToConstant: 68),

            propsBg.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            propsBg.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            propsBg.topAnchor.constraint(equalTo: toolsBg.bottomAnchor),
            propsRow.leadingAnchor.constraint(equalTo: propsContent.leadingAnchor),
            propsRow.trailingAnchor.constraint(lessThanOrEqualTo: propsContent.trailingAnchor),
            propsRow.topAnchor.constraint(equalTo: propsContent.topAnchor),
            propsRow.bottomAnchor.constraint(equalTo: propsContent.bottomAnchor),
            // Same reason as the tools row: 40 pt leaves about 6 pt around its 28 pt controls.
            propsRow.heightAnchor.constraint(equalToConstant: 40),

            scrollView.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: propsBg.bottomAnchor),
            scrollView.bottomAnchor.constraint(equalTo: statusBg.topAnchor),

            statusBg.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            statusBg.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            statusBg.bottomAnchor.constraint(equalTo: root.bottomAnchor),
            statusRow.leadingAnchor.constraint(equalTo: statusContent.leadingAnchor),
            statusRow.trailingAnchor.constraint(equalTo: statusContent.trailingAnchor),
            statusRow.topAnchor.constraint(equalTo: statusContent.topAnchor),
            statusRow.bottomAnchor.constraint(equalTo: statusContent.bottomAnchor)
        ])
    }

    private func toolButton(_ title: String, symbolName: String, tip: String, action: Selector, tag: Int) -> NSButton {
        let b = EditorToolButton(title: title, image: symbol(symbolName, size: 17))
        b.target = self
        b.action = action
        b.toolTip = tip
        b.tag = tag
        b.translatesAutoresizingMaskIntoConstraints = false
        b.heightAnchor.constraint(equalToConstant: 50).isActive = true
        return b
    }

    private func bigButton(_ title: String, symbolName: String, tint: NSColor, tip: String, action: Selector) -> NSButton {
        let b = NSButton(title: title, target: self, action: action)
        b.image = symbol(symbolName, size: 16, weight: .semibold)
        b.imagePosition = .imageLeading
        b.font = NSFont.systemFont(ofSize: 14, weight: .semibold)
        b.controlSize = .large
        b.toolTip = tip
        styleGlassButton(b, prominent: true, tint: tint)
        setButtonTitleColor(b, .white, font: NSFont.systemFont(ofSize: 14, weight: .semibold))
        b.translatesAutoresizingMaskIntoConstraints = false
        b.widthAnchor.constraint(greaterThanOrEqualToConstant: 116).isActive = true
        if !glassAvailable() {
            b.heightAnchor.constraint(equalToConstant: 40).isActive = true
        }
        return b
    }

    private func buildToolsRow() -> NSView {
        let defs: [(Tool, String, String, String, String)] = [
            (.select, L.t("Chọn"), "cursorarrow", "V", L.t("Chọn, kéo để di chuyển, Delete để xoá. Nháy đúp vào chữ để sửa")),
            (.arrow, L.t("Mũi tên"), "arrow.up.right", "A", L.t("Vẽ mũi tên (giữ Shift để thẳng góc 45°)")),
            (.rectangle, L.t("Khung"), "rectangle", "R", L.t("Vẽ khung chữ nhật (Shift: hình vuông)")),
            (.ellipse, L.t("Elip"), "circle", "E", L.t("Vẽ elip (Shift: hình tròn)")),
            (.line, L.t("Đường"), "line.diagonal", "L", L.t("Vẽ đường thẳng")),
            (.pen, L.t("Bút vẽ"), "scribble", "P", L.t("Vẽ tự do")),
            (.highlight, L.t("Tô sáng"), "highlighter", "H", L.t("Tô sáng một vùng (nên chọn màu vàng)")),
            (.text, L.t("Chữ"), "textformat", "T", L.t("Bấm để gõ chữ. Enter để xong, Shift+Enter xuống dòng")),
            (.blur, L.t("Làm mờ"), "eye.slash", "B", L.t("Làm mờ thông tin nhạy cảm")),
            (.step, L.t("Đánh số"), "1.circle", "N", L.t("Bấm để đặt số bước 1, 2, 3...")),
            (.crop, L.t("Cắt ảnh"), "crop", "C", L.t("Kéo chọn vùng muốn giữ lại"))
        ]
        var toolViews: [NSView] = []
        for (t, title, sym, key, tip) in defs {
            let b = toolButton(title, symbolName: sym, tip: tip + " (" + key + ")", action: #selector(toolPressed(_:)), tag: t.rawValue)
            toolButtons[t] = b
            toolViews.append(b)
        }
        let toolStack = NSStackView(views: toolViews)
        toolStack.spacing = 3

        let keys = HotkeySettings.load()
        func withKey(_ tip: String, _ a: HotkeyAction) -> String {
            if let s = keys[a]?.shortText { return tip + " (" + s + ")" }
            return tip
        }
        let ocr = toolButton(L.t("Trích chữ"), symbolName: "text.viewfinder", tip: L.t("Nhận dạng chữ trong ảnh (OCR) và sao chép"), action: #selector(ocrPressed), tag: -1)
        let lib = toolButton(L.t("Thư viện"), symbolName: "photo.on.rectangle", tip: withKey(L.t("Mở thư viện ảnh và video"), .library), action: #selector(libraryPressed), tag: -1)
        let cap = toolButton(L.t("Chụp mới"), symbolName: "camera.viewfinder", tip: withKey(L.t("Chụp ảnh mới"), .captureRegion), action: #selector(newCapturePressed), tag: -1)
        let actions = NSStackView(views: [ocr, lib, cap])
        actions.spacing = 3

        copyButton = bigButton(L.t("Sao chép"), symbolName: "doc.on.doc", tint: NSColor(srgbRed: 25 / 255, green: 110 / 255, blue: 225 / 255, alpha: 1),
                               tip: L.t("Sao chép ảnh vào clipboard để dán (⌘C)"), action: #selector(copyPressed))
        saveButton = bigButton(L.t("Lưu"), symbolName: "square.and.arrow.down", tint: NSColor(srgbRed: 30 / 255, green: 145 / 255, blue: 75 / 255, alpha: 1),
                               tip: L.t("Lưu ảnh (⌘S)"), action: #selector(savePressed))
        saveAsButton = bigButton(L.t("Lưu thành..."), symbolName: "square.and.arrow.down.on.square", tint: NSColor(srgbRed: 75 / 255, green: 85 / 255, blue: 99 / 255, alpha: 1),
                                 tip: L.t("Lưu thành file khác (⇧⌘S)"), action: #selector(saveAsPressed))
        let big = NSStackView(views: [copyButton, saveButton, saveAsButton])
        big.spacing = 8

        let spacer = NSView()
        spacer.setContentHuggingPriority(NSLayoutConstraint.Priority(1), for: .horizontal)
        spacer.setContentCompressionResistancePriority(NSLayoutConstraint.Priority(1), for: .horizontal)
        let row = NSStackView(views: [wrapInGlassGroup(toolStack), wrapInGlassGroup(actions), spacer, wrapInGlassGroup(big)])
        row.orientation = .horizontal
        row.spacing = 12
        row.alignment = .centerY
        // Glass buttons draw a few points outside their frames: more room above so the row does not touch the title bar.
        row.edgeInsets = NSEdgeInsets(top: 12, left: 10, bottom: 10, right: 10)
        row.translatesAutoresizingMaskIntoConstraints = false
        return row
    }

    private func smallButton(_ title: String?, symbolName: String?, tip: String, action: Selector) -> NSButton {
        let b: NSButton
        if let s = symbolName, let img = symbol(s, size: 13) {
            b = NSButton(image: img, target: self, action: action)
            b.title = ""        // not the placeholder "Button"
            b.imagePosition = .imageOnly
        } else {
            b = NSButton(title: title ?? "", target: self, action: action)
        }
        b.toolTip = tip
        styleGlassButton(b, prominent: false, tint: nil)
        if !glassAvailable() {
            b.translatesAutoresizingMaskIntoConstraints = false
            b.heightAnchor.constraint(equalToConstant: 24).isActive = true
            b.widthAnchor.constraint(greaterThanOrEqualToConstant: 30).isActive = true
        }
        return b
    }

    private func buildPropsRow() -> NSView {
        var views: [NSView] = [NSTextField(labelWithString: L.t("Màu:"))]
        for c in EditorController.palette {
            let s = SwatchButton(frame: NSRect(x: 0, y: 0, width: 24, height: 24))
            s.isBordered = false
            s.swatchColor = c
            s.isChosen = false
            s.toolTip = c.hex
            s.target = self
            s.action = #selector(swatchPressed(_:))
            swatches.append(s)
            views.append(s)
        }
        customSwatch = SwatchButton(frame: NSRect(x: 0, y: 0, width: 24, height: 24))
        customSwatch.isBordered = false
        customSwatch.swatchColor = color
        customSwatch.isChosen = false
        let more = NSButton(title: L.t("Khác..."), target: self, action: #selector(morePressed))
        more.toolTip = L.t("Chọn màu khác")
        more.bezelStyle = .push
        more.controlSize = .small
        customSwatch.target = self
        customSwatch.action = #selector(morePressed)
        customSwatch.toolTip = L.t("Chọn màu khác")
        views.append(customSwatch)
        views.append(more)
        views.append(separator())

        let widthLabel = NSTextField(labelWithString: L.t("Độ dày:"))
        widthPopup = NSPopUpButton(frame: .zero, pullsDown: false)
        widthPopup.addItems(withTitles: EditorController.widths.map { String(Int($0)) })
        widthPopup.selectItem(withTitle: String(Int(strokeWidth)))
        widthPopup.target = self
        widthPopup.action = #selector(widthChanged)
        widthPopup.controlSize = .small
        widthViews = [widthLabel, widthPopup]
        views.append(contentsOf: widthViews)
        // The blur tool shows its own settings in place of the stroke width (hidden views leave the stack).
        blurViews = blurSliderViews(L.t("Kích thước ô:"), L.t("Kích thước ô mờ: càng lớn càng giống ô mosaic to"), cellSlider, cellValue)
            + blurSliderViews(L.t("Độ mờ:"), L.t("Độ mờ: 0 là ô vuông sắc nét, 10 là mờ mịn"), smoothSlider, smoothValue)
        for v in blurViews { v.isHidden = true }
        views.append(contentsOf: blurViews)
        views.append(separator())

        undoButton = smallButton(L.t("Hoàn tác"), symbolName: "arrow.uturn.backward", tip: L.t("Hoàn tác") + " (⌘Z)", action: #selector(undoPressed))
        redoButton = smallButton(L.t("Làm lại"), symbolName: "arrow.uturn.forward", tip: L.t("Làm lại") + " (⇧⌘Z)", action: #selector(redoPressed))
        views.append(undoButton)
        views.append(redoButton)
        views.append(separator())
        views.append(smallButton(nil, symbolName: "folder", tip: L.t("Mở thư mục ảnh đã chụp"), action: #selector(folderPressed)))
        views.append(separator())
        views.append(smallButton("−", symbolName: "minus.magnifyingglass", tip: L.t("Thu nhỏ") + " (⌘-)", action: #selector(zoomOutPressed)))
        zoomLabel.alignment = .center
        zoomLabel.font = NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .regular)
        zoomLabel.translatesAutoresizingMaskIntoConstraints = false
        zoomLabel.widthAnchor.constraint(equalToConstant: 48).isActive = true
        views.append(zoomLabel)
        views.append(smallButton("+", symbolName: "plus.magnifyingglass", tip: L.t("Phóng to") + " (⌘+)", action: #selector(zoomInPressed)))
        views.append(smallButton(L.t("Vừa"), symbolName: nil, tip: L.t("Vừa cửa sổ") + " (⌘0)", action: #selector(fitPressed)))
        views.append(smallButton("1:1", symbolName: nil, tip: L.t("Kích thước thật") + " (⌘1)", action: #selector(actualPressed)))

        let row = NSStackView(views: views)
        row.orientation = .horizontal
        row.spacing = 6
        row.alignment = .centerY
        row.edgeInsets = NSEdgeInsets(top: 6, left: 12, bottom: 6, right: 12)
        row.translatesAutoresizingMaskIntoConstraints = false
        return row
    }

    private func blurSliderViews(_ title: String, _ tip: String, _ slider: NSSlider, _ value: NSTextField) -> [NSView] {
        let label = NSTextField(labelWithString: title)
        label.toolTip = tip
        slider.controlSize = .small
        slider.numberOfTickMarks = Int(slider.maxValue - slider.minValue) + 1
        slider.allowsTickMarkValuesOnly = true
        slider.isContinuous = true
        slider.toolTip = tip
        slider.target = self
        slider.action = #selector(blurSliderChanged)
        slider.translatesAutoresizingMaskIntoConstraints = false
        slider.widthAnchor.constraint(equalToConstant: 110).isActive = true
        value.font = NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .regular)
        value.translatesAutoresizingMaskIntoConstraints = false
        value.widthAnchor.constraint(equalToConstant: 20).isActive = true
        return [label, slider, value]
    }

    private var selectedBlur: BlurShape? { tool == .select ? selected as? BlurShape : nil }

    /// Shows the blur settings instead of the stroke width while the blur tool, or a blurred area, is active.
    private func updateBlurProps() {
        let sel = selectedBlur
        let show = tool == .blur || sel != nil
        cellSlider.integerValue = sel?.cell ?? blurCell
        smoothSlider.integerValue = sel?.smooth ?? blurSmooth
        cellValue.stringValue = String(cellSlider.integerValue)
        smoothValue.stringValue = String(smoothSlider.integerValue)
        if blurViews.first?.isHidden == !show { return }
        for v in blurViews { v.isHidden = !show }
        for v in widthViews { v.isHidden = show }
    }

    @objc private func blurSliderChanged(_ sender: NSSlider) {
        // One undo step per drag: the gesture starts with a mouse down (or a key press).
        if let t = NSApp.currentEvent?.type, t == .leftMouseDown || t == .keyDown || t == .scrollWheel { sliderUndoPending = true }
        let cell = cellSlider.integerValue, smooth = smoothSlider.integerValue
        cellValue.stringValue = String(cell)
        smoothValue.stringValue = String(smooth)
        blurCell = cell
        blurSmooth = smooth
        guard let sel = selectedBlur, sel.cell != cell || sel.smooth != smooth else { return }
        if sliderUndoPending {
            pushUndo()
            sliderUndoPending = false
        }
        sel.cell = cell
        sel.smooth = smooth
        rerender()
    }

    private func separator() -> NSView {
        let b = NSBox()
        b.boxType = .separator
        b.translatesAutoresizingMaskIntoConstraints = false
        b.widthAnchor.constraint(equalToConstant: 1).isActive = true
        b.heightAnchor.constraint(equalToConstant: 18).isActive = true
        return b
    }

    private func sizeWindowToImage() {
        let screen = NSScreen.screens.first { NSMouseInRect(NSEvent.mouseLocation, $0.frame, false) } ?? NSScreen.main
        let vf = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let imgW = CGFloat(base.width) / imageScale, imgH = CGFloat(base.height) / imageScale
        let minW = min(1180, vf.width * 0.95)
        let w = min(vf.width * 0.9, max(minW, imgW + 60))
        let h = min(vf.height * 0.9, max(480, imgH + 200))
        window.setFrame(NSRect(x: vf.minX + (vf.width - w) / 2, y: vf.minY + (vf.height - h) / 2, width: w, height: h), display: false)
    }

    // MARK: - Labels, buttons

    private func showHint() {
        infoLabel.stringValue = L.t("Kéo để vẽ • Shift: giữ thẳng/vuông • ⌘+cuộn hoặc chụm 2 ngón: phóng to • Ảnh đã tự lưu và sao chép vào clipboard")
    }

    private func updateTitle() {
        let name = fileURL?.lastPathComponent ?? L.t("Ảnh chưa lưu")
        window.title = (dirty ? "● " : "") + name + " — MiniSnap"
        window.isDocumentEdited = dirty
    }

    private func updateToolButtons() {
        for (t, b) in toolButtons { (b as? EditorToolButton)?.isOn = t == tool }
        updateBlurProps()
        window.invalidateCursorRects(for: canvas)
    }

    private func updateSwatches() {
        var matched = false
        for s in swatches {
            let on = s.swatchColor == color
            matched = matched || on
            s.isChosen = on
        }
        customSwatch.swatchColor = color
        customSwatch.isChosen = !matched
    }

    private func updateUndoButtons() {
        undoButton.isEnabled = !undoStack.isEmpty
        redoButton.isEnabled = !redoStack.isEmpty
    }

    private func updateZoomLabel() {
        zoomLabel.stringValue = String(Int((scrollView.magnification * imageScale * 100).rounded())) + "%"
    }

    private func flash(_ b: NSButton, _ text: String, original: String) {
        setBigTitle(b, text)
        let key = ObjectIdentifier(b)
        flashTasks[key]?.cancel()
        flashTasks[key] = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            if Task.isCancelled { return }
            self?.setBigTitle(b, original)
        }
    }

    private func setBigTitle(_ b: NSButton, _ text: String) {
        b.title = text
        setButtonTitleColor(b, .white, font: NSFont.systemFont(ofSize: 14, weight: .semibold))
    }

    // MARK: - Rendering, zoom

    private func rerender() {
        cache = Renderer.render(base: base, shapes: shapes)
        sizeLabel.stringValue = String(base.width) + " × " + String(base.height) + " px"
        canvas.needsDisplay = true
        updateBlurProps()
    }

    private func flattened() -> CGImage? {
        commitText()
        return Renderer.render(base: base, shapes: shapes)
    }

    private func setZoom(_ z: CGFloat, around p: CGPoint?) {
        commitText()
        let clamped = max(scrollView.minMagnification, min(scrollView.maxMagnification, z))
        if let p = p {
            scrollView.setMagnification(clamped, centeredAt: p)
        } else {
            let visible = scrollView.contentView.bounds
            scrollView.setMagnification(clamped, centeredAt: CGPoint(x: visible.midX, y: visible.midY))
        }
        updateZoomLabel()
        canvas.needsDisplay = true
    }

    func zoom(by factor: CGFloat, around p: CGPoint) {
        setZoom(scrollView.magnification * factor, around: p)
    }

    private func fitZoom() {
        let avail = scrollView.contentSize
        let margin: CGFloat = 24
        let z = min(1 / imageScale,
                    min((avail.width - 2 * margin) / CGFloat(base.width), (avail.height - 2 * margin) / CGFloat(base.height)))
        scrollView.magnification = max(scrollView.minMagnification, z)
        updateZoomLabel()
        canvas.needsDisplay = true
    }

    @objc private func magnificationChanged() {
        updateZoomLabel()
        canvas.needsDisplay = true
    }

    // MARK: - Mouse (called by CanvasView, points are image pixels)

    private var hitTolerance: CGFloat { 5 / max(0.01, scrollView.magnification) }

    func canvasMouseDown(_ p: CGPoint, clickCount: Int, shift: Bool) {
        if textView != nil { commitText(); return }
        mouseIsDown = true
        downPt = p
        lastPt = p
        switch tool {
        case .select:
            selected = hitTest(p)
            updateBlurProps()
            movedSelected = false
            if clickCount == 2, let ts = selected as? TextShape {
                mouseIsDown = false
                beginTextEdit(ts)
            }
            canvas.needsDisplay = true
        case .text:
            mouseIsDown = false
            if let hit = hitTest(p) as? TextShape {
                beginTextEdit(hit)
            } else {
                beginTextEdit(at: p, text: "", color: color, width: strokeWidth)
            }
        case .step:
            mouseIsDown = false
            pushUndo()
            let s = StepShape(color: color, width: strokeWidth)
            s.center = p
            s.number = nextStep()
            shapes.append(s)
            rerender()
        case .crop:
            cropping = true
            cropRect = CGRect(origin: p, size: .zero)
        case .pen:
            let pen = PenShape(color: color, width: strokeWidth)
            pen.points.append(p)
            current = pen
            canvas.needsDisplay = true
        default:
            let s = createTwoPoint(tool)
            s.a = p
            s.b = p
            current = s
        }
    }

    func canvasMouseDragged(_ p: CGPoint, shift: Bool) {
        posLabel.stringValue = String(Int(floor(p.x))) + ", " + String(Int(floor(p.y)))
        guard mouseIsDown else { return }
        switch tool {
        case .select:
            guard let sel = selected else { break }
            if !movedSelected {
                if Geo.dist(p, downPt) * scrollView.magnification < 3 { break }
                pushUndo()
                movedSelected = true
            }
            sel.offset(dx: p.x - lastPt.x, dy: p.y - lastPt.y)
            lastPt = p
            rerender()
        case .crop:
            let end = shift ? EditorController.constrain(downPt, p, tool) : p
            let full = CGRect(x: 0, y: 0, width: base.width, height: base.height)
            cropRect = Geo.norm(downPt, end).intersection(full)
            if cropRect.isNull { cropRect = .zero }
            infoLabel.stringValue = L.t("Vùng cắt: ") + String(Int(cropRect.width)) + " × " + String(Int(cropRect.height)) + L.t(" px — thả chuột để cắt, Esc để huỷ")
            canvas.needsDisplay = true
        case .pen:
            (current as? PenShape)?.points.append(p)
            canvas.needsDisplay = true
        default:
            if let two = current as? TwoPointShape {
                two.b = shift ? EditorController.constrain(two.a, p, tool) : p
                canvas.needsDisplay = true
            }
        }
    }

    func canvasMouseUp(_ p: CGPoint) {
        guard mouseIsDown else { return }
        mouseIsDown = false
        if tool == .crop {
            cropping = false
            showHint()
            let r = cropRect.integral
            if r.width >= 4 && r.height >= 4 { applyCrop(r) }
            canvas.needsDisplay = true
            return
        }
        guard let cur = current else { return }
        var tooSmall = false
        if let two = cur as? TwoPointShape {
            tooSmall = Geo.dist(two.a, two.b) * scrollView.magnification < 4
        }
        if !tooSmall {
            pushUndo()
            shapes.append(cur)
        }
        current = nil
        rerender()
    }

    func canvasMouseMoved(_ p: CGPoint) {
        posLabel.stringValue = String(Int(floor(p.x))) + ", " + String(Int(floor(p.y)))
        updateCursor(at: p)
    }

    func canvasMouseExited() {
        posLabel.stringValue = ""
    }

    func updateCursor(at p: CGPoint) {
        switch tool {
        case .select:
            (hitTest(p) != nil ? NSCursor.openHand : NSCursor.arrow).set()
        case .text:
            NSCursor.iBeam.set()
        default:
            NSCursor.crosshair.set()
        }
    }

    private func createTwoPoint(_ t: Tool) -> TwoPointShape {
        switch t {
        case .rectangle: return RectShape(color: color, width: strokeWidth)
        case .ellipse: return EllipseShape(color: color, width: strokeWidth)
        case .line: return LineShape(color: color, width: strokeWidth)
        case .highlight: return HighlightShape(color: color, width: strokeWidth)
        case .blur:
            let s = BlurShape(color: color, width: strokeWidth)
            s.cell = blurCell
            s.smooth = blurSmooth
            return s
        default: return ArrowShape(color: color, width: strokeWidth)
        }
    }

    static func constrain(_ a: CGPoint, _ b: CGPoint, _ t: Tool) -> CGPoint {
        let dx = b.x - a.x, dy = b.y - a.y
        if t == .line || t == .arrow {
            let step = Double.pi / 4
            let ang = (atan2(Double(dy), Double(dx)) / step).rounded() * step
            let len = Double((dx * dx + dy * dy).squareRoot())
            return CGPoint(x: a.x + CGFloat(cos(ang) * len), y: a.y + CGFloat(sin(ang) * len))
        }
        let m = max(abs(dx), abs(dy))
        return CGPoint(x: a.x + (dx < 0 ? -m : m), y: a.y + (dy < 0 ? -m : m))
    }

    private func hitTest(_ p: CGPoint) -> Shape? {
        for s in shapes.reversed() where s.hitTest(p, tolerance: hitTolerance) { return s }
        return nil
    }

    private func nextStep() -> Int {
        var m = 0
        for s in shapes { if let st = s as? StepShape { m = max(m, st.number) } }
        return m + 1
    }

    private func applyCrop(_ r: CGRect) {
        guard let nb = ImageUtil.crop(base, to: r) else { return }
        pushUndo()
        base = nb
        for s in shapes { s.offset(dx: -r.minX, dy: -r.minY) }
        selected = nil
        canvas.frame = NSRect(x: 0, y: 0, width: base.width, height: base.height)
        rerender()
        fitZoom()
    }

    // MARK: - Text editing

    private func beginTextEdit(_ ts: TextShape) {
        pushUndo()
        editingIndex = shapes.firstIndex { $0 === ts } ?? shapes.count
        shapes.removeAll { $0 === ts }
        selected = nil
        rerender()
        beginTextEdit(at: ts.pos, text: ts.text, color: ts.color, width: ts.width)
        editingText = ts
    }

    private func beginTextEdit(at pos: CGPoint, text: String, color c: RGBAColor, width w: CGFloat) {
        editingText = nil
        textPos = pos
        textColor = c
        textWidth = w
        let tv = AnnotationTextView(frame: NSRect(x: pos.x - 4, y: pos.y - 4, width: 120, height: 40))
        tv.isRichText = false
        tv.allowsUndo = true
        tv.isAutomaticQuoteSubstitutionEnabled = false
        tv.isAutomaticDashSubstitutionEnabled = false
        tv.isAutomaticSpellingCorrectionEnabled = false
        tv.textContainerInset = NSSize(width: 4, height: 4)
        tv.textContainer?.lineFragmentPadding = 0
        tv.textContainer?.widthTracksTextView = false
        tv.textContainer?.size = NSSize(width: 100_000, height: 100_000)
        tv.isHorizontallyResizable = true
        tv.isVerticallyResizable = true
        tv.onCommit = { [weak self] in self?.commitText() }
        tv.onCancel = { [weak self] in self?.cancelText() }
        applyTextStyle(tv)
        tv.string = text
        tv.delegate = self
        canvas.addSubview(tv)
        textView = tv
        resizeTextView()
        window.makeFirstResponder(tv)
        tv.setSelectedRange(NSRange(location: (text as NSString).length, length: 0))
        infoLabel.stringValue = L.t("Gõ chữ • Enter: xong • Shift+Enter: xuống dòng • Esc: huỷ")
    }

    private func applyTextStyle(_ tv: NSTextView) {
        let font = TextShape.font(size: TextShape.fontSize(for: textWidth))
        tv.font = font
        tv.textColor = textColor.ns()
        tv.insertionPointColor = textColor.ns()
        tv.typingAttributes = [.font: font, .foregroundColor: textColor.ns()]
        tv.backgroundColor = textColor.isLight ? NSColor(srgbRed: 50 / 255, green: 50 / 255, blue: 55 / 255, alpha: 0.92) : NSColor(white: 1, alpha: 0.92)
        tv.drawsBackground = true
        let full = NSRange(location: 0, length: (tv.string as NSString).length)
        tv.textStorage?.setAttributes([.font: font, .foregroundColor: textColor.ns()], range: full)
    }

    fileprivate func resizeTextView() {
        guard let tv = textView else { return }
        let probe = TextShape(color: textColor, width: textWidth)
        probe.text = tv.string.isEmpty ? "Wg" : tv.string + " "
        let s = probe.textSize
        let minW = 80 / max(0.05, scrollView.magnification)
        tv.frame = NSRect(x: textPos.x - 4, y: textPos.y - 4, width: max(s.width + 14, minW), height: s.height + 10)
    }

    private func closeTextView() {
        guard let tv = textView else { return }
        textView = nil
        tv.removeFromSuperview()
        showHint()
    }

    private func commitText() {
        guard let tv = textView else { return }
        var text = tv.string
        while let last = text.last, last.isWhitespace { text.removeLast() }
        closeTextView()
        if !text.isEmpty {
            if editingText == nil { pushUndo() }
            let ts = TextShape(color: textColor, width: textWidth)
            ts.pos = textPos
            ts.text = text
            if editingText != nil {
                shapes.insert(ts, at: min(editingIndex, shapes.count))
            } else {
                shapes.append(ts)
            }
        }
        editingText = nil
        rerender()
        window.makeFirstResponder(canvas)
    }

    private func cancelText() {
        guard textView != nil else { return }
        closeTextView()
        if let et = editingText {
            shapes.insert(et, at: min(editingIndex, shapes.count))
            if !undoStack.isEmpty { undoStack.removeLast() }
            updateUndoButtons()
        }
        editingText = nil
        rerender()
        window.makeFirstResponder(canvas)
    }

    // MARK: - Tools, colour, width

    private func setTool(_ t: Tool) {
        commitText()
        tool = t
        current = nil
        cropping = false
        if t != .select { selected = nil }
        updateToolButtons()
        showHint()
        canvas.needsDisplay = true
        window.makeFirstResponder(canvas)
    }

    private func setColor(_ c: RGBAColor) {
        color = c
        updateSwatches()
        if let tv = textView {
            textColor = c
            applyTextStyle(tv)
            window.makeFirstResponder(tv)
            return
        }
        if let sel = selected, tool == .select {
            pushUndo()
            sel.color = c
            rerender()
        }
    }

    private func setWidth(_ w: CGFloat) {
        strokeWidth = w
        if let tv = textView {
            textWidth = w
            applyTextStyle(tv)
            resizeTextView()
            window.makeFirstResponder(tv)
            return
        }
        if let sel = selected, tool == .select {
            pushUndo()
            sel.width = w
            rerender()
        }
    }

    // MARK: - Undo / redo

    private func snapshot() -> State { State(base: base, shapes: shapes.map { $0.clone() }) }

    private func pushUndo() {
        undoStack.append(snapshot())
        redoStack.removeAll()
        dirty = true
        updateUndoButtons()
        updateTitle()
    }

    private func undo() {
        commitText()
        guard let s = undoStack.popLast() else { return }
        redoStack.append(snapshot())
        restore(s)
    }

    private func redo() {
        commitText()
        guard let s = redoStack.popLast() else { return }
        undoStack.append(snapshot())
        restore(s)
    }

    private func restore(_ s: State) {
        let sizeChanged = s.base.width != base.width || s.base.height != base.height
        base = s.base
        shapes = s.shapes
        selected = nil
        dirty = true
        if sizeChanged { canvas.frame = NSRect(x: 0, y: 0, width: base.width, height: base.height) }
        rerender()
        if sizeChanged { fitZoom() }
        updateUndoButtons()
        updateTitle()
    }

    private func deleteSelected() {
        guard let sel = selected else { return }
        pushUndo()
        shapes.removeAll { $0 === sel }
        selected = nil
        rerender()
    }

    private func nudgeSelected(_ dx: CGFloat, _ dy: CGFloat) {
        guard let sel = selected else { return }
        pushUndo()
        sel.offset(dx: dx, dy: dy)
        rerender()
    }

    // MARK: - Clipboard and files

    private func copyToClipboard() {
        guard let flat = flattened() else { return }
        if ImageUtil.copyToPasteboard(flat) {
            infoLabel.stringValue = L.t("Đã sao chép ảnh vào clipboard — dán (⌘V) vào Zalo, Word, email...")
            flash(copyButton, L.t("✓ Đã chép"), original: L.t("Sao chép"))
        }
    }

    @discardableResult
    private func save(as saveAs: Bool) -> Bool {
        commitText()
        var url = fileURL
        if saveAs || url == nil {
            guard let chosen = runSavePanel() else { return false }
            url = chosen
        }
        guard let target = url, let flat = Renderer.render(base: base, shapes: shapes) else { return false }
        do {
            try ImageUtil.write(flat, to: target)
        } catch {
            Alerts.show("MiniSnap", L.t("Không lưu được ảnh:\n") + error.localizedDescription)
            return false
        }
        fileURL = target
        dirty = false
        updateTitle()
        infoLabel.stringValue = L.t("Đã lưu: ") + target.path
        if saveAs {
            flash(saveAsButton, L.t("✓ Đã lưu"), original: L.t("Lưu thành..."))
        } else {
            flash(saveButton, L.t("✓ Đã lưu"), original: L.t("Lưu"))
        }
        return true
    }

    private func runSavePanel() -> URL? {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [UTType.png, UTType.jpeg]
        panel.canCreateDirectories = true
        panel.isExtensionHidden = false
        panel.directoryURL = fileURL?.deletingLastPathComponent() ?? LibraryPaths.imagesFolder
        panel.nameFieldStringValue = fileURL?.lastPathComponent ?? "MiniSnap.png"

        let popup = NSPopUpButton(frame: .zero, pullsDown: false)
        popup.addItems(withTitles: ["PNG", "JPEG"])
        let ext = fileURL?.pathExtension.lowercased() ?? "png"
        popup.selectItem(at: (ext == "jpg" || ext == "jpeg") ? 1 : 0)
        popup.target = self
        popup.action = #selector(formatChanged(_:))
        let label = NSTextField(labelWithString: L.t("Định dạng:"))
        let acc = NSStackView(views: [label, popup])
        acc.edgeInsets = NSEdgeInsets(top: 8, left: 12, bottom: 8, right: 12)
        panel.accessoryView = acc
        savePanel = panel
        let result = panel.runModal()
        savePanel = nil
        return result == .OK ? panel.url : nil
    }

    @objc private func formatChanged(_ sender: NSPopUpButton) {
        guard let panel = savePanel else { return }
        let ext = sender.indexOfSelectedItem == 1 ? "jpg" : "png"
        let name = (panel.nameFieldStringValue as NSString).deletingPathExtension
        panel.nameFieldStringValue = name + "." + ext
    }

    // MARK: - Keyboard

    /// ⌘ shortcuts, seen before the main menu.
    private func handleKeyEquivalent(_ e: NSEvent) -> Bool {
        guard e.type == .keyDown else { return false }
        let flags = e.modifierFlags.intersection(.deviceIndependentFlagsMask)
        guard flags.contains(.command) else { return false }
        let editingText = window.firstResponder is NSText
        let chars = (e.charactersIgnoringModifiers ?? "").lowercased()
        let shift = flags.contains(.shift)
        switch chars {
        case "w": window.performClose(nil); return true
        case "s": save(as: shift); return true
        case "n": onNewCapture?(); return true
        default: break
        }
        if editingText { return false }
        switch chars {
        case "c": copyToClipboard(); return true
        case "z": if shift { redo() } else { undo() }; return true
        case "y": redo(); return true
        case "=", "+": setZoom(scrollView.magnification * 1.25, around: nil); return true
        case "-": setZoom(scrollView.magnification / 1.25, around: nil); return true
        case "0": commitText(); fitZoom(); return true
        case "1": setZoom(1 / imageScale, around: nil); return true
        default: return false
        }
    }

    /// Plain keys while the canvas has focus.
    func canvasKeyDown(_ e: NSEvent) -> Bool {
        let flags = e.modifierFlags.intersection([.command, .option, .control])
        if !flags.isEmpty { return false }
        let code = Int(e.keyCode)
        switch code {
        case kVK_Delete, kVK_ForwardDelete: deleteSelected(); return true
        case kVK_LeftArrow: nudgeSelected(-1, 0); return true
        case kVK_RightArrow: nudgeSelected(1, 0); return true
        case kVK_UpArrow: nudgeSelected(0, -1); return true
        case kVK_DownArrow: nudgeSelected(0, 1); return true
        case kVK_Escape:
            if mouseIsDown { mouseIsDown = false; current = nil; cropping = false; showHint() }
            selected = nil
            canvas.needsDisplay = true
            return true
        default: break
        }
        let map: [String: Tool] = ["v": .select, "a": .arrow, "r": .rectangle, "e": .ellipse, "l": .line, "p": .pen,
                                   "h": .highlight, "t": .text, "b": .blur, "n": .step, "c": .crop]
        if let ch = e.charactersIgnoringModifiers?.lowercased(), let t = map[ch] {
            setTool(t)
            return true
        }
        return false
    }

    // MARK: - Actions

    @objc private func toolPressed(_ sender: NSButton) {
        if let t = Tool(rawValue: sender.tag) { setTool(t) }
    }

    @objc private func swatchPressed(_ sender: SwatchButton) { setColor(sender.swatchColor) }

    @objc private func morePressed() {
        let panel = NSColorPanel.shared
        panel.showsAlpha = false
        panel.color = color.ns()
        panel.setTarget(self)
        panel.setAction(#selector(colorPanelChanged(_:)))
        panel.orderFront(nil)
    }

    @objc private func colorPanelChanged(_ sender: NSColorPanel) {
        setColor(RGBAColor(ns: sender.color))
    }

    @objc private func widthChanged() {
        let i = widthPopup.indexOfSelectedItem
        if i >= 0 && i < EditorController.widths.count { setWidth(EditorController.widths[i]) }
        if textView == nil { window.makeFirstResponder(canvas) }
    }

    @objc private func undoPressed() { undo() }
    @objc private func redoPressed() { redo() }
    @objc private func folderPressed() { NSWorkspace.shared.open(LibraryPaths.imagesFolder) }
    @objc private func zoomInPressed() { setZoom(scrollView.magnification * 1.25, around: nil) }
    @objc private func zoomOutPressed() { setZoom(scrollView.magnification / 1.25, around: nil) }
    @objc private func fitPressed() { commitText(); fitZoom() }
    @objc private func actualPressed() { setZoom(1 / imageScale, around: nil) }
    @objc private func copyPressed() { copyToClipboard() }
    @objc private func savePressed() { save(as: false) }
    @objc private func saveAsPressed() { save(as: true) }
    @objc private func newCapturePressed() { onNewCapture?() }
    @objc private func libraryPressed() { onLibrary?() }

    @objc private func ocrPressed() {
        if let flat = flattened() { onOcr?(flat) }
    }

    // MARK: - Window delegate

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        commitText()
        if !dirty || skipSavePrompt { return true }
        let alert = NSAlert()
        alert.messageText = L.t("Lưu các thay đổi vào ảnh?")
        alert.informativeText = L.t("Nếu không lưu, các chỉnh sửa sẽ bị mất.")
        alert.addButton(withTitle: L.t("Lưu"))
        alert.addButton(withTitle: L.t("Không lưu"))
        alert.addButton(withTitle: L.t("Huỷ"))
        let r = alert.runModal()
        if r == .alertFirstButtonReturn { return save(as: false) }
        if r == .alertSecondButtonReturn { return true }
        return false
    }

    func windowWillClose(_ notification: Notification) {
        if NSColorPanel.sharedColorPanelExists {
            let panel = NSColorPanel.shared
            panel.setTarget(nil)
            panel.setAction(nil)
        }
        for t in flashTasks.values { t.cancel() }
        NotificationCenter.default.removeObserver(self)
        onClose?()
    }
}

extension EditorController: NSTextViewDelegate {
    func textDidChange(_ notification: Notification) {
        resizeTextView()
    }
}

/// An editor toolbar button drawn by hand: symbol above its name, both centred in a rounded tile (accent
/// coloured while selected). The glass bezel put an image-above button's symbol against its top edge.
@MainActor
final class EditorToolButton: NSButton {
    private let label: String
    private let glyph: NSImage?
    private var hovering = false

    /// The current tool (accent tile, white content).
    var isOn = false { didSet { needsDisplay = true } }

    init(title: String, image: NSImage?) {
        label = title
        glyph = image
        super.init(frame: NSRect(x: 0, y: 0, width: 56, height: 50))
        self.title = title
        isBordered = false
        setButtonType(.momentaryChange)
        setAccessibilityLabel(title)
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    override var isFlipped: Bool { false }      // y up, as the layout below assumes

    private static let font = NSFont.systemFont(ofSize: 10.5)

    override var intrinsicContentSize: NSSize {
        let w = (label as NSString).size(withAttributes: [.font: EditorToolButton.font]).width
        return NSSize(width: max(50, ceil(w) + 18), height: 50)
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        for t in trackingAreas { removeTrackingArea(t) }
        addTrackingArea(NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect],
                                       owner: self, userInfo: nil))
    }

    override func mouseEntered(with event: NSEvent) { hovering = true; needsDisplay = true }
    override func mouseExited(with event: NSEvent) { hovering = false; needsDisplay = true }

    override func draw(_ dirtyRect: NSRect) {
        let r = bounds.insetBy(dx: 0.5, dy: 0.5)
        let fill: NSColor
        if isOn {
            fill = isHighlighted ? NSColor.controlAccentColor.blended(withFraction: 0.2, of: .black) ?? .controlAccentColor
                : .controlAccentColor
        } else {
            fill = NSColor.labelColor.withAlphaComponent(isHighlighted ? 0.22 : hovering ? 0.15 : 0.08)
        }
        fill.setFill()
        NSBezierPath(roundedRect: r, xRadius: 10, yRadius: 10).fill()

        let ink = isOn ? NSColor.white : (isEnabled ? NSColor.labelColor : NSColor.tertiaryLabelColor)
        let attrs: [NSAttributedString.Key: Any] = [.font: EditorToolButton.font, .foregroundColor: ink]
        let textSize = (label as NSString).size(withAttributes: attrs)
        let iconSize = glyph?.size ?? .zero
        // A fixed slot for the symbol (symbols differ in height), so every name sits on the same line.
        let slot: CGFloat = 20, gap: CGFloat = 4
        let bottom = (bounds.height - (slot + gap + textSize.height)) / 2
        (label as NSString).draw(at: NSPoint(x: (bounds.width - textSize.width) / 2, y: bottom), withAttributes: attrs)
        if let g = glyph {
            let tinted = NSImage(size: g.size, flipped: false) { rect in
                g.draw(in: rect)
                ink.set()
                rect.fill(using: .sourceAtop)
                return true
            }
            let slotBottom = bottom + textSize.height + gap
            tinted.draw(in: NSRect(x: (bounds.width - iconSize.width) / 2, y: slotBottom + (slot - iconSize.height) / 2,
                                   width: iconSize.width, height: iconSize.height))
        }
    }
}
