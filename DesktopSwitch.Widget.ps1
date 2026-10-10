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
$script:WidgetPage = 'Ticket'
$script:SupportPanelWidth = 300
$script:SupportPanelHeight = 392
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
    $panelW = [int]$script:SupportPanelWidth
    $panelH = [int]$script:SupportPanelHeight
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
        $empty.SetBounds(8, 48, 260, 24)
        $hint = New-Object System.Windows.Forms.Label
        $hint.Text = 'Здесь будут новости и технические работы.'
        $hint.TextAlign = 'MiddleCenter'
        $hint.Font = $script:TabFont
        $hint.ForeColor = [System.Drawing.Color]::FromArgb(107, 114, 128)
        $hint.BackColor = [System.Drawing.Color]::White
        $hint.SetBounds(8, 76, 260, 36)
        $list.Controls.Add($empty)
        $list.Controls.Add($hint)
        return
    }
    $y = 4
    $rowWidth = 276
    foreach ($item in $items) {
        $url = [string]$item.Url
        $row = New-Object System.Windows.Forms.Panel
        $row.SetBounds(8, $y, $rowWidth, 64)
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
        $title.SetBounds(22, 4, 150, 18)
        $title.Tag = $url
        $when = New-Object System.Windows.Forms.Label
        $when.Text = Format-NoticeStamp ([string]$item.PublishedAt)
        $when.Font = $script:RowBodyFont
        $when.ForeColor = [System.Drawing.Color]::FromArgb(107, 114, 128)
        $when.BackColor = $rowColor
        $when.TextAlign = 'MiddleRight'
        $when.SetBounds(172, 4, 92, 18)
        $when.Tag = $url
        $body = New-Object System.Windows.Forms.Label
        $body.Text = Get-NoticeSnippet ([string]$item.Body)
        $body.Font = $script:RowBodyFont
        $body.ForeColor = [System.Drawing.Color]::FromArgb(75, 85, 99)
        $body.BackColor = $rowColor
        $body.SetBounds(22, 24, 242, 32)
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
        $y += 68
        if ($y -gt 2400) { break }
    }
    $list.AutoScrollMinSize = New-Object System.Drawing.Size(0, $y)
}

function Test-JiraTicketMode {
    if ($null -eq $script:Cfg) { return $false }
    return -not [string]::IsNullOrWhiteSpace([string]$script:Cfg.JiraBaseUrl)
}

function Get-WidgetPortalUrl {
    $explicit = ''
    $jira = ''
    if ($script:Cfg) {
        $explicit = [string]$script:Cfg.ServiceDeskUrl
        $jira = [string]$script:Cfg.JiraBaseUrl
    }
    return Get-JiraPortalUrl -BaseUrl $jira -ExplicitUrl $explicit
}

function Set-TicketFieldLayout {
    param([bool]$JiraMode)
    if ($null -eq $script:WidgetUi) { return }
    $ui = $script:WidgetUi
    $ui.ProjectLabel.Visible = $JiraMode
    $ui.ProjectBox.Visible = $JiraMode
    if ($JiraMode) {
        $ui.CategoryLabel.Text = 'Тип запроса'
        $ui.ProjectLabel.SetBounds(10, 44, 280, 14)
        $ui.ProjectBox.SetBounds(10, 58, 280, 22)
        $ui.CategoryLabel.SetBounds(10, 84, 280, 14)
        $ui.CategoryBox.SetBounds(10, 98, 280, 22)
        $ui.SubjectLabel.SetBounds(10, 124, 280, 14)
        $ui.SubjectBox.SetBounds(10, 138, 280, 22)
        $ui.BodyLabel.SetBounds(10, 164, 280, 14)
        $ui.BodyBox.SetBounds(10, 178, 280, 28)
        $ui.TicketStatus.SetBounds(10, 208, 280, 20)
        $ui.SendButton.SetBounds(10, 230, 280, 30)
        $ui.PortalLink.SetBounds(10, 264, 200, 16)
    } else {
        $ui.CategoryLabel.Text = 'Категория'
        $ui.CategoryLabel.SetBounds(10, 44, 280, 14)
        $ui.CategoryBox.SetBounds(10, 58, 280, 22)
        $ui.SubjectLabel.SetBounds(10, 84, 280, 14)
        $ui.SubjectBox.SetBounds(10, 98, 280, 22)
        $ui.BodyLabel.SetBounds(10, 124, 280, 14)
        $ui.BodyBox.SetBounds(10, 138, 280, 64)
        $ui.TicketStatus.SetBounds(10, 206, 280, 24)
        $ui.SendButton.SetBounds(10, 232, 280, 30)
        $ui.PortalLink.SetBounds(10, 266, 200, 16)
    }
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
    Set-TicketFieldLayout -JiraMode $jira
    if ($jira) {
        $ui.PortalLink.Visible = $hasPortal
        $ui.ProjectBox.Enabled = $true
        $ui.CategoryBox.Enabled = $true
        $ui.SubjectBox.Enabled = $true
        $ui.BodyBox.Enabled = $true
        $ui.SendButton.Text = 'Отправить'
        $ui.SendButton.Enabled = $true
        return
    }
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
    if ($Page -ne 'News') { $Page = 'Ticket' }
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
        $ui.TabLine.SetBounds(140, 32, 88, 3)
    } else {
        $ui.NewsTab.ForeColor = $muted
        $ui.TicketTab.ForeColor = $accent
        $ui.NewsTab.Font = $script:TabFont
        $ui.TicketTab.Font = $script:TabFontBold
        $ui.TabLine.SetBounds(16, 32, 72, 3)
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
    if ([string]::IsNullOrWhiteSpace($Page)) { $Page = 'Ticket' }
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
    if ($script:WidgetPage -eq 'Ticket' -and $script:PanelForm -and -not $script:PanelForm.IsDisposed) {
        $script:PanelForm.BeginInvoke([System.Action]{ Request-JiraCatalogIfTicket }) | Out-Null
    }
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
    $panel.ClientSize = New-Object System.Drawing.Size([int]$script:SupportPanelWidth, [int]$script:SupportPanelHeight)
    $panel.Text = Get-WidgetTitle
    $panel.Font = $script:TabFont
    $panel.KeyPreview = $true
    $panel.Region = New-Object System.Drawing.Region((New-RoundedPath -Width ([int]$script:SupportPanelWidth) -Height ([int]$script:SupportPanelHeight) -Radius 16))

    $header = New-Object System.Windows.Forms.Panel
    $header.SetBounds(0, 0, 300, 78)
    $header.BackColor = $headerColor
    $logo = New-Object System.Windows.Forms.Panel
    $logo.SetBounds(10, 12, 32, 32)
    $logo.BackColor = [System.Drawing.Color]::White
    $logo.Region = New-Object System.Drawing.Region((New-RoundedPath -Width 32 -Height 32 -Radius 8))
    $mark = New-Object System.Windows.Forms.Label
    $mark.Dock = 'Fill'
    $mark.TextAlign = 'MiddleCenter'
    $mark.Font = $script:TitleFont
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
    $title.SetBounds(50, 8, 200, 20)
    $identity = New-Object System.Windows.Forms.Label
    $identity.Text = ''
    $identity.Font = $script:RowBodyFont
    $identity.ForeColor = [System.Drawing.Color]::FromArgb(232, 228, 255)
    $identity.BackColor = $headerColor
    $identity.AutoEllipsis = $true
    $identity.SetBounds(50, 28, 220, 14)
    $status = New-Object System.Windows.Forms.Label
    $status.Text = 'Проверка сети'
    $status.Font = $script:RowBodyFont
    $status.ForeColor = [System.Drawing.Color]::FromArgb(232, 228, 255)
    $status.BackColor = $headerColor
    $status.AutoEllipsis = $true
    $status.SetBounds(50, 42, 210, 14)
    $close = New-Object System.Windows.Forms.Button
    $close.Text = [string][char]0x25BE
    $close.SetBounds(268, 4, 26, 22)
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
    $sheet.SetBounds(0, 60, 300, 332)
    $sheet.BackColor = [System.Drawing.Color]::White
    $sheet.Region = New-Object System.Drawing.Region((New-RoundedPath -Width 300 -Height 332 -Radius 14))

    $ticketTab = New-Object System.Windows.Forms.Button
    $ticketTab.Text = 'Заявка'
    $ticketTab.SetBounds(4, 2, 120, 30)
    $ticketTab.FlatStyle = 'Flat'
    $ticketTab.FlatAppearance.BorderSize = 0
    $ticketTab.FlatAppearance.MouseOverBackColor = [System.Drawing.Color]::FromArgb(245, 243, 255)
    $ticketTab.BackColor = [System.Drawing.Color]::White
    $ticketTab.ForeColor = $accent
    $ticketTab.Font = $script:TabFontBold
    $ticketTab.Cursor = [System.Windows.Forms.Cursors]::Hand
    $ticketTab.Add_Click({
        Select-SupportPage -Page Ticket
        if ($script:PanelForm -and -not $script:PanelForm.IsDisposed) {
            $script:PanelForm.BeginInvoke([System.Action]{ Request-JiraCatalogIfTicket }) | Out-Null
        }
    })
    $newsTab = New-Object System.Windows.Forms.Button
    $newsTab.Text = 'Новости'
    $newsTab.SetBounds(124, 2, 140, 30)
    $newsTab.FlatStyle = 'Flat'
    $newsTab.FlatAppearance.BorderSize = 0
    $newsTab.FlatAppearance.MouseOverBackColor = [System.Drawing.Color]::FromArgb(245, 243, 255)
    $newsTab.BackColor = [System.Drawing.Color]::White
    $newsTab.ForeColor = $muted
    $newsTab.Font = $script:TabFont
    $newsTab.Cursor = [System.Windows.Forms.Cursors]::Hand
    $newsTab.Add_Click({ Select-SupportPage -Page News })
    $tabLine = New-Object System.Windows.Forms.Panel
    $tabLine.BackColor = $accent
    $tabLine.SetBounds(16, 32, 72, 3)

    $newsPage = New-Object System.Windows.Forms.Panel
    $newsPage.SetBounds(0, 36, 300, 296)
    $newsPage.Visible = $false
    $newsPage.BackColor = [System.Drawing.Color]::White
    $newsList = New-Object System.Windows.Forms.Panel
    $newsList.Dock = 'Fill'
    $newsList.AutoScroll = $true
    $newsList.BackColor = [System.Drawing.Color]::White
    $newsPage.Controls.Add($newsList)

    $ticketPage = New-Object System.Windows.Forms.Panel
    $ticketPage.SetBounds(0, 36, 300, 296)
    $ticketPage.BackColor = [System.Drawing.Color]::White
    $ticketPage.Visible = $true
    $loginLabel = New-Object System.Windows.Forms.Label
    $loginLabel.Text = 'Логин Windows'
    $loginLabel.ForeColor = $muted
    $loginLabel.BackColor = [System.Drawing.Color]::White
    $loginLabel.SetBounds(10, 4, 134, 14)
    $loginBox = New-Object System.Windows.Forms.TextBox
    $loginBox.ReadOnly = $true
    $loginBox.TabStop = $false
    $loginBox.BackColor = [System.Drawing.Color]::FromArgb(243, 244, 246)
    $loginBox.SetBounds(10, 18, 134, 22)
    $computerLabel = New-Object System.Windows.Forms.Label
    $computerLabel.Text = 'Компьютер'
    $computerLabel.ForeColor = $muted
    $computerLabel.BackColor = [System.Drawing.Color]::White
    $computerLabel.SetBounds(152, 4, 138, 14)
    $computerBox = New-Object System.Windows.Forms.TextBox
    $computerBox.ReadOnly = $true
    $computerBox.TabStop = $false
    $computerBox.BackColor = [System.Drawing.Color]::FromArgb(243, 244, 246)
    $computerBox.SetBounds(152, 18, 138, 22)
    $projectLabel = New-Object System.Windows.Forms.Label
    $projectLabel.Text = 'Проект'
    $projectLabel.ForeColor = $muted
    $projectLabel.BackColor = [System.Drawing.Color]::White
    $projectLabel.Visible = $false
    $projectLabel.SetBounds(10, 44, 280, 14)
    $project = New-Object System.Windows.Forms.ComboBox
    $project.DropDownStyle = 'DropDownList'
    $project.Visible = $false
    $project.SetBounds(10, 58, 280, 22)
    $project.Add_SelectedIndexChanged({
        if ($script:JiraLoading) { return }
        if (-not (Test-JiraTicketMode)) { return }
        Load-JiraRequestTypes
    })
    $categoryLabel = New-Object System.Windows.Forms.Label
    $categoryLabel.Text = 'Категория'
    $categoryLabel.ForeColor = $muted
    $categoryLabel.BackColor = [System.Drawing.Color]::White
    $categoryLabel.SetBounds(10, 44, 280, 14)
    $category = New-Object System.Windows.Forms.ComboBox
    $category.DropDownStyle = 'DropDownList'
    if (-not (Test-JiraTicketMode)) {
        [void]$category.Items.Add('Инцидент')
        [void]$category.Items.Add('Запрос обслуживания')
        [void]$category.Items.Add('Вопрос')
        $category.SelectedIndex = 0
    }
    $category.SetBounds(10, 58, 280, 22)
    $subjectLabel = New-Object System.Windows.Forms.Label
    $subjectLabel.Text = 'Тема'
    $subjectLabel.ForeColor = $muted
    $subjectLabel.BackColor = [System.Drawing.Color]::White
    $subjectLabel.SetBounds(10, 84, 280, 14)
    $subject = New-Object System.Windows.Forms.TextBox
    $subject.SetBounds(10, 98, 280, 22)
    $bodyLabel = New-Object System.Windows.Forms.Label
    $bodyLabel.Text = 'Описание'
    $bodyLabel.ForeColor = $muted
    $bodyLabel.BackColor = [System.Drawing.Color]::White
    $bodyLabel.SetBounds(10, 124, 280, 14)
    $body = New-Object System.Windows.Forms.TextBox
    $body.Multiline = $true
    $body.ScrollBars = 'Vertical'
    $body.SetBounds(10, 138, 280, 64)
    $ticketStatus = New-Object System.Windows.Forms.Label
    $ticketStatus.Text = ''
    $ticketStatus.ForeColor = $muted
    $ticketStatus.BackColor = [System.Drawing.Color]::White
    $ticketStatus.SetBounds(10, 206, 280, 24)
    $send = New-FlatButton -Text 'Отправить' -Location (New-Object System.Drawing.Point(10, 232)) -Size (New-Object System.Drawing.Size(280, 30))
    $portalLink = New-Object System.Windows.Forms.LinkLabel
    $portalLink.Text = 'Открыть портал'
    $portalLink.LinkColor = $accent
    $portalLink.ActiveLinkColor = $accent
    $portalLink.LinkBehavior = 'HoverUnderline'
    $portalLink.BackColor = [System.Drawing.Color]::White
    $portalLink.SetBounds(10, 266, 160, 16)
    $portalLink.Visible = $false
    $portalLink.Add_LinkClicked({
        $portalUrl = Get-WidgetPortalUrl
        if ([string]::IsNullOrWhiteSpace($portalUrl)) { return }
        $who = Get-WindowsSessionIdentity
        Start-Process (Expand-ServiceDeskUrl -Url $portalUrl -Login $who.Login -Computer $who.Computer)
    })
    $send.Add_Click({ Submit-SupportTicket })
    $ticketPage.Controls.Add($loginLabel)
    $ticketPage.Controls.Add($loginBox)
    $ticketPage.Controls.Add($computerLabel)
    $ticketPage.Controls.Add($computerBox)
    $ticketPage.Controls.Add($projectLabel)
    $ticketPage.Controls.Add($project)
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
        ProjectLabel = $projectLabel
        ProjectBox = $project
        CategoryLabel = $categoryLabel
        SubjectLabel = $subjectLabel
        BodyLabel = $bodyLabel
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
        $script:WidgetUi.TicketStatus.ForeColor = [System.Drawing.Color]::FromArgb(146, 43, 33)
    } else {
        $script:WidgetUi.TicketStatus.ForeColor = [System.Drawing.Color]::FromArgb(107, 114, 128)
    }
    $script:WidgetUi.TicketStatus.Text = $clean
    try { $script:WidgetUi.TicketStatus.Refresh() } catch { }
}

function Ensure-JiraCatalog {
    if (-not (Test-JiraTicketMode)) { return }
    if ($script:JiraLoaded -or $script:JiraLoading) { return }
    if ($null -eq $script:WidgetUi) { return }
    $ui = $script:WidgetUi
    $script:JiraLoading = $true
    $loaded = $false
    try {
        Set-TicketStatusMessage -Text 'Загружаю проекты Jira...' -IsError $false
        $ui.ProjectBox.Items.Clear()
        $ui.CategoryBox.Items.Clear()
        $script:JiraDesks = Receive-JiraServiceDesks
        if ($null -eq $script:JiraDesks) { $script:JiraDesks = @() }
        $script:JiraRequestTypes = @()
        foreach ($desk in $script:JiraDesks) {
            if ($null -eq $desk) { continue }
            [void]$ui.ProjectBox.Items.Add((Format-JiraDeskLabel $desk))
        }
        $loaded = $true
        $script:JiraLoaded = $true
        if ($ui.ProjectBox.Items.Count -eq 0) {
            Set-TicketStatusMessage -Text 'В Jira нет доступных проектов helpdesk для этой учётной записи.' -IsError $true
            return
        }
        $ui.ProjectBox.SelectedIndex = 0
    } catch {
        $script:JiraLoaded = $false
        Write-Log ("Проекты Jira не загрузились: {0}" -f $_.Exception.Message) 'WARN'
        Set-TicketStatusMessage -Text 'Не удалось загрузить проекты Jira.' -IsError $true
    } finally {
        $script:JiraLoading = $false
    }
    if ($loaded -and $ui.ProjectBox.Items.Count -gt 0) { Load-JiraRequestTypes }
}

function Load-JiraRequestTypes {
    if (-not (Test-JiraTicketMode)) { return }
    if ($null -eq $script:WidgetUi -or $script:JiraLoading) { return }
    $ui = $script:WidgetUi
    $index = [int]$ui.ProjectBox.SelectedIndex
    $desks = $script:JiraDesks
    if ($null -eq $desks) { $desks = @() }
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
    $desk = $desks[$index]
    $script:JiraLoading = $true
    try {
        Set-TicketStatusMessage -Text 'Загружаю типы запросов...' -IsError $false
        $script:JiraRequestTypes = Receive-JiraRequestTypes -ServiceDeskId ([string]$desk.Id)
        if ($null -eq $script:JiraRequestTypes) { $script:JiraRequestTypes = @() }
        $ui.CategoryBox.Items.Clear()
        foreach ($kind in $script:JiraRequestTypes) {
            if ($null -eq $kind) { continue }
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
    } catch {
        Write-Log ("Типы запросов Jira не загрузились: {0}" -f $_.Exception.Message) 'WARN'
        Set-TicketStatusMessage -Text 'Не удалось загрузить типы запросов.' -IsError $true
    } finally {
        $script:JiraLoading = $false
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
        $ui.TicketStatus.ForeColor = [System.Drawing.Color]::FromArgb(25, 111, 61)
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
    Apply-SupportPageVisual -Page Ticket
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
    $icon.Add_DoubleClick({ Show-SupportPanel -Page Ticket })
    $script:TrayIcon = $icon
}

function Stop-DesktopWidgetApp {
    $script:AllowExit = $true
    if ($script:NewsPopup -and -not $script:NewsPopup.IsDisposed) { $script:NewsPopup.Close() }
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

function Set-NewsPopupBounds {
    if ($null -eq $script:NewsPopup -or $script:NewsPopup.IsDisposed -or -not $script:NewsPopup.Visible) { return }
    Add-Type -AssemblyName System.Windows.Forms
    $screen = [System.Windows.Forms.Screen]::PrimaryScreen.WorkingArea
    $margin = Get-WidgetMargin
    $corner = Get-WidgetCorner
    $button = 60
    $popupW = $script:NewsPopup.Width
    $popupH = $script:NewsPopup.Height
    $gap = 12
    $x = $screen.Left + $margin
    $y = $screen.Top + $margin
    if ($corner -eq 'BottomRight' -or $corner -eq 'TopRight') { $x = $screen.Right - $button - $margin }
    if ($corner -eq 'BottomRight' -or $corner -eq 'BottomLeft') { $y = $screen.Bottom - $button - $margin }
    $px = $x + $button - $popupW
    $py = $y - $gap - $popupH
    if ($corner -eq 'BottomLeft' -or $corner -eq 'TopLeft') { $px = $x }
    if ($corner -eq 'TopLeft' -or $corner -eq 'TopRight') { $py = $y + $button + $gap }
    $panelOpen = $script:PanelOpen -and $null -ne $script:PanelForm -and -not $script:PanelForm.IsDisposed -and $script:PanelForm.Visible
    if ($panelOpen) {
        $px = $script:PanelForm.Left - $gap - $popupW
        $py = $script:PanelForm.Top
        if ($corner -eq 'BottomLeft' -or $corner -eq 'TopLeft') { $px = $script:PanelForm.Right + $gap }
    }
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
}

function Open-NewsFromPopup {
    Hide-NewsPopup
    Show-SupportPanel -Page News
}

function Ensure-NewsPopup {
    if ($script:NewsPopup -and -not $script:NewsPopup.IsDisposed) { return }
    Add-Type -AssemblyName System.Windows.Forms
    Add-Type -AssemblyName System.Drawing
    $accent = [System.Drawing.Color]::FromArgb(109, 74, 255)
    $form = New-Object System.Windows.Forms.Form
    $form.FormBorderStyle = 'None'
    $form.ShowInTaskbar = $false
    $form.StartPosition = 'Manual'
    $form.TopMost = $true
    $form.BackColor = [System.Drawing.Color]::White
    $form.ClientSize = New-Object System.Drawing.Size(280, 120)
    $form.Font = $script:TabFont
    $form.Text = 'Новости'
    $header = New-Object System.Windows.Forms.Panel
    $header.SetBounds(0, 0, 280, 36)
    $header.BackColor = $accent
    $title = New-Object System.Windows.Forms.Label
    $title.Text = 'Новости'
    $title.ForeColor = [System.Drawing.Color]::White
    $title.BackColor = $accent
    $title.Font = $script:TabFontBold
    $title.AutoEllipsis = $true
    $title.SetBounds(12, 8, 220, 20)
    $title.Add_Click({ Open-NewsFromPopup })
    $close = New-Object System.Windows.Forms.Button
    $close.Text = [string][char]0x00D7
    $close.SetBounds(244, 4, 28, 26)
    $close.FlatStyle = 'Flat'
    $close.FlatAppearance.BorderSize = 0
    $close.BackColor = $accent
    $close.ForeColor = [System.Drawing.Color]::White
    $close.Font = $script:TitleFont
    $close.Cursor = [System.Windows.Forms.Cursors]::Hand
    $close.TabStop = $false
    $close.Add_Click({ Hide-NewsPopup })
    $header.Controls.Add($title)
    $header.Controls.Add($close)
    $body = New-Object System.Windows.Forms.Panel
    $body.SetBounds(0, 36, 280, 84)
    $body.BackColor = [System.Drawing.Color]::White
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
    if ($script:WidgetForm -and -not $script:WidgetForm.IsDisposed) { $form.Owner = $script:WidgetForm }
}

function Show-NewsPopup {
    param($Notices)
    $items = @($Notices | Where-Object { $null -ne $_ })
    if ($items.Count -eq 0) { return }
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
        $row.BackColor = [System.Drawing.Color]::White
        $row.Cursor = [System.Windows.Forms.Cursors]::Hand
        $row.Add_Click($open)
        $bar = New-Object System.Windows.Forms.Panel
        $bar.SetBounds(0, 4, 4, 36)
        $bar.BackColor = [System.Drawing.Color]::FromArgb(59, 130, 246)
        if ([string]$item.Kind -eq 'maintenance') { $bar.BackColor = [System.Drawing.Color]::FromArgb(230, 126, 34) }
        $bar.Add_Click($open)
        $caption = New-Object System.Windows.Forms.Label
        $caption.Text = [string]$item.Title
        $caption.Font = $script:RowTitleFont
        $caption.ForeColor = [System.Drawing.Color]::FromArgb(31, 41, 51)
        $caption.BackColor = [System.Drawing.Color]::White
        $caption.AutoEllipsis = $true
        $caption.SetBounds(12, 2, 248, 18)
        $caption.Cursor = [System.Windows.Forms.Cursors]::Hand
        $caption.Add_Click($open)
        $detail = New-Object System.Windows.Forms.Label
        $detail.Text = Get-NoticeSnippet ([string]$item.Body)
        $detail.Font = $script:RowBodyFont
        $detail.ForeColor = [System.Drawing.Color]::FromArgb(75, 85, 99)
        $detail.BackColor = [System.Drawing.Color]::White
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
    $script:NewsPopupBody.SetBounds(0, 36, 280, $bodyHeight)
    $total = 36 + $bodyHeight
    $script:NewsPopup.ClientSize = New-Object System.Drawing.Size(280, $total)
    $script:NewsPopup.Region = New-Object System.Drawing.Region((New-RoundedPath -Width 280 -Height $total -Radius 14))
    if (-not $script:NewsPopup.Visible) { $script:NewsPopup.Show() }
    if ('DesktopHost' -as [type]) {
        try { [DesktopHost]::PreparePanel($script:NewsPopup.Handle) } catch { }
    }
    Set-NewsPopupBounds
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
        if ($fresh.Count -gt 0) {
            try {
                Show-NewsPopup -Notices $fresh
            } catch {
                $balloon = Format-NoticeBalloon $fresh
                if ($null -ne $balloon) { Show-UserNotice -Message ([string]$balloon.Text) -Title ([string]$balloon.Title) }
                Write-Log ("Всплывающее окно новостей не открылось: {0}" -f $_.Exception.Message) 'WARN'
            }
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

function Invoke-ServiceDeskRequest {
    param(
        [string]$Url,
        [string]$Method,
        [string]$JsonBody,
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
        $token = ''
        if ($script:Cfg) { $token = [string]$script:Cfg.ServiceDeskToken }
        if (-not [string]::IsNullOrWhiteSpace($token)) {
            $request.Headers.Add('Authorization', 'Bearer ' + $token)
        } else {
            $request.Credentials = [System.Net.CredentialCache]::DefaultNetworkCredentials
            $request.PreAuthenticate = $true
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
