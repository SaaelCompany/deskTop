# Красный круг с белым восклицательным знаком. Окна в панели задач нет.
# Показ и скрытие решает DesktopSwitch.ps1.

Set-StrictMode -Version 2.0

$script:LauncherForm = $null
$script:LauncherTip = $null
$script:LastClick = [datetime]::MinValue
$script:ButtonMargin = 16

$script:ButtonSource = @'
using System;
using System.Drawing;
using System.Drawing.Drawing2D;
using System.Windows.Forms;

public class OfflineButtonForm : Form {
    const int WM_MOUSEACTIVATE = 0x0021;
    const int MA_NOACTIVATE = 3;
    readonly int markSize;

    public OfflineButtonForm(int markSize) {
        this.markSize = markSize;
        FormBorderStyle = FormBorderStyle.None;
        ShowInTaskbar = false;
        TopMost = true;
        StartPosition = FormStartPosition.Manual;
        Size = new Size(markSize, markSize);
        BackColor = Color.FromArgb(220, 38, 38);
        Cursor = Cursors.Hand;
        Text = "\u0421\u0435\u0440\u0432\u0438\u0441\u043d\u0430\u044f \u0441\u043b\u0443\u0436\u0431\u0430";
        SetStyle(ControlStyles.AllPaintingInWmPaint | ControlStyles.UserPaint | ControlStyles.OptimizedDoubleBuffer, true);
        using (GraphicsPath path = new GraphicsPath()) {
            path.AddEllipse(0, 0, markSize - 1, markSize - 1);
            Region = new Region(path);
        }
    }

    protected override bool ShowWithoutActivation {
        get { return true; }
    }

    protected override CreateParams CreateParams {
        get {
            CreateParams cp = base.CreateParams;
            cp.ExStyle |= 0x00000080 | 0x08000000;
            return cp;
        }
    }

    protected override void WndProc(ref Message m) {
        if (m.Msg == WM_MOUSEACTIVATE) {
            m.Result = (IntPtr)MA_NOACTIVATE;
            return;
        }
        base.WndProc(ref m);
    }

    protected override void OnPaint(PaintEventArgs e) {
        Graphics g = e.Graphics;
        g.SmoothingMode = SmoothingMode.AntiAlias;
        using (SolidBrush brush = new SolidBrush(Color.FromArgb(220, 38, 38))) {
            g.FillEllipse(brush, 1, 1, markSize - 3, markSize - 3);
        }
        using (Pen pen = new Pen(Color.White, 4f)) {
            pen.StartCap = LineCap.Round;
            pen.EndCap = LineCap.Round;
            float x = markSize / 2f;
            g.DrawLine(pen, x, markSize * 0.24f, x, markSize * 0.62f);
        }
        using (SolidBrush dot = new SolidBrush(Color.White)) {
            float d = markSize * 0.14f;
            float x = (markSize - d) / 2f;
            g.FillEllipse(dot, x, markSize * 0.70f, d, d);
        }
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
    $tip.SetToolTip($form, 'Нет интернета. Открыть C:\Users\Public\Desktop')
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
            [System.Windows.Forms.MessageBox]::Show($text, 'Сервисная служба') | Out-Null
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
