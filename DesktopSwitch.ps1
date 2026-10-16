#Requires -Version 5.1
<#
    Следит за интернетом в сеансе пользователя.
    Когда интернета нет, в правом нижнем углу появляется красная кнопка.
    Нажатие открывает C:\Users\Public\Desktop. Когда интернет есть, кнопки нет.

    Права администратора не нужны:
      DesktopSwitch.exe
      DesktopSwitch.exe -Status
#>
[CmdletBinding()]
param(
    [switch]$Once,
    [switch]$Status
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

. (Join-Path $PSScriptRoot 'DesktopSwitch.Logic.ps1')
. (Join-Path $PSScriptRoot 'DesktopSwitch.Widget.ps1')

$script:Version = '1.2.41'
$script:IntervalSeconds = 5
$script:ProbeTimeoutSeconds = 5
$script:ProbeUrl = 'http://www.msftconnecttest.com/connecttest.txt'
$script:ExpectedProbeBody = 'Microsoft Connect Test'
$script:DownChecks = 2
$script:UpChecks = 2
$script:MaxLogBytes = 1048576
$script:Mutex = $null
$script:MutexOwned = $false
$script:DownStreak = 0
$script:UpStreak = 0
$script:ButtonShown = $false
$script:LastInternet = ''
$script:Timer = $null
$script:FirstTick = $true

$logRoot = $env:LOCALAPPDATA
if ([string]::IsNullOrWhiteSpace($logRoot)) { $logRoot = $env:TEMP }
$script:LogFile = Join-Path $logRoot 'DesktopSwitch\desktop-switch.log'

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
    $windows = Test-WindowsInternet
    $probe = $null
    if ($windows -ne $true) {
        $probeTimeout = Get-InternetProbeTimeout -Configured $script:ProbeTimeoutSeconds -WindowsInternet $windows
        $results = New-Object System.Collections.Generic.List[bool]
        $results.Add((Test-ProbeUrl -Url $script:ProbeUrl -TimeoutSec $probeTimeout -ExpectedBody $script:ExpectedProbeBody))
        $probe = Resolve-ProbeAggregate -Results $results.ToArray()
    }
    return Resolve-InternetStatus -WindowsInternet $windows -ProbeSucceeded $probe
}

function Format-StatusWord {
    param([string]$Word)
    switch ($Word) {
        'Up' { return 'есть' }
        'Down' { return 'нет' }
        'Unknown' { return 'неизвестно' }
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
    $internet = 'Unknown'
    try { $internet = Get-InternetStatus } catch { $internet = 'Unknown' }
    Write-Host ("DesktopSwitch {0}" -f $script:Version)
    Write-Host ("Интернет: {0}" -f (Format-StatusWord $internet))
    Write-Host ("Кнопка открывает: {0}" -f (Get-PublicDesktopPath))
    Write-Host ("Журнал: {0}" -f $script:LogFile)
}

function Update-OfflineButton {
    param([string]$Internet)
    $decision = Update-ButtonVisibility -Internet $Internet -Visible $script:ButtonShown -DownStreak $script:DownStreak -UpStreak $script:UpStreak -DownChecks $script:DownChecks -UpChecks $script:UpChecks
    $script:DownStreak = [int]$decision.DownStreak
    $script:UpStreak = [int]$decision.UpStreak
    $script:ButtonShown = [bool]$decision.Visible
    if ($decision.Visible) {
        Set-LauncherVisible -Visible $true
    } elseif ($decision.Changed) {
        Set-LauncherVisible -Visible $false
    }
    if ($decision.Changed) {
        if ($decision.Visible) {
            Write-Log 'Интернета нет. Показана красная кнопка.'
        } else {
            Write-Log 'Интернет есть. Красная кнопка скрыта.'
        }
    }
}

function Invoke-MonitorCycle {
    $internet = 'Unknown'
    try {
        $internet = Get-InternetStatus
    } catch {
        Write-Log ("Проверка интернета не выполнилась: {0}" -f $_.Exception.Message) 'WARN'
    }
    $before = $script:ButtonShown
    Update-OfflineButton -Internet $internet
    if ($internet -ne $script:LastInternet -or $before -ne $script:ButtonShown) {
        $buttonWord = 'hidden'
        if ($script:ButtonShown) { $buttonWord = 'shown' }
        Write-Log ("internet={0} button={1}" -f $internet, $buttonWord)
    }
    $script:LastInternet = [string]$internet
}

function Start-MonitorTimer {
    $script:Timer = New-Object System.Windows.Forms.Timer
    $script:Timer.Interval = 400
    $script:Timer.add_Tick({
        if ($script:FirstTick) {
            $script:FirstTick = $false
            $script:Timer.Interval = $script:IntervalSeconds * 1000
        }
        try {
            Invoke-MonitorCycle
        } catch {
            Write-Log ("Цикл проверки не выполнился: {0}" -f $_.Exception.Message) 'WARN'
        }
    })
    $script:Timer.Start()
    [System.Windows.Forms.Application]::Run()
}

Initialize-Log
if ($Status) {
    Show-StatusReport
    return
}

if (-not (Enter-SingleInstance)) {
    Write-Log 'Уже запущена другая копия. Эта копия завершается.'
    return
}

try {
    Initialize-LauncherWindow
    Write-Log ("DesktopSwitch {0} запущен. Кнопка появится, если интернет пропадёт. Папка: {1}" -f $script:Version, (Get-PublicDesktopPath))
    if ($Once) {
        Invoke-MonitorCycle
    } else {
        Start-MonitorTimer
    }
} catch {
    Show-StartupProblem $_.Exception.Message
} finally {
    Exit-SingleInstance
}
