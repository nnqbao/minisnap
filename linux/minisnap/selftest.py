"""Headless self-test: `python3 -m minisnap --selftest OUTDIR`.

Runs under `xvfb-run -a -s "-screen 0 1600x1000x24"` without a real portal; the screenshot step talks
to FakePortal below, which owns made-up bus names.
Writes OUTDIR/log.txt plus PNGs: render.png, stitch.png, scroll-session.png, and screenshots of every
window in both languages and both colour schemes (e.g. editor-vi-dark.png, shortcuts-portal-en-light.png,
scroll-status-vi-dark.png). Each step logs "ok" or
"FAILED: reason"; a failing step never stops the others; the exit code is non-zero if any failed.
(SelfTest in windows/src/Program.cs.)
"""

import ast
import os
import random
import shutil
import subprocess
import sys
import tempfile
import threading
import time
import traceback

WINDOW_KINDS = ("launcher", "editor", "editor-blur", "overlay", "library", "about", "shortcuts", "shortcuts-portal", "scroll-status",
                "update")


def run(outdir):
    """Prepares an isolated environment, then runs the GTK part inside a non-unique application."""
    outdir = os.path.abspath(outdir)
    os.makedirs(outdir, exist_ok=True)
    with open(os.path.join(outdir, "log.txt"), "w", encoding="utf-8"):
        pass
    tmp = tempfile.mkdtemp(prefix="minisnap-selftest-")
    # Never touch the user's real captures or settings.
    os.environ["MINISNAP_LIBRARY"] = os.path.join(tmp, "library")
    os.environ["XDG_CONFIG_HOME"] = os.path.join(tmp, "config")
    os.environ.pop("MINISNAP_LANG", None)
    os.environ.setdefault("GTK_A11Y", "none")
    os.environ.setdefault("NO_AT_BRIDGE", "1")
    # Deterministic software rendering under Xvfb (override by setting GSK_RENDERER yourself).
    os.environ.setdefault("GSK_RENDERER", "cairo")
    try:
        from .app import MiniSnapApp
        app = MiniSnapApp(selftest_dir=outdir)
        app.run([sys.argv[0] if sys.argv else "minisnap"])
        code = app.selftest_result
    except Exception:  # noqa: BLE001
        _append(outdir, "selftest: FAILED to start: " + traceback.format_exc())
        code = 1
    finally:
        shutil.rmtree(tmp, ignore_errors=True)
    return code


def _append(outdir, line):
    print(line, flush=True)
    with open(os.path.join(outdir, "log.txt"), "a", encoding="utf-8") as f:
        f.write(line + "\n")


def start(app, outdir):
    """Called from MiniSnapApp.do_activate in self-test mode."""
    Runner(app, outdir).start()


# ---------- Synthetic images ----------

def sample_image(w, h, lines, seed):
    """Light page with numbered text lines and a few coloured boxes (SelfTest.SampleImage)."""
    import cairo
    from . import _gi  # noqa: F401
    from gi.repository import PangoCairo
    from .shapes import font_desc

    rnd = random.Random(seed)
    s = cairo.ImageSurface(cairo.FORMAT_ARGB32, w, h)
    cr = cairo.Context(s)
    cr.set_source_rgb(246 / 255.0, 248 / 255.0, 252 / 255.0)
    cr.paint()
    layout = PangoCairo.create_layout(cr)
    layout.set_font_description(font_desc(22, bold=False))
    for i in range(lines):
        layout.set_text("Line %d — the quick brown fox %d jumps" % (i + 1, rnd.randint(1000, 9999)), -1)
        cr.move_to(40, 30 + i * 58)
        cr.set_source_rgb(105 / 255.0, 105 / 255.0, 105 / 255.0)
        PangoCairo.show_layout(cr, layout)
        if i % 7 == 3:
            cr.set_source_rgb(rnd.randint(80, 199) / 255.0, rnd.randint(80, 199) / 255.0, rnd.randint(80, 199) / 255.0)
            cr.rectangle(w - 260, 20 + i * 58, 200, 40)
            cr.fill()
    s.flush()
    return s


def text_image(text, w=900, h=160):
    import cairo
    from . import _gi  # noqa: F401
    from gi.repository import PangoCairo
    from .shapes import font_desc

    s = cairo.ImageSurface(cairo.FORMAT_ARGB32, w, h)
    cr = cairo.Context(s)
    cr.set_source_rgb(1, 1, 1)
    cr.paint()
    layout = PangoCairo.create_layout(cr)
    layout.set_font_description(font_desc(36, bold=False))
    layout.set_text(text, -1)
    cr.move_to(30, 40)
    cr.set_source_rgb(0, 0, 0)
    PangoCairo.show_layout(cr, layout)
    s.flush()
    return s


def blur_sample(w, h):
    """Coloured bands over dark text, so blur cells and softness are easy to judge."""
    import cairo
    from . import _gi  # noqa: F401
    from gi.repository import PangoCairo
    from .shapes import font_desc

    s = cairo.ImageSurface(cairo.FORMAT_ARGB32, w, h)
    cr = cairo.Context(s)
    cr.set_source_rgb(1, 1, 1)
    cr.paint()
    bands = ((255, 214, 0), (30, 145, 75), (25, 110, 225), (232, 38, 38))
    for i, (r, g, b) in enumerate(bands):
        cr.set_source_rgb(r / 255.0, g / 255.0, b / 255.0)
        cr.rectangle(i * w // len(bands), 0, w // len(bands) + 1, h // 2)
        cr.fill()
    layout = PangoCairo.create_layout(cr)
    layout.set_font_description(font_desc(26, bold=True))
    for text, y, rgb in (("0912 345 678", 14, (1, 1, 1)), ("nnqbao@mail.vn", h // 2 + 8, (0, 0, 0))):
        layout.set_text(text, -1)
        cr.move_to(20, y)
        cr.set_source_rgb(*rgb)
        PangoCairo.show_layout(cr, layout)
    s.flush()
    return s


def sample_release_json(version):
    """A GitHub "latest release" answer for a made-up version (no network involved)."""
    tag = "v%d.%d.%d" % tuple(version)
    v = tag[1:]
    base = "https://github.com/nnqbao/minisnap/releases/download/%s/" % tag
    assets = [("minisnap_%s_all.deb" % v, 80000), ("MiniSnap.flatpak", 4700000), ("MiniSnap-Setup.exe", 331000)]
    return {
        "tag_name": tag, "name": tag, "html_url": "https://github.com/nnqbao/minisnap/releases/tag/" + tag,
        "body": "## What's new\r\n* Screenshots on **GNOME** work again\r\n- Update from the app\r\n\r\n\r\n"
                "**Full Changelog**: https://github.com/nnqbao/minisnap/compare/v1.0.0...v9.9.9",
        "assets": [{"name": n, "browser_download_url": base + n, "size": s, "digest": "sha256:" + "ab" * 32}
                   for n, s in assets],
    }


def sample_shapes():
    from .shapes import (ArrowShape, BlurShape, EllipseShape, HighlightShape, LineShape, PenShape, RectShape,
                         StepShape, TextShape)
    red, blue, yellow, green, purple = (232, 38, 38), (30, 120, 230), (255, 214, 0), (40, 170, 70), (150, 70, 200)
    pen = [(620 + i * 6, 430 + 25 * ((i % 8) - 4) * ((-1) ** (i // 8)) / 4.0) for i in range(40)]
    return [
        ArrowShape(a=(560, 420), b=(380, 150), color=red, width=5),
        RectShape(a=(30, 80), b=(560, 140), color=red, width=4),
        EllipseShape(a=(600, 60), b=(860, 180), color=blue, width=4),
        LineShape(a=(600, 230), b=(860, 230), color=green, width=5),
        PenShape(points=pen, color=purple, width=5),
        HighlightShape(a=(36, 200), b=(560, 240), color=yellow, width=5),
        BlurShape(a=(330, 260), b=(720, 330), width=5),
        StepShape(center=(60, 470), number=1, color=red, width=5),
        StepShape(center=(60, 530), number=2, color=blue, width=5),
        TextShape(pos=(100, 450), text="Chú thích tiếng Việt", color=red, width=5),
    ]


def viewport_frame(page, off, width, view_h, header, footer):
    """What a 'browser' shows of `page` scrolled by `off`: sticky header and footer over the content."""
    import cairo
    from . import _gi  # noqa: F401
    from gi.repository import PangoCairo
    from .shapes import font_desc

    frame = cairo.ImageSurface(cairo.FORMAT_ARGB32, width, view_h)
    cr = cairo.Context(frame)
    cr.save()
    cr.rectangle(0, header, width, view_h - header - footer)
    cr.clip()
    cr.set_source_surface(page, 0, header - (off + header))
    cr.paint()
    cr.restore()
    layout = PangoCairo.create_layout(cr)
    layout.set_font_description(font_desc(12))
    cr.set_source_rgb(70 / 255.0, 130 / 255.0, 180 / 255.0)
    cr.rectangle(0, 0, width, header)
    cr.fill()
    cr.set_source_rgb(1, 1, 1)
    cr.move_to(10, 25)
    layout.set_text("STICKY HEADER", -1)
    PangoCairo.show_layout(cr, layout)
    cr.set_source_rgb(47 / 255.0, 79 / 255.0, 79 / 255.0)
    cr.rectangle(0, view_h - footer, width, footer)
    cr.fill()
    cr.set_source_rgb(1, 1, 1)
    cr.move_to(10, view_h - footer + 15)
    layout.set_text("STICKY FOOTER", -1)
    PangoCairo.show_layout(cr, layout)
    frame.flush()
    return frame


def snapshot_window(win, path):
    """Renders a presented window to PNG through Gtk.WidgetPaintable and the window's own renderer."""
    from . import _gi  # noqa: F401
    from gi.repository import Gtk

    last_error = "window has no size"
    for target in (win, win.get_child()):
        if target is None:
            continue
        w, h = target.get_width(), target.get_height()
        if w <= 0 or h <= 0:
            continue
        paintable = Gtk.WidgetPaintable(widget=target)
        snap = Gtk.Snapshot()
        paintable.snapshot(snap, w, h)
        node = snap.to_node()
        if node is None:
            last_error = "empty render node"
            continue
        renderer = win.get_renderer()
        if renderer is None:
            last_error = "window has no renderer"
            continue
        tex = renderer.render_texture(node, None)
        if tex.save_to_png(path) and os.path.getsize(path) > 0:
            return "%dx%d" % (tex.get_width(), tex.get_height())
        last_error = "save_to_png failed"
    raise RuntimeError(last_error)


class FakePortal:
    """A stand-in xdg-desktop-portal served from its own thread (so the app's synchronous calls get
    answers): host Registry.Register, Screenshot (a silent grab is refused with response 2 unless
    allow_silent, the screenshot UI answers with a PNG, deny_all refuses everything) and the permission
    store's DeletePermission. Every call is recorded as (sender, method, args)."""

    NAME = "io.github.nnqbao.MiniSnap.SelfTest.Portal"
    STORE_NAME = "io.github.nnqbao.MiniSnap.SelfTest.PermissionStore"
    XML = """<node>
  <interface name='org.freedesktop.host.portal.Registry'>
    <method name='Register'><arg type='s' direction='in'/><arg type='a{sv}' direction='in'/></method>
  </interface>
  <interface name='org.freedesktop.portal.Screenshot'>
    <method name='Screenshot'>
      <arg type='s' direction='in'/><arg type='a{sv}' direction='in'/><arg type='o' direction='out'/>
    </method>
  </interface>
  <interface name='org.freedesktop.impl.portal.PermissionStore'>
    <method name='DeletePermission'>
      <arg type='s' direction='in'/><arg type='s' direction='in'/><arg type='s' direction='in'/>
    </method>
  </interface>
</node>"""

    def __init__(self, png_path):
        self.png = png_path
        self.calls = []
        self.allow_silent = False
        self.deny_all = False
        self.error = None
        self.loop = None
        self._ready = threading.Event()

    def start(self):
        self.thread = threading.Thread(target=self._run, daemon=True)
        self.thread.start()
        if not self._ready.wait(10):
            raise RuntimeError("fake portal did not start")
        if self.error:
            raise RuntimeError("fake portal: " + self.error)

    def stop(self):
        if self.loop is not None:
            self.loop.quit()
            self.thread.join(10)

    def _run(self):
        from . import _gi  # noqa: F401
        from gi.repository import Gio, GLib
        from . import portal
        ctx = GLib.MainContext.new()
        ctx.push_thread_default()
        try:
            address = Gio.dbus_address_get_for_bus_sync(Gio.BusType.SESSION, None)
            conn = Gio.DBusConnection.new_for_address_sync(
                address, Gio.DBusConnectionFlags.AUTHENTICATION_CLIENT | Gio.DBusConnectionFlags.MESSAGE_BUS_CONNECTION,
                None, None)
            for iface in Gio.DBusNodeInfo.new_for_xml(self.XML).interfaces:
                path = portal.PERMISSION_STORE_PATH if iface.name == portal.PERMISSION_STORE_IFACE else portal.OBJECT_PATH
                conn.register_object(path, iface, self._on_call, None, None)
            for name in (self.NAME, self.STORE_NAME):
                ret = conn.call_sync("org.freedesktop.DBus", "/org/freedesktop/DBus", "org.freedesktop.DBus",
                                     "RequestName", GLib.Variant("(su)", (name, 4)), GLib.VariantType.new("(u)"),
                                     Gio.DBusCallFlags.NONE, 5000, None)
                if ret.unpack()[0] != 1:
                    raise RuntimeError("could not own " + name)
            self.loop = GLib.MainLoop.new(ctx, False)
        except Exception as e:  # noqa: BLE001
            self.error = str(e)
            self._ready.set()
            return
        self._ready.set()
        self.loop.run()
        conn.close_sync(None)
        ctx.pop_thread_default()

    def _on_call(self, conn, sender, path, iface, method, params, invocation):
        from gi.repository import GLib
        from . import portal
        args = params.unpack()
        self.calls.append((sender, method, args))
        if method != "Screenshot":
            invocation.return_value(None)
            return
        options = args[1]
        request = "%s/request/%s/%s" % (portal.OBJECT_PATH, sender.lstrip(":").replace(".", "_"),
                                        options.get("handle_token", "t"))
        invocation.return_value(GLib.Variant("(o)", (request,)))
        if self.deny_all or not (options.get("interactive") or self.allow_silent):
            code, results = 2, {}
        else:
            code, results = 0, {"uri": GLib.Variant("s", GLib.filename_to_uri(self.png, None))}
        conn.emit_signal(sender, request, portal.REQUEST_IFACE, "Response", GLib.Variant("(ua{sv})", (code, results)))


class Runner:
    def __init__(self, app, outdir):
        self.app = app
        self.outdir = outdir
        self.failures = 0
        self.finished = False

    def log(self, line):
        _append(self.outdir, line)

    def check(self, name, fn):
        try:
            detail = fn()
            self.log("%s: ok%s" % (name, (" — " + str(detail)) if detail else ""))
        except Exception as e:  # noqa: BLE001
            self.failures += 1
            self.log("%s: FAILED: %s" % (name, e))
            for line in traceback.format_exc().rstrip().splitlines():
                self.log("    " + line)

    def start(self):
        from gi.repository import GLib
        from . import VERSION
        self.app.hold()
        self.log("MiniSnap %s self-test, Python %s" % (VERSION, sys.version.split()[0]))
        self._log_versions()
        GLib.timeout_add_seconds(300, self._watchdog)
        for name, fn in (
            ("settings", self.test_settings),
            ("args", self.test_args),
            ("i18n", self.test_i18n),
            ("render", self.test_render),
            ("blur settings", self.test_blur),
            ("stitch", self.test_stitch),
            ("scroll session", self.test_scroll_session),
            ("scroll portal plumbing", self.test_scroll_plumbing),
            ("global shortcuts model", self.test_global_shortcuts),
            ("screenshot portal fallback", self.test_screenshot_portal),
            ("monitor mapping", self.test_mapping),
            ("record crop", self.test_crop),
            ("updater compare", self.test_updater),
            ("ocr", self.test_ocr),
            ("video encode", self.test_video),
            ("library files", self.fill_library),
            ("editor operations", self.test_editor_ops),
        ):
            self.check(name, fn)
        self._pump(self._ui_steps())

    def _log_versions(self):
        try:
            from gi.repository import Adw, Gtk
            self.log("GTK %d.%d.%d, libadwaita %d.%d.%d, renderer env GSK_RENDERER=%s" % (
                Gtk.get_major_version(), Gtk.get_minor_version(), Gtk.get_micro_version(),
                Adw.get_major_version(), Adw.get_minor_version(), Adw.get_micro_version(),
                os.environ.get("GSK_RENDERER", "")))
        except Exception as e:  # noqa: BLE001
            self.log("versions: %s" % e)

    def _watchdog(self):
        if not self.finished:
            self.failures += 1
            self.log("watchdog: FAILED: self-test did not finish in 300 s")
            self._finish()
        return False

    def _finish(self):
        if self.finished:
            return
        self.finished = True
        self.log("selftest: %s (%d failed step%s)" % ("ok" if self.failures == 0 else "FAILED", self.failures,
                                                      "" if self.failures == 1 else "s"))
        self.app.selftest_result = 0 if self.failures == 0 else 1
        for w in list(self.app.get_windows()):
            try:
                w.destroy()
            except Exception:  # noqa: BLE001
                pass
        self.app.release()
        self.app.quit()

    # ---------- Non-UI steps ----------

    def test_settings(self):
        from . import settings
        settings.set("ask_after_select", False)
        settings.reset_cache()
        if settings.get("ask_after_select") is not False:
            raise RuntimeError("value not read back from " + settings.config_path())
        settings.set("ask_after_select", True)
        settings.reset_cache()
        return settings.config_path()

    def test_args(self):
        from .app import parse_args
        cases = {
            ("--capture", "region"): ("capture", "region"),
            ("--capture=full",): ("capture", "full"),
            ("--capture", "delayed"): ("capture", "delayed"),
            ("--record",): ("record", None),
            ("--ocr",): ("ocr", None),
            ("--library",): ("library", None),
            ("--about",): ("about", None),
        }
        for args, want in cases.items():
            got = parse_args(list(args))[:2]
            if got != want:
                raise RuntimeError("%s -> %s, expected %s" % (args, got, want))
        try:
            parse_args(["--capture", "nonsense"])
            raise RuntimeError("bad --capture value accepted")
        except ValueError:
            pass
        return "%d cases" % len(cases)

    def test_i18n(self):
        """Every L.t("…") literal in the package must have an English entry."""
        from .i18n import L
        pkg = os.path.dirname(os.path.abspath(__file__))
        used, missing, dynamic = set(), [], 0
        for name in sorted(os.listdir(pkg)):
            if not name.endswith(".py"):
                continue
            with open(os.path.join(pkg, name), "r", encoding="utf-8") as f:
                tree = ast.parse(f.read(), filename=name)
            for node in ast.walk(tree):
                if (isinstance(node, ast.Call) and isinstance(node.func, ast.Attribute) and node.func.attr == "t"
                        and isinstance(node.func.value, ast.Name) and node.func.value.id == "L"):
                    if node.args and isinstance(node.args[0], ast.Constant) and isinstance(node.args[0].value, str):
                        text = node.args[0].value
                        used.add(text)
                        if not L.has(text):
                            missing.append("%s:%d %r" % (name, node.lineno, text))
                    else:
                        dynamic += 1
        if missing:
            raise RuntimeError("%d missing translation(s): %s" % (len(missing), "; ".join(missing)))
        return "%d strings checked, %d non-literal calls" % (len(used), dynamic)

    def test_render(self):
        from . import render
        sample = sample_image(900, 560, 9, 1)
        flat = render.render(sample, sample_shapes())
        path = os.path.join(self.outdir, "render.png")
        flat.write_to_png(path)
        r, g, b = render.pixel_rgb(flat, 30, 110)    # left edge of the red box
        if not (r > 180 and g < 110 and b < 110):
            raise RuntimeError("box edge pixel is %s, expected red" % ((r, g, b),))
        self._render_sample = flat
        return "%dx%d" % render.size(flat)

    def test_blur(self):
        """Cell sizes 1, 4, 7, 10 (rows) against softness 0, 5, 10 (columns) -> blur-grid.png, plus checks that
        a mosaic is made of flat cells and that softness removes the cell edges."""
        import cairo
        from . import render
        from .shapes import BlurShape
        cells, smooths, tw, th = (1, 4, 7, 10), (0, 5, 10), 300, 150
        grid = cairo.ImageSurface(cairo.FORMAT_ARGB32, tw * len(smooths), th * len(cells))
        cr = cairo.Context(grid)
        tiles = {}
        for row, cell in enumerate(cells):
            for col, smooth in enumerate(smooths):
                blur = BlurShape(a=(10, 10), b=(tw - 10, th - 10), cell=cell, smooth=smooth)
                flat = render.render(blur_sample(tw, th), [blur])
                tiles[(cell, smooth)] = flat
                cr.set_source_surface(flat, col * tw, row * th)
                cr.paint()
        grid.write_to_png(os.path.join(self.outdir, "blur-grid.png"))
        # Cell 10 is 64 px: inside one cell of the crisp mosaic every pixel is the same.
        crisp = tiles[(10, 0)]
        if len({render.pixel_rgb(crisp, x, y) for x in range(14, 60, 7) for y in range(14, 60, 7)}) != 1:
            raise RuntimeError("cell 10 / soft 0 is not a flat cell")
        # Fully soft: neighbouring pixels across a cell edge differ only a little.
        soft = tiles[(4, 10)]
        jumps = max(max(abs(p - q) for p, q in zip(render.pixel_rgb(soft, x, 40), render.pixel_rgb(soft, x + 1, 40)))
                    for x in range(12, 280))
        crisp_jumps = max(max(abs(p - q) for p, q in zip(render.pixel_rgb(tiles[(4, 0)], x, 40),
                                                          render.pixel_rgb(tiles[(4, 0)], x + 1, 40)))
                          for x in range(12, 280))
        if not jumps < crisp_jumps:
            raise RuntimeError("softness 10 does not smooth the cells (max step %d vs %d)" % (jumps, crisp_jumps))
        copy = BlurShape(a=(0, 0), b=(5, 5), cell=7, smooth=3).clone()
        if (copy.cell, copy.smooth, BlurShape().cell_pixels(), BlurShape(cell=10).cell_pixels()) != (7, 3, 16, 64):
            raise RuntimeError("clone/cell_pixels")
        return "%d tiles, max step crisp %d / soft %d" % (len(tiles), crisp_jumps, jumps)

    def test_stitch(self):
        """Synthetic scrolling page with a sticky header and footer, viewed through a 600px viewport."""
        from .stitcher import ADDED, NO_MOVEMENT, ScrollStitcher

        page_h, view_h, header, footer, width = 2600, 600, 70, 50, 800
        page = sample_image(width, page_h, 44, 2)
        stitcher = ScrollStitcher()
        last = page_h - (view_h - header - footer) - header
        offsets = [0, 230, 460, 700, 950, 1200, 1450, 1700, 1950, last, last]
        outcomes = []
        for off in offsets:
            frame = viewport_frame(page, off, width, view_h, header, footer)
            if stitcher.frame_count == 0:
                stitcher.add_first(frame)
                outcomes.append("first")
                continue
            o = stitcher.add(frame)
            outcomes.append(o)
            if o == NO_MOVEMENT:
                break
        result = stitcher.compose()
        result.write_to_png(os.path.join(self.outdir, "stitch.png"))
        expected = page_h + footer
        line = "%s | height=%d expected=%d" % (" ".join(outcomes), stitcher.total_height, expected)
        self.log("stitch: " + line)
        stitcher.dispose_frames()
        self._stitch_result = result
        if stitcher.total_height != expected or result.get_height() != expected:
            raise RuntimeError("height %d != expected %d" % (stitcher.total_height, expected))
        return "height %d, %d frames added" % (stitcher.total_height, outcomes.count(ADDED))

    def test_scroll_session(self):
        """The scrolling-capture state machine on the same synthetic page: scroll(n) moves the page by
        n * 120 px (clamped at the end), grab_frame() returns the viewport, schedule() queues the step
        and the loop below runs it at once (no real timers)."""
        from .scrollcapture import ScrollStateMachine

        page_h, view_h, header, footer, width = 2600, 600, 70, 50, 800
        page = sample_image(width, page_h, 44, 2)
        last = page_h - (view_h - header - footer) - header
        state = {"off": 0, "result": None, "done": 0}
        scrolls, progress, queue = [], [], []

        def grab():
            return viewport_frame(page, state["off"], width, view_h, header, footer)

        def scroll(n):
            scrolls.append(n)
            state["off"] = max(0, min(last, state["off"] + n * 120))

        def done(image):
            state["done"] += 1
            state["result"] = image

        machine = ScrollStateMachine(view_h, grab, scroll, lambda ms, fn: queue.append(fn), done,
                                     progress=lambda n, h: progress.append((n, h)))
        machine.start()
        steps = 0
        while queue and steps < 2000:
            queue.pop(0)()
            steps += 1
        img = state["result"]
        if state["done"] != 1:
            raise RuntimeError("done() called %d times" % state["done"])
        if img is None:
            raise RuntimeError("no image (scrolls %s)" % scrolls)
        img.write_to_png(os.path.join(self.outdir, "scroll-session.png"))
        expected = page_h + footer
        self.log("scroll session: scrolls %s | frames %d | height=%d expected=%d"
                 % (scrolls, progress[-1][0] if progress else 0, img.get_height(), expected))
        if img.get_height() != expected or img.get_width() != width:
            raise RuntimeError("image %dx%d, expected %dx%d" % (img.get_width(), img.get_height(), width, expected))
        if state["off"] != last:
            raise RuntimeError("stopped at offset %d, expected the end of the page (%d)" % (state["off"], last))
        return "height %d, %d frames, %d steps" % (img.get_height(), progress[-1][0], steps)

    def test_scroll_plumbing(self):
        """Selection -> stream mapping and RemoteDesktop.Start parsing, without D-Bus."""
        from gi.repository import GLib
        from . import portal, render
        from .app import parse_args
        from .scrollcapture import (parse_start_response, pixels_to_logical, pointer_position,
                                    select_devices_options, selection_to_stream, surface_from_bgrx)

        if parse_args(["--capture", "scroll"])[:2] != ("capture", "scroll"):
            raise RuntimeError("--capture scroll not parsed")

        # Desktop: 1920x1080 + 1280x1024 logical, screenshot at 2x (6400x2160 pixels).
        info = (0, 0, 2.0, 2.0)
        total = (0, 0, 3200, 1080)
        logical = pixels_to_logical((4000, 200, 1000, 800), info)
        if logical != (2000.0, 100.0, 500.0, 400.0):
            raise RuntimeError("pixels_to_logical -> %s" % (logical,))

        results = {
            "devices": 2,
            "streams": [(57, {"position": (1920, 0), "size": (1280, 1024), "source_type": 1})],
            "restore_token": "token-123",
        }
        devices, streams, token = parse_start_response(results)
        if devices != 2 or token != "token-123" or len(streams) != 1:
            raise RuntimeError("parse_start_response -> %s %s %s" % (devices, streams, token))
        s = streams[0]
        if s["node"] != 57 or s["position"] != (1920, 0) or s["size"] != (1280, 1024):
            raise RuntimeError("stream %s" % s)
        # The same parsing on a real variant, as the portal sends it.
        v = GLib.Variant("a{sv}", {
            "devices": GLib.Variant("u", 2),
            "streams": GLib.Variant("a(ua{sv})", [(57, {"position": GLib.Variant("(ii)", (1920, 0)),
                                                        "size": GLib.Variant("(ii)", (1280, 1024))})]),
        })
        if parse_start_response(v.unpack())[1][0]["size"] != (1280, 1024):
            raise RuntimeError("variant parse")
        if parse_start_response({})[1] != [] or parse_start_response({})[0] is not None:
            raise RuntimeError("empty response")

        crop = selection_to_stream(logical, s, 2560, 2048, total)       # monitor streamed at 2x
        if crop != (160, 200, 1000, 800):
            raise RuntimeError("selection_to_stream -> %s" % (crop,))
        if pointer_position(logical, s, total) != (330.0, 300.0):
            raise RuntimeError("pointer_position -> %s" % (pointer_position(logical, s, total),))
        whole = {"node": 3, "position": None, "size": None}
        if selection_to_stream(logical, whole, 6400, 2160, total) != (4000, 200, 1000, 800):
            raise RuntimeError("whole-desktop stream -> %s" % (selection_to_stream(logical, whole, 6400, 2160, total),))
        if selection_to_stream((100, 100, 300, 300), s, 2560, 2048, total) is not None:
            raise RuntimeError("selection on the other monitor accepted")

        o1 = select_devices_options(1, "tok", "h1")
        o2 = select_devices_options(2, "tok", "h2")
        o3 = select_devices_options(2, None, "h3")
        if "persist_mode" in o1 or "restore_token" in o1 or o1["types"].get_uint32() != portal.DEVICE_POINTER:
            raise RuntimeError("version 1 options %s" % o1)
        if o2["persist_mode"].get_uint32() != 2 or o2["restore_token"].get_string() != "tok":
            raise RuntimeError("version 2 options %s" % o2)
        if "restore_token" in o3 or "persist_mode" not in o3:
            raise RuntimeError("no-token options %s" % o3)
        params = GLib.Variant("(oa{sv})", ("/org/freedesktop/portal/desktop/session/1_42/minisnap", o2))
        if params.get_type_string() != "(oa{sv})":
            raise RuntimeError("SelectDevices params %s" % params.get_type_string())

        # BGRx frame -> cropped cairo surface (one red pixel at (5, 2) in an 8x4 frame).
        w, h = 8, 4
        data = bytearray([200, 200, 200, 0] * (w * h))
        o = (2 * w + 5) * 4
        data[o:o + 4] = bytes([0, 0, 255, 0]) if sys.byteorder == "little" else bytes([0, 255, 0, 0])
        frame = surface_from_bgrx(bytes(data), w, h, None, (4, 1, 3, 2))
        if render.size(frame) != (3, 2) or render.pixel_rgb(frame, 1, 1) != (255, 0, 0):
            raise RuntimeError("surface_from_bgrx -> %s %s" % (render.size(frame), render.pixel_rgb(frame, 1, 1)))
        return "crop %s, pointer %s" % (crop, pointer_position(logical, s, total))

    def test_global_shortcuts(self):
        from gi.repository import GLib
        from . import portal
        from .globalshortcuts import (ACTIONS, GlobalShortcuts, bind_params, bind_variant, dispatch,
                                      parse_shortcuts, pretty_trigger, shortcut_list)

        v = bind_variant()
        if v.get_type_string() != "a(sa{sv})" or v.n_children() != len(shortcut_list()):
            raise RuntimeError("bind variant %s with %d items" % (v.get_type_string(), v.n_children()))
        sid, props = v.get_child_value(0).unpack()
        if sid != "capture-region" or props.get("preferred_trigger") != "CTRL+ALT+c" or not props.get("description"):
            raise RuntimeError("first shortcut %s %s" % (sid, props))
        ids = [s[0] for s in shortcut_list()]
        if ids != ["capture-region", "capture-full", "capture-scroll", "record", "ocr", "library"]:
            raise RuntimeError("shortcut ids %s" % ids)
        p = bind_params("/org/freedesktop/portal/desktop/session/1_42/s", "tok")
        if p.get_type_string() != "(oa(sa{sv})sa{sv})":
            raise RuntimeError("BindShortcuts params %s" % p.get_type_string())

        class FakeApp:
            selftest_dir = "fake"

            def __init__(self):
                self.calls = []

            def activate_action(self, name, param):
                self.calls.append(name)

        fake = FakeApp()
        expected = {"capture-region": "capture-region", "capture-full": "capture-full",
                    "capture-scroll": "capture-scroll", "record": "record", "ocr": "ocr", "library": "library"}
        for shortcut_id, action in expected.items():
            if dispatch(fake, shortcut_id) != action or fake.calls[-1] != action:
                raise RuntimeError("%s dispatched to %s" % (shortcut_id, fake.calls[-1:]))
            if not self.app.lookup_action(action):
                raise RuntimeError("the app has no action %s" % action)
        if dispatch(fake, "unknown") is not None or len(fake.calls) != len(expected):
            raise RuntimeError("unknown id dispatched")
        if set(ACTIONS) != set(ids):
            raise RuntimeError("ACTIONS / shortcut_list mismatch")

        # The Activated signal handler: only our own session is obeyed.
        gs = GlobalShortcuts(fake)
        if gs.available:
            raise RuntimeError("self-test must not look for the real portal")
        gs.session = "/org/freedesktop/portal/desktop/session/1_42/s"
        sig = GLib.Variant("(osta{sv})", (gs.session, "ocr", 1234, {}))
        gs._on_activated(None, ":1.5", portal.OBJECT_PATH, portal.GLOBAL_SHORTCUTS_IFACE, "Activated", sig)
        other = GLib.Variant("(osta{sv})", ("/org/freedesktop/portal/desktop/session/1_99/x", "record", 1, {}))
        gs._on_activated(None, ":1.5", portal.OBJECT_PATH, portal.GLOBAL_SHORTCUTS_IFACE, "Activated", other)
        if fake.calls[-1] != "ocr" or len(fake.calls) != len(expected) + 1:
            raise RuntimeError("Activated handler calls %s" % fake.calls)

        got = parse_shortcuts([("capture-region", {"description": "x", "trigger_description": "Ctrl+Alt+C"})])
        if got != {"capture-region": "Ctrl+Alt+C"}:
            raise RuntimeError("parse_shortcuts -> %s" % got)
        if pretty_trigger("CTRL+ALT+c") != "Ctrl+Alt+C" or pretty_trigger("LOGO+SHIFT+F5") != "Super+Shift+F5":
            raise RuntimeError("pretty_trigger")
        return "%d shortcuts, signature %s" % (v.n_children(), p.get_type_string())

    def test_screenshot_portal(self):
        """Registry first, a refused silent grab falls back to the screenshot UI (once per run), refusals
        are told apart from failed calls, and the stored answer can be deleted."""
        import cairo
        from gi.repository import Gio
        from . import capture, portal
        from .overlay import monitors_matching

        one = [(0, 0, 1600, 1000)]
        two = [(0, 0, 1920, 1080), (1920, 0, 1280, 1024)]
        for geoms, w, h, want in ((one, 1600, 1000, [0]), (one, 3200, 2000, [0]), (one, 800, 600, None),
                                  (one, 1600, 900, None), (two, 3200, 1080, [0, 1]), (two, 2560, 2048, [1]),
                                  (two, 1920, 1080, [0]), (two, 640, 480, None)):
            got = monitors_matching(geoms, w, h)
            if got != want:
                raise RuntimeError("monitors_matching(%s, %d, %d) = %s, expected %s" % (geoms, w, h, got, want))

        folder = tempfile.mkdtemp(prefix="minisnap-portal-")
        png = os.path.join(folder, "fake-portal.png")
        img = cairo.ImageSurface(cairo.FORMAT_ARGB32, 64, 40)
        cr = cairo.Context(img)
        cr.set_source_rgb(0.2, 0.5, 0.9)
        cr.paint()
        img.write_to_png(png)
        saved = (portal.BUS_NAME, portal.PERMISSION_STORE_NAME)
        fake = FakePortal(png)
        fake.start()
        portal.BUS_NAME, portal.PERMISSION_STORE_NAME = fake.NAME, fake.STORE_NAME
        portal.reset()
        capture.forget_denial()
        fallbacks = []
        try:
            surface, error, ui = self._portal_shot(capture, False, fallbacks)
            methods = [(c[1], c[2][1].get("interactive") if c[1] == "Screenshot" else c[2][0]) for c in fake.calls]
            if methods != [("Register", portal.APP_ID), ("Screenshot", False), ("Screenshot", True)]:
                raise RuntimeError("portal calls %s" % methods)
            if len({c[0] for c in fake.calls}) != 1 or not portal.registered:
                raise RuntimeError("calls not all on the registered connection: %s" % [c[0] for c in fake.calls])
            shared = Gio.bus_get_sync(Gio.BusType.SESSION, None).get_unique_name()
            if fake.calls[0][0] == shared:
                raise RuntimeError("registered on the shared connection")
            if surface is None or (surface.get_width(), surface.get_height()) != (64, 40) or not ui or error:
                raise RuntimeError("fallback result %s %s %s" % (surface, error, ui))
            if fallbacks != [1]:
                raise RuntimeError("fallback notices %s" % fallbacks)

            # Later captures in this run go straight to the screenshot UI, without a new notice.
            surface, error, ui = self._portal_shot(capture, False, fallbacks)
            if surface is None or not ui or fake.calls[-1][2][1].get("interactive") is not True or len(fake.calls) != 4:
                raise RuntimeError("second capture: %s %s, calls %d" % (surface, ui, len(fake.calls)))
            if fallbacks != [1]:
                raise RuntimeError("fallback notices %s" % fallbacks)

            fake.deny_all = True
            surface, error, ui = self._portal_shot(capture, True, fallbacks)
            if surface is not None or not isinstance(error, capture.Denied):
                raise RuntimeError("refusal reported as %r" % (error,))

            if not portal.reset_screenshot_permission():
                raise RuntimeError("DeletePermission failed")
            if fake.calls[-1][1:] != ("DeletePermission", ("screenshot", "screenshot", portal.APP_ID)):
                raise RuntimeError("permission reset call %s" % (fake.calls[-1][1:],))

            # After the reset (and an "Allow") the silent grab works again.
            capture.forget_denial()
            fake.deny_all = False
            fake.allow_silent = True
            surface, error, ui = self._portal_shot(capture, False, fallbacks)
            if surface is None or ui or fake.calls[-1][2][1].get("interactive") is not False:
                raise RuntimeError("silent grab after reset: %s %s" % (surface, ui))

            # A portal that is not there is an error, not a refusal, and no screenshot UI is tried.
            portal.BUS_NAME = "io.github.nnqbao.MiniSnap.SelfTest.Nobody"
            portal.reset()
            n = len(fake.calls)
            surface, error, ui = self._portal_shot(capture, False, fallbacks)
            if surface is not None or not error or isinstance(error, capture.Denied) or portal.registered:
                raise RuntimeError("missing portal reported as %r (registered %s)" % (error, portal.registered))
            if len(fake.calls) != n or fallbacks != [1]:
                raise RuntimeError("missing portal: %d calls, notices %s" % (len(fake.calls) - n, fallbacks))
        finally:
            portal.BUS_NAME, portal.PERMISSION_STORE_NAME = saved
            portal.reset()
            capture.forget_denial()
            fake.stop()
            shutil.rmtree(folder, ignore_errors=True)
        return "%d portal calls, registered connection, fallback and permission reset" % len(fake.calls)

    @staticmethod
    def _portal_shot(capture, interactive, fallbacks, timeout=15):
        from gi.repository import GLib
        box = []
        capture.take_screenshot(interactive, lambda s, e, ui: box.append((s, e, ui)),
                                on_fallback=lambda: fallbacks.append(1))
        tick = GLib.timeout_add(100, lambda: True)
        ctx = GLib.MainContext.default()
        deadline = time.time() + timeout
        try:
            while not box and time.time() < deadline:
                ctx.iteration(True)
        finally:
            GLib.source_remove(tick)
        if not box:
            raise RuntimeError("no answer from the fake portal")
        return box[0]

    def test_mapping(self):
        from .overlay import map_monitors
        mapping, info = map_monitors([(0, 0, 1920, 1080), (1920, 0, 1280, 1024)], 6400, 2160)
        if info[2] != 2.0 or info[3] != 2.0:
            raise RuntimeError("scale %s" % (info,))
        if mapping[1][1] != (3840, 0, 2560, 2048):
            raise RuntimeError("second monitor -> %s" % (mapping[1][1],))
        mapping, info = map_monitors([(-1280, 0, 1280, 1024), (0, 0, 1920, 1080)], 3200, 1080)
        if mapping[1][1] != (1280, 0, 1920, 1080) or info[0] != -1280:
            raise RuntimeError("negative origin -> %s %s" % (mapping, info))
        return "2 layouts"

    def test_crop(self):
        from .recorder import compute_crop, even_size
        l, t, r, b = compute_crop(3840, 2160, (100, 100, 641, 401), {"position": (0, 0), "size": (1920, 1080)}, None)
        w, h = 3840 - l - r, 2160 - t - b
        if (l, t) != (200, 200) or w % 2 or h % 2 or abs(w - 1282) > 2 or abs(h - 802) > 2:
            raise RuntimeError("crop %s -> %dx%d" % ((l, t, r, b), w, h))
        full = compute_crop(1921, 1081, None, {}, (0, 0, 1921, 1081))
        if full != (0, 0, 1, 1):
            raise RuntimeError("full-frame crop %s" % (full,))
        if even_size(641, 401) != (640, 400) or even_size(7680, 4320) != (3840, 2160):
            raise RuntimeError("even_size")
        return "crop %s" % ((l, t, r, b),)

    def test_updater(self):
        from . import updater
        cur = updater.CURRENT
        newer = updater.Release(tag="v%d.%d.0" % (cur[0], cur[1] + 1))
        same = updater.Release(tag="v" + updater.version_text(cur))
        older = updater.Release(tag="1.0.0")
        result = (updater.is_newer(newer), updater.is_newer(same), updater.is_newer(older))
        if result != (True, False, False):
            raise RuntimeError("is_newer(+1 minor, same, older) = %s" % (result,))
        if updater.parse_version("v2.0-beta") != (2, 0, 0) or updater.parse_version("garbage") is not None:
            raise RuntimeError("parse_version")

        # Release parsing, notes, how to update each kind of installation.
        r = updater.release_from_json(sample_release_json((cur[0], cur[1] + 1, 0)))
        deb = updater.asset_for(r, "deb")
        if not updater.is_newer(r) or deb is None or not deb["name"].endswith("_all.deb") \
                or updater.asset_for(r, "flatpak")["name"] != "MiniSnap.flatpak":
            raise RuntimeError("release_from_json / asset_for: %s" % [a["name"] for a in r.assets])
        notes = updater.clean_notes(r.notes)
        if notes != ("What's new\n• Screenshots on GNOME work again\n• Update from the app\n\n"
                     "Full Changelog: https://github.com/nnqbao/minisnap/compare/v1.0.0...v9.9.9"):
            raise RuntimeError("clean_notes -> %r" % notes)
        cmd = updater.terminal_command(r, "deb")
        if cmd != "wget -qO /tmp/minisnap.deb %s && sudo apt install -y /tmp/minisnap.deb" % deb["url"]:
            raise RuntimeError("deb command %r" % cmd)
        fu = updater.terminal_command(r, "flatpak", flatpak_user=True)
        fs = updater.terminal_command(r, "flatpak", flatpak_user=False)
        if "flatpak install -y --user --reinstall /tmp/MiniSnap.flatpak" not in fu or "--system" not in fs:
            raise RuntimeError("flatpak commands %r / %r" % (fu, fs))
        g = updater.terminal_command(r, "git", here="/home/u/src/minisnap/linux/minisnap")
        if g != "git -C /home/u/src/minisnap pull" or updater.terminal_command(r, "other") is not None:
            raise RuntimeError("git command %r" % g)
        if updater.install_kind(here=updater.DEB_LOCATION) != "deb" \
                or updater.install_kind(here="/nonexistent/a/b") != "other":
            raise RuntimeError("install_kind")
        folder = tempfile.mkdtemp(prefix="minisnap-update-")
        try:
            info = os.path.join(folder, "flatpak-info")
            with open(info, "w", encoding="utf-8") as f:
                f.write("[Application]\nname=io.github.nnqbao.MiniSnap\n\n[Instance]\n"
                        "app-path=/home/u/.local/share/flatpak/app/io.github.nnqbao.MiniSnap/x86_64/master/abc/files\n")
            if not updater.flatpak_user_install(info) or updater.flatpak_user_install(os.path.join(folder, "none")):
                raise RuntimeError("flatpak_user_install")
            if updater.expected_sha256(deb) != "ab" * 32 or updater.expected_sha256({"digest": "md5:12"}) is not None:
                raise RuntimeError("expected_sha256")
            blob = os.path.join(folder, "blob")
            with open(blob, "wb") as f:
                f.write(b"MiniSnap" * 10000)
            import hashlib
            if updater.sha256_of(blob) != hashlib.sha256(b"MiniSnap" * 10000).hexdigest():
                raise RuntimeError("sha256_of")
            if updater.install_argv("/x/m.deb") != ["pkexec", "/usr/bin/apt-get", "install", "-y", "/x/m.deb"]:
                raise RuntimeError("install_argv")
            checked = "dpkg-deb missing"
            if shutil.which("dpkg-deb"):
                pkg = os.path.join(folder, "pkg")
                os.makedirs(os.path.join(pkg, "DEBIAN"))
                with open(os.path.join(pkg, "DEBIAN", "control"), "w", encoding="utf-8") as f:
                    f.write("Package: minisnap\nVersion: 9.8.7\nArchitecture: all\nMaintainer: Test <t@example.com>\n"
                            "Description: test\n")
                built = os.path.join(folder, "m.deb")
                subprocess.run(["dpkg-deb", "--build", "--root-owner-group", pkg, built], check=True,
                               capture_output=True)
                updater.check_deb(built, (9, 8, 7))
                try:
                    updater.check_deb(built, (9, 8, 8))
                except RuntimeError:
                    pass
                else:
                    raise RuntimeError("check_deb accepted the wrong version")
                checked = "check_deb ok"
        finally:
            shutil.rmtree(folder, ignore_errors=True)
        detail = "current=%s, %s" % (updater.version_text(cur), checked)
        if os.environ.get("MINISNAP_SELFTEST_NETWORK") == "1":
            try:
                r = updater.fetch()
                detail += ", latest on GitHub: %s" % ("no releases (404)" if r is None else r.tag)
            except Exception as e:  # noqa: BLE001 - network is informational only
                detail += ", fetch skipped: %s" % e
        return detail

    def test_ocr(self):
        from . import ocr
        if ocr.tesseract_path() is None:
            return "skipped (tesseract not installed)"
        langs = ocr.available_languages()
        text, used = ocr.recognize(sample_image(900, 200, 3, 3))
        self.log("ocr [%s] (installed: %s): %s" % ("+".join(used), ",".join(langs), text.replace("\n", " / ")))
        if "vie" in langs:
            vi, _ = ocr.recognize(text_image("Chú thích tiếng Việt có dấu"))
            self.log("ocr vie sample: " + vi.replace("\n", " / "))
        if "line" not in text.lower():
            self.log("ocr: warning — expected the word 'Line' in the recognized text")
        return "%d characters" % len(text)

    def test_video(self):
        from . import _gi as gi_pins
        if not gi_pins.HAVE_GST:
            return "skipped (GStreamer introspection not installed)"
        from gi.repository import Gst
        from . import recorder
        recorder.ensure_gst()
        enc = recorder.choose_encoder()
        path = os.path.join(self.outdir, "test" + enc[2])
        if os.path.exists(path):
            os.unlink(path)
        tail, _ext = recorder.encode_tail(recorder.even_size(641, 401), path, enc)   # odd on purpose
        pipeline = Gst.parse_launch("videotestsrc num-buffers=45 is-live=false ! "
                                    "video/x-raw,width=641,height=401,framerate=30/1 ! " + tail)
        pipeline.set_state(Gst.State.PLAYING)
        bus = pipeline.get_bus()
        msg = bus.timed_pop_filtered(60 * Gst.SECOND, Gst.MessageType.EOS | Gst.MessageType.ERROR)
        pipeline.set_state(Gst.State.NULL)
        if msg is None:
            raise RuntimeError("timeout waiting for EOS")
        if msg.type == Gst.MessageType.ERROR:
            err, debug = msg.parse_error()
            raise RuntimeError("%s (%s)" % (err.message, debug))
        size = os.path.getsize(path) if os.path.exists(path) else 0
        if size <= 0:
            raise RuntimeError("empty output file")
        pw = "pipewiresrc " + ("present" if recorder.has_element("pipewiresrc") else "MISSING")
        return "%s, %d bytes, encoder %s, %s" % (os.path.basename(path), size, enc[0].split()[0], pw)

    def fill_library(self):
        """A couple of generated images (and a placeholder video) in the temporary library."""
        from . import paths
        folder = paths.images_folder()
        img = getattr(self, "_render_sample", None) or sample_image(900, 560, 9, 1)
        p1 = os.path.join(folder, "MiniSnap_2026-01-02_10-00-00.png")
        img.write_to_png(p1)
        p2 = os.path.join(folder, "MiniSnap_sample_page.png")
        sample_image(800, 1200, 18, 5).write_to_png(p2)
        now = time.time()
        os.utime(p1, (now - 3600, now - 3600))
        os.utime(p2, (now - 86400 * 3, now - 86400 * 3))
        p3 = os.path.join(paths.videos_folder(), "MiniSnap_recording.mp4")
        with open(p3, "wb") as f:
            f.write(b"\0" * 64)
        os.utime(p3, (now - 86400 * 40, now - 86400 * 40))
        n = len(paths.all_files())
        if n != 3:
            raise RuntimeError("library lists %d files, expected 3" % n)
        return "%d files in %s" % (n, os.environ.get("MINISNAP_LIBRARY"))

    def test_editor_ops(self):
        from . import render
        from .editor import EditorWindow
        ed = EditorWindow(self.app, sample_image(400, 300, 4, 6), None)
        ed.skip_save_prompt = True
        try:
            ed.load_shapes(sample_shapes()[:3])
            ed._apply_crop((50, 40, 200, 150))
            if render.size(ed.base) != (200, 150):
                raise RuntimeError("crop -> %s" % (render.size(ed.base),))
            ed.undo()
            if render.size(ed.base) != (400, 300):
                raise RuntimeError("undo -> %s" % (render.size(ed.base),))
            ed.redo()
            ed.set_tool("select")
            ed.set_color((30, 120, 230))
            ed.set_width(8)
            n = ed._next_step()
            flat = ed.flattened()
            return "crop/undo/redo ok, next step %d, flattened %dx%d" % ((n,) + render.size(flat))
        finally:
            ed.close()

    # ---------- Window screenshots ----------

    def _pump(self, gen):
        from gi.repository import GLib
        try:
            delay = next(gen)
        except StopIteration:
            self._finish()
            return False
        except Exception:  # noqa: BLE001
            self.failures += 1
            self.log("ui: FAILED: " + traceback.format_exc())
            self._finish()
            return False
        GLib.timeout_add(int(delay), self._pump, gen)
        return False

    def _ui_steps(self):
        from gi.repository import Adw
        from .i18n import L
        sm = Adw.StyleManager.get_default()
        for lang in ("vi", "en"):
            for scheme in ("light", "dark"):
                L.set(lang == "en", persist=False)
                sm.set_color_scheme(Adw.ColorScheme.FORCE_DARK if scheme == "dark" else Adw.ColorScheme.FORCE_LIGHT)
                yield 200
                for kind in WINDOW_KINDS:
                    name = "%s-%s-%s" % (kind, lang, scheme)
                    holder = {}
                    try:
                        delay = self._open(kind, holder)
                    except Exception as e:  # noqa: BLE001
                        self.failures += 1
                        self.log("window %s: FAILED: %s" % (name, e))
                        for line in traceback.format_exc().rstrip().splitlines():
                            self.log("    " + line)
                        self._close(holder)
                        continue
                    yield delay
                    if kind == "overlay":
                        try:
                            holder["overlay"].simulate_select((220, 160, 640, 360))
                        except Exception as e:  # noqa: BLE001
                            self.log("window %s: simulate_select raised %s" % (name, e))
                        yield 700
                    self.check("window " + name, lambda: snapshot_window(holder["window"],
                                                                         os.path.join(self.outdir, name + ".png")))
                    self._close(holder)
                    yield 150
        sm.set_color_scheme(Adw.ColorScheme.DEFAULT)

    def _open(self, kind, holder):
        """Creates and presents one window; returns how long to wait before capturing it (ms)."""
        from gi.repository import Gdk
        app = self.app
        if kind == "launcher":
            from .app import LauncherWindow
            win = LauncherWindow(app)
            delay = 700
        elif kind == "editor":
            from .editor import EditorWindow
            win = EditorWindow(app, sample_image(900, 560, 9, 4), None)
            win.skip_save_prompt = True
            shapes = sample_shapes()
            win.load_shapes([shapes[0], shapes[1], shapes[7], shapes[9]])
            delay = 1200
        elif kind == "editor-blur":
            # The blur tool swaps the stroke width for its cell size and softness sliders.
            from .editor import EditorWindow
            from .shapes import BLUR, BlurShape
            win = EditorWindow(app, sample_image(900, 560, 9, 4), None)
            win.skip_save_prompt = True
            win.load_shapes([BlurShape(a=(30, 20), b=(620, 260), cell=5, smooth=3)])
            win.set_tool(BLUR)
            if win.width_drop.get_visible() or not win.cell_scale.get_visible():
                raise RuntimeError("blur tool did not show its sliders")
            delay = 1200
        elif kind == "overlay":
            from .overlay import CaptureOverlay
            display = Gdk.Display.get_default()
            model = display.get_monitors()
            geoms = []
            for i in range(model.get_n_items()):
                g = model.get_item(i).get_geometry()
                geoms.append((g.x, g.y, g.width, g.height))
            if not geoms:
                geoms = [(0, 0, 1600, 1000)]
            tw = max(g[0] + g[2] for g in geoms) - min(g[0] for g in geoms)
            th = max(g[1] + g[3] for g in geoms) - min(g[1] for g in geoms)
            fake = sample_image(tw, th, max(8, th // 60), 7)   # synthetic background, never a real screen
            ov = CaptureOverlay(app, fake, lambda result: None, ask_mode=True)
            ov.show()
            holder["overlay"] = ov
            win = ov.views[0]
            delay = 400
        elif kind == "library":
            from .library import LibraryWindow
            win = LibraryWindow(app, lambda p: None, lambda p: None)
            delay = 1800
        elif kind == "about":
            from .about import make_about
            win = make_about(app, None)
            delay = 900
        elif kind == "shortcuts":
            from .shortcuts import ShortcutsWindow
            win = ShortcutsWindow(app)
            delay = 700
        elif kind == "shortcuts-portal":
            # As shown on desktops with the GlobalShortcuts portal (forced: no portal is called here).
            from .shortcuts import ShortcutsWindow
            win = ShortcutsWindow(app, portal_available=True)
            delay = 700
        elif kind == "scroll-status":
            from .scrollcapture import ScrollStatusWindow
            win = ScrollStatusWindow(app, None)
            win.update(7, 4210)
            delay = 500
        elif kind == "update":
            # A made-up newer release, as the .deb installation sees it (no network is used).
            from . import updater
            cur = updater.CURRENT
            release = updater.release_from_json(sample_release_json((cur[0], cur[1] + 1, 0)))
            win = updater.UpdateWindow(app, release, kind="deb", has_pkexec=True)
            if not win.update_btn.get_visible() or not win.cmd_box.get_visible():
                raise RuntimeError("update window without Update now / Terminal command")
            delay = 600
        else:
            raise ValueError(kind)
        holder["window"] = win
        if kind != "overlay":
            win.present()
        return delay

    def _close(self, holder):
        try:
            if "overlay" in holder:
                holder["overlay"].cancel()
            elif "window" in holder:
                holder["window"].close()
        except Exception as e:  # noqa: BLE001
            self.log("close: %s" % e)
