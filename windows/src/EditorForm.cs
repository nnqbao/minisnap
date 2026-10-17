using System;
using System.Collections.Generic;
using System.Drawing;
using System.Drawing.Drawing2D;
using System.Drawing.Imaging;
using System.IO;
using System.Linq;
using System.Runtime.InteropServices;
using System.Windows.Forms;

namespace MiniSnap
{
    // The canvas can be far taller than the screen (scrolling captures), so it double-buffers
    // only the invalidated area instead of the whole control.
    class CanvasControl : Control
    {
        public event PaintEventHandler BufferedPaint;

        public CanvasControl()
        {
            SetStyle(ControlStyles.UserPaint | ControlStyles.AllPaintingInWmPaint | ControlStyles.Opaque
                | ControlStyles.ResizeRedraw | ControlStyles.Selectable, true);
            TabStop = true;
        }

        protected override void OnPaint(PaintEventArgs e)
        {
            Rectangle clip = e.ClipRectangle;
            if (clip.Width <= 0 || clip.Height <= 0) return;
            using (var buffer = BufferedGraphicsManager.Current.Allocate(e.Graphics, clip))
            {
                buffer.Graphics.SetClip(clip);
                using (var bg = new SolidBrush(BackColor)) buffer.Graphics.FillRectangle(bg, clip);
                var handler = BufferedPaint;
                if (handler != null) handler(this, new PaintEventArgs(buffer.Graphics, clip));
                buffer.Render(e.Graphics);
            }
        }

        protected override bool IsInputKey(Keys keyData)
        {
            switch (keyData & Keys.KeyCode)
            {
                case Keys.Left: case Keys.Right: case Keys.Up: case Keys.Down: return true;
            }
            return base.IsInputKey(keyData);
        }
    }

    class ScrollHost : Panel
    {
        // Stop the panel from jumping when the canvas takes focus.
        protected override Point ScrollToControl(Control activeControl) { return DisplayRectangle.Location; }
    }

    class EditorForm : Form
    {
        class State
        {
            public Bitmap Base;
            public List<Shape> Shapes;
        }

        static readonly Color[] Palette =
        {
            Color.FromArgb(232, 38, 38), Color.FromArgb(255, 140, 0), Color.FromArgb(255, 214, 0), Color.FromArgb(40, 170, 70),
            Color.FromArgb(30, 120, 230), Color.FromArgb(150, 70, 200), Color.FromArgb(30, 30, 30), Color.White,
        };
        static readonly int[] Widths = { 2, 3, 5, 8, 12, 16 };
        const int MaxCanvasPixels = 32000;

        readonly Action newCapture, showLibrary;
        readonly Action<Bitmap> runOcr;
        readonly float ui;
        Bitmap baseImg, cache;
        List<Shape> shapes = new List<Shape>();
        readonly Stack<State> undo = new Stack<State>(), redo = new Stack<State>();
        string filePath;
        bool dirty;
        public bool SkipSavePrompt;

        Tool tool = Tool.Arrow;
        Color color = Palette[0];
        float width = 5;
        int blurCell = 2, blurSmooth;
        float zoom = 1f;

        Shape current, selected;
        bool mouseDown, movedSelected, cropping;
        PointF downPt, lastPt;
        RectangleF cropRect;

        TextBox textBox;
        PointF textPos;
        Color textColor;
        float textWidth;
        TextShape editingText;
        int editingIndex;

        ScrollHost host;
        CanvasControl canvas;
        ToolStrip toolsBar, propsBar;
        ToolStripStatusLabel sizeLabel, posLabel, infoLabel;
        ToolStripLabel zoomLabel;
        ToolStripButton colorButton, undoBtn, redoBtn;
        Button copyBtn, saveBtn, saveAsBtn;
        readonly ToolTip bigTips = new ToolTip();
        ToolStripDropDownButton widthBox;
        FlatSlider cellSlider, smoothSlider;
        ToolStripLabel cellValue, smoothValue;
        readonly List<ToolStripItem> widthItems = new List<ToolStripItem>(), blurItems = new List<ToolStripItem>();
        bool blurPropsShown, sliderUndoPending;
        readonly Dictionary<Tool, ToolStripButton> toolButtons = new Dictionary<Tool, ToolStripButton>();
        readonly Dictionary<Keys, Tool> toolKeys = new Dictionary<Keys, Tool>();
        readonly List<KeyValuePair<Color, ToolStripButton>> swatches = new List<KeyValuePair<Color, ToolStripButton>>();

        public EditorForm(Bitmap image, string path, Action newCapture, Action<Bitmap> runOcr, Action showLibrary)
        {
            this.newCapture = newCapture;
            this.runOcr = runOcr;
            this.showLibrary = showLibrary;
            filePath = path;
            baseImg = new Bitmap(image.Width, image.Height, PixelFormat.Format32bppPArgb);
            using (var g = Graphics.FromImage(baseImg))
            {
                g.CompositingMode = CompositingMode.SourceCopy;
                g.DrawImage(image, new Rectangle(0, 0, image.Width, image.Height), new Rectangle(0, 0, image.Width, image.Height), GraphicsUnit.Pixel);
            }
            using (var g = CreateGraphics()) ui = g.DpiX / 96f;

            Icon = AppIcon.Get();
            KeyPreview = true;
            Font = Theme.UiFont(9f);
            // Wide enough for every tool plus the three big buttons, but never wider than the screen.
            MinimumSize = new Size(Math.Min((int)(1250 * ui), Screen.PrimaryScreen.WorkingArea.Width * 95 / 100), (int)(440 * ui));
            BuildUi();
            Theme.Apply(this);
            Theme.StyleStrip(widthBox.DropDown);
            host.BackColor = canvas.BackColor = Theme.Canvas;
            Rerender();
            SizeToImage();
            UpdateTitle();
            UpdateToolButtons();
            UpdateSwatches();
            UpdateUndoButtons();
        }

        // ---------- UI construction ----------

        int Px(float v) { return (int)Math.Round(v * ui); }

        void BuildUi()
        {
            int iconSize = Px(24);
            toolsBar = new ToolStrip
            {
                GripStyle = ToolStripGripStyle.Hidden,
                ImageScalingSize = new Size(iconSize, iconSize),
                Padding = new Padding(Px(6), Px(3), Px(6), Px(3)),
                CanOverflow = true,
            };
            AddTool(Tool.Select, IconKind.Select, L.T("Chọn"), 'V', L.T("Chọn, kéo để di chuyển, Delete để xoá. Nháy đúp vào chữ để sửa"));
            AddTool(Tool.Arrow, IconKind.Arrow, L.T("Mũi tên"), 'A', L.T("Vẽ mũi tên (giữ Shift để thẳng góc 45°)"));
            AddTool(Tool.Rectangle, IconKind.Rectangle, L.T("Khung"), 'R', L.T("Vẽ khung chữ nhật (Shift: hình vuông)"));
            AddTool(Tool.Ellipse, IconKind.Ellipse, L.T("Elip"), 'E', L.T("Vẽ elip (Shift: hình tròn)"));
            AddTool(Tool.Line, IconKind.Line, L.T("Đường"), 'L', L.T("Vẽ đường thẳng"));
            AddTool(Tool.Pen, IconKind.Pen, L.T("Bút vẽ"), 'P', L.T("Vẽ tự do"));
            AddTool(Tool.Highlight, IconKind.Highlight, L.T("Tô sáng"), 'H', L.T("Tô sáng một vùng (nên chọn màu vàng)"));
            AddTool(Tool.Text, IconKind.Text, L.T("Chữ"), 'T', L.T("Bấm để gõ chữ. Enter để xong, Shift+Enter xuống dòng"));
            AddTool(Tool.Blur, IconKind.Blur, L.T("Làm mờ"), 'B', L.T("Làm mờ thông tin nhạy cảm"));
            AddTool(Tool.Step, IconKind.Step, L.T("Đánh số"), 'N', L.T("Bấm để đặt số bước 1, 2, 3..."));
            AddTool(Tool.Crop, IconKind.Crop, L.T("Cắt ảnh"), 'C', L.T("Kéo chọn vùng muốn giữ lại"));
            toolsBar.Items.Add(new ToolStripSeparator());
            var keys = HotkeySettings.Load();
            AddActionButton(L.T("Trích chữ"), IconKind.Ocr, L.T("Nhận dạng chữ trong ảnh (OCR) và sao chép"), RunOcr);
            AddActionButton(L.T("Thư viện"), IconKind.Library, WithKey(L.T("Mở thư viện ảnh và video"), keys[HotkeyAction.Library]), () => showLibrary());
            AddActionButton(L.T("Chụp mới"), IconKind.Capture, WithKey(L.T("Chụp ảnh mới"), keys[HotkeyAction.CaptureRegion]), () => newCapture());

            // The most used actions get big coloured buttons on the right (right-aligned items are laid out right to left).
            saveAsBtn = AddBigButton(L.T("Lưu thành..."), L.T("✓ Đã lưu"), IconKind.SaveAs, Color.FromArgb(75, 85, 99), L.T("Lưu thành file khác (Ctrl+Shift+S)"), () => Save(true));
            saveBtn = AddBigButton(L.T("Lưu"), L.T("✓ Đã lưu"), IconKind.Save, Color.FromArgb(30, 145, 75), L.T("Lưu ảnh (Ctrl+S)"), () => Save(false));
            copyBtn = AddBigButton(L.T("Sao chép"), L.T("✓ Đã chép"), IconKind.Copy, Color.FromArgb(25, 110, 225), L.T("Sao chép ảnh vào clipboard để dán (Ctrl+C)"), CopyToClipboard);

            int small = Px(18);
            propsBar = new ToolStrip
            {
                GripStyle = ToolStripGripStyle.Hidden,
                ImageScalingSize = new Size(small, small),
                Padding = new Padding(Px(6), Px(2), Px(6), Px(2)),
            };
            propsBar.Items.Add(new ToolStripLabel(L.T("Màu:")));
            foreach (var c in Palette)
            {
                var cc = c;
                var b = new ToolStripButton(null, null, (s, e) => SetColor(cc))
                {
                    DisplayStyle = ToolStripItemDisplayStyle.Image,
                    ToolTipText = "#" + c.R.ToString("X2") + c.G.ToString("X2") + c.B.ToString("X2"),
                };
                propsBar.Items.Add(b);
                swatches.Add(new KeyValuePair<Color, ToolStripButton>(cc, b));
            }
            colorButton = new ToolStripButton(L.T("Khác..."), null, (s, e) => PickColor()) { ToolTipText = L.T("Chọn màu khác") };
            propsBar.Items.Add(colorButton);
            propsBar.Items.Add(new ToolStripSeparator());
            var widthLabel = new ToolStripLabel(L.T("Độ dày:"));
            propsBar.Items.Add(widthLabel);
            // A themed drop-down button instead of a ComboBox, which can't follow dark mode.
            widthBox = new ToolStripDropDownButton(((int)width).ToString()) { AutoSize = false, Width = Px(48), TextAlign = ContentAlignment.MiddleLeft };
            foreach (int w in Widths)
            {
                int ww = w;
                widthBox.DropDownItems.Add(new ToolStripMenuItem(w.ToString(), null, (s, e) => { SetWidth(ww); canvas.Focus(); }));
            }
            propsBar.Items.Add(widthBox);
            widthItems.Add(widthLabel);
            widthItems.Add(widthBox);
            // The blur tool shows its own settings in place of the stroke width.
            cellSlider = AddBlurSlider(L.T("Kích thước ô:"), L.T("Kích thước ô mờ: càng lớn càng giống ô mosaic to"), 1, BlurShape.MaxCell, blurCell, out cellValue);
            smoothSlider = AddBlurSlider(L.T("Độ mờ:"), L.T("Độ mờ: 0 là ô vuông sắc nét, 10 là mờ mịn"), 0, BlurShape.MaxSmooth, blurSmooth, out smoothValue);
            propsBar.Items.Add(new ToolStripSeparator());
            undoBtn = AddButton(propsBar, null, IconKind.Undo, L.T("Hoàn tác"), "Ctrl+Z", Undo);
            redoBtn = AddButton(propsBar, null, IconKind.Redo, L.T("Làm lại"), "Ctrl+Y", Redo);
            propsBar.Items.Add(new ToolStripSeparator());
            AddButton(propsBar, null, IconKind.Folder, L.T("Mở thư mục ảnh đã chụp"), null, Library.OpenFolder);
            propsBar.Items.Add(new ToolStripSeparator());
            AddButton(propsBar, L.T("−"), null, L.T("Thu nhỏ"), "Ctrl+-", () => SetZoom(zoom / 1.25f, null));
            zoomLabel = new ToolStripLabel("100%") { AutoSize = false, Width = Px(46) };
            propsBar.Items.Add(zoomLabel);
            AddButton(propsBar, "+", null, L.T("Phóng to"), "Ctrl++", () => SetZoom(zoom * 1.25f, null));
            AddButton(propsBar, L.T("Vừa"), null, L.T("Vừa cửa sổ"), "Ctrl+0", FitZoom);
            AddButton(propsBar, "1:1", null, L.T("Kích thước thật"), "Ctrl+1", () => SetZoom(1f, null));

            host = new ScrollHost { Dock = DockStyle.Fill, AutoScroll = true, BackColor = Theme.Canvas };
            canvas = new CanvasControl { Location = Point.Empty, BackColor = host.BackColor };
            host.Controls.Add(canvas);
            host.Resize += (s, e) => LayoutCanvas();
            canvas.BufferedPaint += Canvas_Paint;
            canvas.MouseDown += Canvas_MouseDown;
            canvas.MouseMove += Canvas_MouseMove;
            canvas.MouseUp += Canvas_MouseUp;
            canvas.MouseWheel += Canvas_MouseWheel;
            canvas.MouseLeave += (s, e) => posLabel.Text = "";

            var status = new StatusStrip();
            sizeLabel = new ToolStripStatusLabel();
            posLabel = new ToolStripStatusLabel { AutoSize = false, Width = Px(110), TextAlign = ContentAlignment.MiddleLeft };
            infoLabel = new ToolStripStatusLabel { Spring = true, TextAlign = ContentAlignment.MiddleLeft };
            status.Items.AddRange(new ToolStripItem[] { sizeLabel, posLabel, infoLabel });
            ShowHint();

            Controls.Add(host);
            Controls.Add(propsBar);
            Controls.Add(toolsBar);
            Controls.Add(status);
        }

        void AddTool(Tool t, IconKind icon, string label, char key, string tip)
        {
            var b = new ToolStripButton(label, Icons.Draw(icon, toolsBar.ImageScalingSize.Width), (s, e) => SetTool(t))
            {
                TextImageRelation = TextImageRelation.ImageAboveText,
                ToolTipText = tip + " (" + key + ")",
                Padding = new Padding(Px(2), 0, Px(2), 0),
            };
            toolsBar.Items.Add(b);
            toolButtons[t] = b;
            toolKeys[(Keys)key] = t;
        }

        static string WithKey(string tip, Hotkey key) { return key.IsNone ? tip : tip + " (" + key.ShortText + ")"; }

        void AddActionButton(string text, IconKind icon, string tip, Action action)
        {
            var b = new ToolStripButton(text, Icons.Draw(icon, toolsBar.ImageScalingSize.Width), (s, e) => action())
            {
                TextImageRelation = TextImageRelation.ImageAboveText,
                ToolTipText = tip,
                Padding = new Padding(Px(2), 0, Px(2), 0),
            };
            toolsBar.Items.Add(b);
        }

        Button AddBigButton(string text, string doneText, IconKind icon, Color back, string tip, Action action)
        {
            var font = Theme.UiFont(11f, FontStyle.Bold);
            int iconSize = Px(22);
            int textW = Math.Max(TextRenderer.MeasureText(text, font).Width, TextRenderer.MeasureText(doneText, font).Width);
            var b = new Button
            {
                Text = text,
                Tag = text,
                Image = Icons.Draw(icon, iconSize, Color.White, back),
                TextImageRelation = TextImageRelation.ImageBeforeText,
                FlatStyle = FlatStyle.Flat,
                BackColor = back,
                ForeColor = Color.White,
                Font = font,
                Size = new Size(iconSize + textW + Px(30), Px(42)),
                Padding = new Padding(Px(8), 0, Px(8), 0),
                Cursor = Cursors.Hand,
                TabStop = false,
                UseMnemonic = false,
            };
            b.FlatAppearance.BorderSize = 0;
            b.FlatAppearance.MouseOverBackColor = ControlPaint.Light(back, 0.3f);
            b.FlatAppearance.MouseDownBackColor = ControlPaint.Dark(back, 0.1f);
            using (var path = Icons.RoundedRect(new RectangleF(0, 0, b.Width, b.Height), Px(7))) b.Region = new Region(path);
            b.Click += (s, e) => action();
            bigTips.SetToolTip(b, tip);
            toolsBar.Items.Add(new ToolStripControlHost(b)
            {
                Alignment = ToolStripItemAlignment.Right,
                Overflow = ToolStripItemOverflow.Never,
                AutoSize = false,
                Size = b.Size,
                Margin = new Padding(Px(3), Px(3), Px(3), Px(3)),
            });
            return b;
        }

        // Briefly shows "✓ Đã lưu" / "✓ Đã chép" on a big button so a click visibly did something.
        void Flash(Button b, string text)
        {
            b.Text = text;
            var t = new Timer { Interval = 1500 };
            t.Tick += (s, e) => { t.Stop(); t.Dispose(); if (!b.IsDisposed) b.Text = (string)b.Tag; };
            t.Start();
        }

        void RunOcr()
        {
            CommitText();
            using (var flat = Renderer.Render(baseImg, shapes)) runOcr(flat);
        }

        ToolStripButton AddButton(ToolStrip bar, string text, IconKind? icon, string tip, string shortcut, Action action)
        {
            var b = new ToolStripButton(text);
            if (icon.HasValue)
            {
                b.Image = Icons.Draw(icon.Value, bar.ImageScalingSize.Width);
                b.DisplayStyle = text == null ? ToolStripItemDisplayStyle.Image : ToolStripItemDisplayStyle.ImageAndText;
            }
            else b.DisplayStyle = ToolStripItemDisplayStyle.Text;
            b.ToolTipText = tip + (shortcut != null ? " (" + shortcut + ")" : "");
            b.Click += (s, e) => action();
            bar.Items.Add(b);
            return b;
        }

        void SizeToImage()
        {
            Rectangle wa = Screen.FromPoint(Cursor.Position).WorkingArea;
            int chromeW = Px(70);
            int chromeH = toolsBar.PreferredSize.Height + propsBar.PreferredSize.Height + Px(110);
            int w = Math.Min(wa.Width * 9 / 10, Math.Max(MinimumSize.Width, baseImg.Width + chromeW));
            int h = Math.Min(wa.Height * 9 / 10, Math.Max(MinimumSize.Height, baseImg.Height + chromeH));
            StartPosition = FormStartPosition.Manual;
            Bounds = new Rectangle(wa.X + (wa.Width - w) / 2, wa.Y + (wa.Height - h) / 2, w, h);
        }

        protected override void OnShown(EventArgs e)
        {
            base.OnShown(e);
            FitZoom();
            canvas.Focus();
        }

        void ShowHint()
        {
            infoLabel.Text = L.T("Kéo để vẽ • Shift: giữ thẳng/vuông • Ctrl+lăn chuột: phóng to • Ảnh đã tự lưu và sao chép vào clipboard");
        }

        void UpdateTitle()
        {
            string name = filePath != null ? Path.GetFileName(filePath) : L.T("Ảnh chưa lưu");
            Text = (dirty ? L.T("● ") : "") + name + L.T(" — MiniSnap");
        }

        void UpdateToolButtons()
        {
            foreach (var kv in toolButtons) kv.Value.Checked = kv.Key == tool;
            canvas.Cursor = tool == Tool.Select ? Cursors.Default : tool == Tool.Text ? Cursors.IBeam : Cursors.Cross;
            UpdateBlurProps();
        }

        void UpdateSwatches()
        {
            int size = propsBar.ImageScalingSize.Width;
            bool matched = false;
            foreach (var kv in swatches)
            {
                bool on = kv.Key.ToArgb() == color.ToArgb();
                matched |= on;
                var old = kv.Value.Image;
                kv.Value.Image = Icons.Swatch(kv.Key, size, on);
                if (old != null) old.Dispose();
            }
            var prev = colorButton.Image;
            colorButton.Image = Icons.Swatch(color, size, !matched);
            if (prev != null) prev.Dispose();
        }

        void UpdateUndoButtons()
        {
            undoBtn.Enabled = undo.Count > 0;
            redoBtn.Enabled = redo.Count > 0;
        }

        // ---------- Rendering, zoom, layout ----------

        void Rerender()
        {
            var old = cache;
            cache = Renderer.Render(baseImg, shapes);
            if (old != null) old.Dispose();
            sizeLabel.Text = baseImg.Width + L.T(" × ") + baseImg.Height + " px";
            canvas.Invalidate();
            if (cellSlider != null) UpdateBlurProps();
        }

        Size ScaledSize { get { return new Size((int)Math.Ceiling(baseImg.Width * zoom), (int)Math.Ceiling(baseImg.Height * zoom)); } }

        void LayoutCanvas()
        {
            int margin = Px(24);
            Size img = ScaledSize;
            int availW = host.Width, availH = host.Height;
            bool needV = img.Height + 2 * margin > availH;
            if (needV) availW -= SystemInformation.VerticalScrollBarWidth;
            if (img.Width + 2 * margin > availW)
            {
                availH -= SystemInformation.HorizontalScrollBarHeight;
                if (!needV && img.Height + 2 * margin > availH) availW -= SystemInformation.VerticalScrollBarWidth;
            }
            canvas.Size = new Size(Math.Max(availW, img.Width + 2 * margin), Math.Max(availH, img.Height + 2 * margin));
            canvas.Invalidate();
        }

        Point ImageOffset
        {
            get
            {
                Size img = ScaledSize;
                return new Point((canvas.Width - img.Width) / 2, (canvas.Height - img.Height) / 2);
            }
        }

        PointF ToImage(Point p)
        {
            var o = ImageOffset;
            return new PointF((p.X - o.X) / zoom, (p.Y - o.Y) / zoom);
        }

        PointF ToCanvas(PointF p)
        {
            var o = ImageOffset;
            return new PointF(p.X * zoom + o.X, p.Y * zoom + o.Y);
        }

        void SetZoom(float z, Point? anchor)
        {
            CommitText();
            float maxZoom = Math.Min(8f, (float)MaxCanvasPixels / Math.Max(baseImg.Width, baseImg.Height));
            z = Math.Max(0.05f, Math.Min(maxZoom, z));
            Point a = anchor ?? new Point(host.ClientSize.Width / 2 - canvas.Left, host.ClientSize.Height / 2 - canvas.Top);
            PointF imgPt = ToImage(a);
            var clientPt = new Point(a.X + canvas.Left, a.Y + canvas.Top);
            zoom = z;
            LayoutCanvas();
            PointF np = ToCanvas(imgPt);
            host.AutoScrollPosition = new Point((int)(np.X - clientPt.X), (int)(np.Y - clientPt.Y));
            zoomLabel.Text = Math.Round(zoom * 100) + "%";
            canvas.Invalidate();
        }

        void FitZoom()
        {
            int margin = Px(24);
            float z = Math.Min(1f, Math.Min((host.Width - 2f * margin) / baseImg.Width, (host.Height - 2f * margin) / baseImg.Height));
            SetZoom(z, null);
        }

        void Canvas_Paint(object sender, PaintEventArgs e)
        {
            var g = e.Graphics;
            var o = ImageOffset;
            Size img = ScaledSize;
            var dest = new Rectangle(o.X, o.Y, img.Width, img.Height);
            using (var shadow = new SolidBrush(Color.FromArgb(70, 0, 0, 0))) g.FillRectangle(shadow, dest.X + 3, dest.Y + 3, dest.Width, dest.Height);
            // Only scale the part of the image that is actually on screen.
            var visible = Rectangle.Intersect(dest, e.ClipRectangle);
            if (visible.Width > 0 && visible.Height > 0)
            {
                var src = new RectangleF((visible.X - o.X) / zoom, (visible.Y - o.Y) / zoom, visible.Width / zoom, visible.Height / zoom);
                g.InterpolationMode = zoom >= 1f ? InterpolationMode.NearestNeighbor : InterpolationMode.HighQualityBilinear;
                g.PixelOffsetMode = PixelOffsetMode.Half;
                g.DrawImage(cache, visible, src, GraphicsUnit.Pixel);
                g.PixelOffsetMode = PixelOffsetMode.Default;
            }

            var saved = g.Save();
            g.TranslateTransform(o.X, o.Y);
            g.ScaleTransform(zoom, zoom);
            g.SmoothingMode = SmoothingMode.AntiAlias;
            if (current != null) current.Draw(g);
            if (selected != null && tool == Tool.Select)
            {
                var b = selected.Bounds;
                b.Inflate(3 / zoom, 3 / zoom);
                using (var pen = new Pen(Color.FromArgb(30, 140, 255), 1.5f / zoom) { DashStyle = DashStyle.Dash })
                    g.DrawRectangle(pen, b.X, b.Y, b.Width, b.Height);
            }
            if (cropping)
            {
                using (var region = new Region(new RectangleF(0, 0, baseImg.Width, baseImg.Height)))
                using (var br = new SolidBrush(Color.FromArgb(140, 0, 0, 0)))
                {
                    region.Exclude(cropRect);
                    g.FillRegion(br, region);
                }
                using (var pen = new Pen(Color.White, 1.5f / zoom) { DashStyle = DashStyle.Dash })
                    g.DrawRectangle(pen, cropRect.X, cropRect.Y, cropRect.Width, cropRect.Height);
            }
            g.Restore(saved);
        }

        // ---------- Mouse ----------

        void Canvas_MouseDown(object sender, MouseEventArgs e)
        {
            canvas.Focus();
            if (textBox != null) { CommitText(); return; }
            if (e.Button != MouseButtons.Left) return;
            PointF p = ToImage(e.Location);
            mouseDown = true;
            downPt = lastPt = p;
            switch (tool)
            {
                case Tool.Select:
                    selected = HitTest(p);
                    movedSelected = false;
                    UpdateBlurProps();
                    if (e.Clicks == 2 && selected is TextShape)
                    {
                        mouseDown = false;
                        BeginTextEdit((TextShape)selected);
                    }
                    canvas.Invalidate();
                    break;
                case Tool.Text:
                    mouseDown = false;
                    var hitText = HitTest(p) as TextShape;
                    if (hitText != null) BeginTextEdit(hitText);
                    else BeginTextEdit(p, "", color, width);
                    break;
                case Tool.Step:
                    mouseDown = false;
                    PushUndo();
                    shapes.Add(new StepShape { Center = p, Number = NextStep(), Color = color, Width = width });
                    Rerender();
                    break;
                case Tool.Crop:
                    cropping = true;
                    cropRect = new RectangleF(p, SizeF.Empty);
                    break;
                case Tool.Pen:
                    var pen = new PenShape { Color = color, Width = width };
                    pen.Points.Add(p);
                    current = pen;
                    canvas.Invalidate();
                    break;
                default:
                    var shape = CreateTwoPoint(tool);
                    shape.A = shape.B = p;
                    current = shape;
                    break;
            }
        }

        void Canvas_MouseMove(object sender, MouseEventArgs e)
        {
            PointF p = ToImage(e.Location);
            posLabel.Text = (int)Math.Floor(p.X) + ", " + (int)Math.Floor(p.Y);
            if (!mouseDown)
            {
                if (tool == Tool.Select) canvas.Cursor = HitTest(p) != null ? Cursors.SizeAll : Cursors.Default;
                return;
            }
            bool shift = (ModifierKeys & Keys.Shift) != 0;
            switch (tool)
            {
                case Tool.Select:
                    if (selected == null) break;
                    if (!movedSelected)
                    {
                        if (Geo.Dist(p, downPt) * zoom < 3) break;
                        PushUndo();
                        movedSelected = true;
                    }
                    selected.Offset(p.X - lastPt.X, p.Y - lastPt.Y);
                    lastPt = p;
                    Rerender();
                    break;
                case Tool.Crop:
                    var r = Geo.Norm(downPt, shift ? Constrain(downPt, p, tool) : p);
                    cropRect = RectangleF.Intersect(r, new RectangleF(0, 0, baseImg.Width, baseImg.Height));
                    infoLabel.Text = L.T("Vùng cắt: ") + (int)cropRect.Width + L.T(" × ") + (int)cropRect.Height + L.T(" px — thả chuột để cắt, Esc để huỷ");
                    canvas.Invalidate();
                    break;
                case Tool.Pen:
                    ((PenShape)current).Points.Add(p);
                    canvas.Invalidate();
                    break;
                default:
                    var two = current as TwoPointShape;
                    if (two != null)
                    {
                        two.B = shift ? Constrain(two.A, p, tool) : p;
                        canvas.Invalidate();
                    }
                    break;
            }
        }

        void Canvas_MouseUp(object sender, MouseEventArgs e)
        {
            if (!mouseDown || e.Button != MouseButtons.Left) return;
            mouseDown = false;
            if (tool == Tool.Crop)
            {
                cropping = false;
                ShowHint();
                var r = Rectangle.Round(cropRect);
                if (r.Width >= 4 && r.Height >= 4) ApplyCrop(r);
                canvas.Invalidate();
                return;
            }
            if (current == null) return;
            var two = current as TwoPointShape;
            bool tooSmall = two != null && Geo.Dist(two.A, two.B) * zoom < 4;
            if (!tooSmall)
            {
                PushUndo();
                shapes.Add(current);
            }
            current = null;
            Rerender();
        }

        void Canvas_MouseWheel(object sender, MouseEventArgs e)
        {
            if ((ModifierKeys & Keys.Control) == 0) return;
            var he = e as HandledMouseEventArgs;
            if (he != null) he.Handled = true;
            SetZoom(e.Delta > 0 ? zoom * 1.15f : zoom / 1.15f, e.Location);
        }

        TwoPointShape CreateTwoPoint(Tool t)
        {
            TwoPointShape s;
            switch (t)
            {
                case Tool.Rectangle: s = new RectShape(); break;
                case Tool.Ellipse: s = new EllipseShape(); break;
                case Tool.Line: s = new LineShape(); break;
                case Tool.Highlight: s = new HighlightShape(); break;
                case Tool.Blur: s = new BlurShape { Cell = blurCell, Smooth = blurSmooth }; break;
                default: s = new ArrowShape(); break;
            }
            s.Color = color;
            s.Width = width;
            return s;
        }

        static PointF Constrain(PointF a, PointF b, Tool t)
        {
            float dx = b.X - a.X, dy = b.Y - a.Y;
            if (t == Tool.Line || t == Tool.Arrow)
            {
                double step = Math.PI / 4;
                double ang = Math.Round(Math.Atan2(dy, dx) / step) * step;
                double len = Math.Sqrt(dx * dx + dy * dy);
                return new PointF(a.X + (float)(Math.Cos(ang) * len), a.Y + (float)(Math.Sin(ang) * len));
            }
            float m = Math.Max(Math.Abs(dx), Math.Abs(dy));
            return new PointF(a.X + (dx < 0 ? -m : m), a.Y + (dy < 0 ? -m : m));
        }

        Shape HitTest(PointF p)
        {
            for (int i = shapes.Count - 1; i >= 0; i--)
                if (shapes[i].HitTest(p, 5 / zoom)) return shapes[i];
            return null;
        }

        int NextStep()
        {
            return shapes.OfType<StepShape>().Select(s => s.Number).DefaultIfEmpty(0).Max() + 1;
        }

        void ApplyCrop(Rectangle r)
        {
            PushUndo();
            var nb = new Bitmap(r.Width, r.Height, PixelFormat.Format32bppPArgb);
            using (var g = Graphics.FromImage(nb))
            {
                g.CompositingMode = CompositingMode.SourceCopy;
                g.DrawImage(baseImg, new Rectangle(0, 0, r.Width, r.Height), r, GraphicsUnit.Pixel);
            }
            baseImg = nb;
            foreach (var s in shapes) s.Offset(-r.X, -r.Y);
            selected = null;
            Rerender();
            FitZoom();
        }

        // ---------- Text editing ----------

        void BeginTextEdit(TextShape ts)
        {
            PushUndo();
            editingIndex = shapes.IndexOf(ts);
            shapes.Remove(ts);
            selected = null;
            Rerender();
            BeginTextEdit(ts.Pos, ts.Text, ts.Color, ts.Width);
            editingText = ts;
        }

        void BeginTextEdit(PointF pos, string text, Color c, float w)
        {
            editingText = null;
            textPos = pos;
            textColor = c;
            textWidth = w;
            var cp = ToCanvas(pos);
            textBox = new TextBox
            {
                Multiline = true,
                AcceptsReturn = true,
                BorderStyle = BorderStyle.FixedSingle,
                Text = text.Replace("\n", "\r\n"),
                ForeColor = c,
                BackColor = Geo.IsLight(c) ? Color.FromArgb(50, 50, 55) : Color.White,
                Font = new Font("Segoe UI", Math.Max(6f, TextShape.FontSizeFor(w) * zoom), FontStyle.Bold, GraphicsUnit.Pixel),
                Location = new Point((int)cp.X - 4, (int)cp.Y - 4),
            };
            textBox.TextChanged += (s, e) => ResizeTextBox();
            textBox.KeyDown += TextBox_KeyDown;
            canvas.Controls.Add(textBox);
            ResizeTextBox();
            textBox.Focus();
            textBox.SelectionStart = textBox.Text.Length;
            infoLabel.Text = L.T("Gõ chữ • Enter: xong • Shift+Enter: xuống dòng • Esc: huỷ");
        }

        void ResizeTextBox()
        {
            if (textBox == null) return;
            string t = textBox.Text.Length == 0 ? "Wg" : textBox.Text + " ";
            var sz = TextRenderer.MeasureText(t, textBox.Font);
            textBox.Size = new Size(Math.Max(sz.Width + 14, Px(80)), sz.Height + 10);
        }

        void TextBox_KeyDown(object sender, KeyEventArgs e)
        {
            if (e.KeyCode == Keys.Enter && !e.Shift) { e.SuppressKeyPress = true; CommitText(); }
            else if (e.KeyCode == Keys.Escape) { e.SuppressKeyPress = true; CancelText(); }
        }

        void CloseTextBox()
        {
            var tb = textBox;
            textBox = null;
            canvas.Controls.Remove(tb);
            tb.Dispose();
            ShowHint();
        }

        void CommitText()
        {
            if (textBox == null) return;
            string text = textBox.Text.Replace("\r\n", "\n").TrimEnd();
            CloseTextBox();
            if (text.Length > 0)
            {
                if (editingText == null) PushUndo();
                var ts = new TextShape { Pos = textPos, Text = text, Color = textColor, Width = textWidth };
                if (editingText != null) shapes.Insert(Math.Min(editingIndex, shapes.Count), ts);
                else shapes.Add(ts);
            }
            editingText = null;
            Rerender();
            canvas.Focus();
        }

        void CancelText()
        {
            if (textBox == null) return;
            CloseTextBox();
            if (editingText != null)
            {
                shapes.Insert(Math.Min(editingIndex, shapes.Count), editingText);
                if (undo.Count > 0) undo.Pop();
                UpdateUndoButtons();
            }
            editingText = null;
            Rerender();
            canvas.Focus();
        }

        // ---------- Tools, colour, width ----------

        void SetTool(Tool t)
        {
            CommitText();
            tool = t;
            current = null;
            cropping = false;
            if (t != Tool.Select) selected = null;
            UpdateToolButtons();
            ShowHint();
            canvas.Invalidate();
            canvas.Focus();
        }

        void SetColor(Color c)
        {
            color = c;
            UpdateSwatches();
            if (textBox != null)
            {
                textColor = c;
                textBox.ForeColor = c;
                textBox.BackColor = Geo.IsLight(c) ? Color.FromArgb(50, 50, 55) : Color.White;
                textBox.Focus();
                return;
            }
            if (selected != null && tool == Tool.Select)
            {
                PushUndo();
                selected.Color = c;
                Rerender();
            }
        }

        void SetWidth(float w)
        {
            width = w;
            widthBox.Text = ((int)w).ToString();
            foreach (ToolStripMenuItem mi in widthBox.DropDownItems) mi.Checked = mi.Text == widthBox.Text;
            if (textBox != null)
            {
                textWidth = w;
                textBox.Font = new Font("Segoe UI", TextShape.FontSizeFor(w) * zoom, FontStyle.Bold, GraphicsUnit.Pixel);
                ResizeTextBox();
                return;
            }
            if (selected != null && tool == Tool.Select)
            {
                PushUndo();
                selected.Width = w;
                Rerender();
            }
        }

        FlatSlider AddBlurSlider(string label, string tip, int min, int max, int value, out ToolStripLabel valueLabel)
        {
            var name = new ToolStripLabel(label) { ToolTipText = tip, Visible = false };
            var slider = new FlatSlider { Minimum = min, Maximum = max, Value = value, Size = new Size(Px(110), Px(22)), BackColor = Theme.Surface };
            var hostItem = new ToolStripControlHost(slider) { AutoSize = false, Size = slider.Size, ToolTipText = tip, Visible = false, Margin = new Padding(Px(2), Px(1), Px(2), Px(1)) };
            var shown = new ToolStripLabel(value.ToString()) { AutoSize = false, Width = Px(24), TextAlign = ContentAlignment.MiddleLeft, Visible = false };
            valueLabel = shown;
            slider.Changing += (s, e) => sliderUndoPending = true;
            slider.ValueChanged += (s, e) => SetBlur(cellSlider.Value, smoothSlider.Value);
            foreach (var item in new ToolStripItem[] { name, hostItem, shown })
            {
                propsBar.Items.Add(item);
                blurItems.Add(item);
            }
            return slider;
        }

        BlurShape SelectedBlur { get { return tool == Tool.Select ? selected as BlurShape : null; } }

        // Shows the blur settings instead of the stroke width while the blur tool, or a blurred area, is active.
        void UpdateBlurProps()
        {
            var sel = SelectedBlur;
            bool show = tool == Tool.Blur || sel != null;
            if (sel != null)
            {
                cellSlider.Value = sel.Cell;
                smoothSlider.Value = sel.Smooth;
            }
            else
            {
                cellSlider.Value = blurCell;
                smoothSlider.Value = blurSmooth;
            }
            cellValue.Text = cellSlider.Value.ToString();
            smoothValue.Text = smoothSlider.Value.ToString();
            if (show == blurPropsShown) return;
            blurPropsShown = show;
            propsBar.SuspendLayout();
            foreach (var item in blurItems) item.Visible = show;
            foreach (var item in widthItems) item.Visible = !show;
            propsBar.ResumeLayout();
        }

        void SetBlur(int cell, int smooth)
        {
            cellValue.Text = cell.ToString();
            smoothValue.Text = smooth.ToString();
            var sel = SelectedBlur;
            if (sel == null)
            {
                blurCell = cell;
                blurSmooth = smooth;
                return;
            }
            if (sel.Cell == cell && sel.Smooth == smooth) return;
            // One undo step per drag of a slider.
            if (sliderUndoPending) { PushUndo(); sliderUndoPending = false; }
            sel.Cell = cell;
            sel.Smooth = smooth;
            blurCell = cell;
            blurSmooth = smooth;
            Rerender();
        }

        void PickColor()
        {
            using (var dlg = new ColorDialog { Color = color, FullOpen = true })
                if (dlg.ShowDialog(this) == DialogResult.OK) SetColor(dlg.Color);
        }

        // ---------- Undo / redo ----------

        State Snapshot()
        {
            return new State { Base = baseImg, Shapes = shapes.Select(s => s.Clone()).ToList() };
        }

        void PushUndo()
        {
            undo.Push(Snapshot());
            redo.Clear();
            dirty = true;
            UpdateUndoButtons();
            UpdateTitle();
        }

        void Undo()
        {
            CommitText();
            if (undo.Count == 0) return;
            redo.Push(Snapshot());
            Restore(undo.Pop());
        }

        void Redo()
        {
            CommitText();
            if (redo.Count == 0) return;
            undo.Push(Snapshot());
            Restore(redo.Pop());
        }

        void Restore(State s)
        {
            bool sizeChanged = s.Base.Size != baseImg.Size;
            baseImg = s.Base;
            shapes = s.Shapes;
            selected = null;
            dirty = true;
            Rerender();
            if (sizeChanged) FitZoom();
            UpdateUndoButtons();
            UpdateTitle();
        }

        public void UseTool(Tool t) { SetTool(t); }

        public void LoadShapes(IEnumerable<Shape> list)
        {
            shapes = list.Select(s => s.Clone()).ToList();
            Rerender();
        }

        void DeleteSelected()
        {
            if (selected == null) return;
            PushUndo();
            shapes.Remove(selected);
            selected = null;
            Rerender();
        }

        void NudgeSelected(int dx, int dy)
        {
            if (selected == null) return;
            PushUndo();
            selected.Offset(dx, dy);
            Rerender();
        }

        // ---------- Clipboard and files ----------

        void CopyToClipboard()
        {
            CommitText();
            using (var flat = Renderer.Render(baseImg, shapes))
            using (var rgb = new Bitmap(flat.Width, flat.Height, PixelFormat.Format24bppRgb))
            {
                using (var g = Graphics.FromImage(rgb))
                    g.DrawImage(flat, new Rectangle(0, 0, flat.Width, flat.Height), new Rectangle(0, 0, flat.Width, flat.Height), GraphicsUnit.Pixel);
                try
                {
                    Clipboard.SetImage(rgb);
                    infoLabel.Text = L.T("Đã sao chép ảnh vào clipboard — dán (Ctrl+V) vào Zalo, Word, email...");
                    Flash(copyBtn, L.T("✓ Đã chép"));
                }
                catch (ExternalException) { infoLabel.Text = L.T("Clipboard đang bận, hãy thử lại."); }
            }
        }

        bool Save(bool saveAs)
        {
            CommitText();
            string path = filePath;
            if (saveAs || string.IsNullOrEmpty(path))
            {
                using (var dlg = new SaveFileDialog
                {
                    Filter = "PNG (*.png)|*.png|JPEG (*.jpg)|*.jpg;*.jpeg|BMP (*.bmp)|*.bmp|GIF (*.gif)|*.gif",
                    FileName = path != null ? Path.GetFileName(path) : "MiniSnap.png",
                    InitialDirectory = path != null ? Path.GetDirectoryName(path) : Library.Folder,
                    AddExtension = true,
                    DefaultExt = "png",
                })
                {
                    if (dlg.ShowDialog(this) != DialogResult.OK) return false;
                    path = dlg.FileName;
                }
            }
            try
            {
                using (var flat = Renderer.Render(baseImg, shapes)) SaveImage(flat, path);
            }
            catch (Exception ex)
            {
                MessageBox.Show(this, L.T("Không lưu được ảnh:\n") + ex.Message, "MiniSnap", MessageBoxButtons.OK, MessageBoxIcon.Warning);
                return false;
            }
            filePath = path;
            dirty = false;
            UpdateTitle();
            infoLabel.Text = L.T("Đã lưu: ") + path;
            Flash(saveAs ? saveAsBtn : saveBtn, L.T("✓ Đã lưu"));
            return true;
        }

        static void SaveImage(Bitmap bmp, string path)
        {
            string ext = Path.GetExtension(path).ToLowerInvariant();
            if (ext == ".jpg" || ext == ".jpeg")
            {
                using (var rgb = new Bitmap(bmp.Width, bmp.Height, PixelFormat.Format24bppRgb))
                {
                    using (var g = Graphics.FromImage(rgb))
                    {
                        g.Clear(Color.White);
                        g.DrawImage(bmp, new Rectangle(0, 0, bmp.Width, bmp.Height), new Rectangle(0, 0, bmp.Width, bmp.Height), GraphicsUnit.Pixel);
                    }
                    var codec = ImageCodecInfo.GetImageEncoders().First(c => c.FormatID == ImageFormat.Jpeg.Guid);
                    using (var ps = new EncoderParameters(1))
                    {
                        ps.Param[0] = new EncoderParameter(System.Drawing.Imaging.Encoder.Quality, 92L);
                        rgb.Save(path, codec, ps);
                    }
                }
            }
            else if (ext == ".bmp") bmp.Save(path, ImageFormat.Bmp);
            else if (ext == ".gif") bmp.Save(path, ImageFormat.Gif);
            else bmp.Save(path, ImageFormat.Png);
        }

        // ---------- Keyboard ----------

        protected override bool ProcessCmdKey(ref Message msg, Keys keyData)
        {
            if (textBox != null && textBox.Focused) return base.ProcessCmdKey(ref msg, keyData);
            switch (keyData)
            {
                case Keys.Control | Keys.Z: Undo(); return true;
                case Keys.Control | Keys.Y:
                case Keys.Control | Keys.Shift | Keys.Z: Redo(); return true;
                case Keys.Control | Keys.C: CopyToClipboard(); return true;
                case Keys.Control | Keys.S: Save(false); return true;
                case Keys.Control | Keys.Shift | Keys.S: Save(true); return true;
                case Keys.Control | Keys.N: newCapture(); return true;
                case Keys.Control | Keys.Oemplus:
                case Keys.Control | Keys.Add: SetZoom(zoom * 1.25f, null); return true;
                case Keys.Control | Keys.OemMinus:
                case Keys.Control | Keys.Subtract: SetZoom(zoom / 1.25f, null); return true;
                case Keys.Control | Keys.D0:
                case Keys.Control | Keys.NumPad0: FitZoom(); return true;
                case Keys.Control | Keys.D1:
                case Keys.Control | Keys.NumPad1: SetZoom(1f, null); return true;
                case Keys.Delete:
                case Keys.Back: DeleteSelected(); return true;
                case Keys.Left: NudgeSelected(-1, 0); return true;
                case Keys.Right: NudgeSelected(1, 0); return true;
                case Keys.Up: NudgeSelected(0, -1); return true;
                case Keys.Down: NudgeSelected(0, 1); return true;
                case Keys.Escape:
                    if (mouseDown) { mouseDown = false; current = null; cropping = false; ShowHint(); }
                    selected = null;
                    canvas.Invalidate();
                    return true;
            }
            Tool t;
            if (toolKeys.TryGetValue(keyData, out t)) { SetTool(t); return true; }
            return base.ProcessCmdKey(ref msg, keyData);
        }

        protected override void OnFormClosing(FormClosingEventArgs e)
        {
            CommitText();
            if (dirty && !SkipSavePrompt)
            {
                var r = MessageBox.Show(this, L.T("Lưu các thay đổi vào ảnh?"), "MiniSnap", MessageBoxButtons.YesNoCancel, MessageBoxIcon.Question);
                if (r == DialogResult.Cancel || (r == DialogResult.Yes && !Save(false)))
                {
                    e.Cancel = true;
                    return;
                }
            }
            base.OnFormClosing(e);
        }

        protected override void OnFormClosed(FormClosedEventArgs e)
        {
            if (cache != null) cache.Dispose();
            base.OnFormClosed(e);
        }
    }
}
