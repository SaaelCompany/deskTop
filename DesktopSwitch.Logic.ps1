# Pure decision logic for DesktopSwitch.
# This file does not touch the registry, the network, or Explorer, so it can be tested
# on any operating system. Windows PowerShell 5.1 compatible: no ternary operator.

Set-StrictMode -Version 2.0

function Get-Prop {
    param($Object, [string]$Name, $Default)
    if ($null -eq $Object) { return $Default }
    $prop = $Object.PSObject.Properties[$Name]
    if ($null -eq $prop -or $null -eq $prop.Value) { return $Default }
    # The comma keeps an empty array from disappearing on the way out of the function.
    ,$prop.Value
}

function ConvertTo-Bool {
    param($Value, [bool]$Default)
    if ($null -eq $Value) { return $Default }
    if ($Value -is [bool]) { return [bool]$Value }
    $text = ([string]$Value).Trim().ToLowerInvariant()
    if ($text -eq '1' -or $text -eq 'true' -or $text -eq 'yes' -or $text -eq 'да') { return $true }
    if ($text -eq '0' -or $text -eq 'false' -or $text -eq 'no' -or $text -eq 'нет') { return $false }
    return $Default
}

function ConvertTo-Int {
    param($Value, [int]$Default)
    if ($null -eq $Value) { return $Default }
    $number = 0
    if ([int]::TryParse(([string]$Value).Trim(), [ref]$number)) { return $number }
    return $Default
}

function ConvertTo-ExpandedPath {
    param([string]$Path)
    if ([string]::IsNullOrWhiteSpace($Path)) { return '' }
    $expanded = [Environment]::ExpandEnvironmentVariables($Path.Trim())
    # GetFullPath on non-Windows treats backslash as a normal character and would
    # prefix the Linux working directory. Normalize only where backslash is a separator.
    $windows = [System.IO.Path]::DirectorySeparatorChar -eq '\'
    $driveOrUnc = $expanded -match '^[A-Za-z]:\\' -or $expanded.StartsWith('\\')
    if ($windows -and $driveOrUnc) {
        try { return [System.IO.Path]::GetFullPath($expanded) } catch { return $expanded }
    }
    return $expanded
}

function Test-UncPathString {
    param([string]$Path)
    if ([string]::IsNullOrWhiteSpace($Path)) { return $false }
    return $Path.Trim() -match '^\\\\[^\\]+\\[^\\]+'
}

function Test-ExampleNetworkPath {
    param([string]$Path)
    if ([string]::IsNullOrWhiteSpace($Path)) { return $false }
    return $Path.Trim() -match '(?i)(^\\\\CHANGE-ME\\)|\\CHANGE-ME(\\|$)'
}

function Get-UncHost {
    param([string]$Path)
    if ($Path -match '^\\\\([^\\]+)\\') { return $Matches[1] }
    return ''
}

function Compare-DesktopPath {
    param([string]$Left, [string]$Right)
    if ([string]::IsNullOrWhiteSpace($Left) -or [string]::IsNullOrWhiteSpace($Right)) { return $false }
    $a = $Left.Trim().TrimEnd('\', '/').ToLowerInvariant()
    $b = $Right.Trim().TrimEnd('\', '/').ToLowerInvariant()
    return $a -eq $b
}

function Get-ClampedInterval {
    param([int]$Seconds)
    if ($Seconds -lt 5) { return 5 }
    if ($Seconds -gt 3600) { return 3600 }
    return $Seconds
}

function Get-ClampedCount {
    param([int]$Value)
    if ($Value -lt 1) { return 1 }
    if ($Value -gt 100) { return 100 }
    return $Value
}

function Get-ClampedTimeout {
    param([int]$Seconds)
    if ($Seconds -lt 1) { return 1 }
    if ($Seconds -gt 30) { return 30 }
    return $Seconds
}

function Get-ClampedLogBytes {
    param([int]$Bytes)
    $min = 65536
    $max = 20971520
    if ($Bytes -lt $min) { return $min }
    if ($Bytes -gt $max) { return $max }
    return $Bytes
}

function Select-HttpProbeUrl {
    param([string[]]$Urls)
    $clean = New-Object System.Collections.Generic.List[string]
    if ($null -eq $Urls) { return ,$clean }
    foreach ($candidate in $Urls) {
        if ([string]::IsNullOrWhiteSpace($candidate)) { continue }
        $uri = $null
        $ok = [Uri]::TryCreate($candidate.Trim(), [UriKind]::Absolute, [ref]$uri)
        if ($ok -and $null -ne $uri -and ($uri.Scheme -eq 'http' -or $uri.Scheme -eq 'https')) {
            $clean.Add($uri.AbsoluteUri)
        }
    }
    return ,$clean
}

function Get-EffectiveDesktopConfig {
    param($Config)
    $triggerRaw = [string](Get-Prop $Config 'Trigger' 'InternetOrShare')
    $triggerKey = $triggerRaw.Trim().ToLowerInvariant()
    $triggerMap = @{
        'internet' = 'Internet'
        'share' = 'Share'
        'internetorshare' = 'InternetOrShare'
    }
    if (-not $triggerMap.ContainsKey($triggerKey)) {
        throw "Неизвестное значение Trigger '$triggerRaw'. Допустимо: Internet, Share, InternetOrShare."
    }

    $internet = Get-Prop $Config 'InternetCheck' $null
    $probeList = New-Object System.Collections.Generic.List[string]
    $expectedBody = ''
    $hasProbeProperty = $false
    if ($null -ne $internet) {
        $probeProp = $internet.PSObject.Properties['ProbeUrls']
        if ($null -ne $probeProp) {
            $hasProbeProperty = $true
            if ($null -ne $probeProp.Value) {
                foreach ($candidate in @($probeProp.Value)) {
                    if (-not [string]::IsNullOrWhiteSpace([string]$candidate)) {
                        $probeList.Add([string]$candidate)
                    }
                }
            }
        }
    }
    if (-not $hasProbeProperty) {
        $probeList.Add('http://www.msftconnecttest.com/connecttest.txt')
        $expectedBody = 'Microsoft Connect Test'
    }
    if ($null -ne $internet) {
        $explicitExpected = Get-Prop $internet 'ExpectedProbeBody' $null
        if ($null -ne $explicitExpected) { $expectedBody = [string]$explicitExpected }
    }
    $selectedProbes = Select-HttpProbeUrl -Urls $probeList.ToArray()

    $extensions = New-Object System.Collections.Generic.List[string]
    $extNode = Get-Prop $Config 'SyncExtensions' $null
    if ($null -eq $extNode) {
        $extensions.Add('.lnk')
        $extensions.Add('.url')
    } else {
        foreach ($ext in @($extNode)) {
            $name = ([string]$ext).Trim().ToLowerInvariant()
            if ([string]::IsNullOrWhiteSpace($name)) { continue }
            if (-not $name.StartsWith('.')) { $name = '.' + $name }
            if ($name.Length -gt 1) { $extensions.Add($name) }
        }
    }

    $localRaw = [string](Get-Prop $Config 'LocalDesktopPath' '%LOCALAPPDATA%\DesktopSwitch\LocalDesktop')
    $logRaw = [string](Get-Prop $Config 'LogPath' '%LOCALAPPDATA%\DesktopSwitch\desktop-switch.log')
    $stateRaw = [string](Get-Prop $Config 'StatePath' '%LOCALAPPDATA%\DesktopSwitch\state.json')

    return [pscustomobject]@{
        Enabled = ConvertTo-Bool (Get-Prop $Config 'Enabled' $false) $false
        NetworkDesktopPath = ([string](Get-Prop $Config 'NetworkDesktopPath' '')).Trim()
        LocalDesktopPath = ConvertTo-ExpandedPath $localRaw
        Trigger = $triggerMap[$triggerKey]
        CheckIntervalSeconds = Get-ClampedInterval (ConvertTo-Int (Get-Prop $Config 'CheckIntervalSeconds' 15) 15)
        FailuresBeforeSwitch = Get-ClampedCount (ConvertTo-Int (Get-Prop $Config 'FailuresBeforeSwitch' 2) 2)
        SuccessesBeforeRestore = Get-ClampedCount (ConvertTo-Int (Get-Prop $Config 'SuccessesBeforeRestore' 3) 3)
        RestoreWhenOnline = ConvertTo-Bool (Get-Prop $Config 'RestoreWhenOnline' $true) $true
        RestartExplorer = ConvertTo-Bool (Get-Prop $Config 'RestartExplorer' $true) $true
        NotifyUser = ConvertTo-Bool (Get-Prop $Config 'NotifyUser' $true) $true
        SyncShortcutsWhileOnline = ConvertTo-Bool (Get-Prop $Config 'SyncShortcutsWhileOnline' $true) $true
        SyncExtensions = $extensions.ToArray()
        UseWindowsConnectivity = ConvertTo-Bool (Get-Prop $internet 'UseWindowsConnectivity' $true) $true
        ProbeUrls = @($selectedProbes)
        ExpectedProbeBody = $expectedBody
        ProbeTimeoutSeconds = Get-ClampedTimeout (ConvertTo-Int (Get-Prop $internet 'ProbeTimeoutSeconds' 5) 5)
        ShareProbeTimeoutSeconds = Get-ClampedTimeout (ConvertTo-Int (Get-Prop $Config 'ShareProbeTimeoutSeconds' 4) 4)
        LogPath = ConvertTo-ExpandedPath $logRaw
        StatePath = ConvertTo-ExpandedPath $stateRaw
        MaxLogBytes = Get-ClampedLogBytes (ConvertTo-Int (Get-Prop $Config 'MaxLogBytes' 1048576) 1048576)
    }
}

function Get-DesktopConfigErrors {
    param(
        [string]$NetworkPath,
        [string]$LocalPath,
        [switch]$AllowEmptyNetwork
    )
    $errors = New-Object System.Collections.Generic.List[string]
    $network = ''
    if (-not [string]::IsNullOrWhiteSpace($NetworkPath)) { $network = $NetworkPath.Trim() }
    $local = ''
    if (-not [string]::IsNullOrWhiteSpace($LocalPath)) { $local = $LocalPath.Trim() }

    if ([string]::IsNullOrWhiteSpace($network)) {
        if (-not $AllowEmptyNetwork) {
            $errors.Add('Укажите NetworkDesktopPath — UNC-путь общей папки рабочего стола, например \\server\share\Desktop. Либо оставьте путь пустым и один раз запустите программу, пока сетевой рабочий стол ещё открыт: путь будет определён автоматически.')
        }
    } elseif (-not (Test-UncPathString $network)) {
        $errors.Add('NetworkDesktopPath должен быть UNC-путём вида \\server\share\Desktop.')
    } elseif (Test-ExampleNetworkPath $network) {
        $errors.Add('NetworkDesktopPath всё ещё содержит CHANGE-ME. Замените его на реальный сервер.')
    }

    if ([string]::IsNullOrWhiteSpace($local)) {
        $errors.Add('Укажите LocalDesktopPath.')
    } elseif (Test-UncPathString $local) {
        $errors.Add('LocalDesktopPath должен быть папкой на локальном диске, а не сетевым путём.')
    } elseif ($local -notmatch '^[A-Za-z]:\\') {
        $errors.Add('LocalDesktopPath после подстановки переменных должен быть путём вида C:\Users\имя\AppData\Local\DesktopSwitch\LocalDesktop.')
    } elseif ($local -match '^[A-Za-z]:\\$') {
        $errors.Add('LocalDesktopPath не должен быть корнем диска.')
    }

    if (-not [string]::IsNullOrWhiteSpace($network) -and -not [string]::IsNullOrWhiteSpace($local)) {
        if (Compare-DesktopPath $network $local) {
            $errors.Add('NetworkDesktopPath и LocalDesktopPath должны различаться.')
        }
    }
    return ,$errors
}

function Resolve-NetworkPathValue {
    param([string]$Configured, [string]$Learned, [string]$Current)
    if (Test-UncPathString $Configured) { return $Configured.Trim() }
    if (Test-UncPathString $Learned) { return $Learned.Trim() }
    if (Test-UncPathString $Current) { return $Current.Trim() }
    return ''
}

function Get-DesktopModeFromPath {
    param([string]$CurrentPath, [string]$NetworkPath, [string]$LocalPath)
    if (Compare-DesktopPath $CurrentPath $LocalPath) { return 'Local' }
    if (Compare-DesktopPath $CurrentPath $NetworkPath) { return 'Network' }
    if (Test-UncPathString $CurrentPath) { return 'Network' }
    if (-not [string]::IsNullOrWhiteSpace($CurrentPath)) { return 'Local' }
    return 'Network'
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

function Get-ConnectivityVerdict {
    param(
        [ValidateSet('Internet', 'Share', 'InternetOrShare')]
        [string]$Trigger,
        [ValidateSet('Up', 'Down', 'Unknown')]
        [string]$Internet,
        [ValidateSet('Up', 'Down', 'Unknown')]
        [string]$Share
    )
    if ($Trigger -eq 'Internet') {
        if ($Internet -eq 'Up') { return 'Online' }
        if ($Internet -eq 'Down') { return 'Offline' }
        return 'Unknown'
    }
    if ($Trigger -eq 'Share') {
        if ($Share -eq 'Up') { return 'Online' }
        if ($Share -eq 'Down') { return 'Offline' }
        return 'Unknown'
    }
    if ($Internet -eq 'Down' -or $Share -eq 'Down') { return 'Offline' }
    if ($Internet -eq 'Up' -and $Share -eq 'Up') { return 'Online' }
    return 'Unknown'
}

function Get-OfflineReasonCode {
    param(
        [ValidateSet('Up', 'Down', 'Unknown')]
        [string]$Internet,
        [ValidateSet('Up', 'Down', 'Unknown')]
        [string]$Share
    )
    $internetDown = $Internet -eq 'Down'
    $shareDown = $Share -eq 'Down'
    if ($internetDown -and $shareDown) { return 'Both' }
    if ($internetDown) { return 'Internet' }
    if ($shareDown) { return 'Share' }
    return 'None'
}

function Get-SwitchMessage {
    param(
        [string]$Action,
        [ValidateSet('Internet', 'Share', 'Both', 'None')]
        [string]$ReasonCode
    )
    if ($Action -eq 'SwitchToLocal' -or $Action -eq 'ReassertLocal') {
        $tail = ' Файлы, созданные на нём, останутся на этом компьютере.'
        if ($ReasonCode -eq 'Internet') {
            return 'Нет доступа в интернет. Включён локальный рабочий стол.' + $tail
        }
        if ($ReasonCode -eq 'Share') {
            return 'Общая папка рабочего стола недоступна. Включён локальный рабочий стол.' + $tail
        }
        return 'Нет доступа к сети. Включён локальный рабочий стол.' + $tail
    }
    if ($Action -eq 'SwitchToNetwork') {
        return 'Доступ к сети восстановлен. Снова включён сетевой рабочий стол.'
    }
    return ''
}

function Update-SwitchDecision {
    param(
        [ValidateSet('Online', 'Offline', 'Unknown')]
        [string]$Verdict,
        [ValidateSet('Network', 'Local')]
        [string]$Mode,
        [int]$FailureStreak,
        [int]$SuccessStreak,
        [int]$FailuresBeforeSwitch,
        [int]$SuccessesBeforeRestore,
        [bool]$RestoreWhenOnline
    )
    if ($FailureStreak -lt 0) { $FailureStreak = 0 }
    if ($SuccessStreak -lt 0) { $SuccessStreak = 0 }

    # An unknown reading is not evidence either way. Reset the streaks so a switch
    # happens only after consecutive definite results.
    if ($Verdict -eq 'Unknown') {
        return [pscustomobject]@{
            Mode = $Mode
            FailureStreak = 0
            SuccessStreak = 0
            Action = 'Hold'
        }
    }

    if ($Verdict -eq 'Offline') {
        $SuccessStreak = 0
        $FailureStreak++
        if ($FailureStreak -gt 1000) { $FailureStreak = 1000 }
        if ($Mode -eq 'Network' -and $FailureStreak -ge $FailuresBeforeSwitch) {
            return [pscustomobject]@{
                Mode = 'Local'
                FailureStreak = $FailureStreak
                SuccessStreak = 0
                Action = 'SwitchToLocal'
            }
        }
        $action = 'WaitOffline'
        if ($Mode -eq 'Local') { $action = 'ReassertLocal' }
        return [pscustomobject]@{
            Mode = $Mode
            FailureStreak = $FailureStreak
            SuccessStreak = 0
            Action = $action
        }
    }

    $FailureStreak = 0
    $SuccessStreak++
    if ($SuccessStreak -gt 1000) { $SuccessStreak = 1000 }
    if ($Mode -eq 'Local' -and $RestoreWhenOnline -and $SuccessStreak -ge $SuccessesBeforeRestore) {
        return [pscustomobject]@{
            Mode = 'Network'
            FailureStreak = 0
            SuccessStreak = $SuccessStreak
            Action = 'SwitchToNetwork'
        }
    }
    $action = 'StayNetwork'
    if ($Mode -eq 'Local') { $action = 'WaitOnline' }
    return [pscustomobject]@{
        Mode = $Mode
        FailureStreak = 0
        SuccessStreak = $SuccessStreak
        Action = $action
    }
}

function Test-DesktopChangeNeeded {
    param(
        [string]$Action,
        [string]$CurrentPath,
        [string]$LocalPath,
        [string]$NetworkPath
    )
    if ($Action -eq 'SwitchToLocal' -or $Action -eq 'ReassertLocal') {
        return -not (Compare-DesktopPath $CurrentPath $LocalPath)
    }
    if ($Action -eq 'SwitchToNetwork') {
        return -not (Compare-DesktopPath $CurrentPath $NetworkPath)
    }
    return $false
}

function Get-ActionTargetPath {
    param(
        [string]$Action,
        [string]$LocalPath,
        [string]$NetworkPath
    )
    if ($Action -eq 'SwitchToLocal' -or $Action -eq 'ReassertLocal') { return $LocalPath }
    if ($Action -eq 'SwitchToNetwork') { return $NetworkPath }
    return ''
}

function Test-ShouldSyncShortcuts {
    param(
        [bool]$SyncEnabled,
        [string]$ShareStatus
    )
    if (-not $SyncEnabled) { return $false }
    return $ShareStatus -eq 'Up'
}

function Test-ReparseAttribute {
    param([int]$Attributes)
    $reparse = [int][System.IO.FileAttributes]::ReparsePoint
    return (($Attributes -band $reparse) -ne 0)
}

function Test-CooldownElapsed {
    param(
        [string]$Stamp,
        [datetime]$Now,
        [int]$CooldownSeconds
    )
    if ([string]::IsNullOrWhiteSpace($Stamp)) { return $true }
    $when = [datetime]::MinValue
    $parsed = [datetime]::TryParse(
        $Stamp,
        [System.Globalization.CultureInfo]::InvariantCulture,
        [System.Globalization.DateTimeStyles]::RoundtripKind,
        [ref]$when)
    if (-not $parsed) { return $true }
    return ($Now - $when).TotalSeconds -ge $CooldownSeconds
}
