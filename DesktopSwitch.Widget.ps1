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
$script:SupportPanelWidth = 360
$script:SupportPanelHeight = 592
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
$script:WidgetPalette = $null
$script:AppThemeLight = $true
$script:LauncherMenuItem = $null
$script:TrayMenu = $null
$script:ThemeHooked = $false
$script:ThemeHandler = $null
$script:ApplyingTheme = $false
$script:PopupNotices = @()
$script:ListPopup = $null
$script:ListPopupClosing = $false
$script:ListPopupReady = $false
$script:SoftListSource = $null

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

function Get-ThemeColor {
    param([string]$Name)
    if ($null -eq $script:WidgetPalette) { $script:WidgetPalette = Get-WidgetPalette -Light $true }
    $rgb = $script:WidgetPalette[$Name]
    return [System.Drawing.Color]::FromArgb([int]$rgb[0], [int]$rgb[1], [int]$rgb[2])
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
    $border = Get-ThemeColor FieldBorder
    $fill = Get-ThemeColor FieldFill
    if ($ReadOnly) { $fill = Get-ThemeColor FieldReadOnly }
    $ink = Get-ThemeColor Ink
    $icon = Get-ThemeColor Icon
    $Field.Shell.BackColor = $border
    $Field.Fill.BackColor = $fill
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
}

function Apply-TrayMenuPalette {
    if ($null -eq $script:TrayMenu) { return }
    $canvas = Get-ThemeColor Canvas
    $ink = Get-ThemeColor Ink
    $script:TrayMenu.BackColor = $canvas
    $script:TrayMenu.ForeColor = $ink
    foreach ($item in @($script:TrayMenu.Items)) {
        if ($item -is [System.Windows.Forms.ToolStripSeparator]) { continue }
        $item.BackColor = $canvas
        $item.ForeColor = $ink
    }
}

function Apply-NewsPopupPalette {
    if ($null -eq $script:NewsPopup -or $script:NewsPopup.IsDisposed) { return }
    $canvas = Get-ThemeColor Canvas
    $ink = Get-ThemeColor Ink
    $muted = Get-ThemeColor Muted
    $hover = Get-ThemeColor Hover
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
        $script:NewsPopupClose.FlatAppearance.MouseOverBackColor = $hover
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
    $ui.CloseButton.FlatAppearance.MouseOverBackColor = $hover
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
    $ui.SendButton.BackColor = $accent
    $ui.SendButton.FlatAppearance.MouseOverBackColor = (Get-ThemeColor AccentHover)
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
    if ($script:WidgetForm -and -not $script:WidgetForm.IsDisposed) { $script:WidgetForm.Invalidate() }
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
    $old = $Button.Region
    $Button.Region = New-Object System.Drawing.Region((New-RoundedPath -Width $Button.Width -Height $Button.Height -Radius 12))
    if ($null -ne $old) { $old.Dispose() }
}

function New-FlatButton {
    param([string]$Text, [System.Drawing.Point]$Location, [System.Drawing.Size]$Size)
    $button = New-Object System.Windows.Forms.Button
    $button.Text = $Text
    $button.Location = $Location
    $button.Size = $Size
    $button.FlatStyle = 'Flat'
    $button.BackColor = Get-ThemeColor Accent
    $button.ForeColor = [System.Drawing.Color]::White
    if ($script:ButtonFont) { $button.Font = $script:ButtonFont }
    else { $button.Font = $script:TabFontBold }
    $button.FlatAppearance.BorderSize = 0
    $button.FlatAppearance.MouseOverBackColor = Get-ThemeColor AccentHover
    $button.Cursor = [System.Windows.Forms.Cursors]::Hand
    $button.Image = New-SendGlyph
    $button.TextImageRelation = 'ImageBeforeText'
    $button.ImageAlign = 'MiddleCenter'
    $button.TextAlign = 'MiddleCenter'
    Update-FlatButtonRegion $button
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
    $oldShell = $shell.Region
    $shell.Region = New-Object System.Drawing.Region((New-RoundedPath -Width $Width -Height $Height -Radius 12))
    if ($null -ne $oldShell) { $oldShell.Dispose() }
    $fill.SetBounds(1, 1, ($Width - 2), ($Height - 2))
    $oldFill = $fill.Region
    $fill.Region = New-Object System.Drawing.Region((New-RoundedPath -Width ($Width - 2) -Height ($Height - 2) -Radius 11))
    if ($null -ne $oldFill) { $oldFill.Dispose() }
    if ($null -ne $icon) { $icon.SetBounds(2, 0, 32, ($Height - 2)) }
    if ($editor -is [System.Windows.Forms.TextBox] -and $editor.Multiline) {
        $editor.SetBounds(36, 8, ($Width - 52), ($Height - 18))
    }
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
    }
}

function Show-SoftListPopup {
    param($List, $Anchor)
    if ($null -eq $List -or -not $List.Enabled) { return }
    if ($List.Items.Count -eq 0) { return }
    Close-SoftListPopup
    $rowH = 36
    $visible = $List.Items.Count
    if ($visible -gt 6) { $visible = 6 }
    $popupW = $Anchor.Width
    $popupH = $visible * $rowH
    $form = New-Object System.Windows.Forms.Form
    $form.FormBorderStyle = 'None'
    $form.ShowInTaskbar = $false
    $form.StartPosition = 'Manual'
    $form.TopMost = $true
    $form.BackColor = Get-ThemeColor FieldFill
    $form.ClientSize = New-Object System.Drawing.Size($popupW, $popupH)
    $form.Region = New-Object System.Drawing.Region((New-RoundedPath -Width $popupW -Height $popupH -Radius 12))
    $origin = $Anchor.PointToScreen((New-Object System.Drawing.Point(0, ($Anchor.Height + 4))))
    $screen = [System.Windows.Forms.Screen]::FromControl($Anchor).WorkingArea
    if (($origin.Y + $popupH) -gt $screen.Bottom) { $origin.Y = $origin.Y - $Anchor.Height - 8 - $popupH }
    $form.Location = $origin
    $scroller = New-Object System.Windows.Forms.Panel
    $scroller.Dock = 'Fill'
    $scroller.AutoScroll = ($List.Items.Count -gt 6)
    $scroller.BackColor = Get-ThemeColor FieldFill
    $script:SoftListSource = $List
    for ($i = 0; $i -lt $List.Items.Count; $i++) {
        $row = New-Object System.Windows.Forms.Label
        $row.Text = [string]$List.Items[$i]
        $row.Tag = $i
        $row.Font = $script:FieldFont
        $row.AutoEllipsis = $true
        $row.TextAlign = 'MiddleLeft'
        $row.Cursor = [System.Windows.Forms.Cursors]::Hand
        $rowWidth = $popupW
        if ($List.Items.Count -gt 6) { $rowWidth = $popupW - 18 }
        $row.SetBounds(0, ($i * $rowH), $rowWidth, $rowH)
        $row.Padding = New-Object System.Windows.Forms.Padding(14, 0, 12, 0)
        if ($i -eq $List.SelectedIndex) {
            $row.BackColor = Get-ThemeColor Accent
            $row.ForeColor = [System.Drawing.Color]::White
        } else {
            $row.BackColor = Get-ThemeColor FieldFill
            $row.ForeColor = Get-ThemeColor Ink
        }
        $row.Add_Click({
            $source = $script:SoftListSource
            if ($null -ne $source) { $source.SelectedIndex = [int]$this.Tag }
            Close-SoftListPopup
        })
        $scroller.Controls.Add($row)
    }
    $form.Controls.Add($scroller)
    $form.Add_Shown({ $script:ListPopupReady = $true })
    $form.Add_Deactivate({
        if (-not $script:ListPopupReady) { return }
        Close-SoftListPopup
    })
    $form.Add_KeyDown({
        if ($_.KeyCode -eq [System.Windows.Forms.Keys]::Escape) { Close-SoftListPopup }
    })
    $form.KeyPreview = $true
    if ($script:PanelForm -and -not $script:PanelForm.IsDisposed) { $form.Owner = $script:PanelForm }
    $script:ListPopupReady = $false
    $script:ListPopup = $form
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
    $border = Get-ThemeColor FieldBorder
    $fillColor = Get-ThemeColor FieldFill
    if ($ReadOnly) { $fillColor = Get-ThemeColor FieldReadOnly }
    $iconColor = Get-ThemeColor Icon
    $ink = Get-ThemeColor Ink
    $shell = New-Object System.Windows.Forms.Panel
    $shell.Size = New-Object System.Drawing.Size($Width, $Height)
    $shell.BackColor = $border
    $shell.Region = New-Object System.Drawing.Region((New-RoundedPath -Width $Width -Height $Height -Radius 12))
    $fill = New-Object System.Windows.Forms.Panel
    $fill.SetBounds(1, 1, ($Width - 2), ($Height - 2))
    $fill.BackColor = $fillColor
    $fill.Region = New-Object System.Drawing.Region((New-RoundedPath -Width ($Width - 2) -Height ($Height - 2) -Radius 11))
    $iconLabel = New-Object System.Windows.Forms.Label
    $iconLabel.Text = $Icon
    $iconLabel.Font = $script:IconFont
    $iconLabel.ForeColor = $iconColor
    $iconLabel.BackColor = $fillColor
    $iconLabel.TextAlign = 'MiddleCenter'
    $iconLabel.SetBounds(2, 0, 32, ($Height - 2))
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
        $valueLabel.SetBounds(36, 2, ($Width - 78), ($Height - 6))
        $chevron = New-Object System.Windows.Forms.Label
        $chevron.Text = [string][char]0x2304
        $chevron.Font = $script:FieldFont
        $chevron.ForeColor = $iconColor
        $chevron.BackColor = $fillColor
        $chevron.TextAlign = 'MiddleCenter'
        $chevron.Cursor = [System.Windows.Forms.Cursors]::Hand
        $chevron.SetBounds(($Width - 36), 2, 28, ($Height - 6))
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
        $editor.SetBounds(36, 8, ($Width - 52), ($Height - 18))
    } else {
        $editor = New-Object System.Windows.Forms.TextBox
        $editor.BorderStyle = 'None'
        $editor.Font = $script:FieldFont
        $editor.BackColor = $fillColor
        $editor.ForeColor = $ink
        $editor.SetBounds(36, 9, ($Width - 52), 22)
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
        $empty.ForeColor = Get-ThemeColor Empty
        $empty.BackColor = Get-ThemeColor Canvas
        $emptyWidth = [int]$script:SupportPanelWidth - 32
        $empty.SetBounds(16, 48, $emptyWidth, 24)
        $hint = New-Object System.Windows.Forms.Label
        $hint.Text = 'Здесь будут новости и технические работы.'
        $hint.TextAlign = 'MiddleCenter'
        $hint.Font = $script:TabFont
        $hint.ForeColor = Get-ThemeColor Muted
        $hint.BackColor = Get-ThemeColor Canvas
        $hint.SetBounds(16, 76, $emptyWidth, 36)
        $list.Controls.Add($empty)
        $list.Controls.Add($hint)
        return
    }
    $y = 4
    $rowWidth = [int]$script:SupportPanelWidth - 32
    foreach ($item in $items) {
        $url = [string]$item.Url
        $row = New-Object System.Windows.Forms.Panel
        $row.SetBounds(16, $y, $rowWidth, 64)
        $row.BackColor = Get-ThemeColor Canvas
        $row.Tag = $url
        $rowColor = $row.BackColor
        $dot = New-Object System.Windows.Forms.Panel
        $dot.SetBounds(4, 16, 6, 6)
        $dotColor = Get-ThemeColor Ink
        if ([string]$item.Kind -eq 'maintenance') { $dotColor = Get-ThemeColor Maintenance }
        $dot.BackColor = $dotColor
        $dotPath = New-Object System.Drawing.Drawing2D.GraphicsPath
        $dotPath.AddEllipse(0, 0, 6, 6)
        $dot.Region = New-Object System.Drawing.Region($dotPath)
        $dot.Tag = $url
        $title = New-Object System.Windows.Forms.Label
        $title.Text = [string]$item.Title
        $title.Font = $script:RowTitleFont
        $title.ForeColor = Get-ThemeColor Ink
        $title.BackColor = $rowColor
        $title.AutoEllipsis = $true
        $title.SetBounds(18, 4, ($rowWidth - 128), 18)
        $title.Tag = $url
        $when = New-Object System.Windows.Forms.Label
        $when.Text = Format-NoticeStamp ([string]$item.PublishedAt)
        $when.Font = $script:RowBodyFont
        $when.ForeColor = Get-ThemeColor Muted
        $when.BackColor = $rowColor
        $when.TextAlign = 'MiddleRight'
        $when.SetBounds(($rowWidth - 100), 4, 92, 18)
        $when.Tag = $url
        $body = New-Object System.Windows.Forms.Label
        $body.Text = Get-NoticeSnippet ([string]$item.Body)
        $body.Font = $script:RowBodyFont
        $body.ForeColor = Get-ThemeColor Muted
        $body.BackColor = $rowColor
        $body.SetBounds(18, 24, ($rowWidth - 28), 32)
        $rule = New-Object System.Windows.Forms.Panel
        $rule.SetBounds(0, 63, $rowWidth, 1)
        $rule.BackColor = Get-ThemeColor Rule
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
        $row.Controls.Add($rule)
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
        $ui.PortalLink.SetBounds(16, 464, 240, 16)
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
        $ui.PortalLink.SetBounds(16, 450, 240, 16)
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
    if ($Page -ne 'News') { $Page = 'Ticket' }
    $script:WidgetPage = $Page
    $ui = $script:WidgetUi
    $newsOn = $Page -eq 'News'
    $ui.NewsPage.Visible = $newsOn
    $ui.TicketPage.Visible = -not $newsOn
    $ink = Get-ThemeColor Ink
    $muted = Get-ThemeColor Muted
    if ($newsOn) {
        $ui.NewsTab.ForeColor = $ink
        $ui.TicketTab.ForeColor = $muted
        $ui.NewsTab.Font = $script:TabFontBold
        $ui.TicketTab.Font = $script:TabFont
        $ui.TabLine.SetBounds(132, 31, 52, 2)
    } else {
        $ui.NewsTab.ForeColor = $muted
        $ui.TicketTab.ForeColor = $ink
        $ui.NewsTab.Font = $script:TabFont
        $ui.TicketTab.Font = $script:TabFontBold
        $ui.TabLine.SetBounds(20, 31, 52, 2)
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
    Sync-WidgetTheme
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
        $fill = Get-ThemeColor Accent
        if ($script:LauncherHot) { $fill = Get-ThemeColor AccentHover }
        $brush = New-Object System.Drawing.SolidBrush $fill
        $g.FillEllipse($brush, 0, 0, 51, 51)
        $brush.Dispose()
        $pen = New-Object System.Drawing.Pen ([System.Drawing.Color]::White, 1.6)
        if ($script:PanelOpen) {
            $g.DrawLine($pen, 19, 19, 33, 33)
            $g.DrawLine($pen, 33, 19, 19, 33)
        } else {
            $bubble = New-RoundedPath -Width 22 -Height 16 -Radius 7
            $g.TranslateTransform(15, 16)
            $g.DrawPath($pen, $bubble)
            $g.ResetTransform()
            $bubble.Dispose()
            $g.DrawLine($pen, 22, 31, 19, 36)
            $g.DrawLine($pen, 19, 36, 27, 31)
        }
        $pen.Dispose()
        $count = Get-UnopenedNoticeCount
        if ($count -gt 0) {
            $badge = New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::White)
            $g.FillEllipse($badge, 32, 2, 16, 16)
            $badge.Dispose()
            $text = [string]$count
            if ($count -gt 9) { $text = '9' }
            $font = New-Object System.Drawing.Font('Segoe UI', 7, [System.Drawing.FontStyle]::Bold)
            $format = New-Object System.Drawing.StringFormat
            $format.Alignment = [System.Drawing.StringAlignment]::Center
            $format.LineAlignment = [System.Drawing.StringAlignment]::Center
            $ink = New-Object System.Drawing.SolidBrush (Get-ThemeColor Accent)
            $rect = New-Object System.Drawing.RectangleF(32, 2, 16, 16)
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
    $accent = Get-ThemeColor Accent
    $headerColor = Get-ThemeColor Canvas
    $ink = Get-ThemeColor Ink
    $muted = Get-ThemeColor Muted
    $labelColor = Get-ThemeColor Label
    $hover = Get-ThemeColor Hover
    $ruleColor = Get-ThemeColor Rule
    $panelW = [int]$script:SupportPanelWidth
    $panelH = [int]$script:SupportPanelHeight
    $headerH = 76
    $pageY = 34
    $pageH = $panelH - $headerH - $pageY
    $panel = New-Object System.Windows.Forms.Form
    $panel.FormBorderStyle = 'None'
    $panel.ShowInTaskbar = $false
    $panel.StartPosition = 'Manual'
    $panel.TopMost = $true
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
    $mark.SetBounds(16, 18, 36, 36)
    $mark.BackColor = $accent
    $mark.Region = New-Object System.Drawing.Region((New-RoundedPath -Width 36 -Height 36 -Radius 10))
    $markLetter = New-Object System.Windows.Forms.Label
    $markLetter.Text = $markText
    $markLetter.Font = $script:TitleFont
    $markLetter.ForeColor = [System.Drawing.Color]::White
    $markLetter.BackColor = $accent
    $markLetter.TextAlign = 'MiddleCenter'
    $markLetter.Dock = 'Fill'
    $mark.Controls.Add($markLetter)
    $title = New-Object System.Windows.Forms.Label
    $title.Text = $titleText
    $title.Font = $script:TitleFont
    $title.ForeColor = $ink
    $title.BackColor = $headerColor
    $title.AutoEllipsis = $true
    $title.SetBounds(60, 14, ($panelW - 108), 22)
    $identity = New-Object System.Windows.Forms.Label
    $identity.Text = ''
    $identity.Font = $script:RowBodyFont
    $identity.ForeColor = $muted
    $identity.BackColor = $headerColor
    $identity.AutoEllipsis = $true
    $identity.SetBounds(60, 36, ($panelW - 84), 14)
    $status = New-Object System.Windows.Forms.Label
    $status.Text = 'Проверка сети'
    $status.Font = $script:RowBodyFont
    $status.ForeColor = $muted
    $status.BackColor = $headerColor
    $status.AutoEllipsis = $true
    $status.SetBounds(60, 52, ($panelW - 84), 14)
    $close = New-Object System.Windows.Forms.Button
    $close.Text = [string][char]0x00D7
    $close.SetBounds(($panelW - 40), 12, 28, 24)
    $close.FlatStyle = 'Flat'
    $close.FlatAppearance.BorderSize = 0
    $close.FlatAppearance.MouseOverBackColor = $hover
    $close.BackColor = $headerColor
    $close.ForeColor = $muted
    $close.Font = $script:TitleFont
    $close.Cursor = [System.Windows.Forms.Cursors]::Hand
    $close.TabStop = $false
    $close.Add_Click({ Hide-SupportPanel })
    $header.Controls.Add($mark)
    $header.Controls.Add($title)
    $header.Controls.Add($identity)
    $header.Controls.Add($status)
    $header.Controls.Add($close)

    $sheet = New-Object System.Windows.Forms.Panel
    $sheet.SetBounds(0, $headerH, $panelW, ($panelH - $headerH))
    $sheet.BackColor = $headerColor

    $ticketTab = New-Object System.Windows.Forms.Button
    $ticketTab.Text = 'Заявка'
    $ticketTab.SetBounds(8, 2, 108, 30)
    $ticketTab.TextAlign = 'MiddleLeft'
    $ticketTab.Padding = New-Object System.Windows.Forms.Padding(12, 0, 0, 0)
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
    $newsTab.Text = 'Новости'
    $newsTab.SetBounds(116, 2, 140, 30)
    $newsTab.TextAlign = 'MiddleLeft'
    $newsTab.Padding = New-Object System.Windows.Forms.Padding(16, 0, 0, 0)
    $newsTab.FlatStyle = 'Flat'
    $newsTab.FlatAppearance.BorderSize = 0
    $newsTab.FlatAppearance.MouseOverBackColor = $hover
    $newsTab.BackColor = $headerColor
    $newsTab.ForeColor = $muted
    $newsTab.Font = $script:TabFont
    $newsTab.Cursor = [System.Windows.Forms.Cursors]::Hand
    $newsTab.Add_Click({ Select-SupportPage -Page News })
    $tabLine = New-Object System.Windows.Forms.Panel
    $tabLine.BackColor = $accent
    $tabLine.SetBounds(20, 31, 52, 2)

    $newsPage = New-Object System.Windows.Forms.Panel
    $newsPage.SetBounds(0, $pageY, $panelW, $pageH)
    $newsPage.Visible = $false
    $newsPage.BackColor = $headerColor
    $newsList = New-Object System.Windows.Forms.Panel
    $newsList.Dock = 'Fill'
    $newsList.AutoScroll = $true
    $newsList.BackColor = $headerColor
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
    $portalLink.SetBounds(16, 450, 240, 16)
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
    $script:PanelForm = New-SupportPanel
    $script:PanelForm.Owner = $launcher
    $script:NewsSignature = $null
    Apply-SupportPageVisual -Page Ticket
    Update-WidgetChrome
    Set-SupportBounds
    Ensure-TrayIcon
    Register-ThemeChanges
    Set-LauncherChrome
    if ('DesktopHost' -as [type] -and $launcher.IsHandleCreated) {
        try { [DesktopHost]::PrepareLauncher($launcher.Handle) } catch { }
    }
    if (Test-ShowLauncher) { Write-Log 'Кнопка поддержки показана в углу экрана.' }
    else { Write-Log 'Кнопка поддержки скрыта. Программа остаётся у часов.' }
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
    [void]$menu.Items.Add((New-Object System.Windows.Forms.ToolStripSeparator))
    $buttonItem = New-Object System.Windows.Forms.ToolStripMenuItem
    $buttonItem.Text = 'Кнопка на экране'
    $buttonItem.CheckOnClick = $true
    $buttonItem.Checked = Test-ShowLauncher
    $script:LauncherMenuItem = $buttonItem
    [void]$menu.Items.Add($buttonItem)
    $exitItem = $menu.Items.Add('Выход')
    $openItem.Add_Click({ Show-SupportPanel -Page $script:WidgetPage })
    $ticketItem.Add_Click({ Show-SupportPanel -Page Ticket })
    $newsItem.Add_Click({ Show-SupportPanel -Page News })
    $buttonItem.Add_Click({
        $show = [bool]$script:LauncherMenuItem.Checked
        if ($script:State) {
            $script:State.ShowLauncher = $show
            Save-StateTable $script:State
        }
        Set-LauncherChrome
    })
    $exitItem.Add_Click({ Stop-DesktopWidgetApp })
    $icon.ContextMenuStrip = $menu
    $script:TrayMenu = $menu
    Apply-TrayMenuPalette
    $icon.Add_DoubleClick({ Show-SupportPanel -Page Ticket })
    $script:TrayIcon = $icon
}

function Stop-DesktopWidgetApp {
    Unregister-ThemeChanges
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
    $button = 52
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
    $ink = Get-ThemeColor Ink
    $muted = Get-ThemeColor Muted
    $canvas = Get-ThemeColor Canvas
    $hover = Get-ThemeColor Hover
    $ruleColor = Get-ThemeColor Rule
    $form = New-Object System.Windows.Forms.Form
    $form.FormBorderStyle = 'None'
    $form.ShowInTaskbar = $false
    $form.StartPosition = 'Manual'
    $form.TopMost = $true
    $form.BackColor = $canvas
    $form.ClientSize = New-Object System.Drawing.Size(280, 120)
    $form.Font = $script:TabFont
    $form.Text = 'Новости'
    $header = New-Object System.Windows.Forms.Panel
    $header.SetBounds(0, 0, 280, 36)
    $header.BackColor = $canvas
    $title = New-Object System.Windows.Forms.Label
    $title.Text = 'Новости'
    $title.ForeColor = $ink
    $title.BackColor = $canvas
    $title.Font = $script:TabFontBold
    $title.AutoEllipsis = $true
    $title.SetBounds(12, 8, 220, 20)
    $title.Add_Click({ Open-NewsFromPopup })
    $close = New-Object System.Windows.Forms.Button
    $close.Text = [string][char]0x00D7
    $close.SetBounds(244, 4, 28, 26)
    $close.FlatStyle = 'Flat'
    $close.FlatAppearance.BorderSize = 0
    $close.FlatAppearance.MouseOverBackColor = $hover
    $close.BackColor = $canvas
    $close.ForeColor = $muted
    $close.Font = $script:TitleFont
    $close.Cursor = [System.Windows.Forms.Cursors]::Hand
    $close.TabStop = $false
    $close.Add_Click({ Hide-NewsPopup })
    $headerRule = New-Object System.Windows.Forms.Panel
    $headerRule.SetBounds(12, 35, 256, 1)
    $headerRule.BackColor = $ruleColor
    $header.Controls.Add($title)
    $header.Controls.Add($close)
    $header.Controls.Add($headerRule)
    $body = New-Object System.Windows.Forms.Panel
    $body.SetBounds(0, 36, 280, 84)
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
    try { Ensure-DesktopWidget } catch {
        Write-Log ("Сбой виджета: {0}" -f $_.Exception.ToString()) 'ERROR'
        throw
    }
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
