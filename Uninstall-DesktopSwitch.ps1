#Requires -Version 5.1
<#
    Убирает автозапуск и останавливает монитор текущего пользователя.
    С ключом -AllUsers также удаляет ярлык из общей автозагрузки.
    config.json, журнал и локальные копии ярлыков не удаляются.
#>
[CmdletBinding()]
param(
    [switch]$AllUsers,
    [string]$TaskName = 'DesktopSwitch'
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

$folders = New-Object System.Collections.Generic.List[string]
$userStartup = [Environment]::GetFolderPath('Startup')
if (-not [string]::IsNullOrWhiteSpace($userStartup)) { $folders.Add($userStartup) }
if ($AllUsers) {
    $commonStartup = [Environment]::GetFolderPath('CommonStartup')
    if (-not [string]::IsNullOrWhiteSpace($commonStartup)) { $folders.Add($commonStartup) }
}

foreach ($folder in $folders) {
    $vbsPath = Join-Path $folder 'DesktopSwitch.vbs'
    if (Test-Path -LiteralPath $vbsPath) {
        Remove-Item -LiteralPath $vbsPath -Force
        Write-Host ("Удалён автозапуск: {0}" -f $vbsPath)
    }
}

foreach ($name in @('powershell.exe', 'pwsh.exe')) {
    $procs = @(Get-CimInstance Win32_Process -Filter "Name = '$name'" -ErrorAction SilentlyContinue)
    foreach ($proc in $procs) {
        $line = [string]$proc.CommandLine
        if ($line -notmatch '(?i)(^|[\s\"\\])DesktopSwitch\.ps1') { continue }
        if ($line -match '(?i)(Install|Uninstall)-DesktopSwitch\.ps1') { continue }
        Stop-Process -Id $proc.ProcessId -Force -ErrorAction SilentlyContinue
        Write-Host ("Остановлен процесс {0}." -f $proc.ProcessId)
    }
}

try {
    Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false -ErrorAction SilentlyContinue
    Write-Host ("Задача планировщика снята, если она была: {0}" -f $TaskName)
} catch {
    Write-Host ("Задачу планировщика снять не удалось: {0}" -f $_.Exception.Message)
}

Write-Host 'Готово. config.json, журнал и локальная папка ярлыков сохранены.'
Write-Host 'Путь рабочего стола в реестре не возвращается автоматически. Если сейчас включён локальный стол, верните сетевой путь вручную или ещё раз запустите монитор при рабочей сети.'
