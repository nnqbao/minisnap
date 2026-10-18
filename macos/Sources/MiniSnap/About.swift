import AppKit
import CryptoKit

enum AppInfo {
    static var version: String {
        (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String) ?? "1.3.0"
    }
    static let author = "Nguyễn Năng Quốc Bảo"
    static let email = "nnqbao@gmail.com"
    static let repoURL = "https://github.com/nnqbao/minisnap"
    static let latestReleaseAPI = "https://api.github.com/repos/nnqbao/minisnap/releases/latest"
    static let macAssetName = "MiniSnap-macOS.zip"
}

/// "About MiniSnap" window.
@MainActor
final class AboutWindow: NSObject, NSWindowDelegate {
    let window: NSWindow
    var onClose: (() -> Void)?

    override init() {
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 440, height: 400),
                          styleMask: [.titled, .closable],
                          backing: .buffered, defer: false)
        super.init()
        window.isReleasedWhenClosed = false
        window.title = L.t("Giới thiệu — MiniSnap")
        window.delegate = self
        applyGlassWindowStyle(window)
        build()
        window.center()
    }

    private func linkButton(_ title: String, action: Selector) -> NSButton {
        let b = NSButton(title: title, target: self, action: action)
        b.isBordered = false
        b.attributedTitle = NSAttributedString(string: title, attributes: [
            .foregroundColor: NSColor.linkColor,
            .underlineStyle: NSUnderlineStyle.single.rawValue,
            .font: NSFont.systemFont(ofSize: 13)
        ])
        return b
    }

    private func build() {
        let (root, content) = makeGlassWindowBackground()

        let icon = NSImageView()
        icon.image = NSApp.applicationIconImage
        icon.imageScaling = .scaleProportionallyUpOrDown
        icon.translatesAutoresizingMaskIntoConstraints = false
        icon.widthAnchor.constraint(equalToConstant: 96).isActive = true
        icon.heightAnchor.constraint(equalToConstant: 96).isActive = true

        let name = NSTextField(labelWithString: "MiniSnap")
        name.font = NSFont.systemFont(ofSize: 26, weight: .bold)
        let version = NSTextField(labelWithString: L.t("Phiên bản ") + AppInfo.version)
        version.textColor = .secondaryLabelColor
        let tagline = NSTextField(wrappingLabelWithString: L.t("Đây là phần mềm chụp ảnh, quay phim màn hình miễn phí, mã nguồn mở dành cho mọi người."))
        tagline.alignment = .center
        tagline.preferredMaxLayoutWidth = 360
        let author = NSTextField(labelWithString: L.t("Tác giả: ") + AppInfo.author)
        let mail = linkButton(AppInfo.email, action: #selector(mailPressed))
        let github = linkButton(AppInfo.repoURL.replacingOccurrences(of: "https://", with: ""), action: #selector(githubPressed))
        let license = NSTextField(labelWithString: L.t("Giấy phép MIT"))
        license.textColor = .secondaryLabelColor

        let update = NSButton(title: L.t("Kiểm tra cập nhật..."), target: self, action: #selector(updatePressed))
        styleGlassButton(update, prominent: true, tint: NSColor.systemBlue)
        let close = NSButton(title: L.t("Đóng"), target: self, action: #selector(closePressed))
        close.keyEquivalent = "\u{1b}"
        styleGlassButton(close, prominent: false, tint: nil)
        for b in [update, close] where !glassAvailable() {
            b.translatesAutoresizingMaskIntoConstraints = false
            b.heightAnchor.constraint(equalToConstant: 30).isActive = true
            b.widthAnchor.constraint(greaterThanOrEqualToConstant: 110).isActive = true
        }
        let buttons = NSStackView(views: [update, close])
        buttons.spacing = 10

        let stack = NSStackView(views: [icon, name, version, tagline, author, mail, github, license, buttons])
        stack.orientation = .vertical
        stack.alignment = .centerX
        stack.spacing = 8
        stack.setCustomSpacing(16, after: tagline)
        stack.setCustomSpacing(18, after: license)
        stack.edgeInsets = NSEdgeInsets(top: 40, left: 30, bottom: 22, right: 30)
        stack.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            stack.topAnchor.constraint(equalTo: content.topAnchor),
            stack.bottomAnchor.constraint(equalTo: content.bottomAnchor),
            stack.widthAnchor.constraint(equalToConstant: 440)
        ])
        window.contentView = root
        root.layoutSubtreeIfNeeded()
        window.setContentSize(root.fittingSize)
    }

    func show() {
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    @objc private func mailPressed() {
        if let u = URL(string: "mailto:" + AppInfo.email) { NSWorkspace.shared.open(u) }
    }

    @objc private func githubPressed() {
        if let u = URL(string: AppInfo.repoURL) { NSWorkspace.shared.open(u) }
    }

    @objc private func updatePressed() { Updater.shared.check(interactive: true) }
    @objc private func closePressed() { window.close() }

    func windowWillClose(_ notification: Notification) { onClose?() }
}

/// Checks GitHub releases and downloads + verifies the macOS zip. When the installed app can be written to
/// (e.g. /Applications) it offers "Install and relaunch": the new app is staged beside the old one, and a
/// detached shell swaps it in after MiniSnap quits, then opens it. Otherwise the new app is shown in Finder.
@MainActor
final class Updater {
    static let shared = Updater()

    /// Called for a silent (automatic) check that found a newer version: (version, notify-text).
    var onSilentUpdateFound: ((String) -> Void)?

    private var busy = false
    private var progressPanel: NSPanel?

    struct Release: Decodable {
        let tag_name: String
        let name: String?
        let body: String?
        let html_url: String
        let assets: [Asset]
    }

    struct Asset: Decodable {
        let name: String
        let browser_download_url: String
        let digest: String?
    }

    private enum Outcome {
        case noReleases
        case release(Release)
    }

    /// Semantic version compare ("v1.4.0" vs "1.3.0"); returns -1, 0 or 1.
    static func compareVersions(_ a: String, _ b: String) -> Int {
        func parts(_ s: String) -> [Int] {
            var t = s.trimmingCharacters(in: .whitespaces)
            if t.hasPrefix("v") || t.hasPrefix("V") { t.removeFirst() }
            let core = t.split(whereSeparator: { $0 == "-" || $0 == "+" }).first.map(String.init) ?? t
            return core.split(separator: ".").map { Int($0.filter { $0.isNumber }) ?? 0 }
        }
        let pa = parts(a), pb = parts(b)
        for i in 0..<max(pa.count, pb.count) {
            let x = i < pa.count ? pa[i] : 0
            let y = i < pb.count ? pb[i] : 0
            if x != y { return x < y ? -1 : 1 }
        }
        return 0
    }

    /// Automatic check, at most once a day.
    func checkDailyIfNeeded() {
        if let last = Prefs.lastUpdateCheck, Date().timeIntervalSince(last) < 24 * 3600 { return }
        Prefs.lastUpdateCheck = Date()
        check(interactive: false)
    }

    func check(interactive: Bool) {
        if busy { return }
        busy = true
        Task {
            let outcome: Outcome
            do {
                outcome = try await fetchLatest()
            } catch {
                busy = false
                if interactive {
                    Alerts.show(L.t("Không kiểm tra được cập nhật"), L.t("Hãy kiểm tra kết nối mạng rồi thử lại.\n\n") + error.localizedDescription)
                }
                return
            }
            busy = false
            switch outcome {
            case .noReleases:
                if interactive {
                    Alerts.show(L.t("Bạn đang dùng bản mới nhất"), L.t("Chưa có bản phát hành nào trên GitHub"), style: .informational)
                }
            case .release(let r):
                let newer = Updater.compareVersions(r.tag_name, AppInfo.version) > 0
                if !newer {
                    if interactive {
                        Alerts.show(L.t("Bạn đang dùng bản mới nhất"), "MiniSnap " + AppInfo.version, style: .informational)
                    }
                } else if interactive {
                    offer(r)
                } else {
                    onSilentUpdateFound?(r.tag_name)
                }
            }
        }
    }

    private func fetchLatest() async throws -> Outcome {
        guard let url = URL(string: AppInfo.latestReleaseAPI) else { throw CaptureError.failed("Bad URL") }
        var req = URLRequest(url: url)
        req.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        req.setValue("MiniSnap", forHTTPHeaderField: "User-Agent")
        req.timeoutInterval = 20
        let (data, resp) = try await URLSession.shared.data(for: req)
        let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
        if code == 404 { return .noReleases }
        if code != 200 { throw CaptureError.failed("GitHub HTTP " + String(code)) }
        let r = try JSONDecoder().decode(Release.self, from: data)
        return .release(r)
    }

    private func offer(_ r: Release) {
        var notes = (r.body ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if notes.count > 600 { notes = String(notes.prefix(600)) + "…" }
        let alert = NSAlert()
        alert.messageText = L.t("Đã có MiniSnap ") + r.tag_name + L.t(" (bạn đang dùng ") + AppInfo.version + ")"
        alert.informativeText = notes
        alert.alertStyle = .informational
        alert.addButton(withTitle: L.t("Tải về"))
        alert.addButton(withTitle: L.t("Để sau"))
        NSApp.activate(ignoringOtherApps: true)
        guard alert.runModal() == .alertFirstButtonReturn else { return }

        guard let asset = r.assets.first(where: { $0.name == AppInfo.macAssetName }),
              let downloadURL = URL(string: asset.browser_download_url) else {
            let a = NSAlert()
            a.messageText = L.t("Không tải được bản cập nhật")
            a.informativeText = L.t("Bản phát hành này không có file MiniSnap-macOS.zip. Mở trang phát hành?")
            a.addButton(withTitle: L.t("Mở trang phát hành"))
            a.addButton(withTitle: L.t("Để sau"))
            if a.runModal() == .alertFirstButtonReturn, let u = URL(string: r.html_url) { NSWorkspace.shared.open(u) }
            return
        }
        download(downloadURL, digest: asset.digest)
    }

    private func showProgress() {
        let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 320, height: 80), styleMask: [.titled], backing: .buffered, defer: false)
        panel.isReleasedWhenClosed = false
        panel.title = "MiniSnap"
        let spinner = NSProgressIndicator()
        spinner.style = .spinning
        spinner.controlSize = .small
        spinner.startAnimation(nil)
        let label = NSTextField(labelWithString: L.t("Đang tải bản cập nhật..."))
        let row = NSStackView(views: [spinner, label])
        row.spacing = 10
        row.edgeInsets = NSEdgeInsets(top: 20, left: 20, bottom: 20, right: 20)
        panel.contentView = row
        panel.center()
        panel.makeKeyAndOrderFront(nil)
        progressPanel = panel
    }

    private func hideProgress() {
        progressPanel?.orderOut(nil)
        progressPanel = nil
    }

    private func download(_ url: URL, digest: String?) {
        busy = true
        showProgress()
        Task {
            defer {
                busy = false
                hideProgress()
            }
            do {
                let dir = FileManager.default.temporaryDirectory.appendingPathComponent("MiniSnap-update-" + UUID().uuidString, isDirectory: true)
                try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true, attributes: nil)
                var req = URLRequest(url: url)
                req.setValue("MiniSnap", forHTTPHeaderField: "User-Agent")
                let (tmp, resp) = try await URLSession.shared.download(for: req)
                let code = (resp as? HTTPURLResponse)?.statusCode ?? 200
                if code != 200 { throw CaptureError.failed("HTTP " + String(code)) }
                let zip = dir.appendingPathComponent(AppInfo.macAssetName)
                try FileManager.default.moveItem(at: tmp, to: zip)

                let expected = digest.flatMap { d -> String? in
                    let lower = d.lowercased()
                    return lower.hasPrefix("sha256:") ? String(lower.dropFirst(7)) : nil
                }
                let app = try await Task.detached(priority: .userInitiated) { () throws -> URL? in
                    if let exp = expected {
                        let data = try Data(contentsOf: zip, options: .mappedIfSafe)
                        let hash = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
                        if hash != exp { throw CaptureError.failed(L.t("File tải về không khớp mã kiểm tra SHA-256 — đã huỷ để an toàn.")) }
                    }
                    let p = Process()
                    p.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
                    p.arguments = ["-x", "-k", zip.path, dir.path]
                    try p.run()
                    p.waitUntilExit()
                    if p.terminationStatus != 0 { throw CaptureError.failed("ditto exit code " + String(p.terminationStatus)) }
                    return Updater.findApp(in: dir)
                }.value
                hideProgress()
                guard let appURL = app else { throw CaptureError.failed("MiniSnap.app not found in the download") }
                let current = Bundle.main.bundleURL
                guard Updater.canReplace(current) else {
                    NSWorkspace.shared.activateFileViewerSelecting([appURL])
                    Alerts.show(L.t("Đã tải bản mới"), L.t("Finder đang hiện MiniSnap.app mới. Hãy thoát MiniSnap, rồi kéo app mới vào thư mục Applications (chọn Thay thế)."), style: .informational)
                    return
                }
                let alert = NSAlert()
                alert.messageText = L.t("Đã tải bản mới")
                alert.informativeText = L.t("Bản mới đã được kiểm tra mã SHA-256. MiniSnap sẽ thoát, thay app trong thư mục ") + current.deletingLastPathComponent().path + L.t(" rồi tự mở lại.\n\nmacOS có thể hỏi lại quyền Ghi màn hình cho bản mới.")
                alert.alertStyle = .informational
                alert.addButton(withTitle: L.t("Cài đặt và khởi động lại"))
                alert.addButton(withTitle: L.t("Để sau"))
                NSApp.activate(ignoringOtherApps: true)
                guard alert.runModal() == .alertFirstButtonReturn else { return }
                // Copy the new app next to the old one first: any failure here leaves the installed app untouched.
                let staged = try await Task.detached(priority: .userInitiated) { () throws -> URL in
                    try Updater.stage(appURL, nextTo: current)
                }.value
                try Updater.swapAfterExit(staged: staged, over: current)
                NSApp.terminate(nil)
            } catch {
                hideProgress()
                Alerts.show(L.t("Không tải được bản cập nhật"), error.localizedDescription)
            }
        }
    }

    /// The running app can be replaced in place: a real .app bundle in a folder we may write to, and not
    /// one that macOS runs from a read-only disk image or a translocated (quarantined) copy.
    nonisolated static func canReplace(_ bundle: URL) -> Bool {
        let path = bundle.standardizedFileURL.path
        guard bundle.pathExtension == "app", !path.hasPrefix("/Volumes/"), !path.contains("/AppTranslocation/") else { return false }
        let fm = FileManager.default
        return fm.isWritableFile(atPath: bundle.deletingLastPathComponent().path) && fm.isWritableFile(atPath: path)
    }

    /// Copies the downloaded app beside the installed one (same volume, so the later swap is a rename).
    nonisolated static func stage(_ newApp: URL, nextTo current: URL) throws -> URL {
        let staged = current.deletingLastPathComponent().appendingPathComponent("." + current.lastPathComponent + ".update")
        let fm = FileManager.default
        if fm.fileExists(atPath: staged.path) { try fm.removeItem(at: staged) }
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        p.arguments = [newApp.path, staged.path]
        try p.run()
        p.waitUntilExit()
        if p.terminationStatus != 0 {
            try? fm.removeItem(at: staged)
            throw CaptureError.failed("ditto exit code " + String(p.terminationStatus))
        }
        // Downloads made by URLSession carry no quarantine flag, but a copy from elsewhere might.
        let x = Process()
        x.executableURL = URL(fileURLWithPath: "/usr/bin/xattr")
        x.arguments = ["-dr", "com.apple.quarantine", staged.path]
        x.standardError = FileHandle.nullDevice
        try? x.run()
        x.waitUntilExit()
        return staged
    }

    /// Starts a detached shell that waits for this process to quit, swaps the staged app in (the old one is
    /// put back if the swap fails) and opens MiniSnap again. Paths are passed as arguments, never inside the script.
    static func swapAfterExit(staged: URL, over current: URL) throws {
        let script = """
        pid="$1"; new="$2"; old="$3"; backup="$old.old-$$"
        i=0
        while kill -0 "$pid" 2>/dev/null; do
          sleep 0.2; i=$((i+1))
          if [ "$i" -ge 300 ]; then rm -rf "$new"; exit 1; fi
        done
        if mv "$old" "$backup"; then
          if mv "$new" "$old"; then rm -rf "$backup"; else mv "$backup" "$old"; rm -rf "$new"; fi
        else
          rm -rf "$new"
        fi
        /usr/bin/open "$old"
        """
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/sh")
        p.arguments = ["-c", script, "minisnap-update", String(ProcessInfo.processInfo.processIdentifier), staged.path, current.path]
        p.standardInput = FileHandle.nullDevice
        p.standardOutput = FileHandle.nullDevice
        p.standardError = FileHandle.nullDevice
        try p.run()
    }

    nonisolated static func findApp(in dir: URL) -> URL? {
        let fm = FileManager.default
        guard let en = fm.enumerator(at: dir, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]) else { return nil }
        while let u = en.nextObject() as? URL {
            if u.pathExtension == "app" {
                if u.lastPathComponent == "MiniSnap.app" { return u }
                en.skipDescendants()
            }
        }
        return nil
    }
}
