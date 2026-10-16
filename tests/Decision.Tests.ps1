# Decision tests for DesktopSwitch. Run from any OS:
#   pwsh -NoProfile -File tests/Decision.Tests.ps1

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

. (Join-Path (Split-Path $PSScriptRoot -Parent) 'DesktopSwitch.Logic.ps1')

$script:Failed = 0

function Assert-Equal {
    param([string]$Name, $Actual, $Expected)
    if ([string]$Actual -ne [string]$Expected) {
        Write-Host ("FAIL {0}: expected [{1}] got [{2}]" -f $Name, $Expected, $Actual)
        $script:Failed++
    } else {
        Write-Host ("ok   {0}" -f $Name)
    }
}

function Assert-True {
    param([string]$Name, $Condition)
    if (-not $Condition) {
        Write-Host ("FAIL {0}" -f $Name)
        $script:Failed++
    } else {
        Write-Host ("ok   {0}" -f $Name)
    }
}

function Step-Button {
    param($State, [string]$Internet)
    $decision = Update-ButtonVisibility -Internet $Internet -Visible $State.Visible -DownStreak $State.Down -UpStreak $State.Up
    return @{
        Visible = [bool]$decision.Visible
        Down = [int]$decision.DownStreak
        Up = [int]$decision.UpStreak
        Changed = [bool]$decision.Changed
    }
}

Assert-Equal 'public desktop' (Get-PublicDesktopPath) 'C:\Users\Public\Desktop'

Assert-Equal 'windows up ignores probe' (Resolve-InternetStatus -WindowsInternet $true -ProbeSucceeded $false) 'Up'
Assert-Equal 'probe up wins' (Resolve-InternetStatus -WindowsInternet $false -ProbeSucceeded $true) 'Up'
Assert-Equal 'windows down' (Resolve-InternetStatus -WindowsInternet $false -ProbeSucceeded $false) 'Down'
Assert-Equal 'probe down without windows' (Resolve-InternetStatus -WindowsInternet $null -ProbeSucceeded $false) 'Down'
Assert-Equal 'both unknown' (Resolve-InternetStatus -WindowsInternet $null -ProbeSucceeded $null) 'Unknown'

Assert-Equal 'empty probe' (Resolve-ProbeAggregate -Results @()) ''
Assert-Equal 'any probe success' (Resolve-ProbeAggregate -Results @($false, $true)) 'True'
Assert-Equal 'all probes fail' (Resolve-ProbeAggregate -Results @($false, $false)) 'False'

Assert-Equal 'offline probe shortened' (Get-InternetProbeTimeout -Configured 5 -WindowsInternet $false) '2'
Assert-Equal 'offline probe already short' (Get-InternetProbeTimeout -Configured 2 -WindowsInternet $false) '2'
Assert-Equal 'offline probe floor' (Get-InternetProbeTimeout -Configured 1 -WindowsInternet $false) '1'
Assert-Equal 'online probe kept' (Get-InternetProbeTimeout -Configured 5 -WindowsInternet $true) '5'
Assert-Equal 'unknown windows keeps probe' (Get-InternetProbeTimeout -Configured 5 -WindowsInternet $null) '5'
Assert-Equal 'probe clamp then shorten' (Get-InternetProbeTimeout -Configured 100 -WindowsInternet $false) '2'
Assert-Equal 'probe clamp online' (Get-InternetProbeTimeout -Configured 100 -WindowsInternet $true) '30'
Assert-Equal 'probe minimum' (Get-InternetProbeTimeout -Configured 0 -WindowsInternet $true) '1'

$state = @{ Visible = $false; Down = 0; Up = 0 }
$state = Step-Button $state 'Down'
Assert-Equal 'first down hidden' $state.Visible 'False'
Assert-Equal 'first down streak' $state.Down '1'
Assert-Equal 'first down unchanged' $state.Changed 'False'

$state = Step-Button $state 'Down'
Assert-Equal 'second down shown' $state.Visible 'True'
Assert-Equal 'second down streak capped' $state.Down '2'
Assert-Equal 'second down changed' $state.Changed 'True'
Assert-Equal 'second down clears up' $state.Up '0'

$state = Step-Button $state 'Down'
Assert-Equal 'third down stays' $state.Visible 'True'
Assert-Equal 'third down not changed' $state.Changed 'False'

$state = Step-Button $state 'Unknown'
Assert-Equal 'unknown holds button' $state.Visible 'True'
Assert-Equal 'unknown resets down' $state.Down '0'
Assert-Equal 'unknown resets up' $state.Up '0'
Assert-Equal 'unknown unchanged' $state.Changed 'False'

$state = Step-Button $state 'Up'
Assert-Equal 'first up still shown' $state.Visible 'True'
Assert-Equal 'first up streak' $state.Up '1'
Assert-Equal 'first up clears down' $state.Down '0'

$state = Step-Button $state 'Up'
Assert-Equal 'second up hides' $state.Visible 'False'
Assert-Equal 'second up changed' $state.Changed 'True'

$state = Step-Button $state 'Up'
Assert-Equal 'third up stays hidden' $state.Visible 'False'
Assert-Equal 'third up unchanged' $state.Changed 'False'

$state = Step-Button $state 'Down'
$state = Step-Button $state 'Up'
Assert-Equal 'single down does not stick' $state.Visible 'False'
Assert-Equal 'up after one down resets down' $state.Down '0'

$hidden = @{ Visible = $false; Down = 0; Up = 0 }
$hidden = Step-Button $hidden 'Unknown'
Assert-Equal 'unknown at start stays hidden' $hidden.Visible 'False'
Assert-Equal 'unknown at start unchanged' $hidden.Changed 'False'

Assert-True 'system account' (Test-InstallerSystemAccount 'NT AUTHORITY\SYSTEM')
Assert-True 'domain system' (Test-InstallerSystemAccount 'CONTOSO\SYSTEM')
Assert-True 'user is not system' (-not (Test-InstallerSystemAccount 'CONTOSO\ivanov'))
Assert-Equal 'user startup' (Resolve-InstallerStartupScope -AllUsers $false -SystemAccount $false) 'CurrentUser'
Assert-Equal 'machine startup' (Resolve-InstallerStartupScope -AllUsers $true -SystemAccount $false) 'AllUsers'
Assert-True 'system does not launch' (-not (Test-InstallerShouldLaunch -SystemAccount $true -NoLaunch $false))
Assert-True 'user launch' (Test-InstallerShouldLaunch -SystemAccount $false -NoLaunch $false)
Assert-True 'local install dir' (Test-DesktopSwitchInstallDir 'C:\Program Files\DesktopSwitch')
Assert-True 'unc rejected' (-not (Test-DesktopSwitchInstallDir '\\server\share'))
Assert-True 'drive root rejected' (-not (Test-DesktopSwitchInstallDir 'C:\'))

$root = Split-Path $PSScriptRoot -Parent
foreach ($name in @('DesktopSwitch.ps1', 'DesktopSwitch.Widget.ps1', 'installer\DesktopSwitch.cs')) {
    $text = Get-Content -LiteralPath (Join-Path $root $name) -Raw -Encoding UTF8
    Assert-True ("no config reader in {0}" -f $name) ($text -notmatch 'config\.json')
    Assert-True ("no tray in {0}" -f $name) ($text -notmatch 'NotifyIcon')
    Assert-True ("no known folder write in {0}" -f $name) ($text -notmatch 'SHSetKnownFolderPath')
}
$logicText = Get-Content -LiteralPath (Join-Path $root 'DesktopSwitch.Logic.ps1') -Raw -Encoding UTF8
Assert-True 'logic has no json config' ($logicText -notmatch 'ConvertFrom-Json')
Assert-True 'widget paints exclamation' ((Get-Content -LiteralPath (Join-Path $root 'DesktopSwitch.Widget.ps1') -Raw -Encoding UTF8) -match 'DrawLine')
Assert-True 'version bumped' ((Get-Content -LiteralPath (Join-Path $root 'DesktopSwitch.ps1') -Raw -Encoding UTF8) -match '1\.2\.41')

if ($script:Failed -gt 0) {
    Write-Host ("{0} failed" -f $script:Failed)
    exit 1
}
Write-Host 'all passed'
