# MiniSnap for Linux

MiniSnap is free, open-source (MIT) screenshot and screen recording software. This folder is the
Linux version: Python 3 + GTK 4 + libadwaita, with screen access through **xdg-desktop-portal**, so it
works on Wayland (the Ubuntu default), on X11 and inside Flatpak. It follows the Windows and macOS
versions: the same tools, strings, colours and Vietnamese / English interface.

> **Honest note:** this version was written without a Linux desktop at hand. It is exercised in CI on
> `ubuntu-24.04` under Xvfb by a headless self-test (`--selftest`, see below) that renders every window
> to PNG in both languages and both colour schemes, but the portal-driven parts (screenshot, window
> picking, screen recording, scrolling capture, global shortcuts) can only be verified on a real
> desktop. Bug reports are very welcome.

## Requirements

Ubuntu 24.04 or newer (GTK 4.14, libadwaita 1.5, Python 3.12, PyGObject 3.48, GStreamer 1.24,
PipeWire 1.0). Install the dependencies:

```sh
sudo apt install python3 python3-gi python3-gi-cairo python3-cairo \
    gir1.2-gtk-4.0 gir1.2-adw-1 gir1.2-gstreamer-1.0 \
    xdg-desktop-portal xdg-desktop-portal-gnome \
    gstreamer1.0-pipewire gstreamer1.0-plugins-base gstreamer1.0-plugins-good gstreamer1.0-plugins-ugly \
    tesseract-ocr tesseract-ocr-vie tesseract-ocr-eng
```

* `xdg-desktop-portal-gnome` is for GNOME; on KDE use `xdg-desktop-portal-kde`, on wlroots
  compositors (Sway, …) `xdg-desktop-portal-wlr`.
* `gstreamer1.0-plugins-ugly` provides the H.264 encoder (`x264enc`). Without it MiniSnap falls back to
  `openh264enc` (`gstreamer1.0-plugins-bad`) or to VP8 / WebM.
* Tesseract is only needed for text extraction (OCR); everything else works without it.

No `pip` packages are needed.

## Run from source

```sh
cd linux
python3 -m minisnap                      # the launcher window
python3 -m minisnap --capture region     # or use the wrapper script:
./bin/minisnap --capture region
```

Command-line options (a second invocation is passed to the running instance):

| Option | Action |
|---|---|
| *(none)* | show the launcher window |
| `--capture region` | drag a region (or click a screen) on a frozen screenshot |
| `--capture full` | capture the whole desktop |
| `--capture delayed` | region capture after 3 seconds |
| `--capture window` | let the desktop's screenshot UI pick a window |
| `--capture scroll` | scrolling capture: select an area, MiniSnap scrolls it and stitches one long image |
| `--record` | record the screen; run it again to stop |
| `--ocr` | select an area and extract its text |
| `--library` | the image & video library |
| `--about` | About MiniSnap |
| `--shortcuts` | the Keyboard shortcuts window |
| `--selftest DIR` | headless self-test, writes `DIR/log.txt` and PNGs |
| `IMAGE…` | open images in the editor |

Captures go to `~/Pictures/MiniSnap`, recordings to `~/Videos/MiniSnap` (your XDG user folders).
Settings are stored in `~/.config/minisnap/settings.json`.

## Keyboard shortcuts

### Global shortcuts portal (GNOME 48+, KDE Plasma 6)

Desktops that ship the **GlobalShortcuts portal** (`org.freedesktop.portal.GlobalShortcuts`: GNOME 48
and newer, KDE Plasma 6) let MiniSnap register real global shortcuts. On those desktops the launcher
menu has **Enable global shortcuts**, and the **Keyboard shortcuts…** window has a *Global shortcuts*
section with a **Register / Change keys…** button. MiniSnap asks for:

| Shortcut | Suggested keys |
|---|---|
| capture region / window | Ctrl+Alt+C |
| capture full screen | Ctrl+Alt+F |
| scrolling capture | Ctrl+Alt+S |
| record video (start / stop) | Ctrl+Alt+R |
| capture and extract text (OCR) | Ctrl+Alt+O |
| library | Ctrl+Alt+L |

The desktop shows its own dialog where you confirm or change the keys; the window then lists the keys
the system actually assigned. While global shortcuts are enabled MiniSnap keeps running in the
background (a notification says so the first time), and it binds them again whenever it starts. Turn
the menu item off, or choose **Exit MiniSnap**, to stop it. This works the same inside Flatpak.

### Custom shortcuts (Ubuntu 24.04 / GNOME 46 and other desktops)

Without the portal, set the shortcuts in the desktop's own settings. On GNOME:

1. *Settings → Keyboard → View and Customize Shortcuts → Custom Shortcuts*
2. Click **+**, give it a name and enter a command, for example:
   * `minisnap --capture region`
   * `minisnap --capture full`
   * `minisnap --capture scroll`
   * `minisnap --record`
   * `minisnap --ocr`
   * `minisnap --library`
3. Click *Set Shortcut…* and press the keys (e.g. Ctrl+Alt+C).

When running from source, use the full path of `linux/bin/minisnap` instead of `minisnap` (inside
Flatpak: `flatpak run io.github.nnqbao.MiniSnap`). The menu item **Keyboard shortcuts…** in the
launcher shows the exact commands with copy buttons. GNOME keeps the Print Screen key for its own
screenshot tool; remove it under *Screenshots* first if you want it for MiniSnap.

## Wayland notes

* Wayland does not let applications read the screen directly. MiniSnap asks the **screenshot portal**
  for a full-desktop image and shows it frozen for you to select from. The first time, your desktop may
  ask for permission.
* Applications can't see where other windows are, so hovering doesn't highlight windows. Use
  **Pick a window** in the launcher (or `--capture window`): the desktop's own screenshot UI lets you
  choose a window, and the result opens in the editor.
* Screen recording uses the **ScreenCast portal**: your desktop asks which screen to share each time.
  The selected region is cropped from that screen's stream.
* Apps can't keep a window on top or hide it from recordings on Wayland, so the small recording window
  (timer, Pause, Stop) is a normal window. Run `minisnap --record` again (e.g. from your shortcut) to stop.

## Scrolling capture

**Scrolling capture** (launcher button, the scroll button or the S key on the post-selection bar, or
`--capture scroll`): select the area that scrolls (a web page, a document, a chat), and MiniSnap
scrolls it down by itself, grabs a frame after each step and stitches the frames into one long image
(sticky headers and footers are kept once). It stops at the end of the page, at 30 000 px or 120
frames, or when you press **Stop** (or Esc while the small status window has the focus). The result is
saved to the library, copied to the clipboard and opened in the editor like any capture.

Wayland does not let applications send scroll events, so MiniSnap uses the **RemoteDesktop portal**
together with the ScreenCast portal (the same portal is used on X11 sessions):

* The first time, your desktop asks for permission to *share the screen* and *control the pointer*;
  pick the screen that contains the selected area. The permission is remembered (a restore token is
  kept in `settings.json`), so later captures start without the dialog. If the remembered permission
  stops working, MiniSnap forgets it and asks again.
* While it works, your desktop shows its usual "screen is being shared" indicator; the pointer is
  moved to the centre of the area.
* It needs `xdg-desktop-portal-gnome` or `xdg-desktop-portal-kde` (GNOME 40+, KDE Plasma 5.27+) and
  `gstreamer1.0-pipewire`. `xdg-desktop-portal-wlr` has no RemoteDesktop interface yet, so Sway and
  other wlroots compositors can't use scrolling capture; MiniSnap explains this instead of failing.
* Wayland doesn't let apps place windows, so the status window may open over the area being
  captured. Move it aside before the capture gets going if it covers the content.

## Updates and Flatpak

The .deb and source installs can check GitHub for new versions (**Check for updates…**, and the daily
check that can be switched off in the menu). Inside Flatpak both are hidden and no update check is ever
made: Flathub delivers the updates through your software centre or `flatpak update`.

## What is included

* region / full-screen / delayed capture with a magnifier, pixel size and colour readout, multi-monitor
* the post-selection bar (Screenshot / Record video / Scrolling capture, width × height, reselect,
  resize and move handles)
* window capture through the system picker
* scrolling capture through the RemoteDesktop + ScreenCast portals
* the annotation editor: arrow, box, ellipse, line, pen, highlight, text, blur, step numbers, crop,
  undo/redo, zoom, copy / save / save as; every capture auto-saved and copied to the clipboard
* screen recording to MP4 (portal + PipeWire + GStreamer), with countdown, pause and stop
* global shortcuts through the GlobalShortcuts portal with a background mode, or desktop custom
  shortcuts as the fallback
* OCR with Tesseract (Vietnamese + English), the library, update check (not in Flatpak), About,
  Vietnamese / English UI

## Self-test

```sh
cd linux
xvfb-run -a -s "-screen 0 1600x1000x24" python3 -m minisnap --selftest /tmp/minisnap-selftest
```

It never calls a portal. It renders all annotation types (`render.png`), runs the scrolling-capture
stitcher on a synthetic page with a sticky header and footer (`stitch.png`, height must match), drives
the scrolling-capture state machine over the same page with simulated scrolling (`scroll-session.png`),
checks the portal plumbing (selection → stream mapping, RemoteDesktop response parsing, the
GlobalShortcuts `BindShortcuts` arguments and the `Activated` dispatch) without D-Bus, runs Tesseract,
encodes a short test video with GStreamer, checks that every UI string has an English translation, and
saves PNGs of the launcher, editor, capture overlay with the mode bar, library, About, shortcuts
(with and without the GlobalShortcuts portal) and scrolling-capture status windows, e.g.
`editor-vi-dark.png`, `shortcuts-portal-en-light.png`, `scroll-status-vi-dark.png`. The exit code is
non-zero if any step failed; details are in `log.txt`.

## License

MIT — see [LICENSE](../LICENSE). Privacy: see [PRIVACY.md](../PRIVACY.md); MiniSnap collects no data.
