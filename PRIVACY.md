# Privacy Policy

MiniSnap is free, open-source software. **It does not collect, store or send any personal data, telemetry or analytics.**

## Your captures stay on your computer

Screenshots, recordings, annotations and recognized text (OCR) are processed locally and saved only where you choose (by default `Pictures\MiniSnap` and `Videos\MiniSnap` on Windows, `~/Pictures/MiniSnap` and `~/Movies/MiniSnap` on macOS). Text recognition uses the OCR engine built into Windows or macOS and runs offline. Nothing is uploaded anywhere.

## The only network connections

MiniSnap connects to the internet only to look for updates, and only to GitHub:

| When | What is contacted | What is sent |
|---|---|---|
| Daily, a few seconds after start — **only if "Check for updates daily" is enabled** (on by default; can be turned off in the installer or the tray / menu-bar menu) | `https://api.github.com/repos/nnqbao/minisnap/releases/latest` | A standard HTTPS request with the user agent `MiniSnap/<version>`. As with any web request, GitHub sees your IP address. |
| When you click **Check for updates** | Same as above | Same as above |
| When you click **Download and install** | The installer file attached to the GitHub release (`github.com` / `objects.githubusercontent.com`) | A standard HTTPS download request. |
| When you click a link (GitHub page, e-mail address) | Opens in your own browser or mail app | — |

GitHub's handling of these requests is covered by the [GitHub General Privacy Statement](https://docs.github.com/site-policy/privacy-policies/github-general-privacy-statement).

## Settings

Settings (language, shortcuts, preferences) are stored locally: in `HKEY_CURRENT_USER\Software\MiniSnap` on Windows and in the app's user defaults on macOS.

## Uninstalling

Windows: *Settings → Apps → MiniSnap → Uninstall* (or *Control Panel → Programs and Features*). Your captures are kept. macOS: delete `MiniSnap.app`.

## Contact

Nguyễn Năng Quốc Bảo — nnqbao@gmail.com — https://github.com/nnqbao/minisnap/issues

---

### Tóm tắt tiếng Việt

MiniSnap **không thu thập, lưu trữ hay gửi bất kỳ dữ liệu cá nhân nào**, cũng không có thống kê sử dụng.

- Ảnh, video và chữ nhận dạng (OCR) được xử lý ngay trên máy bạn, chạy offline, và không tải lên đâu cả.
- App chỉ kết nối tới **GitHub** trong ba trường hợp:
  - tự kiểm tra cập nhật mỗi ngày một lần, nếu bật tuỳ chọn *"Tự kiểm tra cập nhật hằng ngày"* (bật sẵn; tắt được trong bộ cài hoặc ở menu khay);
  - khi bạn bấm *Kiểm tra cập nhật*;
  - khi bạn bấm *Tải và cài đặt*.
- Mỗi lần kết nối như vậy, GitHub chỉ thấy địa chỉ IP và phiên bản MiniSnap của bạn, như mọi lần truy cập web thông thường.
