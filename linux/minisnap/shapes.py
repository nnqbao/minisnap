"""Annotation shapes (port of windows/src/Shapes.cs).

Annotations stay as vector objects on top of the base image until saved, so they can be
selected, moved, recoloured and undone. Coordinates are image pixels; colours are (r, g, b)
tuples 0-255. Drawing uses Cairo, text uses Pango (so Vietnamese diacritics render properly).
"""

import copy
import math

import cairo

from . import _gi  # noqa: F401
from gi.repository import Pango, PangoCairo

# Tool identifiers (Shapes.cs Tool enum).
SELECT, ARROW, RECT, ELLIPSE, LINE, PEN, HIGHLIGHT, TEXT, BLUR, STEP, CROP = (
    "select", "arrow", "rect", "ellipse", "line", "pen", "highlight", "text", "blur", "step", "crop")

FONT_FAMILY = "Sans"


# ---------- Geometry helpers (Geo) ----------

def norm(a, b):
    """Rectangle (x, y, w, h) spanned by two points."""
    x1, y1 = min(a[0], b[0]), min(a[1], b[1])
    return (x1, y1, max(a[0], b[0]) - x1, max(a[1], b[1]) - y1)


def inflate(r, dx, dy=None):
    dy = dx if dy is None else dy
    return (r[0] - dx, r[1] - dy, r[2] + 2 * dx, r[3] + 2 * dy)


def contains(r, p):
    return r[0] <= p[0] <= r[0] + r[2] and r[1] <= p[1] <= r[1] + r[3]


def intersect(a, b):
    x1, y1 = max(a[0], b[0]), max(a[1], b[1])
    x2, y2 = min(a[0] + a[2], b[0] + b[2]), min(a[1] + a[3], b[1] + b[3])
    if x2 <= x1 or y2 <= y1:
        return (x1, y1, 0, 0)
    return (x1, y1, x2 - x1, y2 - y1)


def dist(a, b):
    return math.hypot(a[0] - b[0], a[1] - b[1])


def dist_to_segment(p, a, b):
    dx, dy = b[0] - a[0], b[1] - a[1]
    len2 = dx * dx + dy * dy
    if len2 < 0.0001:
        return dist(p, a)
    t = max(0.0, min(1.0, ((p[0] - a[0]) * dx + (p[1] - a[1]) * dy) / len2))
    return dist(p, (a[0] + t * dx, a[1] + t * dy))


def is_light(c):
    return c[0] * 0.299 + c[1] * 0.587 + c[2] * 0.114 > 165


def contrast(c):
    """Black or white, whichever reads better on top of c."""
    return (25, 25, 25) if is_light(c) else (255, 255, 255)


def set_rgb(cr, c, alpha=255):
    cr.set_source_rgba(c[0] / 255.0, c[1] / 255.0, c[2] / 255.0, alpha / 255.0)


def round_pen(cr, width):
    cr.set_line_width(width)
    cr.set_line_cap(cairo.LINE_CAP_ROUND)
    cr.set_line_join(cairo.LINE_JOIN_ROUND)


_pango_context = None


def _measure_context():
    global _pango_context
    if _pango_context is None:
        _pango_context = PangoCairo.FontMap.get_default().create_context()
    return _pango_context


def font_desc(px, bold=True):
    d = Pango.FontDescription.from_string(FONT_FAMILY + (" Bold" if bold else ""))
    d.set_absolute_size(px * Pango.SCALE)
    return d


# ---------- Shapes ----------

class Shape:
    def __init__(self, color=(232, 38, 38), width=5.0):
        self.color = tuple(color)
        self.width = float(width)

    def draw(self, cr):
        raise NotImplementedError

    def bounds(self):
        raise NotImplementedError

    def offset(self, dx, dy):
        raise NotImplementedError

    def hit_test(self, p, tol):
        return contains(inflate(self.bounds(), tol), p)

    def clone(self):
        return copy.deepcopy(self)


class TwoPointShape(Shape):
    def __init__(self, a=(0, 0), b=(0, 0), **kw):
        super().__init__(**kw)
        self.a = tuple(a)
        self.b = tuple(b)

    @property
    def rect(self):
        return norm(self.a, self.b)

    def bounds(self):
        return inflate(self.rect, self.width / 2)

    def offset(self, dx, dy):
        self.a = (self.a[0] + dx, self.a[1] + dy)
        self.b = (self.b[0] + dx, self.b[1] + dy)


class ArrowShape(TwoPointShape):
    def draw(self, cr):
        ax, ay = self.a
        bx, by = self.b
        dx, dy = bx - ax, by - ay
        length = math.hypot(dx, dy)
        if length < 1:
            return
        ux, uy = dx / length, dy / length
        px, py = -uy, ux
        w = self.width
        head = min(length, max(12.0, w * 3.6))
        head_half, neck, tail = head * 0.6, w * 0.8, w * 0.35
        base = (bx - ux * head, by - uy * head)
        pts = [
            (ax + px * tail, ay + py * tail),
            (base[0] + px * neck, base[1] + py * neck),
            (base[0] + px * head_half, base[1] + py * head_half),
            (bx, by),
            (base[0] - px * head_half, base[1] - py * head_half),
            (base[0] - px * neck, base[1] - py * neck),
            (ax - px * tail, ay - py * tail),
        ]
        cr.move_to(*pts[0])
        for p in pts[1:]:
            cr.line_to(*p)
        cr.close_path()
        set_rgb(cr, self.color)
        cr.fill()

    def bounds(self):
        m = max(12.0, self.width * 3.6) * 0.6
        return inflate(self.rect, m)

    def hit_test(self, p, tol):
        return dist_to_segment(p, self.a, self.b) <= tol + self.width * 1.5


class LineShape(TwoPointShape):
    def draw(self, cr):
        set_rgb(cr, self.color)
        round_pen(cr, self.width)
        cr.move_to(*self.a)
        cr.line_to(*self.b)
        cr.stroke()

    def hit_test(self, p, tol):
        return dist_to_segment(p, self.a, self.b) <= tol + self.width / 2


class RectShape(TwoPointShape):
    def draw(self, cr):
        x, y, w, h = self.rect
        if w < 1 or h < 1:
            return
        set_rgb(cr, self.color)
        cr.set_line_width(self.width)
        cr.set_line_join(cairo.LINE_JOIN_ROUND)
        cr.rectangle(x, y, w, h)
        cr.stroke()


class EllipseShape(TwoPointShape):
    def draw(self, cr):
        x, y, w, h = self.rect
        if w < 1 or h < 1:
            return
        cr.save()
        cr.translate(x + w / 2.0, y + h / 2.0)
        cr.scale(w / 2.0, h / 2.0)
        cr.new_sub_path()
        cr.arc(0, 0, 1, 0, 2 * math.pi)
        cr.restore()   # stroke in unscaled space so the line width stays even
        set_rgb(cr, self.color)
        cr.set_line_width(self.width)
        cr.stroke()


class HighlightShape(TwoPointShape):
    def draw(self, cr):
        x, y, w, h = self.rect
        set_rgb(cr, self.color, 105)
        cr.rectangle(x, y, w, h)
        cr.fill()

    def bounds(self):
        return self.rect


class BlurShape(TwoPointShape):
    """Preview while dragging; the real blur happens in apply() on the flattened image.

    cell: mosaic cell size, 1..10 (10 to 64 image pixels). smooth: 0 = crisp squares .. 10 = a smooth blur."""

    MAX_CELL = 10
    MAX_SMOOTH = 10
    _checker = None

    def __init__(self, cell=2, smooth=0, **kw):
        super().__init__(**kw)
        self.cell = int(cell)
        self.smooth = int(smooth)

    def cell_pixels(self):
        return 4 + 6 * max(1, min(self.MAX_CELL, int(self.cell)))

    @classmethod
    def _checker_pattern(cls):
        if cls._checker is None:
            s = cairo.ImageSurface(cairo.FORMAT_ARGB32, 4, 4)
            c = cairo.Context(s)
            c.set_source_rgba(80 / 255.0, 80 / 255.0, 80 / 255.0, 90 / 255.0)
            c.set_operator(cairo.OPERATOR_SOURCE)
            c.paint()
            c.set_source_rgba(1, 1, 1, 60 / 255.0)
            c.rectangle(0, 0, 2, 2)
            c.rectangle(2, 2, 2, 2)
            c.fill()
            p = cairo.SurfacePattern(s)
            p.set_extend(cairo.EXTEND_REPEAT)
            p.set_filter(cairo.FILTER_NEAREST)
            cls._checker = p
        return cls._checker

    def draw(self, cr):
        x, y, w, h = self.rect
        cr.save()
        cr.rectangle(x, y, w, h)
        cr.set_source(self._checker_pattern())
        cr.fill()
        cr.restore()
        cr.save()
        cr.set_source_rgba(40 / 255.0, 40 / 255.0, 40 / 255.0, 200 / 255.0)
        cr.set_line_width(1)
        cr.set_dash([4, 3])
        cr.rectangle(x, y, w, h)
        cr.stroke()
        cr.restore()

    def bounds(self):
        return self.rect

    def apply(self, surface):
        """Blurs the area of `surface` (a cairo ImageSurface) in place: every cell is averaged, the mosaic
        shows the averages as squares, the smooth blur interpolates between them, and `smooth` blends the two."""
        x, y, w, h = self.rect
        r = intersect((int(round(x)), int(round(y)), int(round(w)), int(round(h))),
                      (0, 0, surface.get_width(), surface.get_height()))
        rx, ry, rw, rh = r
        if rw < 2 or rh < 2:
            return
        block = self.cell_pixels()
        sw, sh = max(1, (rw + block // 2) // block), max(1, (rh + block // 2) // block)
        t = max(0, min(self.MAX_SMOOTH, int(self.smooth))) / float(self.MAX_SMOOTH)
        surface.flush()
        small = cairo.ImageSurface(cairo.FORMAT_ARGB32, sw, sh)
        sc = cairo.Context(small)
        sc.scale(sw / float(rw), sh / float(rh))
        sc.set_source_surface(surface, -rx, -ry)
        sc.get_source().set_filter(cairo.FILTER_GOOD)
        sc.get_source().set_extend(cairo.EXTEND_PAD)
        sc.set_operator(cairo.OPERATOR_SOURCE)
        sc.paint()
        small.flush()
        c = cairo.Context(surface)
        c.rectangle(rx, ry, rw, rh)
        c.clip()
        c.translate(rx, ry)
        c.scale(rw / float(sw), rh / float(sh))
        if t < 1:
            c.set_source_surface(small, 0, 0)
            c.get_source().set_filter(cairo.FILTER_NEAREST)
            c.get_source().set_extend(cairo.EXTEND_PAD)
            c.set_operator(cairo.OPERATOR_SOURCE)
            c.paint()
        if t > 0:
            c.set_source_surface(small, 0, 0)
            c.get_source().set_filter(cairo.FILTER_BILINEAR)
            c.get_source().set_extend(cairo.EXTEND_PAD)
            c.set_operator(cairo.OPERATOR_SOURCE if t >= 1 else cairo.OPERATOR_OVER)
            c.paint_with_alpha(t)
        surface.flush()


class PenShape(Shape):
    def __init__(self, points=None, **kw):
        super().__init__(**kw)
        self.points = list(points or [])

    def draw(self, cr):
        if not self.points:
            return
        set_rgb(cr, self.color)
        if len(self.points) == 1:
            x, y = self.points[0]
            cr.new_sub_path()
            cr.arc(x, y, self.width / 2.0, 0, 2 * math.pi)
            cr.fill()
            return
        round_pen(cr, self.width)
        cr.move_to(*self.points[0])
        for p in self.points[1:]:
            cr.line_to(*p)
        cr.stroke()

    def bounds(self):
        if not self.points:
            return (0, 0, 0, 0)
        xs = [p[0] for p in self.points]
        ys = [p[1] for p in self.points]
        r = (min(xs), min(ys), max(xs) - min(xs), max(ys) - min(ys))
        return inflate(r, self.width / 2)

    def offset(self, dx, dy):
        self.points = [(x + dx, y + dy) for (x, y) in self.points]

    def hit_test(self, p, tol):
        if len(self.points) == 1:
            return dist(p, self.points[0]) <= tol + self.width / 2
        for i in range(1, len(self.points)):
            if dist_to_segment(p, self.points[i - 1], self.points[i]) <= tol + self.width / 2:
                return True
        return False


class TextShape(Shape):
    def __init__(self, pos=(0, 0), text="", **kw):
        super().__init__(**kw)
        self.pos = tuple(pos)
        self.text = text

    @staticmethod
    def font_size_for(width):
        return 12.0 + width * 3.0

    @property
    def font_size(self):
        return self.font_size_for(self.width)

    def _layout(self, cr=None):
        layout = PangoCairo.create_layout(cr) if cr is not None else Pango.Layout.new(_measure_context())
        layout.set_font_description(font_desc(self.font_size))
        layout.set_text(self.text, -1)
        return layout

    def draw(self, cr):
        if not self.text:
            return
        layout = self._layout(cr)
        cr.save()
        cr.move_to(*self.pos)
        PangoCairo.layout_path(cr, layout)
        set_rgb(cr, contrast(self.color), 220)
        cr.set_line_width(max(2.0, self.font_size / 7.0))
        cr.set_line_join(cairo.LINE_JOIN_ROUND)
        cr.stroke_preserve()
        set_rgb(cr, self.color)
        cr.fill()
        cr.restore()

    def bounds(self):
        if not self.text:
            return (self.pos[0], self.pos[1], 1, 1)
        ink, _logical = self._layout().get_pixel_extents()
        r = (self.pos[0] + ink.x, self.pos[1] + ink.y, ink.width, ink.height)
        return inflate(r, self.font_size / 6.0)

    def offset(self, dx, dy):
        self.pos = (self.pos[0] + dx, self.pos[1] + dy)


class StepShape(Shape):
    def __init__(self, center=(0, 0), number=1, **kw):
        super().__init__(**kw)
        self.center = tuple(center)
        self.number = int(number)

    @property
    def radius(self):
        return 10.0 + self.width * 2.0

    def draw(self, cr):
        r = self.radius
        cx, cy = self.center
        cr.save()
        cr.new_sub_path()
        cr.arc(cx, cy, r, 0, 2 * math.pi)
        set_rgb(cr, self.color)
        cr.fill_preserve()
        cr.set_source_rgb(1, 1, 1)
        cr.set_line_width(max(2.0, r / 8.0))
        cr.stroke()
        layout = PangoCairo.create_layout(cr)
        layout.set_font_description(font_desc(r * 1.05))
        layout.set_text(str(self.number), -1)
        ink, _logical = layout.get_pixel_extents()
        cr.move_to(cx - ink.x - ink.width / 2.0, cy - ink.y - ink.height / 2.0)
        set_rgb(cr, contrast(self.color))
        PangoCairo.show_layout(cr, layout)
        cr.restore()

    def bounds(self):
        r = self.radius + 2
        return (self.center[0] - r, self.center[1] - r, 2 * r, 2 * r)

    def offset(self, dx, dy):
        self.center = (self.center[0] + dx, self.center[1] + dy)


def create_two_point(tool, color, width):
    cls = {RECT: RectShape, ELLIPSE: EllipseShape, LINE: LineShape,
           HIGHLIGHT: HighlightShape, BLUR: BlurShape}.get(tool, ArrowShape)
    return cls(color=color, width=width)


def constrain(a, b, tool):
    """Shift held: 45° steps for lines and arrows, squares/circles for the rest."""
    dx, dy = b[0] - a[0], b[1] - a[1]
    if tool in (LINE, ARROW):
        step = math.pi / 4
        ang = round(math.atan2(dy, dx) / step) * step
        length = math.hypot(dx, dy)
        return (a[0] + math.cos(ang) * length, a[1] + math.sin(ang) * length)
    m = max(abs(dx), abs(dy))
    return (a[0] + (-m if dx < 0 else m), a[1] + (-m if dy < 0 else m))
