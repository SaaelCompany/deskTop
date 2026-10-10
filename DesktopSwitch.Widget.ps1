# Desktop widget: service-desk request, news, and maintenance notices.
# Windows PowerShell 5.1, STA. No administrator rights.

Set-StrictMode -Version 2.0

$script:WidgetForm = $null
$script:WidgetUi = $null
$script:WidgetHost = [IntPtr]::Zero
$script:TrayIcon = $null
$script:NewsItems = @()
$script:LastNewsPoll = [datetime]::MinValue
$script:NewsHintShown = $false
$script:AllowExit = $false
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

function Set-WidgetBounds {
    param($Form)
    if ($null -eq $Form -or $Form.IsDisposed) { return }
    $screen = [System.Windows.Forms.Screen]::PrimaryScreen.WorkingArea
    $margin = 16
    if ($script:Cfg) { $margin = [int]$script:Cfg.WidgetMargin }
    $x = $screen.Left + $margin
    $y = $screen.Top + $margin
    $corner = 'BottomRight'
    if ($script:Cfg) { $corner = [string]$script:Cfg.WidgetCorner }
    switch ($corner) {
        'BottomRight' {
            $x = $screen.Right - $Form.Width - $margin
            $y = $screen.Bottom - $Form.Height - $margin
        }
        'BottomLeft' { $y = $screen.Bottom - $Form.Height - $margin }
        'TopRight' { $x = $screen.Right - $Form.Width - $margin }
    }
    if ($script:WidgetHost -ne [IntPtr]::Zero) {
        $point = [DesktopHost]::ToClient($script:WidgetHost, $x, $y)
        $Form.Location = New-Object System.Drawing.Point([int]$point.X, [int]$point.Y)
    } else {
        $Form.Location = New-Object System.Drawing.Point($x, $y)
    }
}

function Update-WidgetChrome {
    if ($null -eq $script:WidgetForm -or $script:WidgetForm.IsDisposed -or $null -eq $script:WidgetUi) { return }
    $mode = [string]$script:DesktopMode
    $verdict = [string]$script:DesktopVerdict
    $status = 'Проверка сети'
    $statusColor = [System.Drawing.Color]::FromArgb(93, 109, 126)
    if ($mode -eq 'Local') {
        $status = 'Локальный рабочий стол'
        $statusColor = [System.Drawing.Color]::FromArgb(146, 43, 33)
    } elseif ($mode -eq 'Network') {
        $status = 'Сетевой рабочий стол'
        if ($verdict -eq 'Online') { $statusColor = [System.Drawing.Color]::FromArgb(25, 111, 61) }
        else { $statusColor = [System.Drawing.Color]::FromArgb(31, 78, 121) }
    }
    $script:WidgetUi.Status.Text = $status
    $script:WidgetUi.Status.ForeColor = $statusColor
    $session = Get-WindowsSessionIdentity
    $script:WidgetUi.Identity.Text = ('{0}  ·  {1}' -f $session.Login, $session.Computer)

    $headline = Get-WidgetHeadline $script:NewsItems
    $showMaintenance = [string]$headline.Kind -eq 'maintenance'
    $script:WidgetUi.Maintenance.Visible = $showMaintenance
    if ($showMaintenance) { $script:WidgetUi.Maintenance.Text = [string]$headline.Title }
    if ($showMaintenance) { $script:WidgetUi.News.Text = 'Откройте новости, чтобы прочитать подробности.' }
    else { $script:WidgetUi.News.Text = [string]$headline.Title }

    $y = 92
    if ($showMaintenance) {
        $script:WidgetUi.Maintenance.SetBounds(12, $y, 316, 36)
        $y += 40
    }
    $script:WidgetUi.News.SetBounds(12, $y, 316, 40)
    $y += 46
    $script:WidgetUi.TicketButton.SetBounds(12, $y, 150, 32)
    $script:WidgetUi.NewsButton.SetBounds(174, $y, 154, 32)
    $script:WidgetForm.ClientSize = New-Object System.Drawing.Size(340, ($y + 46))
    Set-WidgetBounds $script:WidgetForm
}

function Update-WidgetStatus {
    Update-WidgetChrome
}

function New-FlatButton {
    param([string]$Text, [System.Drawing.Point]$Location, [System.Drawing.Size]$Size)
    $button = New-Object System.Windows.Forms.Button
    $button.Text = $Text
    $button.Location = $Location
    $button.Size = $Size
    $button.FlatStyle = 'Flat'
    $button.BackColor = [System.Drawing.Color]::FromArgb(27, 79, 114)
    $button.ForeColor = [System.Drawing.Color]::White
    $button.Font = New-Object System.Drawing.Font('Segoe UI', 9)
    $button.FlatAppearance.BorderSize = 0
    return $button
}

function New-DesktopWidget {
    Add-Type -AssemblyName System.Windows.Forms
    Add-Type -AssemblyName System.Drawing
    if (-not (Initialize-DesktopHost)) { $script:WidgetHost = [IntPtr]::Zero }
    else { $script:WidgetHost = [DesktopHost]::Find() }

    $title = 'Сервисная служба'
    if ($script:Cfg -and -not [string]::IsNullOrWhiteSpace([string]$script:Cfg.WidgetTitle)) {
        $title = [string]$script:Cfg.WidgetTitle
    }

    $form = New-Object System.Windows.Forms.Form
    $form.Text = $title
    $form.FormBorderStyle = 'None'
    $form.ShowInTaskbar = $false
    $form.StartPosition = 'Manual'
    $form.TopMost = $false
    $form.BackColor = [System.Drawing.Color]::FromArgb(247, 249, 251)
    $form.ClientSize = New-Object System.Drawing.Size(340, 188)
    $form.Font = New-Object System.Drawing.Font('Segoe UI', 9)

    $header = New-Object System.Windows.Forms.Panel
    $header.SetBounds(0, 0, 340, 40)
    $header.BackColor = [System.Drawing.Color]::FromArgb(27, 79, 114)
    $headerLabel = New-Object System.Windows.Forms.Label
    $headerLabel.Text = $title
    $headerLabel.ForeColor = [System.Drawing.Color]::White
    $headerLabel.Font = New-Object System.Drawing.Font('Segoe UI', 11, [System.Drawing.FontStyle]::Bold)
    $headerLabel.SetBounds(12, 8, 316, 24)
    $header.Controls.Add($headerLabel)

    $status = New-Object System.Windows.Forms.Label
    $status.Text = 'Проверка сети'
    $status.SetBounds(12, 46, 316, 18)
    $status.ForeColor = [System.Drawing.Color]::FromArgb(93, 109, 126)
    $identity = New-Object System.Windows.Forms.Label
    $identity.Text = ''
    $identity.SetBounds(12, 66, 316, 18)
    $identity.ForeColor = [System.Drawing.Color]::FromArgb(93, 109, 126)

    $maintenance = New-Object System.Windows.Forms.Label
    $maintenance.Visible = $false
    $maintenance.BackColor = [System.Drawing.Color]::FromArgb(253, 235, 208)
    $maintenance.ForeColor = [System.Drawing.Color]::FromArgb(154, 91, 0)
    $maintenance.TextAlign = 'MiddleLeft'
    $maintenance.Padding = New-Object System.Windows.Forms.Padding(6, 0, 6, 0)
    $maintenance.SetBounds(12, 74, 316, 36)

    $news = New-Object System.Windows.Forms.Label
    $news.Text = 'Пока нет сообщений'
    $news.SetBounds(12, 74, 316, 40)
    $news.ForeColor = [System.Drawing.Color]::FromArgb(28, 40, 51)

    $ticketButton = New-FlatButton -Text 'Заявка' -Location (New-Object System.Drawing.Point(12, 120)) -Size (New-Object System.Drawing.Size(150, 32))
    $newsButton = New-FlatButton -Text 'Новости' -Location (New-Object System.Drawing.Point(174, 120)) -Size (New-Object System.Drawing.Size(154, 32))
    $ticketButton.Add_Click({ Show-TicketDialog })
    $newsButton.Add_Click({ Show-NewsDialog })
    $news.Add_Click({ Show-NewsDialog })

    $form.Controls.Add($header)
    $form.Controls.Add($status)
    $form.Controls.Add($identity)
    $form.Controls.Add($maintenance)
    $form.Controls.Add($news)
    $form.Controls.Add($ticketButton)
    $form.Controls.Add($newsButton)
    $form.Add_FormClosing({
        if ($script:AllowExit) { return }
        if ($_.CloseReason -eq [System.Windows.Forms.CloseReason]::UserClosing) { $_.Cancel = $true }
    })
    $form.Add_HandleDestroyed({
        if (-not $script:AllowExit) { $script:WidgetForm = $null }
    })

    $script:WidgetForm = $form
    $script:WidgetUi = @{
        Status = $status
        Identity = $identity
        Maintenance = $maintenance
        News = $news
        TicketButton = $ticketButton
        NewsButton = $newsButton
    }
    Ensure-TrayIcon
    Update-WidgetChrome
    if ($script:WidgetHost -ne [IntPtr]::Zero) {
        [DesktopHost]::Attach($form.Handle, $script:WidgetHost)
        Set-WidgetBounds $form
        Write-Log 'Виджет размещён на рабочем столе.'
    } else {
        Write-Log 'Рабочий стол не отдал область для виджета. Виджет показан в углу экрана.' 'WARN'
    }
    $form.Show()
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
    $ticketItem = $menu.Items.Add('Заявка')
    $newsItem = $menu.Items.Add('Новости')
    $exitItem = $menu.Items.Add('Выход')
    $ticketItem.Add_Click({ Show-TicketDialog })
    $newsItem.Add_Click({ Show-NewsDialog })
    $exitItem.Add_Click({ Stop-DesktopWidgetApp })
    $icon.ContextMenuStrip = $menu
    $icon.Add_DoubleClick({ Ensure-DesktopWidget })
    $script:TrayIcon = $icon
}

function Stop-DesktopWidgetApp {
    $script:AllowExit = $true
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
    Add-Type -AssemblyName System.Windows.Forms
    Add-Type -AssemblyName System.Drawing
    if (-not $script:Cfg -or [string]::IsNullOrWhiteSpace([string]$script:Cfg.NewsUrl)) {
        [System.Windows.Forms.MessageBox]::Show('Адрес ленты новостей задаёт администратор в config.json, поле Widget.NewsUrl.', 'Новости') | Out-Null
        return
    }
    $dialog = New-Object System.Windows.Forms.Form
    $dialog.Text = 'Новости и технические работы'
    $dialog.StartPosition = 'CenterScreen'
    $dialog.TopMost = $true
    $dialog.ClientSize = New-Object System.Drawing.Size(520, 420)
    $dialog.Font = New-Object System.Drawing.Font('Segoe UI', 9)
    $list = New-Object System.Windows.Forms.ListBox
    $list.SetBounds(12, 12, 496, 160)
    $body = New-Object System.Windows.Forms.TextBox
    $body.Multiline = $true
    $body.ReadOnly = $true
    $body.ScrollBars = 'Vertical'
    $body.SetBounds(12, 184, 496, 176)
    $open = New-FlatButton -Text 'Открыть ссылку' -Location (New-Object System.Drawing.Point(12, 372)) -Size (New-Object System.Drawing.Size(160, 32))
    $items = @($script:NewsItems)
    foreach ($item in $items) {
        if ($null -eq $item) { continue }
        $prefix = 'Новость'
        if ([string]$item.Kind -eq 'maintenance') { $prefix = 'Работы' }
        [void]$list.Items.Add(('{0}: {1}' -f $prefix, [string]$item.Title))
    }
    $list.Add_SelectedIndexChanged({
        $index = $list.SelectedIndex
        if ($index -ge 0 -and $index -lt $items.Count -and $null -ne $items[$index]) {
            $body.Text = [string]$items[$index].Body
        }
    })
    $open.Add_Click({
        $index = $list.SelectedIndex
        if ($index -ge 0 -and $index -lt $items.Count -and $null -ne $items[$index] -and -not [string]::IsNullOrWhiteSpace([string]$items[$index].Url)) {
            Start-Process ([string]$items[$index].Url)
        }
    })
    if ($list.Items.Count -gt 0) { $list.SelectedIndex = 0 }
    $dialog.Controls.Add($list)
    $dialog.Controls.Add($body)
    $dialog.Controls.Add($open)
    [void]$dialog.ShowDialog()
    $dialog.Dispose()
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
    Add-Type -AssemblyName System.Windows.Forms
    Add-Type -AssemblyName System.Drawing
    $api = ''
    $portal = ''
    if ($script:Cfg) {
        $api = [string]$script:Cfg.ServiceDeskApiUrl
        $portal = [string]$script:Cfg.ServiceDeskUrl
    }
    $session = Get-WindowsSessionIdentity
    if ([string]::IsNullOrWhiteSpace($api) -and -not [string]::IsNullOrWhiteSpace($portal)) {
        Start-Process (Expand-ServiceDeskUrl -Url $portal -Login $session.Login -Computer $session.Computer)
        return
    }
    if ([string]::IsNullOrWhiteSpace($api)) {
        [System.Windows.Forms.MessageBox]::Show('Адрес сервис-деска задаёт администратор в config.json: Widget.ServiceDeskApiUrl или Widget.ServiceDeskUrl.', 'Заявка') | Out-Null
        return
    }

    $dialog = New-Object System.Windows.Forms.Form
    $dialog.Text = 'Заявка в сервис-деск'
    $dialog.StartPosition = 'CenterScreen'
    $dialog.TopMost = $true
    $dialog.ClientSize = New-Object System.Drawing.Size(460, 430)
    $dialog.Font = New-Object System.Drawing.Font('Segoe UI', 9)
    $loginLabel = New-Object System.Windows.Forms.Label
    $loginLabel.Text = 'Логин Windows'
    $loginLabel.SetBounds(12, 12, 210, 18)
    $loginBox = New-Object System.Windows.Forms.TextBox
    $loginBox.ReadOnly = $true
    $loginBox.TabStop = $false
    $loginBox.Text = $session.Login
    $loginBox.SetBounds(12, 32, 210, 24)
    $computerLabel = New-Object System.Windows.Forms.Label
    $computerLabel.Text = 'Компьютер'
    $computerLabel.SetBounds(234, 12, 210, 18)
    $computerBox = New-Object System.Windows.Forms.TextBox
    $computerBox.ReadOnly = $true
    $computerBox.TabStop = $false
    $computerBox.Text = $session.Computer
    $computerBox.SetBounds(234, 32, 214, 24)
    $categoryLabel = New-Object System.Windows.Forms.Label
    $categoryLabel.Text = 'Категория'
    $categoryLabel.SetBounds(12, 64, 430, 18)
    $category = New-Object System.Windows.Forms.ComboBox
    $category.DropDownStyle = 'DropDownList'
    [void]$category.Items.Add('Инцидент')
    [void]$category.Items.Add('Запрос обслуживания')
    [void]$category.Items.Add('Вопрос')
    $category.SelectedIndex = 0
    $category.SetBounds(12, 84, 436, 24)
    $subjectLabel = New-Object System.Windows.Forms.Label
    $subjectLabel.Text = 'Тема'
    $subjectLabel.SetBounds(12, 116, 430, 18)
    $subject = New-Object System.Windows.Forms.TextBox
    $subject.SetBounds(12, 136, 436, 24)
    $bodyLabel = New-Object System.Windows.Forms.Label
    $bodyLabel.Text = 'Описание'
    $bodyLabel.SetBounds(12, 168, 430, 18)
    $body = New-Object System.Windows.Forms.TextBox
    $body.Multiline = $true
    $body.ScrollBars = 'Vertical'
    $body.SetBounds(12, 188, 436, 150)
    $send = New-FlatButton -Text 'Отправить' -Location (New-Object System.Drawing.Point(12, 356)) -Size (New-Object System.Drawing.Size(140, 32))
    $portalButton = New-FlatButton -Text 'Открыть портал' -Location (New-Object System.Drawing.Point(164, 356)) -Size (New-Object System.Drawing.Size(150, 32))
    $portalButton.Visible = -not [string]::IsNullOrWhiteSpace($portal)
    $portalButton.Add_Click({
        if (-not [string]::IsNullOrWhiteSpace($portal)) {
            $who = Get-WindowsSessionIdentity
            Start-Process (Expand-ServiceDeskUrl -Url $portal -Login $who.Login -Computer $who.Computer)
        }
    })
    $send.Add_Click({
        $errors = Test-TicketDraft -Subject $subject.Text -Body $body.Text
        if ($errors.Count -gt 0) {
            [System.Windows.Forms.MessageBox]::Show([string]::Join("`n", @($errors)), 'Заявка') | Out-Null
            return
        }
        $who = Get-WindowsSessionIdentity
        $payload = New-TicketPayload -Subject $subject.Text -Body $body.Text -Category ([string]$category.SelectedItem) -User $who.Login -Computer $who.Computer -CreatedAt ((Get-Date).ToString('o'))
        try {
            $code = Send-TicketRequest $payload
            Write-Log ("Заявка отправлена, ответ сервис-деска: {0}, категория: {1}, пользователь: {2}, компьютер: {3}." -f $code, $payload.category, $payload.user, $payload.computer)
            [System.Windows.Forms.MessageBox]::Show('Заявка отправлена.', 'Заявка') | Out-Null
            $dialog.Close()
        } catch {
            Write-Log ("Заявку отправить не удалось: {0}" -f $_.Exception.Message) 'WARN'
            [System.Windows.Forms.MessageBox]::Show('Сервис-деск не принял заявку. Попробуйте ещё раз или откройте портал.', 'Заявка') | Out-Null
        }
    })
    $dialog.Controls.Add($loginLabel)
    $dialog.Controls.Add($loginBox)
    $dialog.Controls.Add($computerLabel)
    $dialog.Controls.Add($computerBox)
    $dialog.Controls.Add($categoryLabel)
    $dialog.Controls.Add($category)
    $dialog.Controls.Add($subjectLabel)
    $dialog.Controls.Add($subject)
    $dialog.Controls.Add($bodyLabel)
    $dialog.Controls.Add($body)
    $dialog.Controls.Add($send)
    $dialog.Controls.Add($portalButton)
    [void]$dialog.ShowDialog()
    $dialog.Dispose()
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
