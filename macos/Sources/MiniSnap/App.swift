import AppKit
import UserNotifications
import UniformTypeIdentifiers

@main
enum MiniSnapMain {
    static func main() {
        // `MiniSnap --blur-grid out.png`: renders every blur cell size / softness pair to a PNG and exits (used by CI).
        let args = CommandLine.arguments
        if let i = args.firstIndex(of: "--blur-grid"), i + 1 < args.count {
            let ok = MainActor.assumeIsolated { BlurGrid.write(to: URL(fileURLWithPath: args[i + 1])) }
            exit(ok ? 0 : 1)
        }
        // `MiniSnap --editor-layout`: prints where the editor's toolbar and buttons are laid out (CI check).
        if args.contains("--editor-layout") {
            MainActor.assumeIsolated {
                _ = NSApplication.shared
                NSApp.setActivationPolicy(.accessory)
                guard let ctx = ImageUtil.makeContext(width: 900, height: 560) else { exit(1) }
                ctx.setFillColor(CGColor(gray: 0.9, alpha: 1))
                ctx.fill(CGRect(x: 0, y: 0, width: 900, height: 560))
                guard let image = ctx.makeImage() else { exit(1) }
                let ed = EditorController(image: image, url: nil, imageScale: 1)
                ed.skipSavePrompt = true
                ed.show()
                print(ed.layoutReport())
            }
            exit(0)
        }
        // `MiniSnap --render-windows DIR`: launcher-vi/en.png and hotkeys-vi/en.png in DIR, for CI.
        if let i = args.firstIndex(of: "--render-windows"), i + 1 < args.count {
            let dir = URL(fileURLWithPath: args[i + 1], isDirectory: true)
            let ok = MainActor.assumeIsolated { () -> Bool in
                _ = NSApplication.shared
                NSApp.setActivationPolicy(.accessory)
                var all = true
                for (english, lang) in [(false, "vi"), (true, "en")] {
                    L.set(english: english)
                    let keys = HotkeySettings.load()
                    let launcher = LauncherWindow(keys: keys, recording: false, settingsMenu: { NSMenu() }) { _ in }
                    all = launcher.writeSnapshot(to: dir.appendingPathComponent("launcher-" + lang + ".png")) && all
                    let hotkeys = HotkeySettingsWindow(current: keys) { _ in [] }
                    all = hotkeys.writeSnapshot(to: dir.appendingPathComponent("hotkeys-" + lang + ".png")) && all
                    // The editor's toolbar (its buttons are drawn by hand, so they show up offscreen too).
                    if let ctx = ImageUtil.makeContext(width: 900, height: 560) {
                        ctx.setFillColor(CGColor(gray: 0.92, alpha: 1))
                        ctx.fill(CGRect(x: 0, y: 0, width: 900, height: 560))
                        if let image = ctx.makeImage() {
                            let ed = EditorController(image: image, url: nil, imageScale: 1)
                            ed.skipSavePrompt = true
                            all = ed.writeToolbarSnapshot(to: dir.appendingPathComponent("editor-" + lang + ".png")) && all
                        }
                    }
                }
                return all
            }
            exit(ok ? 0 : 1)
        }
        MainActor.assumeIsolated {
            let app = NSApplication.shared
            let delegate = AppDelegate()
            app.delegate = delegate
            app.setActivationPolicy(.accessory)
            // NSApplication.delegate is weak: keep ours alive for as long as the app runs.
            withExtendedLifetime(delegate) { app.run() }
        }
    }
}

/// User notifications (banners). Clicking one calls `onOpen` with the info string it carries.
final class Notifier: NSObject, UNUserNotificationCenterDelegate {
    var onOpen: ((String) -> Void)?

    /// UNUserNotificationCenter only works inside a real .app bundle.
    private var available: Bool {
        Bundle.main.bundleIdentifier != nil && Bundle.main.bundleURL.pathExtension == "app"
    }

    func setUp() {
        guard available else { return }
        let c = UNUserNotificationCenter.current()
        c.delegate = self
        c.requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    func post(_ title: String, _ body: String, info: String? = nil) {
        guard available else {
            NSLog("MiniSnap: %@ — %@", title, body)
            return
        }
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        if let i = info { content.userInfo = ["info": i] }
        let req = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(req) { _ in }
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .list])
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse,
                                withCompletionHandler completionHandler: @escaping () -> Void) {
        let info = response.notification.request.content.userInfo["info"] as? String
        completionHandler()
        guard let i = info else { return }
        DispatchQueue.main.async { [weak self] in
            self?.onOpen?(i)
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private enum Mode { case image, fullScreen, scroll, video, ocr }

    private var statusItem: NSStatusItem?
    private let statusMenu = NSMenu()
    private let hotkeys = HotkeyManager()
    private var keys = HotkeySettings.load()
    private var busy = false
    private var overlay: CaptureOverlayController?
    private var recorder: RecordingController?
    private var scrollSession: ScrollCaptureSession?
    private var editors: [EditorController] = []
    private var ocrWindows: [OcrWindow] = []
    private var library: LibraryWindow?
    private var hotkeyWindow: HotkeySettingsWindow?
    private var aboutWindow: AboutWindow?
    private var launcher: LauncherWindow?
    private let notifier = Notifier()
    private var quitAfterRecording = false

    // MARK: - Launch

    func applicationDidFinishLaunching(_ notification: Notification) {
        buildMainMenu()

        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = item.button {
            if let img = NSImage(systemSymbolName: "camera.viewfinder", accessibilityDescription: "MiniSnap") {
                img.isTemplate = true
                button.image = img
            } else {
                button.title = "MiniSnap"
            }
            button.toolTip = trayTooltip()
        }
        statusMenu.delegate = self
        statusMenu.autoenablesItems = false
        item.menu = statusMenu
        statusItem = item
        rebuildStatusMenu()

        notifier.onOpen = { [weak self] info in
            MainActor.assumeIsolated { self?.handleNotificationInfo(info) }
        }
        notifier.setUp()

        hotkeys.onPress = { [weak self] action in
            MainActor.assumeIsolated { self?.run(action) }
        }
        let failed = hotkeys.register(keys)
        var msg = keyHint() + L.t(". Bấm vào biểu tượng trên thanh menu để xem thêm hoặc đổi phím tắt.")
        if !failed.isEmpty {
            msg += L.t("\nKhông đăng ký được: ") + failed.compactMap { keys[$0]?.shortText }.joined(separator: ", ")
                + L.t(" (đang bị ứng dụng khác dùng) — vào Cài đặt phím tắt để đổi.")
        }
        notifier.post(L.t("MiniSnap đã sẵn sàng"), msg, info: failed.isEmpty ? nil : "hotkeys")

        Updater.shared.onSilentUpdateFound = { [weak self] version in
            self?.notifier.post(L.t("Có bản MiniSnap mới"), "MiniSnap " + version + " — " + L.t("Chọn \"Kiểm tra cập nhật...\" trong menu để tải về."), info: "update")
        }
        Updater.shared.checkDailyIfNeeded()

        // A menu-bar app shows nothing by itself, so the launcher says it is running. Not when it was
        // started with the Mac (start at login, shortly after boot): it then stays in the menu bar.
        let atLogin = LoginItem.enabled && ProcessInfo.processInfo.systemUptime < 180
        if Prefs.showLauncherAtStart && !atLogin { showLauncher() }
    }

    /// Opening MiniSnap again (Finder, Dock, Spotlight) while it runs brings the launcher back.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showLauncher()
        return true
    }

    @objc private func showLauncher() {
        if let l = launcher {
            l.show()
            return
        }
        let l = LauncherWindow(keys: keys, recording: recorder?.isActive == true,
                               settingsMenu: { [weak self] in self?.makeSettingsMenu() ?? NSMenu() }) { [weak self] action in
            guard let self = self else { return }
            if let a = action { self.run(a) } else { self.menuOpenImage() }
        }
        l.onClose = { [weak self] in self?.launcher = nil }
        launcher = l
        l.show()
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        if let r = recorder, r.isActive {
            quitAfterRecording = true
            r.stopRecording()
            return .terminateCancel
        }
        for ed in editors {
            if !ed.windowShouldClose(ed.window) { return .terminateCancel }
            ed.skipSavePrompt = true
        }
        return .terminateNow
    }

    func applicationWillTerminate(_ notification: Notification) {
        hotkeys.unregisterAll()
    }

    private func handleNotificationInfo(_ info: String) {
        if info == "hotkeys" {
            showHotkeySettings()
        } else if info == "update" {
            Updater.shared.check(interactive: true)
        } else if info.hasPrefix("open:") {
            let path = String(info.dropFirst(5))
            NSWorkspace.shared.open(URL(fileURLWithPath: path))
        }
    }

    // MARK: - Menus

    /// A hidden main menu so ⌘C/⌘V/⌘A/⌘Z/⌘W/⌘Q work in text fields and windows of this menu-bar app.
    private func buildMainMenu() {
        let main = NSMenu()

        let appItem = NSMenuItem()
        let appMenu = NSMenu(title: "MiniSnap")
        let about = NSMenuItem(title: L.t("Giới thiệu MiniSnap"), action: #selector(showAbout), keyEquivalent: "")
        about.target = self
        appMenu.addItem(about)
        appMenu.addItem(NSMenuItem.separator())
        let shortcuts = NSMenuItem(title: L.t("Cài đặt phím tắt..."), action: #selector(menuHotkeys), keyEquivalent: ",")
        shortcuts.target = self
        appMenu.addItem(shortcuts)
        appMenu.addItem(NSMenuItem.separator())
        appMenu.addItem(NSMenuItem(title: "Hide MiniSnap", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h"))
        appMenu.addItem(NSMenuItem(title: L.t("Thoát MiniSnap"), action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        appItem.submenu = appMenu
        main.addItem(appItem)

        let fileItem = NSMenuItem()
        let fileMenu = NSMenu(title: "File")
        fileMenu.addItem(NSMenuItem(title: "Close", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w"))
        fileItem.submenu = fileMenu
        main.addItem(fileItem)

        let editItem = NSMenuItem()
        let editMenu = NSMenu(title: "Edit")
        editMenu.addItem(NSMenuItem(title: "Undo", action: Selector(("undo:")), keyEquivalent: "z"))
        let redo = NSMenuItem(title: "Redo", action: Selector(("redo:")), keyEquivalent: "z")
        redo.keyEquivalentModifierMask = [.command, .shift]
        editMenu.addItem(redo)
        editMenu.addItem(NSMenuItem.separator())
        editMenu.addItem(NSMenuItem(title: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x"))
        editMenu.addItem(NSMenuItem(title: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c"))
        editMenu.addItem(NSMenuItem(title: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v"))
        editMenu.addItem(NSMenuItem(title: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a"))
        editItem.submenu = editMenu
        main.addItem(editItem)

        let windowItem = NSMenuItem()
        let windowMenu = NSMenu(title: "Window")
        windowMenu.addItem(NSMenuItem(title: "Minimize", action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m"))
        windowItem.submenu = windowMenu
        main.addItem(windowItem)

        NSApp.mainMenu = main
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        if menu === statusMenu { rebuildStatusMenu() }
    }

    @discardableResult
    private func addItem(_ title: String, _ action: Selector, symbolName: String? = nil, hotkey: HotkeyAction? = nil) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        if let s = symbolName { item.image = symbol(s, size: 14) }
        if let a = hotkey, let h = keys[a], !h.isNone {
            if let ke = KeyNames.menuKeyEquivalent(for: h.keyCode) {
                item.keyEquivalent = ke
                item.keyEquivalentModifierMask = Hotkey.cocoaFlags(from: h.mods)
            } else {
                item.title = title + "    " + h.displayText
            }
        }
        statusMenu.addItem(item)
        return item
    }

    /// Rebuilt each time the menu opens, so language, shortcuts and checkmarks are always current.
    private func rebuildStatusMenu() {
        statusMenu.removeAllItems()
        addItem(L.t("Chụp vùng / cửa sổ"), #selector(menuCaptureRegion), symbolName: "camera.viewfinder", hotkey: .captureRegion)
        addItem(L.t("Chụp toàn màn hình"), #selector(menuCaptureFull), symbolName: "macwindow", hotkey: .captureFullScreen)
        addItem(L.t("Chụp vùng sau 3 giây"), #selector(menuCaptureDelayed), symbolName: "timer", hotkey: .captureDelayed)
        addItem(L.t("Chụp cuộn trang dài"), #selector(menuScroll), symbolName: "arrow.down.doc", hotkey: .scrollCapture)
        let recording = recorder?.isActive == true
        addItem(recording ? L.t("Dừng quay video") : L.t("Quay video màn hình"), #selector(menuRecord),
                symbolName: recording ? "stop.circle" : "record.circle", hotkey: .recordVideo)
        addItem(L.t("Chụp và trích chữ (OCR)"), #selector(menuOcr), symbolName: "text.viewfinder", hotkey: .ocr)
        statusMenu.addItem(NSMenuItem.separator())
        addItem(L.t("Thư viện ảnh & video"), #selector(menuLibrary), symbolName: "photo.on.rectangle", hotkey: .library)
        addItem(L.t("Mở ảnh..."), #selector(menuOpenImage), symbolName: "folder")
        addItem(L.t("Mở cửa sổ MiniSnap"), #selector(showLauncher), symbolName: "macwindow.on.rectangle")
        statusMenu.addItem(NSMenuItem.separator())

        let ask = addItem(L.t("Hỏi chụp ảnh / quay video / chụp cuộn sau khi chọn vùng"), #selector(menuToggleAsk))
        ask.state = Prefs.askModeAfterSelection ? .on : .off

        // Always bilingual so it can be found whichever language is active.
        let langItem = NSMenuItem(title: "Ngôn ngữ / Language", action: nil, keyEquivalent: "")
        langItem.image = symbol("globe", size: 14)
        let langMenu = NSMenu()
        let vi = NSMenuItem(title: "Tiếng Việt", action: #selector(menuVietnamese), keyEquivalent: "")
        vi.target = self
        vi.state = L.english ? .off : .on
        let en = NSMenuItem(title: "English", action: #selector(menuEnglish), keyEquivalent: "")
        en.target = self
        en.state = L.english ? .on : .off
        langMenu.addItem(vi)
        langMenu.addItem(en)
        langItem.submenu = langMenu
        statusMenu.addItem(langItem)

        addItem(L.t("Cài đặt phím tắt..."), #selector(menuHotkeys), symbolName: "keyboard")
        let login = addItem(L.t("Khởi động cùng máy Mac"), #selector(menuToggleLogin))
        login.state = LoginItem.enabled ? .on : .off
        statusMenu.addItem(NSMenuItem.separator())
        addItem(L.t("Giới thiệu MiniSnap"), #selector(showAbout), symbolName: "info.circle")
        addItem(L.t("Kiểm tra cập nhật..."), #selector(menuCheckUpdates), symbolName: "arrow.down.circle")
        let quit = addItem(L.t("Thoát MiniSnap"), #selector(menuQuit))
        quit.keyEquivalent = "q"
        quit.keyEquivalentModifierMask = [.command]
        statusItem?.button?.toolTip = trayTooltip()
    }

    private func keyHint() -> String {
        var parts: [String] = []
        let names: [(HotkeyAction, String)] = [(.captureRegion, L.t("chụp ảnh")), (.recordVideo, L.t("quay video")),
                                              (.scrollCapture, L.t("chụp cuộn")), (.ocr, L.t("trích chữ"))]
        for (a, n) in names {
            if let s = keys[a]?.shortText { parts.append(s + ": " + n) }
        }
        return parts.isEmpty ? L.t("Chưa gán phím tắt nào") : parts.joined(separator: " • ")
    }

    private func trayTooltip() -> String {
        if let s = keys[.captureRegion]?.shortText { return L.t("MiniSnap — nhấn ") + s + L.t(" để chụp") }
        return "MiniSnap"
    }

    // MARK: - Menu actions

    @objc private func menuCaptureRegion() { run(.captureRegion) }
    @objc private func menuCaptureFull() { run(.captureFullScreen) }
    @objc private func menuCaptureDelayed() { run(.captureDelayed) }
    @objc private func menuScroll() { run(.scrollCapture) }
    @objc private func menuRecord() { run(.recordVideo) }
    @objc private func menuOcr() { run(.ocr) }
    @objc private func menuLibrary() { run(.library) }
    @objc private func menuHotkeys() { showHotkeySettings() }
    @objc private func menuCheckUpdates() { Updater.shared.check(interactive: true) }
    @objc private func menuQuit() { NSApp.terminate(nil) }
    @objc private func menuToggleAsk() { Prefs.askModeAfterSelection.toggle() }
    @objc private func menuVietnamese() { setLanguage(english: false) }
    @objc private func menuEnglish() { setLanguage(english: true) }

    @objc private func menuToggleLogin() {
        do {
            try LoginItem.setEnabled(!LoginItem.enabled)
        } catch {
            Alerts.show("MiniSnap", L.t("Không đổi được cài đặt khởi động:\n") + error.localizedDescription)
        }
    }

    @objc private func menuOpenImage() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [UTType.image]
        panel.allowsMultipleSelection = false
        panel.directoryURL = LibraryPaths.imagesFolder
        NSApp.activate(ignoringOtherApps: true)
        if panel.runModal() == .OK, let url = panel.url { openImageFile(url) }
    }

    @objc private func showAbout() {
        if let a = aboutWindow {
            a.show()
            return
        }
        let a = AboutWindow()
        a.onClose = { [weak self] in self?.aboutWindow = nil }
        aboutWindow = a
        a.show()
    }

    /// The launcher's gear menu: the settings of the menu-bar menu, without the captures.
    private func makeSettingsMenu() -> NSMenu {
        let menu = NSMenu()
        menu.autoenablesItems = false
        func item(_ title: String, _ action: Selector, _ symbolName: String?) -> NSMenuItem {
            let i = NSMenuItem(title: title, action: action, keyEquivalent: "")
            i.target = self
            if let s = symbolName { i.image = symbol(s, size: 14) }
            menu.addItem(i)
            return i
        }
        _ = item(L.t("Kiểm tra cập nhật..."), #selector(menuCheckUpdates), "arrow.down.circle")
        _ = item(L.t("Cài đặt phím tắt..."), #selector(menuHotkeys), "keyboard")
        let langItem = NSMenuItem(title: "Ngôn ngữ / Language", action: nil, keyEquivalent: "")
        langItem.image = symbol("globe", size: 14)
        let langMenu = NSMenu()
        for (title, english, action) in [("Tiếng Việt", false, #selector(menuVietnamese)), ("English", true, #selector(menuEnglish))] {
            let l = NSMenuItem(title: title, action: action, keyEquivalent: "")
            l.target = self
            l.state = L.english == english ? .on : .off
            langMenu.addItem(l)
        }
        langItem.submenu = langMenu
        menu.addItem(langItem)
        menu.addItem(NSMenuItem.separator())
        item(L.t("Hỏi chụp ảnh / quay video / chụp cuộn sau khi chọn vùng"), #selector(menuToggleAsk), nil).state =
            Prefs.askModeAfterSelection ? .on : .off
        item(L.t("Khởi động cùng máy Mac"), #selector(menuToggleLogin), nil).state = LoginItem.enabled ? .on : .off
        menu.addItem(NSMenuItem.separator())
        _ = item(L.t("Giới thiệu MiniSnap"), #selector(showAbout), "info.circle")
        _ = item(L.t("Thoát MiniSnap"), #selector(menuQuit), nil)
        return menu
    }

    private func setLanguage(english: Bool) {
        if english == L.english { return }
        L.set(english: english)
        buildMainMenu()
        rebuildStatusMenu()
        // The launcher is rebuilt in the new language right away (other windows switch when reopened).
        if let l = launcher {
            l.onClose = nil
            l.window.close()
            launcher = nil
            showLauncher()
        }
        notifier.post("MiniSnap", english
            ? "Language changed to English. Open windows switch when you reopen them."
            : "Đã chuyển sang Tiếng Việt. Các cửa sổ đang mở sẽ đổi khi bạn mở lại.")
    }

    private func run(_ action: HotkeyAction) {
        switch action {
        case .captureRegion: beginCapture(.image, delay: 0)
        case .captureFullScreen: beginCapture(.fullScreen, delay: 0)
        case .captureDelayed: beginCapture(.image, delay: 3)
        case .scrollCapture: beginCapture(.scroll, delay: 0)
        case .recordVideo: toggleRecording()
        case .ocr: beginCapture(.ocr, delay: 0)
        case .library: showLibrary(reveal: nil)
        }
    }

    // MARK: - Hotkey settings

    private func showHotkeySettings() {
        if let w = hotkeyWindow {
            w.show()
            return
        }
        // Global shortcuts would swallow the keys the user is trying to record, so pause them meanwhile.
        hotkeys.unregisterAll()
        let w = HotkeySettingsWindow(current: keys) { [weak self] map in
            guard let self = self else { return [] }
            self.keys = map
            HotkeySettings.save(map)
            let failed = self.hotkeys.register(map)
            self.hotkeys.unregisterAll()
            self.rebuildStatusMenu()
            return failed
        }
        w.onClose = { [weak self] in
            guard let self = self else { return }
            self.hotkeyWindow = nil
            _ = self.hotkeys.register(self.keys)
        }
        hotkeyWindow = w
        w.show()
    }

    // MARK: - Capture

    private func toggleRecording() {
        if let r = recorder, r.isActive {
            r.stopRecording()
        } else {
            beginCapture(.video, delay: 0)
        }
    }

    private func beginCapture(_ mode: Mode, delay: Int) {
        if busy || overlay != nil || scrollSession != nil { return }
        if recorder?.isActive == true && mode != .video { return }
        if !Permissions.hasScreenRecording() {
            Permissions.requestScreenRecording()
            if !Permissions.hasScreenRecording() {
                Permissions.showScreenRecordingAlert(detail: nil)
                return
            }
        }
        if mode == .scroll && !Permissions.hasAccessibility() {
            Permissions.showAccessibilityAlert()
            return
        }
        busy = true
        if delay > 0 {
            notifier.post("MiniSnap", L.t("Sẽ chụp sau ") + String(delay) + L.t(" giây..."))
        }
        Task {
            // A short delay also lets the menu finish closing before the screen is grabbed.
            let ms = max(200, delay * 1000)
            try? await Task.sleep(nanoseconds: UInt64(ms) * 1_000_000)
            await self.doCapture(mode)
        }
    }

    private static func prompt(for mode: Mode) -> String? {
        switch mode {
        case .scroll: return L.t("Chụp cuộn: chọn cửa sổ hoặc vùng có nội dung cần cuộn — app sẽ tự cuộn xuống")
        case .video: return L.t("Quay video: chọn cửa sổ hoặc kéo chọn vùng cần quay (Enter = toàn màn hình)")
        case .ocr: return L.t("Trích chữ: chọn vùng có chữ cần lấy")
        default: return nil
        }
    }

    private func doCapture(_ mode: Mode) async {
        let windowRects = mode == .fullScreen ? [] : ScreenCapture.windowRects()
        let shots: [DisplayShot]
        do {
            shots = try await ScreenCapture.captureAllDisplays()
        } catch {
            busy = false
            Permissions.showScreenRecordingAlert(detail: error.localizedDescription)
            return
        }

        if mode == .fullScreen {
            busy = false
            let id = ScreenCapture.displayIDUnderMouse()
            let shot = shots.first { $0.display.displayID == id } ?? shots[0]
            saveAndEdit(shot.image, scale: shot.display.scale)
            return
        }

        let ask = mode == .image && Prefs.askModeAfterSelection
        let defaultAction: OverlayAction
        switch mode {
        case .video: defaultAction = .video
        case .scroll: defaultAction = .scroll
        default: defaultAction = .screenshot
        }
        let ov = CaptureOverlayController(shots: shots, windowRects: windowRects, prompt: AppDelegate.prompt(for: mode),
                                          askMode: ask, defaultAction: defaultAction) { [weak self] result in
            guard let self = self else { return }
            self.overlay = nil
            self.busy = false
            if let r = result { self.handleOverlayResult(r, mode: mode) }
        }
        if ov.isEmpty {
            busy = false
            return
        }
        overlay = ov
        ov.show()
    }

    private func handleOverlayResult(_ r: OverlayResult, mode: Mode) {
        if mode == .ocr {
            if let img = r.croppedImage { showOcr(img) }
            return
        }
        switch r.action {
        case .screenshot:
            if let img = r.croppedImage { saveAndEdit(img, scale: r.shot.display.scale) }
        case .video:
            if r.pointRect.width < 16 || r.pointRect.height < 16 { return }
            let rc = RecordingController(display: r.shot.display, localRect: r.pointRect) { [weak self] url, error in
                self?.recordingDone(url, error)
            }
            recorder = rc
            rc.start()
        case .scroll:
            if !Permissions.hasAccessibility() {
                Permissions.showAccessibilityAlert()
                return
            }
            let session = ScrollCaptureSession(display: r.shot.display, localRect: r.pointRect) { [weak self] image in
                guard let self = self else { return }
                self.scrollSession = nil
                if let img = image { self.saveAndEdit(img, scale: r.shot.display.scale) }
            }
            scrollSession = session
            session.start()
        }
    }

    private func recordingDone(_ url: URL?, _ error: Error?) {
        recorder = nil
        if let e = error {
            Alerts.show("MiniSnap", L.t("Không quay được video:\n") + e.localizedDescription)
        } else if let u = url, FileManager.default.fileExists(atPath: u.path) {
            showLibrary(reveal: u)
            notifier.post(L.t("Đã lưu video"), u.lastPathComponent + L.t("\nBấm vào đây để xem."), info: "open:" + u.path)
        }
        if quitAfterRecording {
            quitAfterRecording = false
            NSApp.terminate(nil)
        }
    }

    // MARK: - Results

    private func saveAndEdit(_ image: CGImage, scale: CGFloat) {
        var url: URL? = LibraryPaths.newImageURL()
        if let u = url {
            do { try ImageUtil.write(image, to: u) } catch { url = nil }
        }
        _ = ImageUtil.copyToPasteboard(image)
        openEditor(image, url: url, scale: scale)
    }

    private func openEditor(_ image: CGImage, url: URL?, scale: CGFloat) {
        let ed = EditorController(image: image, url: url, imageScale: scale)
        ed.onNewCapture = { [weak self] in self?.beginCapture(.image, delay: 0) }
        ed.onOcr = { [weak self] img in self?.showOcr(img) }
        ed.onLibrary = { [weak self] in self?.showLibrary(reveal: nil) }
        ed.onClose = { [weak self, weak ed] in
            guard let self = self, let ed = ed else { return }
            self.editors.removeAll { $0 === ed }
        }
        editors.append(ed)
        ed.show()
    }

    private func openImageFile(_ url: URL) {
        guard let img = ImageUtil.load(url) else {
            Alerts.show("MiniSnap", L.t("Không mở được ảnh:\n") + url.lastPathComponent)
            return
        }
        // Captures in our own library were taken at the screen's backing scale.
        let inLibrary = url.deletingLastPathComponent().standardizedFileURL == LibraryPaths.imagesFolder.standardizedFileURL
        let scale = inLibrary ? (NSScreen.main?.backingScaleFactor ?? 1) : 1
        openEditor(img, url: url, scale: scale)
    }

    private func showOcr(_ image: CGImage) {
        let w = OcrWindow(image: image)
        w.onClose = { [weak self, weak w] in
            guard let self = self, let w = w else { return }
            self.ocrWindows.removeAll { $0 === w }
        }
        ocrWindows.append(w)
        w.show()
    }

    private func ocrFile(_ url: URL) {
        guard let img = ImageUtil.load(url) else {
            Alerts.show("MiniSnap", L.t("Không mở được ảnh:\n") + url.lastPathComponent)
            return
        }
        showOcr(img)
    }

    private func showLibrary(reveal: URL?) {
        let lib: LibraryWindow
        if let l = library {
            lib = l
        } else {
            lib = LibraryWindow()
            lib.onOpenImage = { [weak self] u in self?.openImageFile(u) }
            lib.onOcr = { [weak self] u in self?.ocrFile(u) }
            lib.onClose = { [weak self] in self?.library = nil }
            library = lib
        }
        lib.show()
        if let r = reveal { lib.reveal(r) }
    }
}
