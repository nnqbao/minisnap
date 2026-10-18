using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Drawing;
using System.IO;
using System.Linq;
using System.Net;
using System.Security.Cryptography;
using System.Threading;
using System.Web.Script.Serialization;
using System.Windows.Forms;
using Microsoft.Win32;

namespace MiniSnap
{
    // Checks GitHub Releases of nnqbao/minisnap and installs a newer MiniSnap-Setup.exe in place.
    static class Updater
    {
        const string Api = "https://api.github.com/repos/nnqbao/minisnap/releases/latest";
        const string SetupAsset = "MiniSnap-Setup.exe";
        const string RegPath = @"Software\MiniSnap";

        public class Release
        {
            public Version Version;
            public string Tag, Name, Notes, PageUrl, SetupUrl, Sha256;
            public long Size;
        }

        public static Version Current
        {
            get
            {
                var v = typeof(Updater).Assembly.GetName().Version;
                return new Version(v.Major, v.Minor, Math.Max(0, v.Build));
            }
        }

        static Version ParseTag(string tag)
        {
            string t = (tag ?? "").Trim().TrimStart('v', 'V');
            int dash = t.IndexOfAny(new[] { '-', '+' });
            if (dash >= 0) t = t.Substring(0, dash);
            Version v;
            if (!Version.TryParse(t, out v)) return null;
            return new Version(v.Major, v.Minor, Math.Max(0, v.Build));
        }

        // The latest published release, or null when the repository has no release yet.
        public static Release Fetch()
        {
            ServicePointManager.SecurityProtocol |= SecurityProtocolType.Tls12;
            var req = (HttpWebRequest)WebRequest.Create(Api);
            req.UserAgent = "MiniSnap/" + Current;
            req.Accept = "application/vnd.github+json";
            req.Timeout = 15000;
            string json;
            try
            {
                using (var resp = req.GetResponse())
                using (var sr = new StreamReader(resp.GetResponseStream()))
                    json = sr.ReadToEnd();
            }
            catch (WebException ex)
            {
                var r = ex.Response as HttpWebResponse;
                if (r != null && r.StatusCode == HttpStatusCode.NotFound) return null;
                throw;
            }

            var d = new JavaScriptSerializer { MaxJsonLength = 8 * 1024 * 1024 }.Deserialize<Dictionary<string, object>>(json);
            var rel = new Release
            {
                Tag = Str(d, "tag_name"),
                Name = Str(d, "name"),
                Notes = Str(d, "body"),
                PageUrl = Str(d, "html_url"),
            };
            rel.Version = ParseTag(rel.Tag);
            var assets = d.ContainsKey("assets") ? d["assets"] as object[] : null;
            if (assets == null && d.ContainsKey("assets")) assets = (d["assets"] as System.Collections.ArrayList ?? new System.Collections.ArrayList()).ToArray();
            if (assets != null)
            {
                foreach (var o in assets)
                {
                    var a = o as Dictionary<string, object>;
                    if (a == null || !string.Equals(Str(a, "name"), SetupAsset, StringComparison.OrdinalIgnoreCase)) continue;
                    rel.SetupUrl = Str(a, "browser_download_url");
                    string digest = Str(a, "digest");
                    if (digest != null && digest.StartsWith("sha256:", StringComparison.OrdinalIgnoreCase)) rel.Sha256 = digest.Substring(7).ToLowerInvariant();
                    object size;
                    if (a.TryGetValue("size", out size) && size != null) rel.Size = Convert.ToInt64(size);
                }
            }
            return rel;
        }

        static string Str(Dictionary<string, object> d, string key)
        {
            object v;
            return d.TryGetValue(key, out v) && v != null ? v.ToString() : null;
        }

        public static bool IsNewer(Release r) { return r != null && r.Version != null && r.Version > Current; }

        // Downloads the installer to %TEMP% and checks it against the SHA-256 GitHub publishes for the asset.
        public static string Download(Release r, Action<int> progress, Func<bool> cancelled)
        {
            if (string.IsNullOrEmpty(r.SetupUrl)) throw new InvalidOperationException(L.T("Bản phát hành này không có file MiniSnap-Setup.exe."));
            var uri = new Uri(r.SetupUrl);
            if (uri.Scheme != Uri.UriSchemeHttps || !(uri.Host == "github.com" || uri.Host.EndsWith(".github.com") || uri.Host.EndsWith(".githubusercontent.com")))
                throw new InvalidOperationException(L.T("Đường dẫn tải về không phải của GitHub: ") + uri.Host);

            string dir = Path.Combine(Path.GetTempPath(), "MiniSnap-Update");
            Directory.CreateDirectory(dir);
            string path = Path.Combine(dir, "MiniSnap-Setup-" + r.Version + ".exe");
            ServicePointManager.SecurityProtocol |= SecurityProtocolType.Tls12;
            var req = (HttpWebRequest)WebRequest.Create(uri);
            req.UserAgent = "MiniSnap/" + Current;
            req.Timeout = 30000;
            using (var resp = req.GetResponse())
            using (var input = resp.GetResponseStream())
            using (var output = File.Create(path))
            using (var sha = SHA256.Create())
            {
                long total = resp.ContentLength > 0 ? resp.ContentLength : r.Size, done = 0;
                var buf = new byte[81920];
                int n;
                while ((n = input.Read(buf, 0, buf.Length)) > 0)
                {
                    if (cancelled()) throw new OperationCanceledException();
                    output.Write(buf, 0, n);
                    sha.TransformBlock(buf, 0, n, null, 0);
                    done += n;
                    if (total > 0) progress((int)(done * 100 / total));
                }
                sha.TransformFinalBlock(new byte[0], 0, 0);
                string hex = string.Concat(sha.Hash.Select(b => b.ToString("x2")));
                if (r.Sha256 != null && hex != r.Sha256)
                {
                    output.Close();
                    File.Delete(path);
                    throw new InvalidOperationException(L.T("File tải về bị sai mã kiểm tra (SHA-256). Đã huỷ cập nhật."));
                }
            }
            return path;
        }

        // ---------- Daily background check ----------

        public static bool DueForAutoCheck()
        {
            try
            {
                using (var k = Registry.CurrentUser.OpenSubKey(RegPath))
                {
                    var s = k == null ? null : k.GetValue("LastUpdateCheck") as string;
                    DateTime last;
                    return s == null || !DateTime.TryParse(s, null, System.Globalization.DateTimeStyles.RoundtripKind, out last) || (DateTime.UtcNow - last).TotalHours >= 24;
                }
            }
            catch (Exception) { return true; }
        }

        public static void MarkChecked()
        {
            try
            {
                using (var k = Registry.CurrentUser.CreateSubKey(RegPath))
                    k.SetValue("LastUpdateCheck", DateTime.UtcNow.ToString("o"));
            }
            catch (Exception) { }
        }
    }

    class UpdateForm : Form
    {
        readonly Action<string> install;
        readonly Label title, detail;
        readonly TextBox notes;
        readonly ProgressBar bar;
        readonly FluentButton primary, secondary, close;
        Updater.Release release;
        volatile bool cancel;
        bool downloading;

        // install: called with the downloaded setup path; it closes MiniSnap and runs the installer.
        public UpdateForm(Action<string> install, Updater.Release known)
        {
            this.install = install;
            float ui;
            using (var g = CreateGraphics()) ui = g.DpiX / 96f;
            Func<float, int> S = v => (int)Math.Round(v * ui);

            Text = L.T("Cập nhật MiniSnap");
            Icon = AppIcon.Get();
            Font = Theme.UiFont(9.5f);
            FormBorderStyle = FormBorderStyle.FixedDialog;
            MaximizeBox = MinimizeBox = false;
            StartPosition = FormStartPosition.CenterScreen;
            ClientSize = new Size(S(520), S(380));

            var pad = S(22);
            title = new Label { AutoSize = true, Location = new Point(pad, S(20)), Font = Theme.UiFont(13f, FontStyle.Bold), UseMnemonic = false, MaximumSize = new Size(S(476), 0) };
            detail = new Label { AutoSize = true, Location = new Point(pad, S(54)), ForeColor = Theme.TextSecondary, UseMnemonic = false, MaximumSize = new Size(S(476), 0) };
            notes = new TextBox { Multiline = true, ReadOnly = true, ScrollBars = ScrollBars.Vertical, Location = new Point(pad, S(100)), Size = new Size(S(476), S(180)), Visible = false, BorderStyle = BorderStyle.FixedSingle, TabStop = false };
            bar = new ProgressBar { Location = new Point(pad, S(292)), Size = new Size(S(476), S(6)), Visible = false };
            primary = new FluentButton { Text = L.T("Tải và cài đặt"), Primary = true, Visible = false, MinimumSize = new Size(S(140), S(32)) };
            secondary = new FluentButton { Text = L.T("Xem trên GitHub"), Visible = false, MinimumSize = new Size(S(120), S(32)) };
            close = new FluentButton { Text = L.T("Để sau"), MinimumSize = new Size(S(96), S(32)) };
            var buttons = new FlowLayoutPanel { FlowDirection = FlowDirection.RightToLeft, Location = new Point(pad, S(318)), Size = new Size(S(476), S(44)), WrapContents = false };
            buttons.Controls.Add(close);
            buttons.Controls.Add(primary);
            buttons.Controls.Add(secondary);
            Controls.AddRange(new Control[] { title, detail, notes, bar, buttons });
            CancelButton = close;

            primary.Click += (s, e) => StartDownload();
            secondary.Click += (s, e) => { if (release != null && release.PageUrl != null) AppInfo.Open(release.PageUrl); };
            close.Click += (s, e) => Close();
            Theme.Apply(this);
            notes.BackColor = Theme.Field;
            notes.ForeColor = Theme.Text;
            Shown += (s, e) => { ActiveControl = primary.Visible ? (Control)primary : close; notes.SelectionLength = 0; };

            if (known != null) Load += (s, e) => ShowResult(known, null);
            else
            {
                title.Text = L.T("Đang kiểm tra cập nhật...");
                detail.Text = L.T("Phiên bản hiện tại: ") + Updater.Current;
                Load += (s, e) => CheckAsync();
            }
        }

        void CheckAsync()
        {
            var t = new Thread(() =>
            {
                Updater.Release r = null;
                string error = null;
                try { r = Updater.Fetch(); Updater.MarkChecked(); }
                catch (Exception ex) { error = ex.Message; }
                try { BeginInvoke(new Action(() => ShowResult(r, error))); }
                catch (InvalidOperationException) { }
            });
            t.IsBackground = true;
            t.Start();
        }

        void ShowResult(Updater.Release r, string error)
        {
            release = r;
            close.Text = L.T("Đóng");
            if (error != null)
            {
                title.Text = L.T("Không kiểm tra được cập nhật");
                detail.Text = error + L.T("\nHãy kiểm tra kết nối mạng rồi thử lại.");
                return;
            }
            if (r == null)
            {
                title.Text = L.T("Bạn đang dùng bản mới nhất");
                detail.Text = L.T("Chưa có bản phát hành nào trên GitHub. Phiên bản hiện tại: ") + Updater.Current;
                return;
            }
            if (!Updater.IsNewer(r))
            {
                title.Text = L.T("Bạn đang dùng bản mới nhất");
                detail.Text = L.T("Phiên bản hiện tại: ") + Updater.Current + L.T(" — mới nhất trên GitHub: ") + (r.Version != null ? r.Version.ToString() : r.Tag);
                secondary.Visible = true;
                return;
            }
            title.Text = L.T("Có phiên bản mới: ") + r.Version;
            detail.Text = L.T("Bạn đang dùng ") + Updater.Current + L.T(". Ảnh, video và cài đặt của bạn được giữ nguyên khi cập nhật.");
            string text = string.IsNullOrWhiteSpace(r.Notes) ? (r.Name ?? r.Tag) : r.Notes;
            if (text.Length > 4000) text = text.Substring(0, 4000) + "…";
            notes.Text = text.Replace("\r\n", "\n").Replace("\n", "\r\n");
            notes.Visible = true;
            secondary.Visible = true;
            primary.Visible = r.SetupUrl != null;
            close.Text = L.T("Để sau");
            if (r.SetupUrl == null) detail.Text += L.T("\nBản này chưa có bộ cài cho Windows — hãy xem trên GitHub.");
        }

        void StartDownload()
        {
            if (downloading || release == null) return;
            downloading = true;
            primary.Enabled = secondary.Enabled = false;
            close.Text = L.T("Huỷ");
            bar.Visible = true;
            detail.Text = L.T("Đang tải bản cập nhật...");
            var r = release;
            var t = new Thread(() =>
            {
                string path = null, error = null;
                try { path = Updater.Download(r, pct => BeginInvoke(new Action(() => bar.Value = Math.Min(100, pct))), () => cancel); }
                catch (OperationCanceledException) { return; }
                catch (Exception ex) { error = ex.Message; }
                try
                {
                    BeginInvoke(new Action(() =>
                    {
                        downloading = false;
                        if (error != null)
                        {
                            detail.Text = L.T("Tải về thất bại: ") + error;
                            primary.Enabled = secondary.Enabled = true;
                            close.Text = L.T("Đóng");
                            bar.Visible = false;
                            return;
                        }
                        detail.Text = L.T("Đã tải xong. MiniSnap sẽ đóng lại để cài bản mới rồi tự mở lại.");
                        install(path);
                    }));
                }
                catch (InvalidOperationException) { }
            });
            t.IsBackground = true;
            t.Start();
        }

        protected override void OnFormClosing(FormClosingEventArgs e)
        {
            cancel = true;
            base.OnFormClosing(e);
        }
    }
}
