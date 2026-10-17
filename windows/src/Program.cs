using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Drawing;
using System.Drawing.Drawing2D;
using System.Drawing.Imaging;
using System.IO;
using System.Linq;
using System.Runtime.InteropServices;
using System.Threading;
using System.Windows.Forms;
using Microsoft.Win32;

namespace MiniSnap
{
    static class Program
    {
        [STAThread]
        static void Main(string[] args)
        {
            if (args.Length >= 2 && args[0] == "--export-icon")
            {
                AppIcon.SaveIco(args[1]);
                return;
            }

            L.Load();
            NativeMethods.EnableDpiAwareness();
            Application.EnableVisualStyles();
            Application.SetCompatibleTextRenderingDefault(false);

            if (args.Length >= 2 && args[0] == "--selftest")
            {
                SelfTest.Run(args[1]);
                return;
            }

            bool createdNew;
            using (var mutex = new Mutex(true, "MiniSnap.SingleInstance.7c1e", out createdNew))
            {
                if (!createdNew)
                {
                    // Second launch (e.g. from the Start menu): ask the running copy to show its library,
                    // or the shortcut settings with --hotkeys.
                    NativeMethods.PostToRunningInstance(args.Contains("--hotkeys") ? NativeMethods.WM_SHOWHOTKEYS : NativeMethods.WM_SHOWLIBRARY);
                    return;
                }
                Application.ThreadException += (s, e) =>
                    MessageBox.Show(e.Exception.ToString(), L.T("MiniSnap - lỗi"), MessageBoxButtons.OK, MessageBoxIcon.Error);
                var app = new TrayApp(args.Contains("--startup") || args.Contains("--hotkeys") || args.Contains("--updated"));
                if (args.Contains("--updated")) app.ShowUpdatedBalloon();
                if (args.Contains("--hotkeys")) app.OpenHotkeySettingsOnStart();
                Application.Run(app);
            }
        }
    }

    static class NativeMethods
    {
        public const int WM_HOTKEY = 0x0312;
        public const uint MOD_ALT = 1, MOD_CONTROL = 2, MOD_SHIFT = 4, MOD_NOREPEAT = 0x4000;
        public static readonly int WM_SHOWLIBRARY = RegisterWindowMessage("MiniSnap.ShowLibrary");
        public static readonly int WM_SHOWHOTKEYS = RegisterWindowMessage("MiniSnap.ShowHotkeys");

        [StructLayout(LayoutKind.Sequential)]
        public struct RECT
        {
            public int Left, Top, Right, Bottom;
            public Rectangle ToRectangle() { return Rectangle.FromLTRB(Left, Top, Right, Bottom); }
        }

        public delegate bool EnumWindowsProc(IntPtr hWnd, IntPtr lParam);

        [DllImport("user32.dll")] public static extern bool RegisterHotKey(IntPtr hWnd, int id, uint fsModifiers, uint vk);
        [DllImport("user32.dll")] public static extern bool UnregisterHotKey(IntPtr hWnd, int id);
        [DllImport("user32.dll")] public static extern bool EnumWindows(EnumWindowsProc cb, IntPtr lParam);
        [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr hWnd);
        [DllImport("user32.dll")] public static extern bool IsIconic(IntPtr hWnd);
        [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr hWnd, out RECT r);
        [DllImport("user32.dll")] public static extern int GetWindowLong(IntPtr hWnd, int index);
        [DllImport("dwmapi.dll")] public static extern int DwmGetWindowAttribute(IntPtr hWnd, int attr, out RECT value, int size);
        [DllImport("dwmapi.dll")] public static extern int DwmGetWindowAttribute(IntPtr hWnd, int attr, out int value, int size);
        [DllImport("user32.dll")] static extern bool SetProcessDpiAwarenessContext(IntPtr value);
        [DllImport("user32.dll")] static extern bool SetProcessDPIAware();
        [DllImport("user32.dll")] static extern bool SetWindowDisplayAffinity(IntPtr hWnd, int affinity);
        [DllImport("user32.dll")] static extern void mouse_event(int flags, int dx, int dy, int data, IntPtr extra);
        [DllImport("user32.dll")] static extern short GetAsyncKeyState(int vk);
        [DllImport("user32.dll", CharSet = CharSet.Unicode)] static extern int RegisterWindowMessage(string name);
        [DllImport("user32.dll")] static extern bool PostMessage(IntPtr hWnd, int msg, IntPtr wParam, IntPtr lParam);

        // The manifest already asks for per-monitor DPI awareness; this is a fallback
        // so captured pixels always match physical screen pixels.
        public static void EnableDpiAwareness()
        {
            try { if (SetProcessDpiAwarenessContext(new IntPtr(-4))) return; }
            catch (EntryPointNotFoundException) { }
            try { SetProcessDPIAware(); }
            catch (EntryPointNotFoundException) { }
        }

        // Hides our own toolbars from screenshots and recordings (Windows 10 2004+).
        public static void ExcludeFromCapture(IntPtr hwnd)
        {
            try { SetWindowDisplayAffinity(hwnd, 0x11); }
            catch (EntryPointNotFoundException) { }
        }

        public static void MouseWheel(int delta) { mouse_event(0x0800, 0, 0, delta, IntPtr.Zero); }

        public static bool IsKeyDown(Keys key) { return (GetAsyncKeyState((int)key) & 0x8000) != 0; }

        public static void PostToRunningInstance(int message) { PostMessage(new IntPtr(0xFFFF), message, IntPtr.Zero, IntPtr.Zero); }
    }

    class HotkeyWindow : NativeWindow, IDisposable
    {
        readonly List<int> ids = new List<int>();
        public event Action<int> Pressed;
        public event Action ShowLibraryRequested;
        public event Action ShowHotkeysRequested;

        public HotkeyWindow()
        {
            // A real top-level (hidden) window so it also receives the broadcast from a second launch.
            CreateHandle(new CreateParams { Caption = "MiniSnap.HotkeyWindow" });
        }

        public bool Register(int id, uint modifiers, Keys key)
        {
            bool ok = NativeMethods.RegisterHotKey(Handle, id, modifiers | NativeMethods.MOD_NOREPEAT, (uint)key);
            if (ok) ids.Add(id);
            return ok;
        }

        public void UnregisterAll()
        {
            foreach (int id in ids) NativeMethods.UnregisterHotKey(Handle, id);
            ids.Clear();
        }

        protected override void WndProc(ref Message m)
        {
            if (m.Msg == NativeMethods.WM_HOTKEY)
            {
                var handler = Pressed;
                if (handler != null) handler(m.WParam.ToInt32());
            }
            else if (m.Msg == NativeMethods.WM_SHOWLIBRARY)
            {
                var handler = ShowLibraryRequested;
                if (handler != null) handler();
            }
            else if (m.Msg == NativeMethods.WM_SHOWHOTKEYS)
            {
                var handler = ShowHotkeysRequested;
                if (handler != null) handler();
            }
            base.WndProc(ref m);
        }

        public void Dispose()
        {
            UnregisterAll();
            DestroyHandle();
        }
    }

    static class WindowFinder
    {
        const int GWL_EXSTYLE = -20, WS_EX_TRANSPARENT = 0x20;
        const int DWMWA_EXTENDED_FRAME_BOUNDS = 9, DWMWA_CLOAKED = 14;

        // Visible top-level windows in z-order (topmost first), in screen coordinates.
        public static List<Rectangle> GetWindowRects()
        {
            var list = new List<Rectangle>();
            NativeMethods.EnumWindows((h, l) =>
            {
                if (!NativeMethods.IsWindowVisible(h) || NativeMethods.IsIconic(h)) return true;
                int cloaked;
                if (NativeMethods.DwmGetWindowAttribute(h, DWMWA_CLOAKED, out cloaked, 4) == 0 && cloaked != 0) return true;
                if ((NativeMethods.GetWindowLong(h, GWL_EXSTYLE) & WS_EX_TRANSPARENT) != 0) return true;
                NativeMethods.RECT r;
                if (NativeMethods.DwmGetWindowAttribute(h, DWMWA_EXTENDED_FRAME_BOUNDS, out r, Marshal.SizeOf(typeof(NativeMethods.RECT))) != 0
                    && !NativeMethods.GetWindowRect(h, out r)) return true;
                var rect = r.ToRectangle();
                if (rect.Width >= 8 && rect.Height >= 8) list.Add(rect);
                return true;
            }, IntPtr.Zero);
            return list;
        }
    }

    static class ScreenCapture
    {
        public static Bitmap Capture(Rectangle screenRect)
        {
            var bmp = new Bitmap(screenRect.Width, screenRect.Height, PixelFormat.Format32bppRgb);
            using (var g = Graphics.FromImage(bmp))
                g.CopyFromScreen(screenRect.Location, Point.Empty, screenRect.Size, CopyPixelOperation.SourceCopy);
            return bmp;
        }

        public static Bitmap Crop(Bitmap src, Rectangle r)
        {
            r.Intersect(new Rectangle(0, 0, src.Width, src.Height));
            var bmp = new Bitmap(r.Width, r.Height, PixelFormat.Format32bppPArgb);
            using (var g = Graphics.FromImage(bmp))
            {
                g.CompositingMode = CompositingMode.SourceCopy;
                g.InterpolationMode = InterpolationMode.NearestNeighbor;
                g.PixelOffsetMode = PixelOffsetMode.Half;
                g.DrawImage(src, new Rectangle(0, 0, r.Width, r.Height), r, GraphicsUnit.Pixel);
            }
            return bmp;
        }
    }

    static class Prefs
    {
        const string RegPath = @"Software\MiniSnap";

        // Show the screenshot / video / scrolling-capture bar after a region is selected (default on).
        public static bool AskAfterSelect
        {
            get
            {
                try
                {
                    using (var k = Registry.CurrentUser.OpenSubKey(RegPath))
                        return k == null || !(k.GetValue("AskAfterSelect") is int) || (int)k.GetValue("AskAfterSelect") != 0;
                }
                catch (Exception) { return true; }
            }
            set
            {
                using (var k = Registry.CurrentUser.CreateSubKey(RegPath))
                    k.SetValue("AskAfterSelect", value ? 1 : 0, RegistryValueKind.DWord);
            }
        }
    }

    static class AutoUpdatePref
    {
        const string RegPath = @"Software\MiniSnap";

        // Daily background check against api.github.com (default on; documented in PRIVACY.md).
        public static bool Enabled
        {
            get
            {
                try
                {
                    using (var k = Registry.CurrentUser.OpenSubKey(RegPath))
                        return k == null || !(k.GetValue("AutoUpdateCheck") is int) || (int)k.GetValue("AutoUpdateCheck") != 0;
                }
                catch (Exception) { return true; }
            }
            set
            {
                using (var k = Registry.CurrentUser.CreateSubKey(RegPath))
                    k.SetValue("AutoUpdateCheck", value ? 1 : 0, RegistryValueKind.DWord);
            }
        }
    }

    static class Startup
    {
        const string RunKey = @"Software\Microsoft\Windows\CurrentVersion\Run";

        public static bool Enabled
        {
            get
            {
                using (var k = Registry.CurrentUser.OpenSubKey(RunKey))
                    return k != null && k.GetValue("MiniSnap") != null;
            }
            set
            {
                using (var k = Registry.CurrentUser.CreateSubKey(RunKey))
                {
                    if (value) k.SetValue("MiniSnap", "\"" + Application.ExecutablePath + "\" --startup");
                    else k.DeleteValue("MiniSnap", false);
                }
            }
        }
    }

    class TrayApp : ApplicationContext
    {
        enum Mode { Image, FullScreen, Scroll, Video, Ocr }

        readonly NotifyIcon tray;
        readonly HotkeyWindow hotkeys;
        readonly List<Form> windows = new List<Form>();
        ToolStripMenuItem recordItem, startupItem, askItem, autoUpdateItem;
        readonly Dictionary<HotkeyAction, ToolStripMenuItem> actionItems = new Dictionary<HotkeyAction, ToolStripMenuItem>();
        Dictionary<HotkeyAction, Hotkey> keys = HotkeySettings.Load();
        LibraryForm library;
        RecorderBar recorder;
        HotkeySettingsForm hotkeyForm;
        bool busy;
        Action balloonClick;

        public TrayApp(bool quietStart)
        {
            tray = new NotifyIcon
            {
                Icon = AppIcon.Small(SystemInformation.SmallIconSize.Width),
                ContextMenuStrip = BuildMenu(),
                Visible = true,
            };
            tray.MouseClick += (s, e) => { if (e.Button == MouseButtons.Left) BeginCapture(Mode.Image, 0); };
            tray.BalloonTipClicked += (s, e) => { var a = balloonClick; balloonClick = null; if (a != null) a(); };

            hotkeys = new HotkeyWindow();
            hotkeys.Pressed += id => Run((HotkeyAction)(id - 1));
            hotkeys.ShowLibraryRequested += () => ShowLibrary(null);
            hotkeys.ShowHotkeysRequested += ShowHotkeySettings;
            var failed = RegisterAll();
            UpdateTrayText();
            ScheduleAutoUpdateCheck();

            if (!quietStart || failed.Count > 0)
            {
                string msg = KeyHint() + L.T(". Chuột phải vào biểu tượng này để xem thêm hoặc đổi phím tắt.");
                if (failed.Count > 0)
                    msg += L.T("\nKhông đăng ký được: ") + string.Join(", ", failed.Select(a => keys[a].ShortText)) + L.T(" (đang bị ứng dụng khác dùng) — vào Cài đặt phím tắt để đổi.");
                ShowBalloon(L.T("MiniSnap đã sẵn sàng"), msg, failed.Count > 0 ? new Action(ShowHotkeySettings) : null);
            }
        }

        // Rebuilt whenever the language changes, so every caption is re-read through L.T.
        ContextMenuStrip BuildMenu()
        {
            actionItems.Clear();
            var menu = new ContextMenuStrip();
            AddAction(menu, HotkeyAction.CaptureRegion, L.T("Chụp vùng / cửa sổ"), IconKind.Capture);
            AddAction(menu, HotkeyAction.CaptureFullScreen, L.T("Chụp toàn màn hình"), null);
            AddAction(menu, HotkeyAction.CaptureDelayed, L.T("Chụp vùng sau 3 giây"), null);
            AddAction(menu, HotkeyAction.ScrollCapture, L.T("Chụp cuộn trang dài"), IconKind.Scroll);
            recordItem = AddAction(menu, HotkeyAction.RecordVideo, L.T("Quay video màn hình"), IconKind.Video);
            AddAction(menu, HotkeyAction.Ocr, L.T("Chụp và trích chữ (OCR)"), IconKind.Ocr);
            menu.Items.Add(new ToolStripSeparator());
            AddAction(menu, HotkeyAction.Library, L.T("Thư viện ảnh && video"), IconKind.Library);
            AddItem(menu, L.T("Mở ảnh..."), null, IconKind.Open, (s, e) => OpenImageDialog());
            menu.Items.Add(new ToolStripSeparator());

            // Always bilingual so it can be found whichever language is active.
            var langItem = new ToolStripMenuItem("Ngôn ngữ / Language", Icons.Draw(IconKind.Globe, 16));
            var viItem = new ToolStripMenuItem("Tiếng Việt", null, (s, e) => SetLanguage(false)) { Checked = !L.English };
            var enItem = new ToolStripMenuItem("English", null, (s, e) => SetLanguage(true)) { Checked = L.English };
            langItem.DropDownItems.Add(viItem);
            langItem.DropDownItems.Add(enItem);
            menu.Items.Add(langItem);

            AddItem(menu, L.T("Cài đặt phím tắt..."), null, IconKind.Keyboard, (s, e) => ShowHotkeySettings());
            askItem = AddItem(menu, L.T("Hỏi chụp ảnh / quay video / chụp cuộn sau khi chọn vùng"), null, null, (s, e) =>
            {
                try { Prefs.AskAfterSelect = !Prefs.AskAfterSelect; }
                catch (Exception ex) { MessageBox.Show(ex.Message, "MiniSnap"); }
            });
            startupItem = AddItem(menu, L.T("Khởi động cùng Windows"), null, null, (s, e) => ToggleStartup());
            AddItem(menu, L.T("Kiểm tra cập nhật..."), null, IconKind.Update, (s, e) => ShowUpdate(null));
            autoUpdateItem = AddItem(menu, L.T("Tự kiểm tra cập nhật hằng ngày"), null, null, (s, e) =>
            {
                try { AutoUpdatePref.Enabled = !AutoUpdatePref.Enabled; }
                catch (Exception ex) { MessageBox.Show(ex.Message, "MiniSnap"); }
            });
            AddItem(menu, L.T("Giới thiệu MiniSnap..."), null, IconKind.Info, (s, e) => ShowAbout());
            AddItem(menu, L.T("Thoát MiniSnap"), null, null, (s, e) => ExitThread());
            Theme.StyleStrip(menu);
            menu.Font = Theme.UiFont(9f);
            menu.Opening += (s, e) =>
            {
                startupItem.Checked = Startup.Enabled;
                askItem.Checked = Prefs.AskAfterSelect;
                autoUpdateItem.Checked = AutoUpdatePref.Enabled;
                recordItem.Text = recorder != null ? L.T("Dừng quay video") : L.T("Quay video màn hình");
                foreach (var kv in actionItems) kv.Value.ShortcutKeyDisplayString = keys[kv.Key].ShortText;
            };
            return menu;
        }

        void SetLanguage(bool english)
        {
            if (english == L.English) return;
            try { L.Set(english); }
            catch (Exception ex) { MessageBox.Show(ex.Message, "MiniSnap"); return; }
            // Swap the menu after the click that triggered this has finished.
            var t = new System.Windows.Forms.Timer { Interval = 50 };
            t.Tick += (s, e) =>
            {
                t.Stop();
                t.Dispose();
                var old = tray.ContextMenuStrip;
                tray.ContextMenuStrip = BuildMenu();
                if (old != null) old.Dispose();
                UpdateTrayText();
                ShowBalloon("MiniSnap",
                    english ? "Language changed to English. Open windows switch when you reopen them."
                            : "Đã chuyển sang Tiếng Việt. Các cửa sổ đang mở sẽ đổi khi bạn mở lại.", null);
            };
            t.Start();
        }

        ToolStripMenuItem AddAction(ContextMenuStrip menu, HotkeyAction action, string text, IconKind? icon)
        {
            var item = AddItem(menu, text, null, icon, (s, e) => Run(action));
            actionItems[action] = item;
            return item;
        }

        // Registers every configured shortcut; returns the ones another app already owns.
        List<HotkeyAction> RegisterAll()
        {
            hotkeys.UnregisterAll();
            var failed = new List<HotkeyAction>();
            foreach (var kv in keys)
            {
                if (kv.Value.IsNone) continue;
                if (!hotkeys.Register((int)kv.Key + 1, kv.Value.Mods, kv.Value.Key)) failed.Add(kv.Key);
            }
            return failed;
        }

        string KeyHint()
        {
            var parts = new List<string>();
            foreach (var a in new[] { HotkeyAction.CaptureRegion, HotkeyAction.RecordVideo, HotkeyAction.ScrollCapture, HotkeyAction.Ocr })
                if (!keys[a].IsNone) parts.Add(keys[a].ShortText + ": " + (a == HotkeyAction.CaptureRegion ? L.T("chụp ảnh") : a == HotkeyAction.RecordVideo ? "quay video" : a == HotkeyAction.ScrollCapture ? L.T("chụp cuộn") : L.T("trích chữ")));
            return parts.Count > 0 ? string.Join(L.T(" • "), parts) : L.T("Chưa gán phím tắt nào");
        }

        void UpdateTrayText()
        {
            var k = keys[HotkeyAction.CaptureRegion];
            string text = k.IsNone ? "MiniSnap" : L.T("MiniSnap — nhấn ") + k.ShortText + L.T(" để chụp");
            tray.Text = text.Length > 63 ? text.Substring(0, 63) : text;
        }

        public void ShowUpdatedBalloon()
        {
            ShowBalloon(L.T("Đã cập nhật MiniSnap"), L.T("Bạn đang dùng phiên bản ") + AppInfo.Version, null);
        }

        public void OpenHotkeySettingsOnStart()
        {
            var t = new System.Windows.Forms.Timer { Interval = 300 };
            t.Tick += (s, e) => { t.Stop(); t.Dispose(); ShowHotkeySettings(); };
            t.Start();
        }

        AboutForm about;
        UpdateForm updateForm;
        Control invoker;

        void ShowUpdate(Updater.Release known)
        {
            if (updateForm != null && !updateForm.IsDisposed) { updateForm.Activate(); return; }
            Theme.Load();
            updateForm = new UpdateForm(InstallUpdate, known);
            Track(updateForm);
            updateForm.Show();
            updateForm.Activate();
        }

        // Close every window (unsaved editors still ask), then hand over to the installer, which restarts MiniSnap.
        void InstallUpdate(string setupPath)
        {
            if (recorder != null) recorder.StopRecording();
            foreach (var f in windows.ToArray())
            {
                if (f == updateForm) continue;
                f.Close();
                if (!f.IsDisposed && f.Visible) return;
            }
            try { Process.Start(new ProcessStartInfo(setupPath, "--update") { UseShellExecute = true }); }
            catch (Exception ex)
            {
                MessageBox.Show(L.T("Không chạy được bộ cài:\n") + ex.Message, "MiniSnap", MessageBoxButtons.OK, MessageBoxIcon.Warning);
                return;
            }
            if (updateForm != null && !updateForm.IsDisposed) updateForm.Close();
            ExitThread();
        }

        // Quiet daily check a few seconds after start; only a balloon if something newer exists.
        void ScheduleAutoUpdateCheck()
        {
            if (!AutoUpdatePref.Enabled || !Updater.DueForAutoCheck()) return;
            invoker = new Control();
            invoker.CreateControl();
            var t = new System.Windows.Forms.Timer { Interval = 15000 };
            t.Tick += (s, e) =>
            {
                t.Stop();
                t.Dispose();
                var th = new Thread(() =>
                {
                    Updater.Release r;
                    try { r = Updater.Fetch(); Updater.MarkChecked(); }
                    catch (Exception) { return; }
                    if (!Updater.IsNewer(r)) return;
                    try
                    {
                        invoker.BeginInvoke(new Action(() =>
                            ShowBalloon(L.T("Có bản MiniSnap mới: ") + r.Version, L.T("Bấm vào đây để xem và cập nhật."), () => ShowUpdate(r))));
                    }
                    catch (InvalidOperationException) { }
                });
                th.IsBackground = true;
                th.Start();
            };
            t.Start();
        }

        void ShowAbout()
        {
            if (about != null && !about.IsDisposed) { about.Activate(); return; }
            Theme.Load();
            about = new AboutForm(() => ShowUpdate(null));
            Track(about);
            about.Show();
            about.Activate();
        }

        void ShowHotkeySettings()
        {
            if (hotkeyForm != null && !hotkeyForm.IsDisposed) { hotkeyForm.Activate(); return; }
            // Global shortcuts would swallow the keys the user is trying to record, so pause them meanwhile.
            hotkeys.UnregisterAll();
            Theme.Load();
            hotkeyForm = new HotkeySettingsForm(keys, map =>
            {
                keys = map;
                try { HotkeySettings.Save(map); }
                catch (Exception ex) { MessageBox.Show(L.T("Không lưu được cài đặt:\n") + ex.Message, "MiniSnap"); }
                var failed = RegisterAll();
                hotkeys.UnregisterAll();
                UpdateTrayText();
                return failed;
            });
            hotkeyForm.FormClosed += (s, e) => { hotkeyForm = null; RegisterAll(); };
            Track(hotkeyForm);
            hotkeyForm.Show();
            hotkeyForm.Activate();
        }

        static ToolStripMenuItem AddItem(ContextMenuStrip menu, string text, string shortcut, IconKind? icon, EventHandler onClick)
        {
            var item = new ToolStripMenuItem(text, icon.HasValue ? Icons.Draw(icon.Value, 16) : null, onClick);
            if (shortcut != null) item.ShortcutKeyDisplayString = shortcut;
            menu.Items.Add(item);
            return item;
        }

        void ShowBalloon(string title, string text, Action onClick)
        {
            balloonClick = onClick;
            tray.ShowBalloonTip(4000, title, text, ToolTipIcon.Info);
        }

        void Run(HotkeyAction action)
        {
            switch (action)
            {
                case HotkeyAction.CaptureRegion:
                case HotkeyAction.CaptureRegionAlt: BeginCapture(Mode.Image, 0); break;
                case HotkeyAction.CaptureFullScreen: BeginCapture(Mode.FullScreen, 0); break;
                case HotkeyAction.CaptureDelayed: BeginCapture(Mode.Image, 3); break;
                case HotkeyAction.ScrollCapture: BeginCapture(Mode.Scroll, 0); break;
                case HotkeyAction.RecordVideo: ToggleRecording(); break;
                case HotkeyAction.Ocr: BeginCapture(Mode.Ocr, 0); break;
                case HotkeyAction.Library: ShowLibrary(null); break;
            }
        }

        void ToggleStartup()
        {
            try { Startup.Enabled = !Startup.Enabled; }
            catch (Exception ex) { MessageBox.Show(L.T("Không đổi được cài đặt khởi động:\n") + ex.Message, "MiniSnap"); }
        }

        void ToggleRecording()
        {
            if (recorder != null) recorder.StopRecording();
            else BeginCapture(Mode.Video, 0);
        }

        void BeginCapture(Mode mode, int delaySeconds)
        {
            if (busy || (recorder != null && mode != Mode.Video)) return;
            busy = true;
            if (delaySeconds > 0)
                tray.ShowBalloonTip(1500, "MiniSnap", L.T("Sẽ chụp sau ") + delaySeconds + L.T(" giây..."), ToolTipIcon.None);
            // A short delay also lets the tray menu finish closing before the screen is grabbed.
            var timer = new System.Windows.Forms.Timer { Interval = Math.Max(200, delaySeconds * 1000) };
            timer.Tick += (s, e) =>
            {
                timer.Stop();
                timer.Dispose();
                try { DoCapture(mode); }
                finally { busy = false; }
            };
            timer.Start();
        }

        static string PromptFor(Mode mode)
        {
            switch (mode)
            {
                case Mode.Scroll: return L.T("Chụp cuộn: chọn cửa sổ hoặc vùng có nội dung cần cuộn — app sẽ tự cuộn xuống");
                case Mode.Video: return L.T("Quay video: chọn cửa sổ hoặc kéo chọn vùng cần quay (Enter = toàn màn hình)");
                case Mode.Ocr: return L.T("Trích chữ: chọn vùng có chữ cần lấy");
                default: return null;
            }
        }

        void DoCapture(Mode mode)
        {
            Rectangle vs = SystemInformation.VirtualScreen;
            List<Rectangle> windowRects = mode == Mode.FullScreen ? null : WindowFinder.GetWindowRects();
            Bitmap shot = ScreenCapture.Capture(vs);
            Rectangle sel;
            try
            {
                sel = new Rectangle(0, 0, shot.Width, shot.Height);
                if (mode != Mode.FullScreen)
                {
                    // Plain region capture can ask what to do with the area: screenshot, video or scrolling capture.
                    using (var overlay = new CaptureOverlay(shot, vs, windowRects) { Prompt = PromptFor(mode), AskMode = mode == Mode.Image && Prefs.AskAfterSelect })
                    {
                        sel = overlay.ShowDialog() == DialogResult.OK ? overlay.Selection : Rectangle.Empty;
                        if (overlay.Choice == CaptureChoice.Video) mode = Mode.Video;
                        else if (overlay.Choice == CaptureChoice.Scroll) mode = Mode.Scroll;
                    }
                }
                if (sel.IsEmpty) return;

                if (mode == Mode.Image || mode == Mode.FullScreen)
                {
                    using (var result = ScreenCapture.Crop(shot, sel)) SaveAndEdit(result);
                    return;
                }
                if (mode == Mode.Ocr)
                {
                    using (var result = ScreenCapture.Crop(shot, sel)) ShowOcr(result);
                    return;
                }
            }
            finally { shot.Dispose(); }

            var screenRect = new Rectangle(sel.X + vs.X, sel.Y + vs.Y, sel.Width, sel.Height);
            if (mode == Mode.Scroll)
            {
                var session = new ScrollCaptureSession(screenRect, bmp =>
                {
                    using (bmp) SaveAndEdit(bmp);
                });
                Track(session);
                session.Show();
            }
            else if (mode == Mode.Video)
            {
                if (screenRect.Width < 16 || screenRect.Height < 16) return;
                recorder = new RecorderBar(screenRect, OnRecordingDone);
                Track(recorder);
                recorder.Show();
            }
        }

        void OnRecordingDone(string path, Exception error)
        {
            recorder = null;
            if (error != null)
            {
                MessageBox.Show(L.T("Không quay được video:\n") + error.Message, "MiniSnap", MessageBoxButtons.OK, MessageBoxIcon.Warning);
                return;
            }
            if (path == null || !File.Exists(path)) return;
            ShowLibrary(path);
            ShowBalloon(L.T("Đã lưu video"), Path.GetFileName(path) + L.T("\nBấm vào đây để xem."), () => Process.Start(path));
        }

        void SaveAndEdit(Bitmap img)
        {
            string path = Library.NewPath();
            try { img.Save(path, ImageFormat.Png); }
            catch (Exception) { path = null; }
            try { Clipboard.SetImage(img); }
            catch (ExternalException) { }
            OpenEditor(img, path);
        }

        void ShowOcr(Bitmap img)
        {
            Theme.Load();
            var f = new OcrForm(img);
            Track(f);
            f.Show();
            f.Activate();
        }

        void OcrFile(string path)
        {
            try
            {
                using (var img = Image.FromFile(path))
                using (var bmp = new Bitmap(img))
                    ShowOcr(bmp);
            }
            catch (Exception ex) { MessageBox.Show(L.T("Không mở được ảnh:\n") + ex.Message, "MiniSnap"); }
        }

        void ShowLibrary(string reveal)
        {
            if (library == null || library.IsDisposed)
            {
                Theme.Load();
                library = new LibraryForm(OpenImageFile, OcrFile);
                Track(library);
                library.Show();
            }
            if (reveal != null) library.Reveal(reveal);
            if (library.WindowState == FormWindowState.Minimized) library.WindowState = FormWindowState.Normal;
            library.Activate();
        }

        void OpenImageDialog()
        {
            using (var dlg = new OpenFileDialog { Filter = L.T("Ảnh|*.png;*.jpg;*.jpeg;*.bmp;*.gif|Tất cả|*.*"), InitialDirectory = Library.Folder })
                if (dlg.ShowDialog() == DialogResult.OK) OpenImageFile(dlg.FileName);
        }

        void OpenImageFile(string path)
        {
            Bitmap bmp;
            try
            {
                using (var img = Image.FromFile(path)) bmp = new Bitmap(img);
            }
            catch (Exception ex)
            {
                MessageBox.Show(L.T("Không mở được ảnh:\n") + ex.Message, "MiniSnap", MessageBoxButtons.OK, MessageBoxIcon.Warning);
                return;
            }
            using (bmp) OpenEditor(bmp, path);
        }

        void OpenEditor(Bitmap img, string path)
        {
            Theme.Load();
            var ed = new EditorForm(img, path, () => BeginCapture(Mode.Image, 0), ShowOcr, () => ShowLibrary(null));
            Track(ed);
            ed.Show();
            ed.Activate();
        }

        void Track(Form f)
        {
            windows.Add(f);
            f.FormClosed += (s, e) => windows.Remove(f);
        }

        protected override void ExitThreadCore()
        {
            if (recorder != null) recorder.StopRecording();
            foreach (var f in windows.ToArray())
            {
                f.Close();
                if (!f.IsDisposed && f.Visible) return; // user cancelled closing an unsaved editor
            }
            tray.Visible = false;
            tray.Dispose();
            hotkeys.Dispose();
            base.ExitThreadCore();
        }
    }

    // Renders sample output to PNG files so the drawing code can be checked without clicking through the UI.
    static class SelfTest
    {
        static void Log(string dir, string line) { File.AppendAllText(Path.Combine(dir, "log.txt"), line + Environment.NewLine); }

        static Bitmap SampleImage(int w, int h, int lines, int seed)
        {
            var bmp = new Bitmap(w, h, PixelFormat.Format32bppPArgb);
            var rnd = new Random(seed);
            using (var g = Graphics.FromImage(bmp))
            {
                g.Clear(Color.FromArgb(246, 248, 252));
                g.TextRenderingHint = System.Drawing.Text.TextRenderingHint.AntiAliasGridFit;
                using (var f = new Font("Segoe UI", 22f, FontStyle.Regular, GraphicsUnit.Pixel))
                    for (int i = 0; i < lines; i++)
                    {
                        g.DrawString("Line " + (i + 1) + L.T(" — the quick brown fox ") + rnd.Next(1000, 9999) + " jumps", f, Brushes.DimGray, 40, 30 + i * 58);
                        if (i % 7 == 3)
                            using (var br = new SolidBrush(Color.FromArgb(rnd.Next(80, 200), rnd.Next(80, 200), rnd.Next(80, 200))))
                                g.FillRectangle(br, w - 260, 20 + i * 58, 200, 40);
                    }
            }
            return bmp;
        }

        public static void Run(string dir)
        {
            Directory.CreateDirectory(dir);
            File.WriteAllText(Path.Combine(dir, "log.txt"), "");
            TestHotkeys(dir);
            TestModeBar(dir);
            TestRender(dir);
            TestBlur(dir);
            TestStitch(dir);
            TestOcr(dir);
            TestVideo(dir);
            TestEditorWindow(dir);
            TestLibraryWindow(dir);
            TestAboutWindow(dir);
            TestUpdater(dir);
        }

        static void TestHotkeys(string dir)
        {
            foreach (var h in HotkeySettings.Defaults().Values)
            {
                var back = Hotkey.Parse(h.Serialize());
                if (!h.Equals(back)) Log(dir, "hotkey roundtrip FAILED for " + h);
            }
            Log(dir, "hotkey defaults: " + string.Join(", ", HotkeySettings.Defaults().Select(kv => kv.Key + "=" + kv.Value.ShortText)));

            Dictionary<HotkeyAction, Hotkey> applied = null;
            var form = new HotkeySettingsForm(HotkeySettings.Defaults(), map => { applied = map; return new List<HotkeyAction> { HotkeyAction.Library }; });
            form.TopMost = true;
            var steps = new System.Windows.Forms.Timer { Interval = 700 };
            int step = 0;
            steps.Tick += (s, e) =>
            {
                switch (step++)
                {
                    case 0: form.TestPress(HotkeyAction.ScrollCapture, "^+1"); break;           // new combo
                    case 1: form.TestPress(HotkeyAction.Ocr, "^+1"); break;                     // duplicate -> warning
                    case 2:
                        using (var shot = ScreenCapture.Capture(form.Bounds)) shot.Save(Path.Combine(dir, "hotkeys-duplicate.png"), ImageFormat.Png);
                        form.TestPress(HotkeyAction.Ocr, "{F9}");                               // resolve with a bare F-key
                        break;
                    case 3: form.TestPress(HotkeyAction.RecordVideo, "a"); break;               // rejected: no modifier
                    case 4:
                        using (var shot = ScreenCapture.Capture(form.Bounds)) shot.Save(Path.Combine(dir, "hotkeys-reject.png"), ImageFormat.Png);
                        Log(dir, "hotkey form values: " + string.Join(", ", form.Values.Select(kv => kv.Key + "=" + kv.Value.ShortText)));
                        break;
                    case 6:
                        steps.Stop();
                        form.Close();
                        break;
                }
            };
            form.Shown += (s, e) => steps.Start();
            Application.Run(form);
        }

        // Overlay in ask mode over a synthetic background (never the real screen), with a region selected.
        static void TestModeBar(string dir)
        {
            Rectangle vs = SystemInformation.VirtualScreen;
            using (var fake = SampleImage(vs.Width, vs.Height, Math.Max(8, vs.Height / 60), 7))
            using (var ov = new CaptureOverlay(fake, vs, null) { AskMode = true })
            {
                var sel = new Rectangle(220, 160, 640, 360);
                var t = new System.Windows.Forms.Timer { Interval = 900 };
                t.Tick += (s, e) =>
                {
                    t.Stop();
                    var area = new Rectangle(vs.X + sel.X - 40, vs.Y + sel.Y - 50, sel.Width + 80, sel.Height + 140);
                    using (var shot = ScreenCapture.Capture(area)) shot.Save(Path.Combine(dir, "modebar.png"), ImageFormat.Png);
                    ov.DialogResult = DialogResult.Cancel;
                };
                ov.Shown += (s, e) => ov.BeginInvoke(new Action(() => { ov.SimulateSelect(sel); t.Start(); }));
                ov.ShowDialog();
                Log(dir, "modebar: choice after cancel=" + ov.Choice);
            }
        }

        static void TestRender(string dir)
        {
            using (var sample = SampleImage(900, 560, 9, 1))
            {
                var shapes = new List<Shape>
                {
                    new ArrowShape { A = new PointF(560, 420), B = new PointF(380, 150), Color = Color.FromArgb(232, 38, 38), Width = 5 },
                    new RectShape { A = new PointF(30, 80), B = new PointF(560, 140), Color = Color.FromArgb(232, 38, 38), Width = 4 },
                    new HighlightShape { A = new PointF(36, 200), B = new PointF(560, 240), Color = Color.FromArgb(255, 214, 0), Width = 5 },
                    new BlurShape { A = new PointF(330, 260), B = new PointF(720, 330), Width = 5 },
                    new StepShape { Center = new PointF(60, 470), Number = 1, Color = Color.FromArgb(232, 38, 38), Width = 5 },
                    new TextShape { Pos = new PointF(100, 450), Text = L.T("Chú thích tiếng Việt"), Color = Color.FromArgb(232, 38, 38), Width = 5 },
                };
                using (var flat = Renderer.Render(sample, shapes)) flat.Save(Path.Combine(dir, "render.png"), ImageFormat.Png);
            }
        }

        // Synthetic scrolling page with a sticky header and footer, viewed through a 600px viewport.
        static void TestStitch(string dir)
        {
            const int pageH = 2600, viewH = 600, header = 70, footer = 50, width = 800;
            using (var page = SampleImage(width, pageH, 44, 2))
            {
                var stitcher = new ScrollStitcher();
                int[] offsets = { 0, 230, 460, 700, 950, 1200, 1450, 1700, 1950, pageH - (viewH - header - footer) - header, pageH - (viewH - header - footer) - header };
                string outcomes = "";
                foreach (int off in offsets)
                {
                    var frame = new Bitmap(width, viewH, PixelFormat.Format32bppRgb);
                    using (var g = Graphics.FromImage(frame))
                    {
                        g.DrawImage(page, new Rectangle(0, header, width, viewH - header - footer), new Rectangle(0, off + header, width, viewH - header - footer), GraphicsUnit.Pixel);
                        g.FillRectangle(Brushes.SteelBlue, 0, 0, width, header);
                        g.DrawString("STICKY HEADER", SystemFonts.CaptionFont, Brushes.White, 10, 25);
                        g.FillRectangle(Brushes.DarkSlateGray, 0, viewH - footer, width, footer);
                        g.DrawString("STICKY FOOTER", SystemFonts.CaptionFont, Brushes.White, 10, viewH - footer + 15);
                    }
                    if (stitcher.FrameCount == 0) { stitcher.AddFirst(frame); outcomes += "first "; continue; }
                    var o = stitcher.Add(frame);
                    outcomes += o + " ";
                    if (o != ScrollStitcher.Outcome.Added) frame.Dispose();
                    if (o == ScrollStitcher.Outcome.NoMovement) break;
                }
                using (var result = stitcher.Compose()) result.Save(Path.Combine(dir, "stitch.png"), ImageFormat.Png);
                Log(dir, "stitch: " + outcomes + "| height=" + stitcher.TotalHeight + " expected=" + (pageH + footer));
                stitcher.DisposeFrames();
            }
        }

        static void TestOcr(string dir)
        {
            try
            {
                using (var img = SampleImage(900, 200, 3, 3))
                {
                    var r = OcrService.Recognize(img);
                    Log(dir, "ocr [" + r.Language + "]: " + r.Text.Replace(Environment.NewLine, " / ").Replace("\n", " / "));
                }
            }
            catch (Exception ex) { Log(dir, "ocr FAILED: " + ex); }
        }

        static void TestVideo(string dir)
        {
            string path = Path.Combine(dir, "test.mp4");
            if (File.Exists(path)) File.Delete(path);
            var area = new Rectangle(100, 100, 641, 401); // odd sizes on purpose: must be evened out
            var rec = new ScreenRecorder(area, path);
            Exception error = null;
            var done = new ManualResetEvent(false);
            rec.Finished += ex => { error = ex; done.Set(); };
            rec.Start();
            Thread.Sleep(2500);
            rec.Stop();
            done.WaitOne(15000);
            long size = File.Exists(path) ? new FileInfo(path).Length : 0;
            Log(dir, "video: " + (error != null ? "FAILED " + error : "ok") + " size=" + size + " elapsed=" + rec.Elapsed.TotalSeconds.ToString("0.0") + "s");
            if (size > 0)
            {
                Thread.Sleep(500);
                using (var thumb = ShellThumbnail.Get(path, 320))
                {
                    if (thumb != null) thumb.Save(Path.Combine(dir, "video-thumb.png"), ImageFormat.Png);
                    Log(dir, "video thumbnail: " + (thumb != null ? thumb.Width + "x" + thumb.Height : "none"));
                }
            }
        }

        static void CaptureFormAndClose(Form f, string file, int delay)
        {
            var t = new System.Windows.Forms.Timer { Interval = delay };
            t.Tick += (s, e) =>
            {
                t.Stop();
                using (var shot = ScreenCapture.Capture(f.Bounds)) shot.Save(file, ImageFormat.Png);
                f.Close();
            };
            f.Shown += (s, e) => t.Start();
            Application.Run(f);
        }

        static void TestEditorWindow(string dir)
        {
            using (var sample = SampleImage(900, 560, 9, 4))
            {
                var ed = new EditorForm(sample, null, () => { }, b => { }, () => { });
                ed.LoadShapes(new List<Shape>
                {
                    new ArrowShape { A = new PointF(560, 420), B = new PointF(380, 150), Color = Color.FromArgb(232, 38, 38), Width = 5 },
                    new StepShape { Center = new PointF(60, 470), Number = 1, Color = Color.FromArgb(30, 120, 230), Width = 5 },
                });
                ed.SkipSavePrompt = true;
                CaptureFormAndClose(ed, Path.Combine(dir, "editor.png"), 1200);
            }
            // The blur tool swaps the stroke width for its cell size and softness sliders.
            using (var sample = SampleImage(900, 560, 9, 4))
            {
                var ed = new EditorForm(sample, null, () => { }, b => { }, () => { });
                ed.LoadShapes(new List<Shape> { new BlurShape { A = new PointF(30, 20), B = new PointF(620, 260), Cell = 5, Smooth = 3 } });
                ed.UseTool(Tool.Blur);
                ed.SkipSavePrompt = true;
                CaptureFormAndClose(ed, Path.Combine(dir, "editor-blur.png"), 1200);
            }
        }

        // Coloured bands with dark text, so cells and softness are easy to judge.
        static Bitmap BlurSample(int w, int h)
        {
            var bmp = new Bitmap(w, h, PixelFormat.Format32bppPArgb);
            using (var g = Graphics.FromImage(bmp))
            {
                Color[] bands = { Color.FromArgb(255, 214, 0), Color.FromArgb(30, 145, 75), Color.FromArgb(25, 110, 225), Color.FromArgb(232, 38, 38) };
                for (int i = 0; i < bands.Length; i++)
                    using (var br = new SolidBrush(bands[i])) g.FillRectangle(br, i * w / bands.Length, 0, w / bands.Length + 1, h / 2);
                g.FillRectangle(Brushes.White, 0, h / 2, w, h - h / 2);
                g.TextRenderingHint = System.Drawing.Text.TextRenderingHint.AntiAliasGridFit;
                using (var f = new Font("Segoe UI", 26f, FontStyle.Bold, GraphicsUnit.Pixel))
                {
                    g.DrawString("0912 345 678", f, Brushes.White, 20, 18);
                    g.DrawString("nnqbao@mail.vn", f, Brushes.Black, 20, h / 2 + 10);
                }
            }
            return bmp;
        }

        // Every cell size (rows 1, 4, 7, 10) against softness 0, 5 and 10 (columns), on the same picture.
        static void TestBlur(string dir)
        {
            int[] cells = { 1, 4, 7, 10 }, smooths = { 0, 5, 10 };
            const int tw = 300, th = 150;
            using (var grid = new Bitmap(tw * smooths.Length, th * cells.Length, PixelFormat.Format32bppPArgb))
            {
                using (var g = Graphics.FromImage(grid))
                    for (int row = 0; row < cells.Length; row++)
                        for (int col = 0; col < smooths.Length; col++)
                            using (var tile = BlurSample(tw, th))
                            {
                                var blur = new BlurShape { A = new PointF(10, 10), B = new PointF(tw - 10, th - 10), Cell = cells[row], Smooth = smooths[col] };
                                using (var flat = Renderer.Render(tile, new List<Shape> { blur }))
                                    g.DrawImage(flat, col * tw, row * th, tw, th);
                                g.DrawRectangle(Pens.White, col * tw, row * th, tw - 1, th - 1);
                                using (var f = new Font("Segoe UI", 12f, FontStyle.Bold, GraphicsUnit.Pixel))
                                    g.DrawString("cell " + cells[row] + " / soft " + smooths[col], f, Brushes.Black, col * tw + 14, row * th + th - 26);
                            }
                grid.Save(Path.Combine(dir, "blur-grid.png"), ImageFormat.Png);
            }
            Log(dir, "blur grid: " + cells.Length * smooths.Length + " tiles");
        }

        static void TestUpdater(string dir)
        {
            try
            {
                var latest = Updater.Fetch();
                Log(dir, "update fetch: " + (latest == null ? "no releases (404)" : latest.Tag + " setup=" + (latest.SetupUrl != null) + " sha=" + (latest.Sha256 != null) + " newer=" + Updater.IsNewer(latest)));
                if (latest != null && latest.SetupUrl != null)
                {
                    // Real download of the published installer, including the SHA-256 check.
                    string got = Updater.Download(latest, p => { }, () => false);
                    Log(dir, "update download ok: " + new FileInfo(got).Length + " bytes, sha verified=" + (latest.Sha256 != null));
                    File.Delete(got);
                }
            }
            catch (Exception ex) { Log(dir, "update fetch FAILED: " + ex.Message); }
            var cur = Updater.Current;
            Log(dir, "update compare: current=" + cur
                + " newer(+1 minor)=" + Updater.IsNewer(new Updater.Release { Version = new Version(cur.Major, cur.Minor + 1, 0) })
                + " newer(same)=" + Updater.IsNewer(new Updater.Release { Version = cur })
                + " newer(older)=" + Updater.IsNewer(new Updater.Release { Version = new Version(1, 0, 0) }));
            try
            {
                Updater.Download(new Updater.Release { Version = new Version(9, 9, 9), SetupUrl = "https://example.com/MiniSnap-Setup.exe" }, p => { }, () => false);
                Log(dir, "update host check FAILED: non-GitHub URL accepted");
            }
            catch (InvalidOperationException ex) { Log(dir, "update host check ok: " + ex.Message); }

            var fake = new Updater.Release
            {
                Version = new Version(cur.Major, cur.Minor + 1, 0), Tag = "v" + cur.Major + "." + (cur.Minor + 1) + ".0",
                Notes = "## What's new\n- Example release notes shown in the update window\n- Faster scrolling capture",
                PageUrl = AppInfo.Repo + "/releases", SetupUrl = AppInfo.Repo + "/releases/download/x/MiniSnap-Setup.exe",
            };
            CaptureFormAndClose(new UpdateForm(p => { }, fake), Path.Combine(dir, "update.png"), 1000);
        }

        static void TestAboutWindow(string dir)
        {
            CaptureFormAndClose(new AboutForm(() => { }), Path.Combine(dir, "about.png"), 1000);
        }

        static void TestLibraryWindow(string dir)
        {
            var lib = new LibraryForm(p => { }, p => { });
            CaptureFormAndClose(lib, Path.Combine(dir, "library.png"), 3000);
        }
    }
}
