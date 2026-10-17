using System;
using System.Collections.Generic;
using Microsoft.Win32;

namespace MiniSnap
{
    // UI language. Vietnamese text in the code is the key; English comes from the table below.
    // Text without an entry (symbols like "✕", or a missing translation) is shown unchanged.
    static class L
    {
        const string RegPath = @"Software\MiniSnap";

        public static bool English { get; private set; }

        public static string T(string vi)
        {
            string en;
            return English && En.TryGetValue(vi, out en) ? en : vi;
        }

        public static bool Has(string vi) { return En.ContainsKey(vi); }

        // MINISNAP_LANG=en|vi overrides the saved choice (used by --selftest).
        public static void Load()
        {
            string over = Environment.GetEnvironmentVariable("MINISNAP_LANG");
            if (!string.IsNullOrEmpty(over)) { English = over == "en"; return; }
            string saved = null;
            try
            {
                using (var k = Registry.CurrentUser.OpenSubKey(RegPath))
                    if (k != null) saved = k.GetValue("Language") as string;
            }
            catch (Exception) { }
            // Nothing saved yet: follow the Windows display language.
            English = saved != null ? saved == "en"
                : !System.Globalization.CultureInfo.CurrentUICulture.TwoLetterISOLanguageName.Equals("vi", StringComparison.OrdinalIgnoreCase);
        }

        public static void Set(bool english)
        {
            English = english;
            using (var k = Registry.CurrentUser.CreateSubKey(RegPath))
                k.SetValue("Language", english ? "en" : "vi");
        }

        static readonly Dictionary<string, string> En = new Dictionary<string, string>
        {
            // Tray menu, balloons
            { "Chụp vùng / cửa sổ", "Capture region / window" },
            { "Chụp vùng / cửa sổ (phím phụ)", "Capture region / window (2nd key)" },
            { "Chụp toàn màn hình", "Capture full screen" },
            { "Chụp vùng sau 3 giây", "Capture region after 3 seconds" },
            { "Chụp cuộn trang dài", "Scrolling capture" },
            { "Quay video màn hình", "Record screen video" },
            { "Dừng quay video", "Stop recording" },
            { "Quay video (bắt đầu / dừng)", "Record video (start / stop)" },
            { "Chụp và trích chữ (OCR)", "Capture and extract text (OCR)" },
            { "Thư viện ảnh && video", "Image && video library" },
            { "Mở thư viện ảnh & video", "Open image & video library" },
            { "Mở ảnh...", "Open image..." },
            { "Cài đặt phím tắt...", "Keyboard shortcuts..." },
            { "Khởi động cùng Windows", "Start with Windows" },
            { "Thoát MiniSnap", "Exit MiniSnap" },
            { "MiniSnap đã sẵn sàng", "MiniSnap is ready" },
            { "MiniSnap — nhấn ", "MiniSnap — press " },
            { " để chụp", " to capture" },
            { "chụp ảnh", "capture" },
            { "chụp cuộn", "scrolling capture" },
            { "trích chữ", "extract text" },
            { "Chưa gán phím tắt nào", "No shortcuts assigned" },
            { ". Chuột phải vào biểu tượng này để xem thêm hoặc đổi phím tắt.", ". Right-click this icon for more options or to change shortcuts." },
            { "\nKhông đăng ký được: ", "\nCould not register: " },
            { " (đang bị ứng dụng khác dùng) — vào Cài đặt phím tắt để đổi.", " (used by another app) — change it in Keyboard shortcuts." },
            { "Sẽ chụp sau ", "Capturing in " },
            { " giây...", " seconds..." },
            { "Chụp cuộn: chọn cửa sổ hoặc vùng có nội dung cần cuộn — app sẽ tự cuộn xuống", "Scrolling capture: pick the window or area to scroll — MiniSnap scrolls it for you" },
            { "Quay video: chọn cửa sổ hoặc kéo chọn vùng cần quay (Enter = toàn màn hình)", "Record video: pick a window or drag an area (Enter = full screen)" },
            { "Trích chữ: chọn vùng có chữ cần lấy", "Extract text: select the area containing the text" },
            { "Không quay được video:\n", "Could not record video:\n" },
            { "Đã lưu video", "Video saved" },
            { "\nBấm vào đây để xem.", "\nClick here to watch it." },
            { "Không mở được ảnh:\n", "Could not open the image:\n" },
            { "Ảnh|*.png;*.jpg;*.jpeg;*.bmp;*.gif|Tất cả|*.*", "Images|*.png;*.jpg;*.jpeg;*.bmp;*.gif|All files|*.*" },
            { "Không đổi được cài đặt khởi động:\n", "Could not change the startup setting:\n" },
            { "Không lưu được cài đặt:\n", "Could not save the settings:\n" },
            { "MiniSnap - lỗi", "MiniSnap - error" },
            { "Chú thích tiếng Việt", "Sample annotation" },

            // Editor
            { "Chọn", "Select" },
            { "Mũi tên", "Arrow" },
            { "Khung", "Box" },
            { "Elip", "Ellipse" },
            { "Đường", "Line" },
            { "Bút vẽ", "Pen" },
            { "Tô sáng", "Highlight" },
            { "Chữ", "Text" },
            { "Làm mờ", "Blur" },
            { "Đánh số", "Step" },
            { "Cắt ảnh", "Crop" },
            { "Trích chữ", "Extract text" },
            { "Thư viện", "Library" },
            { "Chụp mới", "New capture" },
            { "Sao chép", "Copy" },
            { "Lưu", "Save" },
            { "Lưu thành...", "Save as..." },
            { "✓ Đã chép", "✓ Copied" },
            { "✓ Đã lưu", "✓ Saved" },
            { "Chọn, kéo để di chuyển, Delete để xoá. Nháy đúp vào chữ để sửa", "Select, drag to move, Delete to remove. Double-click text to edit it" },
            { "Vẽ mũi tên (giữ Shift để thẳng góc 45°)", "Draw an arrow (hold Shift to snap to 45°)" },
            { "Vẽ khung chữ nhật (Shift: hình vuông)", "Draw a rectangle (Shift: square)" },
            { "Vẽ elip (Shift: hình tròn)", "Draw an ellipse (Shift: circle)" },
            { "Vẽ đường thẳng", "Draw a straight line" },
            { "Vẽ tự do", "Draw freehand" },
            { "Tô sáng một vùng (nên chọn màu vàng)", "Highlight an area (yellow works best)" },
            { "Bấm để gõ chữ. Enter để xong, Shift+Enter xuống dòng", "Click to type. Enter to finish, Shift+Enter for a new line" },
            { "Làm mờ thông tin nhạy cảm", "Blur sensitive information" },
            { "Bấm để đặt số bước 1, 2, 3...", "Click to place step numbers 1, 2, 3..." },
            { "Kéo chọn vùng muốn giữ lại", "Drag over the area to keep" },
            { "Nhận dạng chữ trong ảnh (OCR) và sao chép", "Recognize text in the image (OCR) and copy it" },
            { "Mở thư viện ảnh và video", "Open the image and video library" },
            { "Chụp ảnh mới", "Take a new capture" },
            { "Lưu thành file khác (Ctrl+Shift+S)", "Save to another file (Ctrl+Shift+S)" },
            { "Lưu ảnh (Ctrl+S)", "Save image (Ctrl+S)" },
            { "Sao chép ảnh vào clipboard để dán (Ctrl+C)", "Copy the image to the clipboard to paste (Ctrl+C)" },
            { "Màu:", "Color:" },
            { "Khác...", "More..." },
            { "Chọn màu khác", "Pick another color" },
            { "Độ dày:", "Size:" },
            { "Kích thước ô:", "Cell size:" },
            { "Kích thước ô mờ: càng lớn càng giống ô mosaic to", "Blur cell size: larger values look like big mosaic tiles" },
            { "Độ mờ:", "Softness:" },
            { "Độ mờ: 0 là ô vuông sắc nét, 10 là mờ mịn", "Softness: 0 gives crisp squares, 10 a smooth blur" },
            { "Hoàn tác", "Undo" },
            { "Làm lại", "Redo" },
            { "Mở thư mục ảnh đã chụp", "Open the captures folder" },
            { "Thu nhỏ", "Zoom out" },
            { "Phóng to", "Zoom in" },
            { "Vừa", "Fit" },
            { "Vừa cửa sổ", "Fit to window" },
            { "Kích thước thật", "Actual size" },
            { "Kéo để vẽ • Shift: giữ thẳng/vuông • Ctrl+lăn chuột: phóng to • Ảnh đã tự lưu và sao chép vào clipboard", "Drag to draw • Shift: straight/square • Ctrl+wheel: zoom • Image auto-saved and copied to clipboard" },
            { "Ảnh chưa lưu", "Unsaved image" },
            { "Vùng cắt: ", "Crop: " },
            { " px — thả chuột để cắt, Esc để huỷ", " px — release to crop, Esc to cancel" },
            { "Gõ chữ • Enter: xong • Shift+Enter: xuống dòng • Esc: huỷ", "Type • Enter: done • Shift+Enter: new line • Esc: cancel" },
            { "Đã sao chép ảnh vào clipboard — dán (Ctrl+V) vào Zalo, Word, email...", "Image copied — paste it (Ctrl+V) into chat, Word, email..." },
            { "Clipboard đang bận, hãy thử lại.", "The clipboard is busy, please try again." },
            { "Không lưu được ảnh:\n", "Could not save the image:\n" },
            { "Đã lưu: ", "Saved: " },
            { "Lưu các thay đổi vào ảnh?", "Save changes to the image?" },

            // Library
            { "Thư viện — MiniSnap", "Library — MiniSnap" },
            { "Tất cả", "All" },
            { "Ảnh", "Images" },
            { "Video", "Videos" },
            { "Tìm:", "Search:" },
            { "Làm mới", "Refresh" },
            { "Thư mục ảnh", "Images folder" },
            { "Thư mục video", "Videos folder" },
            { "Mở", "Open" },
            { "Trích chữ (OCR)", "Extract text (OCR)" },
            { "Hiện trong thư mục", "Show in folder" },
            { "Xoá (vào Thùng rác)", "Delete (to Recycle Bin)" },
            { "Chưa có ảnh hay video nào.\n", "No images or videos yet.\n" },
            { "Dùng menu ở khay hệ thống để chụp", "Use the tray menu to capture" },
            { "Nhấn ", "Press " },
            { " để quay video.", " to record video." },
            { "Hôm nay", "Today" },
            { "Hôm qua", "Yesterday" },
            { "7 ngày qua", "Last 7 days" },
            { "Tháng này", "This month" },
            { "Cũ hơn", "Older" },
            { " ảnh • ", " images • " },
            { " video   —   ", " videos   —   " },
            { "Đã sao chép ", "Copied " },
            { " vào clipboard", " to the clipboard" },
            { " mục", " items" },
            { "Không sao chép được: ", "Could not copy: " },
            { "Chuyển ", "Move " },
            { " vào Thùng rác?", " to the Recycle Bin?" },
            { "Không xoá được ", "Could not delete " },

            // OCR
            { "Trích chữ (OCR) — MiniSnap", "Extract text (OCR) — MiniSnap" },
            { "Đang nhận dạng chữ...", "Recognizing text..." },
            { "Đóng", "Close" },
            { "Sao chép chữ", "Copy text" },
            { "✓ Đã sao chép", "✓ Copied" },
            { "Không nhận dạng được chữ: ", "Could not recognize text: " },
            { "(Không tìm thấy chữ nào trong ảnh)", "(No text found in the image)" },
            { "Ngôn ngữ: ", "Language: " },
            { "\nMuốn đọc tiếng Việt có dấu: Settings → Time & language → Language & region → Add a language → Tiếng Việt.", "\nFor other languages: Settings → Time & language → Language & region → Add a language." },
            { "OCR thất bại: ", "OCR failed: " },
            { "Windows chưa cài gói nhận dạng chữ (OCR) cho ngôn ngữ nào.", "Windows has no text recognition (OCR) language installed." },

            // Scrolling capture, recording
            { "Đang chuẩn bị chụp cuộn...", "Preparing scrolling capture..." },
            { "Dừng (Esc)", "Stop (Esc)" },
            { "Đang chụp cuộn... ", "Scrolling capture... " },
            { " lần, cao ", " shots, height " },
            { "Bắt đầu sau 3...", "Starting in 3..." },
            { "Bắt đầu sau ", "Starting in " },
            { "Tạm dừng", "Pause" },
            { "Tiếp tục", "Resume" },
            { "Dừng", "Stop" },
            { "Đang lưu video...", "Saving video..." },

            // Keyboard shortcuts
            { "(không dùng)", "(none)" },
            { "Nhấn tổ hợp phím...", "Press a key combination..." },
            { "Cần kèm Ctrl, Alt hoặc Shift", "Needs Ctrl, Alt or Shift" },
            { "Shift + phím chữ sẽ chặn gõ chữ hoa", "Shift + a letter would block typing capitals" },
            { "Cài đặt phím tắt — MiniSnap", "Keyboard shortcuts — MiniSnap" },
            { "Bấm vào ô bên phải rồi nhấn tổ hợp phím mới, ví dụ Ctrl + Shift + 1 hoặc F9.\nBackspace để bỏ phím tắt, Esc để giữ phím cũ. Phím tắt dùng được ở mọi nơi, kể cả khi đang ở app khác.", "Click a box on the right, then press the new key combination, e.g. Ctrl + Shift + 1 or F9.\nBackspace removes a shortcut, Esc keeps the old one. Shortcuts work everywhere, even in other apps." },
            { "Bỏ phím tắt này", "Remove this shortcut" },
            { "Khôi phục mặc định", "Restore defaults" },
            { "⚠ Trùng: ", "⚠ Same as: " },
            { "Chỉ dùng từ menu", "Menu only" },
            { "Mỗi phím tắt chỉ được gán cho một chức năng.", "Each shortcut can only be used for one action." },
            { "⚠ App khác đang dùng phím này", "⚠ Used by another app" },
            { "Đã lưu và áp dụng.", "Saved and applied." },
            { "Đã lưu, nhưng ", "Saved, but " },
            { " phím đang bị app khác chiếm — hãy chọn phím khác.", " shortcut(s) are taken by another app — please pick other keys." },

            // About
            { "Giới thiệu MiniSnap...", "About MiniSnap..." },
            { "Giới thiệu MiniSnap", "About MiniSnap" },
            { "Đây là phần mềm chụp ảnh, quay phim màn hình miễn phí, mã nguồn mở dành cho mọi người.", "Free, open-source screenshot and screen recording software for everyone." },
            { "Tác giả: ", "Author: " },
            { "Liên hệ: ", "Contact: " },
            { "Mã nguồn: ", "Source code: " },
            { "Giấy phép MIT — miễn phí, mã nguồn mở", "MIT License — free and open source" },
            { "Mở trang GitHub", "Open on GitHub" },

            // Updates
            { "Kiểm tra cập nhật...", "Check for updates..." },
            { "Kiểm tra cập nhật", "Check for updates" },
            { "Cập nhật MiniSnap", "Update MiniSnap" },
            { "Đang kiểm tra cập nhật...", "Checking for updates..." },
            { "Phiên bản hiện tại: ", "Current version: " },
            { "Không kiểm tra được cập nhật", "Couldn't check for updates" },
            { "\nHãy kiểm tra kết nối mạng rồi thử lại.", "\nCheck your internet connection and try again." },
            { "Bạn đang dùng bản mới nhất", "You're up to date" },
            { "Chưa có bản phát hành nào trên GitHub. Phiên bản hiện tại: ", "No release has been published on GitHub yet. Current version: " },
            { " — mới nhất trên GitHub: ", " — latest on GitHub: " },
            { "Có phiên bản mới: ", "New version available: " },
            { "Bạn đang dùng ", "You have " },
            { ". Ảnh, video và cài đặt của bạn được giữ nguyên khi cập nhật.", ". Your captures and settings are kept when updating." },
            { "\nBản này chưa có bộ cài cho Windows — hãy xem trên GitHub.", "\nThis release has no Windows installer — see it on GitHub." },
            { "Tải và cài đặt", "Download and install" },
            { "Xem trên GitHub", "View on GitHub" },
            { "Để sau", "Later" },
            { "Đang tải bản cập nhật...", "Downloading the update..." },
            { "Tải về thất bại: ", "Download failed: " },
            { "Đã tải xong. MiniSnap sẽ đóng lại để cài bản mới rồi tự mở lại.", "Downloaded. MiniSnap will close, install the new version and reopen." },
            { "Bản phát hành này không có file MiniSnap-Setup.exe.", "This release has no MiniSnap-Setup.exe file." },
            { "Đường dẫn tải về không phải của GitHub: ", "The download link is not on GitHub: " },
            { "File tải về bị sai mã kiểm tra (SHA-256). Đã huỷ cập nhật.", "The downloaded file failed the SHA-256 check. The update was cancelled." },
            { "Không chạy được bộ cài:\n", "Could not start the installer:\n" },
            { "Có bản MiniSnap mới: ", "New MiniSnap version: " },
            { "Bấm vào đây để xem và cập nhật.", "Click here to see what's new and update." },
            { "Đã cập nhật MiniSnap", "MiniSnap updated" },
            { "Bạn đang dùng phiên bản ", "You're now on version " },
            { "Cập nhật không thành công:\n", "The update failed:\n" },

            { "Tự kiểm tra cập nhật hằng ngày", "Check for updates daily" },
            { "Tự kiểm tra bản mới mỗi ngày (chỉ gửi một yêu cầu tới api.github.com — xem PRIVACY.md)", "Check for new versions daily (sends only one request to api.github.com — see PRIVACY.md)" },
            { "Quyền riêng tư: ", "Privacy: " },
            { "MiniSnap không thu thập dữ liệu", "MiniSnap collects no data" },

            // Post-selection mode bar
            { "Chụp ảnh (Enter)", "Screenshot (Enter)" },
            { "Quay video (V)", "Record video (V)" },
            { "Chụp cuộn (S)", "Scrolling capture (S)" },
            { "Chọn lại (R)", "Reselect (R)" },
            { "Huỷ (Esc)", "Cancel (Esc)" },
            { "Rộng (px) — nhập rồi nhấn Enter", "Width (px) — type and press Enter" },
            { "Cao (px) — nhập rồi nhấn Enter", "Height (px) — type and press Enter" },
            { "Hỏi chụp ảnh / quay video / chụp cuộn sau khi chọn vùng", "Ask screenshot / video / scroll after selecting" },

            // Installer / uninstaller
            { "Cài đặt MiniSnap ", "MiniSnap Setup " },
            { "Cài đặt MiniSnap", "MiniSnap Setup" },
            { "Gỡ cài đặt MiniSnap", "Uninstall MiniSnap" },
            { "Chào mừng đến với MiniSnap", "Welcome to MiniSnap" },
            { "Tuỳ chọn cài đặt", "Setup options" },
            { "Đang cài đặt", "Installing" },
            { "Đã cài xong", "All done" },
            { "Phiên bản ", "Version " },
            { " • Chụp ảnh, quay video màn hình, trích chữ", " • Screenshots, screen recording, text extraction" },
            { "Chọn nơi cài và các tuỳ chọn", "Choose where to install and a few options" },
            { "Vui lòng đợi trong giây lát...", "This only takes a moment..." },
            { "Sẵn sàng sử dụng", "Ready to use" },
            { "Tiếp tục >", "Next >" },
            { "< Quay lại", "< Back" },
            { "Huỷ", "Cancel" },
            { "Cài đặt", "Install" },
            { "Hoàn tất", "Finish" },
            { "Hoàn tất.", "Done." },
            { "Chọn...", "Browse..." },
            { "MiniSnap giúp bạn chụp và chia sẻ màn hình thật nhanh:", "MiniSnap helps you capture and share your screen fast:" },
            { "Chụp vùng, cửa sổ, toàn màn hình — phím PrtScn", "Capture a region, window or full screen — PrtScn key" },
            { "Chụp cuộn trang web dài — Ctrl+Alt+S", "Scrolling capture of long pages — Ctrl+Alt+S" },
            { "Quay video màn hình ra MP4 — Ctrl+Alt+R", "Record your screen to MP4 — Ctrl+Alt+R" },
            { "Trích chữ trong ảnh (OCR) — Ctrl+Alt+O", "Extract text from images (OCR) — Ctrl+Alt+O" },
            { "Chú thích: mũi tên, khung, chữ, làm mờ, đánh số", "Annotate: arrows, boxes, text, blur, step numbers" },
            { "Thư viện ảnh & video có ảnh thu nhỏ — Ctrl+Alt+L", "Image & video library with thumbnails — Ctrl+Alt+L" },
            { "Tự đặt phím tắt theo ý muốn (menu khay → Cài đặt phím tắt)", "Custom shortcuts (tray menu → Keyboard shortcuts)" },
            { "Máy đã có MiniSnap ", "MiniSnap " },
            { " — bản này sẽ cập nhật đè lên, giữ nguyên ảnh đã chụp và phím tắt.", " is already installed — it will be updated, keeping your captures and shortcuts." },
            { "Thư mục cài đặt:", "Install folder:" },
            { "Chọn thư mục cài MiniSnap", "Choose where to install MiniSnap" },
            { "Cài cho riêng tài khoản của bạn, không cần quyền quản trị.", "Installs for your account only; no administrator rights needed." },
            { "Tạo lối tắt ngoài màn hình Desktop", "Create a desktop shortcut" },
            { "Tự chạy MiniSnap khi khởi động Windows (để luôn bấm được PrtScn)", "Start MiniSnap with Windows (so PrtScn always works)" },
            { "Lối tắt trong Start menu luôn được tạo. Gỡ cài đặt trong Settings → Apps.", "A Start menu shortcut is always created. Uninstall from Settings → Apps." },
            { "Đang cài đặt...", "Installing..." },
            { "Đang tạo thư mục cài đặt...", "Creating the install folder..." },
            { "Đang chép MiniSnap.exe...", "Copying MiniSnap.exe..." },
            { "Đang chuẩn bị trình gỡ cài đặt...", "Preparing the uninstaller..." },
            { "Đang tạo lối tắt...", "Creating shortcuts..." },
            { "Đang đăng ký với Windows...", "Registering with Windows..." },
            { "MiniSnap đã được cài đặt thành công!", "MiniSnap was installed successfully!" },
            { "MiniSnap chạy ở khay hệ thống (góc phải thanh taskbar).\nNhấn PrtScn bất cứ lúc nào để chụp màn hình.", "MiniSnap lives in the system tray (right end of the taskbar).\nPress PrtScn any time to take a screenshot." },
            { "Mẹo: trên Windows 11, nếu PrtScn mở Snipping Tool, hãy vào Settings → Accessibility → Keyboard và tắt \"Use the Print screen key to open screen capture\".", "Tip: on Windows 11, if PrtScn opens the Snipping Tool, go to Settings → Accessibility → Keyboard and turn off \"Use the Print screen key to open screen capture\"." },
            { "Mở MiniSnap ngay", "Launch MiniSnap now" },
            { "Chụp ảnh, quay video màn hình và trích chữ", "Screenshots, screen recording and text extraction" },
            { "MiniSnap đang chạy và cần được đóng để tiếp tục.\nẢnh đang chỉnh sửa mà chưa lưu sẽ bị mất. Đóng MiniSnap?", "MiniSnap is running and must be closed to continue.\nUnsaved edits will be lost. Close MiniSnap?" },
            { "Đường dẫn thư mục không hợp lệ.", "That folder path is not valid." },
            { "Cài đặt không thành công:\n", "Setup failed:\n" },
            { "Thoát trình cài đặt?", "Exit setup?" },
            { "Gỡ cài đặt MiniSnap khỏi máy tính?\n\nẢnh và video bạn đã chụp vẫn được giữ lại trong Pictures\\MiniSnap và Videos\\MiniSnap.", "Uninstall MiniSnap from this computer?\n\nYour captures stay in Pictures\\MiniSnap and Videos\\MiniSnap." },
            { "Đã gỡ cài đặt MiniSnap.", "MiniSnap has been uninstalled." },
        };
    }
}
