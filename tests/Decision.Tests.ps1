# Decision tests for Emergency folder. Run from any OS:
#   pwsh -NoProfile -File tests/Decision.Tests.ps1

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

. (Join-Path (Split-Path $PSScriptRoot -Parent) 'EmergencyFolder.Logic.ps1')

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
Assert-Equal 'domain controller' (Get-DomainControllerAddress) '172.16.9.7'
Assert-Equal 'ping up' (Resolve-PingStatus -Succeeded $true) 'Up'
Assert-Equal 'ping down' (Resolve-PingStatus -Succeeded $false) 'Down'
Assert-Equal 'ping unknown' (Resolve-PingStatus -Succeeded $null) 'Unknown'

$once = Update-ButtonVisibility -Internet 'Down' -Visible $false -DownStreak 0 -UpStreak 0 -DownChecks 1 -UpChecks 1
Assert-Equal 'one missed ping shows button' $once.Visible 'True'
$back = Update-ButtonVisibility -Internet 'Up' -Visible $true -DownStreak 0 -UpStreak 0 -DownChecks 1 -UpChecks 1
Assert-Equal 'one reply hides button' $back.Visible 'False'

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
Assert-True 'local install dir' (Test-EmergencyFolderInstallDir 'C:\Program Files\Emergency folder')
Assert-True 'unc rejected' (-not (Test-EmergencyFolderInstallDir '\\server\share'))
Assert-True 'drive root rejected' (-not (Test-EmergencyFolderInstallDir 'C:\'))

$root = Split-Path $PSScriptRoot -Parent
foreach ($name in @('EmergencyFolder.ps1', 'EmergencyFolder.Widget.ps1', 'installer\EmergencyFolder.cs')) {
    $text = Get-Content -LiteralPath (Join-Path $root $name) -Raw -Encoding UTF8
    Assert-True ("no config reader in {0}" -f $name) ($text -notmatch 'config\.json')
    Assert-True ("no tray in {0}" -f $name) ($text -notmatch 'NotifyIcon')
    Assert-True ("no known folder write in {0}" -f $name) ($text -notmatch 'SHSetKnownFolderPath')
}
$logicText = Get-Content -LiteralPath (Join-Path $root 'EmergencyFolder.Logic.ps1') -Raw -Encoding UTF8
Assert-True 'logic has no json config' ($logicText -notmatch 'ConvertFrom-Json')
$widgetText = Get-Content -LiteralPath (Join-Path $root 'EmergencyFolder.Widget.ps1') -Raw -Encoding UTF8
Assert-True 'widget paints exclamation' ($widgetText -match 'DrawLine')
Assert-True 'smooth layered edge' ($widgetText -match 'UpdateLayeredWindow')
Assert-True 'no clipped window edge' ($widgetText -notmatch 'new Region')
$mainText = Get-Content -LiteralPath (Join-Path $root 'EmergencyFolder.ps1') -Raw -Encoding UTF8
Assert-True 'version bumped' ($mainText -match '1\.2\.44')
Assert-True 'program name' ($mainText -match 'Emergency folder')
Assert-True 'pings the domain controller' ($mainText -match '172\.16\.9\.7')
Assert-True 'checks every minute' ($mainText -match 'IntervalSeconds = 60')
Assert-True 'no external probe' ($mainText -notmatch 'msftconnecttest')

if ($script:Failed -gt 0) {
    Write-Host ("{0} failed" -f $script:Failed)
    exit 1
}
Write-Host 'all passed'
