using System;
using System.Drawing;
using System.Drawing.Drawing2D;
using System.Windows.Forms;

namespace MiniSnap
{
    // A Windows 11 style slider drawn by hand: the stock TrackBar can't follow dark mode.
    // Drag, click, mouse wheel and arrow keys change the value; Changing fires once before each
    // user gesture (so the editor can take one undo snapshot per drag), ValueChanged on every step.
    class FlatSlider : Control
    {
        int min, max = 10, value;
        bool dragging;

        public event EventHandler Changing;
        public event EventHandler ValueChanged;

        public FlatSlider()
        {
            SetStyle(ControlStyles.AllPaintingInWmPaint | ControlStyles.OptimizedDoubleBuffer | ControlStyles.UserPaint |
                     ControlStyles.ResizeRedraw | ControlStyles.Selectable | ControlStyles.SupportsTransparentBackColor, true);
            Cursor = Cursors.Hand;
            TabStop = true;
        }

        public int Minimum { get { return min; } set { min = value; Value = this.value; } }
        public int Maximum { get { return max; } set { max = value; Value = this.value; } }

        public int Value
        {
            get { return value; }
            set
            {
                int v = Math.Max(min, Math.Min(max, value));
                if (v == this.value) return;
                this.value = v;
                Invalidate();
            }
        }

        void SetByUser(int v)
        {
            v = Math.Max(min, Math.Min(max, v));
            if (v == value) return;
            value = v;
            Invalidate();
            if (ValueChanged != null) ValueChanged(this, EventArgs.Empty);
        }

        void BeginGesture() { if (Changing != null) Changing(this, EventArgs.Empty); }

        float Pad { get { return Height / 2f; } }

        int ValueAt(int x)
        {
            float w = Math.Max(1f, Width - 2 * Pad);
            float t = Math.Max(0f, Math.Min(1f, (x - Pad) / w));
            return min + (int)Math.Round(t * (max - min));
        }

        protected override void OnMouseDown(MouseEventArgs e)
        {
            base.OnMouseDown(e);
            if (e.Button != MouseButtons.Left) return;
            Focus();
            dragging = true;
            Capture = true;
            BeginGesture();
            SetByUser(ValueAt(e.X));
        }

        protected override void OnMouseMove(MouseEventArgs e)
        {
            base.OnMouseMove(e);
            if (dragging) SetByUser(ValueAt(e.X));
        }

        protected override void OnMouseUp(MouseEventArgs e)
        {
            base.OnMouseUp(e);
            dragging = false;
            Capture = false;
        }

        protected override void OnMouseWheel(MouseEventArgs e)
        {
            base.OnMouseWheel(e);
            BeginGesture();
            SetByUser(value + (e.Delta > 0 ? 1 : -1));
            var he = e as HandledMouseEventArgs;
            if (he != null) he.Handled = true;
        }

        protected override bool IsInputKey(Keys keyData)
        {
            var k = keyData & Keys.KeyCode;
            return k == Keys.Left || k == Keys.Right || k == Keys.Up || k == Keys.Down || base.IsInputKey(keyData);
        }

        protected override void OnKeyDown(KeyEventArgs e)
        {
            base.OnKeyDown(e);
            int d = e.KeyCode == Keys.Left || e.KeyCode == Keys.Down ? -1 : e.KeyCode == Keys.Right || e.KeyCode == Keys.Up ? 1 : 0;
            if (e.KeyCode == Keys.Home) d = min - value;
            if (e.KeyCode == Keys.End) d = max - value;
            if (d == 0) return;
            BeginGesture();
            SetByUser(value + d);
            e.Handled = true;
        }

        protected override void OnGotFocus(EventArgs e) { base.OnGotFocus(e); Invalidate(); }
        protected override void OnLostFocus(EventArgs e) { base.OnLostFocus(e); Invalidate(); }

        protected override void OnPaint(PaintEventArgs e)
        {
            var g = e.Graphics;
            g.Clear(BackColor);
            g.SmoothingMode = SmoothingMode.AntiAlias;
            float pad = Pad, cy = Height / 2f, track = Math.Max(3f, Height / 6f);
            float x0 = pad, x1 = Width - pad;
            float t = max > min ? (value - min) / (float)(max - min) : 0f;
            float tx = x0 + (x1 - x0) * t;
            using (var path = Icons.RoundedRect(new RectangleF(x0, cy - track / 2, x1 - x0, track), track / 2))
            using (var br = new SolidBrush(Theme.Border)) g.FillPath(br, path);
            if (tx - x0 > 0.5f)
                using (var path = Icons.RoundedRect(new RectangleF(x0, cy - track / 2, tx - x0, track), track / 2))
                using (var br = new SolidBrush(Enabled ? Theme.Accent : Theme.TextDisabled)) g.FillPath(br, path);
            // Thumb: an accent dot inside a ring, as in Windows 11.
            float r = Height * 0.36f;
            using (var br = new SolidBrush(Theme.Dark ? Color.FromArgb(69, 69, 69) : Color.White)) g.FillEllipse(br, tx - r, cy - r, 2 * r, 2 * r);
            using (var pen = new Pen(Theme.Border, 1f)) g.DrawEllipse(pen, tx - r, cy - r, 2 * r, 2 * r);
            float ri = r * (dragging ? 0.45f : Focused ? 0.62f : 0.55f);
            using (var br = new SolidBrush(Enabled ? Theme.Accent : Theme.TextDisabled)) g.FillEllipse(br, tx - ri, cy - ri, 2 * ri, 2 * ri);
        }
    }
}
