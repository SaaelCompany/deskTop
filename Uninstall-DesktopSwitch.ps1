#Requires -Version 5.1
<#
    Убирает автозапуск и останавливает монитор текущего пользователя.
    С ключом -AllUsers также удаляет ярлык из общей автозагрузки.
    Учётная запись SYSTEM снимает общую автозагрузку сама.
    -InstallDir удаляет папку программы. Журнал и локальные копии ярлыков не удаляются.
#>
[CmdletBinding()]
param(
    [switch]$AllUsers,
    [string]$InstallDir,
    [string]$TaskName = 'DesktopSwitch'
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'DesktopSwitch.Logic.ps1')

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

$systemAccount = Test-InstallerSystemAccount (Get-InstallerIdentityName)
$removeCommon = $AllUsers -or $systemAccount

$folders = New-Object System.Collections.Generic.List[string]
$userStartup = [Environment]::GetFolderPath('Startup')
if (-not [string]::IsNullOrWhiteSpace($userStartup)) { $folders.Add($userStartup) }
if ($removeCommon) {
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

if (-not [string]::IsNullOrWhiteSpace($InstallDir)) {
    if (-not (Test-DesktopSwitchInstallDir $InstallDir)) {
        throw 'InstallDir должен быть локальной папкой программы, не корнем диска и не сетевым путём.'
    }
    $program = [System.IO.Path]::GetFullPath($InstallDir)
    $marker = Join-Path $program 'DesktopSwitch.ps1'
    if (Test-Path -LiteralPath $marker) {
        Remove-Item -LiteralPath $program -Recurse -Force
        Write-Host ("Удалена папка программы: {0}" -f $program)
    } else {
        Write-Host ("Папка программы не удалена, в ней нет DesktopSwitch.ps1: {0}" -f $program)
    }
}

Write-Host 'Готово. Журнал и локальная папка ярлыков сохранены.'
Write-Host 'Путь рабочего стола в реестре не возвращается автоматически. Если сейчас включён локальный стол, верните сетевой путь вручную или ещё раз запустите монитор при рабочей сети.'
