import Foundation

/// UI language. Vietnamese text in the code is the key; English comes from the table below.
/// Text without an entry (symbols, or a missing translation) is shown unchanged.
enum L {
    private static let defaultsKey = "MiniSnap.Language"

    private(set) static var english: Bool = L.initialEnglish()

    private static func initialEnglish() -> Bool {
        if let over = ProcessInfo.processInfo.environment["MINISNAP_LANG"], !over.isEmpty {
            return over == "en"
        }
        if let saved = UserDefaults.standard.string(forKey: defaultsKey) {
            return saved == "en"
        }
        let first = Locale.preferredLanguages.first ?? "en"
        return !first.lowercased().hasPrefix("vi")
    }

    static func t(_ vi: String) -> String {
        if english, let en = table[vi] { return en }
        return vi
    }

    static func set(english value: Bool) {
        english = value
        UserDefaults.standard.set(value ? "en" : "vi", forKey: defaultsKey)
    }

    private static let table: [String: String] = [
        // Menu bar, notifications
        "Chụp vùng / cửa sổ": "Capture region / window",
        "Chụp toàn màn hình": "Capture full screen",
        "Chụp vùng sau 3 giây": "Capture region after 3 seconds",
        "Chụp cuộn trang dài": "Scrolling capture",
        "Quay video màn hình": "Record screen video",
        "Dừng quay video": "Stop recording",
        "Quay video (bắt đầu / dừng)": "Record video (start / stop)",
        "Chụp và trích chữ (OCR)": "Capture and extract text (OCR)",
        "Thư viện ảnh & video": "Image & video library",
        "Mở thư viện ảnh & video": "Open image & video library",
        "Mở ảnh...": "Open image...",
        "Mở cửa sổ MiniSnap": "Open the MiniSnap window",
        "Cài đặt": "Settings",
        "Chụp sau 3 giây": "Capture after 3 seconds",
        "Chụp ảnh, quay video màn hình và trích chữ": "Screenshots, screen recording and text extraction",
        "MiniSnap chạy trên thanh menu: bấm biểu tượng này ở góc trên bên phải màn hình để chụp bất cứ lúc nào, kể cả khi đã đóng cửa sổ này.": "MiniSnap lives in the menu bar: click this icon at the top right of the screen to capture at any time, even after closing this window.",
        "Hiện cửa sổ này khi mở MiniSnap": "Show this window when MiniSnap opens",
        "Cài đặt phím tắt...": "Keyboard shortcuts...",
        "Khởi động cùng máy Mac": "Start at login",
        "Thoát MiniSnap": "Quit MiniSnap",
        "Hỏi chụp ảnh / quay video / chụp cuộn sau khi chọn vùng": "Ask screenshot / video / scroll after selecting",
        "Giới thiệu MiniSnap": "About MiniSnap",
        "Kiểm tra cập nhật...": "Check for updates...",
        "MiniSnap đã sẵn sàng": "MiniSnap is ready",
        "MiniSnap — nhấn ": "MiniSnap — press ",
        " để chụp": " to capture",
        "chụp ảnh": "capture",
        "quay video": "record video",
        "chụp cuộn": "scrolling capture",
        "trích chữ": "extract text",
        "Chưa gán phím tắt nào": "No shortcuts assigned",
        ". Bấm vào biểu tượng trên thanh menu để xem thêm hoặc đổi phím tắt.": ". Click the menu bar icon for more options or to change shortcuts.",
        "\nKhông đăng ký được: ": "\nCould not register: ",
        " (đang bị ứng dụng khác dùng) — vào Cài đặt phím tắt để đổi.": " (used by another app) — change it in Keyboard shortcuts.",
        "Sẽ chụp sau ": "Capturing in ",
        " giây...": " seconds...",
        "Chụp cuộn: chọn cửa sổ hoặc vùng có nội dung cần cuộn — app sẽ tự cuộn xuống": "Scrolling capture: pick the window or area to scroll — MiniSnap scrolls it for you",
        "Quay video: chọn cửa sổ hoặc kéo chọn vùng cần quay (Enter = toàn màn hình)": "Record video: pick a window or drag an area (Enter = full screen)",
        "Trích chữ: chọn vùng có chữ cần lấy": "Extract text: select the area containing the text",
        "Không quay được video:\n": "Could not record video:\n",
        "Đã lưu video": "Video saved",
        "\nBấm vào đây để xem.": "\nClick here to watch it.",
        "Không mở được ảnh:\n": "Could not open the image:\n",
        "Không đổi được cài đặt khởi động:\n": "Could not change the login item setting:\n",
        "Không lưu được cài đặt:\n": "Could not save the settings:\n",
        "MiniSnap - lỗi": "MiniSnap - error",
        "Chú thích tiếng Việt": "Sample annotation",
        "Đã chuyển sang Tiếng Việt. Các cửa sổ đang mở sẽ đổi khi bạn mở lại.": "Language changed to English. Open windows switch when you reopen them.",

        // Permissions
        "Cần quyền Ghi màn hình": "Screen Recording permission needed",
        "MiniSnap cần quyền Ghi màn hình (Screen Recording) để chụp ảnh và quay video.\n\nMở Cài đặt hệ thống → Quyền riêng tư & Bảo mật → Ghi màn hình & âm thanh hệ thống, bật MiniSnap, rồi mở lại MiniSnap.":
            "MiniSnap needs Screen Recording permission to take screenshots and record videos.\n\nOpen System Settings → Privacy & Security → Screen & System Audio Recording, turn on MiniSnap, then relaunch MiniSnap.",
        "Cần quyền Trợ năng": "Accessibility permission needed",
        "Chụp cuộn cần quyền Trợ năng (Accessibility) để tự cuộn cửa sổ.\n\nMở Cài đặt hệ thống → Quyền riêng tư & Bảo mật → Trợ năng, bật MiniSnap, rồi thử lại.":
            "Scrolling capture needs Accessibility permission to scroll the window for you.\n\nOpen System Settings → Privacy & Security → Accessibility, turn on MiniSnap, then try again.",
        "Mở Cài đặt hệ thống": "Open System Settings",
        "Để sau": "Later",
        "Không chụp được màn hình:\n": "Could not capture the screen:\n",

        // Capture overlay mode bar
        "Chụp ảnh (Enter)": "Screenshot (Enter)",
        "Quay video (V)": "Record video (V)",
        "Chụp cuộn (S)": "Scrolling capture (S)",
        "Chọn lại (R)": "Reselect (R)",
        "Huỷ (Esc)": "Cancel (Esc)",
        "Rộng (px)": "Width (px)",
        "Cao (px)": "Height (px)",

        // Editor
        "Chọn": "Select",
        "Mũi tên": "Arrow",
        "Khung": "Box",
        "Elip": "Ellipse",
        "Đường": "Line",
        "Bút vẽ": "Pen",
        "Tô sáng": "Highlight",
        "Chữ": "Text",
        "Làm mờ": "Blur",
        "Đánh số": "Step",
        "Cắt ảnh": "Crop",
        "Trích chữ": "Extract text",
        "Thư viện": "Library",
        "Chụp mới": "New capture",
        "Sao chép": "Copy",
        "Lưu": "Save",
        "Lưu thành...": "Save as...",
        "✓ Đã chép": "✓ Copied",
        "✓ Đã lưu": "✓ Saved",
        "Chọn, kéo để di chuyển, Delete để xoá. Nháy đúp vào chữ để sửa": "Select, drag to move, Delete to remove. Double-click text to edit it",
        "Vẽ mũi tên (giữ Shift để thẳng góc 45°)": "Draw an arrow (hold Shift to snap to 45°)",
        "Vẽ khung chữ nhật (Shift: hình vuông)": "Draw a rectangle (Shift: square)",
        "Vẽ elip (Shift: hình tròn)": "Draw an ellipse (Shift: circle)",
        "Vẽ đường thẳng": "Draw a straight line",
        "Vẽ tự do": "Draw freehand",
        "Tô sáng một vùng (nên chọn màu vàng)": "Highlight an area (yellow works best)",
        "Bấm để gõ chữ. Enter để xong, Shift+Enter xuống dòng": "Click to type. Enter to finish, Shift+Enter for a new line",
        "Làm mờ thông tin nhạy cảm": "Blur sensitive information",
        "Bấm để đặt số bước 1, 2, 3...": "Click to place step numbers 1, 2, 3...",
        "Kéo chọn vùng muốn giữ lại": "Drag over the area to keep",
        "Nhận dạng chữ trong ảnh (OCR) và sao chép": "Recognize text in the image (OCR) and copy it",
        "Mở thư viện ảnh và video": "Open the image and video library",
        "Chụp ảnh mới": "Take a new capture",
        "Lưu thành file khác (⇧⌘S)": "Save to another file (⇧⌘S)",
        "Lưu ảnh (⌘S)": "Save image (⌘S)",
        "Sao chép ảnh vào clipboard để dán (⌘C)": "Copy the image to the clipboard to paste (⌘C)",
        "Màu:": "Color:",
        "Khác...": "More...",
        "Chọn màu khác": "Pick another color",
        "Độ dày:": "Size:",
        "Kích thước ô:": "Cell size:",
        "Kích thước ô mờ: càng lớn càng giống ô mosaic to": "Blur cell size: larger values look like big mosaic tiles",
        "Độ mờ:": "Softness:",
        "Độ mờ: 0 là ô vuông sắc nét, 10 là mờ mịn": "Softness: 0 gives crisp squares, 10 a smooth blur",
        "Hoàn tác": "Undo",
        "Làm lại": "Redo",
        "Mở thư mục ảnh đã chụp": "Open the captures folder",
        "Thu nhỏ": "Zoom out",
        "Phóng to": "Zoom in",
        "Vừa": "Fit",
        "Vừa cửa sổ": "Fit to window",
        "Kích thước thật": "Actual size",
        "Kéo để vẽ • Shift: giữ thẳng/vuông • ⌘+cuộn hoặc chụm 2 ngón: phóng to • Ảnh đã tự lưu và sao chép vào clipboard": "Drag to draw • Shift: straight/square • ⌘+scroll or pinch: zoom • Image auto-saved and copied to the clipboard",
        "Ảnh chưa lưu": "Unsaved image",
        "Vùng cắt: ": "Crop: ",
        " px — thả chuột để cắt, Esc để huỷ": " px — release to crop, Esc to cancel",
        "Gõ chữ • Enter: xong • Shift+Enter: xuống dòng • Esc: huỷ": "Type • Enter: done • Shift+Enter: new line • Esc: cancel",
        "Đã sao chép ảnh vào clipboard — dán (⌘V) vào Zalo, Word, email...": "Image copied — paste it (⌘V) into chat, Word, email...",
        "Không lưu được ảnh:\n": "Could not save the image:\n",
        "Đã lưu: ": "Saved: ",
        "Lưu các thay đổi vào ảnh?": "Save changes to the image?",
        "Nếu không lưu, các chỉnh sửa sẽ bị mất.": "Your edits will be lost if you don't save them.",
        "Không lưu": "Don't Save",
        "Huỷ": "Cancel",
        "Định dạng:": "Format:",

        // Library
        "Thư viện — MiniSnap": "Library — MiniSnap",
        "Tất cả": "All",
        "Ảnh": "Images",
        "Video": "Videos",
        "Tìm": "Search",
        "Làm mới": "Refresh",
        "Thư mục ảnh": "Images folder",
        "Thư mục video": "Videos folder",
        "Mở": "Open",
        "Trích chữ (OCR)": "Extract text (OCR)",
        "Hiện trong Finder": "Show in Finder",
        "Chuyển vào Thùng rác": "Move to Trash",
        "Chưa có ảnh hay video nào.\n": "No images or videos yet.\n",
        "Dùng menu trên thanh menu để chụp": "Use the menu bar icon to capture",
        "Nhấn ": "Press ",
        " để quay video.": " to record video.",
        "Hôm nay": "Today",
        "Hôm qua": "Yesterday",
        "7 ngày qua": "Last 7 days",
        "Tháng này": "This month",
        "Cũ hơn": "Older",
        " ảnh • ": " images • ",
        " video   —   ": " videos   —   ",
        "Đã sao chép ": "Copied ",
        " vào clipboard": " to the clipboard",
        " mục": " items",
        "Không sao chép được: ": "Could not copy: ",
        "Chuyển ": "Move ",
        " vào Thùng rác?": " to the Trash?",
        "Không xoá được ": "Could not delete ",

        // OCR
        "Trích chữ (OCR) — MiniSnap": "Extract text (OCR) — MiniSnap",
        "Đang nhận dạng chữ...": "Recognizing text...",
        "Đóng": "Close",
        "Sao chép chữ": "Copy text",
        "✓ Đã sao chép": "✓ Copied",
        "Không nhận dạng được chữ: ": "Could not recognize text: ",
        "(Không tìm thấy chữ nào trong ảnh)": "(No text found in the image)",
        "Ngôn ngữ: ": "Languages: ",
        "Đã tự sao chép vào clipboard.": "Copied to the clipboard automatically.",

        // Scrolling capture, recording
        "Đang chuẩn bị chụp cuộn...": "Preparing scrolling capture...",
        "Dừng (Esc)": "Stop (Esc)",
        "Đang chụp cuộn... ": "Scrolling capture... ",
        " lần, cao ": " shots, height ",
        "Bắt đầu sau 3...": "Starting in 3...",
        "Bắt đầu sau ": "Starting in ",
        "Tạm dừng": "Pause",
        "Tiếp tục": "Resume",
        "Dừng": "Stop",
        "Đang lưu video...": "Saving video...",

        // Keyboard shortcuts
        "(không dùng)": "(none)",
        "Nhấn tổ hợp phím...": "Press a key combination...",
        "Cần kèm ⌘, ⌥ hoặc ⌃": "Needs ⌘, ⌥ or ⌃",
        "Cài đặt phím tắt — MiniSnap": "Keyboard shortcuts — MiniSnap",
        "Bấm vào ô bên phải rồi nhấn tổ hợp phím mới, ví dụ ⌥⇧2 hoặc F9.\nDelete để bỏ phím tắt, Esc để giữ phím cũ. Phím tắt dùng được ở mọi nơi, kể cả khi đang ở app khác.":
            "Click a box on the right, then press the new key combination, e.g. ⌥⇧2 or F9.\nDelete removes a shortcut, Esc keeps the old one. Shortcuts work everywhere, even in other apps.",
        "Bỏ phím tắt này": "Remove this shortcut",
        "Khôi phục mặc định": "Restore defaults",
        "⚠ Trùng: ": "⚠ Same as: ",
        "Chỉ dùng từ menu": "Menu only",
        "Mỗi phím tắt chỉ được gán cho một chức năng.": "Each shortcut can only be used for one action.",
        "⚠ App khác đang dùng phím này": "⚠ Used by another app",
        "Đã lưu và áp dụng.": "Saved and applied.",
        "Đã lưu, nhưng ": "Saved, but ",
        " phím đang bị app khác chiếm — hãy chọn phím khác.": " shortcut(s) are taken by another app — please pick other keys.",

        // About
        "Giới thiệu — MiniSnap": "About — MiniSnap",
        "Phiên bản ": "Version ",
        "Đây là phần mềm chụp ảnh, quay phim màn hình miễn phí, mã nguồn mở dành cho mọi người.": "Free, open-source screenshot and screen recording software for everyone.",
        "Tác giả: ": "Author: ",
        "Giấy phép MIT": "MIT License",

        // Updates
        "Bạn đang dùng bản mới nhất": "You're up to date",
        "Chưa có bản phát hành nào trên GitHub": "No releases published yet",
        "Không kiểm tra được cập nhật": "Could not check for updates",
        "Hãy kiểm tra kết nối mạng rồi thử lại.\n\n": "Please check your internet connection and try again.\n\n",
        "Đã có MiniSnap ": "MiniSnap ",
        " (bạn đang dùng ": " is available (you have ",
        "Tải về": "Download",
        "Đang tải bản cập nhật...": "Downloading the update...",
        "Không tải được bản cập nhật": "Could not download the update",
        "Bản phát hành này không có file MiniSnap-macOS.zip. Mở trang phát hành?": "This release has no MiniSnap-macOS.zip file. Open the release page?",
        "Mở trang phát hành": "Open release page",
        "File tải về không khớp mã kiểm tra SHA-256 — đã huỷ để an toàn.": "The downloaded file does not match its SHA-256 checksum — cancelled for safety.",
        "Đã tải bản mới": "Update downloaded",
        "Finder đang hiện MiniSnap.app mới. Hãy thoát MiniSnap, rồi kéo app mới vào thư mục Applications (chọn Thay thế).": "Finder is showing the new MiniSnap.app. Quit MiniSnap, then drag the new app into your Applications folder (choose Replace).",
        "Bản mới đã được kiểm tra mã SHA-256. MiniSnap sẽ thoát, thay app trong thư mục ": "The new version's SHA-256 checksum has been verified. MiniSnap will quit, replace the app in ",
        " rồi tự mở lại.\n\nmacOS có thể hỏi lại quyền Ghi màn hình cho bản mới.": " and open again.\n\nmacOS may ask again for the Screen Recording permission for the new version.",
        "Cài đặt và khởi động lại": "Install and Relaunch",
        "Có bản MiniSnap mới": "A new MiniSnap version is available",
        "Chọn \"Kiểm tra cập nhật...\" trong menu để tải về.": "Choose \"Check for updates...\" in the menu to download it."
    ]
}
