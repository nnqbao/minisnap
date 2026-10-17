"""Annotation editor (port of windows/src/EditorForm.cs).

Tools on the left of the top row, three big Copy / Save / Save as buttons on the right, colours,
sizes, undo/redo and zoom on the second row, a Cairo canvas in the middle and a status line at the
bottom. Shapes stay vector objects until the image is copied or saved.

Zoom is in image pixels per *device* pixel, so 100% shows a HiDPI screenshot pixel-for-pixel; the
DrawingArea's Cairo context is in logical units, so drawing scales by zoom / device scale.
"""

import math
import os
import time

import cairo

from . import _gi  # noqa: F401
from gi.repository import Adw, Gdk, Gio, GLib, Gtk, Pango

from . import icons, paths, render, shapes, theme
from .i18n import L
from .shapes import (ARROW, BLUR, CROP, ELLIPSE, HIGHLIGHT, LINE, PEN, RECT, SELECT, STEP, TEXT,
                     BlurShape, PenShape, StepShape, TextShape, TwoPointShape)

PALETTE = [(232, 38, 38), (255, 140, 0), (255, 214, 0), (40, 170, 70),
           (30, 120, 230), (150, 70, 200), (30, 30, 30), (255, 255, 255)]
WIDTHS = [2, 3, 5, 8, 12, 16]
MAX_CANVAS_PIXELS = 16000   # keep the canvas widget inside GPU texture limits
MARGIN = 24


class EditorWindow(Adw.ApplicationWindow):
    _counter = 0

    def __init__(self, app, image, path=None):
        super().__init__(application=app)
        EditorWindow._counter += 1
        self.app = app
        self.base = render.copy_surface(image)
        self.cache = None
        self.shapes = []
        self.undo_stack = []
        self.redo_stack = []
        self.file_path = path
        self.dirty = False
        self.skip_save_prompt = False
        self._closing_ok = False

        self.tool = ARROW
        self.color = PALETTE[0]
        self.width = 5.0
        self.zoom = 1.0
        self._fitted = False
        self._pending_scroll = None
        self._pointer = None

        self.current = None
        self.selected = None
        self.mouse_down = False
        self.moved_selected = False
        self.cropping = False
        self.down_pt = self.last_pt = (0.0, 0.0)
        self.crop_rect = (0, 0, 0, 0)
        self._last_press = (0, 0.0, 0.0)

        self.text_view = None
        self.text_pos = (0, 0)
        self.text_color = self.color
        self.text_width = self.width
        self.editing_text = None
        self.editing_index = 0
        self._text_css_name = "ms-text-edit-%d" % EditorWindow._counter
        self._text_provider = None

        self._build_ui()
        self._rerender()
        self._size_to_image()
        self._update_title()
        self._update_tool_buttons()
        self._update_swatches()
        self._update_undo_buttons()

        self.connect("close-request", self._on_close_request)
        self._dark_handler = Adw.StyleManager.get_default().connect("notify::dark", lambda *_: self.canvas.queue_draw())

    # ---------- UI construction ----------

    def _build_ui(self):
        view = Adw.ToolbarView()
        header = Adw.HeaderBar()
        self.title_widget = Adw.WindowTitle()
        header.set_title_widget(self.title_widget)
        view.add_top_bar(header)

        # Row 1: tools (left, scrollable when narrow) + big buttons (right).
        row1 = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=6)
        row1.add_css_class("ms-tool-row")
        tools_box = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=2)
        self.tool_buttons = {}
        self.tool_keys = {}
        group = None
        for (tool, glyph, label, key, tip) in (
            (SELECT, "select", L.t("Chọn"), "v", L.t("Chọn, kéo để di chuyển, Delete để xoá. Nháy đúp vào chữ để sửa")),
            (ARROW, "arrow", L.t("Mũi tên"), "a", L.t("Vẽ mũi tên (giữ Shift để thẳng góc 45°)")),
            (RECT, "rect", L.t("Khung"), "r", L.t("Vẽ khung chữ nhật (Shift: hình vuông)")),
            (ELLIPSE, "ellipse", L.t("Elip"), "e", L.t("Vẽ elip (Shift: hình tròn)")),
            (LINE, "line", L.t("Đường"), "l", L.t("Vẽ đường thẳng")),
            (PEN, "pen", L.t("Bút vẽ"), "p", L.t("Vẽ tự do")),
            (HIGHLIGHT, "highlight", L.t("Tô sáng"), "h", L.t("Tô sáng một vùng (nên chọn màu vàng)")),
            (TEXT, "text", L.t("Chữ"), "t", L.t("Bấm để gõ chữ. Enter để xong, Shift+Enter xuống dòng")),
            (BLUR, "blur", L.t("Làm mờ"), "b", L.t("Làm mờ thông tin nhạy cảm")),
            (STEP, "step", L.t("Đánh số"), "n", L.t("Bấm để đặt số bước 1, 2, 3...")),
            (CROP, "crop", L.t("Cắt ảnh"), "c", L.t("Kéo chọn vùng muốn giữ lại")),
        ):
            b = Gtk.ToggleButton()
            b.set_child(self._icon_label(glyph, label))
            b.add_css_class("flat")
            b.add_css_class("ms-tool-button")
            b.set_tooltip_text("%s (%s)" % (tip, key.upper()))
            b.set_focus_on_click(False)
            if group is None:
                group = b
            else:
                b.set_group(group)
            b.connect("toggled", self._on_tool_toggled, tool)
            tools_box.append(b)
            self.tool_buttons[tool] = b
            self.tool_keys[key] = tool
        tools_box.append(Gtk.Separator(orientation=Gtk.Orientation.VERTICAL))
        for (glyph, label, tip, cb) in (
            ("ocr", L.t("Trích chữ"), L.t("Nhận dạng chữ trong ảnh (OCR) và sao chép"), self._run_ocr),
            ("library", L.t("Thư viện"), L.t("Mở thư viện ảnh và video"), lambda: self.app.show_library()),
            ("capture", L.t("Chụp mới"), L.t("Chụp ảnh mới"), lambda: self.app.begin_capture("region")),
        ):
            b = Gtk.Button()
            b.set_child(self._icon_label(glyph, label))
            b.add_css_class("flat")
            b.add_css_class("ms-tool-button")
            b.set_tooltip_text(tip)
            b.set_focus_on_click(False)
            b.connect("clicked", lambda _b, f=cb: f())
            tools_box.append(b)
        tools_scroll = Gtk.ScrolledWindow()
        tools_scroll.set_policy(Gtk.PolicyType.AUTOMATIC, Gtk.PolicyType.NEVER)
        tools_scroll.set_propagate_natural_height(True)
        tools_scroll.set_propagate_natural_width(True)
        tools_scroll.set_hexpand(True)
        tools_scroll.set_child(tools_box)
        row1.append(tools_scroll)

        self.copy_btn = self._big_button(L.t("Sao chép"), L.t("✓ Đã chép"), "copy", "ms-blue", theme.BLUE,
                                         L.t("Sao chép ảnh vào clipboard để dán (Ctrl+C)"), self.copy_to_clipboard)
        self.save_btn = self._big_button(L.t("Lưu"), L.t("✓ Đã lưu"), "save", "ms-green", theme.GREEN,
                                         L.t("Lưu ảnh (Ctrl+S)"), lambda: self.save(False))
        self.save_as_btn = self._big_button(L.t("Lưu thành..."), L.t("✓ Đã lưu"), "saveas", "ms-gray", theme.GRAY,
                                            L.t("Lưu thành file khác (Ctrl+Shift+S)"), lambda: self.save(True))
        for b in (self.copy_btn, self.save_btn, self.save_as_btn):
            row1.append(b)
        view.add_top_bar(row1)

        # Row 2: colours, size, undo/redo, folder, zoom.
        row2 = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=2)
        row2.add_css_class("ms-props-row")
        row2.append(Gtk.Label(label=L.t("Màu:")))
        self.swatches = []
        for c in PALETTE:
            b = Gtk.Button()
            sw = icons.Swatch(c, 20)
            b.set_child(sw)
            b.add_css_class("flat")
            b.add_css_class("ms-swatch")
            b.set_tooltip_text("#%02X%02X%02X" % c)
            b.set_focus_on_click(False)
            b.connect("clicked", lambda _b, cc=c: self.set_color(cc))
            row2.append(b)
            self.swatches.append((c, sw))
        more = Gtk.Button()
        more_box = Gtk.Box(spacing=4)
        self.custom_swatch = icons.Swatch(self.color, 20)
        more_box.append(self.custom_swatch)
        more_box.append(Gtk.Label(label=L.t("Khác...")))
        more.set_child(more_box)
        more.add_css_class("flat")
        more.set_tooltip_text(L.t("Chọn màu khác"))
        more.set_focus_on_click(False)
        more.connect("clicked", lambda *_: self.pick_color())
        row2.append(more)
        row2.append(Gtk.Separator(orientation=Gtk.Orientation.VERTICAL))
        width_label = Gtk.Label(label=L.t("Độ dày:"))
        row2.append(width_label)
        self.width_drop = Gtk.DropDown.new_from_strings([str(w) for w in WIDTHS])
        self.width_drop.set_selected(WIDTHS.index(5))
        self.width_drop.set_focus_on_click(False)
        self._width_guard = False
        self.width_drop.connect("notify::selected", self._on_width_selected)
        row2.append(self.width_drop)
        self.width_widgets = [width_label, self.width_drop]
        # The blur tool shows its own settings in place of the stroke width.
        self.blur_cell, self.blur_smooth = 2, 0
        self._blur_guard = False
        self._blur_last_change = 0.0
        self.blur_widgets = []
        self.cell_scale, self.cell_value = self._blur_slider(
            row2, L.t("Kích thước ô:"), L.t("Kích thước ô mờ: càng lớn càng giống ô mosaic to"), 1, BlurShape.MAX_CELL, self.blur_cell)
        self.smooth_scale, self.smooth_value = self._blur_slider(
            row2, L.t("Độ mờ:"), L.t("Độ mờ: 0 là ô vuông sắc nét, 10 là mờ mịn"), 0, BlurShape.MAX_SMOOTH, self.blur_smooth)
        for wdg in self.blur_widgets:
            wdg.set_visible(False)
        row2.append(Gtk.Separator(orientation=Gtk.Orientation.VERTICAL))
        self.undo_btn = self._small_button("undo", None, L.t("Hoàn tác") + " (Ctrl+Z)", self.undo)
        self.redo_btn = self._small_button("redo", None, L.t("Làm lại") + " (Ctrl+Y)", self.redo)
        row2.append(self.undo_btn)
        row2.append(self.redo_btn)
        row2.append(Gtk.Separator(orientation=Gtk.Orientation.VERTICAL))
        row2.append(self._small_button("folder", None, L.t("Mở thư mục ảnh đã chụp"),
                                       lambda: paths.open_folder(paths.images_folder())))
        row2.append(Gtk.Separator(orientation=Gtk.Orientation.VERTICAL))
        row2.append(self._small_button("zoomout", None, L.t("Thu nhỏ") + " (Ctrl+-)", lambda: self.set_zoom(self.zoom / 1.25)))
        self.zoom_label = Gtk.Label(label="100%")
        self.zoom_label.add_css_class("ms-zoom-label")
        self.zoom_label.add_css_class("numeric")
        row2.append(self.zoom_label)
        row2.append(self._small_button("zoomin", None, L.t("Phóng to") + " (Ctrl++)", lambda: self.set_zoom(self.zoom * 1.25)))
        row2.append(self._small_button(None, L.t("Vừa"), L.t("Vừa cửa sổ") + " (Ctrl+0)", self.fit_zoom))
        row2.append(self._small_button(None, "1:1", L.t("Kích thước thật") + " (Ctrl+1)", lambda: self.set_zoom(1.0)))
        view.add_top_bar(row2)
        view.set_top_bar_style(Adw.ToolbarStyle.RAISED_BORDER)

        # Canvas.
        self.canvas = Gtk.DrawingArea()
        self.canvas.set_draw_func(self._draw)
        self.canvas.set_focusable(True)
        self.canvas.set_hexpand(True)
        self.canvas.set_vexpand(True)
        self.canvas.connect("resize", self._on_canvas_resize)
        self.overlay = Gtk.Overlay()
        self.overlay.set_child(self.canvas)
        self.scroller = Gtk.ScrolledWindow()
        self.scroller.set_hexpand(True)
        self.scroller.set_vexpand(True)
        self.scroller.set_child(self.overlay)
        view.set_content(self.scroller)

        drag = Gtk.GestureDrag()
        drag.set_button(1)
        drag.connect("drag-begin", self._on_drag_begin)
        drag.connect("drag-update", self._on_drag_update)
        drag.connect("drag-end", self._on_drag_end)
        self.canvas.add_controller(drag)
        motion = Gtk.EventControllerMotion()
        motion.connect("motion", self._on_motion)
        motion.connect("leave", lambda *_: (self.pos_label.set_text(""), setattr(self, "_pointer", None)))
        self.canvas.add_controller(motion)
        scroll = Gtk.EventControllerScroll.new(Gtk.EventControllerScrollFlags.VERTICAL)
        scroll.connect("scroll", self._on_scroll)
        self.canvas.add_controller(scroll)

        keys = Gtk.EventControllerKey()
        keys.set_propagation_phase(Gtk.PropagationPhase.CAPTURE)
        keys.connect("key-pressed", self._on_key)
        self.add_controller(keys)

        # Status line.
        status = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=16)
        status.add_css_class("ms-statusbar")
        self.size_label = Gtk.Label(xalign=0)
        self.pos_label = Gtk.Label(xalign=0)
        self.pos_label.set_width_chars(12)
        self.info_label = Gtk.Label(xalign=0)
        self.info_label.set_hexpand(True)
        self.info_label.set_ellipsize(Pango.EllipsizeMode.END)
        status.append(self.size_label)
        status.append(self.pos_label)
        status.append(self.info_label)
        view.add_bottom_bar(status)
        view.set_bottom_bar_style(Adw.ToolbarStyle.RAISED_BORDER)
        self._show_hint()

        self.set_content(view)

    def _icon_label(self, glyph, label):
        box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=1)
        box.append(icons.Glyph(glyph, 24))
        box.append(Gtk.Label(label=label))
        return box

    def _small_button(self, glyph, text, tip, cb):
        b = Gtk.Button()
        if glyph is not None:
            b.set_child(icons.Glyph(glyph, 18))
        else:
            b.set_label(text)
        b.add_css_class("flat")
        b.set_tooltip_text(tip)
        b.set_focus_on_click(False)
        b.connect("clicked", lambda *_: cb())
        return b

    def _big_button(self, text, done_text, glyph, css, back, tip, cb):
        b = Gtk.Button()
        box = Gtk.Box(spacing=8)
        box.append(icons.Glyph(glyph, 22, ink=(255, 255, 255), paper=back, mono=True))
        label = Gtk.Label(label=text)
        label.set_width_chars(max(len(text), len(done_text)))
        box.append(label)
        b.set_child(box)
        b.add_css_class("ms-big-button")
        b.add_css_class(css)
        b.set_tooltip_text(tip)
        b.set_valign(Gtk.Align.CENTER)
        b.set_focus_on_click(False)
        b.connect("clicked", lambda *_: cb())
        b._ms_label = label
        b._ms_text = text
        b._ms_timer = 0
        return b

    def _flash(self, b, text):
        """Briefly shows "✓ Đã lưu" / "✓ Đã chép" on a big button so a click visibly did something."""
        b._ms_label.set_text(text)
        if b._ms_timer:
            GLib.source_remove(b._ms_timer)

        def restore():
            b._ms_timer = 0
            b._ms_label.set_text(b._ms_text)
            return False
        b._ms_timer = GLib.timeout_add(1500, restore)

    def _size_to_image(self):
        ds = self._device_scale()
        mw, mh = 1600, 1000
        display = Gdk.Display.get_default()
        if display is not None:
            model = display.get_monitors()
            if model.get_n_items() > 0:
                g = model.get_item(0).get_geometry()
                mw, mh = g.width, g.height
        min_w = min(1180, int(mw * 0.95))
        w = min(int(mw * 0.9), max(min_w, int(self.base.get_width() / ds) + 70))
        h = min(int(mh * 0.9), max(480, int(self.base.get_height() / ds) + 260))
        self.set_default_size(w, h)

    def _show_hint(self):
        self.info_label.set_text(L.t("Kéo để vẽ • Shift: giữ thẳng/vuông • Ctrl+lăn chuột: phóng to • Ảnh đã tự lưu và sao chép vào clipboard"))

    def _update_title(self):
        name = os.path.basename(self.file_path) if self.file_path else L.t("Ảnh chưa lưu")
        title = ("● " if self.dirty else "") + name
        self.set_title(title + " — MiniSnap")
        self.title_widget.set_title(title)
        self.title_widget.set_subtitle("MiniSnap")

    def _update_tool_buttons(self):
        for t, b in self.tool_buttons.items():
            if b.get_active() != (t == self.tool):
                b.set_active(t == self.tool)
        self.canvas.set_cursor_from_name("default" if self.tool == SELECT else "text" if self.tool == TEXT else "crosshair")
        self._update_blur_props()

    # ---------- Blur settings ----------

    def _blur_slider(self, row, title, tip, lo, hi, value):
        label = Gtk.Label(label=title)
        label.set_tooltip_text(tip)
        scale = Gtk.Scale.new_with_range(Gtk.Orientation.HORIZONTAL, lo, hi, 1)
        scale.set_draw_value(False)
        scale.set_round_digits(0)
        scale.set_value(value)
        scale.set_size_request(110, -1)
        scale.set_valign(Gtk.Align.CENTER)
        scale.set_tooltip_text(tip)
        scale.set_focus_on_click(False)
        scale.connect("value-changed", self._on_blur_slider)
        shown = Gtk.Label(label=str(value))
        shown.set_width_chars(2)
        shown.set_xalign(0)
        shown.add_css_class("numeric")
        for wdg in (label, scale, shown):
            row.append(wdg)
            self.blur_widgets.append(wdg)
        return scale, shown

    def _selected_blur(self):
        return self.selected if self.tool == SELECT and isinstance(self.selected, BlurShape) else None

    def _update_blur_props(self):
        """Shows the blur settings instead of the stroke width while the blur tool, or a blurred area, is active."""
        if not getattr(self, "blur_widgets", None):
            return
        sel = self._selected_blur()
        show = self.tool == BLUR or sel is not None
        self._blur_guard = True
        self.cell_scale.set_value(sel.cell if sel is not None else self.blur_cell)
        self.smooth_scale.set_value(sel.smooth if sel is not None else self.blur_smooth)
        self._blur_guard = False
        self.cell_value.set_text(str(int(self.cell_scale.get_value())))
        self.smooth_value.set_text(str(int(self.smooth_scale.get_value())))
        if self.blur_widgets[0].get_visible() == show:
            return
        for wdg in self.blur_widgets:
            wdg.set_visible(show)
        for wdg in self.width_widgets:
            wdg.set_visible(not show)

    def _on_blur_slider(self, _scale):
        if self._blur_guard:
            return
        cell, smooth = int(round(self.cell_scale.get_value())), int(round(self.smooth_scale.get_value()))
        self.cell_value.set_text(str(cell))
        self.smooth_value.set_text(str(smooth))
        self.blur_cell, self.blur_smooth = cell, smooth
        sel = self._selected_blur()
        if sel is None or (sel.cell == cell and sel.smooth == smooth):
            return
        # Changes less than a second apart (one drag of a slider) share one undo step.
        now = time.monotonic()
        if now - self._blur_last_change > 1.0:
            self._push_undo()
        self._blur_last_change = now
        sel.cell, sel.smooth = cell, smooth
        self._rerender()

    def _update_swatches(self):
        matched = False
        for c, sw in self.swatches:
            on = tuple(c) == tuple(self.color)
            matched |= on
            sw.update(ring=on)
        self.custom_swatch.update(rgb=self.color, ring=not matched)

    def _update_undo_buttons(self):
        self.undo_btn.set_sensitive(bool(self.undo_stack))
        self.redo_btn.set_sensitive(bool(self.redo_stack))

    # ---------- Rendering, zoom, layout ----------

    def _device_scale(self):
        native = self.get_native()
        surface = native.get_surface() if native is not None else None
        if surface is not None and hasattr(surface, "get_scale"):
            try:
                return max(0.5, float(surface.get_scale()))
            except Exception:  # noqa: BLE001
                pass
        return float(max(1, self.get_scale_factor()))

    def _view_scale(self):
        """Logical units per image pixel."""
        return self.zoom / self._device_scale()

    def _rerender(self):
        self.cache = render.render(self.base, self.shapes)
        self.size_label.set_text("%d × %d px" % (self.base.get_width(), self.base.get_height()))
        self.canvas.queue_draw()
        self._update_blur_props()

    def _layout_canvas(self):
        s = self._view_scale()
        self.canvas.set_content_width(int(math.ceil(self.base.get_width() * s + 2 * MARGIN)))
        self.canvas.set_content_height(int(math.ceil(self.base.get_height() * s + 2 * MARGIN)))
        self.canvas.queue_draw()

    def _image_offset(self):
        s = self._view_scale()
        w, h = self.canvas.get_width(), self.canvas.get_height()
        return ((w - self.base.get_width() * s) / 2.0, (h - self.base.get_height() * s) / 2.0)

    def to_image(self, x, y):
        ox, oy = self._image_offset()
        s = self._view_scale()
        return ((x - ox) / s, (y - oy) / s)

    def to_canvas(self, p):
        ox, oy = self._image_offset()
        s = self._view_scale()
        return (p[0] * s + ox, p[1] * s + oy)

    def set_zoom(self, z, anchor=None):
        """anchor: point in the visible viewport (logical) that keeps its image position."""
        self._commit_text()
        # The canvas widget is image * zoom device pixels wide; keep it inside GPU texture limits.
        max_zoom = min(8.0, float(MAX_CANVAS_PIXELS) / max(self.base.get_width(), self.base.get_height()))
        z = max(0.05, min(max_zoom, z))
        hadj, vadj = self.scroller.get_hadjustment(), self.scroller.get_vadjustment()
        if anchor is None:
            anchor = (self.scroller.get_width() / 2.0, self.scroller.get_height() / 2.0)
        img_pt = self.to_image(anchor[0] + hadj.get_value(), anchor[1] + vadj.get_value())
        self.zoom = z
        self._pending_scroll = (img_pt, anchor)
        self._layout_canvas()
        self.zoom_label.set_text("%d%%" % round(self.zoom * 100))
        GLib.idle_add(self._apply_pending_scroll)

    def _apply_pending_scroll(self):
        if self._pending_scroll is None:
            return False
        img_pt, anchor = self._pending_scroll
        self._pending_scroll = None
        cx, cy = self.to_canvas(img_pt)
        hadj, vadj = self.scroller.get_hadjustment(), self.scroller.get_vadjustment()
        hadj.set_value(max(0, min(cx - anchor[0], hadj.get_upper() - hadj.get_page_size())))
        vadj.set_value(max(0, min(cy - anchor[1], vadj.get_upper() - vadj.get_page_size())))
        return False

    def fit_zoom(self):
        ds = self._device_scale()
        aw = max(50, self.scroller.get_width() - 2 * MARGIN)
        ah = max(50, self.scroller.get_height() - 2 * MARGIN)
        z = min(1.0, min(aw * ds / self.base.get_width(), ah * ds / self.base.get_height()))
        self.set_zoom(z)

    def _on_canvas_resize(self, area, w, h):
        if not self._fitted and self.scroller.get_width() > 0:
            self._fitted = True
            GLib.idle_add(lambda: (self.fit_zoom(), False)[1])
        elif self._pending_scroll is not None:
            GLib.idle_add(self._apply_pending_scroll)

    def _draw(self, area, cr, width, height):
        cr.set_source_rgb(*theme.canvas_rgb())
        cr.paint()
        s = self._view_scale()
        ox, oy = self._image_offset()
        iw, ih = self.base.get_width() * s, self.base.get_height() * s
        cr.set_source_rgba(0, 0, 0, 70 / 255.0)
        cr.rectangle(ox + 3, oy + 3, iw, ih)
        cr.fill()

        cr.save()
        cr.rectangle(ox, oy, iw, ih)
        cr.clip()
        cr.translate(ox, oy)
        cr.scale(s, s)
        cr.set_source_surface(self.cache, 0, 0)
        cr.get_source().set_filter(cairo.FILTER_NEAREST if self.zoom >= 1 else cairo.FILTER_GOOD)
        cr.paint()
        cr.restore()

        cr.save()
        cr.translate(ox, oy)
        cr.scale(s, s)
        if self.current is not None:
            self.current.draw(cr)
        if self.selected is not None and self.tool == SELECT:
            b = shapes.inflate(self.selected.bounds(), 3 / s)
            cr.set_source_rgb(30 / 255.0, 140 / 255.0, 1)
            cr.set_line_width(1.5 / s)
            cr.set_dash([4 / s, 3 / s])
            cr.rectangle(*b)
            cr.stroke()
            cr.set_dash([])
        if self.cropping:
            cr.rectangle(0, 0, self.base.get_width(), self.base.get_height())
            cr.rectangle(*self.crop_rect)
            cr.set_fill_rule(cairo.FILL_RULE_EVEN_ODD)
            cr.set_source_rgba(0, 0, 0, 140 / 255.0)
            cr.fill()
            cr.set_fill_rule(cairo.FILL_RULE_WINDING)
            cr.set_source_rgb(1, 1, 1)
            cr.set_line_width(1.5 / s)
            cr.set_dash([4 / s, 3 / s])
            cr.rectangle(*self.crop_rect)
            cr.stroke()
            cr.set_dash([])
        cr.restore()

    # ---------- Mouse ----------

    def _shift(self, gesture):
        return bool(gesture.get_current_event_state() & Gdk.ModifierType.SHIFT_MASK)

    def _is_double_click(self, x, y):
        settings = Gtk.Settings.get_default()
        dbl_time = settings.get_property("gtk-double-click-time") if settings else 400
        dbl_dist = settings.get_property("gtk-double-click-distance") if settings else 5
        now = GLib.get_monotonic_time() / 1000.0
        last_t, lx, ly = self._last_press
        self._last_press = (now, x, y)
        return now - last_t <= dbl_time and abs(x - lx) <= dbl_dist and abs(y - ly) <= dbl_dist

    def _on_drag_begin(self, gesture, x, y):
        self.canvas.grab_focus()
        double = self._is_double_click(x, y)
        if self.text_view is not None:
            self._commit_text()
            self._ignore_drag = True
            return
        self._ignore_drag = False
        p = self.to_image(x, y)
        self.mouse_down = True
        self.down_pt = self.last_pt = p
        t = self.tool
        if t == SELECT:
            self.selected = self._hit_test(p)
            self._update_blur_props()
            self.moved_selected = False
            if double and isinstance(self.selected, TextShape):
                self.mouse_down = False
                self._begin_edit_shape(self.selected)
            self.canvas.queue_draw()
        elif t == TEXT:
            self.mouse_down = False
            hit = self._hit_test(p)
            if isinstance(hit, TextShape):
                self._begin_edit_shape(hit)
            else:
                self._begin_text_edit(p, "", self.color, self.width)
        elif t == STEP:
            self.mouse_down = False
            self._push_undo()
            self.shapes.append(StepShape(center=p, number=self._next_step(), color=self.color, width=self.width))
            self._rerender()
        elif t == CROP:
            self.cropping = True
            self.crop_rect = (p[0], p[1], 0, 0)
        elif t == PEN:
            self.current = PenShape(points=[p], color=self.color, width=self.width)
            self.canvas.queue_draw()
        else:
            s = shapes.create_two_point(t, self.color, self.width)
            if isinstance(s, BlurShape):
                s.cell, s.smooth = self.blur_cell, self.blur_smooth
            s.a = s.b = p
            self.current = s

    def _on_drag_update(self, gesture, dx, dy):
        if getattr(self, "_ignore_drag", False) or not self.mouse_down:
            return
        ok, sx, sy = gesture.get_start_point()
        p = self.to_image(sx + dx, sy + dy)
        self._show_pos(p)
        shift = self._shift(gesture)
        t = self.tool
        if t == SELECT:
            if self.selected is None:
                return
            if not self.moved_selected:
                if shapes.dist(p, self.down_pt) * self._view_scale() < 3:
                    return
                self._push_undo()
                self.moved_selected = True
            self.selected.offset(p[0] - self.last_pt[0], p[1] - self.last_pt[1])
            self.last_pt = p
            self._rerender()
        elif t == CROP:
            end = shapes.constrain(self.down_pt, p, t) if shift else p
            r = shapes.norm(self.down_pt, end)
            self.crop_rect = shapes.intersect(r, (0, 0, self.base.get_width(), self.base.get_height()))
            self.info_label.set_text(L.t("Vùng cắt: ") + "%d × %d" % (self.crop_rect[2], self.crop_rect[3])
                                     + L.t(" px — thả chuột để cắt, Esc để huỷ"))
            self.canvas.queue_draw()
        elif t == PEN:
            if isinstance(self.current, PenShape):
                self.current.points.append(p)
                self.canvas.queue_draw()
        elif isinstance(self.current, TwoPointShape):
            self.current.b = shapes.constrain(self.current.a, p, t) if shift else p
            self.canvas.queue_draw()

    def _on_drag_end(self, gesture, dx, dy):
        if getattr(self, "_ignore_drag", False):
            self._ignore_drag = False
            return
        if not self.mouse_down:
            return
        self.mouse_down = False
        if self.tool == CROP:
            self.cropping = False
            self._show_hint()
            x, y, w, h = (int(round(v)) for v in self.crop_rect)
            if w >= 4 and h >= 4:
                self._apply_crop((x, y, w, h))
            self.canvas.queue_draw()
            return
        if self.current is None:
            return
        too_small = isinstance(self.current, TwoPointShape) and shapes.dist(self.current.a, self.current.b) * self._view_scale() < 4
        if not too_small:
            self._push_undo()
            self.shapes.append(self.current)
        self.current = None
        self._rerender()

    def _show_pos(self, p):
        self.pos_label.set_text("%d, %d" % (math.floor(p[0]), math.floor(p[1])))

    def _on_motion(self, ctrl, x, y):
        self._pointer = (x, y)
        p = self.to_image(x, y)
        self._show_pos(p)
        if not self.mouse_down and self.tool == SELECT:
            self.canvas.set_cursor_from_name("move" if self._hit_test(p) is not None else "default")

    def _on_scroll(self, ctrl, dx, dy):
        if not (ctrl.get_current_event_state() & Gdk.ModifierType.CONTROL_MASK):
            return False
        anchor = None
        if self._pointer is not None:
            hadj, vadj = self.scroller.get_hadjustment(), self.scroller.get_vadjustment()
            anchor = (self._pointer[0] - hadj.get_value(), self._pointer[1] - vadj.get_value())
        self.set_zoom(self.zoom / 1.15 if dy > 0 else self.zoom * 1.15, anchor)
        return True

    def _hit_test(self, p):
        tol = 5 / self._view_scale()
        for s in reversed(self.shapes):
            if s.hit_test(p, tol):
                return s
        return None

    def _next_step(self):
        nums = [s.number for s in self.shapes if isinstance(s, StepShape)]
        return (max(nums) if nums else 0) + 1

    def _apply_crop(self, r):
        self._push_undo()
        self.base = render.crop(self.base, r)
        for s in self.shapes:
            s.offset(-r[0], -r[1])
        self.selected = None
        self._rerender()
        self.fit_zoom()

    # ---------- Text editing ----------

    def _begin_edit_shape(self, ts):
        self._push_undo()
        self.editing_index = self.shapes.index(ts)
        self.shapes.remove(ts)
        self.selected = None
        self._rerender()
        self._begin_text_edit(ts.pos, ts.text, ts.color, ts.width)
        self.editing_text = ts

    def _begin_text_edit(self, pos, text, color, width):
        self.editing_text = None
        self.text_pos = pos
        self.text_color = color
        self.text_width = width
        tv = Gtk.TextView()
        tv.set_name(self._text_css_name)
        tv.set_wrap_mode(Gtk.WrapMode.NONE)
        tv.set_accepts_tab(False)
        tv.set_left_margin(4)
        tv.set_right_margin(4)
        tv.set_top_margin(2)
        tv.set_bottom_margin(2)
        tv.set_size_request(80, -1)
        tv.get_buffer().set_text(text, -1)
        tv.set_halign(Gtk.Align.START)
        tv.set_valign(Gtk.Align.START)
        keys = Gtk.EventControllerKey()
        keys.set_propagation_phase(Gtk.PropagationPhase.CAPTURE)
        keys.connect("key-pressed", self._on_text_key)
        tv.add_controller(keys)
        self.text_view = tv
        self._style_text_view()
        self._place_text_view()
        self.overlay.add_overlay(tv)
        tv.grab_focus()
        buf = tv.get_buffer()
        buf.place_cursor(buf.get_end_iter())
        self.info_label.set_text(L.t("Gõ chữ • Enter: xong • Shift+Enter: xuống dòng • Esc: huỷ"))

    def _place_text_view(self):
        if self.text_view is None:
            return
        cx, cy = self.to_canvas(self.text_pos)
        self.text_view.set_margin_start(max(0, int(cx) - 6))
        self.text_view.set_margin_top(max(0, int(cy) - 4))

    def _style_text_view(self):
        if self._text_provider is None:
            self._text_provider = theme.new_provider()
        c = self.text_color
        bg = (50, 50, 55) if shapes.is_light(c) else (255, 255, 255)
        px = max(6.0, TextShape.font_size_for(self.text_width) * self._view_scale())
        css = ("#%(n)s { font-family: Sans; font-weight: bold; font-size: %(px).1fpx; border: 1px solid rgba(128,128,128,0.8); }\n"
               "#%(n)s, #%(n)s text { color: rgb(%(r)d,%(g)d,%(b)d); background-color: rgb(%(br)d,%(bg)d,%(bb)d); caret-color: rgb(%(r)d,%(g)d,%(b)d); }\n"
               % {"n": self._text_css_name, "px": px, "r": c[0], "g": c[1], "b": c[2],
                  "br": bg[0], "bg": bg[1], "bb": bg[2]})
        theme.set_provider_css(self._text_provider, css)

    def _on_text_key(self, ctrl, keyval, keycode, state):
        if keyval in (Gdk.KEY_Return, Gdk.KEY_KP_Enter) and not (state & Gdk.ModifierType.SHIFT_MASK):
            self._commit_text()
            return True
        if keyval == Gdk.KEY_Escape:
            self._cancel_text()
            return True
        return False

    def _close_text_view(self):
        tv = self.text_view
        self.text_view = None
        if tv is not None:
            buf = tv.get_buffer()
            text = buf.get_text(buf.get_start_iter(), buf.get_end_iter(), False)
            self.overlay.remove_overlay(tv)
            self._show_hint()
            return text
        return ""

    def _commit_text(self):
        if self.text_view is None:
            return
        text = self._close_text_view().rstrip()
        if text:
            if self.editing_text is None:
                self._push_undo()
            ts = TextShape(pos=self.text_pos, text=text, color=self.text_color, width=self.text_width)
            if self.editing_text is not None:
                self.shapes.insert(min(self.editing_index, len(self.shapes)), ts)
            else:
                self.shapes.append(ts)
        self.editing_text = None
        self._rerender()
        self.canvas.grab_focus()

    def _cancel_text(self):
        if self.text_view is None:
            return
        self._close_text_view()
        if self.editing_text is not None:
            self.shapes.insert(min(self.editing_index, len(self.shapes)), self.editing_text)
            if self.undo_stack:
                self.undo_stack.pop()
            self._update_undo_buttons()
        self.editing_text = None
        self._rerender()
        self.canvas.grab_focus()

    # ---------- Tools, colour, width ----------

    def _on_tool_toggled(self, button, tool):
        if button.get_active() and tool != self.tool:
            self.set_tool(tool)

    def set_tool(self, t):
        self._commit_text()
        self.tool = t
        self.current = None
        self.cropping = False
        if t != SELECT:
            self.selected = None
        self._update_tool_buttons()
        self._show_hint()
        self.canvas.queue_draw()
        self.canvas.grab_focus()

    def set_color(self, c):
        self.color = tuple(c)
        self._update_swatches()
        if self.text_view is not None:
            self.text_color = self.color
            self._style_text_view()
            self.text_view.grab_focus()
            return
        if self.selected is not None and self.tool == SELECT:
            self._push_undo()
            self.selected.color = self.color
            self._rerender()

    def _on_width_selected(self, drop, _pspec):
        if self._width_guard:
            return
        i = drop.get_selected()
        if 0 <= i < len(WIDTHS):
            self.set_width(WIDTHS[i])

    def set_width(self, w):
        self.width = float(w)
        if w in WIDTHS and self.width_drop.get_selected() != WIDTHS.index(w):
            self._width_guard = True
            self.width_drop.set_selected(WIDTHS.index(w))
            self._width_guard = False
        if self.text_view is not None:
            self.text_width = self.width
            self._style_text_view()
            self.text_view.grab_focus()
            return
        if self.selected is not None and self.tool == SELECT:
            self._push_undo()
            self.selected.width = self.width
            self._rerender()
        self.canvas.grab_focus()

    def pick_color(self):
        dialog = Gtk.ColorDialog()
        dialog.set_title(L.t("Chọn màu khác"))
        dialog.set_with_alpha(False)
        initial = Gdk.RGBA()
        initial.parse("rgb(%d,%d,%d)" % self.color)

        def done(dlg, res):
            try:
                rgba = dlg.choose_rgba_finish(res)
            except GLib.Error:
                return
            if rgba is not None:
                self.set_color((int(round(rgba.red * 255)), int(round(rgba.green * 255)), int(round(rgba.blue * 255))))
        dialog.choose_rgba(self, initial, None, done)

    # ---------- Undo / redo ----------

    def _snapshot(self):
        return (self.base, [s.clone() for s in self.shapes])

    def _push_undo(self):
        self.undo_stack.append(self._snapshot())
        self.redo_stack.clear()
        self.dirty = True
        self._update_undo_buttons()
        self._update_title()

    def undo(self):
        self._commit_text()
        if not self.undo_stack:
            return
        self.redo_stack.append(self._snapshot())
        self._restore(self.undo_stack.pop())

    def redo(self):
        self._commit_text()
        if not self.redo_stack:
            return
        self.undo_stack.append(self._snapshot())
        self._restore(self.redo_stack.pop())

    def _restore(self, state):
        base, shape_list = state
        size_changed = render.size(base) != render.size(self.base)
        self.base = base
        self.shapes = shape_list
        self.selected = None
        self.dirty = True
        self._rerender()
        if size_changed:
            self.fit_zoom()
        self._update_undo_buttons()
        self._update_title()

    def load_shapes(self, shape_list):
        self.shapes = [s.clone() for s in shape_list]
        self._rerender()

    def delete_selected(self):
        if self.selected is None:
            return
        self._push_undo()
        self.shapes.remove(self.selected)
        self.selected = None
        self._rerender()

    def nudge_selected(self, dx, dy):
        if self.selected is None:
            return
        self._push_undo()
        self.selected.offset(dx, dy)
        self._rerender()

    def flattened(self):
        self._commit_text()
        return render.render(self.base, self.shapes)

    def _run_ocr(self):
        self.app.show_ocr(self.flattened())

    # ---------- Clipboard and files ----------

    def copy_to_clipboard(self):
        if render.copy_to_clipboard(self.flattened(), self.get_display()):
            self.info_label.set_text(L.t("Đã sao chép ảnh vào clipboard — dán (Ctrl+V) vào Zalo, Word, email..."))
            self._flash(self.copy_btn, L.t("✓ Đã chép"))
        else:
            self.info_label.set_text(L.t("Clipboard đang bận, hãy thử lại."))

    def save(self, save_as, then=None):
        """Saves to the current file, or asks for one. then(ok) runs when finished."""
        self._commit_text()
        if save_as or not self.file_path:
            self._ask_path(lambda path: self._finish_save(path, save_as, then) if path else (then and then(False)))
            return
        self._finish_save(self.file_path, save_as, then)

    def _finish_save(self, path, save_as, then):
        if not os.path.splitext(path)[1]:
            path += ".png"
        try:
            render.save_image(self.flattened(), path)
        except Exception as e:  # noqa: BLE001
            self._error(L.t("Không lưu được ảnh:\n") + str(getattr(e, "message", e)))
            if then:
                then(False)
            return
        self.file_path = path
        self.dirty = False
        self._update_title()
        self.info_label.set_text(L.t("Đã lưu: ") + path)
        self._flash(self.save_as_btn if save_as else self.save_btn, L.t("✓ Đã lưu"))
        if then:
            then(True)

    def _ask_path(self, callback):
        dialog = Gtk.FileDialog()
        dialog.set_title(L.t("Lưu thành..."))
        dialog.set_modal(True)
        folder = os.path.dirname(self.file_path) if self.file_path else paths.images_folder()
        dialog.set_initial_folder(Gio.File.new_for_path(folder))
        dialog.set_initial_name(os.path.basename(self.file_path) if self.file_path else "MiniSnap.png")
        filters = Gio.ListStore.new(Gtk.FileFilter)
        png = Gtk.FileFilter()
        png.set_name("PNG (*.png)")
        png.add_pattern("*.png")
        png.add_pattern("*.PNG")
        jpg = Gtk.FileFilter()
        jpg.set_name("JPEG (*.jpg)")
        for pat in ("*.jpg", "*.jpeg", "*.JPG", "*.JPEG"):
            jpg.add_pattern(pat)
        filters.append(png)
        filters.append(jpg)
        dialog.set_filters(filters)
        dialog.set_default_filter(png)

        def done(dlg, res):
            try:
                f = dlg.save_finish(res)
            except GLib.Error:
                callback(None)
                return
            callback(f.get_path() if f is not None else None)
        dialog.save(self, None, done)

    def _error(self, text):
        dlg = Adw.MessageDialog(transient_for=self, heading="MiniSnap", body=text)
        dlg.add_response("close", L.t("Đóng"))
        dlg.present()

    # ---------- Keyboard ----------

    def _typing(self):
        focus = self.get_focus()
        return isinstance(focus, (Gtk.Text, Gtk.TextView, Gtk.Entry, Gtk.SearchEntry, Gtk.SpinButton))

    def _on_key(self, ctrl, keyval, keycode, state):
        if self._typing():
            return False
        ctrl_down = bool(state & Gdk.ModifierType.CONTROL_MASK)
        shift = bool(state & Gdk.ModifierType.SHIFT_MASK)
        alt = bool(state & Gdk.ModifierType.ALT_MASK)
        k = Gdk.keyval_to_lower(keyval)
        if ctrl_down and not alt:
            if k == Gdk.KEY_z:
                self.redo() if shift else self.undo()
            elif k == Gdk.KEY_y:
                self.redo()
            elif k == Gdk.KEY_c:
                self.copy_to_clipboard()
            elif k == Gdk.KEY_s:
                self.save(shift)
            elif k == Gdk.KEY_n:
                self.app.begin_capture("region")
            elif k in (Gdk.KEY_plus, Gdk.KEY_equal, Gdk.KEY_KP_Add):
                self.set_zoom(self.zoom * 1.25)
            elif k in (Gdk.KEY_minus, Gdk.KEY_KP_Subtract, Gdk.KEY_underscore):
                self.set_zoom(self.zoom / 1.25)
            elif k in (Gdk.KEY_0, Gdk.KEY_KP_0):
                self.fit_zoom()
            elif k in (Gdk.KEY_1, Gdk.KEY_KP_1):
                self.set_zoom(1.0)
            else:
                return False
            return True
        if alt:
            return False
        if k in (Gdk.KEY_Delete, Gdk.KEY_BackSpace):
            self.delete_selected()
        elif k == Gdk.KEY_Left:
            self.nudge_selected(-1, 0)
        elif k == Gdk.KEY_Right:
            self.nudge_selected(1, 0)
        elif k == Gdk.KEY_Up:
            self.nudge_selected(0, -1)
        elif k == Gdk.KEY_Down:
            self.nudge_selected(0, 1)
        elif k == Gdk.KEY_Escape:
            if self.mouse_down:
                self.mouse_down = False
                self.current = None
                self.cropping = False
                self._show_hint()
            self.selected = None
            self.canvas.queue_draw()
        else:
            name = Gdk.keyval_name(k) or ""
            if len(name) == 1 and name in self.tool_keys:
                self.set_tool(self.tool_keys[name])
                return True
            return False
        return True

    # ---------- Closing ----------

    def _on_close_request(self, *_):
        self._commit_text()
        if self.dirty and not self.skip_save_prompt and not self._closing_ok:
            dlg = Adw.MessageDialog(transient_for=self, heading="MiniSnap", body=L.t("Lưu các thay đổi vào ảnh?"))
            dlg.add_response("cancel", L.t("Huỷ"))
            dlg.add_response("discard", L.t("Không lưu"))
            dlg.add_response("save", L.t("Lưu"))
            dlg.set_response_appearance("discard", Adw.ResponseAppearance.DESTRUCTIVE)
            dlg.set_response_appearance("save", Adw.ResponseAppearance.SUGGESTED)
            dlg.set_default_response("save")
            dlg.set_close_response("cancel")

            def answered(d, response):
                if response == "discard":
                    self._force_close()
                elif response == "save":
                    self.save(False, lambda ok: ok and self._force_close())
            dlg.connect("response", answered)
            dlg.present()
            return True
        self._cleanup()
        return False

    def _force_close(self):
        self._closing_ok = True
        self.close()

    def _cleanup(self):
        if self._text_provider is not None:
            theme.remove_provider(self._text_provider)
            self._text_provider = None
        try:
            Adw.StyleManager.get_default().disconnect(self._dark_handler)
        except Exception:  # noqa: BLE001
            pass
