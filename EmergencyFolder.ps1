#Requires -Version 5.1
<#
    Пингует контроллер домена
    Когда контроллер не отвечает, в правом нижнем углу появляется красная кнопка.
    Нажатие открывает C:\Users\Public\Desktop. Когда контроллер снова отвечает, кнопки нет.

    Права администратора не нужны:
      "Emergency folder.exe"
      "Emergency folder.exe" -Status
#>
[CmdletBinding()]
param(
    [switch]$Once,
    [switch]$Status
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

. (Join-Path $PSScriptRoot 'EmergencyFolder.Logic.ps1')
. (Join-Path $PSScriptRoot 'EmergencyFolder.Widget.ps1')

$script:Version = '1.2.44'
$script:IntervalSeconds = 60
$script:PingTimeoutMs = 2000
$script:DownChecks = 1
$script:UpChecks = 1
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
$script:LogFile = Join-Path $logRoot 'Emergency folder\emergency-folder.log'

function Initialize-Log {
    $dir = Split-Path -Parent $script:LogFile
    try {
        if ($dir -and -not (Test-Path -LiteralPath $dir)) {
            New-Item -ItemType Directory -Force -Path $dir | Out-Null
        }
    } catch {
        $fallback = Join-Path $env:TEMP 'Emergency folder.log'
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

function Test-DomainControllerPing {
    param([string]$Address, [int]$TimeoutMs)
    $ping = $null
    try {
        $ping = New-Object System.Net.NetworkInformation.Ping
        $reply = $ping.Send($Address, $TimeoutMs)
        if ($null -eq $reply) { return $false }
        return $reply.Status -eq [System.Net.NetworkInformation.IPStatus]::Success
    } catch {
        Write-Log ("Пинг {0} не выполнился: {1}" -f $Address, $_.Exception.Message) 'WARN'
        return $false
    } finally {
        if ($null -ne $ping) { $ping.Dispose() }
    }
}

function Get-InternetStatus {
    $address = Get-DomainControllerAddress
    $ok = Test-DomainControllerPing -Address $address -TimeoutMs $script:PingTimeoutMs
    return Resolve-PingStatus -Succeeded $ok
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
        [System.Windows.Forms.MessageBox]::Show($Text, 'Emergency folder') | Out-Null
    } catch {
        Write-Host $Text
    }
}

function Enter-SingleInstance {
    $script:Mutex = New-Object System.Threading.Mutex($false, 'Local\EmergencyFolderMonitor')
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

function Stop-LegacyMonitor {
    foreach ($proc in @(Get-Process -Name 'DesktopSwitch' -ErrorAction SilentlyContinue)) {
        try {
            Stop-Process -Id $proc.Id -Force -ErrorAction SilentlyContinue
            Write-Log ("Остановлена прежняя программа DesktopSwitch, процесс {0}." -f $proc.Id)
        } catch {
        }
    }
}

function Show-StatusReport {
    $internet = 'Unknown'
    try { $internet = Get-InternetStatus } catch { $internet = 'Unknown' }
    Write-Host ("Emergency folder {0}" -f $script:Version)
    Write-Host ("Контроллер {0}: {1}" -f (Get-DomainControllerAddress), (Format-StatusWord $internet))
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
            Write-Log ("Контроллер {0} не отвечает. Показана красная кнопка." -f (Get-DomainControllerAddress))
        } else {
            Write-Log ("Контроллер {0} отвечает. Красная кнопка скрыта." -f (Get-DomainControllerAddress))
        }
    }
}

function Invoke-MonitorCycle {
    $internet = 'Unknown'
    try {
        $internet = Get-InternetStatus
    } catch {
        Write-Log ("Пинг контроллера не выполнился: {0}" -f $_.Exception.Message) 'WARN'
    }
    $before = $script:ButtonShown
    Update-OfflineButton -Internet $internet
    if ($internet -ne $script:LastInternet -or $before -ne $script:ButtonShown) {
        $buttonWord = 'hidden'
        if ($script:ButtonShown) { $buttonWord = 'shown' }
        Write-Log ("dc={0} ping={1} button={2}" -f (Get-DomainControllerAddress), $internet, $buttonWord)
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
    Stop-LegacyMonitor
    Write-Log ("Emergency folder {0} запущен. Пинг {1} каждые {2} с. Папка: {3}" -f $script:Version, (Get-DomainControllerAddress), $script:IntervalSeconds, (Get-PublicDesktopPath))
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
