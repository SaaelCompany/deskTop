#Requires -Version 5.1
<#
    Следит за интернетом и общей папкой рабочего стола.
    Когда связи нет, папка «Рабочий стол» текущего пользователя переключается
    на локальный диск. Когда связь возвращается, восстанавливается сетевой путь.

    Запуск в сеансе пользователя, права администратора не нужны:
      powershell.exe -NoProfile -STA -ExecutionPolicy Bypass -File .\DesktopSwitch.ps1
      powershell.exe -NoProfile -STA -ExecutionPolicy Bypass -File .\DesktopSwitch.ps1 -Status
      powershell.exe -NoProfile -STA -ExecutionPolicy Bypass -File .\DesktopSwitch.ps1 -Once -WhatIf
#>
[CmdletBinding()]
param(
    [Alias('Config')]
    [string]$ConfigPath,
    [switch]$Once,
    [switch]$Status,
    [switch]$WhatIf
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

. (Join-Path $PSScriptRoot 'DesktopSwitch.Logic.ps1')
. (Join-Path $PSScriptRoot 'DesktopSwitch.Widget.ps1')

$script:Version = '1.2.37'
$script:Cfg = $null
$script:State = $null
$script:LogFile = $null
$script:MaxLogBytes = 1048576
$script:Mutex = $null
$script:MutexOwned = $false
$script:NativeReady = $false
$script:NativeTried = $false
$script:BackgroundIo = $null

$script:NativeSource = @'
using System;
using System.Runtime.InteropServices;

public sealed class KnownFolderCall {
    public int HResult;
    public string Path;
}

public static class KnownFolderNative {
    static Guid DesktopId = new Guid("B4BFCC3A-DB2C-424C-B029-7FE99A87C641");
    const uint KF_FLAG_DONT_VERIFY = 0x00004000;
    const int SHCNE_ASSOCCHANGED = 0x08000000;
    const uint SHCNF_FLUSHNOWAIT = 0x00002000;
    const uint WM_SETTINGCHANGE = 0x001A;
    const uint SMTO_ABORTIFHUNG = 0x0002;

    [DllImport("shell32.dll", CharSet = CharSet.Unicode)]
    static extern int SHGetKnownFolderPath(ref Guid rfid, uint dwFlags, IntPtr hToken, out IntPtr pszPath);

    [DllImport("shell32.dll", CharSet = CharSet.Unicode)]
    static extern int SHSetKnownFolderPath(ref Guid rfid, uint dwFlags, IntPtr hToken, string pszPath);

    [DllImport("ole32.dll")]
    static extern void CoTaskMemFree(IntPtr pv);

    [DllImport("shell32.dll")]
    static extern void SHChangeNotify(int wEventId, uint uFlags, IntPtr dwItem1, IntPtr dwItem2);

    [DllImport("user32.dll", CharSet = CharSet.Unicode)]
    static extern IntPtr SendMessageTimeout(
        IntPtr hWnd,
        uint Msg,
        UIntPtr wParam,
        string lParam,
        uint fuFlags,
        uint uTimeout,
        out UIntPtr lpdwResult);

    public static KnownFolderCall GetDesktop() {
        KnownFolderCall call = new KnownFolderCall();
        IntPtr ptr;
        Guid id = DesktopId;
        int hr = SHGetKnownFolderPath(ref id, KF_FLAG_DONT_VERIFY, IntPtr.Zero, out ptr);
        call.HResult = hr;
        if (ptr != IntPtr.Zero) {
            if (hr == 0) {
                call.Path = Marshal.PtrToStringUni(ptr);
            }
            CoTaskMemFree(ptr);
        }
        return call;
    }

    public static int SetDesktop(string path) {
        Guid id = DesktopId;
        return SHSetKnownFolderPath(ref id, 0, IntPtr.Zero, path);
    }

    public static void NotifyShell() {
        SHChangeNotify(SHCNE_ASSOCCHANGED, SHCNF_FLUSHNOWAIT, IntPtr.Zero, IntPtr.Zero);
        UIntPtr ignored;
        SendMessageTimeout(new IntPtr(0xFFFF), WM_SETTINGCHANGE, UIntPtr.Zero, "Shell", SMTO_ABORTIFHUNG, 2000, out ignored);
    }
}
'@

$script:SyncCode = @'
param($Source, $Destination, $Extensions)
$wanted = @{}
foreach ($ext in @($Extensions)) {
    $name = ([string]$ext).Trim().ToLowerInvariant()
    if (-not $name.StartsWith(".")) { $name = "." + $name }
    if ($name.Length -gt 1) { $wanted[$name] = $true }
}
if (-not [System.IO.Directory]::Exists($Source)) { return 0 }
if (-not [System.IO.Directory]::Exists($Destination)) {
    [void][System.IO.Directory]::CreateDirectory($Destination)
}
$copied = 0
foreach ($file in [System.IO.Directory]::GetFiles($Source)) {
    $ext = [System.IO.Path]::GetExtension($file).ToLowerInvariant()
    if (-not $wanted.ContainsKey($ext)) { continue }
    $dest = [System.IO.Path]::Combine($Destination, [System.IO.Path]::GetFileName($file))
    $copy = $true
    if ([System.IO.File]::Exists($dest)) {
        $srcInfo = New-Object System.IO.FileInfo $file
        $dstInfo = New-Object System.IO.FileInfo $dest
        if ($dstInfo.Length -eq $srcInfo.Length -and $dstInfo.LastWriteTimeUtc -ge $srcInfo.LastWriteTimeUtc) {
            $copy = $false
        }
    }
    if ($copy) {
        [System.IO.File]::Copy($file, $dest, $true)
        $copied++
    }
}
return $copied
'@

function Resolve-ConfigPath {
    param([string]$Explicit)
    if (-not [string]::IsNullOrWhiteSpace($Explicit)) {
        if (-not (Test-Path -LiteralPath $Explicit)) {
            throw "Файл конфигурации не найден: $Explicit"
        }
        return (Resolve-Path -LiteralPath $Explicit).Path
    }
    $beside = Join-Path $PSScriptRoot 'config.json'
    if (Test-Path -LiteralPath $beside) { return (Resolve-Path -LiteralPath $beside).Path }
    $example = Join-Path $PSScriptRoot 'config.example.json'
    throw "Рядом со скриптом нет config.json. Скопируйте '$example' в '$beside' и поставьте Enabled в true. Сетевой путь политика записывает сама."
}

function Read-DesktopConfig {
    param([string]$Path)
    $raw = Get-Content -LiteralPath $Path -Raw -Encoding UTF8
    if ([string]::IsNullOrWhiteSpace($raw)) { throw "Файл конфигурации пуст: $Path" }
    return (ConvertFrom-DesktopJson $raw)
}

function Initialize-Log {
    $dir = Split-Path -Parent $script:LogFile
    try {
        if ($dir -and -not (Test-Path -LiteralPath $dir)) {
            New-Item -ItemType Directory -Force -Path $dir | Out-Null
        }
    } catch {
        $fallback = Join-Path $env:TEMP 'DesktopSwitch.log'
        $script:LogFile = $fallback
        $dir = Split-Path -Parent $fallback
        if ($dir -and -not (Test-Path -LiteralPath $dir)) {
            New-Item -ItemType Directory -Force -Path $dir | Out-Null
        }
    }
}

function Write-Log {
    param([string]$Message, [string]$Level = 'INFO')
    $line = '{0:yyyy-MM-dd HH:mm:ss} [{1}] {2}' -f (Get-Date), $Level, $Message
    if ($script:LogFile) {
        try {
            if ((Test-Path -LiteralPath $script:LogFile) -and ((Get-Item -LiteralPath $script:LogFile).Length -gt $script:MaxLogBytes)) {
                Move-Item -LiteralPath $script:LogFile -Destination ($script:LogFile + '.1') -Force
            }
            Add-Content -LiteralPath $script:LogFile -Value $line -Encoding UTF8
        } catch {
        }
    }
    Write-Host $line
}

function Initialize-DesktopNative {
    if ($script:NativeReady) { return $true }
    if ($script:NativeTried) { return $false }
    $script:NativeTried = $true
    if ('KnownFolderNative' -as [type]) {
        $script:NativeReady = $true
        return $true
    }
    try {
        Add-Type -TypeDefinition $script:NativeSource -ErrorAction Stop
        $script:NativeReady = $true
        return $true
    } catch {
        Write-Log ("Интерфейс оболочки недоступен, путь рабочего стола читается из реестра: {0}" -f $_.Exception.Message) 'WARN'
        return $false
    }
}

function Get-DesktopPathFromRegistry {
    $usf = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\User Shell Folders'
    $props = Get-ItemProperty -LiteralPath $usf -Name 'Desktop' -ErrorAction Stop
    return ConvertTo-ExpandedPath ([string]$props.Desktop)
}

function Get-CurrentDesktopPath {
    if (Initialize-DesktopNative) {
        $call = [KnownFolderNative]::GetDesktop()
        if ($call.HResult -eq 0 -and -not [string]::IsNullOrWhiteSpace($call.Path)) {
            return [string]$call.Path
        }
        Write-Log ("SHGetKnownFolderPath вернул код {0}. Читаю реестр." -f $call.HResult) 'WARN'
    }
    return Get-DesktopPathFromRegistry
}

function Set-DesktopRegistryPath {
    param([string]$Path)
    $usf = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\User Shell Folders'
    $shellFolders = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Shell Folders'
    if (-not (Test-Path -LiteralPath $usf)) {
        New-Item -Path $usf -Force | Out-Null
    }
    New-ItemProperty -LiteralPath $usf -Name 'Desktop' -Value $Path -PropertyType ExpandString -Force | Out-Null
    if (Test-Path -LiteralPath $shellFolders) {
        New-ItemProperty -LiteralPath $shellFolders -Name 'Desktop' -Value $Path -PropertyType String -Force | Out-Null
    }
    # Folder Redirection stores the same folder under its GUID. Update that value
    # when it already exists so an offline policy refresh does not leave a stale UNC.
    $key = Get-Item -LiteralPath $usf
    $guidName = '{B4BFCC3A-DB2C-424C-B029-7FE99A87C641}'
    $currentGuid = $key.GetValue($guidName)
    if ($null -ne $currentGuid) {
        $kind = $key.GetValueKind($guidName)
        $propertyType = 'String'
        if ($kind -eq [Microsoft.Win32.RegistryValueKind]::ExpandString) { $propertyType = 'ExpandString' }
        New-ItemProperty -LiteralPath $usf -Name $guidName -Value $Path -PropertyType $propertyType -Force | Out-Null
    }
}

function Set-CurrentDesktopPath {
    param([string]$Path)
    if ([string]::IsNullOrWhiteSpace($Path)) { throw 'Пустой путь рабочего стола.' }
    # A UNC desktop already exists on the server. Creating it from here can hang or
    # throw, and then the shell path is never written back.
    if (-not (Test-UncPathString $Path)) {
        if (-not (Test-Path -LiteralPath $Path)) {
            New-Item -ItemType Directory -Path $Path -Force | Out-Null
        }
    }
    Set-DesktopRegistryPath -Path $Path
    if (Initialize-DesktopNative) {
        $hr = [KnownFolderNative]::SetDesktop($Path)
        if ($hr -ne 0) {
            Write-Log ("SHSetKnownFolderPath вернул код {0}. Значение в реестре уже записано." -f $hr) 'WARN'
        }
        [KnownFolderNative]::NotifyShell()
    }
}

function Test-BackgroundIoBusy {
    if ($null -eq $script:BackgroundIo) { return $false }
    if (-not $script:BackgroundIo.Handle.IsCompleted) { return $true }
    try { $null = $script:BackgroundIo.Shell.EndInvoke($script:BackgroundIo.Handle) } catch { }
    try { $script:BackgroundIo.Shell.Dispose() } catch { }
    $script:BackgroundIo = $null
    return $false
}

function Start-BackgroundIo {
    param([string]$Code, [object[]]$Arguments, [string]$Kind)
    if ([string]::IsNullOrWhiteSpace($Kind)) { $Kind = 'probe' }
    $ps = [powershell]::Create()
    $null = $ps.AddScript($Code)
    foreach ($argument in $Arguments) { $null = $ps.AddArgument($argument) }
    $handle = $ps.BeginInvoke()
    $script:BackgroundIo = @{ Shell = $ps; Handle = $handle; Kind = $Kind; Started = Get-Date }
    return $handle
}

function Release-StaleBackgroundIo {
    param([int]$LimitSec)
    if ($null -eq $script:BackgroundIo) { return }
    if ($script:BackgroundIo.Handle.IsCompleted) { return }
    $started = $script:BackgroundIo.Started
    if ($null -eq $started) { return }
    if (((Get-Date) - [datetime]$started).TotalSeconds -lt $LimitSec) { return }
    Write-Log 'Проверка общей папки зависла и больше не блокирует возврат на сетевой стол.' 'WARN'
    $script:BackgroundIo = $null
}

function Wait-BackgroundIo {
    param([int]$TimeoutSec)
    if ($null -eq $script:BackgroundIo) {
        return [pscustomobject]@{ TimedOut = $false; Value = $null }
    }
    $finished = $script:BackgroundIo.Handle.AsyncWaitHandle.WaitOne([TimeSpan]::FromSeconds($TimeoutSec))
    if (-not $finished) {
        # Leave the runspace alive. Stopping a thread blocked in SMB can hang
        # the monitor; the next cycle treats the share as down until the call ends.
        return [pscustomobject]@{ TimedOut = $true; Value = $null }
    }
    $value = $null
    try {
        $collected = $script:BackgroundIo.Shell.EndInvoke($script:BackgroundIo.Handle)
        $items = @($collected)
        if ($items.Count -gt 0) { $value = $items[0] }
    } catch {
        $value = $null
    } finally {
        try { $script:BackgroundIo.Shell.Dispose() } catch { }
        $script:BackgroundIo = $null
    }
    return [pscustomobject]@{ TimedOut = $false; Value = $value }
}

function Test-TcpPort {
    param([string]$HostName, [int]$Port, [int]$TimeoutSec)
    $client = New-Object System.Net.Sockets.TcpClient
    try {
        $wait = $client.BeginConnect($HostName, $Port, $null, $null)
        $opened = $wait.AsyncWaitHandle.WaitOne([TimeSpan]::FromSeconds($TimeoutSec))
        if (-not $opened) { return $false }
        try { $client.EndConnect($wait) } catch { return $false }
        return [bool]$client.Connected
    } catch {
        return $false
    } finally {
        $client.Close()
    }
}

function Get-ShareStatus {
    param([string]$UncPath, [int]$TimeoutSec)
    $limit = $TimeoutSec * 2
    if ($limit -lt 12) { $limit = 12 }
    Release-StaleBackgroundIo -LimitSec $limit
    if (Test-BackgroundIoBusy) {
        $kind = ''
        try { $kind = [string]$script:BackgroundIo.Kind } catch { $kind = '' }
        # Copying shortcuts means the share was reachable. A probe still in flight is not proof that it is down.
        if ($kind -eq 'sync') { return 'Up' }
        return 'Unknown'
    }
    if (-not (Test-UncPathString $UncPath)) { return 'Unknown' }
    $server = Get-UncHost $UncPath
    if ([string]::IsNullOrWhiteSpace($server)) { return 'Down' }
    if (-not (Test-TcpPort -HostName $server -Port 445 -TimeoutSec $TimeoutSec)) { return 'Down' }
    Start-BackgroundIo -Code 'param($p) [System.IO.Directory]::Exists($p)' -Arguments @($UncPath) -Kind 'probe' | Out-Null
    $wait = Wait-BackgroundIo -TimeoutSec $TimeoutSec
    if ($wait.TimedOut -or $wait.Value -ne $true) { return 'Down' }
    return 'Up'
}

function Test-WindowsInternet {
    $nlm = $null
    try {
        $clsid = [Guid]'DCB00C01-570F-4A9B-8D69-199FDBA5723B'
        $type = [Type]::GetTypeFromCLSID($clsid)
        if ($null -eq $type) { return $null }
        $nlm = [Activator]::CreateInstance($type)
        $connectivity = [int]$nlm.GetConnectivity()
        $ipv4Internet = 0x40
        $ipv6Internet = 0x400
        return (($connectivity -band $ipv4Internet) -ne 0) -or (($connectivity -band $ipv6Internet) -ne 0)
    } catch {
        Write-Log ("Проверка статуса сети Windows не выполнилась: {0}" -f $_.Exception.Message) 'WARN'
        return $null
    } finally {
        if ($null -ne $nlm) {
            try { [void][Runtime.InteropServices.Marshal]::ReleaseComObject($nlm) } catch { }
        }
    }
}

function Test-ProbeUrl {
    param([string]$Url, [int]$TimeoutSec, [string]$ExpectedBody)
    $response = $null
    try {
        $request = [System.Net.HttpWebRequest]::Create($Url)
        $request.Method = 'GET'
        $request.Timeout = $TimeoutSec * 1000
        $request.ReadWriteTimeout = $TimeoutSec * 1000
        $request.UserAgent = 'DesktopSwitch'
        $request.AllowAutoRedirect = $false
        $proxy = [System.Net.WebRequest]::GetSystemWebProxy()
        $proxy.Credentials = [System.Net.CredentialCache]::DefaultNetworkCredentials
        $request.Proxy = $proxy
        $response = $request.GetResponse()
        $code = [int]$response.StatusCode
        if ($code -lt 200 -or $code -ge 300) { return $false }
        if ([string]::IsNullOrWhiteSpace($ExpectedBody)) { return $true }
        $reader = New-Object System.IO.StreamReader($response.GetResponseStream())
        try { $body = $reader.ReadToEnd() } finally { $reader.Close() }
        return $body.Trim().StartsWith($ExpectedBody.Trim())
    } catch {
        return $false
    } finally {
        if ($null -ne $response) { $response.Close() }
    }
}

function Get-InternetStatus {
    $windows = $null
    if ($script:Cfg.UseWindowsConnectivity) {
        $windows = Test-WindowsInternet
    }
    $probe = $null
    $urls = @()
    if ($null -ne $script:Cfg.ProbeUrls) {
        $urls = @($script:Cfg.ProbeUrls | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) })
    }
    if ($urls.Count -gt 0 -and $windows -ne $true) {
        $probeTimeout = Get-InternetProbeTimeout -Configured $script:Cfg.ProbeTimeoutSeconds -WindowsInternet $windows
        $results = New-Object System.Collections.Generic.List[bool]
        foreach ($url in $urls) {
            $results.Add((Test-ProbeUrl -Url $url -TimeoutSec $probeTimeout -ExpectedBody $script:Cfg.ExpectedProbeBody))
        }
        $probe = Resolve-ProbeAggregate -Results $results.ToArray()
    }
    return Resolve-InternetStatus -WindowsInternet $windows -ProbeSucceeded $probe
}

function Invoke-ShortcutSync {
    param([string]$Source, [string]$Destination)
    if (Test-BackgroundIoBusy) {
        Write-Log 'Копирование ярлыков пропущено: предыдущее обращение к сетевой папке ещё не завершилось.' 'WARN'
        return
    }
    if (Compare-DesktopPath $Source $Destination) {
        Write-Log 'Копирование ярлыков пропущено: сетевой и локальный пути совпадают.' 'WARN'
        return
    }
    $timeout = $script:Cfg.ShareProbeTimeoutSeconds * 3
    if ($timeout -lt 10) { $timeout = 10 }
    if ($timeout -gt 30) { $timeout = 30 }
    Start-BackgroundIo -Code $script:SyncCode -Arguments @($Source, $Destination, $script:Cfg.SyncExtensions) -Kind 'sync' | Out-Null
    $wait = Wait-BackgroundIo -TimeoutSec $timeout
    if ($wait.TimedOut) {
        Write-Log 'Копирование ярлыков прервано по таймауту. Сетевая папка считается недоступной до завершения операции.' 'WARN'
        return
    }
    if ($null -eq $wait.Value) {
        Write-Log 'Копирование ярлыков не выполнилось.' 'WARN'
        return
    }
    $copied = [int]$wait.Value
    if ($copied -gt 0) {
        Write-Log ("Скопировано ярлыков в локальную папку: {0}." -f $copied)
    }
}

function Test-LocalDesktopSafe {
    param([string]$Path)
    if ([string]::IsNullOrWhiteSpace($Path) -or (Test-UncPathString $Path)) { return $false }
    if (-not (Test-Path -LiteralPath $Path)) { return $true }
    $item = Get-Item -LiteralPath $Path -Force
    if (-not $item.PSIsContainer) { return $false }
    return -not (Test-ReparseAttribute -Attributes ([int]$item.Attributes))
}

function Restart-UserExplorer {
    $existing = @(Get-Process -Name explorer -ErrorAction SilentlyContinue)
    if ($existing.Count -gt 0) {
        Stop-Process -Name explorer -Force -ErrorAction SilentlyContinue
        $deadline = (Get-Date).AddSeconds(5)
        do {
            Start-Sleep -Milliseconds 300
            $still = @(Get-Process -Name explorer -ErrorAction SilentlyContinue)
        } while ($still.Count -eq 0 -and (Get-Date) -lt $deadline)
    }
    $after = @(Get-Process -Name explorer -ErrorAction SilentlyContinue)
    if ($after.Count -eq 0) {
        Start-Process -FilePath (Join-Path $env:WINDIR 'explorer.exe')
    }
}

function Show-UserNotice {
    param([string]$Message, [string]$Title = 'Рабочий стол')
    if (-not $script:Cfg.NotifyUser) { return }
    if ([string]::IsNullOrWhiteSpace($Message)) { return }
    if ($script:TrayIcon) {
        $script:TrayIcon.BalloonTipTitle = $Title
        $script:TrayIcon.BalloonTipText = $Message
        $script:TrayIcon.ShowBalloonTip(8000)
        return
    }
    if ([Threading.Thread]::CurrentThread.GetApartmentState() -ne 'STA') {
        Write-Log 'Уведомление пропущено: запустите PowerShell с ключом -STA.' 'WARN'
        return
    }
    $icon = $null
    try {
        Add-Type -AssemblyName System.Windows.Forms
        Add-Type -AssemblyName System.Drawing
        $icon = New-Object System.Windows.Forms.NotifyIcon
        $icon.Icon = [System.Drawing.SystemIcons]::Information
        $icon.Text = 'Рабочий стол'
        $icon.Visible = $true
        $icon.BalloonTipTitle = $Title
        $icon.BalloonTipText = $Message
        $icon.ShowBalloonTip(5000)
        $deadline = (Get-Date).AddSeconds(6)
        while ((Get-Date) -lt $deadline) {
            [System.Windows.Forms.Application]::DoEvents()
            Start-Sleep -Milliseconds 200
        }
    } catch {
        Write-Log ("Уведомление не показано: {0}" -f $_.Exception.Message) 'WARN'
    } finally {
        if ($null -ne $icon) {
            $icon.Visible = $false
            $icon.Dispose()
        }
    }
}

function Read-StateTable {
    $table = @{
        Mode = ''
        FailureStreak = 0
        SuccessStreak = 0
        LearnedNetworkPath = ''
        LastAction = ''
        LastReason = ''
        LastExplorerRestartAt = ''
        SeenNoticeIds = @()
        ReadNoticeIds = @()
        NoticeLog = @()
        ShowLauncher = $true
        StayOnTop = $true
        UpdatedAt = ''
    }
    if (-not (Test-Path -LiteralPath $script:Cfg.StatePath)) { return $table }
    try {
        $loaded = Get-Content -LiteralPath $script:Cfg.StatePath -Raw -Encoding UTF8 | ConvertFrom-Json
    } catch {
        Write-Log ("Файл состояния повреждён, начинаю заново: {0}" -f $_.Exception.Message) 'WARN'
        return $table
    }
    foreach ($key in @($table.Keys)) {
        $value = Get-Prop $loaded $key $null
        if ($null -ne $value) { $table[$key] = $value }
    }
    $table.FailureStreak = ConvertTo-Int $table.FailureStreak 0
    $table.SuccessStreak = ConvertTo-Int $table.SuccessStreak 0
    $table.Mode = [string]$table.Mode
    $table.LearnedNetworkPath = [string]$table.LearnedNetworkPath
    $table.LastAction = [string]$table.LastAction
    $table.LastReason = [string]$table.LastReason
    $table.LastExplorerRestartAt = [string]$table.LastExplorerRestartAt
    $table.SeenNoticeIds = (ConvertTo-IdList $table.SeenNoticeIds).ToArray()
    $table.ReadNoticeIds = (ConvertTo-IdList $table.ReadNoticeIds).ToArray()
    $table.ShowLauncher = Resolve-ShowLauncher $table.ShowLauncher
    $table.StayOnTop = Resolve-StayOnTop $table.StayOnTop
    return $table
}

function Save-StateTable {
    param($Table)
    $dir = Split-Path -Parent $script:Cfg.StatePath
    if ($dir -and -not (Test-Path -LiteralPath $dir)) {
        New-Item -ItemType Directory -Force -Path $dir | Out-Null
    }
    $Table.UpdatedAt = (Get-Date).ToString('o')
    $json = $Table | ConvertTo-Json -Depth 4
    Set-Content -LiteralPath $script:Cfg.StatePath -Value $json -Encoding UTF8
}

function Format-StatusWord {
    param([string]$Word)
    switch ($Word) {
        'Up' { return 'есть' }
        'Down' { return 'нет' }
        'Unknown' { return 'неизвестно' }
        'Online' { return 'в сети' }
        'Offline' { return 'нет связи' }
        'Network' { return 'сетевой' }
        'Local' { return 'локальный' }
        default { return $Word }
    }
}

function Show-StartupProblem {
    param([string]$Text)
    if ([string]::IsNullOrWhiteSpace($Text)) { $Text = 'Программа не запустилась.' }
    try { Write-Log $Text 'ERROR' } catch { Write-Host $Text }
    try {
        Add-Type -AssemblyName System.Windows.Forms -ErrorAction Stop
        [System.Windows.Forms.MessageBox]::Show($Text, 'Сервисная служба') | Out-Null
    } catch {
        Write-Host $Text
    }
}

function Enter-SingleInstance {
    $script:Mutex = New-Object System.Threading.Mutex($false, 'Local\DesktopSwitchMonitor')
    $acquired = $false
    try {
        $acquired = $script:Mutex.WaitOne(0)
    } catch [System.Threading.AbandonedMutexException] {
        # The previous monitor exited without releasing the mutex. This process owns it now.
        $acquired = $true
    }
    if (-not $acquired) {
        $script:Mutex.Dispose()
        $script:Mutex = $null
        return $false
    }
    $script:MutexOwned = $true
    return $true
}

function Exit-SingleInstance {
    if ($script:MutexOwned -and $null -ne $script:Mutex) {
        try { [void]$script:Mutex.ReleaseMutex() } catch { }
        $script:Mutex.Dispose()
        $script:MutexOwned = $false
    }
}

function Show-StatusReport {
    param([string]$ConfigFile)
    $current = ''
    try {
        $current = Get-CurrentDesktopPath
    } catch {
        $current = 'не удалось прочитать: ' + $_.Exception.Message
    }
    $network = Resolve-NetworkPathValue -Configured $script:Cfg.NetworkDesktopPath -Learned ([string]$script:State.LearnedNetworkPath) -Current $current
    $allowEmpty = [string]::IsNullOrWhiteSpace($network)
    $errors = Get-DesktopConfigErrors -NetworkPath $network -LocalPath $script:Cfg.LocalDesktopPath -AllowEmptyNetwork:$allowEmpty
    $internet = 'Unknown'
    $share = 'Unknown'
    try { $internet = Get-InternetStatus } catch { $internet = 'Unknown' }
    if ((Test-UncPathString $network) -and -not (Test-ExampleNetworkPath $network)) {
        try { $share = Get-ShareStatus -UncPath $network -TimeoutSec $script:Cfg.ShareProbeTimeoutSeconds } catch { $share = 'Unknown' }
    }
    $verdict = 'Unknown'
    if ($errors.Count -eq 0 -and -not [string]::IsNullOrWhiteSpace($network)) {
        $verdict = Get-ConnectivityVerdict -Trigger $script:Cfg.Trigger -Internet $internet -Share $share
    }
    $mode = [string]$script:State.Mode
    if ($mode -ne 'Network' -and $mode -ne 'Local') {
        $mode = Get-DesktopModeFromPath -CurrentPath $current -NetworkPath $network -LocalPath $script:Cfg.LocalDesktopPath
    }
    $enabledText = 'нет'
    if ($script:Cfg.Enabled) { $enabledText = 'да' }
    Write-Host ("DesktopSwitch {0}" -f $script:Version)
    Write-Host ("Конфигурация: {0}" -f $ConfigFile)
    Write-Host ("Включено: {0}" -f $enabledText)
    Write-Host ("Условие переключения: {0}" -f $script:Cfg.Trigger)
    Write-Host ("Текущий рабочий стол: {0}" -f $current)
    Write-Host ("Сетевой путь: {0}" -f $network)
    Write-Host ("Локальный путь: {0}" -f $script:Cfg.LocalDesktopPath)
    Write-Host ("Интернет: {0}" -f (Format-StatusWord $internet))
    Write-Host ("Сетевая папка: {0}" -f (Format-StatusWord $share))
    Write-Host ("Итог: {0}" -f (Format-StatusWord $verdict))
    Write-Host ("Режим: {0}" -f (Format-StatusWord $mode))
    $session = Get-WindowsSessionIdentity
    Write-Host ("Пользователь: {0}" -f $session.Login)
    Write-Host ("Компьютер: {0}" -f $session.Computer)
    Write-Host ("Журнал: {0}" -f $script:LogFile)
    foreach ($item in $errors) { Write-Host ("Ошибка настройки: {0}" -f $item) }
}

function Invoke-MonitorCycle {
    $current = Get-CurrentDesktopPath
    $networkPath = Resolve-NetworkPathValue -Configured $script:Cfg.NetworkDesktopPath -Learned ([string]$script:State.LearnedNetworkPath) -Current $current
    $allowEmpty = [string]::IsNullOrWhiteSpace($networkPath)
    $errors = Get-DesktopConfigErrors -NetworkPath $networkPath -LocalPath $script:Cfg.LocalDesktopPath -AllowEmptyNetwork:$allowEmpty
    if ($errors.Count -gt 0) {
        foreach ($item in $errors) { Write-Log $item 'ERROR' }
        return
    }

    $internet = Get-InternetStatus
    $share = 'Unknown'
    $internetOutage = $script:Cfg.Trigger -eq 'InternetOrShare' -and $internet -eq 'Down'
    $internetOnlyWithoutSync = $script:Cfg.Trigger -eq 'Internet' -and -not ($script:Cfg.SyncShortcutsWhileOnline -and $internet -eq 'Up')
    if (-not $internetOutage -and -not $internetOnlyWithoutSync) {
        $share = Get-ShareStatus -UncPath $networkPath -TimeoutSec $script:Cfg.ShareProbeTimeoutSeconds
    }

    $verdict = Get-ConnectivityVerdict -Trigger $script:Cfg.Trigger -Internet $internet -Share $share
    $mode = [string]$script:State.Mode
    if ($mode -ne 'Network' -and $mode -ne 'Local') {
        $mode = Get-DesktopModeFromPath -CurrentPath $current -NetworkPath $networkPath -LocalPath $script:Cfg.LocalDesktopPath
    }
    $decision = Update-SwitchDecision -Verdict $verdict -Mode $mode -FailureStreak ([int]$script:State.FailureStreak) -SuccessStreak ([int]$script:State.SuccessStreak) -FailuresBeforeSwitch $script:Cfg.FailuresBeforeSwitch -SuccessesBeforeRestore $script:Cfg.SuccessesBeforeRestore -RestoreWhenOnline $script:Cfg.RestoreWhenOnline
    $reason = Get-OfflineReasonCode -Internet $internet -Share $share
    $script:DesktopMode = [string]$decision.Mode
    $script:DesktopVerdict = [string]$verdict
    Write-Log ("internet={0} share={1} verdict={2} mode={3}->{4} action={5} fail={6} success={7} desktop={8}" -f $internet, $share, $verdict, $mode, $decision.Mode, $decision.Action, $decision.FailureStreak, $decision.SuccessStreak, $networkPath)

    $preview = $WhatIf -or $script:Cfg.Preview -or -not $script:Cfg.Enabled
    if (Test-ShouldSyncShortcuts -SyncEnabled $script:Cfg.SyncShortcutsWhileOnline -ShareStatus $share) {
        if ($preview) {
            Write-Log 'WhatIf: ярлыки были бы скопированы в локальную папку.'
        } else {
            Invoke-ShortcutSync -Source $networkPath -Destination $script:Cfg.LocalDesktopPath
        }
    }

    $target = Get-ActionTargetPath -Action $decision.Action -LocalPath $script:Cfg.LocalDesktopPath -NetworkPath $networkPath
    $apply = Test-DesktopChangeNeeded -Action $decision.Action -CurrentPath $current -LocalPath $script:Cfg.LocalDesktopPath -NetworkPath $networkPath
    if ($apply -and ($decision.Action -eq 'SwitchToLocal' -or $decision.Action -eq 'ReassertLocal')) {
        if (Test-UncPathString $target) {
            Write-Log 'Смена отменена: локальный путь оказался сетевым.' 'ERROR'
            $apply = $false
        } elseif (-not (Test-LocalDesktopSafe -Path $script:Cfg.LocalDesktopPath)) {
            Write-Log 'Смена отменена: LocalDesktopPath указывает на файл или на ссылку (junction/symlink), а не на обычную локальную папку.' 'ERROR'
            $apply = $false
        }
    }
    if ($apply -and $decision.Action -eq 'SwitchToNetwork' -and -not (Test-UncPathString $target)) {
        Write-Log 'Смена отменена: сетевой путь не является UNC.' 'ERROR'
        $apply = $false
    }

    $didChange = $false
    if ($apply) {
        if ($preview) {
            Write-Log ("WhatIf: рабочий стол был бы переключён на {0} ({1})." -f $target, $decision.Action)
        } else {
            try {
                Set-CurrentDesktopPath -Path $target
                $didChange = $true
                Write-Log ("Рабочий стол переключён на {0}." -f $target)
            } catch {
                Write-Log ("Не удалось переключить рабочий стол на {0}: {1}" -f $target, $_.Exception.Message) 'ERROR'
            }
        }
    }

    if (-not $preview) {
        $script:State.Mode = [string]$decision.Mode
        $script:State.FailureStreak = [int]$decision.FailureStreak
        $script:State.SuccessStreak = [int]$decision.SuccessStreak
        $script:State.LearnedNetworkPath = $networkPath
        $script:State.LastAction = [string]$decision.Action
        $script:State.LastReason = [string]$reason
        Save-StateTable $script:State

        if ($didChange -and $script:Cfg.RestartExplorer) {
            $stamp = [string]$script:State.LastExplorerRestartAt
            if (Test-CooldownElapsed -Stamp $stamp -Now (Get-Date) -CooldownSeconds 120) {
                Restart-UserExplorer
                $script:State.LastExplorerRestartAt = (Get-Date).ToString('o')
                Save-StateTable $script:State
                Write-Log 'Проводник перезапущен, чтобы смена рабочего стола стала видна.'
                Start-Sleep -Seconds 1
                if (Get-Command -Name Ensure-DesktopWidget -ErrorAction SilentlyContinue) {
                    try { Ensure-DesktopWidget } catch { Write-Log ("Виджет не удалось вернуть на стол: {0}" -f $_.Exception.Message) 'WARN' }
                }
                if (Get-Command -Name Set-LauncherChrome -ErrorAction SilentlyContinue) {
                    try { Set-LauncherChrome } catch { Write-Log ("Кнопку не удалось показать снова: {0}" -f $_.Exception.Message) 'WARN' }
                }
            } else {
                Write-Log 'Путь записан. Повторный перезапуск Проводника отложен, чтобы не закрывать его окна слишком часто.' 'WARN'
            }
        }
        if ($didChange) {
            $message = Get-SwitchMessage -Action $decision.Action -ReasonCode $reason
            if (-not [string]::IsNullOrWhiteSpace($message)) { Show-UserNotice -Message $message -Title 'Рабочий стол' }
            if (($decision.Action -eq 'SwitchToLocal' -or $decision.Action -eq 'ReassertLocal') -and (Test-Path -LiteralPath $script:Cfg.LocalDesktopPath)) {
                $shortcutCount = @(Get-ChildItem -LiteralPath $script:Cfg.LocalDesktopPath -File -Force -ErrorAction SilentlyContinue | Where-Object { $_.Extension -match '^\.(lnk|url)$' }).Count
                if ($shortcutCount -eq 0) {
                    if ($script:Cfg.SyncShortcutsWhileOnline) {
                        Write-Log 'В локальной папке пока нет ярлыков. Они копируются, пока общая папка доступна. Если сбой случился до первого копирования, локальный стол будет пустым.' 'WARN'
                    } else {
                        Write-Log ("В папке {0} нет ярлыков .lnk и .url. Положите их туда заранее: при выключенном копировании программа эту папку сама не заполняет." -f $script:Cfg.LocalDesktopPath) 'WARN'
                    }
                }
            }
        }
    }
    if (Get-Command -Name Update-WidgetStatus -ErrorAction SilentlyContinue) {
        try { Update-WidgetStatus } catch { }
    }
}

function Assert-StaticConfig {
    $allowEmpty = [string]::IsNullOrWhiteSpace($script:Cfg.NetworkDesktopPath)
    $errors = Get-DesktopConfigErrors -NetworkPath $script:Cfg.NetworkDesktopPath -LocalPath $script:Cfg.LocalDesktopPath -AllowEmptyNetwork:$allowEmpty
    if ($errors.Count -gt 0) {
        foreach ($item in $errors) { Write-Log $item 'ERROR' }
        throw [string]::Join([Environment]::NewLine, @($errors))
    }
}

try { [Console]::OutputEncoding = [System.Text.Encoding]::UTF8 } catch { }
try {
    [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor [System.Net.SecurityProtocolType]::Tls12
} catch { }

if (Test-UncPathString $PSScriptRoot) {
    Write-Host 'Программа лежит на сетевом пути. Скопируйте её на локальный диск, иначе при обрыве сети она не запустится.'
}

$configFile = Resolve-ConfigPath -Explicit $ConfigPath
$script:ConfigFile = $configFile
$loaded = Read-DesktopConfig -Path $configFile
$script:Cfg = Get-EffectiveDesktopConfig $loaded
$script:LogFile = $script:Cfg.LogPath
$script:MaxLogBytes = $script:Cfg.MaxLogBytes
Initialize-Log
$script:State = Read-StateTable

if ($Status) {
    Show-StatusReport -ConfigFile $configFile
    exit 0
}

try {
    Assert-StaticConfig
} catch {
    Show-StartupProblem ([string]$_.Exception.Message)
    exit 1
}

if (-not $script:Cfg.Enabled -and -not $WhatIf) {
    Write-Log 'Программа выключена. Поставьте Enabled в true. Сетевой путь можно не указывать: его берёт политика.'
    exit 0
}

if (-not $WhatIf) {
    if (-not (Enter-SingleInstance)) {
        Show-StartupProblem 'Программа уже запущена в этом сеансе. Посмотрите значок у часов и правый нижний угол. Если окна нет, завершите процесс DesktopSwitch или Windows PowerShell в диспетчере задач и запустите снова.'
        exit 0
    }
}

try {
    if ($Once) {
        Invoke-MonitorCycle
    } else {
        $session = Get-WindowsSessionIdentity
        Write-Log ("DesktopSwitch {0} запущен. Пользователь={1} компьютер={2} условие={3} интервал={4}с." -f $script:Version, $session.Login, $session.Computer, $script:Cfg.Trigger, $script:Cfg.CheckIntervalSeconds)
        if ($script:Cfg.SyncShortcutsWhileOnline) {
            Write-Log ("Ярлыки копируются в {0}, пока общая папка доступна." -f $script:Cfg.LocalDesktopPath)
        } else {
            Write-Log ("Копирование ярлыков выключено. При обрыве стол переключится на готовую папку {0}." -f $script:Cfg.LocalDesktopPath)
        }
        if ([string]::IsNullOrWhiteSpace([string]$script:Cfg.EmergencyFolder)) {
            Write-Log 'Аварийная папка не задана. Укажите EmergencyFolder в config.json.'
        } else {
            Write-Log ("Аварийная папка: {0}." -f $script:Cfg.EmergencyFolder)
        }
        if (-not [string]::IsNullOrWhiteSpace([string]$script:Cfg.NewsJql)) {
            Write-Log ("Новости читаются из задач Jira: {0}" -f $script:Cfg.NewsJql)
        }
        if ($script:Cfg.WidgetEnabled) {
            Start-WidgetApplication
        } else {
            while ($true) {
                try {
                    Invoke-MonitorCycle
                } catch {
                    Write-Log ("Сбой цикла: {0}" -f $_.Exception.Message) 'ERROR'
                }
                Start-Sleep -Seconds $script:Cfg.CheckIntervalSeconds
            }
        }
    }
} catch {
    Show-StartupProblem ([string]$_.Exception.ToString())
    exit 1
} finally {
    Exit-SingleInstance
}
