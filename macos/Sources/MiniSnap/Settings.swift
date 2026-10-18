import AppKit
import ServiceManagement
import ApplicationServices

/// Small persisted preferences.
enum Prefs {
    private static let askModeKey = "MiniSnap.AskModeAfterSelection"
    private static let lastUpdateCheckKey = "MiniSnap.LastUpdateCheck"

    /// When on, a region/window capture shows the Screenshot / Video / Scroll bar before capturing.
    static var askModeAfterSelection: Bool {
        get {
            if UserDefaults.standard.object(forKey: askModeKey) == nil { return true }
            return UserDefaults.standard.bool(forKey: askModeKey)
        }
        set { UserDefaults.standard.set(newValue, forKey: askModeKey) }
    }

    private static let showLauncherKey = "MiniSnap.ShowLauncherAtStart"

    /// The launcher window appears when MiniSnap is opened (see AppDelegate for the start-at-login case).
    static var showLauncherAtStart: Bool {
        get {
            if UserDefaults.standard.object(forKey: showLauncherKey) == nil { return true }
            return UserDefaults.standard.bool(forKey: showLauncherKey)
        }
        set { UserDefaults.standard.set(newValue, forKey: showLauncherKey) }
    }

    static var lastUpdateCheck: Date? {
        get { UserDefaults.standard.object(forKey: lastUpdateCheckKey) as? Date }
        set { UserDefaults.standard.set(newValue, forKey: lastUpdateCheckKey) }
    }
}

/// Where captures and recordings are stored: ~/Pictures/MiniSnap and ~/Movies/MiniSnap.
enum LibraryPaths {
    static let imageExtensions: Set<String> = ["png", "jpg", "jpeg", "bmp", "gif", "tiff", "tif", "heic"]
    static let videoExtensions: Set<String> = ["mp4", "mov"]

    static var imagesFolder: URL { ensure(.picturesDirectory, fallback: "Pictures") }
    static var videosFolder: URL { ensure(.moviesDirectory, fallback: "Movies") }

    private static func ensure(_ dir: FileManager.SearchPathDirectory, fallback: String) -> URL {
        let fm = FileManager.default
        let base: URL
        if let over = ProcessInfo.processInfo.environment["MINISNAP_LIBRARY"], !over.isEmpty {
            base = URL(fileURLWithPath: over).appendingPathComponent(fallback)
        } else if let u = fm.urls(for: dir, in: .userDomainMask).first {
            base = u
        } else {
            base = fm.homeDirectoryForCurrentUser.appendingPathComponent(fallback)
        }
        let folder = base.appendingPathComponent("MiniSnap", isDirectory: true)
        try? fm.createDirectory(at: folder, withIntermediateDirectories: true, attributes: nil)
        return folder
    }

    static func newImageURL() -> URL { unique(in: imagesFolder, ext: "png") }
    static func newVideoURL() -> URL { unique(in: videosFolder, ext: "mp4") }

    private static func unique(in folder: URL, ext: String) -> URL {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        let name = "MiniSnap_" + f.string(from: Date())
        var url = folder.appendingPathComponent(name + "." + ext)
        var i = 2
        while FileManager.default.fileExists(atPath: url.path) {
            url = folder.appendingPathComponent(name + "_" + String(i) + "." + ext)
            i += 1
        }
        return url
    }

    static func isImage(_ url: URL) -> Bool { imageExtensions.contains(url.pathExtension.lowercased()) }
    static func isVideo(_ url: URL) -> Bool { videoExtensions.contains(url.pathExtension.lowercased()) }

    static func allFiles() -> [(url: URL, date: Date, size: Int)] {
        var result: [(url: URL, date: Date, size: Int)] = []
        let keys: [URLResourceKey] = [.contentModificationDateKey, .fileSizeKey, .isRegularFileKey]
        for (folder, isVideo) in [(imagesFolder, false), (videosFolder, true)] {
            let items = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: keys, options: [.skipsHiddenFiles])) ?? []
            for u in items {
                let wanted = isVideo ? LibraryPaths.isVideo(u) : LibraryPaths.isImage(u)
                if !wanted { continue }
                let v = try? u.resourceValues(forKeys: Set(keys))
                if v?.isRegularFile == false { continue }
                result.append((u, v?.contentModificationDate ?? Date.distantPast, v?.fileSize ?? 0))
            }
        }
        result.sort { $0.date > $1.date }
        return result
    }
}

/// "Start at login" through SMAppService (macOS 13+).
enum LoginItem {
    static var enabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    static func setEnabled(_ on: Bool) throws {
        if on {
            try SMAppService.mainApp.register()
        } else {
            try SMAppService.mainApp.unregister()
        }
    }
}

/// TCC permission helpers.
@MainActor
enum Permissions {
    static func hasScreenRecording() -> Bool {
        CGPreflightScreenCaptureAccess()
    }

    static func requestScreenRecording() {
        _ = CGRequestScreenCaptureAccess()
    }

    static func hasAccessibility() -> Bool {
        AXIsProcessTrusted()
    }

    /// Shows the system prompt (adds MiniSnap to the Accessibility list) and returns the current state.
    @discardableResult
    static func promptAccessibility() -> Bool {
        // Literal value of kAXTrustedCheckOptionPrompt (avoids Unmanaged/CFString import differences between SDKs).
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }

    static func openPrivacyPane(_ anchor: String) {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?" + anchor) {
            NSWorkspace.shared.open(url)
        }
    }

    static func showScreenRecordingAlert(detail: String?) {
        let alert = NSAlert()
        alert.messageText = L.t("Cần quyền Ghi màn hình")
        var text = L.t("MiniSnap cần quyền Ghi màn hình (Screen Recording) để chụp ảnh và quay video.\n\nMở Cài đặt hệ thống → Quyền riêng tư & Bảo mật → Ghi màn hình & âm thanh hệ thống, bật MiniSnap, rồi mở lại MiniSnap.")
        text += "\n\n" + L.t("Nếu MiniSnap đã bật sẵn trong danh sách mà vẫn bị hỏi (thường sau khi cập nhật), hãy chọn MiniSnap, bấm nút − để xoá, rồi mở lại MiniSnap và cho phép lại.")
        if let d = detail, !d.isEmpty { text += "\n\n(" + d + ")" }
        alert.informativeText = text
        alert.alertStyle = .warning
        alert.addButton(withTitle: L.t("Mở Cài đặt hệ thống"))
        alert.addButton(withTitle: L.t("Để sau"))
        NSApp.activate(ignoringOtherApps: true)
        if alert.runModal() == .alertFirstButtonReturn {
            openPrivacyPane("Privacy_ScreenCapture")
        }
    }

    static func showAccessibilityAlert() {
        promptAccessibility()
        let alert = NSAlert()
        alert.messageText = L.t("Cần quyền Trợ năng")
        alert.informativeText = L.t("Chụp cuộn cần quyền Trợ năng (Accessibility) để tự cuộn cửa sổ.\n\nMở Cài đặt hệ thống → Quyền riêng tư & Bảo mật → Trợ năng, bật MiniSnap, rồi thử lại.")
        alert.alertStyle = .warning
        alert.addButton(withTitle: L.t("Mở Cài đặt hệ thống"))
        alert.addButton(withTitle: L.t("Để sau"))
        NSApp.activate(ignoringOtherApps: true)
        if alert.runModal() == .alertFirstButtonReturn {
            openPrivacyPane("Privacy_Accessibility")
        }
    }
}

@MainActor
enum Alerts {
    static func show(_ title: String, _ text: String, style: NSAlert.Style = .warning) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = text
        alert.alertStyle = style
        alert.addButton(withTitle: "OK")
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
    }
}
