# Corner button that opens a small support window: ticket and news.
# Windows PowerShell 5.1, STA. No administrator rights.

Set-StrictMode -Version 2.0

$script:WidgetForm = $null
$script:PanelForm = $null
$script:WidgetUi = $null
$script:WidgetHost = [IntPtr]::Zero
$script:TrayIcon = $null
$script:NewsItems = @()
$script:LastNewsPoll = [datetime]::MinValue
$script:NewsHintShown = $false
$script:NewsSignature = $null
$script:OpenedNoticeIds = @{}
$script:ReadNoticeIds = @{}
$script:NewsPinnedIds = @{}
$script:NewsReading = $false
$script:ReadNoticesImported = $false
$script:AllowExit = $false
$script:PanelOpen = $false
$script:PanelHiding = $false
$script:WidgetPage = 'Ticket'
$script:SupportPanelWidth = 360
$script:SupportPanelHeight = 580
$script:NewsPopup = $null
$script:NewsPopupBody = $null
$script:NewsPopupTitle = $null
$script:NewsPopupHiding = $false
$script:LauncherHot = $false
$script:LauncherClickAt = [datetime]::MinValue
$script:WidgetContext = $null
$script:DesktopMode = ''
$script:DesktopVerdict = ''
$script:JiraDesks = @()
$script:JiraRequestTypes = @()
$script:JiraLoaded = $false
$script:JiraLoading = $false
$script:JiraPower = $null
$script:JiraAsync = $null
$script:JiraWait = $null
$script:JiraJobKind = ''
$script:TopMenuItem = $null
$script:WidgetPalette = $null
$script:AppThemeLight = $true
$script:LauncherMenuItem = $null
$script:TrayMenu = $null
$script:TrayMenuColors = $null
$script:TrayIconOwned = $false
$script:LauncherClickHook = $null
$script:ThemeHooked = $false
$script:ThemeHandler = $null
$script:ApplyingTheme = $false
$script:PopupNotices = @()
$script:ListPopup = $null
$script:ListPopupClosing = $false
$script:ListPopupReady = $false
$script:SoftListSource = $null
$script:ListScroll = 0
$script:ListMaxRows = 0
$script:ListRows = @()
$script:ListRowH = 34
$script:ListPad = 8
$script:SendHot = $false
$script:CloseHot = $false
$script:DeskLayerFailed = $false
$script:IconMissLogged = $false
$script:LauncherColorLogged = $false
$script:CornerLogged = $false
$script:ConfigFile = $null

$script:DesktopHostSource = @'
using System;
using System.Runtime.InteropServices;

public sealed class DesktopPoint {
    public int X;
    public int Y;
}

public static class DesktopHost {
    delegate bool EnumProc(IntPtr hwnd, IntPtr lparam);

    [StructLayout(LayoutKind.Sequential)]
    struct POINT {
        public int X;
        public int Y;
    }

    [DllImport("user32.dll", CharSet = CharSet.Unicode)]
    static extern IntPtr FindWindow(string cls, string window);

    [DllImport("user32.dll", CharSet = CharSet.Unicode)]
    static extern IntPtr FindWindowEx(IntPtr parent, IntPtr child, string cls, string window);

    [DllImport("user32.dll")]
    static extern bool EnumWindows(EnumProc lpEnumFunc, IntPtr lparam);

    [DllImport("user32.dll", CharSet = CharSet.Unicode)]
    static extern IntPtr SendMessageTimeout(IntPtr hWnd, uint Msg, UIntPtr wParam, IntPtr lParam, uint fuFlags, uint uTimeout, out UIntPtr result);

    [DllImport("user32.dll")]
    static extern IntPtr SetParent(IntPtr child, IntPtr parent);

    [DllImport("user32.dll")]
    static extern bool ScreenToClient(IntPtr hwnd, ref POINT point);

    [DllImport("user32.dll", EntryPoint = "GetWindowLong")]
    static extern int GetWindowLong32(IntPtr hWnd, int nIndex);

    [DllImport("user32.dll", EntryPoint = "SetWindowLong")]
    static extern int SetWindowLong32(IntPtr hWnd, int nIndex, int dwNewLong);

    [DllImport("user32.dll", EntryPoint = "GetWindowLongPtr")]
    static extern IntPtr GetWindowLongPtr64(IntPtr hWnd, int nIndex);

    [DllImport("user32.dll", EntryPoint = "SetWindowLongPtr")]
    static extern IntPtr SetWindowLongPtr64(IntPtr hWnd, int nIndex, IntPtr dwNewLong);

    static IntPtr foundHost;

    public static IntPtr Find() {
        IntPtr progman = FindWindow("Progman", null);
        UIntPtr ignored;
        if (progman != IntPtr.Zero) {
            SendMessageTimeout(progman, 0x052C, UIntPtr.Zero, IntPtr.Zero, 0x0002, 1000, out ignored);
        }
        foundHost = IntPtr.Zero;
        EnumWindows(delegate (IntPtr hwnd, IntPtr lparam) {
            IntPtr shell = FindWindowEx(hwnd, IntPtr.Zero, "SHELLDLL_DefView", null);
            if (shell != IntPtr.Zero) {
                IntPtr worker = FindWindowEx(IntPtr.Zero, hwnd, "WorkerW", null);
                if (worker != IntPtr.Zero) foundHost = worker;
                else if (foundHost == IntPtr.Zero) foundHost = hwnd;
            }
            return true;
        }, IntPtr.Zero);
        if (foundHost != IntPtr.Zero) return foundHost;
        return progman;
    }

    public static void Attach(IntPtr child, IntPtr host) {
        if (child == IntPtr.Zero || host == IntPtr.Zero) return;
        const int GWL_STYLE = -16;
        const int WS_CHILD = 0x40000000;
        const int WS_POPUP = unchecked((int)0x80000000);
        if (IntPtr.Size == 8) {
            long style = GetWindowLongPtr64(child, GWL_STYLE).ToInt64();
            style = (style | WS_CHILD) & ~((long)WS_POPUP);
            SetWindowLongPtr64(child, GWL_STYLE, new IntPtr(style));
        } else {
            int style = GetWindowLong32(child, GWL_STYLE);
            style = (style | WS_CHILD) & ~WS_POPUP;
            SetWindowLong32(child, GWL_STYLE, style);
        }
        SetParent(child, host);
    }

    public static DesktopPoint ToClient(IntPtr host, int screenX, int screenY) {
        POINT point = new POINT();
        point.X = screenX;
        point.Y = screenY;
        ScreenToClient(host, ref point);
        DesktopPoint result = new DesktopPoint();
        result.X = point.X;
        result.Y = point.Y;
        return result;
    }

    public static void PrepareLauncher(IntPtr hwnd) {
        SetExtraStyle(hwnd, true);
    }

    public static void PreparePanel(IntPtr hwnd) {
        SetExtraStyle(hwnd, false);
    }

    static void SetExtraStyle(IntPtr hwnd, bool noActivate) {
        if (hwnd == IntPtr.Zero) return;
        const int GWL_EXSTYLE = -20;
        const long WS_EX_TOOLWINDOW = 0x80;
        const long WS_EX_APPWINDOW = 0x40000;
        const long WS_EX_NOACTIVATE = 0x08000000;
        if (IntPtr.Size == 8) {
            long style = GetWindowLongPtr64(hwnd, GWL_EXSTYLE).ToInt64();
            style = (style | WS_EX_TOOLWINDOW) & ~WS_EX_APPWINDOW;
            if (noActivate) style |= WS_EX_NOACTIVATE;
            SetWindowLongPtr64(hwnd, GWL_EXSTYLE, new IntPtr(style));
        } else {
            int style = GetWindowLong32(hwnd, GWL_EXSTYLE);
            style = (style | (int)WS_EX_TOOLWINDOW) & ~(int)WS_EX_APPWINDOW;
            if (noActivate) style |= (int)WS_EX_NOACTIVATE;
            SetWindowLong32(hwnd, GWL_EXSTYLE, style);
        }
    }
}
'@

function Initialize-DeskLayer {
    if ('DeskLayer' -as [type]) { return $true }
    if ($script:DeskLayerFailed) { return $false }
    $source = @'
using System;
using System.Drawing;
using System.Drawing.Drawing2D;
using System.Drawing.Imaging;
using System.IO;
using System.Runtime.InteropServices;
using System.Windows.Forms;

public static class DeskLayer {
    [StructLayout(LayoutKind.Sequential)]
    struct POINT { public int X; public int Y; }
    [StructLayout(LayoutKind.Sequential)]
    struct SIZE { public int cx; public int cy; }
    [StructLayout(LayoutKind.Sequential)]
    struct BLENDFUNCTION {
        public byte BlendOp;
        public byte BlendFlags;
        public byte SourceConstantAlpha;
        public byte AlphaFormat;
    }
    [StructLayout(LayoutKind.Sequential)]
    struct BITMAPINFOHEADER {
        public int biSize;
        public int biWidth;
        public int biHeight;
        public short biPlanes;
        public short biBitCount;
        public int biCompression;
        public int biSizeImage;
        public int biXPelsPerMeter;
        public int biYPelsPerMeter;
        public int biClrUsed;
        public int biClrImportant;
    }
    [DllImport("user32.dll", EntryPoint = "GetWindowLong")]
    static extern int GetWindowLong32(IntPtr hWnd, int nIndex);
    [DllImport("user32.dll", EntryPoint = "SetWindowLong")]
    static extern int SetWindowLong32(IntPtr hWnd, int nIndex, int dwNewLong);
    [DllImport("user32.dll", EntryPoint = "GetWindowLongPtr")]
    static extern IntPtr GetWindowLongPtr64(IntPtr hWnd, int nIndex);
    [DllImport("user32.dll", EntryPoint = "SetWindowLongPtr")]
    static extern IntPtr SetWindowLongPtr64(IntPtr hWnd, int nIndex, IntPtr dwNewLong);
    [DllImport("user32.dll")] static extern IntPtr GetDC(IntPtr hWnd);
    [DllImport("user32.dll")] static extern int ReleaseDC(IntPtr hWnd, IntPtr hDC);
    [DllImport("gdi32.dll")] static extern IntPtr CreateCompatibleDC(IntPtr hdc);
    [DllImport("gdi32.dll")] static extern bool DeleteDC(IntPtr hdc);
    [DllImport("gdi32.dll")] static extern IntPtr SelectObject(IntPtr hdc, IntPtr obj);
    [DllImport("gdi32.dll")] static extern bool DeleteObject(IntPtr obj);
    [DllImport("gdi32.dll")] static extern IntPtr CreateDIBSection(IntPtr hdc, ref BITMAPINFOHEADER bmi, uint usage, out IntPtr bits, IntPtr section, uint offset);
    [DllImport("user32.dll")] static extern bool UpdateLayeredWindow(IntPtr hwnd, IntPtr hdcDst, ref POINT pptDst, ref SIZE psize, IntPtr hdcSrc, ref POINT pptSrc, int crKey, ref BLENDFUNCTION pblend, int dwFlags);
    [DllImport("user32.dll", SetLastError = true)]
    public static extern bool DestroyIcon(IntPtr handle);
    [DllImport("user32.dll", SetLastError = true)]
    static extern IntPtr CreateIconFromResourceEx(byte[] bits, uint size, bool icon, uint version, int cx, int cy, uint flags);
    [DllImport("kernel32.dll", EntryPoint = "RtlMoveMemory")]
    static extern void CopyMemory(IntPtr dest, IntPtr src, uint length);

    static void SetLayered(IntPtr hwnd, bool on) {
        const int GWL_EXSTYLE = -20;
        const int WS_EX_LAYERED = 0x80000;
        if (IntPtr.Size == 8) {
            long style = GetWindowLongPtr64(hwnd, GWL_EXSTYLE).ToInt64();
            if (on) style |= WS_EX_LAYERED;
            else style &= ~WS_EX_LAYERED;
            SetWindowLongPtr64(hwnd, GWL_EXSTYLE, new IntPtr(style));
        } else {
            int style = GetWindowLong32(hwnd, GWL_EXSTYLE);
            if (on) style |= WS_EX_LAYERED;
            else style &= ~WS_EX_LAYERED;
            SetWindowLong32(hwnd, GWL_EXSTYLE, style);
        }
    }

    static GraphicsPath RoundRect(float x, float y, float w, float h, float r) {
        GraphicsPath path = new GraphicsPath();
        float d = r * 2f;
        if (d > w) d = w;
        if (d > h) d = h;
        path.AddArc(x, y, d, d, 180, 90);
        path.AddArc(x + w - d, y, d, d, 270, 90);
        path.AddArc(x + w - d, y + h - d, d, d, 0, 90);
        path.AddArc(x, y + h - d, d, d, 90, 90);
        path.CloseFigure();
        return path;
    }

    static void DrawExclamation(Graphics g, float size) {
        float s = size / 52f;
        float weight = 3.4f * s;
        if (weight < 1.6f) weight = 1.6f;
        using (Pen pen = new Pen(Color.White, weight)) {
            pen.StartCap = LineCap.Round;
            pen.EndCap = LineCap.Round;
            g.DrawLine(pen, 26f * s, 12f * s, 26f * s, 31f * s);
        }
        using (SolidBrush brush = new SolidBrush(Color.White)) {
            float d = 5.2f * s;
            if (d < 2.4f) d = 2.4f;
            g.FillEllipse(brush, 26f * s - d / 2f, 36.5f * s, d, d);
        }
    }

    static void DrawNoticeBadge(Graphics g, int badge, int size) {
        string text = badge > 9 ? "9+" : badge.ToString();
        float height = 20f;
        float width = text.Length > 1 ? 26f : 20f;
        float left = size - width - 1f;
        float top = 1f;
        g.TextRenderingHint = System.Drawing.Text.TextRenderingHint.AntiAliasGridFit;
        using (SolidBrush shadow = new SolidBrush(Color.FromArgb(80, 0, 0, 0))) {
            g.FillEllipse(shadow, left + 0.4f, top + 1.6f, width, height);
        }
        using (SolidBrush plate = new SolidBrush(Color.FromArgb(255, 23, 26, 33))) {
            g.FillEllipse(plate, left, top, width, height);
        }
        using (Pen ring = new Pen(Color.White, 1.7f)) {
            g.DrawEllipse(ring, left + 1.15f, top + 1.15f, width - 2.3f, height - 2.3f);
        }
        float fontSize = text.Length > 1 ? 10f : 12f;
        using (Font font = new Font("Segoe UI", fontSize, FontStyle.Bold, GraphicsUnit.Pixel))
        using (SolidBrush ink = new SolidBrush(Color.White))
        using (StringFormat format = new StringFormat()) {
            format.Alignment = StringAlignment.Center;
            format.LineAlignment = StringAlignment.Center;
            format.FormatFlags = StringFormatFlags.NoWrap;
            g.DrawString(text, font, ink, new RectangleF(left, top - 0.4f, width, height), format);
        }
    }

    public static bool ShowLauncher(IntPtr hwnd, int fillArgb, int x, int y, bool open, int badge, string iconPath) {
        if (hwnd == IntPtr.Zero) return false;
        const int size = 52;
        Bitmap bmp = new Bitmap(size, size, PixelFormat.Format32bppPArgb);
        using (Graphics g = Graphics.FromImage(bmp)) {
            g.SmoothingMode = SmoothingMode.AntiAlias;
            g.PixelOffsetMode = PixelOffsetMode.HighQuality;
            g.Clear(Color.Transparent);
            Color fill = Color.FromArgb(fillArgb);
            if (open) {
                using (SolidBrush plateBrush = new SolidBrush(Color.FromArgb(168, 16, 18, 24))) {
                    g.FillEllipse(plateBrush, 0.5f, 0.5f, 51f, 51f);
                }
                using (Pen pen = new Pen(Color.White, 2.6f)) {
                    pen.StartCap = LineCap.Round;
                    pen.EndCap = LineCap.Round;
                    pen.LineJoin = LineJoin.Round;
                    g.DrawLine(pen, 18f, 18f, 34f, 34f);
                    g.DrawLine(pen, 34f, 18f, 18f, 34f);
                }
            } else {
            Color disc = fill;
            int plateAlpha = disc.A == 0 ? 1 : disc.A;
            using (SolidBrush brush = new SolidBrush(Color.FromArgb(plateAlpha, disc.R, disc.G, disc.B))) {
                g.FillEllipse(brush, 0.5f, 0.5f, 51f, 51f);
            }
            bool drewIcon = false;
            int inset = disc.A == 0 ? 1 : 6;
            int iconSize = size - (inset * 2);
            if (!string.IsNullOrEmpty(iconPath) && File.Exists(iconPath)) {
                try {
                    using (FileStream stream = new FileStream(iconPath, FileMode.Open, FileAccess.Read, FileShare.ReadWrite))
                    using (Image image = Image.FromStream(stream)) {
                        g.SetClip(new Rectangle(0, 0, size, size));
                        using (GraphicsPath clip = new GraphicsPath()) {
                            clip.AddEllipse(inset, inset, iconSize, iconSize);
                            g.SetClip(clip);
                        }
                        g.DrawImage(image, new Rectangle(inset, inset, iconSize, iconSize));
                        g.ResetClip();
                        drewIcon = true;
                    }
                } catch {
                    drewIcon = false;
                }
            }
            if (!drewIcon) DrawExclamation(g, size);
            }
            if (badge > 0 && !open) DrawNoticeBadge(g, badge, size);
        }
        IntPtr screen = GetDC(IntPtr.Zero);
        IntPtr mem = CreateCompatibleDC(screen);
        BITMAPINFOHEADER info = new BITMAPINFOHEADER();
        info.biSize = 40;
        info.biWidth = size;
        info.biHeight = -size;
        info.biPlanes = 1;
        info.biBitCount = 32;
        IntPtr bits;
        IntPtr dib = CreateDIBSection(screen, ref info, 0, out bits, IntPtr.Zero, 0);
        bool ok = false;
        try {
            BitmapData src = bmp.LockBits(new Rectangle(0, 0, size, size), ImageLockMode.ReadOnly, PixelFormat.Format32bppPArgb);
            int stride = src.Stride;
            int abs = stride < 0 ? -stride : stride;
            for (int row = 0; row < size; row++) {
                long from = src.Scan0.ToInt64() + (stride > 0 ? row * stride : (size - 1 - row) * abs);
                long to = bits.ToInt64() + (row * size * 4);
                CopyMemory(new IntPtr(to), new IntPtr(from), (uint)(size * 4));
            }
            bmp.UnlockBits(src);
            IntPtr old = SelectObject(mem, dib);
            SetLayered(hwnd, true);
            POINT dst = new POINT();
            dst.X = x;
            dst.Y = y;
            SIZE dim = new SIZE();
            dim.cx = size;
            dim.cy = size;
            POINT srcPt = new POINT();
            BLENDFUNCTION blend = new BLENDFUNCTION();
            blend.BlendOp = 0;
            blend.SourceConstantAlpha = 255;
            blend.AlphaFormat = 1;
            ok = UpdateLayeredWindow(hwnd, screen, ref dst, ref dim, mem, ref srcPt, 0, ref blend, 2);
            SelectObject(mem, old);
            if (!ok) SetLayered(hwnd, false);
        } finally {
            if (dib != IntPtr.Zero) DeleteObject(dib);
            DeleteDC(mem);
            ReleaseDC(IntPtr.Zero, screen);
            bmp.Dispose();
        }
        return ok;
    }

    public static Icon MakeChatIcon(int fillArgb) {
        const int size = 32;
        Color fill = Color.FromArgb(fillArgb);
        Color accent = Color.FromArgb(255, fill.R, fill.G, fill.B);
        Bitmap bmp = new Bitmap(size, size, PixelFormat.Format32bppArgb);
        using (Graphics g = Graphics.FromImage(bmp)) {
            g.SmoothingMode = SmoothingMode.AntiAlias;
            g.PixelOffsetMode = PixelOffsetMode.HighQuality;
            g.Clear(Color.Transparent);
            using (SolidBrush brush = new SolidBrush(accent)) {
                g.FillEllipse(brush, 0.5f, 0.5f, 31f, 31f);
            }
            DrawExclamation(g, size);
        }
        IntPtr handle = IntPtr.Zero;
        try {
            using (MemoryStream stream = new MemoryStream()) {
                bmp.Save(stream, ImageFormat.Png);
                byte[] png = stream.ToArray();
                handle = CreateIconFromResourceEx(png, (uint)png.Length, true, 0x00030000, size, size, 0);
            }
        } catch {
            handle = IntPtr.Zero;
        }
        if (handle == IntPtr.Zero) handle = bmp.GetHicon();
        bmp.Dispose();
        if (handle == IntPtr.Zero) return null;
        return Icon.FromHandle(handle);
    }
}

public class DeskClickWindow : NativeWindow {
    protected override void WndProc(ref Message m) {
        if (m.Msg == 0x0021) {
            m.Result = (IntPtr)3;
            return;
        }
        base.WndProc(ref m);
    }
}

public class DeskMenuColors : ProfessionalColorTable {
    public Color Canvas = Color.White;
    public Color Ink = Color.FromArgb(24, 24, 27);
    public Color Hover = Color.FromArgb(244, 244, 245);
    public Color Rule = Color.FromArgb(244, 244, 245);
    public Color Accent = Color.FromArgb(220, 38, 38);
    public override Color ToolStripDropDownBackground { get { return Canvas; } }
    public override Color MenuBorder { get { return Rule; } }
    public override Color MenuItemBorder { get { return Hover; } }
    public override Color MenuItemSelected { get { return Hover; } }
    public override Color MenuItemSelectedGradientBegin { get { return Hover; } }
    public override Color MenuItemSelectedGradientEnd { get { return Hover; } }
    public override Color MenuItemPressedGradientBegin { get { return Hover; } }
    public override Color MenuItemPressedGradientMiddle { get { return Hover; } }
    public override Color MenuItemPressedGradientEnd { get { return Hover; } }
    public override Color ImageMarginGradientBegin { get { return Canvas; } }
    public override Color ImageMarginGradientMiddle { get { return Canvas; } }
    public override Color ImageMarginGradientEnd { get { return Canvas; } }
    public override Color ImageMarginRevealedGradientBegin { get { return Canvas; } }
    public override Color ImageMarginRevealedGradientMiddle { get { return Canvas; } }
    public override Color ImageMarginRevealedGradientEnd { get { return Canvas; } }
    public override Color SeparatorDark { get { return Rule; } }
    public override Color SeparatorLight { get { return Canvas; } }
    public override Color CheckBackground { get { return Canvas; } }
    public override Color CheckSelectedBackground { get { return Hover; } }
    public override Color CheckPressedBackground { get { return Hover; } }
    public override Color ButtonSelectedHighlight { get { return Hover; } }
    public override Color ButtonSelectedHighlightBorder { get { return Hover; } }
    public override Color ButtonSelectedBorder { get { return Hover; } }
    public override Color ToolStripBorder { get { return Rule; } }
    public override Color GripDark { get { return Rule; } }
    public override Color GripLight { get { return Canvas; } }
}

public class DeskMenuRenderer : ToolStripProfessionalRenderer {
    public DeskMenuRenderer(DeskMenuColors colors) : base(colors) {
        RoundedEdges = false;
    }

    DeskMenuColors Colors { get { return (DeskMenuColors)ColorTable; } }

    static GraphicsPath RoundMenu(float x, float y, float w, float h, float r) {
        GraphicsPath path = new GraphicsPath();
        float d = r * 2f;
        if (d > w) d = w;
        if (d > h) d = h;
        if (d < 1f) d = 1f;
        path.AddArc(x, y, d, d, 180, 90);
        path.AddArc(x + w - d, y, d, d, 270, 90);
        path.AddArc(x + w - d, y + h - d, d, d, 0, 90);
        path.AddArc(x, y + h - d, d, d, 90, 90);
        path.CloseFigure();
        return path;
    }

    protected override void OnRenderToolStripBackground(ToolStripRenderEventArgs e) {
        e.Graphics.Clear(Colors.Canvas);
    }

    protected override void OnRenderImageMargin(ToolStripRenderEventArgs e) {
        using (SolidBrush brush = new SolidBrush(Colors.Canvas)) {
            e.Graphics.FillRectangle(brush, e.AffectedBounds);
        }
    }

    protected override void OnRenderToolStripBorder(ToolStripRenderEventArgs e) {
        Graphics g = e.Graphics;
        g.SmoothingMode = SmoothingMode.AntiAlias;
        Rectangle b = e.AffectedBounds;
        if (b.Width < 4 || b.Height < 4) return;
        using (Pen pen = new Pen(Colors.Rule, 1f))
        using (GraphicsPath path = RoundMenu(b.X + 0.5f, b.Y + 0.5f, b.Width - 1f, b.Height - 1f, 12f)) {
            g.DrawPath(pen, path);
        }
    }

    protected override void OnRenderMenuItemBackground(ToolStripItemRenderEventArgs e) {
        if (e.Item is ToolStripSeparator) return;
        Rectangle bounds = new Rectangle(6, 1, e.Item.Width - 12, e.Item.Height - 2);
        if (bounds.Width < 4 || bounds.Height < 4) return;
        Color fill = Colors.Canvas;
        if (e.Item.Selected || e.Item.Pressed) fill = Colors.Hover;
        e.Graphics.SmoothingMode = SmoothingMode.AntiAlias;
        using (SolidBrush brush = new SolidBrush(fill))
        using (GraphicsPath path = RoundMenu(bounds.X, bounds.Y, bounds.Width, bounds.Height, 8f)) {
            e.Graphics.FillPath(brush, path);
        }
    }

    protected override void OnRenderItemText(ToolStripItemTextRenderEventArgs e) {
        e.TextColor = Colors.Ink;
        base.OnRenderItemText(e);
    }

    protected override void OnRenderSeparator(ToolStripSeparatorRenderEventArgs e) {
        int y = e.Item.Height / 2;
        using (Pen pen = new Pen(Colors.Rule, 1f)) {
            e.Graphics.DrawLine(pen, 14, y, e.Item.Width - 14, y);
        }
    }

    protected override void OnRenderItemCheck(ToolStripItemImageRenderEventArgs e) {
        Graphics g = e.Graphics;
        g.SmoothingMode = SmoothingMode.AntiAlias;
        Rectangle b = e.ImageRectangle;
        float x = b.Left + 2f;
        float y = b.Top + (b.Height / 2f);
        using (Pen pen = new Pen(Colors.Ink, 1.8f)) {
            pen.StartCap = LineCap.Round;
            pen.EndCap = LineCap.Round;
            pen.LineJoin = LineJoin.Round;
            g.DrawLine(pen, x, y, x + 3.2f, y + 3.2f);
            g.DrawLine(pen, x + 3.2f, y + 3.2f, x + 8.2f, y - 3.4f);
        }
    }

    protected override void OnRenderArrow(ToolStripArrowRenderEventArgs e) {
        e.ArrowColor = Colors.Ink;
        base.OnRenderArrow(e);
    }
}
'@
    try {
        Add-Type -TypeDefinition $source -ReferencedAssemblies System.Drawing, System.Windows.Forms -ErrorAction Stop
        return $true
    } catch {
        $script:DeskLayerFailed = $true
        return $false
    }
}

function Resolve-WidgetIconPath {
    param([string]$Path)
    if ([string]::IsNullOrWhiteSpace($Path)) { return '' }
    $clean = $Path.Trim().Trim('"')
    if ([System.IO.Path]::IsPathRooted($clean)) {
        if (Test-Path -LiteralPath $clean) { return (Resolve-Path -LiteralPath $clean).Path }
        return ''
    }
    $roots = New-Object System.Collections.Generic.List[string]
    if ($script:ConfigFile) {
        $parent = Split-Path -Parent ([string]$script:ConfigFile)
        if (-not [string]::IsNullOrWhiteSpace($parent)) { $roots.Add($parent) }
    }
    if (-not [string]::IsNullOrWhiteSpace($PSScriptRoot)) { $roots.Add($PSScriptRoot) }
    foreach ($root in $roots) {
        $full = Join-Path $root $clean
        if (Test-Path -LiteralPath $full) { return (Resolve-Path -LiteralPath $full).Path }
    }
    return ''
}

function Update-LauncherSurface {
    $form = $script:WidgetForm
    if ($null -eq $form -or $form.IsDisposed) { return }
    if (-not $form.IsHandleCreated) { return }
    $color = Get-LauncherFill
    if ($script:LauncherHot) { $color = Get-LauncherFill -Hover }
    if (-not $script:LauncherColorLogged -and $script:Cfg) {
        $script:LauncherColorLogged = $true
        $shown = [string]$script:Cfg.WidgetColor
        $opaque = 100
        if ($script:Cfg.PSObject.Properties['WidgetOpacity']) { $opaque = [int]$script:Cfg.WidgetOpacity }
        if ([string]::IsNullOrWhiteSpace($shown)) { $shown = '#DC2626' }
        Write-Log ("Кнопка: цвет {0}, непрозрачность {1}%." -f $shown, $opaque)
    }
    $icon = ''
    if ($script:Cfg -and -not [string]::IsNullOrWhiteSpace([string]$script:Cfg.WidgetIcon)) {
        $icon = Resolve-WidgetIconPath ([string]$script:Cfg.WidgetIcon)
        if ([string]::IsNullOrWhiteSpace($icon) -and -not $script:IconMissLogged) {
            $script:IconMissLogged = $true
            Write-Log ("Файл иконки не найден: {0}" -f [string]$script:Cfg.WidgetIcon) 'WARN'
        }
    }
    $layered = $false
    $hadRegion = $null -ne $form.Region
    if ($hadRegion) { $form.Region = $null }
    if (Initialize-DeskLayer) {
        try {
            $badge = Get-LauncherBadgeCount
            $layered = [bool]([DeskLayer]::ShowLauncher($form.Handle, $color.ToArgb(), $form.Left, $form.Top, [bool]$script:PanelOpen, $badge, $icon))
        } catch {
            $layered = $false
        }
    }
    if ($layered) { return }
    if ($hadRegion -and $null -eq $form.Region) {
        $circle = New-Object System.Drawing.Drawing2D.GraphicsPath
        $circle.AddEllipse(0, 0, 52, 52)
        $form.Region = New-Object System.Drawing.Region($circle)
        $circle.Dispose()
    }
    if ($null -eq $form.Region) {
        $circle = New-Object System.Drawing.Drawing2D.GraphicsPath
        $circle.AddEllipse(0, 0, 52, 52)
        $form.Region = New-Object System.Drawing.Region($circle)
        $circle.Dispose()
    }
    $form.Invalidate()
}

function Initialize-DesktopHost {
    if ('DesktopHost' -as [type]) { return $true }
    try {
        Add-Type -TypeDefinition $script:DesktopHostSource -ErrorAction Stop
        return $true
    } catch {
        Write-Log ("Не удалось подготовить вывод виджета на рабочий стол: {0}" -f $_.Exception.Message) 'WARN'
        return $false
    }
}

function Get-WidgetTitle {
    $title = 'Сервисная служба'
    if ($script:Cfg -and -not [string]::IsNullOrWhiteSpace([string]$script:Cfg.WidgetTitle)) {
        $title = [string]$script:Cfg.WidgetTitle
    }
    return $title
}

function Get-WidgetMargin {
    $margin = 16
    if ($script:Cfg) { $margin = [int]$script:Cfg.WidgetMargin }
    if ($margin -lt 0) { return 0 }
    return $margin
}

function Get-ThemeColor {
    param([string]$Name)
    if ($null -eq $script:WidgetPalette) { $script:WidgetPalette = Get-WidgetPalette -Light $true }
    $rgb = $script:WidgetPalette[$Name]
    return [System.Drawing.Color]::FromArgb([int]$rgb[0], [int]$rgb[1], [int]$rgb[2])
}

function Get-LauncherFill {
    param([switch]$Hover)
    $red = 220
    $green = 38
    $blue = 38
    $accent = Get-ThemeColor Accent
    $red = [int]$accent.R
    $green = [int]$accent.G
    $blue = [int]$accent.B
    $hex = ''
    if ($script:Cfg -and $script:Cfg.PSObject.Properties['WidgetColor']) {
        $hex = [string]$script:Cfg.WidgetColor
    }
    if ($hex.Length -eq 7 -and $hex.StartsWith('#')) {
        $red = [Convert]::ToInt32($hex.Substring(1, 2), 16)
        $green = [Convert]::ToInt32($hex.Substring(3, 2), 16)
        $blue = [Convert]::ToInt32($hex.Substring(5, 2), 16)
    }
    $opacity = 100
    if ($script:Cfg -and $script:Cfg.PSObject.Properties['WidgetOpacity']) {
        $opacity = [int]$script:Cfg.WidgetOpacity
    }
    if ($opacity -lt 0) { $opacity = 0 }
    if ($opacity -gt 100) { $opacity = 100 }
    $alpha = [int][Math]::Round(255.0 * $opacity / 100.0)
    if ($Hover) {
        $red = [int][Math]::Round($red * 0.82)
        $green = [int][Math]::Round($green * 0.82)
        $blue = [int][Math]::Round($blue * 0.82)
    }
    return [System.Drawing.Color]::FromArgb($alpha, $red, $green, $blue)
}

function Test-StayOnTop {
    if ($null -eq $script:State) { return $true }
    if ($script:State -is [System.Collections.IDictionary]) {
        if (-not $script:State.Contains('StayOnTop')) { return $true }
        return Resolve-StayOnTop $script:State['StayOnTop']
    }
    return Resolve-StayOnTop $script:State.StayOnTop
}

function Apply-WidgetZOrder {
    $top = Test-StayOnTop
    foreach ($form in @($script:WidgetForm, $script:PanelForm, $script:NewsPopup, $script:ListPopup)) {
        if ($null -eq $form -or $form.IsDisposed) { continue }
        $form.TopMost = $top
    }
}

function Test-LeftMousePress {
    param($EventArgs)
    if ($null -eq $EventArgs) { return $true }
    $button = $null
    try { $button = $EventArgs.Button } catch { return $true }
    if ($null -eq $button) { return $true }
    return [bool]($button -eq [System.Windows.Forms.MouseButtons]::Left)
}

function Attach-LauncherClickHook {
    param($Form)
    if ($null -eq $Form -or $Form.IsDisposed -or -not $Form.IsHandleCreated) { return }
    if (-not (Initialize-DeskLayer)) { return }
    if (-not ('DeskClickWindow' -as [type])) { return }
    $hook = $script:LauncherClickHook
    if ($null -ne $hook) {
        try { $hook.ReleaseHandle() } catch { }
    }
    $hook = New-Object DeskClickWindow
    $hook.AssignHandle($Form.Handle)
    $script:LauncherClickHook = $hook
}

function Invoke-WindowChrome {
    param($Form, [switch]$Launcher)
    if ($null -eq $Form -or $Form.IsDisposed) { return }
    if (-not $Form.IsHandleCreated) { [void]$Form.Handle }
    if ('DesktopHost' -as [type]) {
        try {
            if ($Launcher) { [DesktopHost]::PrepareLauncher($Form.Handle) }
            else { [DesktopHost]::PreparePanel($Form.Handle) }
        } catch { }
    }
    if ($Launcher) { Attach-LauncherClickHook $Form }
}

function Enable-ControlBuffer {
    param($Control)
    if ($null -eq $Control) { return }
    try {
        $flags = [System.Reflection.BindingFlags]'Instance,NonPublic'
        $prop = $Control.GetType().GetProperty('DoubleBuffered', $flags)
        if ($null -ne $prop) { $prop.SetValue($Control, $true, $null) }
    } catch { }
}

function Read-AppThemeLight {
    $value = $null
    try {
        $item = Get-ItemProperty -Path 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize' -Name 'AppsUseLightTheme' -ErrorAction Stop
        $value = $item.AppsUseLightTheme
    } catch { }
    return Resolve-AppThemeLight $value
}

function Enable-AppThemeMode {
    # Цвета читаются из реестра и рисуются самим окном.
    # Не вызываем недокументированные функции uxtheme: на части сборок Windows это закрывает процесс до появления кнопки.
    return
}

function New-UiFont {
    param([string]$Family, [float]$Size, [System.Drawing.FontStyle]$Style = 'Regular')
    try {
        return New-Object System.Drawing.Font($Family, $Size, $Style)
    } catch {
        return New-Object System.Drawing.Font('Segoe UI', $Size, $Style)
    }
}

function Test-ShowLauncher {
    if ($null -eq $script:State) { return $true }
    return Resolve-ShowLauncher $script:State.ShowLauncher
}

function Get-WidgetCorner {
    $corner = 'BottomRight'
    if ($script:Cfg -and -not [string]::IsNullOrWhiteSpace([string]$script:Cfg.WidgetCorner)) {
        $corner = [string]$script:Cfg.WidgetCorner
    }
    return $corner
}

function Get-SupportStatus {
    $mode = [string]$script:DesktopMode
    $verdict = [string]$script:DesktopVerdict
    $text = 'Проверка сети'
    $color = Get-ThemeColor StatusMuted
    if ($mode -eq 'Local') {
        $text = 'Локальный стол'
        $color = Get-ThemeColor StatusLocal
    } elseif ($mode -eq 'Network') {
        $text = 'Сетевой стол'
        if ($verdict -eq 'Online') { $color = Get-ThemeColor StatusOnline }
    }
    return [pscustomobject]@{ Text = $text; Color = $color }
}

function Update-SoftFieldTheme {
    param($Field, [bool]$ReadOnly)
    if ($null -eq $Field) { return }
    $canvas = Get-ThemeColor Canvas
    $fill = Get-ThemeColor FieldFill
    if ($ReadOnly) { $fill = Get-ThemeColor FieldReadOnly }
    $ink = Get-ThemeColor Ink
    $icon = Get-ThemeColor Icon
    $Field.Shell.BackColor = $canvas
    $Field.Fill.BackColor = $canvas
    $Field.Icon.BackColor = $fill
    $Field.Icon.ForeColor = $icon
    if ($Field.Editor -is [System.Windows.Forms.Control]) {
        $Field.Editor.BackColor = $fill
        $Field.Editor.ForeColor = $ink
    }
    $valueLabel = $null
    $chevron = $null
    if ($Field -is [System.Collections.IDictionary]) {
        if ($Field.ContainsKey('ValueLabel')) { $valueLabel = $Field['ValueLabel'] }
        if ($Field.ContainsKey('Chevron')) { $chevron = $Field['Chevron'] }
    }
    if ($null -ne $valueLabel) {
        $valueLabel.BackColor = $fill
        $valueLabel.ForeColor = $ink
    }
    if ($null -ne $chevron) {
        $chevron.BackColor = $fill
        $chevron.ForeColor = $icon
    }
    foreach ($child in @($Field.Fill.Controls)) {
        if ($child.Tag -eq 'cue') {
            $child.BackColor = $fill
            $child.ForeColor = $icon
        }
    }
    $Field.Fill.Invalidate()
}

function Update-TrayIconImage {
    if ($null -eq $script:TrayIcon) { return }
    $fresh = $null
    $owned = $false
    if (Initialize-DeskLayer) {
        try {
            $accent = Get-LauncherFill
            $color = [System.Drawing.Color]::FromArgb(255, [int]$accent.R, [int]$accent.G, [int]$accent.B)
            $fresh = [DeskLayer]::MakeChatIcon($color.ToArgb())
            $owned = $null -ne $fresh
        } catch {
            $fresh = $null
            $owned = $false
        }
    }
    if ($null -eq $fresh) {
        $fresh = [System.Drawing.SystemIcons]::Application
        $owned = $false
    }
    $previous = $script:TrayIcon.Icon
    $previousOwned = [bool]$script:TrayIconOwned
    $script:TrayIcon.Icon = $fresh
    $script:TrayIconOwned = $owned
    if ($previousOwned -and $null -ne $previous) {
        try { [DeskLayer]::DestroyIcon($previous.Handle) } catch { }
        try { $previous.Dispose() } catch { }
    }
}

function Apply-TrayMenuPalette {
    if ($null -eq $script:TrayMenu) { return }
    $canvas = Get-ThemeColor Canvas
    $ink = Get-ThemeColor Ink
    $hover = Get-ThemeColor Hover
    $rule = Get-ThemeColor Rule
    $accent = Get-ThemeColor Accent
    $script:TrayMenu.BackColor = $canvas
    $script:TrayMenu.ForeColor = $ink
    $script:TrayMenu.ShowImageMargin = $false
    $script:TrayMenu.ShowCheckMargin = $true
    if (-not (Initialize-DeskLayer)) {
        foreach ($item in @($script:TrayMenu.Items)) {
            if ($item -is [System.Windows.Forms.ToolStripSeparator]) { continue }
            $item.ForeColor = $ink
        }
        Update-TrayIconImage
        return
    }
    if ('DeskMenuColors' -as [type]) {
        $colors = $script:TrayMenuColors
        if ($null -eq $colors) {
            $colors = New-Object DeskMenuColors
            $script:TrayMenuColors = $colors
        }
        $colors.Canvas = $canvas
        $colors.Ink = $ink
        $colors.Hover = $hover
        $colors.Rule = $rule
        $colors.Accent = $accent
        $hasRenderer = $false
        if ('DeskMenuRenderer' -as [type]) {
            $hasRenderer = $script:TrayMenu.Renderer -is [DeskMenuRenderer]
        }
        if (-not $hasRenderer -and ('DeskMenuRenderer' -as [type])) {
            $script:TrayMenu.Renderer = New-Object DeskMenuRenderer($colors)
        }
    }
    foreach ($item in @($script:TrayMenu.Items)) {
        if ($item -is [System.Windows.Forms.ToolStripSeparator]) { continue }
        $item.ForeColor = $ink
    }
    try { $script:TrayMenu.Invalidate() } catch { }
    Update-TrayIconImage
}

function Apply-NewsPopupPalette {
    if ($null -eq $script:NewsPopup -or $script:NewsPopup.IsDisposed) { return }
    $canvas = Get-ThemeColor Canvas
    $ink = Get-ThemeColor Ink
    $muted = Get-ThemeColor Muted
    $rule = Get-ThemeColor Rule
    $script:NewsPopup.BackColor = $canvas
    if ($script:NewsPopupHeader) { $script:NewsPopupHeader.BackColor = $canvas }
    if ($script:NewsPopupTitle) {
        $script:NewsPopupTitle.ForeColor = $ink
        $script:NewsPopupTitle.BackColor = $canvas
    }
    if ($script:NewsPopupClose) {
        $script:NewsPopupClose.BackColor = $canvas
        $script:NewsPopupClose.ForeColor = $muted
    }
    if ($script:NewsPopupRule) { $script:NewsPopupRule.BackColor = $rule }
    if ($script:NewsPopupBody) { $script:NewsPopupBody.BackColor = $canvas }
    if ($script:NewsPopup.Visible -and $script:PopupNotices) {
        Show-NewsPopup -Notices $script:PopupNotices
    }
}

function Apply-WidgetPalette {
    if ($null -eq $script:WidgetUi) { return }
    $ui = $script:WidgetUi
    $canvas = Get-ThemeColor Canvas
    $ink = Get-ThemeColor Ink
    $muted = Get-ThemeColor Muted
    $label = Get-ThemeColor Label
    $hover = Get-ThemeColor Hover
    $rule = Get-ThemeColor Rule
    $accent = Get-ThemeColor Accent
    if ($script:PanelForm -and -not $script:PanelForm.IsDisposed) { $script:PanelForm.BackColor = $canvas }
    $ui.Header.BackColor = $canvas
    $ui.TitleLabel.ForeColor = $ink
    $ui.TitleLabel.BackColor = $canvas
    $ui.Identity.ForeColor = $muted
    $ui.Identity.BackColor = $canvas
    $ui.Status.BackColor = $canvas
    $ui.CloseButton.BackColor = $canvas
    $ui.CloseButton.ForeColor = $muted
    if ($ui.CloseButton -is [System.Windows.Forms.Button]) {
        $ui.CloseButton.FlatAppearance.MouseOverBackColor = $hover
    }
    $ui.CloseButton.Invalidate()
    if ($ui.ContainsKey('Mark') -and $null -ne $ui.Mark) {
        $ui.Mark.BackColor = $canvas
        $ui.Mark.Invalidate()
    }
    $ui.HeaderRule.BackColor = $rule
    $ui.Sheet.BackColor = $canvas
    $ui.TicketTab.BackColor = $canvas
    $ui.NewsTab.BackColor = $canvas
    $ui.TicketTab.FlatAppearance.MouseOverBackColor = $hover
    $ui.NewsTab.FlatAppearance.MouseOverBackColor = $hover
    $ui.TabLine.BackColor = $accent
    $ui.NewsPage.BackColor = $canvas
    $ui.TicketPage.BackColor = $canvas
    $ui.NewsList.BackColor = $canvas
    foreach ($name in @('LoginLabel', 'ComputerLabel', 'ProjectLabel', 'CategoryLabel', 'SubjectLabel', 'BodyLabel')) {
        $ui[$name].ForeColor = $label
        $ui[$name].BackColor = $canvas
    }
    $ui.TicketStatus.BackColor = $canvas
    $ui.PortalLink.BackColor = $canvas
    $ui.PortalLink.LinkColor = $accent
    $ui.PortalLink.ActiveLinkColor = $accent
    $ui.SendButton.BackColor = $canvas
    if ($ui.SendButton -is [System.Windows.Forms.Button]) {
        $ui.SendButton.FlatAppearance.MouseOverBackColor = (Get-ThemeColor AccentHover)
    }
    $ui.SendButton.Invalidate()
    Update-SoftFieldTheme $ui.LoginField $true
    Update-SoftFieldTheme $ui.ComputerField $true
    Update-SoftFieldTheme $ui.ProjectField $false
    Update-SoftFieldTheme $ui.CategoryField $false
    Update-SoftFieldTheme $ui.SubjectField $false
    Update-SoftFieldTheme $ui.BodyField $false
    Apply-SupportPageVisual -Page $script:WidgetPage
    Update-NewsRows
    $script:NewsSignature = Get-NewsSignature
    Apply-NewsPopupPalette
    Apply-TrayMenuPalette
    if ($script:WidgetForm -and -not $script:WidgetForm.IsDisposed) { Update-LauncherSurface }
}

function Sync-WidgetTheme {
    param([switch]$Force)
    if ($script:ApplyingTheme) { return }
    $light = Read-AppThemeLight
    if (-not $Force -and $null -ne $script:WidgetPalette -and [bool]$script:AppThemeLight -eq [bool]$light) { return }
    $script:AppThemeLight = $light
    $script:WidgetPalette = Get-WidgetPalette -Light $light
    $script:ApplyingTheme = $true
    try { Apply-WidgetPalette } finally { $script:ApplyingTheme = $false }
}

function Register-ThemeChanges {
    if ($script:ThemeHooked) { return }
    $script:ThemeHandler = {
        try {
            $form = $script:WidgetForm
            if ($null -eq $form -or $form.IsDisposed -or -not $form.IsHandleCreated) { return }
            $form.BeginInvoke([System.Action]{ Sync-WidgetTheme }) | Out-Null
        } catch { }
    }
    try {
        [Microsoft.Win32.SystemEvents]::add_UserPreferenceChanged($script:ThemeHandler)
        $script:ThemeHooked = $true
    } catch { }
}

function Unregister-ThemeChanges {
    if (-not $script:ThemeHooked) { return }
    try { [Microsoft.Win32.SystemEvents]::remove_UserPreferenceChanged($script:ThemeHandler) } catch { }
    $script:ThemeHooked = $false
}

function Set-LauncherChrome {
    $show = Test-ShowLauncher
    if ($script:LauncherMenuItem) { $script:LauncherMenuItem.Checked = $show }
    $launcher = $script:WidgetForm
    if ($null -eq $launcher -or $launcher.IsDisposed) { return }
    if (-not $show) {
        if ($script:PanelForm -and -not $script:PanelForm.IsDisposed -and $script:PanelForm.Owner -eq $launcher) {
            $script:PanelForm.Owner = $null
        }
        if ($script:NewsPopup -and -not $script:NewsPopup.IsDisposed -and $script:NewsPopup.Owner -eq $launcher) {
            $script:NewsPopup.Owner = $null
        }
        if ($launcher.Visible) { $launcher.Hide() }
        return
    }
    if (-not $launcher.Visible) { $launcher.Show() }
    if ($script:PanelForm -and -not $script:PanelForm.IsDisposed) { $script:PanelForm.Owner = $launcher }
    if ($script:NewsPopup -and -not $script:NewsPopup.IsDisposed) { $script:NewsPopup.Owner = $launcher }
    if ('DesktopHost' -as [type] -and $launcher.IsHandleCreated) {
        try { [DesktopHost]::PrepareLauncher($launcher.Handle) } catch { }
    }
    Update-LauncherSurface
}

function Format-NoticeStamp {
    param([string]$Value)
    if ([string]::IsNullOrWhiteSpace($Value)) { return '' }
    $when = [datetime]::MinValue
    $parsed = [datetime]::TryParse($Value, [System.Globalization.CultureInfo]::InvariantCulture, [System.Globalization.DateTimeStyles]::RoundtripKind, [ref]$when)
    if (-not $parsed) { $parsed = [datetime]::TryParse($Value, [ref]$when) }
    if (-not $parsed) { return '' }
    $months = @('января', 'февраля', 'марта', 'апреля', 'мая', 'июня', 'июля', 'августа', 'сентября', 'октября', 'ноября', 'декабря')
    return ('{0} {1}, {2:HH:mm}' -f $when.Day, $months[$when.Month - 1], $when)
}

function Get-NoticeSnippet {
    param([string]$Text)
    if ([string]::IsNullOrWhiteSpace($Text)) { return '' }
    $plain = ([regex]::Replace($Text, '\s+', ' ')).Trim()
    if ($plain.Length -gt 110) { return $plain.Substring(0, 107) + '...' }
    return $plain
}

function Get-NewsSignature {
    $parts = New-Object System.Collections.Generic.List[string]
    foreach ($item in @($script:NewsItems)) {
        if ($null -eq $item) { continue }
        $parts.Add(([string]$item.Id) + '|' + ([string]$item.Kind) + '|' + ([string]$item.Title))
    }
    $pin = New-Object System.Collections.Generic.List[string]
    foreach ($key in @($script:NewsPinnedIds.Keys)) { $pin.Add([string]$key) }
    $parts.Add('pin=' + (($pin.ToArray() | Sort-Object) -join ','))
    return [string]::Join("`n", $parts.ToArray())
}

function Import-NoticeLog {
    $existing = @()
    if ($script:State) { $existing = $script:State.NoticeLog }
    $log = Merge-NoticeLog -Existing $existing -Incoming @() -Now (Get-Date)
    if ($script:State) { $script:State.NoticeLog = $log }
    $script:NewsItems = (ConvertTo-NoticeLogItems $log).ToArray()
}

function Import-ReadNoticeIds {
    if ($script:ReadNoticesImported) { return }
    $script:ReadNoticesImported = $true
    if (-not $script:State) { return }
    foreach ($id in (ConvertTo-IdList $script:State.ReadNoticeIds)) {
        $script:ReadNoticeIds[$id] = $true
        $script:OpenedNoticeIds[$id] = $true
    }
    foreach ($id in (ConvertTo-IdList $script:State.SeenNoticeIds)) {
        $script:ReadNoticeIds[$id] = $true
        $script:OpenedNoticeIds[$id] = $true
    }
}

function Save-ReadNoticeIds {
    if (-not $script:State) { return }
    $ids = New-Object System.Collections.Generic.List[string]
    foreach ($key in @($script:ReadNoticeIds.Keys)) {
        $text = [string]$key
        if (-not [string]::IsNullOrWhiteSpace($text)) { $ids.Add($text) }
    }
    if ($ids.Count -gt 200) { $ids = $ids.GetRange($ids.Count - 200, 200) }
    $script:State.ReadNoticeIds = $ids.ToArray()
    $script:State.SeenNoticeIds = Merge-NoticeIds -Existing $script:State.SeenNoticeIds -More $script:State.ReadNoticeIds
    Save-StateTable $script:State
}

function Get-LauncherBadgeCount {
    if ($script:PanelOpen) { return 0 }
    if ($script:NewsPopup -and -not $script:NewsPopup.IsDisposed -and $script:NewsPopup.Visible) { return 0 }
    try { return [int](Get-UnopenedNoticeCount) } catch { return 0 }
}

function Get-UnopenedNoticeCount {
    Import-ReadNoticeIds
    $count = 0
    foreach ($item in @($script:NewsItems)) {
        if ($null -eq $item) { continue }
        $id = [string]$item.Id
        if ([string]::IsNullOrWhiteSpace($id)) { continue }
        if ($script:OpenedNoticeIds.ContainsKey($id)) { continue }
        $count++
    }
    return $count
}

function Mark-NoticesOpened {
    Import-ReadNoticeIds
    $ids = New-Object System.Collections.Generic.List[string]
    foreach ($item in @($script:NewsItems)) {
        if ($null -eq $item) { continue }
        $id = (Get-NoticeField $item 'Id').Trim()
        if ([string]::IsNullOrWhiteSpace($id)) { continue }
        $script:OpenedNoticeIds[$id] = $true
        $ids.Add($id)
    }
    if ($ids.Count -gt 0 -and $script:State) {
        $script:State.SeenNoticeIds = Merge-NoticeIds -Existing $script:State.SeenNoticeIds -More $ids.ToArray()
        Save-StateTable $script:State
    }
}

function Test-NoticeLinkEnabled {
    param([string]$Url)
    if ([string]::IsNullOrWhiteSpace($Url)) { return $false }
    if ($script:Cfg) {
        $root = Get-JiraApiRoot ([string]$script:Cfg.JiraBaseUrl)
        if (-not [string]::IsNullOrWhiteSpace($root) -and $Url.StartsWith($root)) { return $false }
    }
    return $true
}

function Enter-NewsReading {
    if ($script:NewsReading) { return }
    $script:NewsReading = $true
    Mark-NoticesOpened
    $script:NewsSignature = $null
    Update-NewsRows
    Update-LauncherSurface
}

function Leave-NewsReading {
    $script:NewsReading = $false
}

function Set-SupportBounds {
    Add-Type -AssemblyName System.Windows.Forms
    $screen = [System.Windows.Forms.Screen]::PrimaryScreen.WorkingArea
    $margin = Get-WidgetMargin
    $corner = Get-WidgetCorner
    $button = 52
    $panelW = [int]$script:SupportPanelWidth
    $panelH = [int]$script:SupportPanelHeight
    $gap = 12
    $x = $screen.Left + $margin
    $y = $screen.Top + $margin
    if ($corner -eq 'BottomRight' -or $corner -eq 'TopRight') { $x = $screen.Right - $button - $margin }
    if ($corner -eq 'BottomRight' -or $corner -eq 'BottomLeft') { $y = $screen.Bottom - $button - $margin }
    if ($script:WidgetForm -and -not $script:WidgetForm.IsDisposed) {
        $script:WidgetForm.Location = New-Object System.Drawing.Point($x, $y)
        if (-not $script:CornerLogged) {
            $script:CornerLogged = $true
            Write-Log ("Кнопка: угол {0}, точка {1},{2}." -f $corner, $x, $y)
        }
    }
    $px = $x + $button - $panelW
    $py = $y - $gap - $panelH
    if ($corner -eq 'BottomLeft' -or $corner -eq 'TopLeft') { $px = $x }
    if ($corner -eq 'TopLeft' -or $corner -eq 'TopRight') { $py = $y + $button + $gap }
    if ($px -lt ($screen.Left + 8)) { $px = $screen.Left + 8 }
    if (($px + $panelW) -gt ($screen.Right - 8)) { $px = $screen.Right - $panelW - 8 }
    if ($py -lt ($screen.Top + 8)) { $py = $screen.Top + 8 }
    if (($py + $panelH) -gt ($screen.Bottom - 8)) { $py = $screen.Bottom - $panelH - 8 }
    if ($script:PanelForm -and -not $script:PanelForm.IsDisposed) {
        $script:PanelForm.Location = New-Object System.Drawing.Point($px, $py)
    }
    Set-NewsPopupBounds
}

function New-RoundedPath {
    param([int]$Width, [int]$Height, [int]$Radius)
    $path = New-Object System.Drawing.Drawing2D.GraphicsPath
    $diameter = $Radius * 2
    if ($diameter -gt $Width) { $diameter = $Width }
    if ($diameter -gt $Height) { $diameter = $Height }
    $right = $Width - $diameter
    $bottom = $Height - $diameter
    $path.AddArc(0, 0, $diameter, $diameter, 180, 90)
    $path.AddArc($right, 0, $diameter, $diameter, 270, 90)
    $path.AddArc($right, $bottom, $diameter, $diameter, 0, 90)
    $path.AddArc(0, $bottom, $diameter, $diameter, 90, 90)
    $path.CloseFigure()
    return $path
}

function New-SendGlyph {
    $bmp = New-Object System.Drawing.Bitmap 16, 16
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
    $g.Clear([System.Drawing.Color]::Transparent)
    $brush = New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::White)
    $points = New-Object System.Drawing.Point[] 4
    $points[0] = New-Object System.Drawing.Point(1, 7)
    $points[1] = New-Object System.Drawing.Point(15, 1)
    $points[2] = New-Object System.Drawing.Point(8, 15)
    $points[3] = New-Object System.Drawing.Point(7, 8)
    $g.FillPolygon($brush, $points)
    $brush.Dispose()
    $g.Dispose()
    return $bmp
}

function Update-FlatButtonRegion {
    param($Button)
    if ($null -eq $Button) { return }
    $Button.Invalidate()
}

function New-FlatButton {
    param([string]$Text, [System.Drawing.Point]$Location, [System.Drawing.Size]$Size)
    $button = New-Object System.Windows.Forms.Panel
    $button.Text = $Text
    $button.Location = $Location
    $button.Size = $Size
    $button.BackColor = Get-ThemeColor Canvas
    $button.ForeColor = [System.Drawing.Color]::White
    $button.Font = $script:ButtonFont
    $button.Cursor = [System.Windows.Forms.Cursors]::Hand
    $button.Add_MouseEnter({ $script:SendHot = $true; $this.Invalidate() })
    $button.Add_MouseLeave({ $script:SendHot = $false; $this.Invalidate() })
    $button.Add_TextChanged({ $this.Invalidate() })
    $button.Add_EnabledChanged({ $this.Invalidate() })
    $button.Add_Paint({
        $box = $this
        $g = $_.Graphics
        $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
        $g.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality
        $g.TextRenderingHint = [System.Drawing.Text.TextRenderingHint]::ClearTypeGridFit
        $g.Clear($box.BackColor)
        $w = $box.Width - 2
        $h = $box.Height - 2
        if ($w -lt 4 -or $h -lt 4) { return }
        $path = New-RoundedPath -Width $w -Height $h -Radius 12
        $g.TranslateTransform(1, 1)
        $fill = Get-ThemeColor Accent
        $ink = [System.Drawing.Color]::White
        if (-not $box.Enabled) {
            $fill = Get-ThemeColor FieldBorder
            $ink = Get-ThemeColor Muted
        } elseif ($script:SendHot) {
            $fill = Get-ThemeColor AccentHover
        }
        $brush = New-Object System.Drawing.SolidBrush $fill
        $g.FillPath($brush, $path)
        $brush.Dispose()
        $path.Dispose()
        $g.ResetTransform()
        $font = $box.Font
        $label = [string]$box.Text
        $flags = [System.Windows.Forms.TextFormatFlags]::NoPadding -bor [System.Windows.Forms.TextFormatFlags]::SingleLine -bor [System.Windows.Forms.TextFormatFlags]::VerticalCenter
        $measured = [System.Windows.Forms.TextRenderer]::MeasureText($g, $label, $font, (New-Object System.Drawing.Size(1000, $box.Height)), $flags)
        $icon = 14
        $gap = 8
        $total = $icon + $gap + $measured.Width
        $x = [int](($box.Width - $total) / 2)
        if ($x -lt 8) { $x = 8 }
        $mid = $box.Height / 2
        $textBrush = New-Object System.Drawing.SolidBrush $ink
        $ox = $x
        $oy = $mid - 6
        $points = New-Object System.Drawing.PointF[] 4
        $points[0] = New-Object System.Drawing.PointF(($ox + 0.5), ($oy + 6))
        $points[1] = New-Object System.Drawing.PointF(($ox + 13.5), ($oy + 0.5))
        $points[2] = New-Object System.Drawing.PointF(($ox + 7.5), ($oy + 12.5))
        $points[3] = New-Object System.Drawing.PointF(($ox + 6), ($oy + 7))
        $g.FillPolygon($textBrush, $points)
        $textBrush.Dispose()
        $textRect = New-Object System.Drawing.Rectangle(($x + $icon + $gap), 0, ($measured.Width + 4), $box.Height)
        [System.Windows.Forms.TextRenderer]::DrawText($g, $label, $font, $textRect, $ink, $flags)
    })
    return $button
}

function Update-SoftFieldSize {
    param($Field, [int]$Width, [int]$Height)
    if ($null -eq $Field) { return }
    $shell = $Field.Shell
    $fill = $Field.Fill
    $editor = $Field.Editor
    $icon = $Field.Icon
    $shell.Size = New-Object System.Drawing.Size($Width, $Height)
    $shell.Region = $null
    $fill.SetBounds(0, 0, $Width, $Height)
    $fill.Region = $null
    if ($null -ne $icon) { $icon.SetBounds(10, 4, 28, ($Height - 8)) }
    if ($editor -is [System.Windows.Forms.TextBox] -and $editor.Multiline) {
        $editor.SetBounds(40, 10, ($Width - 56), ($Height - 20))
    }
    $fill.Invalidate()
}

function Initialize-SoftListType {
    if ('DeskSoftList' -as [type]) { return }
    $source = @'
using System;

public sealed class DeskSoftItems {
    object[] data = new object[0];
    public event EventHandler Changed;
    public int Count { get { return data.Length; } }
    public object this[int index] { get { return data[index]; } }
    public void Clear() {
        data = new object[0];
        if (Changed != null) Changed(this, EventArgs.Empty);
    }
    public void Add(object item) {
        object[] next = new object[data.Length + 1];
        for (int i = 0; i < data.Length; i++) next[i] = data[i];
        next[data.Length] = item;
        data = next;
        if (Changed != null) Changed(this, EventArgs.Empty);
    }
}

public sealed class DeskSoftList {
    public DeskSoftItems Items;
    int index = -1;
    public bool Enabled;
    public event EventHandler SelectedIndexChanged;
    public event EventHandler ItemsChanged;
    public DeskSoftList() {
        Enabled = true;
        Items = new DeskSoftItems();
        Items.Changed += OnItemsChanged;
    }
    void OnItemsChanged(object sender, EventArgs e) {
        if (Items.Count == 0) {
            if (index != -1) {
                index = -1;
                if (SelectedIndexChanged != null) SelectedIndexChanged(this, EventArgs.Empty);
            }
        } else if (index >= Items.Count) {
            index = Items.Count - 1;
            if (SelectedIndexChanged != null) SelectedIndexChanged(this, EventArgs.Empty);
        }
        if (ItemsChanged != null) ItemsChanged(this, EventArgs.Empty);
    }
    public int SelectedIndex {
        get { return index; }
        set {
            if (value < -1) value = -1;
            if (Items.Count == 0) value = -1;
            else if (value >= Items.Count) value = Items.Count - 1;
            if (value == index) {
                if (ItemsChanged != null) ItemsChanged(this, EventArgs.Empty);
                return;
            }
            index = value;
            if (SelectedIndexChanged != null) SelectedIndexChanged(this, EventArgs.Empty);
            if (ItemsChanged != null) ItemsChanged(this, EventArgs.Empty);
        }
    }
    public object SelectedItem {
        get {
            if (index < 0 || index >= Items.Count) return null;
            return Items[index];
        }
    }
}
'@
    Add-Type -TypeDefinition $source -ErrorAction Stop
}

function Close-SoftListPopup {
    if ($script:ListPopupClosing) { return }
    $popup = $script:ListPopup
    if ($null -eq $popup -or $popup.IsDisposed) {
        $script:ListPopup = $null
        $script:SoftListSource = $null
        return
    }
    $script:ListPopupClosing = $true
    $script:ListPopupReady = $false
    try { $popup.Close() } catch { }
    finally {
        $script:ListPopupClosing = $false
        $script:ListPopup = $null
        $script:SoftListSource = $null
        $script:ListRows = @()
        $script:ListScroll = 0
    }
}

function Update-SoftListRows {
    $list = $script:SoftListSource
    $rows = @($script:ListRows)
    if ($null -eq $list -or $rows.Count -eq 0) { return }
    $count = $list.Items.Count
    $max = [int]$script:ListMaxRows
    if ($max -lt 1) { $max = $rows.Count }
    $maxScroll = $count - $max
    if ($maxScroll -lt 0) { $maxScroll = 0 }
    if ($script:ListScroll -lt 0) { $script:ListScroll = 0 }
    if ($script:ListScroll -gt $maxScroll) { $script:ListScroll = $maxScroll }
    $pad = [int]$script:ListPad
    $rowH = [int]$script:ListRowH
    $popupW = 0
    if ($script:ListPopup -and -not $script:ListPopup.IsDisposed) { $popupW = $script:ListPopup.ClientSize.Width }
    for ($i = 0; $i -lt $rows.Count; $i++) {
        $row = $rows[$i]
        $index = $script:ListScroll + $i
        if ($index -ge $count) {
            $row.Visible = $false
            continue
        }
        $row.Visible = $true
        $row.Text = [string]$list.Items[$index]
        $row.Tag = $index
        $row.SetBounds(8, ($pad + ($i * $rowH) + 2), ($popupW - 20), ($rowH - 4))
        if ($index -eq $list.SelectedIndex) {
            $row.BackColor = Get-ThemeColor Selection
            $row.ForeColor = Get-ThemeColor Ink
        } else {
            $row.BackColor = Get-ThemeColor FieldFill
            $row.ForeColor = Get-ThemeColor Ink
        }
    }
    if ($script:ListPopup -and -not $script:ListPopup.IsDisposed) { $script:ListPopup.Invalidate() }
}

function Move-SoftListScroll {
    param([int]$Delta)
    $script:ListScroll = [int]$script:ListScroll + $Delta
    Update-SoftListRows
}

function Show-SoftListPopup {
    param($List, $Anchor)
    if ($null -eq $List -or -not $List.Enabled) { return }
    if ($List.Items.Count -eq 0) { return }
    Close-SoftListPopup
    $rowH = 34
    $pad = 8
    $count = $List.Items.Count
    $anchorTop = $Anchor.PointToScreen((New-Object System.Drawing.Point(0, 0)))
    $anchorBottom = $Anchor.PointToScreen((New-Object System.Drawing.Point(0, $Anchor.Height)))
    $screen = [System.Windows.Forms.Screen]::FromControl($Anchor).WorkingArea
    $limitTop = $screen.Top + 8
    $limitBottom = $screen.Bottom - 8
    if ($script:PanelForm -and -not $script:PanelForm.IsDisposed) {
        if ($script:PanelForm.Top -gt $limitTop) { $limitTop = $script:PanelForm.Top + 12 }
        if ($script:PanelForm.Bottom -lt $limitBottom) { $limitBottom = $script:PanelForm.Bottom - 12 }
    }
    $spaceBelow = $limitBottom - $anchorBottom.Y - 6
    $spaceAbove = $anchorTop.Y - 6 - $limitTop
    $room = $spaceBelow
    if ($spaceAbove -gt $room) { $room = $spaceAbove }
    $maxRows = [int][Math]::Floor(($room - ($pad * 2)) / $rowH)
    if ($maxRows -lt 3) { $maxRows = 3 }
    if ($maxRows -gt 7) { $maxRows = 7 }
    if ($maxRows -gt $count) { $maxRows = $count }
    $popupW = $Anchor.Width
    $popupH = ($pad * 2) + ($maxRows * $rowH)
    $openUp = ($spaceBelow -lt $popupH) -and ($spaceAbove -ge $spaceBelow)
    $originX = $anchorTop.X
    if ($openUp) { $originY = $anchorTop.Y - 6 - $popupH }
    else { $originY = $anchorBottom.Y + 6 }
    if ($originY -lt $limitTop) { $originY = $limitTop }
    if (($originY + $popupH) -gt $limitBottom) { $originY = $limitBottom - $popupH }
    $form = New-Object System.Windows.Forms.Form
    $form.FormBorderStyle = 'None'
    $form.ShowInTaskbar = $false
    $form.StartPosition = 'Manual'
    $form.TopMost = Test-StayOnTop
    $form.BackColor = Get-ThemeColor FieldFill
    $form.ClientSize = New-Object System.Drawing.Size($popupW, $popupH)
    $form.Region = New-Object System.Drawing.Region((New-RoundedPath -Width $popupW -Height $popupH -Radius 12))
    $form.Location = New-Object System.Drawing.Point($originX, $originY)
    $script:SoftListSource = $List
    $script:ListScroll = 0
    if ($List.SelectedIndex -gt ($maxRows - 1)) { $script:ListScroll = $List.SelectedIndex - 1 }
    $script:ListMaxRows = $maxRows
    $script:ListRowH = $rowH
    $script:ListPad = $pad
    $script:ListRows = @()
    $wheel = { Move-SoftListScroll -Delta (-1 * [int]($_.Delta / 120)) }
    for ($i = 0; $i -lt $maxRows; $i++) {
        $row = New-Object System.Windows.Forms.Label
        $row.Font = $script:FieldFont
        $row.AutoEllipsis = $true
        $row.TextAlign = 'MiddleLeft'
        $row.Cursor = [System.Windows.Forms.Cursors]::Hand
        $row.Padding = New-Object System.Windows.Forms.Padding(10, 0, 8, 0)
        $row.Add_Click({
            $source = $script:SoftListSource
            if ($null -ne $source) { $source.SelectedIndex = [int]$this.Tag }
            Close-SoftListPopup
        })
        $row.Add_MouseEnter({
            $source = $script:SoftListSource
            if ($null -eq $source) { return }
            if ([int]$this.Tag -eq $source.SelectedIndex) { return }
            $this.BackColor = Get-ThemeColor Hover
        })
        $row.Add_MouseLeave({ Update-SoftListRows })
        $row.Add_MouseWheel($wheel)
        $form.Controls.Add($row)
        $script:ListRows += $row
    }
    $form.Add_MouseWheel($wheel)
    $form.Add_Paint({
        $list = $script:SoftListSource
        if ($null -eq $list) { return }
        $count = $list.Items.Count
        $max = [int]$script:ListMaxRows
        if ($count -le $max -or $max -lt 1) { return }
        $g = $_.Graphics
        $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
        $thumbH = [int](($this.Height - 16) * $max / $count)
        if ($thumbH -lt 16) { $thumbH = 16 }
        $maxScroll = $count - $max
        if ($maxScroll -lt 1) { return }
        $travel = $this.Height - 16 - $thumbH
        $y = 8 + [int]($travel * $script:ListScroll / $maxScroll)
        $brush = New-Object System.Drawing.SolidBrush (Get-ThemeColor Icon)
        $g.FillRectangle($brush, ($this.Width - 7), $y, 3, $thumbH)
        $brush.Dispose()
    })
    $form.Add_Shown({ $script:ListPopupReady = $true })
    $form.Add_Deactivate({
        if (-not $script:ListPopupReady) { return }
        Close-SoftListPopup
    })
    $form.Add_KeyDown({
        if ($_.KeyCode -eq [System.Windows.Forms.Keys]::Escape) { Close-SoftListPopup }
        elseif ($_.KeyCode -eq [System.Windows.Forms.Keys]::Down) { Move-SoftListScroll 1 }
        elseif ($_.KeyCode -eq [System.Windows.Forms.Keys]::Up) { Move-SoftListScroll -1 }
    })
    $form.KeyPreview = $true
    if ($script:PanelForm -and -not $script:PanelForm.IsDisposed) { $form.Owner = $script:PanelForm }
    $script:ListPopupReady = $false
    $script:ListPopup = $form
    Update-SoftListRows
    $form.Show()
}

function New-SoftField {
    param(
        [string]$Kind,
        [string]$Icon,
        [switch]$ReadOnly,
        [int]$Width = 328,
        [int]$Height = 40
    )
    $fillColor = Get-ThemeColor FieldFill
    if ($ReadOnly) { $fillColor = Get-ThemeColor FieldReadOnly }
    $iconColor = Get-ThemeColor Icon
    $ink = Get-ThemeColor Ink
    $shell = New-Object System.Windows.Forms.Panel
    $shell.Size = New-Object System.Drawing.Size($Width, $Height)
    $shell.BackColor = Get-ThemeColor Canvas
    $fill = New-Object System.Windows.Forms.Panel
    $fill.SetBounds(0, 0, $Width, $Height)
    $fill.BackColor = Get-ThemeColor Canvas
    if ($ReadOnly) { $fill.AccessibleName = 'ro' } else { $fill.AccessibleName = '' }
    $fill.Add_Paint({
        $box = $this
        $g = $_.Graphics
        $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
        $g.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality
        $g.Clear((Get-ThemeColor Canvas))
        $w = $box.Width - 2
        $h = $box.Height - 2
        if ($w -lt 8 -or $h -lt 8) { return }
        $path = New-RoundedPath -Width $w -Height $h -Radius 12
        $g.TranslateTransform(1, 1)
        $tone = Get-ThemeColor FieldFill
        if ($box.AccessibleName -eq 'ro') { $tone = Get-ThemeColor FieldReadOnly }
        $brush = New-Object System.Drawing.SolidBrush $tone
        $g.FillPath($brush, $path)
        $pen = New-Object System.Drawing.Pen (Get-ThemeColor FieldBorder)
        $g.DrawPath($pen, $path)
        $pen.Dispose()
        $brush.Dispose()
        $path.Dispose()
        $g.ResetTransform()
    })
    $iconLabel = New-Object System.Windows.Forms.Label
    $iconLabel.Text = $Icon
    $iconLabel.Font = $script:IconFont
    $iconLabel.ForeColor = $iconColor
    $iconLabel.BackColor = $fillColor
    $iconLabel.TextAlign = 'MiddleCenter'
    $iconLabel.SetBounds(10, 4, 28, ($Height - 8))
    if ($Kind -eq 'Combo') {
        Initialize-SoftListType
        $editor = New-Object DeskSoftList
        $valueLabel = New-Object System.Windows.Forms.Label
        $valueLabel.Font = $script:FieldFont
        $valueLabel.ForeColor = $ink
        $valueLabel.BackColor = $fillColor
        $valueLabel.AutoEllipsis = $true
        $valueLabel.TextAlign = 'MiddleLeft'
        $valueLabel.Cursor = [System.Windows.Forms.Cursors]::Hand
        $valueLabel.SetBounds(40, 4, ($Width - 84), ($Height - 8))
        $chevron = New-Object System.Windows.Forms.Label
        $chevron.Text = [string][char]0x2304
        $chevron.Font = $script:FieldFont
        $chevron.ForeColor = $iconColor
        $chevron.BackColor = $fillColor
        $chevron.TextAlign = 'MiddleCenter'
        $chevron.Cursor = [System.Windows.Forms.Cursors]::Hand
        $chevron.SetBounds(($Width - 34), 4, 22, ($Height - 8))
        $syncCaption = {
            $caption = ''
            if ($editor.SelectedIndex -ge 0 -and $editor.SelectedIndex -lt $editor.Items.Count) {
                $caption = [string]$editor.Items[$editor.SelectedIndex]
            }
            $valueLabel.Text = $caption
        }.GetNewClosure()
        $editor.Add_SelectedIndexChanged($syncCaption)
        $editor.Add_ItemsChanged($syncCaption)
        $openList = { Show-SoftListPopup -List $editor -Anchor $shell }.GetNewClosure()
        $fill.Add_Click($openList)
        $iconLabel.Add_Click($openList)
        $shell.Add_Click($openList)
        $valueLabel.Add_Click($openList)
        $chevron.Add_Click($openList)
        $fill.Controls.Add($iconLabel)
        $fill.Controls.Add($valueLabel)
        $fill.Controls.Add($chevron)
        $shell.Controls.Add($fill)
        return @{ Shell = $shell; Editor = $editor; Fill = $fill; Icon = $iconLabel; ValueLabel = $valueLabel; Chevron = $chevron }
    } elseif ($Kind -eq 'Note') {
        $editor = New-Object System.Windows.Forms.TextBox
        $editor.Multiline = $true
        $editor.ScrollBars = 'None'
        $editor.BorderStyle = 'None'
        $editor.Font = $script:FieldFont
        $editor.BackColor = $fillColor
        $editor.ForeColor = $ink
        $editor.AcceptsReturn = $true
        $editor.SetBounds(40, 10, ($Width - 56), ($Height - 20))
    } else {
        $editor = New-Object System.Windows.Forms.TextBox
        $editor.BorderStyle = 'None'
        $editor.Font = $script:FieldFont
        $editor.BackColor = $fillColor
        $editor.ForeColor = $ink
        $editor.SetBounds(40, 10, ($Width - 56), 20)
        if ($ReadOnly) {
            $editor.ReadOnly = $true
            $editor.TabStop = $false
        }
    }
    $focusEditor = {
        try { $editor.Focus() } catch { }
    }.GetNewClosure()
    $fill.Add_Click($focusEditor)
    $iconLabel.Add_Click($focusEditor)
    $shell.Add_Click($focusEditor)
    $fill.Controls.Add($iconLabel)
    $fill.Controls.Add($editor)
    $shell.Controls.Add($fill)
    return @{ Shell = $shell; Editor = $editor; Fill = $fill; Icon = $iconLabel; ValueLabel = $null; Chevron = $null }
}

function Set-FieldCue {
    param($Box, [string]$Cue)
    if ($null -eq $Box -or [string]::IsNullOrWhiteSpace($Cue)) { return }
    $hostPanel = $Box.Parent
    if ($null -eq $hostPanel) { return }
    $cueLabel = New-Object System.Windows.Forms.Label
    $cueLabel.Text = $Cue
    $cueLabel.Tag = 'cue'
    $cueLabel.Font = $script:FieldFont
    $cueLabel.ForeColor = Get-ThemeColor Icon
    $cueLabel.BackColor = $Box.BackColor
    $cueLabel.AutoEllipsis = $true
    $cueLabel.Cursor = [System.Windows.Forms.Cursors]::IBeam
    $cueHeight = 22
    if (-not $Box.Multiline) { $cueHeight = $Box.Height }
    $cueLabel.SetBounds($Box.Left, $Box.Top, $Box.Width, $cueHeight)
    $cueLabel.Add_Click({ try { $Box.Focus() } catch { } }.GetNewClosure())
    $Box.Add_GotFocus({ $cueLabel.Visible = $false }.GetNewClosure())
    $Box.Add_LostFocus({ $cueLabel.Visible = [string]::IsNullOrEmpty($Box.Text) }.GetNewClosure())
    $Box.Add_TextChanged({
        $cueLabel.Visible = [string]::IsNullOrEmpty($Box.Text) -and -not $Box.Focused
    }.GetNewClosure())
    $hostPanel.Controls.Add($cueLabel)
    $cueLabel.BringToFront()
}

function Clear-ChildControls {
    param($Parent)
    if ($null -eq $Parent) { return }
    $pending = @($Parent.Controls)
    foreach ($child in $pending) {
        $Parent.Controls.Remove($child)
        $child.Dispose()
    }
}

function Move-NewsScroll {
    param([int]$Delta)
    $canvas = $script:NewsCanvas
    $list = $null
    if ($script:WidgetUi) { $list = $script:WidgetUi.NewsList }
    if ($null -eq $canvas -or $canvas.IsDisposed -or $null -eq $list -or $list.IsDisposed) { return }
    $max = $canvas.Height - $list.ClientSize.Height
    if ($max -lt 0) { $max = 0 }
    $step = 0
    if ($Delta -gt 0) { $step = 72 } elseif ($Delta -lt 0) { $step = -72 }
    $next = $canvas.Top + $step
    if ($next -gt 0) { $next = 0 }
    if ($next -lt (0 - $max)) { $next = 0 - $max }
    $canvas.Top = $next
}

function Register-NewsWheel {
    param($Control)
    if ($null -eq $Control -or $Control.IsDisposed) { return }
    $Control.Add_MouseWheel({ if ($args.Count -gt 1) { Move-NewsScroll $args[1].Delta } })
    foreach ($child in @($Control.Controls)) { Register-NewsWheel $child }
}

function Update-NewsRows {
    if ($null -eq $script:WidgetUi) { return }
    $list = $script:WidgetUi.NewsList
    Clear-ChildControls $list
    $list.AutoScroll = $false
    $canvas = New-Object System.Windows.Forms.Panel
    $canvas.BackColor = Get-ThemeColor Canvas
    $viewWidth = $list.ClientSize.Width
    if ($viewWidth -lt 120) { $viewWidth = [int]$script:SupportPanelWidth }
    $canvas.SetBounds(0, 0, $viewWidth, 40)
    $list.Controls.Add($canvas)
    $script:NewsCanvas = $canvas
    $visible = New-Object System.Collections.Generic.List[object]
    foreach ($candidate in @($script:NewsItems)) {
        if ($null -eq $candidate) { continue }
        $visible.Add($candidate)
    }
    $items = @($visible.ToArray())
    if ($items.Count -eq 0) {
        $empty = New-Object System.Windows.Forms.Label
        $empty.Text = 'Пока нет сообщений'
        $empty.TextAlign = 'MiddleCenter'
        $empty.Font = $script:TabFontBold
        $empty.ForeColor = Get-ThemeColor Empty
        $empty.BackColor = Get-ThemeColor Canvas
        $emptyWidth = [int]$script:SupportPanelWidth - 32
        $empty.SetBounds(16, 48, $emptyWidth, 24)
        $hint = New-Object System.Windows.Forms.Label
        $hint.Text = 'Сообщения остаются здесь сутки.'
        $hint.TextAlign = 'MiddleCenter'
        $hint.Font = $script:TabFont
        $hint.ForeColor = Get-ThemeColor Muted
        $hint.BackColor = Get-ThemeColor Canvas
        $hint.SetBounds(16, 76, $emptyWidth, 36)
        $canvas.Controls.Add($empty)
        $canvas.Controls.Add($hint)
        $canvas.Height = 140
        Register-NewsWheel $canvas
        return
    }
    $y = 12
    $rowWidth = $viewWidth - 32
    if ($rowWidth -lt 120) { $rowWidth = [int]$script:SupportPanelWidth - 32 }
    $rowHeight = 84
    foreach ($item in $items) {
        $url = [string]$item.Url
        $opens = Test-NoticeLinkEnabled $url
        $row = New-Object System.Windows.Forms.Panel
        $row.SetBounds(16, $y, $rowWidth, $rowHeight)
        $row.BackColor = Get-ThemeColor FieldFill
        $row.Tag = $url
        $rowColor = $row.BackColor
        $bar = New-Object System.Windows.Forms.Panel
        $bar.SetBounds(0, 0, 3, $rowHeight)
        if ([string]$item.Kind -eq 'maintenance') { $bar.BackColor = Get-ThemeColor Maintenance }
        else { $bar.BackColor = Get-ThemeColor Accent }
        $title = New-Object System.Windows.Forms.Label
        $title.Text = [string]$item.Title
        $title.Font = $script:RowTitleFont
        $title.ForeColor = Get-ThemeColor Ink
        $title.BackColor = $rowColor
        $title.AutoEllipsis = $true
        $title.SetBounds(16, 10, ($rowWidth - 28), 20)
        $title.Tag = $url
        $body = New-Object System.Windows.Forms.Label
        $body.Text = Get-NoticeSnippet ([string]$item.Body)
        $body.Font = $script:RowBodyFont
        $body.ForeColor = Get-ThemeColor Detail
        $body.BackColor = $rowColor
        $body.AutoEllipsis = $true
        $body.SetBounds(16, 32, ($rowWidth - 28), 18)
        $body.Tag = $url
        $when = New-Object System.Windows.Forms.Label
        $when.Text = Format-NoticeStamp ([string]$item.PublishedAt)
        $when.Font = $script:RowBodyFont
        $when.ForeColor = Get-ThemeColor Muted
        $when.BackColor = $rowColor
        $when.AutoEllipsis = $true
        $when.SetBounds(16, 54, ($rowWidth - 28), 18)
        $when.Tag = $url
        if ($opens) {
            $targetUrl = $url
            $openNotice = {
                if (-not [string]::IsNullOrWhiteSpace($targetUrl)) { Start-Process $targetUrl }
            }.GetNewClosure()
            $hand = [System.Windows.Forms.Cursors]::Hand
            $row.Cursor = $hand
            $title.Cursor = $hand
            $body.Cursor = $hand
            $when.Cursor = $hand
            $row.Add_Click($openNotice)
            $title.Add_Click($openNotice)
            $body.Add_Click($openNotice)
            $when.Add_Click($openNotice)
        }
        $row.Controls.Add($bar)
        $row.Controls.Add($title)
        $row.Controls.Add($body)
        $row.Controls.Add($when)
        $canvas.Controls.Add($row)
        $y += ($rowHeight + 10)
        if ($y -gt 2400) { break }
    }
    $canvas.Height = $y + 16
    $canvas.Top = 0
    Register-NewsWheel $canvas
}

function Test-JiraTicketMode {
    if ($null -eq $script:Cfg) { return $false }
    return [string]$script:Cfg.ServiceDeskProvider -eq 'Jira'
}

function Get-WidgetPortalUrl {
    $explicit = ''
    $jira = ''
    if ($script:Cfg) {
        $explicit = [string]$script:Cfg.ServiceDeskUrl
        if (Test-JiraTicketMode) { $jira = [string]$script:Cfg.JiraBaseUrl }
    }
    return Get-JiraPortalUrl -BaseUrl $jira -ExplicitUrl $explicit
}

function Get-WebhookCategoryNames {
    $fallback = @('Инцидент', 'Запрос обслуживания', 'Вопрос')
    if ($null -eq $script:Cfg) { return ,$fallback }
    $configured = $script:Cfg.ServiceDeskCategories
    if ($null -eq $configured -or $configured.Count -eq 0) { return ,$fallback }
    return ,$configured
}

function Test-WebhookProjectMode {
    if (Test-JiraTicketMode -or $null -eq $script:Cfg) { return $false }
    $projects = $script:Cfg.ServiceDeskProjects
    return ($null -ne $projects -and $projects.Count -gt 0)
}

function Get-SelectedTicketProject {
    $empty = [pscustomobject]@{ Name = ''; Id = '' }
    if ($null -eq $script:WidgetUi) { return $empty }
    $index = [int]$script:WidgetUi.ProjectBox.SelectedIndex
    if ($index -lt 0) { return $empty }
    if (Test-JiraTicketMode) {
        $desks = $script:JiraDesks
        if ($null -eq $desks -or $index -ge $desks.Count -or $null -eq $desks[$index]) { return $empty }
        $desk = $desks[$index]
        $key = [string]$desk.ProjectKey
        if ([string]::IsNullOrWhiteSpace($key)) { $key = [string]$desk.Id }
        return [pscustomobject]@{ Name = [string]$desk.ProjectName; Id = $key }
    }
    if (-not (Test-WebhookProjectMode)) { return $empty }
    $projects = $script:Cfg.ServiceDeskProjects
    if ($null -eq $projects -or $index -ge $projects.Count -or $null -eq $projects[$index]) { return $empty }
    return [pscustomobject]@{ Name = [string]$projects[$index].Name; Id = [string]$projects[$index].Id }
}

function Set-TicketFieldLayout {
    param([bool]$ShowProject)
    if ($null -eq $script:WidgetUi) { return }
    $ui = $script:WidgetUi
    $fieldW = [int]$script:SupportPanelWidth - 32
    $ui.LoginLabel.SetBounds(16, 2, $fieldW, 14)
    $ui.LoginHost.SetBounds(16, 18, $fieldW, 40)
    $ui.ComputerLabel.SetBounds(16, 66, $fieldW, 14)
    $ui.ComputerHost.SetBounds(16, 82, $fieldW, 40)
    $ui.ProjectLabel.Visible = $ShowProject
    $ui.ProjectHost.Visible = $ShowProject
    if ($ShowProject) {
        if (Test-JiraTicketMode) { $ui.CategoryLabel.Text = 'Тип запроса' }
        else { $ui.CategoryLabel.Text = 'Категория' }
        $ui.ProjectLabel.SetBounds(16, 130, $fieldW, 14)
        $ui.ProjectHost.SetBounds(16, 146, $fieldW, 40)
        $ui.CategoryLabel.SetBounds(16, 194, $fieldW, 14)
        $ui.CategoryHost.SetBounds(16, 210, $fieldW, 40)
        $ui.SubjectLabel.SetBounds(16, 258, $fieldW, 14)
        $ui.SubjectHost.SetBounds(16, 274, $fieldW, 40)
        $ui.BodyLabel.SetBounds(16, 322, $fieldW, 14)
        Update-SoftFieldSize -Field $ui.BodyField -Width $fieldW -Height 56
        $ui.BodyHost.SetBounds(16, 338, $fieldW, 56)
        $ui.TicketStatus.SetBounds(16, 398, $fieldW, 16)
        $ui.SendButton.SetBounds(16, 416, $fieldW, 44)
        $ui.PortalLink.TextAlign = 'MiddleCenter'
        $ui.PortalLink.SetBounds(16, 460, $fieldW, 20)
    } else {
        $ui.CategoryLabel.Text = 'Категория'
        $ui.CategoryLabel.SetBounds(16, 130, $fieldW, 14)
        $ui.CategoryHost.SetBounds(16, 146, $fieldW, 40)
        $ui.SubjectLabel.SetBounds(16, 194, $fieldW, 14)
        $ui.SubjectHost.SetBounds(16, 210, $fieldW, 40)
        $ui.BodyLabel.SetBounds(16, 258, $fieldW, 14)
        Update-SoftFieldSize -Field $ui.BodyField -Width $fieldW -Height 104
        $ui.BodyHost.SetBounds(16, 274, $fieldW, 104)
        $ui.TicketStatus.SetBounds(16, 384, $fieldW, 16)
        $ui.SendButton.SetBounds(16, 402, $fieldW, 44)
        $ui.PortalLink.TextAlign = 'MiddleCenter'
        $ui.PortalLink.SetBounds(16, 450, $fieldW, 22)
    }
    Update-FlatButtonRegion $ui.SendButton
}

function Update-TicketActions {
    if ($null -eq $script:WidgetUi) { return }
    $api = ''
    if ($script:Cfg) { $api = [string]$script:Cfg.ServiceDeskApiUrl }
    $ui = $script:WidgetUi
    $jira = Test-JiraTicketMode
    $portal = Get-WidgetPortalUrl
    $hasApi = -not [string]::IsNullOrWhiteSpace($api)
    $hasPortal = -not [string]::IsNullOrWhiteSpace($portal)
    Set-TicketFieldLayout -ShowProject ($jira -or (Test-WebhookProjectMode))
    if ($jira) {
        $ui.PortalLink.Visible = $hasPortal
        $ui.ProjectBox.Enabled = $true
        $ui.CategoryBox.Enabled = $true
        $ui.SubjectBox.Enabled = $true
        $ui.BodyBox.Enabled = $true
        $ui.SendButton.Text = 'Отправить заявку'
        $ui.SendButton.Enabled = $true
        return
    }
    $ui.PortalLink.Visible = $hasApi -and $hasPortal
    $ui.ProjectBox.Enabled = $hasApi -or $hasPortal
    $ui.SubjectBox.Enabled = $hasApi
    $ui.BodyBox.Enabled = $hasApi
    $ui.CategoryBox.Enabled = $hasApi
    if ($hasApi) {
        $ui.SendButton.Text = 'Отправить заявку'
        $ui.SendButton.Enabled = $true
    } elseif ($hasPortal) {
        $ui.SendButton.Text = 'Открыть портал'
        $ui.SendButton.Enabled = $true
    } else {
        $ui.SendButton.Text = 'Отправить заявку'
        $ui.SendButton.Enabled = $false
        if ([string]::IsNullOrWhiteSpace([string]$ui.TicketStatus.Text)) {
            $ui.TicketStatus.ForeColor = Get-ThemeColor Muted
            $ui.TicketStatus.Text = 'Адрес сервис-деска задаёт администратор в config.json.'
        }
    }
}

function Apply-SupportPageVisual {
    param([string]$Page)
    if ($null -eq $script:WidgetUi) { return }
    $script:WidgetPage = 'Ticket'
    $ui = $script:WidgetUi
    if ($ui.NewsPage) { $ui.NewsPage.Visible = $false }
    $ui.TicketPage.Visible = $true
    $ink = Get-ThemeColor Ink
    $ui.NewsTab.Text = 'Аварийная папка'
    $ui.NewsTab.ForeColor = $ink
    $ui.NewsTab.Font = $script:TabFont
    $ui.TicketTab.ForeColor = $ink
    $ui.TicketTab.Font = $script:TabFontBold
    Update-SupportTabLine
    $session = Get-WindowsSessionIdentity
    $ui.LoginBox.Text = Format-WindowsAccount ([string]$session.Login)
    $ui.ComputerBox.Text = [string]$session.Computer
}

function Update-SupportTabLine {
    param([switch]$News)
    if ($null -eq $script:WidgetUi) { return }
    $panelW = [int]$script:SupportPanelWidth
    $half = [int]($panelW / 2)
    $lineW = 64
    $origin = 0
    if ($News) { $origin = $half }
    $x = $origin + [int](($half - $lineW) / 2)
    $script:WidgetUi.TabLine.SetBounds($x, 30, $lineW, 2)
}

function Select-SupportPage {
    param([string]$Page)
    Apply-SupportPageVisual -Page 'Ticket'
}

function Update-WidgetChrome {
    Sync-WidgetTheme
    if ($null -eq $script:WidgetForm -or $script:WidgetForm.IsDisposed -or $null -eq $script:WidgetUi) { return }
    $ui = $script:WidgetUi
    $status = Get-SupportStatus
    $ui.Status.Text = [string]$status.Text
    $ui.Status.ForeColor = $status.Color
    $session = Get-WindowsSessionIdentity
    $login = Format-WindowsAccount ([string]$session.Login)
    $computer = [string]$session.Computer
    $ui.Identity.Text = ''
    $ui.Identity.Visible = $false
    $ui.LoginBox.Text = $login
    $ui.ComputerBox.Text = $computer
    $ui.NewsTab.Text = 'Аварийная папка'
    $signature = Get-NewsSignature
    if ($null -eq $script:NewsSignature -or $signature -ne $script:NewsSignature) {
        Update-NewsRows
        $script:NewsSignature = $signature
    }
    Update-TicketActions
    Set-SupportBounds
    Update-LauncherSurface
}

function Update-WidgetStatus {
    Update-WidgetChrome
}

function Hide-SupportPanel {
    if ($script:PanelHiding) { return }
    $script:PanelHiding = $true
    try {
        $script:PanelOpen = $false
        Leave-NewsReading
        if ($script:PanelForm -and -not $script:PanelForm.IsDisposed -and $script:PanelForm.Visible) {
            $script:PanelForm.Hide()
        }
        Update-LauncherSurface
    } finally {
        $script:PanelHiding = $false
    }
}

function Show-SupportPanel {
    param([string]$Page)
    if ([string]::IsNullOrWhiteSpace($Page)) { $Page = 'Ticket' }
    if ($null -eq $script:WidgetForm -or $script:WidgetForm.IsDisposed -or -not $script:WidgetForm.IsHandleCreated) {
        Ensure-DesktopWidget
    }
    if ($null -eq $script:PanelForm -or $script:PanelForm.IsDisposed) { return }
    $script:PanelOpen = $true
    Set-SupportBounds
    Apply-SupportPageVisual -Page $Page
    if ($script:WidgetPage -eq 'News') { Enter-NewsReading }
    else { Leave-NewsReading }
    if (-not $script:PanelForm.Visible) { $script:PanelForm.Show() }
    try { $script:PanelForm.Activate() } catch { }
    Update-LauncherSurface
    Start-JiraCatalogLoad
}

function New-LauncherButton {
    $form = New-Object System.Windows.Forms.Form
    $form.FormBorderStyle = 'None'
    $form.ShowInTaskbar = $false
    $form.StartPosition = 'Manual'
    $form.TopMost = Test-StayOnTop
    $form.BackColor = Get-ThemeColor Accent
    $form.ClientSize = New-Object System.Drawing.Size(52, 52)
    $form.Text = Get-WidgetTitle
    $form.Cursor = [System.Windows.Forms.Cursors]::Hand
    $circle = New-Object System.Drawing.Drawing2D.GraphicsPath
    $circle.AddEllipse(0, 0, 52, 52)
    $form.Region = New-Object System.Drawing.Region($circle)
    $form.Add_Paint({
        $g = $_.Graphics
        $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
        $g.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality
        $fill = Get-LauncherFill
        if ($script:LauncherHot) { $fill = Get-LauncherFill -Hover }
        if ($script:PanelOpen) {
            $plate = New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::FromArgb(168, 16, 18, 24))
            $g.FillEllipse($plate, 0, 0, 51, 51)
            $plate.Dispose()
            $pen = New-Object System.Drawing.Pen ([System.Drawing.Color]::White, 2.6)
            $pen.StartCap = [System.Drawing.Drawing2D.LineCap]::Round
            $pen.EndCap = [System.Drawing.Drawing2D.LineCap]::Round
            $g.DrawLine($pen, 18, 18, 34, 34)
            $g.DrawLine($pen, 34, 18, 18, 34)
            $pen.Dispose()
        } else {
        $disc = $fill
        $plateAlpha = $disc.A
        if ($plateAlpha -eq 0) { $plateAlpha = 1 }
        $brush = New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::FromArgb($plateAlpha, $disc.R, $disc.G, $disc.B))
        $g.FillEllipse($brush, 0, 0, 51, 51)
        $brush.Dispose()
        $drewIcon = $false
        $inset = 6
        if ($disc.A -eq 0) { $inset = 1 }
        $iconSize = 52 - ($inset * 2)
        if ($script:Cfg -and -not [string]::IsNullOrWhiteSpace([string]$script:Cfg.WidgetIcon)) {
            $iconPath = Resolve-WidgetIconPath ([string]$script:Cfg.WidgetIcon)
            if (-not [string]::IsNullOrWhiteSpace($iconPath)) {
                $stream = $null
                $image = $null
                try {
                    $stream = New-Object System.IO.FileStream($iconPath, 'Open', 'Read', 'ReadWrite')
                    $image = [System.Drawing.Image]::FromStream($stream)
                    $clip = New-Object System.Drawing.Drawing2D.GraphicsPath
                    $clip.AddEllipse($inset, $inset, $iconSize, $iconSize)
                    $g.SetClip($clip)
                    $g.DrawImage($image, (New-Object System.Drawing.Rectangle($inset, $inset, $iconSize, $iconSize)))
                    $g.ResetClip()
                    $clip.Dispose()
                    $drewIcon = $true
                } catch {
                    $drewIcon = $false
                } finally {
                    if ($null -ne $image) { $image.Dispose() }
                    if ($null -ne $stream) { $stream.Dispose() }
                }
            }
        }
        if (-not $drewIcon) {
            $pen = New-Object System.Drawing.Pen ([System.Drawing.Color]::White, 3.4)
            $pen.StartCap = [System.Drawing.Drawing2D.LineCap]::Round
            $pen.EndCap = [System.Drawing.Drawing2D.LineCap]::Round
            $g.DrawLine($pen, 26, 12, 26, 31)
            $pen.Dispose()
            $dot = New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::White)
            $g.FillEllipse($dot, 23.4, 36.5, 5.2, 5.2)
            $dot.Dispose()
        }
        }
        $count = Get-LauncherBadgeCount
        if ($count -gt 0) {
            $text = [string]$count
            if ($count -gt 9) { $text = '9+' }
            $badgeHeight = 20
            $badgeWidth = 20
            if ($text.Length -gt 1) { $badgeWidth = 26 }
            $badgeX = 52 - $badgeWidth - 1
            $badgeY = 1
            $shadow = New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::FromArgb(80, 0, 0, 0))
            $g.FillEllipse($shadow, ($badgeX + 0.4), ($badgeY + 1.6), $badgeWidth, $badgeHeight)
            $shadow.Dispose()
            $plate = New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::FromArgb(255, 23, 26, 33))
            $g.FillEllipse($plate, $badgeX, $badgeY, $badgeWidth, $badgeHeight)
            $plate.Dispose()
            $ring = New-Object System.Drawing.Pen ([System.Drawing.Color]::White, 1.7)
            $g.DrawEllipse($ring, ($badgeX + 1.15), ($badgeY + 1.15), ($badgeWidth - 2.3), ($badgeHeight - 2.3))
            $ring.Dispose()
            $g.TextRenderingHint = [System.Drawing.Text.TextRenderingHint]::AntiAliasGridFit
            $fontPx = 12
            if ($text.Length -gt 1) { $fontPx = 10 }
            $font = New-Object System.Drawing.Font('Segoe UI', ([single]$fontPx), [System.Drawing.FontStyle]::Bold, [System.Drawing.GraphicsUnit]::Pixel)
            $ink = New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::White)
            $format = New-Object System.Drawing.StringFormat
            $format.Alignment = [System.Drawing.StringAlignment]::Center
            $format.LineAlignment = [System.Drawing.StringAlignment]::Center
            $box = New-Object System.Drawing.RectangleF(([single]$badgeX), ([single]($badgeY - 0.4)), ([single]$badgeWidth), ([single]$badgeHeight))
            $g.DrawString($text, $font, $ink, $box, $format)
            $format.Dispose()
            $ink.Dispose()
            $font.Dispose()
        }
    })
    $form.Add_MouseEnter({ $script:LauncherHot = $true; Update-LauncherSurface })
    $form.Add_MouseLeave({ $script:LauncherHot = $false; Update-LauncherSurface })
    $form.Add_MouseDown({
        $mouse = $null
        if ($args.Count -gt 1) { $mouse = $args[1] }
        if (-not (Test-LeftMousePress $mouse)) { return }
        $now = Get-Date
        if (($now - $script:LauncherClickAt).TotalMilliseconds -lt 400) { return }
        $script:LauncherClickAt = $now
        Open-EmergencyFolder
    })
    $form.Add_HandleCreated({ Attach-LauncherClickHook $form }.GetNewClosure())
    $form.Add_FormClosing({
        if ($script:AllowExit) { return }
        if ($_.CloseReason -eq [System.Windows.Forms.CloseReason]::UserClosing) { $_.Cancel = $true }
    })
    $form.Add_HandleDestroyed({
        if (-not $script:AllowExit) { $script:WidgetForm = $null }
    })
    return $form
}

function New-SupportPanel {
    $accent = Get-ThemeColor Accent
    $headerColor = Get-ThemeColor Canvas
    $ink = Get-ThemeColor Ink
    $muted = Get-ThemeColor Muted
    $labelColor = Get-ThemeColor Label
    $hover = Get-ThemeColor Hover
    $ruleColor = Get-ThemeColor Rule
    $panelW = [int]$script:SupportPanelWidth
    $panelH = [int]$script:SupportPanelHeight
    $headerH = 64
    $pageY = 34
    $pageH = $panelH - $headerH - $pageY
    $panel = New-Object System.Windows.Forms.Form
    $panel.FormBorderStyle = 'None'
    $panel.ShowInTaskbar = $false
    $panel.StartPosition = 'Manual'
    $panel.TopMost = Test-StayOnTop
    $panel.BackColor = $headerColor
    $panel.ClientSize = New-Object System.Drawing.Size($panelW, $panelH)
    $panel.Text = Get-WidgetTitle
    $panel.Font = $script:TabFont
    $panel.KeyPreview = $true
    $panel.Region = New-Object System.Drawing.Region((New-RoundedPath -Width $panelW -Height $panelH -Radius 20))

    $header = New-Object System.Windows.Forms.Panel
    $header.SetBounds(0, 0, $panelW, $headerH)
    $header.BackColor = $headerColor
    $titleText = Get-WidgetTitle
    $markText = 'С'
    $trimmedTitle = $titleText.Trim()
    if ($trimmedTitle.Length -gt 0) { $markText = $trimmedTitle.Substring(0, 1).ToUpper() }
    $mark = New-Object System.Windows.Forms.Panel
    $mark.SetBounds(16, 14, 36, 36)
    $mark.BackColor = $headerColor
    $mark.Text = $markText
    $mark.Font = $script:LogoFont
    $mark.Add_Paint({
        $box = $this
        $g = $_.Graphics
        $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
        $g.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality
        $g.TextRenderingHint = [System.Drawing.Text.TextRenderingHint]::ClearTypeGridFit
        $g.Clear($box.BackColor)
        $path = New-RoundedPath -Width 34 -Height 34 -Radius 10
        $g.TranslateTransform(1, 1)
        $brush = New-Object System.Drawing.SolidBrush (Get-ThemeColor Accent)
        $g.FillPath($brush, $path)
        $brush.Dispose()
        $path.Dispose()
        $g.ResetTransform()
        $flags = [System.Windows.Forms.TextFormatFlags]::HorizontalCenter -bor [System.Windows.Forms.TextFormatFlags]::VerticalCenter -bor [System.Windows.Forms.TextFormatFlags]::NoPadding -bor [System.Windows.Forms.TextFormatFlags]::SingleLine
        [System.Windows.Forms.TextRenderer]::DrawText($g, [string]$box.Text, $box.Font, (New-Object System.Drawing.Rectangle(1, 1, 34, 34)), [System.Drawing.Color]::White, $flags)
    })
    $title = New-Object System.Windows.Forms.Label
    $title.Text = $titleText
    $title.Font = $script:TitleFont
    $title.ForeColor = $ink
    $title.BackColor = $headerColor
    $title.AutoEllipsis = $true
    $title.SetBounds(60, 14, ($panelW - 120), 22)
    $identity = New-Object System.Windows.Forms.Label
    $identity.Text = ''
    $identity.Visible = $false
    $identity.Font = $script:RowBodyFont
    $identity.ForeColor = $muted
    $identity.BackColor = $headerColor
    $status = New-Object System.Windows.Forms.Label
    $status.Text = 'Проверка сети'
    $status.Font = $script:RowBodyFont
    $status.ForeColor = $muted
    $status.BackColor = $headerColor
    $status.AutoEllipsis = $true
    $status.SetBounds(60, 36, ($panelW - 120), 16)
    $close = New-Object System.Windows.Forms.Label
    $close.Text = [string][char]0xE711
    $close.Font = $script:IconFont
    $close.TextAlign = 'MiddleCenter'
    $close.ForeColor = $ink
    $close.BackColor = $headerColor
    $close.Cursor = [System.Windows.Forms.Cursors]::Hand
    $close.SetBounds(($panelW - 60), 8, 48, 48)
    $close.Add_MouseEnter({ $this.ForeColor = Get-ThemeColor Ink; $this.BackColor = Get-ThemeColor Hover })
    $close.Add_MouseLeave({ $this.ForeColor = Get-ThemeColor Ink; $this.BackColor = Get-ThemeColor Canvas })
    $close.Add_MouseDown({
        $mouse = $null
        if ($args.Count -gt 1) { $mouse = $args[1] }
        if (-not (Test-LeftMousePress $mouse)) { return }
        Hide-SupportPanel
    })
    $header.Controls.Add($mark)
    $header.Controls.Add($title)
    $header.Controls.Add($identity)
    $header.Controls.Add($status)
    $header.Controls.Add($close)
    $close.BringToFront()

    $sheet = New-Object System.Windows.Forms.Panel
    $sheet.SetBounds(0, $headerH, $panelW, ($panelH - $headerH))
    $sheet.BackColor = $headerColor

    $half = [int]($panelW / 2)
    $ticketTab = New-Object System.Windows.Forms.Button
    $ticketTab.Text = 'Заявка'
    $ticketTab.SetBounds(0, 0, $half, 32)
    $ticketTab.TextAlign = 'MiddleCenter'
    $ticketTab.Padding = New-Object System.Windows.Forms.Padding(0)
    $ticketTab.FlatStyle = 'Flat'
    $ticketTab.FlatAppearance.BorderSize = 0
    $ticketTab.FlatAppearance.MouseOverBackColor = $hover
    $ticketTab.BackColor = $headerColor
    $ticketTab.ForeColor = $ink
    $ticketTab.Font = $script:TabFontBold
    $ticketTab.Cursor = [System.Windows.Forms.Cursors]::Hand
    $ticketTab.Add_Click({
        Select-SupportPage -Page Ticket
        if ($script:PanelForm -and -not $script:PanelForm.IsDisposed) {
            $script:PanelForm.BeginInvoke([System.Action]{ Request-JiraCatalogIfTicket }) | Out-Null
        }
    })
    $newsTab = New-Object System.Windows.Forms.Button
    $newsTab.Text = 'Аварийная папка'
    $newsTab.SetBounds($half, 0, ($panelW - $half), 32)
    $newsTab.TextAlign = 'MiddleCenter'
    $newsTab.Padding = New-Object System.Windows.Forms.Padding(0)
    $newsTab.FlatStyle = 'Flat'
    $newsTab.FlatAppearance.BorderSize = 0
    $newsTab.FlatAppearance.MouseOverBackColor = $hover
    $newsTab.BackColor = $headerColor
    $newsTab.ForeColor = $ink
    $newsTab.Font = $script:TabFont
    $newsTab.Cursor = [System.Windows.Forms.Cursors]::Hand
    $newsTab.Add_Click({ Open-EmergencyFolder })
    $tabLine = New-Object System.Windows.Forms.Panel
    $tabLine.BackColor = $accent
    $tabLine.SetBounds(58, 30, 64, 2)

    $newsPage = New-Object System.Windows.Forms.Panel
    $newsPage.SetBounds(0, $pageY, $panelW, $pageH)
    $newsPage.Visible = $false
    $newsPage.BackColor = $headerColor
    $newsList = New-Object System.Windows.Forms.Panel
    $newsList.Dock = 'Fill'
    $newsList.AutoScroll = $false
    $newsList.BackColor = $headerColor
    $newsList.Add_MouseWheel({ if ($args.Count -gt 1) { Move-NewsScroll $args[1].Delta } })
    $newsPage.Controls.Add($newsList)

    $ticketPage = New-Object System.Windows.Forms.Panel
    $ticketPage.SetBounds(0, $pageY, $panelW, $pageH)
    $ticketPage.BackColor = $headerColor
    $ticketPage.Visible = $true
    $fieldW = $panelW - 32
    $iconUser = [string][char]0xE77B
    $iconPc = [string][char]0xE7F8
    $iconList = [string][char]0xE8FD
    $iconEdit = [string][char]0xE70F
    $iconMessage = [string][char]0xE8BD
    $loginLabel = New-Object System.Windows.Forms.Label
    $loginLabel.Text = 'Логин Windows'
    $loginLabel.ForeColor = $labelColor
    $loginLabel.BackColor = $headerColor
    $loginLabel.SetBounds(16, 2, $fieldW, 14)
    $loginField = New-SoftField -Kind Text -Icon $iconUser -ReadOnly -Width $fieldW -Height 40
    $loginHost = $loginField.Shell
    $loginBox = $loginField.Editor
    $computerLabel = New-Object System.Windows.Forms.Label
    $computerLabel.Text = 'Компьютер'
    $computerLabel.ForeColor = $labelColor
    $computerLabel.BackColor = $headerColor
    $computerLabel.SetBounds(16, 66, $fieldW, 14)
    $computerField = New-SoftField -Kind Text -Icon $iconPc -ReadOnly -Width $fieldW -Height 40
    $computerHost = $computerField.Shell
    $computerBox = $computerField.Editor
    $projectLabel = New-Object System.Windows.Forms.Label
    $projectLabel.Text = 'Проект'
    $projectLabel.ForeColor = $labelColor
    $projectLabel.BackColor = $headerColor
    $projectLabel.Visible = $false
    $projectLabel.SetBounds(16, 130, $fieldW, 14)
    $projectField = New-SoftField -Kind Combo -Icon $iconList -Width $fieldW -Height 40
    $projectHost = $projectField.Shell
    $projectHost.Visible = $false
    $project = $projectField.Editor
    $project.Add_SelectedIndexChanged({
        if ($script:JiraLoading) { return }
        if (-not (Test-JiraTicketMode)) { return }
        Load-JiraRequestTypes
    })
    $categoryLabel = New-Object System.Windows.Forms.Label
    $categoryLabel.Text = 'Категория'
    $categoryLabel.ForeColor = $labelColor
    $categoryLabel.BackColor = $headerColor
    $categoryLabel.SetBounds(16, 130, $fieldW, 14)
    $categoryField = New-SoftField -Kind Combo -Icon $iconList -Width $fieldW -Height 40
    $categoryHost = $categoryField.Shell
    $category = $categoryField.Editor
    if (-not (Test-JiraTicketMode)) {
        foreach ($name in (Get-WebhookCategoryNames)) {
            if (-not [string]::IsNullOrWhiteSpace([string]$name)) { [void]$category.Items.Add([string]$name) }
        }
        if ($category.Items.Count -gt 0) { $category.SelectedIndex = 0 }
        if ($null -ne $script:Cfg -and $null -ne $script:Cfg.ServiceDeskProjects) {
            foreach ($projectItem in $script:Cfg.ServiceDeskProjects) {
                if ($null -eq $projectItem) { continue }
                [void]$project.Items.Add((Format-ServiceDeskProjectLabel $projectItem))
            }
            if ($project.Items.Count -gt 0) { $project.SelectedIndex = 0 }
        }
    }
    $subjectLabel = New-Object System.Windows.Forms.Label
    $subjectLabel.Text = 'Тема'
    $subjectLabel.ForeColor = $labelColor
    $subjectLabel.BackColor = $headerColor
    $subjectLabel.SetBounds(16, 194, $fieldW, 14)
    $subjectField = New-SoftField -Kind Text -Icon $iconEdit -Width $fieldW -Height 40
    $subjectHost = $subjectField.Shell
    $subject = $subjectField.Editor
    Set-FieldCue -Box $subject -Cue 'Например: Не печатает принтер'
    $bodyLabel = New-Object System.Windows.Forms.Label
    $bodyLabel.Text = 'Описание'
    $bodyLabel.ForeColor = $labelColor
    $bodyLabel.BackColor = $headerColor
    $bodyLabel.SetBounds(16, 258, $fieldW, 14)
    $bodyField = New-SoftField -Kind Note -Icon $iconMessage -Width $fieldW -Height 104
    $bodyHost = $bodyField.Shell
    $body = $bodyField.Editor
    Set-FieldCue -Box $body -Cue 'Опишите суть обращения...'
    $ticketStatus = New-Object System.Windows.Forms.Label
    $ticketStatus.Text = ''
    $ticketStatus.ForeColor = $muted
    $ticketStatus.BackColor = $headerColor
    $ticketStatus.SetBounds(16, 384, $fieldW, 16)
    $send = New-FlatButton -Text 'Отправить заявку' -Location (New-Object System.Drawing.Point(16, 402)) -Size (New-Object System.Drawing.Size($fieldW, 44))
    $portalLink = New-Object System.Windows.Forms.LinkLabel
    $portalLink.Text = 'Открыть портал'
    $portalLink.LinkColor = $accent
    $portalLink.ActiveLinkColor = $accent
    $portalLink.LinkBehavior = 'HoverUnderline'
    $portalLink.BackColor = $headerColor
    $portalLink.AutoSize = $false
    $portalLink.TextAlign = 'MiddleCenter'
    $portalLink.UseCompatibleTextRendering = $false
    $portalLink.SetBounds(16, 450, $fieldW, 22)
    $portalLink.Visible = $false
    $portalLink.Add_LinkClicked({
        $portalUrl = Get-WidgetPortalUrl
        if ([string]::IsNullOrWhiteSpace($portalUrl)) { return }
        $who = Get-WindowsSessionIdentity
        $chosen = Get-SelectedTicketProject
        Start-Process (Expand-ServiceDeskUrl -Url $portalUrl -Login $who.Login -Computer $who.Computer -Project $chosen.Name -ProjectId $chosen.Id)
    })
    $send.Add_Click({ Submit-SupportTicket })
    $ticketPage.Controls.Add($loginLabel)
    $ticketPage.Controls.Add($loginHost)
    $ticketPage.Controls.Add($computerLabel)
    $ticketPage.Controls.Add($computerHost)
    $ticketPage.Controls.Add($projectLabel)
    $ticketPage.Controls.Add($projectHost)
    $ticketPage.Controls.Add($categoryLabel)
    $ticketPage.Controls.Add($categoryHost)
    $ticketPage.Controls.Add($subjectLabel)
    $ticketPage.Controls.Add($subjectHost)
    $ticketPage.Controls.Add($bodyLabel)
    $ticketPage.Controls.Add($bodyHost)
    $ticketPage.Controls.Add($ticketStatus)
    $ticketPage.Controls.Add($send)
    $ticketPage.Controls.Add($portalLink)
    $sheet.Controls.Add($newsPage)
    $sheet.Controls.Add($ticketPage)
    $sheet.Controls.Add($newsTab)
    $sheet.Controls.Add($ticketTab)
    $sheet.Controls.Add($tabLine)
    $panel.Controls.Add($header)
    $panel.Controls.Add($sheet)
    $headerRule = New-Object System.Windows.Forms.Panel
    $headerRule.SetBounds(16, ($headerH - 1), ($panelW - 32), 1)
    $headerRule.BackColor = $ruleColor
    $panel.Controls.Add($headerRule)
    Enable-ControlBuffer $panel
    Enable-ControlBuffer $header
    Enable-ControlBuffer $sheet
    Enable-ControlBuffer $ticketPage
    Enable-ControlBuffer $newsPage
    Enable-ControlBuffer $newsList
    $panel.Add_KeyDown({
        if ($_.KeyCode -eq [System.Windows.Forms.Keys]::Escape) { Hide-SupportPanel }
    })
    $panel.Add_FormClosing({
        if ($script:AllowExit) { return }
        $_.Cancel = $true
        Hide-SupportPanel
    })

    $script:WidgetUi = @{
        Header = $header
        Sheet = $sheet
        TitleLabel = $title
        CloseButton = $close
        Mark = $mark
        HeaderRule = $headerRule
        Status = $status
        Identity = $identity
        LoginLabel = $loginLabel
        LoginHost = $loginHost
        LoginField = $loginField
        LoginBox = $loginBox
        ComputerLabel = $computerLabel
        ComputerHost = $computerHost
        ComputerField = $computerField
        ComputerBox = $computerBox
        ProjectLabel = $projectLabel
        ProjectHost = $projectHost
        ProjectField = $projectField
        ProjectBox = $project
        CategoryLabel = $categoryLabel
        CategoryHost = $categoryHost
        CategoryField = $categoryField
        SubjectLabel = $subjectLabel
        SubjectHost = $subjectHost
        SubjectField = $subjectField
        BodyLabel = $bodyLabel
        BodyHost = $bodyHost
        BodyField = $bodyField
        NewsTab = $newsTab
        TicketTab = $ticketTab
        TabLine = $tabLine
        NewsPage = $newsPage
        TicketPage = $ticketPage
        NewsList = $newsList
        SubjectBox = $subject
        BodyBox = $body
        CategoryBox = $category
        SendButton = $send
        PortalLink = $portalLink
        TicketStatus = $ticketStatus
    }
    return $panel
}

function Request-JiraCatalogIfTicket {
    if ($script:PanelOpen -and $script:WidgetPage -eq 'Ticket') { Ensure-JiraCatalog }
}

function Set-TicketStatusMessage {
    param([string]$Text, [bool]$IsError)
    if ($null -eq $script:WidgetUi) { return }
    $clean = ''
    if ($null -ne $Text) { $clean = ($Text.Trim() -replace '\s+', ' ') }
    if ($clean.Length -gt 140) { $clean = $clean.Substring(0, 140) }
    if ($IsError) {
        $script:WidgetUi.TicketStatus.ForeColor = Get-ThemeColor StatusError
    } else {
        $script:WidgetUi.TicketStatus.ForeColor = Get-ThemeColor Muted
    }
    $script:WidgetUi.TicketStatus.Text = $clean
    try { $script:WidgetUi.TicketStatus.Refresh() } catch { }
}

function Start-JiraCatalogLoad {
    if (-not (Test-JiraTicketMode)) { return }
    if ($script:JiraLoaded -or $script:JiraLoading) { return }
    if ($null -eq $script:WidgetUi) { return }
    Set-TicketStatusMessage -Text 'Загружаю проекты Jira...' -IsError $false
    Start-JiraWorker -Kind 'desks' -DeskId ''
}

function Ensure-JiraCatalog {
    Start-JiraCatalogLoad
}

function Load-JiraRequestTypes {
    if (-not (Test-JiraTicketMode)) { return }
    if ($null -eq $script:WidgetUi -or $script:JiraLoading) { return }
    $ui = $script:WidgetUi
    $index = [int]$ui.ProjectBox.SelectedIndex
    $desks = @($script:JiraDesks)
    if ($index -lt 0 -or $index -ge $desks.Count -or $null -eq $desks[$index]) {
        $script:JiraLoading = $true
        try {
            $script:JiraRequestTypes = @()
            $ui.CategoryBox.Items.Clear()
        } finally {
            $script:JiraLoading = $false
        }
        return
    }
    Set-TicketStatusMessage -Text 'Загружаю типы запросов...' -IsError $false
    Start-JiraWorker -Kind 'types' -DeskId ([string]$desks[$index].Id)
}

function Start-JiraWorker {
    param([string]$Kind, [string]$DeskId)
    if ($script:JiraLoading) { return }
    if ($null -eq $script:Cfg) { return }
    $script:JiraLoading = $true
    $script:JiraJobKind = $Kind
    $ps = $null
    try {
    $logicPath = Join-Path $PSScriptRoot 'DesktopSwitch.Logic.ps1'
    $baseUrl = [string]$script:Cfg.JiraBaseUrl
    $token = [string]$script:Cfg.ServiceDeskToken
    $ps = [powershell]::Create()
    [void]$ps.AddScript({
        param($LogicPath, $BaseUrl, $Token, $DeskId, $Kind)
        $ErrorActionPreference = 'Stop'
        Set-StrictMode -Version 2.0
        . $LogicPath
        function Read-DeskBody {
            param([string]$Url, [string]$Bearer)
            $request = [System.Net.HttpWebRequest]::Create($Url)
            $request.Method = 'GET'
            $request.Accept = 'application/json'
            $request.Timeout = 20000
            $request.ReadWriteTimeout = 20000
            $request.UserAgent = 'DesktopSwitch'
            $proxy = [System.Net.WebRequest]::GetSystemWebProxy()
            $proxy.Credentials = [System.Net.CredentialCache]::DefaultNetworkCredentials
            $request.Proxy = $proxy
            $request.Headers.Add('X-ExperimentalApi', 'opt-in')
            if (-not [string]::IsNullOrWhiteSpace($Bearer)) {
                $request.Headers.Add('Authorization', 'Bearer ' + $Bearer)
            } else {
                Set-WindowsRequestAuth -Request $request
            }
            $response = $null
            $reader = $null
            try {
                $response = $request.GetResponse()
                $reader = New-Object System.IO.StreamReader($response.GetResponseStream(), [System.Text.Encoding]::UTF8)
                return $reader.ReadToEnd()
            } catch [System.Net.WebException] {
                $detail = [string]$_.Exception.Message
                $errorResponse = $_.Exception.Response
                if ($null -ne $errorResponse) {
                    try {
                        $errorReader = New-Object System.IO.StreamReader($errorResponse.GetResponseStream(), [System.Text.Encoding]::UTF8)
                        $raw = $errorReader.ReadToEnd()
                        $errorReader.Close()
                        $parsed = Get-JiraErrorText $raw
                        if (-not [string]::IsNullOrWhiteSpace($parsed)) { $detail = $parsed }
                    } catch { }
                    try { $errorResponse.Close() } catch { }
                }
                throw $detail
            } finally {
                if ($null -ne $reader) { $reader.Close() }
                if ($null -ne $response) { $response.Close() }
            }
        }
        function Read-DeskPages {
            param([string]$PageKind, [string]$ServiceDeskId)
            $all = New-Object System.Collections.Generic.List[object]
            $start = 0
            $guard = 0
            while ($guard -lt 20) {
                $guard++
                $url = ''
                if ($PageKind -eq 'types') {
                    $url = Get-JiraRequestTypeUrl -BaseUrl $BaseUrl -ServiceDeskId $ServiceDeskId -Start $start -Limit 50
                } else {
                    $url = Get-JiraServiceDeskUrl -BaseUrl $BaseUrl -Start $start -Limit 50
                }
                if ([string]::IsNullOrWhiteSpace($url)) { break }
                $body = Read-DeskBody -Url $url -Bearer $Token
                $page = $null
                if (-not [string]::IsNullOrWhiteSpace($body)) { $page = $body | ConvertFrom-Json }
                $chunk = @()
                if ($PageKind -eq 'types') { $chunk = ConvertFrom-JiraRequestTypes $page }
                else { $chunk = ConvertFrom-JiraServiceDesks $page }
                foreach ($item in @($chunk)) {
                    if ($null -ne $item) { $all.Add($item) }
                }
                $next = Get-JiraNextStart -Page $page -FallbackStart $start
                if ($next -lt 0 -or $next -le $start) { break }
                $start = $next
            }
            return ,$all.ToArray()
        }
        $deskItems = @()
        $typeItems = @()
        if ($Kind -eq 'types') {
            $typeItems = Read-DeskPages -PageKind 'types' -ServiceDeskId $DeskId
        } else {
            $deskItems = Read-DeskPages -PageKind 'desks' -ServiceDeskId ''
            $firstId = ''
            if ($deskItems -is [System.Array] -and $deskItems.Length -gt 0 -and $null -ne $deskItems[0]) {
                $firstId = [string]$deskItems[0].Id
            }
            if (-not [string]::IsNullOrWhiteSpace($firstId)) {
                $typeItems = Read-DeskPages -PageKind 'types' -ServiceDeskId $firstId
            }
        }
        [pscustomobject]@{
            Ok = $true
            Desks = $deskItems
            Types = $typeItems
            Error = ''
        }
    }).AddArgument($logicPath).AddArgument($baseUrl).AddArgument($token).AddArgument($DeskId).AddArgument($Kind)
    $script:JiraPower = $ps
    $script:JiraAsync = $ps.BeginInvoke()
    if ($null -eq $script:JiraWait) {
        $script:JiraWait = New-Object System.Windows.Forms.Timer
        $script:JiraWait.Interval = 80
        $script:JiraWait.Add_Tick({
            try { Complete-JiraCatalogLoad } catch {
                $script:JiraLoading = $false
                Write-Log ("Каталог Jira не применился: {0}" -f $_.Exception.Message) 'WARN'
            }
        })
    }
    $script:JiraWait.Start()
    } catch {
        $script:JiraLoading = $false
        $script:JiraPower = $null
        $script:JiraAsync = $null
        if ($null -ne $ps) { try { $ps.Dispose() } catch { } }
        Write-Log ("Каталог Jira не запустился: {0}" -f $_.Exception.Message) 'WARN'
        Set-TicketStatusMessage -Text 'Не удалось загрузить проекты Jira.' -IsError $true
    }
}

function Complete-JiraCatalogLoad {
    if ($null -eq $script:JiraAsync -or -not $script:JiraAsync.IsCompleted) { return }
    if ($script:JiraWait) { $script:JiraWait.Stop() }
    $kind = [string]$script:JiraJobKind
    $power = $script:JiraPower
    $async = $script:JiraAsync
    $script:JiraPower = $null
    $script:JiraAsync = $null
    $script:JiraLoading = $false
    $result = $null
    $errorText = ''
    try {
        $output = @($power.EndInvoke($async))
        if ($output.Count -gt 0) { $result = $output[$output.Count - 1] }
    } catch {
        $errorText = [string]$_.Exception.Message
    } finally {
        try { $power.Dispose() } catch { }
    }
    if ($null -eq $script:WidgetUi) { return }
    if ($null -ne $result -and $null -ne $result.PSObject.Properties['Error'] -and -not [string]::IsNullOrWhiteSpace([string]$result.Error)) {
        $errorText = [string]$result.Error
    }
    if (-not [string]::IsNullOrWhiteSpace($errorText) -or $null -eq $result) {
        if ($kind -eq 'types') {
            Write-Log ("Типы запросов Jira не загрузились: {0}" -f $errorText) 'WARN'
            Set-TicketStatusMessage -Text 'Не удалось загрузить типы запросов.' -IsError $true
        } else {
            $script:JiraLoaded = $false
            Write-Log ("Проекты Jira не загрузились: {0}" -f $errorText) 'WARN'
            Set-TicketStatusMessage -Text 'Не удалось загрузить проекты Jira.' -IsError $true
        }
        return
    }
    if ($kind -eq 'types') {
        Set-JiraTypeItems -Types $result.Types
        return
    }
    Set-JiraDeskItems -Desks $result.Desks -Types $result.Types
}

function Set-JiraDeskItems {
    param($Desks, $Types)
    if ($null -eq $script:WidgetUi) { return }
    $ui = $script:WidgetUi
    $script:JiraLoading = $true
    try {
        $deskList = New-Object System.Collections.Generic.List[object]
        foreach ($desk in @($Desks)) {
            if ($null -ne $desk) { $deskList.Add($desk) }
        }
        $script:JiraDesks = $deskList.ToArray()
        $ui.ProjectBox.Items.Clear()
        foreach ($desk in $script:JiraDesks) {
            [void]$ui.ProjectBox.Items.Add((Format-JiraDeskLabel $desk))
        }
        $script:JiraLoaded = $true
        if ($ui.ProjectBox.Items.Count -eq 0) {
            $script:JiraRequestTypes = @()
            $ui.CategoryBox.Items.Clear()
            Set-TicketStatusMessage -Text 'В Jira нет доступных проектов helpdesk для этой учётной записи.' -IsError $true
            return
        }
        $ui.ProjectBox.SelectedIndex = 0
        Set-JiraTypeItems -Types $Types
    } finally {
        $script:JiraLoading = $false
    }
}

function Set-JiraTypeItems {
    param($Types)
    if ($null -eq $script:WidgetUi) { return }
    $ui = $script:WidgetUi
    $wasLoading = [bool]$script:JiraLoading
    $script:JiraLoading = $true
    try {
        $typeList = New-Object System.Collections.Generic.List[object]
        foreach ($kind in @($Types)) {
            if ($null -ne $kind) { $typeList.Add($kind) }
        }
        $script:JiraRequestTypes = $typeList.ToArray()
        $ui.CategoryBox.Items.Clear()
        foreach ($kind in $script:JiraRequestTypes) {
            $name = [string]$kind.Name
            if ([string]::IsNullOrWhiteSpace($name)) { $name = [string]$kind.Id }
            [void]$ui.CategoryBox.Items.Add($name)
        }
        if ($ui.CategoryBox.Items.Count -gt 0) {
            $ui.CategoryBox.SelectedIndex = 0
            Set-TicketStatusMessage -Text '' -IsError $false
        } else {
            Set-TicketStatusMessage -Text 'Для этого проекта нет типов запросов.' -IsError $true
        }
    } finally {
        if (-not $wasLoading) { $script:JiraLoading = $false }
    }
}

function Submit-SupportTicket {
    if ($null -eq $script:WidgetUi) { return }
    $api = ''
    if ($script:Cfg) { $api = [string]$script:Cfg.ServiceDeskApiUrl }
    $who = Get-WindowsSessionIdentity
    $ui = $script:WidgetUi
    $jira = Test-JiraTicketMode
    $portal = Get-WidgetPortalUrl
    if (-not $jira -and [string]::IsNullOrWhiteSpace($api)) {
        if (-not [string]::IsNullOrWhiteSpace($portal)) {
            Start-Process (Expand-ServiceDeskUrl -Url $portal -Login $who.Login -Computer $who.Computer)
        }
        return
    }
    $errors = Test-TicketDraft -Subject ([string]$ui.SubjectBox.Text) -Body ([string]$ui.BodyBox.Text)
    if ($errors.Count -gt 0) {
        Set-TicketStatusMessage -Text ([string]$errors[0]) -IsError $true
        return
    }
    if ($jira) {
        Submit-JiraRequest -Login $who.Login -Computer $who.Computer
        return
    }
    $categoryName = [string]$ui.CategoryBox.SelectedItem
    if ([string]::IsNullOrWhiteSpace($categoryName)) { $categoryName = 'Инцидент' }
    $chosen = Get-SelectedTicketProject
    if ((Test-WebhookProjectMode) -and [string]::IsNullOrWhiteSpace([string]$chosen.Id)) {
        Set-TicketStatusMessage -Text 'Выберите проект.' -IsError $true
        return
    }
    $payload = New-TicketPayload -Subject ([string]$ui.SubjectBox.Text) -Body ([string]$ui.BodyBox.Text) -Category $categoryName -Project $chosen.Name -ProjectId $chosen.Id -User $who.Login -Computer $who.Computer -CreatedAt ((Get-Date).ToString('o'))
    try {
        $code = Send-TicketRequest $payload
        Write-Log ("Заявка отправлена, ответ сервис-деска: {0}, проект: {1}, категория: {2}, пользователь: {3}, компьютер: {4}." -f $code, $payload.projectId, $payload.category, $payload.user, $payload.computer)
        $ui.SubjectBox.Text = ''
        $ui.BodyBox.Text = ''
        $ui.TicketStatus.ForeColor = Get-ThemeColor StatusOk
        $ui.TicketStatus.Text = 'Заявка отправлена.'
    } catch {
        Write-Log ("Заявку отправить не удалось: {0}" -f $_.Exception.Message) 'WARN'
        Set-TicketStatusMessage -Text 'Сервис-деск не принял заявку. Попробуйте ещё раз или откройте портал.' -IsError $true
    }
}

function Submit-JiraRequest {
    param([string]$Login, [string]$Computer)
    $ui = $script:WidgetUi
    $deskIndex = [int]$ui.ProjectBox.SelectedIndex
    $typeIndex = [int]$ui.CategoryBox.SelectedIndex
    $desks = $script:JiraDesks
    $types = $script:JiraRequestTypes
    if ($null -eq $desks) { $desks = @() }
    if ($null -eq $types) { $types = @() }
    if ($deskIndex -lt 0 -or $typeIndex -lt 0 -or $deskIndex -ge $desks.Count -or $typeIndex -ge $types.Count -or $null -eq $desks[$deskIndex] -or $null -eq $types[$typeIndex]) {
        Set-TicketStatusMessage -Text 'Выберите проект и тип запроса.' -IsError $true
        return
    }
    $desk = $desks[$deskIndex]
    $kind = $types[$typeIndex]
    $payload = New-JiraRequestPayload -ServiceDeskId ([string]$desk.Id) -RequestTypeId ([string]$kind.Id) -Summary ([string]$ui.SubjectBox.Text) -Description ([string]$ui.BodyBox.Text) -User $Login -Computer $Computer
    try {
        $json = $payload | ConvertTo-Json -Compress -Depth 6
        $url = Get-JiraCreateRequestUrl ([string]$script:Cfg.JiraBaseUrl)
        $result = Invoke-ServiceDeskRequest -Url $url -Method 'POST' -JsonBody $json -Jira
        $key = Get-JiraIssueKey ([string]$result.Body)
        Write-Log ("Заявка Jira создана: {0}, проект: {1}, тип: {2}, пользователь: {3}, компьютер: {4}." -f $key, $desk.ProjectKey, $kind.Name, $Login, $Computer)
        $ui.SubjectBox.Text = ''
        $ui.BodyBox.Text = ''
        $ui.TicketStatus.ForeColor = Get-ThemeColor StatusOk
        if ([string]::IsNullOrWhiteSpace($key)) { $ui.TicketStatus.Text = 'Заявка создана в Jira.' }
        else { $ui.TicketStatus.Text = ('Заявка {0} создана.' -f $key) }
    } catch {
        Write-Log ("Заявку в Jira отправить не удалось: {0}" -f $_.Exception.Message) 'WARN'
        $detail = [string]$_.Exception.Message
        if ([string]::IsNullOrWhiteSpace($detail)) { $detail = 'Jira не приняла заявку.' }
        else { $detail = 'Jira не приняла заявку. ' + $detail }
        Set-TicketStatusMessage -Text $detail -IsError $true
    }
}

function New-DesktopWidget {
    Add-Type -AssemblyName System.Windows.Forms
    Add-Type -AssemblyName System.Drawing
    Enable-AppThemeMode
    Sync-WidgetTheme -Force
    if (-not (Initialize-DesktopHost)) { $script:WidgetHost = [IntPtr]::Zero }
    $script:TabFont = New-UiFont 'Segoe UI' 9
    $script:TabFontBold = New-UiFont 'Segoe UI' 9 Bold
    $script:TitleFont = New-UiFont 'Segoe UI' 12 Bold
    $script:LogoFont = New-UiFont 'Segoe UI' 14 Bold
    $script:RowTitleFont = New-UiFont 'Segoe UI' 9 Bold
    $script:RowBodyFont = New-UiFont 'Segoe UI' 8
    $script:FieldFont = New-UiFont 'Segoe UI' 10
    $script:ButtonFont = New-UiFont 'Segoe UI' 10 Bold
    $script:IconFont = New-UiFont 'Segoe MDL2 Assets' 12
    if ($script:PanelForm -and -not $script:PanelForm.IsDisposed) {
        $previousExit = $script:AllowExit
        $script:AllowExit = $true
        try { $script:PanelForm.Dispose() } finally { $script:AllowExit = $previousExit }
    }
    $script:PanelForm = $null
    $launcher = New-LauncherButton
    $script:WidgetForm = $launcher
    Set-SupportBounds
    Ensure-TrayIcon
    Register-ThemeChanges
    Set-LauncherChrome
    Invoke-WindowChrome -Form $launcher -Launcher
    Apply-WidgetZOrder
    if (Test-ShowLauncher) { Write-Log 'Красная кнопка показана в углу экрана.' }
    else { Write-Log 'Кнопка скрыта. Программа остаётся у часов.' }
}

function Ensure-DesktopWidget {
    if ($script:WidgetForm -and -not $script:WidgetForm.IsDisposed -and $script:WidgetForm.IsHandleCreated) {
        Set-SupportBounds
        Update-LauncherSurface
        return
    }
    New-DesktopWidget
}

function Ensure-TrayIcon {
    if ($script:TrayIcon) { return }
    $icon = New-Object System.Windows.Forms.NotifyIcon
    $icon.Icon = [System.Drawing.SystemIcons]::Application
    $icon.Text = 'Аварийная папка'
    $icon.Visible = $true
    $script:TrayIconOwned = $false
    $menu = New-Object System.Windows.Forms.ContextMenuStrip
    if ($script:TabFont) { $menu.Font = $script:TabFont }
    else { $menu.Font = New-UiFont 'Segoe UI' 9 }
    $menu.Padding = New-Object System.Windows.Forms.Padding(6, 8, 6, 8)
    $menu.ShowImageMargin = $false
    $menu.ShowCheckMargin = $true
    $itemPad = New-Object System.Windows.Forms.Padding(6, 4, 12, 4)
    $openItem = New-Object System.Windows.Forms.ToolStripMenuItem
    $openItem.Text = 'Открыть папку'
    $openItem.Padding = $itemPad
    [void]$menu.Items.Add($openItem)
    [void]$menu.Items.Add((New-Object System.Windows.Forms.ToolStripSeparator))
    $buttonItem = New-Object System.Windows.Forms.ToolStripMenuItem
    $buttonItem.Text = 'Кнопка на экране'
    $buttonItem.CheckOnClick = $true
    $buttonItem.Checked = Test-ShowLauncher
    $buttonItem.Padding = $itemPad
    $script:LauncherMenuItem = $buttonItem
    [void]$menu.Items.Add($buttonItem)
    $topItem = New-Object System.Windows.Forms.ToolStripMenuItem
    $topItem.Text = 'Поверх всех окон'
    $topItem.CheckOnClick = $true
    $topItem.Checked = Test-StayOnTop
    $topItem.Padding = $itemPad
    $script:TopMenuItem = $topItem
    [void]$menu.Items.Add($topItem)
    if (Test-IsWindowsAdmin) {
        [void]$menu.Items.Add((New-Object System.Windows.Forms.ToolStripSeparator))
        $exitItem = New-Object System.Windows.Forms.ToolStripMenuItem
        $exitItem.Text = 'Выход'
        $exitItem.Padding = $itemPad
        [void]$menu.Items.Add($exitItem)
        $exitItem.Add_Click({ Stop-DesktopWidgetApp })
    }
    $openItem.Add_Click({ Open-EmergencyFolder })
    $buttonItem.Add_Click({
        $show = [bool]$script:LauncherMenuItem.Checked
        if ($script:State) {
            $script:State.ShowLauncher = $show
            Save-StateTable $script:State
        }
        Set-LauncherChrome
    })
    $topItem.Add_Click({
        $top = [bool]$script:TopMenuItem.Checked
        if ($script:State) {
            $script:State.StayOnTop = $top
            Save-StateTable $script:State
        }
        Apply-WidgetZOrder
    })
    $menu.Add_Opened({
        try {
            $strip = $menu
            if ($null -ne $this -and $this -is [System.Windows.Forms.ContextMenuStrip]) { $strip = $this }
            $width = [int]$strip.Width
            $height = [int]$strip.Height
            if ($width -lt 8 -or $height -lt 8) { return }
            $path = New-RoundedPath -Width $width -Height $height -Radius 12
            $strip.Region = New-Object System.Drawing.Region($path)
            $path.Dispose()
        } catch { }
    }.GetNewClosure())
    $icon.ContextMenuStrip = $menu
    $script:TrayMenu = $menu
    $script:TrayIcon = $icon
    Apply-TrayMenuPalette
    $icon.Add_DoubleClick({ Open-EmergencyFolder })
}

function Stop-DesktopWidgetApp {
    Unregister-ThemeChanges
    $script:AllowExit = $true
    if ($script:NewsPopup -and -not $script:NewsPopup.IsDisposed) { $script:NewsPopup.Close() }
    if ($script:PanelForm -and -not $script:PanelForm.IsDisposed) { $script:PanelForm.Close() }
    if ($script:WidgetForm -and -not $script:WidgetForm.IsDisposed) { $script:WidgetForm.Close() }
    if ($script:TrayIcon) {
        $ownedIcon = $null
        if ($script:TrayIconOwned) { $ownedIcon = $script:TrayIcon.Icon }
        try { $script:TrayIcon.Icon = $null } catch { }
        if ($null -ne $ownedIcon) {
            try { [DeskLayer]::DestroyIcon($ownedIcon.Handle) } catch { }
            try { $ownedIcon.Dispose() } catch { }
        }
        $script:TrayIcon.Visible = $false
        $script:TrayIcon.Dispose()
        $script:TrayIcon = $null
        $script:TrayIconOwned = $false
    }
    if ($script:WidgetContext) { $script:WidgetContext.ExitThread() }
}

function Receive-HttpText {
    param([string]$Url, [int]$TimeoutSec)
    $response = $null
    try {
        $request = [System.Net.HttpWebRequest]::Create($Url)
        $request.Method = 'GET'
        $request.Timeout = $TimeoutSec * 1000
        $request.ReadWriteTimeout = $TimeoutSec * 1000
        $request.UserAgent = 'DesktopSwitch'
        $request.AllowAutoRedirect = $true
        $proxy = [System.Net.WebRequest]::GetSystemWebProxy()
        $proxy.Credentials = [System.Net.CredentialCache]::DefaultNetworkCredentials
        $request.Proxy = $proxy
        $request.Credentials = [System.Net.CredentialCache]::DefaultNetworkCredentials
        $response = $request.GetResponse()
        $reader = New-Object System.IO.StreamReader($response.GetResponseStream(), [System.Text.Encoding]::UTF8)
        try { return $reader.ReadToEnd() } finally { $reader.Close() }
    } finally {
        if ($null -ne $response) { $response.Close() }
    }
}

function Set-NewsPopupBounds {
    if ($null -eq $script:NewsPopup -or $script:NewsPopup.IsDisposed -or -not $script:NewsPopup.Visible) { return }
    Add-Type -AssemblyName System.Windows.Forms
    $screen = [System.Windows.Forms.Screen]::PrimaryScreen.WorkingArea
    $margin = Get-WidgetMargin
    $corner = Get-WidgetCorner
    $button = 52
    $popupW = $script:NewsPopup.Width
    $popupH = $script:NewsPopup.Height
    $gap = 8
    $x = $screen.Left + $margin
    $y = $screen.Top + $margin
    if ($script:WidgetForm -and -not $script:WidgetForm.IsDisposed) {
        $x = $script:WidgetForm.Left
        $y = $script:WidgetForm.Top
    } else {
        if ($corner -eq 'BottomRight' -or $corner -eq 'TopRight') { $x = $screen.Right - $button - $margin }
        if ($corner -eq 'BottomRight' -or $corner -eq 'BottomLeft') { $y = $screen.Bottom - $button - $margin }
    }
    $rightSide = ($corner -eq 'BottomRight' -or $corner -eq 'TopRight')
    $bottomSide = ($corner -eq 'BottomRight' -or $corner -eq 'BottomLeft')
    if ($rightSide) { $px = $x - $gap - $popupW } else { $px = $x + $button + $gap }
    if ($bottomSide) { $py = $y + $button - $popupH } else { $py = $y }
    if ($px -lt ($screen.Left + 8)) { $px = $screen.Left + 8 }
    if (($px + $popupW) -gt ($screen.Right - 8)) { $px = $screen.Right - $popupW - 8 }
    if ($py -lt ($screen.Top + 8)) { $py = $screen.Top + 8 }
    if (($py + $popupH) -gt ($screen.Bottom - 8)) { $py = $screen.Bottom - $popupH - 8 }
    $script:NewsPopup.Location = New-Object System.Drawing.Point($px, $py)
}

function Hide-NewsPopup {
    if ($script:NewsPopupHiding) { return }
    $script:NewsPopupHiding = $true
    try {
        if ($script:NewsPopup -and -not $script:NewsPopup.IsDisposed -and $script:NewsPopup.Visible) {
            $script:NewsPopup.Hide()
        }
    } finally {
        $script:NewsPopupHiding = $false
    }
    Update-LauncherSurface
}

function Open-NewsFromPopup {
    Hide-NewsPopup
    Show-SupportPanel -Page News
}

function Ensure-NewsPopup {
    if ($script:NewsPopup -and -not $script:NewsPopup.IsDisposed) { return }
    Add-Type -AssemblyName System.Windows.Forms
    Add-Type -AssemblyName System.Drawing
    $ink = Get-ThemeColor Ink
    $muted = Get-ThemeColor Muted
    $canvas = Get-ThemeColor Canvas
    $ruleColor = Get-ThemeColor Rule
    $form = New-Object System.Windows.Forms.Form
    $form.FormBorderStyle = 'None'
    $form.ShowInTaskbar = $false
    $form.StartPosition = 'Manual'
    $form.TopMost = Test-StayOnTop
    $form.BackColor = $canvas
    $form.ClientSize = New-Object System.Drawing.Size(280, 120)
    $form.Font = $script:TabFont
    $form.Text = 'Новости'
    $header = New-Object System.Windows.Forms.Panel
    $header.SetBounds(0, 0, 280, 44)
    $header.BackColor = $canvas
    $title = New-Object System.Windows.Forms.Label
    $title.Text = 'Новости'
    $title.ForeColor = $ink
    $title.BackColor = $canvas
    $title.Font = $script:TabFontBold
    $title.AutoEllipsis = $true
    $title.SetBounds(12, 8, 220, 20)
    $title.Add_Click({ Open-NewsFromPopup })
    $close = New-Object System.Windows.Forms.Label
    $close.Text = [string][char]0xE711
    $close.SetBounds(232, 0, 48, 44)
    $close.TextAlign = 'MiddleCenter'
    $close.BackColor = $canvas
    $close.ForeColor = $ink
    $close.Font = $script:IconFont
    $close.Cursor = [System.Windows.Forms.Cursors]::Hand
    $close.Add_MouseEnter({ $this.ForeColor = Get-ThemeColor Ink; $this.BackColor = Get-ThemeColor Hover })
    $close.Add_MouseLeave({ $this.ForeColor = Get-ThemeColor Ink; $this.BackColor = Get-ThemeColor Canvas })
    $close.Add_MouseDown({
        $mouse = $null
        if ($args.Count -gt 1) { $mouse = $args[1] }
        if (-not (Test-LeftMousePress $mouse)) { return }
        Hide-NewsPopup
    })
    $headerRule = New-Object System.Windows.Forms.Panel
    $headerRule.SetBounds(12, 43, 256, 1)
    $headerRule.BackColor = $ruleColor
    $header.Controls.Add($title)
    $header.Controls.Add($close)
    $header.Controls.Add($headerRule)
    $close.BringToFront()
    $body = New-Object System.Windows.Forms.Panel
    $body.SetBounds(0, 44, 280, 84)
    $body.BackColor = $canvas
    $form.Controls.Add($header)
    $form.Controls.Add($body)
    $form.Add_FormClosing({
        if ($script:AllowExit) { return }
        if ($_.CloseReason -eq [System.Windows.Forms.CloseReason]::UserClosing) {
            $_.Cancel = $true
            Hide-NewsPopup
        }
    })
    $script:NewsPopup = $form
    $script:NewsPopupBody = $body
    $script:NewsPopupTitle = $title
    $script:NewsPopupHeader = $header
    $script:NewsPopupClose = $close
    $script:NewsPopupRule = $headerRule
    if ((Test-ShowLauncher) -and $script:WidgetForm -and -not $script:WidgetForm.IsDisposed) { $form.Owner = $script:WidgetForm }
}

function Show-NewsPopup {
    param($Notices)
    $items = @($Notices | Where-Object { $null -ne $_ })
    if ($items.Count -eq 0) { return }
    $script:PopupNotices = $items
    Ensure-DesktopWidget
    Ensure-NewsPopup
    $heading = 'Новости'
    foreach ($item in $items) {
        if ([string]$item.Kind -eq 'maintenance') { $heading = 'Технические работы' }
    }
    $script:NewsPopupTitle.Text = $heading
    Clear-ChildControls $script:NewsPopupBody
    $open = { Open-NewsFromPopup }
    $y = 6
    foreach ($item in $items) {
        $row = New-Object System.Windows.Forms.Panel
        $row.SetBounds(8, $y, 264, 44)
        $row.BackColor = Get-ThemeColor Canvas
        $row.Cursor = [System.Windows.Forms.Cursors]::Hand
        $row.Add_Click($open)
        $bar = New-Object System.Windows.Forms.Panel
        $bar.SetBounds(0, 4, 4, 36)
        $bar.BackColor = Get-ThemeColor Ink
        if ([string]$item.Kind -eq 'maintenance') { $bar.BackColor = Get-ThemeColor Maintenance }
        $bar.Add_Click($open)
        $caption = New-Object System.Windows.Forms.Label
        $caption.Text = [string]$item.Title
        $caption.Font = $script:RowTitleFont
        $caption.ForeColor = Get-ThemeColor Ink
        $caption.BackColor = Get-ThemeColor Canvas
        $caption.AutoEllipsis = $true
        $caption.SetBounds(12, 2, 248, 18)
        $caption.Cursor = [System.Windows.Forms.Cursors]::Hand
        $caption.Add_Click($open)
        $detail = New-Object System.Windows.Forms.Label
        $detail.Text = Get-NoticeSnippet ([string]$item.Body)
        $detail.Font = $script:RowBodyFont
        $detail.ForeColor = Get-ThemeColor Detail
        $detail.BackColor = Get-ThemeColor Canvas
        $detail.AutoEllipsis = $true
        $detail.SetBounds(12, 22, 248, 16)
        $detail.Cursor = [System.Windows.Forms.Cursors]::Hand
        $detail.Add_Click($open)
        $row.Controls.Add($bar)
        $row.Controls.Add($caption)
        $row.Controls.Add($detail)
        $script:NewsPopupBody.Controls.Add($row)
        $y += 48
    }
    $bodyHeight = $y + 6
    $script:NewsPopupBody.SetBounds(0, 44, 280, $bodyHeight)
    $total = 44 + $bodyHeight
    $script:NewsPopup.ClientSize = New-Object System.Drawing.Size(280, $total)
    $script:NewsPopup.Region = New-Object System.Drawing.Region((New-RoundedPath -Width 280 -Height $total -Radius 14))
    Invoke-WindowChrome -Form $script:NewsPopup
    if (-not $script:NewsPopup.Visible) { $script:NewsPopup.Show() }
    Set-NewsPopupBounds
    Update-LauncherSurface
}

function Get-JiraNewsNotices {
    if ([string]::IsNullOrWhiteSpace([string]$script:Cfg.JiraBaseUrl)) {
        throw 'Для новостей из Jira заполните JiraBaseUrl.'
    }
    $url = Get-JiraNewsSearchUrl -BaseUrl ([string]$script:Cfg.JiraBaseUrl) -Jql ([string]$script:Cfg.NewsJql)
    if ([string]::IsNullOrWhiteSpace($url)) { throw 'Запрос новостей Jira пуст.' }
    $newsToken = Resolve-NewsRequestToken -NewsToken ([string]$script:Cfg.NewsToken) -ServiceDeskToken ([string]$script:Cfg.ServiceDeskToken)
    $result = Invoke-ServiceDeskRequest -Url $url -Method 'GET' -Jira -Token $newsToken
    $parsed = $null
    if (-not [string]::IsNullOrWhiteSpace([string]$result.Body)) { $parsed = $result.Body | ConvertFrom-Json }
    return @(ConvertFrom-JiraNewsIssues -Page $parsed -BaseUrl ([string]$script:Cfg.JiraBaseUrl))
}

function Update-WidgetNews {
    $hasNewsUrl = $script:Cfg -and -not [string]::IsNullOrWhiteSpace([string]$script:Cfg.NewsUrl)
    $hasNewsJql = $script:Cfg -and -not [string]::IsNullOrWhiteSpace([string]$script:Cfg.NewsJql)
    if (-not $hasNewsUrl -and -not $hasNewsJql) {
        if (-not $script:NewsHintShown) {
            $script:NewsItems = @()
            $script:NewsHintShown = $true
            Update-WidgetChrome
        }
        return
    }
    $due = $script:LastNewsPoll -eq [datetime]::MinValue
    if (-not $due) {
        $waitSeconds = Get-NewsPollSeconds ([int]$script:Cfg.NewsPollMinutes)
        $due = ((Get-Date) - $script:LastNewsPoll).TotalSeconds -ge $waitSeconds
    }
    if (-not $due) { return }
    $script:LastNewsPoll = Get-Date
    try {
        $items = New-Object System.Collections.Generic.List[object]
        $loaded = $false
        if ($hasNewsUrl) {
            try {
                $text = Receive-HttpText -Url ([string]$script:Cfg.NewsUrl) -TimeoutSec 20
                foreach ($item in @(Sort-Notices (ConvertFrom-NewsFeed $text))) {
                    if ($null -ne $item) { $items.Add($item) }
                }
                $loaded = $true
            } catch {
                Write-Log ("Лента NewsUrl не загрузилась: {0}" -f $_.Exception.Message) 'WARN'
            }
        }
        if ($hasNewsJql) {
            try {
                foreach ($item in @(Get-JiraNewsNotices)) {
                    if ($null -ne $item) { $items.Add($item) }
                }
                $loaded = $true
            } catch {
                Write-Log ("Новости Jira не загрузились: {0}" -f $_.Exception.Message) 'WARN'
            }
        }
        if ($loaded) {
            $existingLog = @()
            if ($script:State) { $existingLog = $script:State.NoticeLog }
            $log = Merge-NoticeLog -Existing $existingLog -Incoming $items.ToArray() -Now (Get-Date)
            if ($script:State) { $script:State.NoticeLog = $log }
            $script:NewsItems = (ConvertTo-NoticeLogItems $log).ToArray()
            if ($script:NewsReading) { Mark-NoticesOpened }
        }
        Import-ReadNoticeIds
        $seen = @()
        if ($script:State) {
            $seen = Merge-NoticeIds -Existing $script:State.SeenNoticeIds -More $script:State.ReadNoticeIds
        }
        $fresh = @(Get-NoticesToShow -Items $items.ToArray() -SeenIds $seen -Max 3)
        if ($fresh.Count -gt 0) {
            try {
                Show-NewsPopup -Notices $fresh
            } catch {
                $balloon = Format-NoticeBalloon $fresh
                if ($null -ne $balloon) { Show-UserNotice -Message ([string]$balloon.Text) -Title ([string]$balloon.Title) }
                Write-Log ("Всплывающее окно новостей не открылось: {0}" -f $_.Exception.Message) 'WARN'
            }
            $freshIds = New-Object System.Collections.Generic.List[string]
            foreach ($item in $fresh) {
                if ($null -eq $item) { continue }
                $id = (Get-NoticeField $item 'Id').Trim()
                if ([string]::IsNullOrWhiteSpace($id)) { continue }
                $freshIds.Add($id)
            }
            if ($script:State) {
                $script:State.SeenNoticeIds = Merge-NoticeIds -Existing $script:State.SeenNoticeIds -More $freshIds.ToArray()
                Save-StateTable $script:State
            }
        } elseif ($script:State) {
            Save-StateTable $script:State
        }
    } catch {
        Write-Log ("Новости не загрузились: {0}" -f $_.Exception.Message) 'WARN'
    }
    Update-WidgetChrome
}

function Show-NewsDialog {
    Show-SupportPanel -Page News
}

function Invoke-ServiceDeskRequest {
    param(
        [string]$Url,
        [string]$Method,
        [string]$JsonBody,
        [string]$Token,
        [switch]$Jira
    )
    if ([string]::IsNullOrWhiteSpace($Url)) { throw 'Адрес запроса не задан.' }
    $verb = $Method.Trim().ToUpperInvariant()
    $response = $null
    $reader = $null
    try {
        $request = [System.Net.HttpWebRequest]::Create($Url)
        $request.Method = $verb
        $request.Accept = 'application/json'
        $request.Timeout = 20000
        $request.ReadWriteTimeout = 20000
        $request.UserAgent = 'DesktopSwitch'
        $proxy = [System.Net.WebRequest]::GetSystemWebProxy()
        $proxy.Credentials = [System.Net.CredentialCache]::DefaultNetworkCredentials
        $request.Proxy = $proxy
        if ($Jira) { $request.Headers.Add('X-ExperimentalApi', 'opt-in') }
        $token = [string]$Token
        if ([string]::IsNullOrWhiteSpace($token) -and $script:Cfg) { $token = [string]$script:Cfg.ServiceDeskToken }
        if (-not [string]::IsNullOrWhiteSpace($token)) {
            $request.Headers.Add('Authorization', 'Bearer ' + $token)
        } else {
            Set-WindowsRequestAuth -Request $request
            if (-not $script:WindowsAuthLogged) {
                $script:WindowsAuthLogged = $true
                Write-Log 'Jira: вход текущей учётной записью Windows (Negotiate). Адрес должен быть именем сервера, не IP.'
            }
        }
        if ($verb -eq 'POST') {
            $bytes = [System.Text.Encoding]::UTF8.GetBytes([string]$JsonBody)
            $request.ContentType = 'application/json; charset=utf-8'
            $request.ContentLength = $bytes.Length
            $stream = $request.GetRequestStream()
            $stream.Write($bytes, 0, $bytes.Length)
            $stream.Close()
        }
        $response = $request.GetResponse()
        $reader = New-Object System.IO.StreamReader($response.GetResponseStream(), [System.Text.Encoding]::UTF8)
        $text = $reader.ReadToEnd()
        return [pscustomobject]@{
            StatusCode = [int]$response.StatusCode
            Body = $text
        }
    } catch [System.Net.WebException] {
        $detail = ''
        $errorResponse = $_.Exception.Response
        if ($null -ne $errorResponse) {
            try {
                $errorReader = New-Object System.IO.StreamReader($errorResponse.GetResponseStream(), [System.Text.Encoding]::UTF8)
                $detail = Get-JiraErrorText ($errorReader.ReadToEnd())
                $errorReader.Close()
            } catch { }
            try { $errorResponse.Close() } catch { }
        }
        if ([string]::IsNullOrWhiteSpace($detail)) { $detail = [string]$_.Exception.Message }
        $statusCode = 0
        try { if ($null -ne $errorResponse) { $statusCode = [int]$errorResponse.StatusCode } } catch { $statusCode = 0 }
        if ($statusCode -eq 401 -and [string]::IsNullOrWhiteSpace($token)) {
            $detail = $detail + ' Вход Windows не принят. JiraBaseUrl должен быть именем сервера, не IP-адресом, а REST API должен разрешать Negotiate.'
        }
        throw $detail
    } finally {
        if ($null -ne $reader) { $reader.Close() }
        if ($null -ne $response) { $response.Close() }
    }
}

function Receive-JiraServiceDesks {
    $all = New-Object System.Collections.Generic.List[object]
    $start = 0
    $guard = 0
    while ($guard -lt 20) {
        $guard++
        $url = Get-JiraServiceDeskUrl -BaseUrl ([string]$script:Cfg.JiraBaseUrl) -Start $start -Limit 50
        $result = Invoke-ServiceDeskRequest -Url $url -Method 'GET' -JsonBody '' -Jira
        $parsed = $null
        if (-not [string]::IsNullOrWhiteSpace([string]$result.Body)) { $parsed = $result.Body | ConvertFrom-Json }
        $pageDesks = ConvertFrom-JiraServiceDesks $parsed
        foreach ($desk in $pageDesks) {
            if ($null -ne $desk) { $all.Add($desk) }
        }
        $next = Get-JiraNextStart -Page $parsed -FallbackStart $start
        if ($next -lt 0 -or $next -le $start) { break }
        $start = $next
    }
    return ,$all.ToArray()
}

function Receive-JiraRequestTypes {
    param([string]$ServiceDeskId)
    $all = New-Object System.Collections.Generic.List[object]
    $start = 0
    $guard = 0
    while ($guard -lt 20) {
        $guard++
        $url = Get-JiraRequestTypeUrl -BaseUrl ([string]$script:Cfg.JiraBaseUrl) -ServiceDeskId $ServiceDeskId -Start $start -Limit 50
        $result = Invoke-ServiceDeskRequest -Url $url -Method 'GET' -JsonBody '' -Jira
        $parsed = $null
        if (-not [string]::IsNullOrWhiteSpace([string]$result.Body)) { $parsed = $result.Body | ConvertFrom-Json }
        $pageTypes = ConvertFrom-JiraRequestTypes $parsed
        foreach ($kind in $pageTypes) {
            if ($null -ne $kind) { $all.Add($kind) }
        }
        $next = Get-JiraNextStart -Page $parsed -FallbackStart $start
        if ($next -lt 0 -or $next -le $start) { break }
        $start = $next
    }
    return ,$all.ToArray()
}

function Send-TicketRequest {
    param($Payload)
    $json = $Payload | ConvertTo-Json -Compress
    $result = Invoke-ServiceDeskRequest -Url ([string]$script:Cfg.ServiceDeskApiUrl) -Method 'POST' -JsonBody $json
    return [int]$result.StatusCode
}

function Show-TicketDialog {
    Show-SupportPanel -Page Ticket
}

function Open-EmergencyFolder {
    $path = ''
    if ($script:Cfg) { $path = [string]$script:Cfg.EmergencyFolder }
    if ([string]::IsNullOrWhiteSpace($path)) {
        Show-StartupProblem 'В config.json не указана папка EmergencyFolder.'
        return
    }
    if (-not (Test-Path -LiteralPath $path)) {
        Show-StartupProblem ('Папка не найдена: ' + $path)
        return
    }
    Write-Log ("Открываю папку {0}." -f $path)
    Start-Process -FilePath 'explorer.exe' -ArgumentList @($path)
}

function Start-WidgetApplication {
    Add-Type -AssemblyName System.Windows.Forms
    Add-Type -AssemblyName System.Drawing
    [System.Windows.Forms.Application]::EnableVisualStyles()
    $script:WidgetContext = New-Object System.Windows.Forms.ApplicationContext
    # The button has to exist before the first network check. That check can sit
    # on a share or on the shell path, and until it returns the window never appeared.
    try { Ensure-DesktopWidget } catch {
        Write-Log ("Сбой виджета: {0}" -f $_.Exception.ToString()) 'ERROR'
        throw
    }
    $script:MonitorTimerReady = $false
    $script:MonitorTimer = New-Object System.Windows.Forms.Timer
    $script:MonitorTimer.Interval = 400
    $script:MonitorTimer.Add_Tick({
        if (-not $script:MonitorTimerReady) {
            $script:MonitorTimerReady = $true
            $script:MonitorTimer.Interval = [Math]::Max(5000, ([int]$script:Cfg.CheckIntervalSeconds * 1000))
        }
        try { Invoke-MonitorCycle } catch { Write-Log ("Сбой цикла: {0}" -f $_.Exception.Message) 'ERROR' }
        try { Ensure-DesktopWidget } catch { Write-Log ("Сбой виджета: {0}" -f $_.Exception.Message) 'ERROR' }
    })
    $script:MonitorTimer.Start()
    [System.Windows.Forms.Application]::Run($script:WidgetContext)
}
