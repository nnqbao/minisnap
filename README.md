# MiniSnap

**Free, open-source screen capture for Windows, macOS and Linux** — screenshots, annotations, scrolling capture, screen recording and text extraction (OCR). Inspired by tools like Snagit, written from scratch, MIT-licensed.

**Phần mềm chụp màn hình miễn phí, nguồn mở cho Windows, macOS và Linux** — [đọc tiếng Việt bên dưới](#tiếng-việt).

![MiniSnap editor](docs/editor.png)

| Dark mode | After selecting an area |
|---|---|
| ![Dark mode](docs/editor-dark.png) | ![Mode bar](docs/mode-bar.png) |

| Linux (GTK4 / libadwaita) | |
|---|---|
| ![Linux launcher](docs/linux-launcher.png) | ![Linux editor](docs/linux-editor.png) |

## Features

| | Windows | macOS | Linux |
|---|---|---|---|
| Capture a region, a window or the full screen, with magnifier | ✅ | ✅ | ✅ (window via the system picker on Wayland) |
| All-in-one: after selecting an area, pick **screenshot, video or scrolling capture**; resize the area or type an exact size | ✅ | ✅ | ✅ |
| Annotate: arrow, box, ellipse, line, pen, highlight, text, blur / mosaic (adjustable cell size and softness), step numbers, crop, undo/redo | ✅ | ✅ | ✅ |
| Big one-click **Copy / Save / Save as** buttons; every capture is auto-saved and copied | ✅ | ✅ | ✅ |
| Scrolling capture of long pages (sticky headers/footers handled) | ✅ | ✅ | ✅ (RemoteDesktop portal; permission remembered) |
| Screen recording to MP4 (H.264) with pause/resume | ✅ | ✅ | ✅ (PipeWire) |
| Text extraction (OCR), offline | ✅ Windows OCR | ✅ Vision | ✅ Tesseract (Vietnamese included) |
| Library with thumbnails, grouped by date, search | ✅ | ✅ | ✅ |
| Global keyboard shortcuts | ✅ customizable | ✅ customizable | ✅ GlobalShortcuts portal (GNOME 48+, Plasma 6); guided custom shortcuts elsewhere |
| English and Vietnamese, switchable at any time | ✅ | ✅ | ✅ |
| Native modern look | Windows 11 (Mica, light/dark, Fluent icons) | Liquid Glass on macOS 26 | GNOME / libadwaita, light/dark |
| Check for updates from GitHub Releases | ✅ one-click install (SHA-256 verified) | ✅ install and relaunch (SHA-256 verified; app in a writable folder such as Applications) | ✅ one-click install for the .deb (SHA-256 verified, asks for your password); Terminal command for every install |

> **Status:** the macOS and Linux versions were written without a Mac or a Linux desktop at hand. Both are built by CI on every push, and the Linux version also runs a headless self-test that renders every window — but neither has been tested by hand yet. Bug reports are very welcome.

## Download

Get the latest build from **[Releases](https://github.com/nnqbao/minisnap/releases)**:

- **Windows 10/11:** `MiniSnap-Setup.exe` — per-user install, no admin rights. The installer is not code-signed yet, so SmartScreen may warn: click *More info → Run anyway*.
- **macOS 14+:** `MiniSnap-macOS.zip` — unzip, then right-click `MiniSnap.app` → *Open* the first time (the app is not notarized). Grant *Screen Recording* (and *Accessibility* for scrolling capture) when asked.
- **Ubuntu 24.04+ / Debian:** `minisnap_<version>_all.deb` — `sudo apt install ./minisnap_*_all.deb` (pulls in GTK4, libadwaita, GStreamer and Tesseract).
- **Any Linux distribution:** `MiniSnap.flatpak` — `flatpak install --user MiniSnap.flatpak` (needs the Flathub remote for the GNOME runtime). Screen access goes through the desktop portal, so the system asks for permission the first time. Getting MiniSnap onto Flathub: see [linux/flathub/README.md](linux/flathub/README.md).

See the [Code signing policy](#code-signing-policy) and the [Privacy policy](PRIVACY.md).

## Code signing policy

Free code signing provided by [SignPath.io](https://signpath.io), certificate by [SignPath Foundation](https://signpath.org).

- Windows binaries (`MiniSnap.exe`, `MiniSnap-Setup.exe`) are built from this repository by GitHub Actions ([build.yml](.github/workflows/build.yml)) and only releases built that way are signed. Releases published before signing was set up are unsigned.
- Team roles:
  - **Committers and reviewers:** [@nnqbao](https://github.com/nnqbao) (Nguyễn Năng Quốc Bảo)
  - **Approvers:** [@nnqbao](https://github.com/nnqbao) (Nguyễn Năng Quốc Bảo) — every release is approved manually before it is signed.
- Privacy: this program will not transfer any information to other networked systems unless specifically requested by the user or the person installing or operating it, except the optional daily update check described in the [Privacy policy](PRIVACY.md), which can be turned off.

## Default shortcuts

| Action | Windows | macOS | Linux (suggested) |
|---|---|---|---|
| Capture region / window | `PrtScn` (also `Ctrl+Shift+X`) | `⌥⇧2` | `Ctrl+Alt+C` |
| Capture full screen | `Ctrl+PrtScn` | `⌥⇧1` | `Ctrl+Alt+F` |
| Capture after 3 seconds | `Shift+PrtScn` | `⌥⇧3` | — |
| Scrolling capture | `Ctrl+Alt+S` | `⌥⇧S` | `Ctrl+Alt+S` |
| Record video (start/stop) | `Ctrl+Alt+R` | `⌥⇧R` | `Ctrl+Alt+R` |
| Capture & extract text | `Ctrl+Alt+O` | `⌥⇧O` | `Ctrl+Alt+O` |
| Library | `Ctrl+Alt+L` | `⌥⇧L` | `Ctrl+Alt+L` |

On Windows and macOS all shortcuts can be changed in **Keyboard shortcuts…** from the tray / menu-bar menu. On Linux, desktops with the GlobalShortcuts portal (GNOME 48+, KDE Plasma 6) register them in one click; elsewhere (for example Ubuntu 24.04 / GNOME 46) the same window explains how to add them as custom shortcuts (each runs a `minisnap --capture …` command, with copy buttons).

![Keyboard shortcuts](docs/shortcuts.png)

## Building from source

- **Windows** — no SDK needed; uses the C# compiler that ships with Windows (.NET Framework 4.8):
  ```powershell
  powershell -ExecutionPolicy Bypass -File windows\build.ps1
  ```
  Produces `windows\bin\MiniSnap.exe` and `windows\bin\MiniSnap-Setup.exe`. See [windows/README.md](windows/README.md).
- **macOS** — Xcode 15+ command-line tools:
  ```bash
  bash macos/build.sh
  ```
  Produces `macos/dist/MiniSnap.app` and `MiniSnap-macOS.zip`. See [macos/README.md](macos/README.md).
- **Linux** — Python 3 with GTK4/libadwaita; run from source or build the packages:
  ```bash
  cd linux && python3 -m minisnap        # run from the source tree
  bash linux/packaging/build-deb.sh      # → linux/dist/minisnap_<version>_all.deb
  flatpak-builder --user --install build-dir linux/packaging/io.github.kingrubic.MiniSnap.yml
  ```
  See [linux/README.md](linux/README.md) for the apt packages to install first.

GitHub Actions builds everything on every push (and runs the Linux self-test); pushing a tag like `v1.7.0` publishes a release with all downloads.

## Project layout

```
windows/   C# WinForms app + installer (src/, installer/, build.ps1)
macos/     Swift / AppKit app (Swift Package) + build.sh
linux/     Python / GTK4 + libadwaita app, .desktop/AppStream data, .deb and Flatpak packaging
docs/      screenshots for this README
```

## Contributing

Issues and pull requests are welcome — especially testing on macOS and Linux (Wayland and X11), new translations (`windows/src/Strings.cs`, `macos/Sources/MiniSnap/Strings.swift`, `linux/minisnap/i18n.py`), and bug fixes.

## Author

**Nguyễn Năng Quốc Bảo** — [nnqbao@gmail.com](mailto:nnqbao@gmail.com) · [github.com/nnqbao/minisnap](https://github.com/nnqbao/minisnap)

## License

[MIT](LICENSE) — free for personal and commercial use.

---

## Tiếng Việt

MiniSnap là phần mềm chụp màn hình **miễn phí, nguồn mở (giấy phép MIT)** cho Windows, macOS và Linux:

- Chụp vùng, cửa sổ hoặc toàn màn hình, có kính lúp.
- Chọn vùng xong sẽ hiện thanh nhỏ để chọn **chụp ảnh, quay video hay chụp cuộn**; kéo chỉnh vùng hoặc nhập kích thước chính xác.
- Chú thích: mũi tên, khung, elip, đường thẳng, bút vẽ, tô sáng, chữ, làm mờ / mosaic (chỉnh được kích thước ô và độ mờ), đánh số bước, cắt ảnh, hoàn tác / làm lại.
- Nút lớn **Sao chép / Lưu / Lưu thành…**; mọi ảnh chụp đều tự lưu và tự sao chép vào clipboard.
- Chụp cuộn trang dài, quay video màn hình ra MP4, trích chữ trong ảnh (OCR, chạy offline, đọc được tiếng Việt).
- Thư viện ảnh & video có ảnh thu nhỏ; phím tắt; giao diện tiếng Việt / tiếng Anh.

**Tải về:** vào mục [Releases](https://github.com/nnqbao/minisnap/releases).
- **Windows:** chạy `MiniSnap-Setup.exe`. Nếu SmartScreen cảnh báo, bấm *More info → Run anyway*.
- **macOS:** giải nén `MiniSnap-macOS.zip`, lần đầu bấm chuột phải vào `MiniSnap.app` → *Open*.
- **Ubuntu:** `sudo apt install ./minisnap_*_all.deb`.
- **Linux nói chung:** dùng file `MiniSnap.flatpak`.

**Đổi ngôn ngữ:**
- Windows: chuột phải vào biểu tượng ở khay hệ thống → *Ngôn ngữ / Language*.
- macOS: menu trên thanh menu.
- Linux: nút menu ☰ của cửa sổ MiniSnap.

**Phím tắt trên Linux:** mở menu ☰ → *Phím tắt bàn phím…*. Trên GNOME 48 trở lên hoặc KDE Plasma 6, bấm một nút là đăng ký xong phím tắt. Trên Ubuntu 24.04, cửa sổ này hướng dẫn gán phím trong Cài đặt.

**Cập nhật:** dùng *Kiểm tra cập nhật...* trong menu. App cũng tự kiểm tra mỗi ngày một lần và chỉ báo khi có bản mới.

**Tác giả:** Nguyễn Năng Quốc Bảo — nnqbao@gmail.com. Đây là phần mềm chụp ảnh, quay phim màn hình miễn phí, mã nguồn mở dành cho mọi người.

**Lưu ý:** bản macOS và Linux được viết khi không có sẵn máy Mac hay máy Linux để thử. GitHub Actions build được cả hai, và bản Linux còn tự chạy kiểm tra giao diện, nhưng chưa ai thử bằng tay. Rất mong mọi người báo lỗi.

Hướng dẫn chi tiết cho Windows (tiếng Việt): [windows/README.md](windows/README.md).
