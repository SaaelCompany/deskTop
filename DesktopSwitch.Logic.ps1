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

function Remove-JsonComments {
    param([string]$Text)
    if ([string]::IsNullOrEmpty($Text)) { return '' }
    $builder = New-Object System.Text.StringBuilder
    $inString = $false
    $escape = $false
    $chars = $Text.ToCharArray()
    $i = 0
    while ($i -lt $chars.Length) {
        $c = $chars[$i]
        if ($inString) {
            [void]$builder.Append($c)
            if ($escape) {
                $escape = $false
            } elseif ($c -eq '\') {
                $escape = $true
            } elseif ($c -eq '"') {
                $inString = $false
            }
            $i++
            continue
        }
        if ($c -eq '"') {
            $inString = $true
            [void]$builder.Append($c)
            $i++
            continue
        }
        if ($c -eq '/' -and ($i + 1) -lt $chars.Length -and $chars[$i + 1] -eq '/') {
            $i += 2
            while ($i -lt $chars.Length -and $chars[$i] -ne "`n" -and $chars[$i] -ne "`r") { $i++ }
            continue
        }
        [void]$builder.Append($c)
        $i++
    }
    return $builder.ToString()
}

function ConvertFrom-DesktopJson {
    param([string]$Text)
    $clean = Remove-JsonComments $Text
    if ([string]::IsNullOrWhiteSpace($clean)) { throw 'Файл JSON пуст.' }
    return ($clean | ConvertFrom-Json)
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

function Resolve-AppThemeLight {
    param($AppsUseLightTheme)
    if ($null -eq $AppsUseLightTheme) { return $true }
    $text = ([string]$AppsUseLightTheme).Trim()
    if ([string]::IsNullOrWhiteSpace($text)) { return $true }
    $number = 0
    if (-not [int]::TryParse($text, [ref]$number)) { return $true }
    return $number -ne 0
}

function Resolve-ShowLauncher {
    param($Stored)
    return ConvertTo-Bool $Stored $true
}

function Resolve-StayOnTop {
    param($Stored)
    return ConvertTo-Bool $Stored $true
}

function ConvertTo-WidgetColor {
    param([string]$Text)
    $clean = Get-WidgetColorHex $Text
    if ([string]::IsNullOrWhiteSpace($clean)) { return '' }
    return ('#{0}' -f $clean.Substring(0, 6))
}

function Get-WidgetColorHex {
    param([string]$Text)
    if ([string]::IsNullOrWhiteSpace($Text)) { return '' }
    $clean = $Text.Trim()
    if ($clean.StartsWith('#')) { $clean = $clean.Substring(1) }
    if ($clean.Length -eq 3 -or $clean.Length -eq 4) {
        $expanded = ''
        foreach ($char in $clean.ToCharArray()) { $expanded += ('' + $char + $char) }
        $clean = $expanded
    }
    if ($clean.Length -ne 6 -and $clean.Length -ne 8) { return '' }
    $index = 0
    while ($index -lt $clean.Length) {
        $byte = 0
        $parsed = [int]::TryParse($clean.Substring($index, 2), [System.Globalization.NumberStyles]::HexNumber, [System.Globalization.CultureInfo]::InvariantCulture, [ref]$byte)
        if (-not $parsed -or $byte -lt 0 -or $byte -gt 255) { return '' }
        $index += 2
    }
    return $clean.ToUpperInvariant()
}

function Resolve-WidgetOpacity {
    param($Stored, [string]$ColorText)
    $fromColor = -1
    $hex = Get-WidgetColorHex $ColorText
    if ($hex.Length -eq 8) {
        $alpha = 0
        $parsedAlpha = [int]::TryParse($hex.Substring(6, 2), [System.Globalization.NumberStyles]::HexNumber, [System.Globalization.CultureInfo]::InvariantCulture, [ref]$alpha)
        if ($parsedAlpha) { $fromColor = [int][Math]::Round(100.0 * $alpha / 255.0) }
    }
    if ($null -eq $Stored) {
        if ($fromColor -ge 0) { return $fromColor }
        return 100
    }
    $text = ([string]$Stored).Trim()
    if ($text.EndsWith('%')) { $text = $text.Substring(0, $text.Length - 1).Trim() }
    if ([string]::IsNullOrWhiteSpace($text)) {
        if ($fromColor -ge 0) { return $fromColor }
        return 100
    }
    $number = 0.0
    $style = [System.Globalization.NumberStyles]::Float
    $parsed = [double]::TryParse($text, $style, [System.Globalization.CultureInfo]::InvariantCulture, [ref]$number)
    if (-not $parsed) {
        $parsed = [double]::TryParse($text, $style, [System.Globalization.CultureInfo]::CurrentCulture, [ref]$number)
    }
    if (-not $parsed) {
        if ($fromColor -ge 0) { return $fromColor }
        return 100
    }
    if ($number -ge 0 -and $number -le 1) { $number = $number * 100 }
    if ($number -lt 0) { return 0 }
    if ($number -gt 100) { return 100 }
    return [int][Math]::Round($number)
}

function Get-WidgetPalette {
    param([bool]$Light)
    if ($Light) {
        return @{
            Canvas = @(255, 255, 255)
            Ink = @(24, 24, 27)
            Muted = @(113, 113, 122)
            Label = @(71, 85, 105)
            FieldBorder = @(226, 232, 240)
            FieldFill = @(255, 255, 255)
            FieldReadOnly = @(248, 250, 252)
            Icon = @(148, 163, 184)
            Hover = @(244, 244, 245)
            Selection = @(232, 240, 255)
            Rule = @(244, 244, 245)
            Accent = @(47, 107, 255)
            AccentHover = @(37, 90, 230)
            StatusMuted = @(113, 113, 122)
            StatusLocal = @(185, 28, 28)
            StatusOnline = @(22, 101, 52)
            StatusError = @(146, 43, 33)
            StatusOk = @(25, 111, 61)
            Maintenance = @(180, 83, 9)
            Empty = @(31, 41, 51)
            Detail = @(75, 85, 99)
        }
    }
    return @{
        Canvas = @(32, 32, 36)
        Ink = @(244, 244, 245)
        Muted = @(161, 161, 170)
        Label = @(203, 213, 225)
        FieldBorder = @(63, 63, 70)
        FieldFill = @(39, 39, 42)
        FieldReadOnly = @(28, 28, 32)
        Icon = @(148, 163, 184)
        Hover = @(48, 48, 54)
        Selection = @(46, 58, 82)
        Rule = @(63, 63, 70)
        Accent = @(47, 107, 255)
        AccentHover = @(37, 90, 230)
        StatusMuted = @(161, 161, 170)
        StatusLocal = @(248, 113, 113)
        StatusOnline = @(74, 222, 128)
        StatusError = @(252, 165, 165)
        StatusOk = @(134, 239, 172)
        Maintenance = @(251, 191, 36)
        Empty = @(244, 244, 245)
        Detail = @(161, 161, 170)
    }
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

function Get-InternetProbeTimeout {
    param([int]$Configured, $WindowsInternet)
    $timeout = Get-ClampedTimeout $Configured
    if ($WindowsInternet -eq $false -and $timeout -gt 2) { return 2 }
    return $timeout
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

    $widget = Get-Prop $Config 'Widget' $null
    $cornerRaw = ([string](Get-Prop $widget 'Corner' 'BottomRight')).Trim().ToLowerInvariant()
    $cornerMap = @{
        'bottomright' = 'BottomRight'
        'bottomleft' = 'BottomLeft'
        'topright' = 'TopRight'
        'topleft' = 'TopLeft'
    }
    $cornerKey = 'bottomright'
    if ($cornerMap.ContainsKey($cornerRaw)) { $cornerKey = $cornerRaw }

    $localRaw = [string](Get-Prop $Config 'LocalDesktopPath' '%LOCALAPPDATA%\DesktopSwitch\LocalDesktop')
    $logRaw = [string](Get-Prop $Config 'LogPath' '%LOCALAPPDATA%\DesktopSwitch\desktop-switch.log')
    $stateRaw = [string](Get-Prop $Config 'StatePath' '%LOCALAPPDATA%\DesktopSwitch\state.json')
    $serviceDeskUrl = Select-SingleHttpUrl (Get-Prop $widget 'ServiceDeskUrl' '')
    $serviceDeskApi = Select-SingleHttpUrl (Get-Prop $widget 'ServiceDeskApiUrl' '')
    $jiraBaseUrl = Select-SingleHttpUrl (Get-Prop $widget 'JiraBaseUrl' '')
    $serviceDeskProvider = Resolve-ServiceDeskProvider -Requested ([string](Get-Prop $widget 'ServiceDesk' '')) -JiraBaseUrl $jiraBaseUrl -ApiUrl $serviceDeskApi -PortalUrl $serviceDeskUrl
    $serviceDeskCategories = Get-ServiceDeskCategories $widget
    $serviceDeskProjects = Get-ServiceDeskProjects $widget
    $widgetColorText = ([string](Get-Prop $widget 'Color' '')).Trim()

    return [pscustomobject]@{
        Enabled = ConvertTo-Bool (Get-Prop $Config 'Enabled' $false) $false
        NetworkDesktopPath = ([string](Get-Prop $Config 'NetworkDesktopPath' '')).Trim()
        LocalDesktopPath = ConvertTo-ExpandedPath $localRaw
        Trigger = $triggerMap[$triggerKey]
        CheckIntervalSeconds = Get-ClampedInterval (ConvertTo-Int (Get-Prop $Config 'CheckIntervalSeconds' 5) 5)
        FailuresBeforeSwitch = Get-ClampedCount (ConvertTo-Int (Get-Prop $Config 'FailuresBeforeSwitch' 2) 2)
        SuccessesBeforeRestore = Get-ClampedCount (ConvertTo-Int (Get-Prop $Config 'SuccessesBeforeRestore' 2) 2)
        RestoreWhenOnline = ConvertTo-Bool (Get-Prop $Config 'RestoreWhenOnline' $true) $true
        RestartExplorer = ConvertTo-Bool (Get-Prop $Config 'RestartExplorer' $true) $true
        NotifyUser = ConvertTo-Bool (Get-Prop $Config 'NotifyUser' $true) $true
        Preview = ConvertTo-Bool (Get-Prop $Config 'Preview' $false) $false
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
        WidgetEnabled = ConvertTo-Bool (Get-Prop $widget 'Enabled' $true) $true
        WidgetTitle = ([string](Get-Prop $widget 'Title' 'Сервисная служба')).Trim()
        WidgetIcon = ([string](Get-Prop $widget 'Icon' '')).Trim()
        WidgetColor = ConvertTo-WidgetColor $widgetColorText
        WidgetOpacity = Resolve-WidgetOpacity (Get-Prop $widget 'Opacity' $null) $widgetColorText
        WidgetCorner = $cornerMap[$cornerKey]
        WidgetMargin = Get-ClampedMargin (ConvertTo-Int (Get-Prop $widget 'Margin' 16) 16)
        ServiceDeskUrl = $serviceDeskUrl
        ServiceDeskApiUrl = $serviceDeskApi
        ServiceDeskToken = ([string](Get-Prop $widget 'ServiceDeskToken' '')).Trim()
        ServiceDeskProvider = $serviceDeskProvider
        ServiceDeskCategories = $serviceDeskCategories
        ServiceDeskProjects = $serviceDeskProjects
        JiraBaseUrl = $jiraBaseUrl
        NewsUrl = Select-SingleHttpUrl (Get-Prop $widget 'NewsUrl' '')
        NewsJql = ([string](Get-Prop $widget 'NewsJql' '')).Trim()
        NewsPollMinutes = Get-ClampedMinutes (ConvertTo-Int (Get-Prop $widget 'NewsPollMinutes' 10) 10)
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
            $errors.Add('Сетевой путь ещё неизвестен. Оставьте NetworkDesktopPath пустым: программа прочитает путь, который записала политика, когда сетевой стол открыт. Либо укажите UNC явно, если путь нужно зафиксировать.')
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
    # An explicit config path is optional. Group Policy writes the live UNC into the
    # user profile, and that path can differ between users, so the current shell path
    # wins over the path remembered earlier. The remembered path is used only after
    # the desktop has already been switched to a local folder.
    if (Test-UncPathString $Configured) { return $Configured.Trim() }
    if (Test-UncPathString $Current) { return $Current.Trim() }
    if (Test-UncPathString $Learned) { return $Learned.Trim() }
    return ''
}

function Get-ClampedMinutes {
    param([int]$Minutes)
    if ($Minutes -lt 1) { return 1 }
    if ($Minutes -gt 240) { return 240 }
    return $Minutes
}

function Get-ClampedMargin {
    param([int]$Pixels)
    if ($Pixels -lt 0) { return 0 }
    if ($Pixels -gt 80) { return 80 }
    return $Pixels
}

function Select-SingleHttpUrl {
    param($Url)
    if ([string]::IsNullOrWhiteSpace([string]$Url)) { return '' }
    $clean = Select-HttpProbeUrl -Urls @([string]$Url)
    if ($clean.Count -eq 0) { return '' }
    return [string]$clean[0]
}

function Resolve-ServiceDeskProvider {
    param(
        [string]$Requested,
        [string]$JiraBaseUrl,
        [string]$ApiUrl,
        [string]$PortalUrl
    )
    $key = ''
    if ($null -ne $Requested) { $key = $Requested.Trim().ToLowerInvariant() }
    $hasJira = -not [string]::IsNullOrWhiteSpace($JiraBaseUrl)
    $hasApi = -not [string]::IsNullOrWhiteSpace($ApiUrl)
    $hasPortal = -not [string]::IsNullOrWhiteSpace($PortalUrl)
    if ($key -eq 'jira' -or $key -eq 'jsm') {
        if ($hasJira) { return 'Jira' }
        return 'None'
    }
    if ($key -eq 'webhook' -or $key -eq 'generic' -or $key -eq 'http' -or $key -eq 'json') {
        if ($hasApi) { return 'Webhook' }
        if ($hasPortal) { return 'Portal' }
        return 'None'
    }
    if ($key -eq 'portal') {
        if ($hasPortal) { return 'Portal' }
        return 'None'
    }
    if ($key -eq 'none' -or $key -eq 'off' -or $key -eq 'нет') { return 'None' }
    if ($key -ne '' -and $key -ne 'auto') {
        throw "Неизвестное значение ServiceDesk '$Requested'. Допустимо: Auto, Webhook, Jira."
    }
    # A filled webhook address is the universal path and stays selected when a Jira
    # address is also present. Jira is used automatically only when it is the only target.
    if ($hasApi) { return 'Webhook' }
    if ($hasJira) { return 'Jira' }
    if ($hasPortal) { return 'Portal' }
    return 'None'
}

function Get-ServiceDeskCategories {
    param($Widget)
    $items = New-Object System.Collections.Generic.List[string]
    $seen = @{}
    $node = Get-Prop $Widget 'Categories' $null
    $raw = @()
    if ($null -ne $node) {
        if ($node -is [System.Array]) { $raw = $node }
        else { $raw = @([string]$node) }
    }
    foreach ($candidate in $raw) {
        $name = ([string]$candidate).Trim()
        if ([string]::IsNullOrWhiteSpace($name)) { continue }
        if ($name.Length -gt 80) { $name = $name.Substring(0, 80) }
        $marker = $name.ToLowerInvariant()
        if ($seen.ContainsKey($marker)) { continue }
        $seen[$marker] = $true
        $items.Add($name)
        if ($items.Count -ge 30) { break }
    }
    if ($items.Count -eq 0) {
        $items.Add('Инцидент')
        $items.Add('Запрос обслуживания')
        $items.Add('Вопрос')
    }
    return ,$items.ToArray()
}

function Format-ServiceDeskProjectLabel {
    param($Project)
    if ($null -eq $Project) { return '' }
    $name = ([string](Get-Prop $Project 'Name' '')).Trim()
    $id = ([string](Get-Prop $Project 'Id' '')).Trim()
    if ([string]::IsNullOrWhiteSpace($name)) { $name = $id }
    if ([string]::IsNullOrWhiteSpace($name)) { return '' }
    if (-not [string]::IsNullOrWhiteSpace($id) -and $name -ne $id) {
        return ('{0} ({1})' -f $name, $id)
    }
    return $name
}

function Get-ServiceDeskProjects {
    param($Widget)
    $items = New-Object System.Collections.Generic.List[object]
    $seen = @{}
    $node = Get-Prop $Widget 'Projects' $null
    $raw = @()
    if ($null -ne $node) {
        if ($node -is [System.Array]) { $raw = $node }
        else { $raw = @($node) }
    }
    foreach ($candidate in $raw) {
        if ($null -eq $candidate) { continue }
        $id = ''
        $name = ''
        if ($candidate -is [string]) {
            $name = $candidate.Trim()
            $id = $name
        } else {
            $id = ([string](Get-Prop $candidate 'id' '')).Trim()
            if ([string]::IsNullOrWhiteSpace($id)) { $id = ([string](Get-Prop $candidate 'Id' '')).Trim() }
            $name = ([string](Get-Prop $candidate 'name' '')).Trim()
            if ([string]::IsNullOrWhiteSpace($name)) { $name = ([string](Get-Prop $candidate 'Name' '')).Trim() }
            if ([string]::IsNullOrWhiteSpace($name)) { $name = $id }
            if ([string]::IsNullOrWhiteSpace($id)) { $id = $name }
        }
        if ([string]::IsNullOrWhiteSpace($name)) { continue }
        if ($name.Length -gt 80) { $name = $name.Substring(0, 80) }
        if ($id.Length -gt 80) { $id = $id.Substring(0, 80) }
        $marker = $id.ToLowerInvariant()
        if ($seen.ContainsKey($marker)) { continue }
        $seen[$marker] = $true
        $items.Add([pscustomobject]@{
            Id = $id
            Name = $name
        })
        if ($items.Count -ge 50) { break }
    }
    return ,$items.ToArray()
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

function Remove-NoticeMarkup {
    param([string]$Text)
    if ([string]::IsNullOrWhiteSpace($Text)) { return '' }
    $decoded = [System.Net.WebUtility]::HtmlDecode($Text)
    $plain = [regex]::Replace($decoded, '<[^>]+>', ' ')
    return ([regex]::Replace($plain, '\s+', ' ')).Trim()
}

function Get-NoticeKind {
    param([string]$Raw)
    if ([string]$Raw -match '(?i)maintenance|outage|incident|работ|техн') { return 'maintenance' }
    return 'news'
}

function Get-NoticeIdentity {
    param([string]$Explicit, [string]$Url, [string]$Title, [string]$PublishedAt)
    if (-not [string]::IsNullOrWhiteSpace($Explicit)) { return $Explicit.Trim() }
    if (-not [string]::IsNullOrWhiteSpace($Url)) { return $Url.Trim() }
    $raw = ([string]$Title + '|' + [string]$PublishedAt).ToLowerInvariant()
    $sha = [System.Security.Cryptography.SHA256]::Create()
    try {
        $bytes = [System.Text.Encoding]::UTF8.GetBytes($raw)
        $hash = $sha.ComputeHash($bytes)
        return ([System.BitConverter]::ToString($hash)).Replace('-', '').Substring(0, 16).ToLowerInvariant()
    } finally {
        $sha.Dispose()
    }
}

function ConvertTo-NoticeTime {
    param([string]$Raw)
    if ([string]::IsNullOrWhiteSpace($Raw)) { return '' }
    $when = [datetime]::MinValue
    $parsed = [datetime]::TryParse(
        $Raw,
        [System.Globalization.CultureInfo]::InvariantCulture,
        [System.Globalization.DateTimeStyles]::RoundtripKind,
        [ref]$when)
    if (-not $parsed) {
        $parsed = [datetime]::TryParse($Raw, [ref]$when)
    }
    if (-not $parsed) { return $Raw.Trim() }
    return $when.ToString('o')
}

function New-Notice {
    param([string]$Id, [string]$Title, [string]$Body, [string]$Kind, [string]$Url, [string]$PublishedAt)
    $safeTitle = Remove-NoticeMarkup $Title
    if ([string]::IsNullOrWhiteSpace($safeTitle)) { $safeTitle = 'Сообщение' }
    $safeUrl = ''
    if (-not [string]::IsNullOrWhiteSpace($Url)) { $safeUrl = $Url.Trim() }
    $published = ConvertTo-NoticeTime $PublishedAt
    return [pscustomobject]@{
        Id = Get-NoticeIdentity -Explicit $Id -Url $safeUrl -Title $safeTitle -PublishedAt $published
        Title = $safeTitle
        Body = Remove-NoticeMarkup $Body
        Kind = Get-NoticeKind $Kind
        Url = $safeUrl
        PublishedAt = $published
    }
}

function ConvertFrom-NewsJson {
    param($Parsed)
    $nodes = $null
    if ($Parsed -is [System.Array]) {
        $nodes = $Parsed
    } else {
        $nodes = Get-Prop $Parsed 'items' $null
        if ($null -eq $nodes) { $nodes = Get-Prop $Parsed 'Items' $null }
    }
    $items = New-Object System.Collections.Generic.List[object]
    foreach ($node in @($nodes)) {
        if ($null -eq $node) { continue }
        $kind = [string](Get-Prop $node 'kind' '')
        if ([string]::IsNullOrWhiteSpace($kind)) { $kind = [string](Get-Prop $node 'category' '') }
        $items.Add((New-Notice -Id ([string](Get-Prop $node 'id' '')) -Title ([string](Get-Prop $node 'title' '')) -Body ([string](Get-Prop $node 'body' '')) -Kind $kind -Url ([string](Get-Prop $node 'url' '')) -PublishedAt ([string](Get-Prop $node 'publishedAt' ''))))
    }
    return $items.ToArray()
}

function Get-XmlChildText {
    param($Node, [string]$Name)
    if ($null -eq $Node) { return '' }
    $child = $Node.SelectSingleNode("*[local-name()='$Name']")
    if ($null -eq $child) { return '' }
    return [string]$child.InnerText
}

function Get-XmlLink {
    param($Node)
    if ($null -eq $Node) { return '' }
    $link = $Node.SelectSingleNode("*[local-name()='link']")
    if ($null -eq $link) { return '' }
    $href = $link.GetAttribute('href')
    if (-not [string]::IsNullOrWhiteSpace($href)) { return $href }
    return [string]$link.InnerText
}

function ConvertFrom-NewsXml {
    param([xml]$Xml)
    $items = New-Object System.Collections.Generic.List[object]
    foreach ($node in @($Xml.SelectNodes('/rss/channel/item'))) {
        $items.Add((New-Notice -Id (Get-XmlChildText $node 'guid') -Title (Get-XmlChildText $node 'title') -Body (Get-XmlChildText $node 'description') -Kind (Get-XmlChildText $node 'category') -Url (Get-XmlLink $node) -PublishedAt (Get-XmlChildText $node 'pubDate')))
    }
    foreach ($node in @($Xml.SelectNodes('/*[local-name()="feed"]/*[local-name()="entry"]'))) {
        $body = Get-XmlChildText $node 'summary'
        if ([string]::IsNullOrWhiteSpace($body)) { $body = Get-XmlChildText $node 'content' }
        $items.Add((New-Notice -Id (Get-XmlChildText $node 'id') -Title (Get-XmlChildText $node 'title') -Body $body -Kind (Get-XmlChildText $node 'category') -Url (Get-XmlLink $node) -PublishedAt (Get-XmlChildText $node 'updated')))
    }
    return $items.ToArray()
}

function ConvertFrom-NewsFeed {
    param([string]$Content)
    if ([string]::IsNullOrWhiteSpace($Content)) { return @() }
    $trim = $Content.Trim()
    if ($trim.StartsWith('<')) {
        $xml = New-Object xml
        $xml.LoadXml($trim)
        return ConvertFrom-NewsXml $xml
    }
    $parsed = ConvertFrom-DesktopJson $trim
    return ConvertFrom-NewsJson $parsed
}

function Sort-Notices {
    param($Items)
    $list = @($Items | Where-Object { $null -ne $_ })
    if ($list.Count -eq 0) { return @() }
    return @($list | Sort-Object @{ Expression = { if ([string]$_.Kind -eq 'maintenance') { 0 } else { 1 } } }, @{ Expression = { [string]$_.PublishedAt }; Descending = $true })
}

function Get-NoticesToShow {
    param($Items, $SeenIds, [int]$Max = 3)
    if ($Max -lt 1) { $Max = 1 }
    $seen = @{}
    foreach ($id in @($SeenIds)) {
        $text = [string]$id
        if (-not [string]::IsNullOrWhiteSpace($text)) { $seen[$text] = $true }
    }
    $fresh = New-Object System.Collections.Generic.List[object]
    foreach ($item in @(Sort-Notices $Items)) {
        if ($null -eq $item) { continue }
        if ($seen.ContainsKey([string]$item.Id)) { continue }
        $fresh.Add($item)
        if ($fresh.Count -ge $Max) { break }
    }
    return $fresh.ToArray()
}

function Format-NoticeBalloon {
    param($Notices)
    $list = @($Notices | Where-Object { $null -ne $_ })
    if ($list.Count -eq 0) { return $null }
    $title = 'Новости'
    $lines = New-Object System.Collections.Generic.List[string]
    foreach ($item in $list) {
        if ([string]$item.Kind -eq 'maintenance') { $title = 'Технические работы' }
        $prefix = 'Новость: '
        if ([string]$item.Kind -eq 'maintenance') { $prefix = 'Работы: ' }
        $lines.Add($prefix + [string]$item.Title)
    }
    $text = [string]::Join("`n", $lines.ToArray())
    if ($text.Length -gt 220) { $text = $text.Substring(0, 217) + '...' }
    return [pscustomobject]@{ Title = $title; Text = $text }
}

function Get-WidgetHeadline {
    param($Items)
    $list = @(Sort-Notices $Items)
    if ($list.Count -eq 0) {
        return [pscustomobject]@{ Title = 'Пока нет сообщений'; Kind = 'none' }
    }
    return [pscustomobject]@{ Title = [string]$list[0].Title; Kind = [string]$list[0].Kind }
}

function ConvertTo-IdList {
    param($Value)
    $list = New-Object System.Collections.Generic.List[string]
    if ($null -eq $Value) { return ,$list }
    foreach ($id in @($Value)) {
        $text = [string]$id
        if (-not [string]::IsNullOrWhiteSpace($text)) { $list.Add($text.Trim()) }
    }
    return ,$list
}

function Test-TicketDraft {
    param([string]$Subject, [string]$Body)
    $errors = New-Object System.Collections.Generic.List[string]
    $theme = ''
    $text = ''
    if ($null -ne $Subject) { $theme = $Subject.Trim() }
    if ($null -ne $Body) { $text = $Body.Trim() }
    if ($theme.Length -lt 3) { $errors.Add('Укажите тему заявки, хотя бы 3 символа.') }
    if ($theme.Length -gt 200) { $errors.Add('Тема длиннее 200 символов.') }
    if ($text.Length -lt 5) { $errors.Add('Опишите заявку подробнее.') }
    if ($text.Length -gt 4000) { $errors.Add('Текст длиннее 4000 символов.') }
    return ,$errors
}

function Format-WindowsLogin {
    param([string]$IdentityName, [string]$Domain, [string]$User)
    if (-not [string]::IsNullOrWhiteSpace($IdentityName)) { return $IdentityName.Trim() }
    $account = ''
    $realm = ''
    if ($null -ne $User) { $account = $User.Trim() }
    if ($null -ne $Domain) { $realm = $Domain.Trim() }
    if (-not [string]::IsNullOrWhiteSpace($realm) -and -not [string]::IsNullOrWhiteSpace($account)) {
        return ('{0}\{1}' -f $realm, $account)
    }
    return $account
}

function Format-WindowsAccount {
    param([string]$Login)
    $value = ''
    if ($null -ne $Login) { $value = $Login.Trim() }
    if ([string]::IsNullOrWhiteSpace($value)) { return '' }
    $slash = $value.LastIndexOf('\')
    if ($slash -ge 0 -and $slash -lt ($value.Length - 1)) { return $value.Substring($slash + 1) }
    $at = $value.IndexOf('@')
    if ($at -gt 0) { return $value.Substring(0, $at) }
    return $value
}

function Get-WindowsSessionIdentity {
    $identityName = ''
    try {
        $current = [System.Security.Principal.WindowsIdentity]::GetCurrent()
        if ($null -ne $current) { $identityName = [string]$current.Name }
    } catch {
        $identityName = ''
    }
    $computer = [string]$env:COMPUTERNAME
    if ([string]::IsNullOrWhiteSpace($computer)) {
        try { $computer = [System.Net.Dns]::GetHostName() } catch { $computer = '' }
    }
    if ($null -eq $computer) { $computer = '' }
    return [pscustomobject]@{
        Login = Format-WindowsLogin -IdentityName $identityName -Domain ([string]$env:USERDOMAIN) -User ([string]$env:USERNAME)
        Computer = $computer.Trim()
    }
}

function Expand-ServiceDeskUrl {
    param([string]$Url, [string]$Login, [string]$Computer, [string]$Project, [string]$ProjectId)
    if ([string]::IsNullOrWhiteSpace($Url)) { return '' }
    $safeLogin = ''
    $safeComputer = ''
    $safeProject = ''
    $safeProjectId = ''
    if ($null -ne $Login) { $safeLogin = [Uri]::EscapeDataString($Login) }
    if ($null -ne $Computer) { $safeComputer = [Uri]::EscapeDataString($Computer) }
    if ($null -ne $Project) { $safeProject = [Uri]::EscapeDataString($Project) }
    if ($null -ne $ProjectId) { $safeProjectId = [Uri]::EscapeDataString($ProjectId) }
    return $Url.Replace('{login}', $safeLogin).Replace('{computer}', $safeComputer).Replace('{project}', $safeProject).Replace('{projectId}', $safeProjectId)
}

function New-TicketPayload {
    param(
        [string]$Subject,
        [string]$Body,
        [string]$Category,
        [string]$User,
        [string]$Computer,
        [string]$CreatedAt,
        [string]$Project,
        [string]$ProjectId
    )
    $userName = ''
    $pc = ''
    $projectName = ''
    $projectKey = ''
    if ($null -ne $User) { $userName = $User.Trim() }
    if ($null -ne $Computer) { $pc = $Computer.Trim() }
    if ($null -ne $Project) { $projectName = $Project.Trim() }
    if ($null -ne $ProjectId) { $projectKey = $ProjectId.Trim() }
    return [pscustomobject]@{
        subject = $Subject.Trim()
        body = $Body.Trim()
        category = $Category.Trim()
        project = $projectName
        projectId = $projectKey
        user = $userName
        computer = $pc
        createdAt = $CreatedAt
    }
}

function Get-JiraApiRoot {
    param([string]$BaseUrl)
    if ([string]::IsNullOrWhiteSpace($BaseUrl)) { return '' }
    return $BaseUrl.Trim().TrimEnd('/')
}

function Get-JiraNewsSearchUrl {
    param([string]$BaseUrl, [string]$Jql)
    $root = Get-JiraApiRoot $BaseUrl
    $query = ''
    if ($null -ne $Jql) { $query = $Jql.Trim() }
    if ([string]::IsNullOrWhiteSpace($root) -or [string]::IsNullOrWhiteSpace($query)) { return '' }
    $encoded = [Uri]::EscapeDataString($query)
    return ('{0}/rest/api/2/search?jql={1}&maxResults=10&fields=summary,description,updated,labels,issuetype' -f $root, $encoded)
}

function ConvertFrom-JiraNewsIssues {
    param($Page, [string]$BaseUrl)
    $items = New-Object System.Collections.Generic.List[object]
    $issues = Get-Prop $Page 'issues' $null
    $root = Get-JiraApiRoot $BaseUrl
    foreach ($issue in @($issues)) {
        if ($null -eq $issue) { continue }
        $key = ([string](Get-Prop $issue 'key' '')).Trim()
        if ([string]::IsNullOrWhiteSpace($key)) { continue }
        $fields = Get-Prop $issue 'fields' $null
        $summary = ([string](Get-Prop $fields 'summary' '')).Trim()
        $description = ''
        if ($null -ne $fields) {
            $descProp = $fields.PSObject.Properties['description']
            if ($null -ne $descProp -and $descProp.Value -is [string]) { $description = $descProp.Value }
        }
        if ($description.Length -gt 1000) { $description = $description.Substring(0, 1000) }
        $updated = [string](Get-Prop $fields 'updated' '')
        $kindParts = New-Object System.Collections.Generic.List[string]
        foreach ($label in @(Get-Prop $fields 'labels' $null)) {
            $name = ([string]$label).Trim()
            if (-not [string]::IsNullOrWhiteSpace($name)) { $kindParts.Add($name) }
        }
        $issueType = Get-Prop $fields 'issuetype' $null
        $typeName = ([string](Get-Prop $issueType 'name' '')).Trim()
        if (-not [string]::IsNullOrWhiteSpace($typeName)) { $kindParts.Add($typeName) }
        $url = ''
        if (-not [string]::IsNullOrWhiteSpace($root)) { $url = $root + '/browse/' + $key }
        $items.Add((New-Notice -Id $key -Title $summary -Body $description -Kind ($kindParts -join ' ') -Url $url -PublishedAt $updated))
    }
    return $items.ToArray()
}

function Get-JiraServiceDeskUrl {
    param([string]$BaseUrl, [int]$Start, [int]$Limit)
    $root = Get-JiraApiRoot $BaseUrl
    if ([string]::IsNullOrWhiteSpace($root)) { return '' }
    if ($Start -lt 0) { $Start = 0 }
    if ($Limit -lt 1) { $Limit = 50 }
    if ($Limit -gt 100) { $Limit = 100 }
    return ('{0}/rest/servicedeskapi/servicedesk?start={1}&limit={2}' -f $root, $Start, $Limit)
}

function Get-JiraRequestTypeUrl {
    param([string]$BaseUrl, [string]$ServiceDeskId, [int]$Start, [int]$Limit)
    $root = Get-JiraApiRoot $BaseUrl
    if ([string]::IsNullOrWhiteSpace($root) -or [string]::IsNullOrWhiteSpace($ServiceDeskId)) { return '' }
    if ($Start -lt 0) { $Start = 0 }
    if ($Limit -lt 1) { $Limit = 50 }
    if ($Limit -gt 100) { $Limit = 100 }
    $id = [Uri]::EscapeDataString($ServiceDeskId.Trim())
    return ('{0}/rest/servicedeskapi/servicedesk/{1}/requesttype?start={2}&limit={3}' -f $root, $id, $Start, $Limit)
}

function Get-JiraCreateRequestUrl {
    param([string]$BaseUrl)
    $root = Get-JiraApiRoot $BaseUrl
    if ([string]::IsNullOrWhiteSpace($root)) { return '' }
    return ($root + '/rest/servicedeskapi/request')
}

function Get-JiraPortalUrl {
    param([string]$BaseUrl, [string]$ExplicitUrl)
    if (-not [string]::IsNullOrWhiteSpace($ExplicitUrl)) { return $ExplicitUrl.Trim() }
    $root = Get-JiraApiRoot $BaseUrl
    if ([string]::IsNullOrWhiteSpace($root)) { return '' }
    return ($root + '/servicedesk/customer/portals')
}

function Get-JiraValueCount {
    param($Page)
    $values = Get-Prop $Page 'values' $null
    $count = 0
    foreach ($item in @($values)) {
        if ($null -ne $item) { $count++ }
    }
    return $count
}

function Get-JiraNextStart {
    param($Page, [int]$FallbackStart)
    if ($null -eq $Page) { return -1 }
    $lastProp = $Page.PSObject.Properties['isLastPage']
    if ($null -ne $lastProp -and (ConvertTo-Bool $lastProp.Value $true)) { return -1 }
    $size = 0
    $sizeProp = $Page.PSObject.Properties['size']
    if ($null -ne $sizeProp) { $size = ConvertTo-Int $sizeProp.Value 0 }
    if ($size -le 0) { $size = Get-JiraValueCount $Page }
    if ($size -le 0) { return -1 }
    $start = $FallbackStart
    $startProp = $Page.PSObject.Properties['start']
    if ($null -ne $startProp) { $start = ConvertTo-Int $startProp.Value $FallbackStart }
    return ($start + $size)
}

function ConvertFrom-JiraServiceDesks {
    param($Page)
    $items = New-Object System.Collections.Generic.List[object]
    $values = Get-Prop $Page 'values' $null
    foreach ($desk in @($values)) {
        if ($null -eq $desk) { continue }
        $id = ([string](Get-Prop $desk 'id' '')).Trim()
        if ([string]::IsNullOrWhiteSpace($id)) { continue }
        $items.Add([pscustomobject]@{
            Id = $id
            ProjectKey = ([string](Get-Prop $desk 'projectKey' '')).Trim()
            ProjectName = ([string](Get-Prop $desk 'projectName' '')).Trim()
            ProjectId = ([string](Get-Prop $desk 'projectId' '')).Trim()
        })
    }
    return ,$items.ToArray()
}

function ConvertFrom-JiraRequestTypes {
    param($Page)
    $items = New-Object System.Collections.Generic.List[object]
    $values = Get-Prop $Page 'values' $null
    foreach ($kind in @($values)) {
        if ($null -eq $kind) { continue }
        $id = ([string](Get-Prop $kind 'id' '')).Trim()
        if ([string]::IsNullOrWhiteSpace($id)) { continue }
        $items.Add([pscustomobject]@{
            Id = $id
            Name = ([string](Get-Prop $kind 'name' '')).Trim()
        })
    }
    return ,$items.ToArray()
}

function Format-JiraDeskLabel {
    param($Desk)
    if ($null -eq $Desk) { return '' }
    $name = ([string](Get-Prop $Desk 'ProjectName' '')).Trim()
    $key = ([string](Get-Prop $Desk 'ProjectKey' '')).Trim()
    $id = ([string](Get-Prop $Desk 'Id' '')).Trim()
    if ([string]::IsNullOrWhiteSpace($name)) { $name = $key }
    if ([string]::IsNullOrWhiteSpace($name)) { $name = $id }
    if (-not [string]::IsNullOrWhiteSpace($key) -and $name -ne $key) {
        return ('{0} ({1})' -f $name, $key)
    }
    return $name
}

function Format-JiraRequestDescription {
    param([string]$Description, [string]$User, [string]$Computer)
    $text = ''
    $userName = ''
    $pc = ''
    if ($null -ne $Description) { $text = $Description.Trim() }
    if ($null -ne $User) { $userName = $User.Trim() }
    if ($null -ne $Computer) { $pc = $Computer.Trim() }
    $parts = New-Object System.Collections.Generic.List[string]
    if (-not [string]::IsNullOrWhiteSpace($text)) { $parts.Add($text) }
    $tail = New-Object System.Collections.Generic.List[string]
    if (-not [string]::IsNullOrWhiteSpace($userName)) { $tail.Add(('Пользователь: {0}' -f $userName)) }
    if (-not [string]::IsNullOrWhiteSpace($pc)) { $tail.Add(('Компьютер: {0}' -f $pc)) }
    if ($tail.Count -gt 0) {
        if ($parts.Count -gt 0) { $parts.Add('') }
        foreach ($line in $tail) { $parts.Add($line) }
    }
    return ($parts -join "`n")
}

function New-JiraRequestPayload {
    param(
        [string]$ServiceDeskId,
        [string]$RequestTypeId,
        [string]$Summary,
        [string]$Description,
        [string]$User,
        [string]$Computer
    )
    $desk = ''
    $kind = ''
    $theme = ''
    if ($null -ne $ServiceDeskId) { $desk = $ServiceDeskId.Trim() }
    if ($null -ne $RequestTypeId) { $kind = $RequestTypeId.Trim() }
    if ($null -ne $Summary) { $theme = $Summary.Trim() }
    return [pscustomobject]@{
        serviceDeskId = $desk
        requestTypeId = $kind
        requestFieldValues = [pscustomobject]@{
            summary = $theme
            description = Format-JiraRequestDescription -Description $Description -User $User -Computer $Computer
        }
    }
}

function Get-JiraErrorText {
    param($Body)
    if ($null -eq $Body) { return '' }
    $parsed = $Body
    if ($Body -is [string]) {
        $raw = $Body.Trim()
        if ([string]::IsNullOrWhiteSpace($raw)) { return '' }
        try {
            $parsed = $raw | ConvertFrom-Json
        } catch {
            if ($raw.Length -gt 240) { return $raw.Substring(0, 240) }
            return $raw
        }
    }
    $message = ([string](Get-Prop $parsed 'errorMessage' '')).Trim()
    if (-not [string]::IsNullOrWhiteSpace($message)) { return $message }
    $parts = New-Object System.Collections.Generic.List[string]
    $messages = Get-Prop $parsed 'errorMessages' $null
    foreach ($item in @($messages)) {
        $line = ([string]$item).Trim()
        if (-not [string]::IsNullOrWhiteSpace($line)) { $parts.Add($line) }
    }
    $errors = Get-Prop $parsed 'errors' $null
    if ($null -ne $errors) {
        foreach ($prop in $errors.PSObject.Properties) {
            $line = ([string]$prop.Value).Trim()
            if (-not [string]::IsNullOrWhiteSpace($line)) {
                $parts.Add(('{0}: {1}' -f $prop.Name, $line))
            }
        }
    }
    if ($parts.Count -gt 0) {
        $joined = ($parts -join '; ')
        if ($joined.Length -gt 400) { return $joined.Substring(0, 400) }
        return $joined
    }
    $message = ([string](Get-Prop $parsed 'message' '')).Trim()
    if ($message.Length -gt 400) { return $message.Substring(0, 400) }
    return $message
}

function Get-JiraIssueKey {
    param($Body)
    if ($null -eq $Body) { return '' }
    $parsed = $Body
    if ($Body -is [string]) {
        if ([string]::IsNullOrWhiteSpace($Body)) { return '' }
        try { $parsed = $Body | ConvertFrom-Json } catch { return '' }
    }
    return ([string](Get-Prop $parsed 'issueKey' '')).Trim()
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

function Test-DesktopSwitchInstallDir {
    param([string]$Path)
    if ([string]::IsNullOrWhiteSpace($Path)) { return $false }
    $full = $Path.Trim()
    if ($full.StartsWith('\\') -or $full.StartsWith('//')) { return $false }
    if ($full -match '^[A-Za-z]:\\?$') { return $false }
    if ($full -eq '/' -or $full -eq '\') { return $false }
    return $true
}
