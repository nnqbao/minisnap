using System;
using System.Diagnostics;
using System.Drawing;
using System.Drawing.Drawing2D;
using System.IO;
using System.Linq;
using System.Reflection;
using System.Runtime.InteropServices;
using System.Threading;
using System.Windows.Forms;
using Microsoft.Win32;

[assembly: AssemblyTitle("Cài đặt MiniSnap")]
[assembly: AssemblyProduct("MiniSnap")]
[assembly: AssemblyCompany("Nguyễn Năng Quốc Bảo")]
[assembly: AssemblyVersion("1.8.1.0")]
[assembly: AssemblyFileVersion("1.8.1.0")]

namespace MiniSnap.Setup
{
    // Per-user installer: no admin rights, installs to %LocalAppData%\Programs\MiniSnap,
    // registers in "Apps & features" and doubles as the uninstaller (Uninstall.exe --uninstall).
    static class SetupProgram
    {
        public const string AppName = "MiniSnap";
        public const string Version = "1.8.1";
        public const string UninstallKey = @"Software\Microsoft\Windows\CurrentVersion\Uninstall\MiniSnap";
        public const string RunKey = @"Software\Microsoft\Windows\CurrentVersion\Run";

        [DllImport("user32.dll")] static extern bool SetProcessDpiAwarenessContext(IntPtr value);

        [STAThread]
        static void Main(string[] args)
        {
            try { SetProcessDpiAwarenessContext(new IntPtr(-4)); }
            catch (EntryPointNotFoundException) { }
            L.Load();
            Application.EnableVisualStyles();
            Application.SetCompatibleTextRenderingDefault(false);
            if (args.Any(a => a.Equals("--uninstall", StringComparison.OrdinalIgnoreCase) || a.Equals("/uninstall", StringComparison.OrdinalIgnoreCase)))
                Installer.Uninstall(args.Any(a => a.Equals("/quiet", StringComparison.OrdinalIgnoreCase)));
            else if (args.Any(a => a.Equals("--update", StringComparison.OrdinalIgnoreCase)))
                Installer.SilentUpdate();
            else
                Application.Run(new SetupForm());
        }
    }

    static class Installer
    {
        public static string DefaultFolder
        {
            get { return Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "Programs", SetupProgram.AppName); }
        }

        public static string StartMenuShortcut
        {
            get { return Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.Programs), SetupProgram.AppName + ".lnk"); }
        }

        public static string DesktopShortcut
        {
            get { return Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.DesktopDirectory), SetupProgram.AppName + ".lnk"); }
        }

        public static string InstalledFolder()
        {
            using (var k = Registry.CurrentUser.OpenSubKey(SetupProgram.UninstallKey))
                return k == null ? null : k.GetValue("InstallLocation") as string;
        }

        public static string InstalledVersion()
        {
            using (var k = Registry.CurrentUser.OpenSubKey(SetupProgram.UninstallKey))
                return k == null ? null : k.GetValue("DisplayVersion") as string;
        }

        // Keep the user's earlier choice when updating; on by default.
        public static bool AutoUpdateDefault()
        {
            using (var k = Registry.CurrentUser.OpenSubKey(@"Software\MiniSnap"))
                return k == null || !(k.GetValue("AutoUpdateCheck") is int) || (int)k.GetValue("AutoUpdateCheck") != 0;
        }

        public static Process[] RunningInstances()
        {
            return Process.GetProcessesByName(SetupProgram.AppName);
        }

        // Returns false if the user chose not to close a running MiniSnap.
        public static bool CloseRunning(IWin32Window owner)
        {
            var procs = RunningInstances();
            if (procs.Length == 0) return true;
            if (MessageBox.Show(owner, L.T("MiniSnap đang chạy và cần được đóng để tiếp tục.\nẢnh đang chỉnh sửa mà chưa lưu sẽ bị mất. Đóng MiniSnap?"),
                    L.T("Cài đặt MiniSnap"), MessageBoxButtons.OKCancel, MessageBoxIcon.Warning) != DialogResult.OK) return false;
            foreach (var p in procs)
            {
                try { p.Kill(); p.WaitForExit(5000); }
                catch (Exception) { }
            }
            return true;
        }

        static void CreateShortcut(string lnk, string target, string description)
        {
            var type = Type.GetTypeFromProgID("WScript.Shell");
            dynamic shell = Activator.CreateInstance(type);
            try
            {
                dynamic sc = shell.CreateShortcut(lnk);
                sc.TargetPath = target;
                sc.WorkingDirectory = Path.GetDirectoryName(target);
                sc.Description = description;
                sc.IconLocation = target + ",0";
                sc.Save();
                Marshal.FinalReleaseComObject(sc);
            }
            finally { Marshal.FinalReleaseComObject(shell); }
        }

        public static void Install(string folder, bool desktop, bool startup, bool? autoUpdate, Action<int, string> progress)
        {
            progress(10, L.T("Đang tạo thư mục cài đặt..."));
            Directory.CreateDirectory(folder);
            string exe = Path.Combine(folder, "MiniSnap.exe");

            progress(25, L.T("Đang chép MiniSnap.exe..."));
            using (var res = Assembly.GetExecutingAssembly().GetManifestResourceStream("MiniSnap.exe"))
            using (var fs = File.Create(exe))
                res.CopyTo(fs);

            progress(45, L.T("Đang chuẩn bị trình gỡ cài đặt..."));
            string uninstaller = Path.Combine(folder, "Uninstall.exe");
            string self = Application.ExecutablePath;
            if (!string.Equals(Path.GetFullPath(self), Path.GetFullPath(uninstaller), StringComparison.OrdinalIgnoreCase))
                File.Copy(self, uninstaller, true);

            progress(60, L.T("Đang tạo lối tắt..."));
            CreateShortcut(StartMenuShortcut, exe, L.T("Chụp ảnh, quay video màn hình và trích chữ"));
            if (desktop) CreateShortcut(DesktopShortcut, exe, L.T("Chụp ảnh, quay video màn hình và trích chữ"));
            else if (File.Exists(DesktopShortcut)) File.Delete(DesktopShortcut);

            progress(80, L.T("Đang đăng ký với Windows..."));
            using (var k = Registry.CurrentUser.CreateSubKey(SetupProgram.UninstallKey))
            {
                k.SetValue("DisplayName", "MiniSnap");
                k.SetValue("DisplayVersion", SetupProgram.Version);
                k.SetValue("Publisher", "Nguyễn Năng Quốc Bảo");
                k.SetValue("URLInfoAbout", "https://github.com/nnqbao/minisnap");
                k.SetValue("HelpLink", "https://github.com/nnqbao/minisnap/issues");
                k.SetValue("Contact", "nnqbao@gmail.com");
                k.SetValue("DisplayIcon", exe + ",0");
                k.SetValue("InstallLocation", folder);
                k.SetValue("UninstallString", "\"" + uninstaller + "\" --uninstall");
                k.SetValue("QuietUninstallString", "\"" + uninstaller + "\" --uninstall /quiet");
                k.SetValue("InstallDate", DateTime.Now.ToString("yyyyMMdd"));
                k.SetValue("EstimatedSize", (int)(new FileInfo(exe).Length / 1024 + new FileInfo(uninstaller).Length / 1024), RegistryValueKind.DWord);
                k.SetValue("NoModify", 1, RegistryValueKind.DWord);
                k.SetValue("NoRepair", 1, RegistryValueKind.DWord);
            }
            using (var k = Registry.CurrentUser.CreateSubKey(SetupProgram.RunKey))
            {
                if (startup) k.SetValue("MiniSnap", "\"" + exe + "\" --startup");
                else k.DeleteValue("MiniSnap", false);
            }
            if (autoUpdate.HasValue)
                using (var k = Registry.CurrentUser.CreateSubKey(@"Software\MiniSnap"))
                    k.SetValue("AutoUpdateCheck", autoUpdate.Value ? 1 : 0, RegistryValueKind.DWord);
            progress(100, L.T("Hoàn tất."));
        }

        // Started by MiniSnap's "Check for updates": reinstall over the existing copy with the same
        // shortcut/startup choices, no wizard, then relaunch the app.
        public static void SilentUpdate()
        {
            string folder = InstalledFolder() ?? DefaultFolder;
            bool desktop = File.Exists(DesktopShortcut);
            bool startup;
            using (var k = Registry.CurrentUser.OpenSubKey(SetupProgram.RunKey))
                startup = k != null && k.GetValue("MiniSnap") != null;

            // MiniSnap exits right after starting us; give it a moment, then make sure it is gone.
            for (int i = 0; i < 20 && RunningInstances().Length > 0; i++) Thread.Sleep(250);
            foreach (var p in RunningInstances())
            {
                try { p.Kill(); p.WaitForExit(5000); }
                catch (Exception) { }
            }
            try { Install(folder, desktop, startup, null, (pct, msg) => { }); }
            catch (Exception ex)
            {
                MessageBox.Show(L.T("Cập nhật không thành công:\n") + ex.Message, L.T("Cài đặt MiniSnap"), MessageBoxButtons.OK, MessageBoxIcon.Error);
                return;
            }
            try { Process.Start(new ProcessStartInfo(Path.Combine(folder, "MiniSnap.exe"), "--updated") { WorkingDirectory = folder }); }
            catch (Exception) { }
        }

        public static void Uninstall(bool quiet)
        {
            string folder = InstalledFolder();
            if (!quiet && MessageBox.Show(L.T("Gỡ cài đặt MiniSnap khỏi máy tính?\n\nẢnh và video bạn đã chụp vẫn được giữ lại trong Pictures\\MiniSnap và Videos\\MiniSnap."),
                    L.T("Gỡ cài đặt MiniSnap"), MessageBoxButtons.YesNo, MessageBoxIcon.Question) != DialogResult.Yes) return;
            if (quiet) { foreach (var p in RunningInstances()) { try { p.Kill(); p.WaitForExit(5000); } catch (Exception) { } } }
            else if (!CloseRunning(null)) return;

            TryDelete(StartMenuShortcut);
            TryDelete(DesktopShortcut);
            using (var k = Registry.CurrentUser.OpenSubKey(SetupProgram.RunKey, true))
                if (k != null) k.DeleteValue("MiniSnap", false);
            Registry.CurrentUser.DeleteSubKeyTree(SetupProgram.UninstallKey, false);

            if (!string.IsNullOrEmpty(folder) && Directory.Exists(folder))
            {
                TryDelete(Path.Combine(folder, "MiniSnap.exe"));
                // This exe may be the Uninstall.exe inside the folder: let cmd remove it after we exit.
                string cmd = "/c ping 127.0.0.1 -n 3 > nul & del /f /q \"" + Path.Combine(folder, "Uninstall.exe") + "\" & rmdir \"" + folder + "\"";
                Process.Start(new ProcessStartInfo("cmd.exe", cmd) { CreateNoWindow = true, UseShellExecute = false, WindowStyle = ProcessWindowStyle.Hidden });
            }
            if (!quiet) MessageBox.Show(L.T("Đã gỡ cài đặt MiniSnap."), L.T("Gỡ cài đặt MiniSnap"), MessageBoxButtons.OK, MessageBoxIcon.Information);
        }

        static void TryDelete(string path)
        {
            try { if (File.Exists(path)) File.Delete(path); }
            catch (Exception) { }
        }
    }

    class SetupForm : Form
    {
        readonly float ui;
        readonly Panel header, body, footer;
        readonly Panel welcomePage, optionsPage, progressPage, finishPage;
        readonly Button backBtn, nextBtn, cancelBtn;
        readonly TextBox folderBox;
        readonly CheckBox desktopBox, startupBox, updateBox, launchBox;
        readonly ProgressBar progress;
        readonly Label progressLabel, headerTitle, headerSub;
        readonly Image logo;
        int page;
        bool installed;

        int S(float v) { return (int)Math.Round(v * ui); }

        public SetupForm()
        {
            using (var g = CreateGraphics()) ui = g.DpiX / 96f;
            Text = L.T("Cài đặt MiniSnap ") + SetupProgram.Version;
            Icon = MiniSnap.AppIcon.Get();
            Font = Theme.UiFont(9.5f);
            FormBorderStyle = FormBorderStyle.FixedDialog;
            MaximizeBox = false;
            StartPosition = FormStartPosition.CenterScreen;
            ClientSize = new Size(S(600), S(470));
            BackColor = Theme.Window;
            logo = MiniSnap.AppIcon.Render(S(56));

            header = new Panel { Dock = DockStyle.Top, Height = S(92) };
            header.Paint += PaintHeader;
            headerTitle = new Label { AutoSize = true, BackColor = Color.Transparent, ForeColor = Color.White, Font = Theme.UiFont(15f, FontStyle.Bold), Location = new Point(S(96), S(18)) };
            headerSub = new Label { AutoSize = true, BackColor = Color.Transparent, ForeColor = Color.FromArgb(255, 235, 225), Location = new Point(S(98), S(54)) };
            header.Controls.Add(headerTitle);
            header.Controls.Add(headerSub);

            footer = new Panel { Dock = DockStyle.Bottom, Height = S(58), BackColor = Theme.Surface };
            cancelBtn = MakeButton(L.T("Huỷ"));
            nextBtn = MakeButton(L.T("Tiếp tục >"));
            ((FluentButton)nextBtn).Primary = true;
            backBtn = MakeButton(L.T("< Quay lại"));
            cancelBtn.Location = new Point(ClientSize.Width - S(16) - cancelBtn.Width, S(14));
            nextBtn.Location = new Point(cancelBtn.Left - S(10) - nextBtn.Width, S(14));
            backBtn.Location = new Point(nextBtn.Left - S(6) - backBtn.Width, S(14));
            cancelBtn.Click += (s, e) => Close();
            nextBtn.Click += (s, e) => Next();
            backBtn.Click += (s, e) => ShowPage(page - 1);
            footer.Controls.AddRange(new Control[] { backBtn, nextBtn, cancelBtn });
            AcceptButton = nextBtn;

            body = new Panel { Dock = DockStyle.Fill, Padding = new Padding(S(28), S(20), S(28), S(10)) };

            // Welcome
            welcomePage = NewPage();
            AddText(welcomePage, L.T("MiniSnap giúp bạn chụp và chia sẻ màn hình thật nhanh:"), 0, true);
            string[] features =
            {
                L.T("Chụp vùng, cửa sổ, toàn màn hình — phím PrtScn"),
                L.T("Chụp cuộn trang web dài — Ctrl+Alt+S"),
                L.T("Quay video màn hình ra MP4 — Ctrl+Alt+R"),
                L.T("Trích chữ trong ảnh (OCR) — Ctrl+Alt+O"),
                L.T("Chú thích: mũi tên, khung, chữ, làm mờ, đánh số"),
                L.T("Thư viện ảnh & video có ảnh thu nhỏ — Ctrl+Alt+L"),
                L.T("Tự đặt phím tắt theo ý muốn (menu khay → Cài đặt phím tắt)"),
            };
            for (int i = 0; i < features.Length; i++) AddText(welcomePage, L.T("✓  ") + features[i], S(36) + i * S(28), false);
            string prev = Installer.InstalledVersion();
            if (prev != null)
                AddText(welcomePage, L.T("Máy đã có MiniSnap ") + prev + L.T(" — bản này sẽ cập nhật đè lên, giữ nguyên ảnh đã chụp và phím tắt."), S(240), false).ForeColor = Theme.Accent;

            // Options
            optionsPage = NewPage();
            AddText(optionsPage, L.T("Thư mục cài đặt:"), 0, true);
            folderBox = new TextBox { Location = new Point(0, S(30)), Width = S(430), Text = Installer.InstalledFolder() ?? Installer.DefaultFolder };
            var browse = MakeButton(L.T("Chọn..."));
            browse.Location = new Point(folderBox.Right + S(8), S(28));
            browse.Click += (s, e) => Browse();
            optionsPage.Controls.Add(folderBox);
            optionsPage.Controls.Add(browse);
            AddText(optionsPage, L.T("Cài cho riêng tài khoản của bạn, không cần quyền quản trị."), S(60), false).ForeColor = Theme.TextSecondary;
            desktopBox = new CheckBox { Text = L.T("Tạo lối tắt ngoài màn hình Desktop"), Checked = true, AutoSize = true, Location = new Point(0, S(106)) };
            startupBox = new CheckBox { Text = L.T("Tự chạy MiniSnap khi khởi động Windows (để luôn bấm được PrtScn)"), Checked = true, AutoSize = true, Location = new Point(0, S(136)) };
            optionsPage.Controls.Add(desktopBox);
            optionsPage.Controls.Add(startupBox);
            updateBox = new CheckBox { Text = L.T("Tự kiểm tra bản mới mỗi ngày (chỉ gửi một yêu cầu tới api.github.com — xem PRIVACY.md)"), Checked = Installer.AutoUpdateDefault(), AutoSize = false, Size = new Size(S(545), S(42)), CheckAlign = ContentAlignment.TopLeft, TextAlign = ContentAlignment.TopLeft, Location = new Point(0, S(166)) };
            optionsPage.Controls.Add(updateBox);
            AddText(optionsPage, L.T("Lối tắt trong Start menu luôn được tạo. Gỡ cài đặt trong Settings → Apps."), S(222), false).ForeColor = Theme.TextSecondary;

            // Progress
            progressPage = NewPage();
            progressLabel = AddText(progressPage, L.T("Đang cài đặt..."), S(40), false);
            progress = new ProgressBar { Location = new Point(0, S(70)), Width = S(540), Height = S(22) };
            progressPage.Controls.Add(progress);

            // Finish
            finishPage = NewPage();
            AddText(finishPage, L.T("MiniSnap đã được cài đặt thành công!"), 0, true);
            AddText(finishPage, L.T("MiniSnap chạy ở khay hệ thống (góc phải thanh taskbar).\nNhấn PrtScn bất cứ lúc nào để chụp màn hình."), S(36), false);
            AddText(finishPage, L.T("Mẹo: trên Windows 11, nếu PrtScn mở Snipping Tool, hãy vào Settings → Accessibility → Keyboard và tắt \"Use the Print screen key to open screen capture\"."), S(96), false).ForeColor = Theme.TextSecondary;
            launchBox = new CheckBox { Text = L.T("Mở MiniSnap ngay"), Checked = true, AutoSize = true, Location = new Point(0, S(160)) };
            finishPage.Controls.Add(launchBox);

            body.Controls.AddRange(new Control[] { welcomePage, optionsPage, progressPage, finishPage });
            Controls.Add(body);
            Controls.Add(footer);
            Controls.Add(header);
            Theme.Apply(this);
            ShowPage(0);
        }

        Button MakeButton(string text)
        {
            return new FluentButton { Text = text, MinimumSize = new Size(S(96), S(32)) };
        }

        Panel NewPage()
        {
            return new Panel { Dock = DockStyle.Fill, Visible = false, BackColor = Theme.Window };
        }

        Label AddText(Panel page, string text, int y, bool bold)
        {
            var l = new Label
            {
                Text = text,
                UseMnemonic = false,
                AutoSize = true,
                Location = new Point(0, y),
                MaximumSize = new Size(S(545), 0),
                Font = bold ? Theme.UiFont(10.5f, FontStyle.Bold) : Font,
            };
            page.Controls.Add(l);
            return l;
        }

        void PaintHeader(object sender, PaintEventArgs e)
        {
            var g = e.Graphics;
            using (var br = new LinearGradientBrush(header.ClientRectangle, Color.FromArgb(255, 110, 50), Color.FromArgb(215, 40, 90), LinearGradientMode.Horizontal))
                g.FillRectangle(br, header.ClientRectangle);
            g.DrawImage(logo, S(24), (header.Height - logo.Height) / 2);
        }

        void ShowPage(int p)
        {
            page = Math.Max(0, Math.Min(3, p));
            welcomePage.Visible = page == 0;
            optionsPage.Visible = page == 1;
            progressPage.Visible = page == 2;
            finishPage.Visible = page == 3;
            string[] titles = { L.T("Chào mừng đến với MiniSnap"), L.T("Tuỳ chọn cài đặt"), L.T("Đang cài đặt"), L.T("Đã cài xong") };
            string[] subs = { L.T("Phiên bản ") + SetupProgram.Version + L.T(" • Chụp ảnh, quay video màn hình, trích chữ"), L.T("Chọn nơi cài và các tuỳ chọn"), L.T("Vui lòng đợi trong giây lát..."), L.T("Sẵn sàng sử dụng") };
            headerTitle.Text = titles[page];
            headerSub.Text = subs[page];
            backBtn.Visible = page == 1;
            cancelBtn.Visible = page < 2;
            nextBtn.Enabled = page != 2;
            nextBtn.Text = page == 1 ? L.T("Cài đặt") : page == 3 ? L.T("Hoàn tất") : L.T("Tiếp tục >");
            if (nextBtn.Enabled) nextBtn.Focus();
            header.Invalidate();
        }

        void Browse()
        {
            using (var dlg = new FolderBrowserDialog { Description = L.T("Chọn thư mục cài MiniSnap"), SelectedPath = folderBox.Text })
                if (dlg.ShowDialog(this) == DialogResult.OK)
                    folderBox.Text = Path.GetFileName(dlg.SelectedPath).Equals(SetupProgram.AppName, StringComparison.OrdinalIgnoreCase)
                        ? dlg.SelectedPath : Path.Combine(dlg.SelectedPath, SetupProgram.AppName);
        }

        void Next()
        {
            if (page == 0) { ShowPage(1); return; }
            if (page == 1) { RunInstall(); return; }
            if (page == 3)
            {
                if (launchBox.Checked)
                {
                    string exe = Path.Combine(folderBox.Text, "MiniSnap.exe");
                    try { Process.Start(new ProcessStartInfo(exe) { WorkingDirectory = folderBox.Text }); }
                    catch (Exception) { }
                }
                Close();
            }
        }

        void RunInstall()
        {
            string folder;
            try { folder = Path.GetFullPath(folderBox.Text.Trim()); }
            catch (Exception)
            {
                MessageBox.Show(this, L.T("Đường dẫn thư mục không hợp lệ."), Text, MessageBoxButtons.OK, MessageBoxIcon.Warning);
                return;
            }
            folderBox.Text = folder;
            if (!Installer.CloseRunning(this)) return;
            ShowPage(2);
            Refresh();
            try
            {
                Installer.Install(folder, desktopBox.Checked, startupBox.Checked, updateBox.Checked, (pct, msg) =>
                {
                    progress.Value = pct;
                    progressLabel.Text = msg;
                    progressPage.Refresh();
                    Thread.Sleep(120);
                });
                installed = true;
                ShowPage(3);
            }
            catch (Exception ex)
            {
                MessageBox.Show(this, L.T("Cài đặt không thành công:\n") + ex.Message, Text, MessageBoxButtons.OK, MessageBoxIcon.Error);
                ShowPage(1);
            }
        }

        protected override void OnFormClosing(FormClosingEventArgs e)
        {
            if (page == 2) { e.Cancel = true; return; }
            if (!installed && page < 2 && e.CloseReason == CloseReason.UserClosing && page > 0
                && MessageBox.Show(this, L.T("Thoát trình cài đặt?"), Text, MessageBoxButtons.YesNo, MessageBoxIcon.Question) != DialogResult.Yes)
                e.Cancel = true;
            base.OnFormClosing(e);
        }
    }
}
