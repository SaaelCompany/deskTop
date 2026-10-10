#Requires -Version 5.1
<#
    Включает автозапуск монитора в сеансе пользователя.
    По умолчанию — папка «Автозагрузка» текущего пользователя.
    С ключом -AllUsers — общая автозагрузка компьютера (нужны права администратора).
    -InstallDir копирует пакет в постоянную локальную папку. Так его ставит SCCM.
    Учётная запись SYSTEM сама выбирает общую автозагрузку и не запускает монитор в сеансе 0.
    С ключом -ScheduledTask дополнительно создаётся задача планировщика.
#>
[CmdletBinding()]
param(
    [switch]$AllUsers,
    [switch]$ScheduledTask,
    [switch]$NoLaunch,
    [string]$InstallDir,
    [string]$TaskName = 'DesktopSwitch'
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'DesktopSwitch.Logic.ps1')

$configPath = Join-Path $PSScriptRoot 'config.json'
$example = Join-Path $PSScriptRoot 'config.example.json'
if (-not (Test-Path -LiteralPath $configPath)) {
    throw "Нет файла config.json. Скопируйте '$example' в '$configPath' и поставьте Enabled в true. Права администратора не нужны, сетевой путь политика задаёт сама."
}

$loaded = Get-Content -LiteralPath $configPath -Raw -Encoding UTF8 | ConvertFrom-Json
$effective = Get-EffectiveDesktopConfig $loaded
$problems = New-Object System.Collections.Generic.List[string]
if (-not $effective.Enabled) {
    $problems.Add('В config.json параметр Enabled должен быть true.')
}
$allowEmpty = [string]::IsNullOrWhiteSpace($effective.NetworkDesktopPath)
$errors = Get-DesktopConfigErrors -NetworkPath $effective.NetworkDesktopPath -LocalPath $effective.LocalDesktopPath -AllowEmptyNetwork:$allowEmpty
foreach ($item in $errors) { $problems.Add([string]$item) }
if ($problems.Count -gt 0) {
    throw [string]::Join([Environment]::NewLine, @($problems))
}

function Stop-DesktopSwitchMonitor {
    foreach ($name in @('powershell.exe', 'pwsh.exe')) {
        $procs = @(Get-CimInstance Win32_Process -Filter "Name = '$name'" -ErrorAction SilentlyContinue)
        foreach ($proc in $procs) {
            $line = [string]$proc.CommandLine
            if ($line -notmatch '(?i)(^|[\s\"\\])DesktopSwitch\.ps1') { continue }
            if ($line -match '(?i)(Install|Uninstall)-DesktopSwitch\.ps1') { continue }
            Stop-Process -Id $proc.ProcessId -Force -ErrorAction SilentlyContinue
            Write-Host ("Остановлен прежний монитор, процесс {0}." -f $proc.ProcessId)
        }
    }
}

function Get-InstallerIdentityName {
    try {
        $current = [System.Security.Principal.WindowsIdentity]::GetCurrent()
        if ($null -eq $current) { return '' }
        if ($current.IsSystem) { return 'NT AUTHORITY\SYSTEM' }
        return [string]$current.Name
    } catch {
        return ''
    }
}

function Copy-DesktopSwitchPackage {
    param([string]$Source, [string]$Destination)
    if (-not (Test-DesktopSwitchInstallDir $Destination)) {
        throw 'InstallDir должен быть локальной папкой, не корнем диска и не сетевым путём.'
    }
    $sourceFull = [System.IO.Path]::GetFullPath($Source)
    $destFull = [System.IO.Path]::GetFullPath($Destination)
    if ($sourceFull.TrimEnd('\') -eq $destFull.TrimEnd('\')) { return $destFull }
    if (-not (Test-Path -LiteralPath $destFull)) {
        New-Item -ItemType Directory -Path $destFull -Force | Out-Null
    }
    $names = @(
        'DesktopSwitch.ps1',
        'DesktopSwitch.Logic.ps1',
        'DesktopSwitch.Widget.ps1',
        'Install-DesktopSwitch.ps1',
        'Uninstall-DesktopSwitch.ps1',
        'Show-DesktopSwitchStatus.cmd',
        'config.json',
        'config.example.json',
        'README.md'
    )
    foreach ($name in $names) {
        $from = Join-Path $sourceFull $name
        if (-not (Test-Path -LiteralPath $from)) { continue }
        Copy-Item -LiteralPath $from -Destination (Join-Path $destFull $name) -Force
    }
    $news = Join-Path $sourceFull 'examples\news.json'
    if (Test-Path -LiteralPath $news) {
        $examples = Join-Path $destFull 'examples'
        if (-not (Test-Path -LiteralPath $examples)) {
            New-Item -ItemType Directory -Path $examples -Force | Out-Null
        }
        Copy-Item -LiteralPath $news -Destination (Join-Path $examples 'news.json') -Force
    }
    if (-not (Test-Path -LiteralPath (Join-Path $destFull 'config.json'))) {
        throw 'В пакете нет config.json. Положите готовый файл настроек в источник SCCM.'
    }
    if (-not (Test-Path -LiteralPath (Join-Path $destFull 'DesktopSwitch.ps1'))) {
        throw 'В пакете нет DesktopSwitch.ps1.'
    }
    return $destFull
}

$packageRoot = $PSScriptRoot
if (-not [string]::IsNullOrWhiteSpace($InstallDir)) {
    $packageRoot = Copy-DesktopSwitchPackage -Source $PSScriptRoot -Destination $InstallDir
    Write-Host ("Пакет скопирован: {0}" -f $packageRoot)
}
$monitor = (Resolve-Path -LiteralPath (Join-Path $packageRoot 'DesktopSwitch.ps1')).Path
$identityName = Get-InstallerIdentityName
$systemAccount = Test-InstallerSystemAccount $identityName
$scope = Resolve-InstallerStartupScope -AllUsers ([bool]$AllUsers) -SystemAccount $systemAccount
if ($systemAccount -and -not $AllUsers) {
    Write-Host 'Учётная запись установки — SYSTEM. Автозапуск будет общим для всех пользователей.'
}

Stop-DesktopSwitchMonitor
Start-Sleep -Seconds 1

if ($scope -eq 'AllUsers') {
    $startup = [Environment]::GetFolderPath('CommonStartup')
} else {
    $startup = [Environment]::GetFolderPath('Startup')
}
if ([string]::IsNullOrWhiteSpace($startup)) { throw 'Не удалось определить папку автозагрузки.' }

$escaped = $monitor.Replace('"', '""')
$vbs = @"
Set shell = CreateObject("Wscript.Shell")
shell.Run "powershell.exe -NoProfile -STA -WindowStyle Hidden -ExecutionPolicy Bypass -File ""$escaped""", 0, False
"@.Trim()
$vbsPath = Join-Path $startup 'DesktopSwitch.vbs'
$encoding = 'ASCII'
if ($monitor -match '[^\x00-\x7F]') { $encoding = 'Unicode' }
Set-Content -LiteralPath $vbsPath -Value $vbs -Encoding $encoding
Write-Host ("Автозапуск создан: {0}" -f $vbsPath)

if ($ScheduledTask) {
    try {
        $argument = '-NoProfile -STA -WindowStyle Hidden -ExecutionPolicy Bypass -File "{0}"' -f $monitor
        $action = New-ScheduledTaskAction -Execute 'powershell.exe' -Argument $argument
        $trigger = New-ScheduledTaskTrigger -AtLogOn
        $settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -MultipleInstances IgnoreNew -StartWhenAvailable -RestartCount 3 -RestartInterval (New-TimeSpan -Minutes 1)
        $settings.ExecutionTimeLimit = [TimeSpan]::Zero
        if ($scope -eq 'AllUsers') {
            $principal = New-ScheduledTaskPrincipal -GroupId 'S-1-5-32-545' -RunLevel Limited
        } else {
            $principal = New-ScheduledTaskPrincipal -UserId $env:USERNAME -LogonType Interactive -RunLevel Limited
        }
        Register-ScheduledTask -TaskName $TaskName -Action $action -Trigger $trigger -Settings $settings -Principal $principal -Force | Out-Null
        Write-Host ("Задача планировщика создана: {0}" -f $TaskName)
    } catch {
        Write-Host ("Задачу планировщика создать не удалось. Автозагрузки достаточно. Причина: {0}" -f $_.Exception.Message)
    }
}

if (Test-InstallerShouldLaunch -SystemAccount $systemAccount -NoLaunch ([bool]$NoLaunch)) {
    $launch = '-NoProfile -STA -WindowStyle Hidden -ExecutionPolicy Bypass -File "{0}"' -f $monitor
    Start-Process -FilePath 'powershell.exe' -ArgumentList $launch -WindowStyle Hidden
    Write-Host 'Монитор запущен.'
} else {
    Write-Host 'Монитор запустится при следующем входе пользователя.'
}
Write-Host ("Настройки: {0}" -f (Join-Path $packageRoot 'config.json'))
Write-Host ("Журнал: {0}" -f $effective.LogPath)
Write-Host 'Проверка: powershell.exe -NoProfile -STA -ExecutionPolicy Bypass -File .\DesktopSwitch.ps1 -Status'
