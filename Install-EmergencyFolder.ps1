#Requires -Version 5.1
<#
    Включает автозапуск в сеансе текущего пользователя.
    Права администратора не нужны.
    -AllUsers и учётная запись SYSTEM не кладут ярлык в общую автозагрузку:
    такой ярлык даёт ошибку Windows 2211. Для всего компьютера ставьте MSI.
    -InstallDir копирует пакет в постоянную локальную папку.
    -ScheduledTask дополнительно создаёт задачу планировщика.
#>
[CmdletBinding()]
param(
    [switch]$AllUsers,
    [switch]$ScheduledTask,
    [switch]$NoLaunch,
    [string]$InstallDir,
    [string]$TaskName = 'Emergency folder'
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'EmergencyFolder.Logic.ps1')

function Stop-EmergencyFolderMonitor {
    foreach ($procName in @('Emergency folder', 'DesktopSwitch')) {
        foreach ($proc in @(Get-Process -Name $procName -ErrorAction SilentlyContinue)) {
            Stop-Process -Id $proc.Id -Force -ErrorAction SilentlyContinue
            Write-Host ("Остановлен процесс {0}, идентификатор {1}." -f $proc.ProcessName, $proc.Id)
        }
    }
    foreach ($name in @('powershell.exe', 'pwsh.exe')) {
        $procs = @(Get-CimInstance Win32_Process -Filter "Name = '$name'" -ErrorAction SilentlyContinue)
        foreach ($proc in $procs) {
            $line = [string]$proc.CommandLine
            if ($line -notmatch '(?i)EmergencyFolder\.ps1' -and $line -notmatch '(?i)DesktopSwitch\.ps1') { continue }
            if ($line -match '(?i)(Install|Uninstall)-(EmergencyFolder|DesktopSwitch)\.ps1') { continue }
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

function Copy-EmergencyFolderPackage {
    param([string]$Source, [string]$Destination)
    if (-not (Test-EmergencyFolderInstallDir $Destination)) {
        throw 'InstallDir должен быть локальной папкой, не корнем диска и не сетевым путём.'
    }
    $sourceFull = [System.IO.Path]::GetFullPath($Source)
    $destFull = [System.IO.Path]::GetFullPath($Destination)
    if ($sourceFull.TrimEnd('\') -eq $destFull.TrimEnd('\')) { return $destFull }
    if (-not (Test-Path -LiteralPath $destFull)) {
        New-Item -ItemType Directory -Path $destFull -Force | Out-Null
    }
    $names = @(
        'Emergency folder.exe',
        'EmergencyFolder.ps1',
        'EmergencyFolder.Logic.ps1',
        'EmergencyFolder.Widget.ps1',
        'Install-EmergencyFolder.ps1',
        'Uninstall-EmergencyFolder.ps1',
        'Show-EmergencyFolderStatus.cmd',
        'README.md'
    )
    foreach ($name in $names) {
        $from = Join-Path $sourceFull $name
        if (-not (Test-Path -LiteralPath $from)) { continue }
        Copy-Item -LiteralPath $from -Destination (Join-Path $destFull $name) -Force
    }
    if (-not (Test-Path -LiteralPath (Join-Path $destFull 'EmergencyFolder.ps1'))) {
        throw 'В пакете нет EmergencyFolder.ps1.'
    }
    return $destFull
}

Stop-EmergencyFolderMonitor
Start-Sleep -Seconds 1

$packageRoot = $PSScriptRoot
if (-not [string]::IsNullOrWhiteSpace($InstallDir)) {
    $packageRoot = Copy-EmergencyFolderPackage -Source $PSScriptRoot -Destination $InstallDir
    Write-Host ("Пакет скопирован: {0}" -f $packageRoot)
}
$monitor = (Resolve-Path -LiteralPath (Join-Path $packageRoot 'EmergencyFolder.ps1')).Path
$exePath = Join-Path $packageRoot 'Emergency folder.exe'
$exeFull = ''
if (Test-Path -LiteralPath $exePath) {
    $exeFull = (Resolve-Path -LiteralPath $exePath).Path
}
$identityName = Get-InstallerIdentityName
$systemAccount = Test-InstallerSystemAccount $identityName
$scope = Resolve-InstallerStartupScope -AllUsers ([bool]$AllUsers) -SystemAccount $systemAccount
if ($systemAccount -and -not $AllUsers) {
    Write-Host 'Учётная запись установки — SYSTEM. Общая автозагрузка не используется.'
}

if ($scope -eq 'CurrentUser') {
    $startup = [Environment]::GetFolderPath('Startup')
    if ([string]::IsNullOrWhiteSpace($startup)) { throw 'Не удалось определить папку автозагрузки.' }
    $vbsPath = Join-Path $startup 'Emergency folder.vbs'
    if (-not [string]::IsNullOrWhiteSpace($exeFull)) {
        $escaped = $exeFull.Replace('"', '""')
        $vbs = @"
Set shell = CreateObject("Wscript.Shell")
shell.Run """$escaped""", 0, False
"@.Trim()
        $encoding = 'ASCII'
        if ($exeFull -match '[^\x00-\x7F]') { $encoding = 'Unicode' }
    } else {
        $escaped = $monitor.Replace('"', '""')
        $vbs = @"
Set shell = CreateObject("Wscript.Shell")
shell.Run "powershell.exe -NoProfile -STA -WindowStyle Hidden -ExecutionPolicy Bypass -File ""$escaped""", 0, False
"@.Trim()
        $encoding = 'ASCII'
        if ($monitor -match '[^\x00-\x7F]') { $encoding = 'Unicode' }
    }
    Set-Content -LiteralPath $vbsPath -Value $vbs -Encoding $encoding
    Write-Host ("Автозапуск создан: {0}" -f $vbsPath)
} else {
    Write-Host 'Общая папка автозагрузки не используется. Для всех пользователей ставьте Emergency folder.msi: автозапуск записан в HKLM\Software\Microsoft\Windows\CurrentVersion\Run.'
}

if ($ScheduledTask) {
    try {
        if (-not [string]::IsNullOrWhiteSpace($exeFull)) {
            $action = New-ScheduledTaskAction -Execute $exeFull
        } else {
            $argument = '-NoProfile -STA -WindowStyle Hidden -ExecutionPolicy Bypass -File "{0}"' -f $monitor
            $action = New-ScheduledTaskAction -Execute 'powershell.exe' -Argument $argument
        }
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
        Write-Host ("Задачу планировщика создать не удалось. Причина: {0}" -f $_.Exception.Message)
    }
}

if (Test-InstallerShouldLaunch -SystemAccount $systemAccount -NoLaunch ([bool]$NoLaunch)) {
    if (-not [string]::IsNullOrWhiteSpace($exeFull)) {
        Start-Process -FilePath $exeFull -WindowStyle Hidden
    } else {
        $launch = '-NoProfile -STA -WindowStyle Hidden -ExecutionPolicy Bypass -File "{0}"' -f $monitor
        Start-Process -FilePath 'powershell.exe' -ArgumentList $launch -WindowStyle Hidden
    }
    Write-Host 'Монитор запущен.'
} else {
    Write-Host 'Монитор запустится при следующем входе пользователя.'
}
Write-Host ("Журнал: {0}" -f (Join-Path $env:LOCALAPPDATA 'Emergency folder\emergency-folder.log'))
Write-Host 'Проверка: "Emergency folder.exe" -Status'
