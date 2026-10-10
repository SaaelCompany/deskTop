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
$script:AllowExit = $false
$script:PanelOpen = $false
$script:PanelHiding = $false
$script:WidgetPage = 'News'
$script:LauncherHot = $false
$script:LauncherClickAt = [datetime]::MinValue
$script:WidgetContext = $null
$script:DesktopMode = ''
$script:DesktopVerdict = ''

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
    $color = [System.Drawing.Color]::FromArgb(232, 228, 255)
    if ($mode -eq 'Local') {
        $text = 'Локальный стол'
        $color = [System.Drawing.Color]::FromArgb(255, 205, 199)
    } elseif ($mode -eq 'Network') {
        $text = 'Сетевой стол'
        if ($verdict -eq 'Online') { $color = [System.Drawing.Color]::FromArgb(186, 245, 214) }
    }
    return [pscustomobject]@{ Text = $text; Color = $color }
}

function Format-NoticeStamp {
    param([string]$Value)
    if ([string]::IsNullOrWhiteSpace($Value)) { return '' }
    $when = [datetime]::MinValue
    $parsed = [datetime]::TryParse($Value, [System.Globalization.CultureInfo]::InvariantCulture, [System.Globalization.DateTimeStyles]::RoundtripKind, [ref]$when)
    if (-not $parsed) { $parsed = [datetime]::TryParse($Value, [ref]$when) }
    if (-not $parsed) { return '' }
    return $when.ToString('dd.MM HH:mm')
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
    return [string]::Join("`n", $parts.ToArray())
}

function Get-UnopenedNoticeCount {
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
    foreach ($item in @($script:NewsItems)) {
        if ($null -eq $item) { continue }
        $id = [string]$item.Id
        if ([string]::IsNullOrWhiteSpace($id)) { continue }
        $script:OpenedNoticeIds[$id] = $true
    }
}

function Set-SupportBounds {
    Add-Type -AssemblyName System.Windows.Forms
    $screen = [System.Windows.Forms.Screen]::PrimaryScreen.WorkingArea
    $margin = Get-WidgetMargin
    $corner = Get-WidgetCorner
    $button = 60
    $panelW = 360
    $panelH = 520
    $gap = 12
    $x = $screen.Left + $margin
    $y = $screen.Top + $margin
    if ($corner -eq 'BottomRight' -or $corner -eq 'TopRight') { $x = $screen.Right - $button - $margin }
    if ($corner -eq 'BottomRight' -or $corner -eq 'BottomLeft') { $y = $screen.Bottom - $button - $margin }
    if ($script:WidgetForm -and -not $script:WidgetForm.IsDisposed) {
        $script:WidgetForm.Location = New-Object System.Drawing.Point($x, $y)
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

function New-FlatButton {
    param([string]$Text, [System.Drawing.Point]$Location, [System.Drawing.Size]$Size)
    $button = New-Object System.Windows.Forms.Button
    $button.Text = $Text
    $button.Location = $Location
    $button.Size = $Size
    $button.FlatStyle = 'Flat'
    $button.BackColor = [System.Drawing.Color]::FromArgb(109, 74, 255)
    $button.ForeColor = [System.Drawing.Color]::White
    $button.Font = $script:TabFontBold
    $button.FlatAppearance.BorderSize = 0
    $button.FlatAppearance.MouseOverBackColor = [System.Drawing.Color]::FromArgb(90, 58, 230)
    $button.Cursor = [System.Windows.Forms.Cursors]::Hand
    return $button
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

function Update-NewsRows {
    if ($null -eq $script:WidgetUi) { return }
    $list = $script:WidgetUi.NewsList
    Clear-ChildControls $list
    $items = @($script:NewsItems | Where-Object { $null -ne $_ })
    if ($items.Count -eq 0) {
        $empty = New-Object System.Windows.Forms.Label
        $empty.Text = 'Пока нет сообщений'
        $empty.TextAlign = 'MiddleCenter'
        $empty.Font = $script:TabFontBold
        $empty.ForeColor = [System.Drawing.Color]::FromArgb(31, 41, 51)
        $empty.BackColor = [System.Drawing.Color]::White
        $empty.SetBounds(16, 78, 328, 24)
        $hint = New-Object System.Windows.Forms.Label
        $hint.Text = 'Здесь будут новости и технические работы.'
        $hint.TextAlign = 'MiddleCenter'
        $hint.Font = $script:TabFont
        $hint.ForeColor = [System.Drawing.Color]::FromArgb(107, 114, 128)
        $hint.BackColor = [System.Drawing.Color]::White
        $hint.SetBounds(16, 106, 328, 36)
        $list.Controls.Add($empty)
        $list.Controls.Add($hint)
        return
    }
    $y = 4
    $rowWidth = 336
    foreach ($item in $items) {
        $url = [string]$item.Url
        $row = New-Object System.Windows.Forms.Panel
        $row.SetBounds(8, $y, $rowWidth, 74)
        $row.BackColor = [System.Drawing.Color]::White
        if ([string]$item.Kind -eq 'maintenance') { $row.BackColor = [System.Drawing.Color]::FromArgb(255, 247, 237) }
        $row.Tag = $url
        $rowColor = $row.BackColor
        $dot = New-Object System.Windows.Forms.Panel
        $dot.SetBounds(10, 14, 8, 8)
        $dotColor = [System.Drawing.Color]::FromArgb(59, 130, 246)
        if ([string]$item.Kind -eq 'maintenance') { $dotColor = [System.Drawing.Color]::FromArgb(230, 126, 34) }
        $dot.BackColor = $dotColor
        $dotPath = New-Object System.Drawing.Drawing2D.GraphicsPath
        $dotPath.AddEllipse(0, 0, 8, 8)
        $dot.Region = New-Object System.Drawing.Region($dotPath)
        $dot.Tag = $url
        $title = New-Object System.Windows.Forms.Label
        $title.Text = [string]$item.Title
        $title.Font = $script:RowTitleFont
        $title.ForeColor = [System.Drawing.Color]::FromArgb(31, 41, 51)
        $title.BackColor = $rowColor
        $title.AutoEllipsis = $true
        $title.SetBounds(26, 6, 196, 18)
        $title.Tag = $url
        $when = New-Object System.Windows.Forms.Label
        $when.Text = Format-NoticeStamp ([string]$item.PublishedAt)
        $when.Font = $script:RowBodyFont
        $when.ForeColor = [System.Drawing.Color]::FromArgb(107, 114, 128)
        $when.BackColor = $rowColor
        $when.TextAlign = 'MiddleRight'
        $when.SetBounds(224, 6, 100, 18)
        $when.Tag = $url
        $body = New-Object System.Windows.Forms.Label
        $body.Text = Get-NoticeSnippet ([string]$item.Body)
        $body.Font = $script:RowBodyFont
        $body.ForeColor = [System.Drawing.Color]::FromArgb(75, 85, 99)
        $body.BackColor = $rowColor
        $body.SetBounds(26, 28, 298, 34)
        $body.Tag = $url
        $targetUrl = $url
        $openNotice = {
            if (-not [string]::IsNullOrWhiteSpace($targetUrl)) { Start-Process $targetUrl }
        }.GetNewClosure()
        $row.Add_Click($openNotice)
        $dot.Add_Click($openNotice)
        $title.Add_Click($openNotice)
        $when.Add_Click($openNotice)
        $body.Add_Click($openNotice)
        if (-not [string]::IsNullOrWhiteSpace($url)) {
            $hand = [System.Windows.Forms.Cursors]::Hand
            $row.Cursor = $hand
            $title.Cursor = $hand
            $when.Cursor = $hand
            $body.Cursor = $hand
        }
        $row.Controls.Add($dot)
        $row.Controls.Add($title)
        $row.Controls.Add($when)
        $row.Controls.Add($body)
        $list.Controls.Add($row)
        $y += 80
        if ($y -gt 2400) { break }
    }
    $list.AutoScrollMinSize = New-Object System.Drawing.Size(0, $y)
}

function Update-TicketActions {
    if ($null -eq $script:WidgetUi) { return }
    $api = ''
    $portal = ''
    if ($script:Cfg) {
        $api = [string]$script:Cfg.ServiceDeskApiUrl
        $portal = [string]$script:Cfg.ServiceDeskUrl
    }
    $ui = $script:WidgetUi
    $hasApi = -not [string]::IsNullOrWhiteSpace($api)
    $hasPortal = -not [string]::IsNullOrWhiteSpace($portal)
    $ui.PortalLink.Visible = $hasApi -and $hasPortal
    $ui.SubjectBox.Enabled = $hasApi
    $ui.BodyBox.Enabled = $hasApi
    $ui.CategoryBox.Enabled = $hasApi
    if ($hasApi) {
        $ui.SendButton.Text = 'Отправить'
        $ui.SendButton.Enabled = $true
    } elseif ($hasPortal) {
        $ui.SendButton.Text = 'Открыть портал'
        $ui.SendButton.Enabled = $true
    } else {
        $ui.SendButton.Text = 'Отправить'
        $ui.SendButton.Enabled = $false
        if ([string]::IsNullOrWhiteSpace([string]$ui.TicketStatus.Text)) {
            $ui.TicketStatus.ForeColor = [System.Drawing.Color]::FromArgb(107, 114, 128)
            $ui.TicketStatus.Text = 'Адрес сервис-деска задаёт администратор в config.json.'
        }
    }
}

function Apply-SupportPageVisual {
    param([string]$Page)
    if ($null -eq $script:WidgetUi) { return }
    if ($Page -ne 'Ticket') { $Page = 'News' }
    $script:WidgetPage = $Page
    $ui = $script:WidgetUi
    $newsOn = $Page -eq 'News'
    $ui.NewsPage.Visible = $newsOn
    $ui.TicketPage.Visible = -not $newsOn
    $accent = [System.Drawing.Color]::FromArgb(109, 74, 255)
    $muted = [System.Drawing.Color]::FromArgb(107, 114, 128)
    if ($newsOn) {
        $ui.NewsTab.ForeColor = $accent
        $ui.TicketTab.ForeColor = $muted
        $ui.NewsTab.Font = $script:TabFontBold
        $ui.TicketTab.Font = $script:TabFont
        $ui.TabLine.SetBounds(28, 40, 96, 3)
    } else {
        $ui.NewsTab.ForeColor = $muted
        $ui.TicketTab.ForeColor = $accent
        $ui.NewsTab.Font = $script:TabFont
        $ui.TicketTab.Font = $script:TabFontBold
        $ui.TabLine.SetBounds(176, 40, 72, 3)
        $session = Get-WindowsSessionIdentity
        $ui.LoginBox.Text = [string]$session.Login
        $ui.ComputerBox.Text = [string]$session.Computer
    }
}

function Select-SupportPage {
    param([string]$Page)
    Apply-SupportPageVisual -Page $Page
    if ($script:PanelOpen -and $script:WidgetPage -eq 'News') {
        Mark-NoticesOpened
        if ($script:WidgetForm -and -not $script:WidgetForm.IsDisposed) { $script:WidgetForm.Invalidate() }
    }
}

function Update-WidgetChrome {
    if ($null -eq $script:WidgetForm -or $script:WidgetForm.IsDisposed -or $null -eq $script:WidgetUi) { return }
    $ui = $script:WidgetUi
    $status = Get-SupportStatus
    $ui.Status.Text = [string]$status.Text
    $ui.Status.ForeColor = $status.Color
    $session = Get-WindowsSessionIdentity
    $login = [string]$session.Login
    $computer = [string]$session.Computer
    $identity = $login
    if (-not [string]::IsNullOrWhiteSpace($computer)) {
        if ([string]::IsNullOrWhiteSpace($identity)) { $identity = $computer }
        else { $identity = ('{0}  ·  {1}' -f $login, $computer) }
    }
    $ui.Identity.Text = $identity
    $ui.LoginBox.Text = $login
    $ui.ComputerBox.Text = $computer
    $count = @($script:NewsItems | Where-Object { $null -ne $_ }).Count
    if ($count -gt 0) { $ui.NewsTab.Text = ('Новости  {0}' -f $count) }
    else { $ui.NewsTab.Text = 'Новости' }
    $signature = Get-NewsSignature
    if ($null -eq $script:NewsSignature -or $signature -ne $script:NewsSignature) {
        Update-NewsRows
        $script:NewsSignature = $signature
    }
    Update-TicketActions
    Set-SupportBounds
    $script:WidgetForm.Invalidate()
}

function Update-WidgetStatus {
    Update-WidgetChrome
}

function Hide-SupportPanel {
    if ($script:PanelHiding) { return }
    $script:PanelHiding = $true
    try {
        $script:PanelOpen = $false
        if ($script:PanelForm -and -not $script:PanelForm.IsDisposed -and $script:PanelForm.Visible) {
            $script:PanelForm.Hide()
        }
        if ($script:WidgetForm -and -not $script:WidgetForm.IsDisposed) { $script:WidgetForm.Invalidate() }
    } finally {
        $script:PanelHiding = $false
    }
}

function Show-SupportPanel {
    param([string]$Page)
    if ([string]::IsNullOrWhiteSpace($Page)) { $Page = 'News' }
    Ensure-DesktopWidget
    if ($null -eq $script:PanelForm -or $script:PanelForm.IsDisposed) { return }
    $script:PanelOpen = $true
    Select-SupportPage -Page $Page
    Set-SupportBounds
    if (-not $script:PanelForm.Visible) { $script:PanelForm.Show() }
    try { $script:PanelForm.Activate() } catch { }
    if ('DesktopHost' -as [type]) {
        try { [DesktopHost]::PreparePanel($script:PanelForm.Handle) } catch { }
    }
    if ($script:WidgetForm -and -not $script:WidgetForm.IsDisposed) { $script:WidgetForm.Invalidate() }
}

function New-LauncherButton {
    $form = New-Object System.Windows.Forms.Form
    $form.FormBorderStyle = 'None'
    $form.ShowInTaskbar = $false
    $form.StartPosition = 'Manual'
    $form.TopMost = $true
    $form.BackColor = [System.Drawing.Color]::FromArgb(109, 74, 255)
    $form.ClientSize = New-Object System.Drawing.Size(60, 60)
    $form.Text = Get-WidgetTitle
    $form.Cursor = [System.Windows.Forms.Cursors]::Hand
    $circle = New-Object System.Drawing.Drawing2D.GraphicsPath
    $circle.AddEllipse(0, 0, 60, 60)
    $form.Region = New-Object System.Drawing.Region($circle)
    $form.Add_Paint({
        $g = $_.Graphics
        $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
        $fill = [System.Drawing.Color]::FromArgb(109, 74, 255)
        if ($script:LauncherHot) { $fill = [System.Drawing.Color]::FromArgb(124, 98, 255) }
        $brush = New-Object System.Drawing.SolidBrush $fill
        $g.FillEllipse($brush, 0, 0, 59, 59)
        $brush.Dispose()
        $white = New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::White)
        if ($script:PanelOpen) {
            $pen = New-Object System.Drawing.Pen ([System.Drawing.Color]::White, 2.4)
            $g.DrawLine($pen, 22, 22, 38, 38)
            $g.DrawLine($pen, 38, 22, 22, 38)
            $pen.Dispose()
        } else {
            $g.FillEllipse($white, 16, 18, 20, 15)
            $g.FillEllipse($white, 28, 28, 16, 12)
        }
        $white.Dispose()
        $count = Get-UnopenedNoticeCount
        if ($count -gt 0) {
            $badge = New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::FromArgb(231, 76, 60))
            $g.FillEllipse($badge, 36, 2, 20, 20)
            $badge.Dispose()
            $text = [string]$count
            if ($count -gt 9) { $text = '9' }
            $font = New-Object System.Drawing.Font('Segoe UI', 8, [System.Drawing.FontStyle]::Bold)
            $format = New-Object System.Drawing.StringFormat
            $format.Alignment = [System.Drawing.StringAlignment]::Center
            $format.LineAlignment = [System.Drawing.StringAlignment]::Center
            $ink = New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::White)
            $rect = New-Object System.Drawing.RectangleF(36, 2, 20, 20)
            $g.DrawString($text, $font, $ink, $rect, $format)
            $ink.Dispose()
            $font.Dispose()
            $format.Dispose()
        }
    })
    $form.Add_MouseEnter({ $script:LauncherHot = $true; if ($script:WidgetForm) { $script:WidgetForm.Invalidate() } })
    $form.Add_MouseLeave({ $script:LauncherHot = $false; if ($script:WidgetForm) { $script:WidgetForm.Invalidate() } })
    $form.Add_Click({
        $now = Get-Date
        if (($now - $script:LauncherClickAt).TotalMilliseconds -lt 280) { return }
        $script:LauncherClickAt = $now
        if ($script:PanelOpen) { Hide-SupportPanel }
        else { Show-SupportPanel -Page $script:WidgetPage }
    })
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
    $accent = [System.Drawing.Color]::FromArgb(109, 74, 255)
    $headerColor = $accent
    $ink = [System.Drawing.Color]::FromArgb(31, 41, 51)
    $muted = [System.Drawing.Color]::FromArgb(107, 114, 128)
    $panel = New-Object System.Windows.Forms.Form
    $panel.FormBorderStyle = 'None'
    $panel.ShowInTaskbar = $false
    $panel.StartPosition = 'Manual'
    $panel.TopMost = $true
    $panel.BackColor = [System.Drawing.Color]::White
    $panel.ClientSize = New-Object System.Drawing.Size(360, 520)
    $panel.Text = Get-WidgetTitle
    $panel.Font = $script:TabFont
    $panel.KeyPreview = $true
    $panel.Region = New-Object System.Drawing.Region((New-RoundedPath -Width 360 -Height 520 -Radius 18))

    $header = New-Object System.Windows.Forms.Panel
    $header.SetBounds(0, 0, 360, 118)
    $header.BackColor = $headerColor
    $logo = New-Object System.Windows.Forms.Panel
    $logo.SetBounds(16, 26, 40, 40)
    $logo.BackColor = [System.Drawing.Color]::White
    $logo.Region = New-Object System.Drawing.Region((New-RoundedPath -Width 40 -Height 40 -Radius 10))
    $mark = New-Object System.Windows.Forms.Label
    $mark.Dock = 'Fill'
    $mark.TextAlign = 'MiddleCenter'
    $mark.Font = $script:LogoFont
    $mark.ForeColor = $accent
    $mark.BackColor = [System.Drawing.Color]::White
    $titleText = Get-WidgetTitle
    $mark.Text = 'С'
    if (-not [string]::IsNullOrWhiteSpace($titleText)) { $mark.Text = $titleText.Substring(0, 1).ToUpperInvariant() }
    $logo.Controls.Add($mark)
    $title = New-Object System.Windows.Forms.Label
    $title.Text = $titleText
    $title.Font = $script:TitleFont
    $title.ForeColor = [System.Drawing.Color]::White
    $title.BackColor = $headerColor
    $title.AutoEllipsis = $true
    $title.SetBounds(68, 22, 220, 24)
    $identity = New-Object System.Windows.Forms.Label
    $identity.Text = ''
    $identity.Font = $script:RowBodyFont
    $identity.ForeColor = [System.Drawing.Color]::FromArgb(232, 228, 255)
    $identity.BackColor = $headerColor
    $identity.AutoEllipsis = $true
    $identity.SetBounds(68, 48, 270, 18)
    $status = New-Object System.Windows.Forms.Label
    $status.Text = 'Проверка сети'
    $status.Font = $script:RowBodyFont
    $status.ForeColor = [System.Drawing.Color]::FromArgb(232, 228, 255)
    $status.BackColor = $headerColor
    $status.AutoEllipsis = $true
    $status.SetBounds(68, 68, 220, 18)
    $close = New-Object System.Windows.Forms.Button
    $close.Text = [string][char]0x25BE
    $close.SetBounds(316, 8, 32, 28)
    $close.FlatStyle = 'Flat'
    $close.FlatAppearance.BorderSize = 0
    $close.BackColor = $headerColor
    $close.ForeColor = [System.Drawing.Color]::White
    $close.Font = $script:TitleFont
    $close.Cursor = [System.Windows.Forms.Cursors]::Hand
    $close.TabStop = $false
    $close.Add_Click({ Hide-SupportPanel })
    $header.Controls.Add($logo)
    $header.Controls.Add($title)
    $header.Controls.Add($identity)
    $header.Controls.Add($status)
    $header.Controls.Add($close)

    $sheet = New-Object System.Windows.Forms.Panel
    $sheet.SetBounds(0, 100, 360, 420)
    $sheet.BackColor = [System.Drawing.Color]::White
    $sheet.Region = New-Object System.Drawing.Region((New-RoundedPath -Width 360 -Height 420 -Radius 16))

    $newsTab = New-Object System.Windows.Forms.Button
    $newsTab.Text = 'Новости'
    $newsTab.SetBounds(8, 4, 150, 34)
    $newsTab.FlatStyle = 'Flat'
    $newsTab.FlatAppearance.BorderSize = 0
    $newsTab.FlatAppearance.MouseOverBackColor = [System.Drawing.Color]::FromArgb(245, 243, 255)
    $newsTab.BackColor = [System.Drawing.Color]::White
    $newsTab.ForeColor = $accent
    $newsTab.Font = $script:TabFontBold
    $newsTab.Cursor = [System.Windows.Forms.Cursors]::Hand
    $newsTab.Add_Click({ Select-SupportPage -Page News })
    $ticketTab = New-Object System.Windows.Forms.Button
    $ticketTab.Text = 'Заявка'
    $ticketTab.SetBounds(150, 4, 140, 34)
    $ticketTab.FlatStyle = 'Flat'
    $ticketTab.FlatAppearance.BorderSize = 0
    $ticketTab.FlatAppearance.MouseOverBackColor = [System.Drawing.Color]::FromArgb(245, 243, 255)
    $ticketTab.BackColor = [System.Drawing.Color]::White
    $ticketTab.ForeColor = $muted
    $ticketTab.Font = $script:TabFont
    $ticketTab.Cursor = [System.Windows.Forms.Cursors]::Hand
    $ticketTab.Add_Click({ Select-SupportPage -Page Ticket })
    $tabLine = New-Object System.Windows.Forms.Panel
    $tabLine.BackColor = $accent
    $tabLine.SetBounds(28, 40, 96, 3)

    $newsPage = New-Object System.Windows.Forms.Panel
    $newsPage.SetBounds(0, 46, 360, 374)
    $newsPage.BackColor = [System.Drawing.Color]::White
    $newsList = New-Object System.Windows.Forms.Panel
    $newsList.Dock = 'Fill'
    $newsList.AutoScroll = $true
    $newsList.BackColor = [System.Drawing.Color]::White
    $newsPage.Controls.Add($newsList)

    $ticketPage = New-Object System.Windows.Forms.Panel
    $ticketPage.SetBounds(0, 46, 360, 374)
    $ticketPage.BackColor = [System.Drawing.Color]::White
    $ticketPage.Visible = $false
    $loginLabel = New-Object System.Windows.Forms.Label
    $loginLabel.Text = 'Логин Windows'
    $loginLabel.ForeColor = $muted
    $loginLabel.BackColor = [System.Drawing.Color]::White
    $loginLabel.SetBounds(16, 8, 156, 16)
    $loginBox = New-Object System.Windows.Forms.TextBox
    $loginBox.ReadOnly = $true
    $loginBox.TabStop = $false
    $loginBox.BackColor = [System.Drawing.Color]::FromArgb(243, 244, 246)
    $loginBox.SetBounds(16, 26, 156, 24)
    $computerLabel = New-Object System.Windows.Forms.Label
    $computerLabel.Text = 'Компьютер'
    $computerLabel.ForeColor = $muted
    $computerLabel.BackColor = [System.Drawing.Color]::White
    $computerLabel.SetBounds(184, 8, 160, 16)
    $computerBox = New-Object System.Windows.Forms.TextBox
    $computerBox.ReadOnly = $true
    $computerBox.TabStop = $false
    $computerBox.BackColor = [System.Drawing.Color]::FromArgb(243, 244, 246)
    $computerBox.SetBounds(184, 26, 160, 24)
    $categoryLabel = New-Object System.Windows.Forms.Label
    $categoryLabel.Text = 'Категория'
    $categoryLabel.ForeColor = $muted
    $categoryLabel.BackColor = [System.Drawing.Color]::White
    $categoryLabel.SetBounds(16, 58, 328, 16)
    $category = New-Object System.Windows.Forms.ComboBox
    $category.DropDownStyle = 'DropDownList'
    [void]$category.Items.Add('Инцидент')
    [void]$category.Items.Add('Запрос обслуживания')
    [void]$category.Items.Add('Вопрос')
    $category.SelectedIndex = 0
    $category.SetBounds(16, 76, 328, 24)
    $subjectLabel = New-Object System.Windows.Forms.Label
    $subjectLabel.Text = 'Тема'
    $subjectLabel.ForeColor = $muted
    $subjectLabel.BackColor = [System.Drawing.Color]::White
    $subjectLabel.SetBounds(16, 108, 328, 16)
    $subject = New-Object System.Windows.Forms.TextBox
    $subject.SetBounds(16, 126, 328, 24)
    $bodyLabel = New-Object System.Windows.Forms.Label
    $bodyLabel.Text = 'Описание'
    $bodyLabel.ForeColor = $muted
    $bodyLabel.BackColor = [System.Drawing.Color]::White
    $bodyLabel.SetBounds(16, 156, 328, 16)
    $body = New-Object System.Windows.Forms.TextBox
    $body.Multiline = $true
    $body.ScrollBars = 'Vertical'
    $body.SetBounds(16, 174, 328, 88)
    $ticketStatus = New-Object System.Windows.Forms.Label
    $ticketStatus.Text = ''
    $ticketStatus.ForeColor = $muted
    $ticketStatus.BackColor = [System.Drawing.Color]::White
    $ticketStatus.SetBounds(16, 268, 328, 32)
    $send = New-FlatButton -Text 'Отправить' -Location (New-Object System.Drawing.Point(16, 304)) -Size (New-Object System.Drawing.Size(328, 36))
    $portalLink = New-Object System.Windows.Forms.LinkLabel
    $portalLink.Text = 'Открыть портал'
    $portalLink.LinkColor = $accent
    $portalLink.ActiveLinkColor = $accent
    $portalLink.LinkBehavior = 'HoverUnderline'
    $portalLink.BackColor = [System.Drawing.Color]::White
    $portalLink.SetBounds(16, 346, 160, 18)
    $portalLink.Visible = $false
    $portalLink.Add_LinkClicked({
        $portalUrl = ''
        if ($script:Cfg) { $portalUrl = [string]$script:Cfg.ServiceDeskUrl }
        if ([string]::IsNullOrWhiteSpace($portalUrl)) { return }
        $who = Get-WindowsSessionIdentity
        Start-Process (Expand-ServiceDeskUrl -Url $portalUrl -Login $who.Login -Computer $who.Computer)
    })
    $send.Add_Click({ Submit-SupportTicket })
    $ticketPage.Controls.Add($loginLabel)
    $ticketPage.Controls.Add($loginBox)
    $ticketPage.Controls.Add($computerLabel)
    $ticketPage.Controls.Add($computerBox)
    $ticketPage.Controls.Add($categoryLabel)
    $ticketPage.Controls.Add($category)
    $ticketPage.Controls.Add($subjectLabel)
    $ticketPage.Controls.Add($subject)
    $ticketPage.Controls.Add($bodyLabel)
    $ticketPage.Controls.Add($body)
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
    $panel.Add_KeyDown({
        if ($_.KeyCode -eq [System.Windows.Forms.Keys]::Escape) { Hide-SupportPanel }
    })
    $panel.Add_FormClosing({
        if ($script:AllowExit) { return }
        $_.Cancel = $true
        Hide-SupportPanel
    })

    $script:WidgetUi = @{
        Status = $status
        Identity = $identity
        LoginBox = $loginBox
        ComputerBox = $computerBox
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

function Submit-SupportTicket {
    if ($null -eq $script:WidgetUi) { return }
    $api = ''
    $portal = ''
    if ($script:Cfg) {
        $api = [string]$script:Cfg.ServiceDeskApiUrl
        $portal = [string]$script:Cfg.ServiceDeskUrl
    }
    $who = Get-WindowsSessionIdentity
    $ui = $script:WidgetUi
    if ([string]::IsNullOrWhiteSpace($api)) {
        if (-not [string]::IsNullOrWhiteSpace($portal)) {
            Start-Process (Expand-ServiceDeskUrl -Url $portal -Login $who.Login -Computer $who.Computer)
        }
        return
    }
    $errors = Test-TicketDraft -Subject ([string]$ui.SubjectBox.Text) -Body ([string]$ui.BodyBox.Text)
    if ($errors.Count -gt 0) {
        $ui.TicketStatus.ForeColor = [System.Drawing.Color]::FromArgb(146, 43, 33)
        $ui.TicketStatus.Text = [string]$errors[0]
        return
    }
    $categoryName = [string]$ui.CategoryBox.SelectedItem
    if ([string]::IsNullOrWhiteSpace($categoryName)) { $categoryName = 'Инцидент' }
    $payload = New-TicketPayload -Subject ([string]$ui.SubjectBox.Text) -Body ([string]$ui.BodyBox.Text) -Category $categoryName -User $who.Login -Computer $who.Computer -CreatedAt ((Get-Date).ToString('o'))
    try {
        $code = Send-TicketRequest $payload
        Write-Log ("Заявка отправлена, ответ сервис-деска: {0}, категория: {1}, пользователь: {2}, компьютер: {3}." -f $code, $payload.category, $payload.user, $payload.computer)
        $ui.SubjectBox.Text = ''
        $ui.BodyBox.Text = ''
        $ui.TicketStatus.ForeColor = [System.Drawing.Color]::FromArgb(25, 111, 61)
        $ui.TicketStatus.Text = 'Заявка отправлена.'
    } catch {
        Write-Log ("Заявку отправить не удалось: {0}" -f $_.Exception.Message) 'WARN'
        $ui.TicketStatus.ForeColor = [System.Drawing.Color]::FromArgb(146, 43, 33)
        $ui.TicketStatus.Text = 'Сервис-деск не принял заявку. Попробуйте ещё раз или откройте портал.'
    }
}

function New-DesktopWidget {
    Add-Type -AssemblyName System.Windows.Forms
    Add-Type -AssemblyName System.Drawing
    if (-not (Initialize-DesktopHost)) { $script:WidgetHost = [IntPtr]::Zero }
    $script:TabFont = New-Object System.Drawing.Font('Segoe UI', 9)
    $script:TabFontBold = New-Object System.Drawing.Font('Segoe UI', 9, [System.Drawing.FontStyle]::Bold)
    $script:TitleFont = New-Object System.Drawing.Font('Segoe UI', 12, [System.Drawing.FontStyle]::Bold)
    $script:LogoFont = New-Object System.Drawing.Font('Segoe UI', 14, [System.Drawing.FontStyle]::Bold)
    $script:RowTitleFont = New-Object System.Drawing.Font('Segoe UI', 9, [System.Drawing.FontStyle]::Bold)
    $script:RowBodyFont = New-Object System.Drawing.Font('Segoe UI', 8)
    if ($script:PanelForm -and -not $script:PanelForm.IsDisposed) {
        $previousExit = $script:AllowExit
        $script:AllowExit = $true
        try { $script:PanelForm.Dispose() } finally { $script:AllowExit = $previousExit }
    }
    $script:PanelForm = $null
    $launcher = New-LauncherButton
    $script:WidgetForm = $launcher
    $script:PanelForm = New-SupportPanel
    $script:PanelForm.Owner = $launcher
    $script:NewsSignature = $null
    Apply-SupportPageVisual -Page News
    Update-WidgetChrome
    Set-SupportBounds
    $launcher.Show()
    if ('DesktopHost' -as [type]) {
        try { [DesktopHost]::PrepareLauncher($launcher.Handle) } catch { }
    }
    Write-Log 'Кнопка поддержки показана в углу экрана.'
}

function Ensure-DesktopWidget {
    if ($script:WidgetForm -and -not $script:WidgetForm.IsDisposed -and $script:WidgetForm.IsHandleCreated) {
        Update-WidgetChrome
        return
    }
    New-DesktopWidget
}

function Ensure-TrayIcon {
    if ($script:TrayIcon) { return }
    $icon = New-Object System.Windows.Forms.NotifyIcon
    $icon.Icon = [System.Drawing.SystemIcons]::Information
    $icon.Text = 'Сервисная служба'
    $icon.Visible = $true
    $menu = New-Object System.Windows.Forms.ContextMenuStrip
    $openItem = $menu.Items.Add('Открыть')
    $ticketItem = $menu.Items.Add('Заявка')
    $newsItem = $menu.Items.Add('Новости')
    $exitItem = $menu.Items.Add('Выход')
    $openItem.Add_Click({ Show-SupportPanel -Page $script:WidgetPage })
    $ticketItem.Add_Click({ Show-SupportPanel -Page Ticket })
    $newsItem.Add_Click({ Show-SupportPanel -Page News })
    $exitItem.Add_Click({ Stop-DesktopWidgetApp })
    $icon.ContextMenuStrip = $menu
    $icon.Add_DoubleClick({ Show-SupportPanel -Page News })
    $script:TrayIcon = $icon
}

function Stop-DesktopWidgetApp {
    $script:AllowExit = $true
    if ($script:PanelForm -and -not $script:PanelForm.IsDisposed) { $script:PanelForm.Close() }
    if ($script:WidgetForm -and -not $script:WidgetForm.IsDisposed) { $script:WidgetForm.Close() }
    if ($script:TrayIcon) {
        $script:TrayIcon.Visible = $false
        $script:TrayIcon.Dispose()
        $script:TrayIcon = $null
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

function Update-WidgetNews {
    if (-not $script:Cfg -or [string]::IsNullOrWhiteSpace([string]$script:Cfg.NewsUrl)) {
        if (-not $script:NewsHintShown) {
            $script:NewsItems = @()
            $script:NewsHintShown = $true
            Update-WidgetChrome
        }
        return
    }
    $due = $script:LastNewsPoll -eq [datetime]::MinValue
    if (-not $due) {
        $due = ((Get-Date) - $script:LastNewsPoll).TotalMinutes -ge [int]$script:Cfg.NewsPollMinutes
    }
    if (-not $due) { return }
    $script:LastNewsPoll = Get-Date
    try {
        $text = Receive-HttpText -Url ([string]$script:Cfg.NewsUrl) -TimeoutSec 20
        $script:NewsItems = @(Sort-Notices (ConvertFrom-NewsFeed $text))
        $seen = @()
        if ($script:State) { $seen = @($script:State.SeenNoticeIds) }
        $fresh = @(Get-NoticesToShow -Items $script:NewsItems -SeenIds $seen -Max 3)
        $balloon = Format-NoticeBalloon $fresh
        if ($null -ne $balloon -and $fresh.Count -gt 0) {
            Show-UserNotice -Message ([string]$balloon.Text) -Title ([string]$balloon.Title)
            $ids = ConvertTo-IdList $seen
            foreach ($item in $fresh) {
                if ($null -ne $item) { $ids.Add([string]$item.Id) }
            }
            if ($ids.Count -gt 200) { $ids = $ids.GetRange($ids.Count - 200, 200) }
            if ($script:State) {
                $script:State.SeenNoticeIds = $ids.ToArray()
                Save-StateTable $script:State
            }
        }
    } catch {
        Write-Log ("Новости не загрузились: {0}" -f $_.Exception.Message) 'WARN'
    }
    Update-WidgetChrome
}

function Show-NewsDialog {
    Show-SupportPanel -Page News
}

function Send-TicketRequest {
    param($Payload)
    $json = $Payload | ConvertTo-Json -Compress
    $bytes = [System.Text.Encoding]::UTF8.GetBytes($json)
    $response = $null
    try {
        $request = [System.Net.HttpWebRequest]::Create([string]$script:Cfg.ServiceDeskApiUrl)
        $request.Method = 'POST'
        $request.ContentType = 'application/json; charset=utf-8'
        $request.ContentLength = $bytes.Length
        $request.Timeout = 20000
        $request.ReadWriteTimeout = 20000
        $request.UserAgent = 'DesktopSwitch'
        $proxy = [System.Net.WebRequest]::GetSystemWebProxy()
        $proxy.Credentials = [System.Net.CredentialCache]::DefaultNetworkCredentials
        $request.Proxy = $proxy
        $request.Credentials = [System.Net.CredentialCache]::DefaultNetworkCredentials
        if (-not [string]::IsNullOrWhiteSpace([string]$script:Cfg.ServiceDeskToken)) {
            $request.Headers.Add('Authorization', 'Bearer ' + [string]$script:Cfg.ServiceDeskToken)
        }
        $stream = $request.GetRequestStream()
        $stream.Write($bytes, 0, $bytes.Length)
        $stream.Close()
        $response = $request.GetResponse()
        return [int]$response.StatusCode
    } finally {
        if ($null -ne $response) { $response.Close() }
    }
}

function Show-TicketDialog {
    Show-SupportPanel -Page Ticket
}

function Start-WidgetApplication {
    Add-Type -AssemblyName System.Windows.Forms
    Add-Type -AssemblyName System.Drawing
    [System.Windows.Forms.Application]::EnableVisualStyles()
    $script:WidgetContext = New-Object System.Windows.Forms.ApplicationContext
    try { Invoke-MonitorCycle } catch { Write-Log ("Сбой цикла: {0}" -f $_.Exception.Message) 'ERROR' }
    try { Update-WidgetNews } catch { Write-Log ("Сбой новостей: {0}" -f $_.Exception.Message) 'ERROR' }
    try { Ensure-DesktopWidget } catch { Write-Log ("Сбой виджета: {0}" -f $_.Exception.Message) 'ERROR' }
    $timer = New-Object System.Windows.Forms.Timer
    $timer.Interval = [Math]::Max(5000, ([int]$script:Cfg.CheckIntervalSeconds * 1000))
    $timer.Add_Tick({
        try { Invoke-MonitorCycle } catch { Write-Log ("Сбой цикла: {0}" -f $_.Exception.Message) 'ERROR' }
        try { Update-WidgetNews } catch { Write-Log ("Сбой новостей: {0}" -f $_.Exception.Message) 'ERROR' }
        try { Ensure-DesktopWidget } catch { Write-Log ("Сбой виджета: {0}" -f $_.Exception.Message) 'ERROR' }
    })
    $timer.Start()
    [System.Windows.Forms.Application]::Run($script:WidgetContext)
}
