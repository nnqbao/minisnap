"""Checks GitHub Releases of nnqbao/minisnap for a newer version (port of windows/src/Updater.cs).

How MiniSnap updates depends on how it was installed (install_kind):
- deb: "Update now" downloads the release's .deb, checks it against the SHA-256 digest GitHub publishes
  for the asset and the package's name and version, then installs it with `pkexec apt-get install`
  (the system asks for the password) and offers to restart MiniSnap.
- flatpak, git: the window shows the Terminal command that updates it, with a Copy button (a Flatpak
  app cannot install on the host).
The deb kind gets the same command too, as an alternative. The daily silent check only runs when
"Check for updates daily" is on.
"""

import configparser
import datetime
import hashlib
import json
import os
import re
import shlex
import shutil
import subprocess
import threading
import urllib.error
import urllib.request

from . import _gi  # noqa: F401
from gi.repository import Adw, Gio, GLib, Gtk, Pango

from . import REPO, VERSION, paths, settings
from .i18n import L

API = "https://api.github.com/repos/nnqbao/minisnap/releases/latest"
DEB_LOCATION = "/usr/share/minisnap/minisnap"


class Release:
    def __init__(self, tag=None, name=None, notes=None, page_url=None, assets=None):
        self.tag = tag
        self.name = name
        self.notes = notes
        self.page_url = page_url
        self.assets = assets or []      # [{"name", "url", "digest", "size"}]
        self.version = parse_version(tag)


def parse_version(tag):
    """'v1.5.1' / '1.5' / '1.6.0-beta' -> (major, minor, patch); None when unparsable."""
    t = (tag or "").strip().lstrip("vV")
    for sep in "-+ ":
        t = t.split(sep, 1)[0]
    parts = t.split(".")
    try:
        nums = [int(p) for p in parts if p != ""]
    except ValueError:
        return None
    if not nums or len(nums) > 4:
        return None
    while len(nums) < 3:
        nums.append(0)
    return tuple(nums[:3])


CURRENT = parse_version(VERSION)


def version_text(v):
    return ".".join(str(x) for x in v) if v else "?"


def is_newer(release, current=None):
    current = current or CURRENT
    return release is not None and release.version is not None and release.version > current


def release_from_json(data):
    assets = []
    for a in data.get("assets") or []:
        if a.get("name") and a.get("browser_download_url"):
            assets.append({"name": a["name"], "url": a["browser_download_url"],
                           "digest": a.get("digest") or "", "size": int(a.get("size") or 0)})
    return Release(tag=data.get("tag_name"), name=data.get("name"), notes=data.get("body"),
                   page_url=data.get("html_url") or REPO + "/releases", assets=assets)


def fetch(timeout=15):
    """The latest published release, or None when the repository has no release yet (404)."""
    req = urllib.request.Request(API, headers={
        "User-Agent": "MiniSnap/" + VERSION,
        "Accept": "application/vnd.github+json",
    })
    try:
        with urllib.request.urlopen(req, timeout=timeout) as resp:
            data = json.loads(resp.read().decode("utf-8"))
    except urllib.error.HTTPError as e:
        if e.code == 404:
            return None
        raise
    return release_from_json(data)


def clean_notes(text):
    """GitHub's Markdown release notes as plain text."""
    out = []
    for line in (text or "").replace("\r\n", "\n").split("\n"):
        s = line.rstrip()
        s = re.sub(r"^\s*#+\s*", "", s)
        s = re.sub(r"^(\s*)[*-]\s+", r"\1• ", s)
        s = re.sub(r"\[([^\]]+)\]\(([^)\s]+)\)", r"\1 (\2)", s)
        s = s.replace("**", "").replace("__", "").replace("`", "")
        out.append(s)
    return re.sub(r"\n{3,}", "\n\n", "\n".join(out)).strip()


# ---------- How this copy was installed ----------

def install_kind(here=None):
    """'deb' (the package installs to /usr/share/minisnap), 'flatpak', 'git' (a source checkout) or 'other'."""
    if paths.in_flatpak():
        return "flatpak"
    here = here or os.path.dirname(os.path.abspath(__file__))
    if os.path.normpath(here) == DEB_LOCATION:
        return "deb"
    if os.path.isdir(os.path.join(here, "..", "..", ".git")):
        return "git"
    return "other"


def flatpak_user_install(info_path="/.flatpak-info"):
    """True when the running Flatpak is a per-user installation (~/.local/share/flatpak)."""
    cp = configparser.ConfigParser(interpolation=None)
    try:
        cp.read(info_path, encoding="utf-8")
        return "/.local/share/flatpak/" in cp.get("Instance", "app-path", fallback="")
    except (configparser.Error, OSError):
        return False


def asset_for(release, kind):
    for a in release.assets if release is not None else []:
        if kind == "deb" and a["name"].endswith("_all.deb"):
            return a
        if kind == "flatpak" and a["name"].endswith(".flatpak"):
            return a
    return None


def terminal_command(release, kind, flatpak_user=None, here=None):
    """One line to paste into a Terminal that updates this installation, or None."""
    if kind == "git":
        here = here or os.path.dirname(os.path.abspath(__file__))
        return "git -C %s pull" % shlex.quote(os.path.normpath(os.path.join(here, "..", "..")))
    a = asset_for(release, kind)
    if a is None:
        return None
    if kind == "deb":
        return "wget -qO /tmp/minisnap.deb %s && sudo apt install -y /tmp/minisnap.deb" % shlex.quote(a["url"])
    if kind == "flatpak":
        if flatpak_user is None:
            flatpak_user = flatpak_user_install()
        return "wget -qO /tmp/MiniSnap.flatpak %s && flatpak install -y %s --reinstall /tmp/MiniSnap.flatpak" % (
            shlex.quote(a["url"]), "--user" if flatpak_user else "--system")
    return None


# ---------- Download, verify, install (.deb) ----------

def updates_folder():
    folder = os.path.join(GLib.get_user_cache_dir(), "minisnap", "updates")
    os.makedirs(folder, exist_ok=True)
    return folder


def sha256_of(path):
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for block in iter(lambda: f.read(1 << 16), b""):
            h.update(block)
    return h.hexdigest()


def expected_sha256(asset):
    d = (asset or {}).get("digest") or ""
    if d.lower().startswith("sha256:") and re.fullmatch(r"[0-9a-fA-F]{64}", d[7:]):
        return d[7:].lower()
    return None


def download(asset, dest, progress=None, timeout=30):
    """Downloads the asset to dest and checks it against its SHA-256 digest; raises on any problem.
    progress(done_bytes, total_bytes) is called from this (worker) thread."""
    want = expected_sha256(asset)
    if want is None:
        raise RuntimeError(L.t("GitHub không cung cấp mã SHA-256 cho tệp này nên MiniSnap không tự cài."))
    if not asset["url"].startswith("https://github.com/"):
        raise RuntimeError("unexpected download address: " + asset["url"])
    part = dest + ".part"
    req = urllib.request.Request(asset["url"], headers={"User-Agent": "MiniSnap/" + VERSION})
    h = hashlib.sha256()
    done = 0
    with urllib.request.urlopen(req, timeout=timeout) as resp, open(part, "wb") as out:
        total = int(resp.headers.get("Content-Length") or asset.get("size") or 0)
        while True:
            block = resp.read(1 << 16)
            if not block:
                break
            out.write(block)
            h.update(block)
            done += len(block)
            if progress is not None:
                progress(done, total)
    if h.hexdigest() != want:
        os.unlink(part)
        raise RuntimeError(L.t("Tệp tải về không khớp mã SHA-256 của GitHub, đã huỷ cài đặt."))
    os.replace(part, dest)
    return dest


def check_deb(path, version):
    """The package must be MiniSnap at the expected version (dpkg-deb reads its control file)."""
    try:
        out = subprocess.run(["dpkg-deb", "-f", path, "Package", "Version"], capture_output=True,
                             text=True, timeout=30, check=True).stdout
    except (OSError, subprocess.SubprocessError) as e:
        raise RuntimeError("dpkg-deb: %s" % e)
    fields = dict(line.split(": ", 1) for line in out.splitlines() if ": " in line)
    if fields.get("Package") != "minisnap" or parse_version(fields.get("Version")) != version:
        raise RuntimeError(L.t("Gói tải về không phải MiniSnap ") + version_text(version) + " (%s)" % out.strip())


def install_argv(path):
    return ["pkexec", "/usr/bin/apt-get", "install", "-y", path]


def restart(app):
    """Starts MiniSnap again once this process has quit (a second instance would only forward to us)."""
    exe = shutil.which("minisnap") or "/usr/bin/minisnap"
    try:
        subprocess.Popen(["sh", "-c", 'sleep 1; exec "$0"', exe], start_new_session=True,
                         stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    except OSError:
        pass
    app.quit()


# ---------- Daily background check ----------

def due_for_auto_check():
    last = settings.get("last_update_check")
    if not last:
        return True
    try:
        t = datetime.datetime.fromisoformat(last)
        if t.tzinfo is None:
            t = t.replace(tzinfo=datetime.timezone.utc)
    except ValueError:
        return True
    return datetime.datetime.now(datetime.timezone.utc) - t >= datetime.timedelta(hours=24)


def mark_checked():
    try:
        settings.set("last_update_check", datetime.datetime.now(datetime.timezone.utc).isoformat())
    except OSError:
        pass


def schedule_auto_check(on_found):
    """Quiet check 15 s after start and then once a day while MiniSnap runs; on_found(release) in the
    main thread only when something newer exists."""
    def run_check():
        if not settings.get("auto_update_check") or not due_for_auto_check():
            return

        def work():
            try:
                r = fetch()
                mark_checked()
            except Exception:  # noqa: BLE001 - silent: no network is not an error here
                return
            if is_newer(r):
                GLib.idle_add(lambda: (on_found(r), False)[1])
        threading.Thread(target=work, daemon=True).start()

    GLib.timeout_add_seconds(15, lambda: (run_check(), False)[1])
    GLib.timeout_add_seconds(24 * 3600, lambda: (run_check(), True)[1])


def _size_text(n):
    return "%.1f MB" % (n / 1048576.0) if n >= 1048576 else "%d KB" % max(1, n // 1024)


class UpdateWindow(Adw.ApplicationWindow):
    def __init__(self, app, known=None, kind=None, has_pkexec=None):
        """kind: how MiniSnap was installed, has_pkexec: whether pkexec exists (both detected when None;
        the self-test forces them)."""
        super().__init__(application=app)
        self.app = app
        self.release = None
        self.kind = kind or install_kind()
        self.has_pkexec = shutil.which("pkexec") is not None if has_pkexec is None else has_pkexec
        self.busy = False
        self.installed = False
        self.set_title(L.t("Cập nhật MiniSnap"))
        self.set_default_size(560, 500)

        view = Adw.ToolbarView()
        view.add_top_bar(Adw.HeaderBar())
        box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=10)
        box.set_margin_start(22)
        box.set_margin_end(22)
        box.set_margin_top(14)
        box.set_margin_bottom(18)
        self.title_label = Gtk.Label(xalign=0)
        self.title_label.set_wrap(True)
        self.title_label.add_css_class("ms-update-title")
        self.detail = Gtk.Label(xalign=0)
        self.detail.set_wrap(True)
        self.detail.add_css_class("dim-label")
        self.notes = Gtk.TextView()
        self.notes.set_editable(False)
        self.notes.set_cursor_visible(False)
        self.notes.set_wrap_mode(Gtk.WrapMode.WORD_CHAR)
        self.notes.set_left_margin(8)
        self.notes.set_right_margin(8)
        self.notes.set_top_margin(6)
        self.notes.set_bottom_margin(6)
        self.notes_scroll = Gtk.ScrolledWindow()
        self.notes_scroll.set_vexpand(True)
        self.notes_scroll.set_min_content_height(90)
        self.notes_scroll.set_child(self.notes)
        self.notes_scroll.add_css_class("card")
        self.notes_scroll.set_visible(False)

        # Progress of "Update now".
        self.progress = Gtk.ProgressBar()
        self.progress.set_visible(False)
        self.status = Gtk.Label(xalign=0)
        self.status.set_wrap(True)
        self.status.set_selectable(True)
        self.status.set_visible(False)

        # The Terminal command, with a Copy button.
        self.cmd_box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=6)
        self.cmd_box.set_visible(False)
        self.cmd_heading = Gtk.Label(xalign=0)
        self.cmd_heading.set_wrap(True)
        self.cmd_heading.add_css_class("heading")
        cmd_row = Gtk.Box(spacing=8)
        cmd_row.add_css_class("card")
        self.cmd_label = Gtk.Label(xalign=0)
        self.cmd_label.set_wrap(True)
        self.cmd_label.set_wrap_mode(Pango.WrapMode.WORD_CHAR)     # the URL has no spaces
        self.cmd_label.set_selectable(True)
        self.cmd_label.set_hexpand(True)
        self.cmd_label.add_css_class("monospace")
        self.cmd_label.set_margin_start(10)
        self.cmd_label.set_margin_top(8)
        self.cmd_label.set_margin_bottom(8)
        self.copy_btn = Gtk.Button(label=L.t("Sao chép"))
        self.copy_btn.set_valign(Gtk.Align.CENTER)
        self.copy_btn.set_margin_end(8)
        self.copy_btn.connect("clicked", self._copy)
        cmd_row.append(self.cmd_label)
        cmd_row.append(self.copy_btn)
        self.cmd_box.append(self.cmd_heading)
        self.cmd_box.append(cmd_row)

        buttons = Gtk.Box(spacing=8)
        buttons.set_valign(Gtk.Align.END)
        buttons.set_vexpand(True)
        self.github = Gtk.Button(label=L.t("Xem trên GitHub"))
        self.github.set_visible(False)
        self.github.connect("clicked", lambda *_: paths.open_uri(self.release.page_url if self.release and self.release.page_url else REPO + "/releases"))
        spacer = Gtk.Box()
        spacer.set_hexpand(True)
        self.update_btn = Gtk.Button(label=L.t("Cập nhật ngay"))
        self.update_btn.add_css_class("suggested-action")
        self.update_btn.set_visible(False)
        self.update_btn.connect("clicked", self._on_update)
        self.close_btn = Gtk.Button(label=L.t("Để sau"))
        self.close_btn.connect("clicked", lambda *_: self.close())
        buttons.append(self.github)
        buttons.append(spacer)
        buttons.append(self.update_btn)
        buttons.append(self.close_btn)
        for w in (self.title_label, self.detail, self.notes_scroll, self.progress, self.status, self.cmd_box, buttons):
            box.append(w)
        view.set_content(box)
        self.set_content(view)
        self.connect("close-request", lambda *_: self.busy)    # not while apt is running

        if known is not None:
            self.show_result(known, None)
        else:
            self.title_label.set_text(L.t("Đang kiểm tra cập nhật..."))
            self.detail.set_text(L.t("Phiên bản hiện tại: ") + VERSION)
            threading.Thread(target=self._check, daemon=True).start()

    def _check(self):
        r, error = None, None
        try:
            r = fetch()
            mark_checked()
        except Exception as e:  # noqa: BLE001
            error = str(getattr(e, "reason", None) or e)
        GLib.idle_add(lambda: (self.show_result(r, error), False)[1])

    def show_result(self, r, error):
        self.release = r
        self.close_btn.set_label(L.t("Đóng"))
        if error is not None:
            self.title_label.set_text(L.t("Không kiểm tra được cập nhật"))
            self.detail.set_text(error + L.t("\nHãy kiểm tra kết nối mạng rồi thử lại."))
            return
        if r is None:
            self.title_label.set_text(L.t("Bạn đang dùng bản mới nhất"))
            self.detail.set_text(L.t("Chưa có bản phát hành nào trên GitHub. Phiên bản hiện tại: ") + VERSION)
            return
        if not is_newer(r):
            self.title_label.set_text(L.t("Bạn đang dùng bản mới nhất"))
            self.detail.set_text(L.t("Phiên bản hiện tại: ") + VERSION + L.t(" — mới nhất trên GitHub: ")
                                 + (version_text(r.version) if r.version else (r.tag or "?")))
            self.github.set_visible(True)
            return
        self.title_label.set_text(L.t("Có phiên bản mới: ") + version_text(r.version))
        detail = L.t("Bạn đang dùng ") + VERSION + L.t(". Ảnh, video và cài đặt của bạn được giữ nguyên khi cập nhật.")
        can_auto = self.kind == "deb" and expected_sha256(asset_for(r, "deb")) is not None and self.has_pkexec
        cmd = terminal_command(r, self.kind)
        if can_auto:
            detail += L.t("\nBấm Cập nhật ngay: MiniSnap tải bản mới, kiểm tra mã SHA-256 rồi cài đặt (hệ thống sẽ hỏi mật khẩu của bạn).")
        elif cmd is None:
            detail += L.t("\nHãy tải bản mới cho Linux trên trang GitHub.")
        self.detail.set_text(detail)
        text = clean_notes(r.notes) or (r.name or r.tag or "")
        if len(text) > 4000:
            text = text[:4000] + "…"
        self.notes.get_buffer().set_text(text, -1)
        self.notes_scroll.set_visible(bool(text))
        if cmd is not None:
            self.cmd_heading.set_text(L.t("Hoặc cập nhật bằng Terminal:") if can_auto
                                      else L.t("Cập nhật bằng lệnh Terminal:"))
            self.cmd_label.set_text(cmd)
            self.cmd_box.set_visible(True)
        self.github.set_visible(True)
        self.update_btn.set_visible(can_auto)
        if not can_auto and cmd is None:
            self.github.add_css_class("suggested-action")
        self.close_btn.set_label(L.t("Để sau"))
        (self.update_btn if can_auto else self.close_btn).grab_focus()

    def _copy(self, *_):
        self.get_display().get_clipboard().set_text(self.cmd_label.get_text())
        self.copy_btn.set_label(L.t("✓ Đã chép"))
        GLib.timeout_add(1500, lambda: (self.copy_btn.set_label(L.t("Sao chép")), False)[1])

    # ---------- Update now (.deb) ----------

    def _set_busy(self, busy):
        self.busy = busy
        self.update_btn.set_sensitive(not busy)
        self.close_btn.set_sensitive(not busy)

    def _say(self, text, error=False):
        self.status.set_text(text)
        self.status.set_visible(True)
        if error:
            self.status.add_css_class("error")
        else:
            self.status.remove_css_class("error")

    def _on_update(self, *_):
        if self.installed:
            restart(self.app)
            return
        asset = asset_for(self.release, "deb")
        if asset is None or self.busy:
            return
        self._set_busy(True)
        self.progress.set_fraction(0)
        self.progress.set_visible(True)
        self._say(L.t("Đang tải ") + asset["name"] + "…")
        version = self.release.version

        def progress(done, total):
            GLib.idle_add(lambda: (self._progress(done, total), False)[1])

        def work():
            try:
                dest = download(asset, os.path.join(updates_folder(), asset["name"]), progress)
                check_deb(dest, version)
            except Exception as e:  # noqa: BLE001
                msg = str(getattr(e, "reason", None) or e)
                GLib.idle_add(lambda: (self._failed(msg), False)[1])
                return
            GLib.idle_add(lambda: (self._install(dest), False)[1])
        threading.Thread(target=work, daemon=True).start()

    def _progress(self, done, total):
        if total > 0:
            self.progress.set_fraction(min(1.0, done / float(total)))
            self._say(L.t("Đang tải ") + "%s / %s" % (_size_text(done), _size_text(total)))
        else:
            self.progress.pulse()

    def _install(self, path):
        self.progress.set_fraction(1.0)
        self._say(L.t("Đã kiểm tra mã SHA-256. Đang cài đặt — hãy nhập mật khẩu khi hệ thống hỏi…"))
        try:
            proc = Gio.Subprocess.new(install_argv(path),
                                      Gio.SubprocessFlags.STDOUT_PIPE | Gio.SubprocessFlags.STDERR_MERGE)
        except GLib.Error as e:
            self._failed(e.message)
            return
        proc.communicate_utf8_async(None, None, self._installed, path)

    def _installed(self, proc, res, path):
        try:
            _ok, out, _err = proc.communicate_utf8_finish(res)
        except GLib.Error as e:
            self._failed(e.message)
            return
        code = proc.get_exit_status()
        if code != 0:
            if code in (126, 127):
                self._failed(L.t("Chưa được cấp quyền cài đặt (hộp thoại mật khẩu bị đóng)."))
            else:
                tail = "\n".join((out or "").strip().splitlines()[-6:])
                self._failed(L.t("apt-get báo lỗi:\n") + tail)
            return
        try:
            os.unlink(path)
        except OSError:
            pass
        self._set_busy(False)
        self.installed = True
        self.progress.set_visible(False)
        self.cmd_box.set_visible(False)
        self.title_label.set_text(L.t("Đã cập nhật lên ") + version_text(self.release.version))
        self._say(L.t("Khởi động lại MiniSnap để dùng bản mới."))
        self.update_btn.set_label(L.t("Khởi động lại MiniSnap"))
        self.close_btn.set_label(L.t("Để sau"))
        self.update_btn.grab_focus()

    def _failed(self, msg):
        self._set_busy(False)
        self.progress.set_visible(False)
        extra = L.t("\nBạn có thể dùng lệnh Terminal bên dưới.") if self.cmd_box.get_visible() else ""
        self._say(L.t("Không cập nhật được: ") + msg + extra, error=True)
