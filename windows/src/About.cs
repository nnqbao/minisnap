using System;
using System.Diagnostics;
using System.Drawing;
using System.Reflection;
using System.Windows.Forms;

namespace MiniSnap
{
    static class AppInfo
    {
        public const string Author = "Nguyễn Năng Quốc Bảo";
        public const string Email = "nnqbao@gmail.com";
        public const string Repo = "https://github.com/nnqbao/minisnap";

        public static string Version
        {
            get
            {
                var v = Assembly.GetExecutingAssembly().GetName().Version;
                return v.Major + "." + v.Minor + "." + v.Build;
            }
        }

        public static void Open(string target)
        {
            try { Process.Start(target); }
            catch (Exception ex) { MessageBox.Show(ex.Message, "MiniSnap"); }
        }
    }

    class AboutForm : Form
    {
        public AboutForm(Action checkUpdates)
        {
            float ui;
            using (var g = CreateGraphics()) ui = g.DpiX / 96f;
            Func<float, int> S = v => (int)Math.Round(v * ui);

            Text = L.T("Giới thiệu MiniSnap");
            Icon = AppIcon.Get();
            Font = Theme.UiFont(9.5f);
            FormBorderStyle = FormBorderStyle.FixedDialog;
            MaximizeBox = MinimizeBox = false;
            StartPosition = FormStartPosition.CenterScreen;
            AutoSize = true;
            AutoSizeMode = AutoSizeMode.GrowAndShrink;
            ShowInTaskbar = true;

            var root = new TableLayoutPanel { AutoSize = true, ColumnCount = 2, Padding = new Padding(S(24), S(22), S(24), S(18)) };
            root.ColumnStyles.Add(new ColumnStyle(SizeType.AutoSize));
            root.ColumnStyles.Add(new ColumnStyle(SizeType.AutoSize));

            var logo = new PictureBox { Image = AppIcon.Render(S(72)), Size = new Size(S(72), S(72)), Margin = new Padding(0, S(2), S(20), 0) };
            root.Controls.Add(logo, 0, 0);
            root.SetRowSpan(logo, 8);

            Func<string, Font, Color, int, Label> add = (text, font, color, top) =>
            {
                var l = new Label { Text = text, Font = font, ForeColor = color, AutoSize = true, MaximumSize = new Size(S(380), 0), Margin = new Padding(0, top, 0, 0), UseMnemonic = false };
                root.Controls.Add(l, 1, root.RowCount++);
                return l;
            };
            root.RowCount = 0;
            add("MiniSnap", Theme.UiFont(20f, FontStyle.Bold), Theme.Text, 0);
            add(L.T("Phiên bản ") + AppInfo.Version, Font, Theme.TextSecondary, S(2));
            add(L.T("Đây là phần mềm chụp ảnh, quay phim màn hình miễn phí, mã nguồn mở dành cho mọi người."), Theme.UiFont(10.5f), Theme.Text, S(14));
            add(L.T("Tác giả: ") + AppInfo.Author, Font, Theme.Text, S(14));

            var email = MakeLink(L.T("Liên hệ: "), AppInfo.Email, "mailto:" + AppInfo.Email, S);
            root.Controls.Add(email, 1, root.RowCount++);
            var repo = MakeLink(L.T("Mã nguồn: "), AppInfo.Repo.Replace("https://", ""), AppInfo.Repo, S);
            root.Controls.Add(repo, 1, root.RowCount++);
            var privacy = MakeLink(L.T("Quyền riêng tư: "), L.T("MiniSnap không thu thập dữ liệu"), AppInfo.Repo + "/blob/main/PRIVACY.md", S);
            root.Controls.Add(privacy, 1, root.RowCount++);
            add(L.T("Giấy phép MIT — miễn phí, mã nguồn mở"), Font, Theme.TextSecondary, S(4));

            var buttons = new FlowLayoutPanel { AutoSize = true, FlowDirection = FlowDirection.LeftToRight, Margin = new Padding(0, S(18), 0, 0), WrapContents = false };
            var gh = new FluentButton { Text = L.T("Mở trang GitHub"), Primary = true, MinimumSize = new Size(S(130), S(32)) };
            gh.Click += (s, e) => AppInfo.Open(AppInfo.Repo);
            var close = new FluentButton { Text = L.T("Đóng"), MinimumSize = new Size(S(96), S(32)) };
            close.Click += (s, e) => Close();
            var upd = new FluentButton { Text = L.T("Kiểm tra cập nhật"), MinimumSize = new Size(S(130), S(32)) };
            upd.Click += (s, e) => checkUpdates();
            buttons.Controls.Add(gh);
            buttons.Controls.Add(upd);
            buttons.Controls.Add(close);
            root.Controls.Add(buttons, 1, root.RowCount++);
            CancelButton = close;

            Controls.Add(root);
            Theme.Apply(this);
            Shown += (s, e) => close.Focus();
        }

        static Control MakeLink(string caption, string text, string target, Func<float, int> S)
        {
            var row = new FlowLayoutPanel { AutoSize = true, WrapContents = false, Margin = new Padding(0, S(4), 0, 0) };
            row.Controls.Add(new Label { Text = caption, AutoSize = true, Margin = new Padding(0), UseMnemonic = false });
            var link = new LinkLabel
            {
                Text = text,
                AutoSize = true,
                Margin = new Padding(0),
                LinkColor = Theme.Accent,
                ActiveLinkColor = Theme.Accent,
                VisitedLinkColor = Theme.Accent,
                LinkBehavior = LinkBehavior.HoverUnderline,
                UseMnemonic = false,
            };
            link.LinkClicked += (s, e) => AppInfo.Open(target);
            row.Controls.Add(link);
            return row;
        }
    }
}
