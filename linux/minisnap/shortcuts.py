"""Keyboard shortcuts: real global shortcuts through the GlobalShortcuts portal where the desktop
has it (GNOME 48+, KDE Plasma 6), and always the fallback explanation of GNOME custom keyboard
shortcuts, which run `minisnap --capture region` and friends on the running instance (what
Ubuntu 24.04 / GNOME 46 needs).
"""

import os
import shlex
import shutil
import subprocess

from . import _gi  # noqa: F401
from gi.repository import Adw, GLib, Gtk

from . import paths
from .i18n import L


def launcher_command():
    """`minisnap` when installed on PATH, else the absolute path of linux/bin/minisnap.

    Inside Flatpak the shortcut runs on the host, so it must go through `flatpak run`."""
    if paths.in_flatpak():
        return "flatpak run " + os.environ.get("FLATPAK_ID", "io.github.nnqbao.MiniSnap")
    if shutil.which("minisnap"):
        return "minisnap"
    here = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "bin", "minisnap")
    return here if os.path.exists(here) else "minisnap"


def commands():
    """(name, arguments, suggested keys)."""
    return [
        (L.t("Chụp vùng / cửa sổ"), "--capture region", "Ctrl+Alt+C"),
        (L.t("Chụp toàn màn hình"), "--capture full", "Ctrl+Alt+F"),
        (L.t("Chụp cuộn trang dài"), "--capture scroll", "Ctrl+Alt+S"),
        (L.t("Quay video (bắt đầu / dừng)"), "--record", "Ctrl+Alt+R"),
        (L.t("Chụp và trích chữ (OCR)"), "--ocr", "Ctrl+Alt+O"),
        (L.t("Thư viện ảnh & video"), "--library", "Ctrl+Alt+L"),
    ]


class ShortcutsWindow(Adw.ApplicationWindow):
    def __init__(self, app, portal_available=None):
        """portal_available: None = ask the app's GlobalShortcuts object (the self-test forces True)."""
        super().__init__(application=app)
        self.app = app
        self.gs = getattr(app, "gshortcuts", None)
        if portal_available is None:
            portal_available = self.gs is not None and self.gs.available
        self.trigger_labels = {}
        self.portal_status = None
        self.set_title(L.t("Phím tắt bàn phím — MiniSnap"))
        self.set_default_size(640, 680 if portal_available else 620)
        view = Adw.ToolbarView()
        view.add_top_bar(Adw.HeaderBar())

        page = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=14)
        page.set_margin_start(20)
        page.set_margin_end(20)
        page.set_margin_top(14)
        page.set_margin_bottom(20)

        if portal_available:
            page.append(self._portal_group())
            fallback = Gtk.Label(xalign=0)
            fallback.set_wrap(True)
            fallback.add_css_class("heading")
            fallback.set_margin_top(6)
            fallback.set_text(L.t("Cách khác: phím tắt tự tạo trong Cài đặt (GNOME 46 / Ubuntu 24.04)"))
            page.append(fallback)
            if self.gs is not None:
                self.gs.add_listener(self._refresh_portal)
                self.connect("destroy", lambda *_: self.gs.remove_listener(self._refresh_portal))

        intro = Gtk.Label(xalign=0)
        intro.set_wrap(True)
        intro.set_text(L.t("Trên Linux, phím tắt toàn cục được đặt trong Cài đặt của hệ thống. Mỗi phím tắt chạy một lệnh MiniSnap; nếu MiniSnap đang chạy, lệnh được chuyển cho cửa sổ đang mở."))
        page.append(intro)

        steps = Gtk.Label(xalign=0)
        steps.set_wrap(True)
        steps.set_text(L.t("1. Mở Cài đặt → Bàn phím → Xem và tuỳ chỉnh phím tắt → Phím tắt tự tạo.") + "\n"
                       + L.t("2. Bấm + (Thêm phím tắt), đặt tên, dán lệnh bên dưới vào ô Lệnh.") + "\n"
                       + L.t("3. Bấm Đặt phím tắt… rồi nhấn tổ hợp phím, ví dụ Ctrl+Alt+C."))
        page.append(steps)

        group = Adw.PreferencesGroup()
        group.set_title(L.t("Lệnh"))
        exe = launcher_command()
        for name, args, keys in commands():
            cmd = shlex.quote(exe) + " " + args
            row = Adw.ActionRow()
            row.set_use_markup(False)   # titles contain "&"
            row.set_title(name)
            row.set_subtitle(cmd)
            row.set_subtitle_selectable(True)
            row.add_css_class("ms-command-row")
            hint = Gtk.Label(label=L.t("Gợi ý: ") + keys)
            hint.add_css_class("dim-label")
            hint.set_valign(Gtk.Align.CENTER)
            row.add_suffix(hint)
            copy = Gtk.Button(label=L.t("Sao chép"))
            copy.set_valign(Gtk.Align.CENTER)
            copy.connect("clicked", self._copy, cmd)
            row.add_suffix(copy)
            group.add(row)
        page.append(group)

        note = Gtk.Label(xalign=0)
        note.set_wrap(True)
        note.add_css_class("dim-label")
        note.set_text(L.t("Phím Print Screen đang được GNOME dùng cho công cụ chụp màn hình của nó. Muốn dùng Print Screen cho MiniSnap, hãy bỏ phím đó ở mục Chụp màn hình trong Cài đặt → Bàn phím trước."))
        page.append(note)

        if shutil.which("gnome-control-center"):
            open_btn = Gtk.Button(label=L.t("Mở Cài đặt bàn phím"))
            open_btn.add_css_class("suggested-action")
            open_btn.set_halign(Gtk.Align.START)
            open_btn.connect("clicked", self._open_settings)
            page.append(open_btn)

        scroll = Gtk.ScrolledWindow()
        scroll.set_policy(Gtk.PolicyType.NEVER, Gtk.PolicyType.AUTOMATIC)
        clamp = Adw.Clamp()
        clamp.set_maximum_size(720)
        clamp.set_child(page)
        scroll.set_child(clamp)
        view.set_content(scroll)
        self.set_content(view)

    # ---------- GlobalShortcuts portal ----------

    def _portal_group(self):
        from .globalshortcuts import pretty_trigger, shortcut_list
        group = Adw.PreferencesGroup()
        group.set_title(L.t("Phím tắt toàn cục (hệ thống hỗ trợ)"))
        group.set_description(L.t("Desktop của bạn cho phép MiniSnap tự đăng ký phím tắt. Hệ thống sẽ mở hộp thoại riêng để bạn xác nhận hoặc đổi phím; MiniSnap chạy nền để nhận phím tắt."))
        button = Gtk.Button(label=L.t("Đăng ký / Đổi phím…"))
        button.add_css_class("suggested-action")
        button.set_valign(Gtk.Align.CENTER)
        button.connect("clicked", self._on_configure)
        # Below the list rather than as the header suffix: there it overlapped the wrapped description.
        for sid, name, preferred in shortcut_list():
            row = Adw.ActionRow()
            row.set_use_markup(False)
            row.set_title(name)
            label = Gtk.Label()
            label.set_valign(Gtk.Align.CENTER)
            label.set_selectable(False)
            row.add_suffix(label)
            self.trigger_labels[sid] = (label, pretty_trigger(preferred))
            group.add(row)
        self.portal_status = Gtk.Label(xalign=0)
        self.portal_status.set_wrap(True)
        self.portal_status.set_hexpand(True)
        self.portal_status.add_css_class("dim-label")
        self.portal_status.add_css_class("caption")
        footer = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=12)
        footer.set_margin_top(10)
        footer.append(button)
        footer.append(self.portal_status)
        group.add(footer)
        self._refresh_portal()
        return group

    def _refresh_portal(self):
        gs = self.gs
        triggers = gs.triggers if gs is not None else {}
        enabled = gs is not None and gs.enabled()
        for sid, (label, suggested) in self.trigger_labels.items():
            bound = triggers.get(sid)
            for c in ("dim-label", "accent"):
                label.remove_css_class(c)
            if bound:
                label.set_text(bound)
                label.add_css_class("accent")
            else:
                label.set_text(L.t("Gợi ý: ") + suggested)
                label.add_css_class("dim-label")
        if self.portal_status is not None:
            if gs is not None and gs.error:
                self.portal_status.set_text(L.t("Hệ thống báo lỗi: ") + str(gs.error))
            elif enabled:
                self.portal_status.set_text(L.t("Đang bật. Phím tắt hiển thị ở trên là phím hệ thống đã gán."))
            else:
                self.portal_status.set_text(L.t("Chưa bật. Bấm Đăng ký / Đổi phím… để bật."))

    def _on_configure(self, *_):
        if self.gs is None:
            return
        try:
            self.gs.configure()
        except OSError as e:
            self.portal_status.set_text(L.t("Không lưu được cài đặt:\n") + str(e))
            return
        if hasattr(self.app, "sync_global_shortcuts_action"):
            self.app.sync_global_shortcuts_action()
        self._refresh_portal()

    def _copy(self, button, cmd):
        self.get_display().get_clipboard().set_text(cmd)
        button.set_label(L.t("✓ Đã chép"))
        GLib.timeout_add(1500, lambda: (button.set_label(L.t("Sao chép")), False)[1])

    def _open_settings(self, *_):
        try:
            subprocess.Popen(["gnome-control-center", "keyboard"], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        except OSError:
            pass
