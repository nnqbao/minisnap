# MiniSnap

App chụp màn hình kiểu Snagit cho Windows 10/11, viết lại từ đầu bằng C# WinForms. App không cần cài .NET hay thư viện nào thêm.

## Cài đặt

Tải `MiniSnap-Setup.exe` ở mục [Releases](https://github.com/nnqbao/minisnap/releases) (hoặc tự build, file nằm ở `windows\bin\`) rồi chạy và bấm Tiếp tục → Cài đặt → Hoàn tất. Bộ cài:
- cài cho riêng tài khoản của bạn vào `%LocalAppData%\Programs\MiniSnap`, không cần quyền quản trị;
- tạo lối tắt trong Start menu, và tuỳ chọn tạo thêm ngoài Desktop;
- tuỳ chọn tự chạy cùng Windows;
- hiện trong **Settings → Apps** để gỡ cài đặt như mọi app khác. Khi gỡ, ảnh và video đã chụp vẫn được giữ lại.

> Bộ cài chưa được ký số, nên lần đầu chạy Windows SmartScreen có thể cảnh báo. Bấm **More info → Run anyway**.

## Phím tắt

Muốn đổi phím tắt, bấm chuột phải vào biểu tượng MiniSnap ở khay hệ thống → **Cài đặt phím tắt...**. Trong cửa sổ này:
- bấm vào ô của chức năng rồi nhấn tổ hợp phím mới, ví dụ `Ctrl + Shift + 1` hoặc `F9`;
- `Backspace` để bỏ phím tắt (chức năng vẫn dùng được từ menu), `Esc` để giữ phím cũ;
- phím chữ hoặc số phải kèm Ctrl hoặc Alt; riêng `PrtScn`, `F1`–`F24`, `Pause` và `ScrollLock` dùng một mình được;
- app báo ngay khi hai chức năng trùng phím, hoặc khi phím đang bị một app khác chiếm;
- có nút **Khôi phục mặc định**.

Cài đặt được lưu trong registry tại `HKCU\Software\MiniSnap\Hotkeys` và được giữ nguyên khi cập nhật bản mới.

Phím mặc định:

| Phím | Tác dụng |
|---|---|
| `PrtScn` hoặc `Ctrl+Shift+X` | Chụp vùng / cửa sổ |
| `Ctrl+PrtScn` | Chụp toàn màn hình |
| `Shift+PrtScn` | Chụp sau 3 giây |
| `Ctrl+Alt+S` | Chụp cuộn trang dài: chọn cửa sổ hoặc vùng, app tự cuộn và ghép ảnh. Nhấn Esc để dừng sớm |
| `Ctrl+Alt+R` | Quay video MP4: chọn vùng, đếm ngược 3 giây; nhấn lại để dừng |
| `Ctrl+Alt+O` | Chụp và trích chữ (OCR): chữ được tự sao chép vào clipboard |
| `Ctrl+Alt+L` | Mở thư viện ảnh và video |

> Windows 11: nếu bấm PrtScn mà Snipping Tool mở ra, hãy vào Settings → Accessibility → Keyboard và tắt "Use the Print screen key to open screen capture".

## Tính năng

- **Chụp ảnh**: rê chuột vào cửa sổ rồi bấm để chụp cả cửa sổ, hoặc kéo để chụp vùng. Có kính lúp hiện toạ độ và mã màu. Ảnh tự lưu vào `Pictures\MiniSnap` và tự sao chép vào clipboard.
- **Thanh chọn chế độ** (giống "All-in-One" của Snagit): chọn vùng xong, một thanh nhỏ hiện ra để chọn
  - 📷 chụp ảnh (`Enter`), 🎥 quay video (`V`) hoặc ⬇ chụp cuộn (`S`);
  - nhập Rộng × Cao chính xác, kéo cạnh hoặc góc để chỉnh vùng, kéo bên trong để di chuyển;
  - ↺ chọn lại (`R`), ✕ huỷ (`Esc`).

  Tắt hoặc bật thanh này ở menu khay → *Hỏi chụp ảnh / quay video / chụp cuộn sau khi chọn vùng*.
- **Trình chỉnh sửa**:
  - Công cụ: mũi tên, khung, elip, đường thẳng, bút vẽ, tô sáng, chữ, làm mờ, đánh số bước, cắt ảnh.
  - Có hoàn tác / làm lại, phóng to, lưu ra PNG, JPG, BMP hoặc GIF.
  - Nút **Trích chữ** để lấy chữ trong ảnh đang mở.
- **Chụp cuộn**: tự nhận ra header và footer dính (sticky) nên không bị lặp. Ảnh ghép cao tối đa 30.000 px.
- **Quay video**:
  - MP4 H.264, 30 khung hình/giây, có hiện con trỏ chuột, có tạm dừng / tiếp tục.
  - Lưu vào `Videos\MiniSnap`.
  - Thanh điều khiển và viền đỏ quanh vùng quay không bị lọt vào video.
  - Chưa ghi âm thanh.
- **OCR**: dùng bộ nhận dạng chữ có sẵn trong Windows, chạy offline. Muốn đọc **tiếng Việt có dấu**, bạn cần thêm gói ngôn ngữ: Settings → Time & language → Language & region → Add a language → Tiếng Việt.
- **Thư viện**:
  - Ảnh thu nhỏ của mọi ảnh và video, chia nhóm theo ngày; có lọc Ảnh / Video và ô tìm kiếm.
  - Nháy đúp để mở. Chuột phải để trích chữ, sao chép, hiện trong thư mục hoặc xoá (vào Thùng rác).
  - Kéo thả file sang ứng dụng khác được.

## Giao diện, cập nhật, giới thiệu

- **Giao diện Windows 11:**
  - tự theo chế độ sáng/tối và màu nhấn của Windows, thanh tiêu đề Mica;
  - icon Segoe Fluent, chữ Segoe UI Variable;
  - thanh công cụ phẳng, nút bo tròn.
- **Kiểm tra cập nhật:** menu khay → *Kiểm tra cập nhật...*, hoặc nút trong cửa sổ Giới thiệu.
  - App đọc bản mới nhất trên GitHub Releases, tải `MiniSnap-Setup.exe`, đối chiếu mã SHA-256 do GitHub công bố, rồi cài đè và tự mở lại.
  - Ảnh, video và cài đặt của bạn được giữ nguyên.
  - App cũng tự kiểm tra tối đa mỗi ngày một lần và chỉ hiện thông báo khi có bản mới.
- **Giới thiệu:** menu khay → *Giới thiệu MiniSnap...*, gồm tác giả, email liên hệ và link GitHub.

## Build từ mã nguồn

```powershell
powershell -ExecutionPolicy Bypass -File build.ps1
```

Lệnh này tạo ra `bin\MiniSnap.exe` và `bin\MiniSnap-Setup.exe`, dùng trình biên dịch C# có sẵn trong Windows.

| File | Nội dung |
|---|---|
| `src/Program.cs` | Khay hệ thống, phím tắt, điều phối các chế độ chụp, `--selftest` |
| `src/CaptureOverlay.cs` | Màn hình chọn vùng và kính lúp |
| `src/EditorForm.cs`, `src/Shapes.cs` | Trình chỉnh sửa và các công cụ chú thích |
| `src/ScrollCapture.cs` | Tự cuộn và ghép ảnh |
| `src/Recorder.cs` | Quay video qua Media Foundation |
| `src/Ocr.cs` | Nhận dạng chữ (Windows.Media.Ocr) |
| `src/LibraryForm.cs` | Thư viện ảnh và video |
| `src/Hotkeys.cs` | Lưu phím tắt và cửa sổ Cài đặt phím tắt |
| `src/Theme.cs` | Giao diện Windows 11 (sáng/tối, Mica, Fluent) |
| `src/Updater.cs` | Kiểm tra và cài bản cập nhật từ GitHub |
| `src/About.cs` | Cửa sổ Giới thiệu |
| `src/Strings.cs` | Bảng dịch Việt → Anh |
| `installer/Setup.cs` | Bộ cài đặt / gỡ cài đặt |

Chạy `MiniSnap.exe --selftest <thư mục>` để kiểm tra phần vẽ, ghép ảnh cuộn, OCR và quay video. Lệnh này xuất ảnh mẫu và file `log.txt`.
