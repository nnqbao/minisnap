using System;
using System.Collections.Generic;
using System.Drawing;
using System.Drawing.Drawing2D;
using System.Drawing.Imaging;

namespace MiniSnap
{
    enum Tool { Select, Arrow, Rectangle, Ellipse, Line, Pen, Highlight, Text, Blur, Step, Crop }

    // Annotations stay as vector objects on top of the base image until saved,
    // so they can be selected, moved, recoloured and undone.
    abstract class Shape
    {
        public Color Color;
        public float Width;

        public abstract void Draw(Graphics g);
        public abstract RectangleF Bounds { get; }
        public abstract void Offset(float dx, float dy);

        public virtual bool HitTest(PointF p, float tolerance)
        {
            var b = Bounds;
            b.Inflate(tolerance, tolerance);
            return b.Contains(p);
        }

        public virtual Shape Clone() { return (Shape)MemberwiseClone(); }
    }

    abstract class TwoPointShape : Shape
    {
        public PointF A, B;

        public RectangleF Rect { get { return Geo.Norm(A, B); } }
        public override RectangleF Bounds { get { var r = Rect; r.Inflate(Width / 2, Width / 2); return r; } }

        public override void Offset(float dx, float dy)
        {
            A = new PointF(A.X + dx, A.Y + dy);
            B = new PointF(B.X + dx, B.Y + dy);
        }
    }

    class ArrowShape : TwoPointShape
    {
        public override void Draw(Graphics g)
        {
            float dx = B.X - A.X, dy = B.Y - A.Y;
            float len = (float)Math.Sqrt(dx * dx + dy * dy);
            if (len < 1f) return;
            float ux = dx / len, uy = dy / len, px = -uy, py = ux;
            float head = Math.Min(len, Math.Max(12f, Width * 3.6f));
            float headHalf = head * 0.6f, neck = Width * 0.8f, tail = Width * 0.35f;
            var basePt = new PointF(B.X - ux * head, B.Y - uy * head);
            using (var path = new GraphicsPath())
            using (var br = new SolidBrush(Color))
            {
                path.AddPolygon(new[]
                {
                    new PointF(A.X + px * tail, A.Y + py * tail),
                    new PointF(basePt.X + px * neck, basePt.Y + py * neck),
                    new PointF(basePt.X + px * headHalf, basePt.Y + py * headHalf),
                    B,
                    new PointF(basePt.X - px * headHalf, basePt.Y - py * headHalf),
                    new PointF(basePt.X - px * neck, basePt.Y - py * neck),
                    new PointF(A.X - px * tail, A.Y - py * tail),
                });
                g.FillPath(br, path);
            }
        }

        public override RectangleF Bounds { get { var r = Rect; float m = Math.Max(12f, Width * 3.6f) * 0.6f; r.Inflate(m, m); return r; } }

        public override bool HitTest(PointF p, float tol) { return Geo.DistToSegment(p, A, B) <= tol + Width * 1.5f; }
    }

    class LineShape : TwoPointShape
    {
        public override void Draw(Graphics g)
        {
            using (var pen = Geo.MakePen(Color, Width)) g.DrawLine(pen, A, B);
        }

        public override bool HitTest(PointF p, float tol) { return Geo.DistToSegment(p, A, B) <= tol + Width / 2; }
    }

    class RectShape : TwoPointShape
    {
        public override void Draw(Graphics g)
        {
            var r = Rect;
            if (r.Width < 1 || r.Height < 1) return;
            using (var pen = new Pen(Color, Width) { LineJoin = LineJoin.Round }) g.DrawRectangle(pen, r.X, r.Y, r.Width, r.Height);
        }
    }

    class EllipseShape : TwoPointShape
    {
        public override void Draw(Graphics g)
        {
            var r = Rect;
            if (r.Width < 1 || r.Height < 1) return;
            using (var pen = new Pen(Color, Width)) g.DrawEllipse(pen, r);
        }
    }

    class HighlightShape : TwoPointShape
    {
        public override void Draw(Graphics g)
        {
            using (var br = new SolidBrush(Color.FromArgb(105, Color))) g.FillRectangle(br, Rect);
        }

        public override RectangleF Bounds { get { return Rect; } }
    }

    class BlurShape : TwoPointShape
    {
        public const int MaxCell = 10, MaxSmooth = 10;
        // Cell: mosaic cell size, 1..10 (10 to 64 image pixels). Smooth: 0 = crisp squares .. 10 = a smooth blur.
        public int Cell = 2, Smooth = 0;

        public int CellPixels { get { return 4 + 6 * Math.Max(1, Math.Min(MaxCell, Cell)); } }

        // Preview while dragging; the real pixelation happens in Apply on the flattened image.
        public override void Draw(Graphics g)
        {
            var r = Rect;
            using (var br = new HatchBrush(HatchStyle.SmallCheckerBoard, Color.FromArgb(90, 80, 80, 80), Color.FromArgb(60, 255, 255, 255)))
                g.FillRectangle(br, r);
            using (var pen = new Pen(Color.FromArgb(200, 40, 40, 40), 1f) { DashStyle = DashStyle.Dash })
                g.DrawRectangle(pen, r.X, r.Y, r.Width, r.Height);
        }

        public override RectangleF Bounds { get { return Rect; } }

        public void Apply(Bitmap canvas)
        {
            Rectangle r = Rectangle.Round(Rect);
            r.Intersect(new Rectangle(0, 0, canvas.Width, canvas.Height));
            if (r.Width < 2 || r.Height < 2) return;
            int block = CellPixels;
            int sw = Math.Max(1, (r.Width + block / 2) / block), sh = Math.Max(1, (r.Height + block / 2) / block);
            float smooth = Math.Max(0, Math.Min(MaxSmooth, Smooth)) / (float)MaxSmooth;
            using (var small = new Bitmap(sw, sh, PixelFormat.Format32bppPArgb))
            {
                // Average each cell: a box-filtered downscale of the area.
                using (var sg = Graphics.FromImage(small))
                using (var ia = new ImageAttributes())
                {
                    ia.SetWrapMode(WrapMode.TileFlipXY);
                    sg.CompositingMode = CompositingMode.SourceCopy;
                    sg.InterpolationMode = InterpolationMode.HighQualityBilinear;
                    sg.PixelOffsetMode = PixelOffsetMode.Half;
                    sg.DrawImage(canvas, new Rectangle(0, 0, sw, sh), r.X, r.Y, r.Width, r.Height, GraphicsUnit.Pixel, ia);
                }
                using (var g = Graphics.FromImage(canvas))
                using (var ia = new ImageAttributes())
                {
                    g.SetClip(r);
                    g.PixelOffsetMode = PixelOffsetMode.Half;
                    ia.SetWrapMode(WrapMode.TileFlipXY);
                    // Mosaic: the cells blown up as hard squares.
                    if (smooth < 1f)
                    {
                        g.CompositingMode = CompositingMode.SourceCopy;
                        g.InterpolationMode = InterpolationMode.NearestNeighbor;
                        g.DrawImage(small, r, 0, 0, sw, sh, GraphicsUnit.Pixel, ia);
                    }
                    // Blur: the same cells blown up smoothly, blended over the squares by Smooth.
                    if (smooth > 0f)
                    {
                        g.CompositingMode = smooth >= 1f ? CompositingMode.SourceCopy : CompositingMode.SourceOver;
                        g.InterpolationMode = InterpolationMode.HighQualityBicubic;
                        if (smooth < 1f) ia.SetColorMatrix(new ColorMatrix { Matrix33 = smooth });
                        g.DrawImage(small, r, 0, 0, sw, sh, GraphicsUnit.Pixel, ia);
                    }
                }
            }
        }
    }

    class PenShape : Shape
    {
        public List<PointF> Points = new List<PointF>();

        public override void Draw(Graphics g)
        {
            if (Points.Count == 0) return;
            if (Points.Count == 1)
            {
                using (var br = new SolidBrush(Color))
                    g.FillEllipse(br, Points[0].X - Width / 2, Points[0].Y - Width / 2, Width, Width);
                return;
            }
            using (var pen = Geo.MakePen(Color, Width)) g.DrawLines(pen, Points.ToArray());
        }

        public override RectangleF Bounds
        {
            get
            {
                if (Points.Count == 0) return RectangleF.Empty;
                float x1 = float.MaxValue, y1 = float.MaxValue, x2 = float.MinValue, y2 = float.MinValue;
                foreach (var p in Points)
                {
                    x1 = Math.Min(x1, p.X); y1 = Math.Min(y1, p.Y);
                    x2 = Math.Max(x2, p.X); y2 = Math.Max(y2, p.Y);
                }
                var r = RectangleF.FromLTRB(x1, y1, x2, y2);
                r.Inflate(Width / 2, Width / 2);
                return r;
            }
        }

        public override void Offset(float dx, float dy)
        {
            for (int i = 0; i < Points.Count; i++) Points[i] = new PointF(Points[i].X + dx, Points[i].Y + dy);
        }

        public override bool HitTest(PointF p, float tol)
        {
            if (Points.Count == 1) return Geo.Dist(p, Points[0]) <= tol + Width / 2;
            for (int i = 1; i < Points.Count; i++)
                if (Geo.DistToSegment(p, Points[i - 1], Points[i]) <= tol + Width / 2) return true;
            return false;
        }

        public override Shape Clone()
        {
            var c = (PenShape)MemberwiseClone();
            c.Points = new List<PointF>(Points);
            return c;
        }
    }

    class TextShape : Shape
    {
        public PointF Pos;
        public string Text = "";

        public static float FontSizeFor(float width) { return 12f + width * 3f; }
        public float FontSize { get { return FontSizeFor(Width); } }

        GraphicsPath BuildPath()
        {
            var path = new GraphicsPath();
            using (var ff = new FontFamily("Segoe UI"))
                path.AddString(Text, ff, (int)FontStyle.Bold, FontSize, Pos, StringFormat.GenericTypographic);
            return path;
        }

        public override void Draw(Graphics g)
        {
            if (Text.Length == 0) return;
            using (var path = BuildPath())
            using (var halo = new Pen(Geo.Contrast(Color, 220), Math.Max(2f, FontSize / 7f)) { LineJoin = LineJoin.Round })
            using (var br = new SolidBrush(Color))
            {
                g.DrawPath(halo, path);
                g.FillPath(br, path);
            }
        }

        public override RectangleF Bounds
        {
            get
            {
                if (Text.Length == 0) return new RectangleF(Pos, new SizeF(1, 1));
                using (var path = BuildPath())
                {
                    var r = path.GetBounds();
                    r.Inflate(FontSize / 6f, FontSize / 6f);
                    return r;
                }
            }
        }

        public override void Offset(float dx, float dy) { Pos = new PointF(Pos.X + dx, Pos.Y + dy); }
    }

    class StepShape : Shape
    {
        public PointF Center;
        public int Number;

        public float Radius { get { return 10f + Width * 2f; } }

        public override void Draw(Graphics g)
        {
            float r = Radius;
            var rect = new RectangleF(Center.X - r, Center.Y - r, 2 * r, 2 * r);
            using (var br = new SolidBrush(Color)) g.FillEllipse(br, rect);
            using (var pen = new Pen(Color.White, Math.Max(2f, r / 8f))) g.DrawEllipse(pen, rect);
            using (var font = new Font("Segoe UI", r * 1.05f, FontStyle.Bold, GraphicsUnit.Pixel))
            using (var tb = new SolidBrush(Geo.Contrast(Color, 255)))
            using (var sf = new StringFormat { Alignment = StringAlignment.Center, LineAlignment = StringAlignment.Center })
            {
                var old = g.TextRenderingHint;
                g.TextRenderingHint = System.Drawing.Text.TextRenderingHint.AntiAlias;
                g.DrawString(Number.ToString(), font, tb, new RectangleF(rect.X, rect.Y + r * 0.04f, rect.Width, rect.Height), sf);
                g.TextRenderingHint = old;
            }
        }

        public override RectangleF Bounds { get { float r = Radius + 2; return new RectangleF(Center.X - r, Center.Y - r, 2 * r, 2 * r); } }

        public override void Offset(float dx, float dy) { Center = new PointF(Center.X + dx, Center.Y + dy); }
    }

    static class Geo
    {
        public static RectangleF Norm(PointF a, PointF b)
        {
            return RectangleF.FromLTRB(Math.Min(a.X, b.X), Math.Min(a.Y, b.Y), Math.Max(a.X, b.X), Math.Max(a.Y, b.Y));
        }

        public static float Dist(PointF a, PointF b)
        {
            float dx = a.X - b.X, dy = a.Y - b.Y;
            return (float)Math.Sqrt(dx * dx + dy * dy);
        }

        public static float DistToSegment(PointF p, PointF a, PointF b)
        {
            float dx = b.X - a.X, dy = b.Y - a.Y;
            float len2 = dx * dx + dy * dy;
            if (len2 < 0.0001f) return Dist(p, a);
            float t = Math.Max(0, Math.Min(1, ((p.X - a.X) * dx + (p.Y - a.Y) * dy) / len2));
            return Dist(p, new PointF(a.X + t * dx, a.Y + t * dy));
        }

        public static Pen MakePen(Color c, float width)
        {
            return new Pen(c, width) { StartCap = LineCap.Round, EndCap = LineCap.Round, LineJoin = LineJoin.Round };
        }

        public static bool IsLight(Color c) { return c.R * 0.299 + c.G * 0.587 + c.B * 0.114 > 165; }

        // Black or white, whichever reads better on top of c.
        public static Color Contrast(Color c, int alpha)
        {
            return IsLight(c) ? Color.FromArgb(alpha, 25, 25, 25) : Color.FromArgb(alpha, 255, 255, 255);
        }
    }

    static class Renderer
    {
        public static Bitmap Render(Bitmap baseImg, IList<Shape> shapes)
        {
            var bmp = new Bitmap(baseImg.Width, baseImg.Height, PixelFormat.Format32bppPArgb);
            using (var g = Graphics.FromImage(bmp))
            {
                g.CompositingMode = CompositingMode.SourceCopy;
                g.InterpolationMode = InterpolationMode.NearestNeighbor;
                g.PixelOffsetMode = PixelOffsetMode.Half;
                var r = new Rectangle(0, 0, baseImg.Width, baseImg.Height);
                g.DrawImage(baseImg, r, r, GraphicsUnit.Pixel);
            }
            // A fresh Graphics per shape so blur can read the pixels drawn so far.
            foreach (var s in shapes)
            {
                var blur = s as BlurShape;
                if (blur != null) { blur.Apply(bmp); continue; }
                using (var g = Graphics.FromImage(bmp))
                {
                    g.SmoothingMode = SmoothingMode.AntiAlias;
                    s.Draw(g);
                }
            }
            return bmp;
        }
    }
}
