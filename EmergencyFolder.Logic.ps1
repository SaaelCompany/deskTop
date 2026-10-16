# Решение, показывать ли кнопку. Файл не трогает реестр, сеть и Проводник,
# поэтому его можно проверить на любой системе. Windows PowerShell 5.1: без тернарного оператора.

Set-StrictMode -Version 2.0

function Get-ClampedTimeout {
    param([int]$Seconds)
    if ($Seconds -lt 1) { return 1 }
    if ($Seconds -gt 30) { return 30 }
    return $Seconds
}

function Get-InternetProbeTimeout {
    param([int]$Configured, $WindowsInternet)
    $timeout = Get-ClampedTimeout $Configured
    if ($WindowsInternet -eq $false -and $timeout -gt 2) { return 2 }
    return $timeout
}

function Resolve-ProbeAggregate {
    param([bool[]]$Results)
    if ($null -eq $Results -or $Results.Count -eq 0) { return $null }
    foreach ($result in $Results) {
        if ($result) { return $true }
    }
    return $false
}

function Resolve-InternetStatus {
    param($WindowsInternet, $ProbeSucceeded)
    if ($WindowsInternet -eq $true) { return 'Up' }
    if ($ProbeSucceeded -eq $true) { return 'Up' }
    if ($WindowsInternet -eq $false) { return 'Down' }
    if ($ProbeSucceeded -eq $false) { return 'Down' }
    return 'Unknown'
}

function Get-PublicDesktopPath {
    return 'C:\Users\Public\Desktop'
}

function Update-ButtonVisibility {
    param(
        [ValidateSet('Up', 'Down', 'Unknown')]
        [string]$Internet,
        [bool]$Visible,
        [int]$DownStreak,
        [int]$UpStreak,
        [int]$DownChecks = 2,
        [int]$UpChecks = 2
    )
    $downNeed = $DownChecks
    if ($downNeed -lt 1) { $downNeed = 1 }
    $upNeed = $UpChecks
    if ($upNeed -lt 1) { $upNeed = 1 }

    $show = $Visible
    $down = 0
    $up = 0
    if ($Internet -eq 'Down') {
        $down = $DownStreak + 1
        if ($down -ge $downNeed) {
            $down = $downNeed
            $show = $true
        }
    } elseif ($Internet -eq 'Up') {
        $up = $UpStreak + 1
        if ($up -ge $upNeed) {
            $up = $upNeed
            $show = $false
        }
    }

    return [pscustomobject]@{
        Visible = [bool]$show
        DownStreak = [int]$down
        UpStreak = [int]$up
        Changed = [bool]($show -ne $Visible)
    }
}

function Test-InstallerSystemAccount {
    param([string]$IdentityName)
    if ([string]::IsNullOrWhiteSpace($IdentityName)) { return $false }
    return $IdentityName.Trim() -match '(?i)(^|\\)SYSTEM$'
}

function Resolve-InstallerStartupScope {
    param([bool]$AllUsers, [bool]$SystemAccount)
    if ($AllUsers -or $SystemAccount) { return 'AllUsers' }
    return 'CurrentUser'
}

function Test-InstallerShouldLaunch {
    param([bool]$SystemAccount, [bool]$NoLaunch)
    if ($NoLaunch -or $SystemAccount) { return $false }
    return $true
}

function Test-EmergencyFolderInstallDir {
    param([string]$Path)
    if ([string]::IsNullOrWhiteSpace($Path)) { return $false }
    $full = $Path.Trim()
    if ($full.StartsWith('\\') -or $full.StartsWith('//')) { return $false }
    if ($full -match '^[A-Za-z]:\\?$') { return $false }
    if ($full -eq '/' -or $full -eq '\') { return $false }
    return $true
}
