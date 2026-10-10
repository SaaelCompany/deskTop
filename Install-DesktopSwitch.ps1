#Requires -Version 5.1
<#
    Включает автозапуск монитора в сеансе пользователя.
    По умолчанию — папка «Автозагрузка» текущего пользователя.
    С ключом -AllUsers — общая автозагрузка компьютера (нужны права администратора).
    С ключом -ScheduledTask дополнительно создаётся задача планировщика.
#>
[CmdletBinding()]
param(
    [switch]$AllUsers,
    [switch]$ScheduledTask,
    [string]$TaskName = 'DesktopSwitch'
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'DesktopSwitch.Logic.ps1')

$monitor = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot 'DesktopSwitch.ps1')).Path
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

Stop-DesktopSwitchMonitor
Start-Sleep -Seconds 1

if ($AllUsers) {
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
        $principal = New-ScheduledTaskPrincipal -UserId $env:USERNAME -LogonType Interactive -RunLevel Limited
        Register-ScheduledTask -TaskName $TaskName -Action $action -Trigger $trigger -Settings $settings -Principal $principal -Force | Out-Null
        Write-Host ("Задача планировщика создана: {0}" -f $TaskName)
    } catch {
        Write-Host ("Задачу планировщика создать не удалось. Автозагрузки достаточно. Причина: {0}" -f $_.Exception.Message)
    }
}

$launch = '-NoProfile -STA -WindowStyle Hidden -ExecutionPolicy Bypass -File "{0}"' -f $monitor
Start-Process -FilePath 'powershell.exe' -ArgumentList $launch -WindowStyle Hidden
Write-Host 'Монитор запущен.'
Write-Host ("Журнал: {0}" -f $effective.LogPath)
Write-Host 'Проверка: powershell.exe -NoProfile -STA -ExecutionPolicy Bypass -File .\DesktopSwitch.ps1 -Status'
