# Красный круг с белым восклицательным знаком. Окна в панели задач нет.
# Край круга сглажен: окно прямоугольное, лишние пиксели прозрачные.
# Показ и скрытие решает EmergencyFolder.ps1.

Set-StrictMode -Version 2.0

$script:LauncherForm = $null
$script:LauncherTip = $null
$script:LastClick = [datetime]::MinValue
$script:ButtonMargin = 16

$script:ButtonSource = @'
using System;
using System.Drawing;
using System.Drawing.Drawing2D;
using System.Drawing.Imaging;
using System.Runtime.InteropServices;
using System.Windows.Forms;

public class OfflineButtonForm : Form {
    const int WM_MOUSEACTIVATE = 0x0021;
    const int WM_NCHITTEST = 0x0084;
    const int MA_NOACTIVATE = 3;
    const int HTTRANSPARENT = -1;
    const byte AC_SRC_OVER = 0;
    const byte AC_SRC_ALPHA = 1;
    const int ULW_ALPHA = 2;

    readonly int markSize;

    [StructLayout(LayoutKind.Sequential, Pack = 1)]
    struct POINT {
        public int X;
        public int Y;
        public POINT(int x, int y) { X = x; Y = y; }
    }

    [StructLayout(LayoutKind.Sequential, Pack = 1)]
    struct SIZE {
        public int Width;
        public int Height;
        public SIZE(int width, int height) { Width = width; Height = height; }
    }

    [StructLayout(LayoutKind.Sequential, Pack = 1)]
    struct BLENDFUNCTION {
        public byte BlendOp;
        public byte BlendFlags;
        public byte SourceConstantAlpha;
        public byte AlphaFormat;
    }

    [StructLayout(LayoutKind.Sequential, Pack = 1)]
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

    [DllImport("user32.dll", SetLastError = true)]
    static extern bool UpdateLayeredWindow(IntPtr hwnd, IntPtr hdcDst, ref POINT pptDst, ref SIZE psize, IntPtr hdcSrc, ref POINT pptSrc, int crKey, ref BLENDFUNCTION pblend, int dwFlags);

    [DllImport("user32.dll", SetLastError = true)]
    static extern IntPtr GetDC(IntPtr hwnd);

    [DllImport("user32.dll")]
    static extern int ReleaseDC(IntPtr hwnd, IntPtr hdc);

    [DllImport("gdi32.dll", SetLastError = true)]
    static extern IntPtr CreateCompatibleDC(IntPtr hdc);

    [DllImport("gdi32.dll")]
    static extern bool DeleteDC(IntPtr hdc);

    [DllImport("gdi32.dll")]
    static extern IntPtr SelectObject(IntPtr hdc, IntPtr hgdiobj);

    [DllImport("gdi32.dll")]
    static extern bool DeleteObject(IntPtr hObject);

    [DllImport("gdi32.dll", SetLastError = true)]
    static extern IntPtr CreateDIBSection(IntPtr hdc, ref BITMAPINFOHEADER pbmi, uint usage, out IntPtr ppvBits, IntPtr hSection, uint offset);

    public OfflineButtonForm(int markSize) {
        this.markSize = markSize;
        FormBorderStyle = FormBorderStyle.None;
        ShowInTaskbar = false;
        TopMost = true;
        StartPosition = FormStartPosition.Manual;
        Size = new Size(markSize, markSize);
        Cursor = Cursors.Hand;
        Text = "Emergency folder";
    }

    public static Bitmap DrawMark(int markSize) {
        Bitmap bitmap = new Bitmap(markSize, markSize, PixelFormat.Format32bppPArgb);
        int scale = 4;
        int big = markSize * scale;
        using (Bitmap hi = new Bitmap(big, big, PixelFormat.Format32bppArgb)) {
            using (Graphics g = Graphics.FromImage(hi)) {
                g.SmoothingMode = SmoothingMode.AntiAlias;
                g.PixelOffsetMode = PixelOffsetMode.HighQuality;
                g.CompositingQuality = CompositingQuality.HighQuality;
                g.Clear(Color.Transparent);
                float pad = 2f * scale;
                float diameter = big - (pad * 2f);
                using (SolidBrush brush = new SolidBrush(Color.FromArgb(220, 38, 38))) {
                    g.FillEllipse(brush, pad, pad, diameter, diameter);
                }
                using (Pen pen = new Pen(Color.White, 4f * scale)) {
                    pen.StartCap = LineCap.Round;
                    pen.EndCap = LineCap.Round;
                    float x = big / 2f;
                    g.DrawLine(pen, x, big * 0.26f, x, big * 0.62f);
                }
                using (SolidBrush dot = new SolidBrush(Color.White)) {
                    float d = big * 0.12f;
                    float x = (big - d) / 2f;
                    g.FillEllipse(dot, x, big * 0.70f, d, d);
                }
            }
            using (Graphics g = Graphics.FromImage(bitmap)) {
                g.CompositingMode = CompositingMode.SourceCopy;
                g.InterpolationMode = InterpolationMode.HighQualityBicubic;
                g.PixelOffsetMode = PixelOffsetMode.HighQuality;
                g.CompositingQuality = CompositingQuality.HighQuality;
                g.DrawImage(hi, new Rectangle(0, 0, markSize, markSize));
            }
        }
        return bitmap;
    }

    protected override bool ShowWithoutActivation {
        get { return true; }
    }

    protected override CreateParams CreateParams {
        get {
            CreateParams cp = base.CreateParams;
            cp.ExStyle |= 0x00080000 | 0x00000080 | 0x08000000;
            return cp;
        }
    }

    protected override void OnHandleCreated(EventArgs e) {
        base.OnHandleCreated(e);
        ApplySurface();
    }

    protected override void OnLocationChanged(EventArgs e) {
        base.OnLocationChanged(e);
        if (IsHandleCreated) ApplySurface();
    }

    protected override void WndProc(ref Message m) {
        if (m.Msg == WM_MOUSEACTIVATE) {
            m.Result = (IntPtr)MA_NOACTIVATE;
            return;
        }
        if (m.Msg == WM_NCHITTEST) {
            int packed = m.LParam.ToInt32();
            int screenX = (short)(packed & 0xFFFF);
            int screenY = (short)((packed >> 16) & 0xFFFF);
            Point local = PointToClient(new Point(screenX, screenY));
            float center = markSize / 2f;
            float dx = local.X - center;
            float dy = local.Y - center;
            float radius = center - 2f;
            if ((dx * dx) + (dy * dy) > radius * radius) {
                m.Result = (IntPtr)HTTRANSPARENT;
                return;
            }
        }
        base.WndProc(ref m);
    }

    void ApplySurface() {
        using (Bitmap bitmap = DrawMark(markSize)) {
            Present(bitmap);
        }
    }

    void Present(Bitmap bitmap) {
        BITMAPINFOHEADER header = new BITMAPINFOHEADER();
        header.biSize = Marshal.SizeOf(typeof(BITMAPINFOHEADER));
        header.biWidth = bitmap.Width;
        header.biHeight = -bitmap.Height;
        header.biPlanes = 1;
        header.biBitCount = 32;
        header.biCompression = 0;

        IntPtr screen = GetDC(IntPtr.Zero);
        IntPtr bits;
        IntPtr dib = CreateDIBSection(screen, ref header, 0, out bits, IntPtr.Zero, 0);
        if (dib == IntPtr.Zero) {
            ReleaseDC(IntPtr.Zero, screen);
            return;
        }

        BitmapData data = bitmap.LockBits(new Rectangle(0, 0, bitmap.Width, bitmap.Height), ImageLockMode.ReadOnly, PixelFormat.Format32bppPArgb);
        int rowBytes = bitmap.Width * 4;
        byte[] raw = new byte[rowBytes * bitmap.Height];
        for (int y = 0; y < bitmap.Height; y++) {
            IntPtr row = new IntPtr(data.Scan0.ToInt64() + (data.Stride * y));
            Marshal.Copy(row, raw, y * rowBytes, rowBytes);
        }
        bitmap.UnlockBits(data);
        Marshal.Copy(raw, 0, bits, raw.Length);

        IntPtr mem = CreateCompatibleDC(screen);
        IntPtr old = SelectObject(mem, dib);
        POINT dst = new POINT(Left, Top);
        SIZE size = new SIZE(bitmap.Width, bitmap.Height);
        POINT src = new POINT(0, 0);
        BLENDFUNCTION blend = new BLENDFUNCTION();
        blend.BlendOp = AC_SRC_OVER;
        blend.SourceConstantAlpha = 255;
        blend.AlphaFormat = AC_SRC_ALPHA;
        UpdateLayeredWindow(Handle, screen, ref dst, ref size, mem, ref src, 0, ref blend, ULW_ALPHA);
        SelectObject(mem, old);
        DeleteObject(dib);
        DeleteDC(mem);
        ReleaseDC(IntPtr.Zero, screen);
    }
}
'@

function Initialize-LauncherWindow {
    Add-Type -AssemblyName System.Windows.Forms
    Add-Type -AssemblyName System.Drawing
    if (-not ('OfflineButtonForm' -as [type])) {
        Add-Type -TypeDefinition $script:ButtonSource -ReferencedAssemblies @('System.Windows.Forms', 'System.Drawing')
    }
    $form = New-Object OfflineButtonForm 52
    $form.add_MouseDown({
        param($sender, $e)
        if ($e.Button -ne [System.Windows.Forms.MouseButtons]::Left) { return }
        $now = Get-Date
        if (($now - $script:LastClick).TotalMilliseconds -lt 400) { return }
        $script:LastClick = $now
        Open-PublicDesktop
    })
    $form.add_FormClosing({
        param($sender, $e)
        if ($e.CloseReason -eq [System.Windows.Forms.CloseReason]::UserClosing) {
            $e.Cancel = $true
        }
    })
    $tip = New-Object System.Windows.Forms.ToolTip
    $tip.SetToolTip($form, 'Контроллер домена недоступен. Открыть C:\Users\Public\Desktop')
    $script:LauncherTip = $tip
    $script:LauncherForm = $form
}

function Move-LauncherToCorner {
    $form = $script:LauncherForm
    if ($null -eq $form) { return }
    $area = [System.Windows.Forms.Screen]::PrimaryScreen.WorkingArea
    $x = $area.Right - $form.Width - $script:ButtonMargin
    $y = $area.Bottom - $form.Height - $script:ButtonMargin
    if ($x -lt $area.Left) { $x = $area.Left }
    if ($y -lt $area.Top) { $y = $area.Top }
    $form.Location = New-Object System.Drawing.Point([int]$x, [int]$y)
}

function Open-PublicDesktop {
    $folder = Get-PublicDesktopPath
    try {
        if (-not (Test-Path -LiteralPath $folder)) {
            New-Item -ItemType Directory -Path $folder -Force | Out-Null
        }
        Start-Process -FilePath 'explorer.exe' -ArgumentList $folder
        if (Get-Command Write-Log -ErrorAction SilentlyContinue) {
            Write-Log ("Открыта папка {0}." -f $folder)
        }
    } catch {
        $text = "Не удалось открыть папку $folder.`r`n`r`n" + $_.Exception.Message
        if (Get-Command Write-Log -ErrorAction SilentlyContinue) {
            Write-Log $text 'ERROR'
        }
        try {
            [System.Windows.Forms.MessageBox]::Show($text, 'Emergency folder') | Out-Null
        } catch {
            Write-Host $text
        }
    }
}

function Set-LauncherVisible {
    param([bool]$Visible)
    $form = $script:LauncherForm
    if ($null -eq $form) { return }
    if ($Visible) {
        Move-LauncherToCorner
        if (-not $form.Visible) { $form.Show() }
    } elseif ($form.Visible) {
        $form.Hide()
    }
}

function Test-LauncherVisible {
    $form = $script:LauncherForm
    if ($null -eq $form) { return $false }
    return [bool]$form.Visible
}
