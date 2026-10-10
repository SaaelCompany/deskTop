# Decision tests for DesktopSwitch. Run from any OS:
#   pwsh -NoProfile -File tests/Decision.Tests.ps1

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

$env:USERPROFILE = 'C:\Users\TestUser'
$env:LOCALAPPDATA = 'C:\Users\TestUser\AppData\Local'

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

function Assert-Contains {
    param([string]$Name, [string]$Text, [string]$Fragment)
    if ([string]$Text -notlike ('*' + $Fragment + '*')) {
        Write-Host ("FAIL {0}: [{1}] does not contain [{2}]" -f $Name, $Text, $Fragment)
        $script:Failed++
    } else {
        Write-Host ("ok   {0}" -f $Name)
    }
}

function Decide {
    param(
        [string]$Verdict,
        [string]$Mode,
        [int]$Fail = 0,
        [int]$Ok = 0,
        [int]$FailN = 2,
        [int]$OkN = 3,
        [bool]$Restore = $true
    )
    Update-SwitchDecision -Verdict $Verdict -Mode $Mode -FailureStreak $Fail -SuccessStreak $Ok -FailuresBeforeSwitch $FailN -SuccessesBeforeRestore $OkN -RestoreWhenOnline:$Restore
}

$first = Decide -Verdict 'Offline' -Mode 'Network'
Assert-Equal 'first outage waits' $first.Action 'WaitOffline'
Assert-Equal 'first outage keeps network' $first.Mode 'Network'
Assert-Equal 'first outage streak' $first.FailureStreak 1

$second = Decide -Verdict 'Offline' -Mode 'Network' -Fail $first.FailureStreak
Assert-Equal 'second outage switches' $second.Action 'SwitchToLocal'
Assert-Equal 'second outage mode' $second.Mode 'Local'
Assert-Equal 'second outage streak' $second.FailureStreak 2

$immediate = Decide -Verdict 'Offline' -Mode 'Network' -FailN 1
Assert-Equal 'threshold 1 switches immediately' $immediate.Action 'SwitchToLocal'

$held = Decide -Verdict 'Offline' -Mode 'Local' -Ok 2
Assert-Equal 'offline local reasserts' $held.Action 'ReassertLocal'
Assert-Equal 'offline local resets success' $held.SuccessStreak 0
Assert-Equal 'offline local counts failure' $held.FailureStreak 1

$back1 = Decide -Verdict 'Online' -Mode 'Local'
Assert-Equal 'first recovery waits' $back1.Action 'WaitOnline'
Assert-Equal 'first recovery stays local' $back1.Mode 'Local'
Assert-Equal 'first recovery success' $back1.SuccessStreak 1

$back2 = Decide -Verdict 'Online' -Mode 'Local' -Ok 1
Assert-Equal 'second recovery waits' $back2.Action 'WaitOnline'
$back3 = Decide -Verdict 'Online' -Mode 'Local' -Ok 2
Assert-Equal 'third recovery restores' $back3.Action 'SwitchToNetwork'
Assert-Equal 'third recovery mode' $back3.Mode 'Network'

$stay = Decide -Verdict 'Online' -Mode 'Network' -Fail 1
Assert-Equal 'online network stays' $stay.Action 'StayNetwork'
Assert-Equal 'online network clears failures' $stay.FailureStreak 0
Assert-Equal 'online network counts success' $stay.SuccessStreak 1

$unknown = Decide -Verdict 'Unknown' -Mode 'Network' -Fail 1 -Ok 2
Assert-Equal 'unknown holds mode' $unknown.Action 'Hold'
Assert-Equal 'unknown keeps mode' $unknown.Mode 'Network'
Assert-Equal 'unknown clears failures' $unknown.FailureStreak 0
Assert-Equal 'unknown clears success' $unknown.SuccessStreak 0

$noRestore = Decide -Verdict 'Online' -Mode 'Local' -Ok 5 -Restore $false
Assert-Equal 'restore disabled stays local' $noRestore.Action 'WaitOnline'
Assert-Equal 'restore disabled mode' $noRestore.Mode 'Local'

$capped = Decide -Verdict 'Offline' -Mode 'Local' -Fail 1000
Assert-Equal 'failure streak cap' $capped.FailureStreak 1000
Assert-Equal 'capped streak still reasserts' $capped.Action 'ReassertLocal'

Assert-Equal 'internet up ignores dead share' (Get-ConnectivityVerdict -Trigger 'Internet' -Internet 'Up' -Share 'Down') 'Online'
Assert-Equal 'internet down is offline' (Get-ConnectivityVerdict -Trigger 'Internet' -Internet 'Down' -Share 'Up') 'Offline'
Assert-Equal 'internet unknown holds' (Get-ConnectivityVerdict -Trigger 'Internet' -Internet 'Unknown' -Share 'Down') 'Unknown'
Assert-Equal 'share up ignores dead internet' (Get-ConnectivityVerdict -Trigger 'Share' -Internet 'Down' -Share 'Up') 'Online'
Assert-Equal 'share down is offline' (Get-ConnectivityVerdict -Trigger 'Share' -Internet 'Up' -Share 'Down') 'Offline'
Assert-Equal 'share unknown holds' (Get-ConnectivityVerdict -Trigger 'Share' -Internet 'Up' -Share 'Unknown') 'Unknown'
Assert-Equal 'either internet down' (Get-ConnectivityVerdict -Trigger 'InternetOrShare' -Internet 'Down' -Share 'Up') 'Offline'
Assert-Equal 'either share down' (Get-ConnectivityVerdict -Trigger 'InternetOrShare' -Internet 'Up' -Share 'Down') 'Offline'
Assert-Equal 'either both up' (Get-ConnectivityVerdict -Trigger 'InternetOrShare' -Internet 'Up' -Share 'Up') 'Online'
Assert-Equal 'either internet unknown share up' (Get-ConnectivityVerdict -Trigger 'InternetOrShare' -Internet 'Unknown' -Share 'Up') 'Unknown'
Assert-Equal 'either both unknown' (Get-ConnectivityVerdict -Trigger 'InternetOrShare' -Internet 'Unknown' -Share 'Unknown') 'Unknown'

Assert-Equal 'reason both' (Get-OfflineReasonCode -Internet 'Down' -Share 'Down') 'Both'
Assert-Equal 'reason internet' (Get-OfflineReasonCode -Internet 'Down' -Share 'Up') 'Internet'
Assert-Equal 'reason share' (Get-OfflineReasonCode -Internet 'Up' -Share 'Down') 'Share'
Assert-Equal 'reason none' (Get-OfflineReasonCode -Internet 'Up' -Share 'Up') 'None'

$localMessage = Get-SwitchMessage -Action 'SwitchToLocal' -ReasonCode 'Internet'
Assert-Contains 'local message' $localMessage 'локальный'
Assert-Contains 'local message keeps files' $localMessage 'останутся'
$networkMessage = Get-SwitchMessage -Action 'SwitchToNetwork' -ReasonCode 'None'
Assert-Contains 'network message' $networkMessage 'сетевой'
Assert-Equal 'hold has no message' (Get-SwitchMessage -Action 'Hold' -ReasonCode 'None') ''

Assert-Equal 'windows internet wins' (Resolve-InternetStatus -WindowsInternet $true -ProbeSucceeded $false) 'Up'
Assert-Equal 'probe overrides false windows status' (Resolve-InternetStatus -WindowsInternet $false -ProbeSucceeded $true) 'Up'
Assert-Equal 'windows false without probe is down' (Resolve-InternetStatus -WindowsInternet $false -ProbeSucceeded $null) 'Down'
Assert-Equal 'probe false alone is down' (Resolve-InternetStatus -WindowsInternet $null -ProbeSucceeded $false) 'Down'
Assert-Equal 'no signals is unknown' (Resolve-InternetStatus -WindowsInternet $null -ProbeSucceeded $null) 'Unknown'
Assert-Equal 'empty probes are unknown' (Resolve-ProbeAggregate -Results @()) $null
Assert-Equal 'any probe success' (Resolve-ProbeAggregate -Results @($false, $true)) $true
Assert-Equal 'all probes fail' (Resolve-ProbeAggregate -Results @($false, $false)) $false

Assert-True 'unc share' (Test-UncPathString '\\server\share\Desktop')
Assert-True 'unc without subfolder' (Test-UncPathString '\\server\share')
Assert-True 'drive path is not unc' (-not (Test-UncPathString 'C:\Users\Desktop'))
Assert-True 'server only is not unc' (-not (Test-UncPathString '\\server'))
Assert-Equal 'unc host' (Get-UncHost '\\fs01\Desktop\Common') 'fs01'
Assert-True 'example marker' (Test-ExampleNetworkPath '\\CHANGE-ME\DesktopShare\Desktop')
Assert-True 'real server is not example' (-not (Test-ExampleNetworkPath '\\fileserver\Desktop\Common'))
Assert-True 'path case and slash' (Compare-DesktopPath 'C:\Users\A\Desktop\' 'c:\users\a\desktop')
Assert-True 'unc case and slash' (Compare-DesktopPath '\\FS\Share\Desktop' '\\fs\share\desktop\')
Assert-True 'different paths' (-not (Compare-DesktopPath 'C:\A' 'C:\B'))

Assert-Equal 'mode local' (Get-DesktopModeFromPath -CurrentPath 'C:\Cache' -NetworkPath '\\fs\share\Desktop' -LocalPath 'C:\Cache') 'Local'
Assert-Equal 'mode network exact' (Get-DesktopModeFromPath -CurrentPath '\\fs\share\Desktop' -NetworkPath '\\fs\share\Desktop' -LocalPath 'C:\Cache') 'Network'
Assert-Equal 'mode other unc' (Get-DesktopModeFromPath -CurrentPath '\\other\share\Desk' -NetworkPath '\\fs\share\Desktop' -LocalPath 'C:\Cache') 'Network'
Assert-Equal 'mode other local' (Get-DesktopModeFromPath -CurrentPath 'D:\Desk' -NetworkPath '\\fs\share\Desktop' -LocalPath 'C:\Cache') 'Local'
Assert-Equal 'mode empty' (Get-DesktopModeFromPath -CurrentPath '' -NetworkPath '\\fs\share\Desktop' -LocalPath 'C:\Cache') 'Network'

Assert-Equal 'configured path wins' (Resolve-NetworkPathValue -Configured '\\fs\share\Desktop' -Learned '\\old\share' -Current '\\current\share') '\\fs\share\Desktop'
Assert-Equal 'live policy path wins' (Resolve-NetworkPathValue -Configured '' -Learned '\\old\share\Desktop' -Current '\\current\share\Desktop') '\\current\share\Desktop'
Assert-Equal 'learned path while local' (Resolve-NetworkPathValue -Configured '' -Learned '\\old\share\Desktop' -Current 'C:\Users\Desktop') '\\old\share\Desktop'
Assert-Equal 'current unc last' (Resolve-NetworkPathValue -Configured 'not-a-path' -Learned '' -Current '\\current\share\Desktop') '\\current\share\Desktop'
Assert-Equal 'nothing found' (Resolve-NetworkPathValue -Configured '' -Learned '' -Current 'C:\Users\Desktop') ''

Assert-True 'switch local when different' (Test-DesktopChangeNeeded -Action 'SwitchToLocal' -CurrentPath '\\fs\share\Desktop' -LocalPath 'C:\Cache' -NetworkPath '\\fs\share\Desktop')
Assert-True 'switch local skipped when already there' (-not (Test-DesktopChangeNeeded -Action 'SwitchToLocal' -CurrentPath 'C:\Cache' -LocalPath 'C:\Cache\' -NetworkPath '\\fs\share\Desktop'))
Assert-True 'reassert when policy restored unc' (Test-DesktopChangeNeeded -Action 'ReassertLocal' -CurrentPath '\\fs\share\Desktop' -LocalPath 'C:\Cache' -NetworkPath '\\fs\share\Desktop')
Assert-True 'reassert skipped when local holds' (-not (Test-DesktopChangeNeeded -Action 'ReassertLocal' -CurrentPath 'C:\Cache' -LocalPath 'C:\Cache' -NetworkPath '\\fs\share\Desktop'))
Assert-True 'stay does not rewrite' (-not (Test-DesktopChangeNeeded -Action 'StayNetwork' -CurrentPath 'C:\Cache' -LocalPath 'C:\Cache' -NetworkPath '\\fs\share\Desktop'))
Assert-True 'restore when different' (Test-DesktopChangeNeeded -Action 'SwitchToNetwork' -CurrentPath 'C:\Cache' -LocalPath 'C:\Cache' -NetworkPath '\\fs\share\Desktop')
Assert-Equal 'target local' (Get-ActionTargetPath -Action 'SwitchToLocal' -LocalPath 'C:\Cache' -NetworkPath '\\fs\share') 'C:\Cache'
Assert-Equal 'target network' (Get-ActionTargetPath -Action 'SwitchToNetwork' -LocalPath 'C:\Cache' -NetworkPath '\\fs\share') '\\fs\share'
Assert-Equal 'target empty while waiting' (Get-ActionTargetPath -Action 'WaitOffline' -LocalPath 'C:\Cache' -NetworkPath '\\fs\share') ''

Assert-True 'sync when share is up' (Test-ShouldSyncShortcuts -SyncEnabled $true -ShareStatus 'Up')
Assert-True 'no sync when share is down' (-not (Test-ShouldSyncShortcuts -SyncEnabled $true -ShareStatus 'Down'))
Assert-True 'no sync when disabled' (-not (Test-ShouldSyncShortcuts -SyncEnabled $false -ShareStatus 'Up'))

$reparse = [int][System.IO.FileAttributes]::ReparsePoint
$directory = [int][System.IO.FileAttributes]::Directory
Assert-True 'reparse attribute' (Test-ReparseAttribute -Attributes ($reparse -bor $directory))
Assert-True 'plain directory' (-not (Test-ReparseAttribute -Attributes $directory))

$now = [datetime]::Parse('2026-10-10T12:00:00')
Assert-True 'empty cooldown elapsed' (Test-CooldownElapsed -Stamp '' -Now $now -CooldownSeconds 120)
Assert-True 'fresh restart blocked' (-not (Test-CooldownElapsed -Stamp '2026-10-10T11:59:00' -Now $now -CooldownSeconds 120))
Assert-True 'old restart allowed' (Test-CooldownElapsed -Stamp '2026-10-10T11:57:00' -Now $now -CooldownSeconds 120)
Assert-True 'bad stamp allowed' (Test-CooldownElapsed -Stamp 'not-a-date' -Now $now -CooldownSeconds 120)

Assert-Equal 'interval floor' (Get-ClampedInterval 1) 5
Assert-Equal 'interval ceiling' (Get-ClampedInterval 99999) 3600
Assert-Equal 'interval kept' (Get-ClampedInterval 15) 15
Assert-Equal 'count floor' (Get-ClampedCount 0) 1
Assert-Equal 'timeout ceiling' (Get-ClampedTimeout 100) 30
Assert-Equal 'log floor' (Get-ClampedLogBytes 10) 65536

$probes = Select-HttpProbeUrl -Urls @('http://example.test/a', 'ftp://example.test/b', 'not a url', 'https://intranet.example/health')
Assert-Equal 'http probe kept' $probes.Count 2
Assert-Equal 'first probe' $probes[0] 'http://example.test/a'

$defaults = Get-EffectiveDesktopConfig ([pscustomobject]@{})
Assert-Equal 'default disabled' $defaults.Enabled $false
Assert-Equal 'default trigger' $defaults.Trigger 'InternetOrShare'
Assert-Equal 'default interval' $defaults.CheckIntervalSeconds 15
Assert-Equal 'default failures' $defaults.FailuresBeforeSwitch 2
Assert-Equal 'default successes' $defaults.SuccessesBeforeRestore 3
Assert-Equal 'default local' $defaults.LocalDesktopPath 'C:\Users\TestUser\AppData\Local\DesktopSwitch\LocalDesktop'
Assert-Equal 'default probe count' @($defaults.ProbeUrls).Count 1
Assert-Equal 'default probe body' $defaults.ExpectedProbeBody 'Microsoft Connect Test'
Assert-Equal 'default extensions' (@($defaults.SyncExtensions) -join ',') '.lnk,.url'

$custom = Get-EffectiveDesktopConfig ([pscustomobject]@{
    Enabled = 'true'
    Trigger = 'internet'
    CheckIntervalSeconds = 1
    InternetCheck = [pscustomobject]@{
        UseWindowsConnectivity = $false
        ProbeUrls = @('https://intranet.example/health')
        ProbeTimeoutSeconds = 0
    }
    SyncExtensions = @()
})
Assert-Equal 'string enabled' $custom.Enabled $true
Assert-Equal 'trigger case' $custom.Trigger 'Internet'
Assert-Equal 'clamped interval via config' $custom.CheckIntervalSeconds 5
Assert-Equal 'custom probe' @($custom.ProbeUrls)[0] 'https://intranet.example/health'
Assert-Equal 'custom probe has no expected body' $custom.ExpectedProbeBody ''
Assert-Equal 'windows check disabled' $custom.UseWindowsConnectivity $false
Assert-Equal 'empty extension list' @($custom.SyncExtensions).Count 0
$emptyProp = Get-Prop ([pscustomobject]@{ SyncExtensions = @() }) 'SyncExtensions' $null
Assert-True 'empty property preserved' (($null -ne $emptyProp) -and (@($emptyProp).Count -eq 0))
Assert-Equal 'probe timeout floor' $custom.ProbeTimeoutSeconds 1

$badTrigger = $false
try { Get-EffectiveDesktopConfig ([pscustomobject]@{ Trigger = 'wifi' }) | Out-Null } catch { $badTrigger = $true }
Assert-True 'bad trigger throws' $badTrigger

$root = Split-Path $PSScriptRoot -Parent
$example = Get-Content -LiteralPath (Join-Path $root 'config.example.json') -Raw -Encoding UTF8 | ConvertFrom-Json
$exampleConfig = Get-EffectiveDesktopConfig $example
Assert-Equal 'example stays disabled' $exampleConfig.Enabled $false
Assert-Equal 'example follows policy' $exampleConfig.NetworkDesktopPath ''
Assert-Equal 'example widget on' $exampleConfig.WidgetEnabled $true
$exampleErrors = Get-DesktopConfigErrors -NetworkPath $exampleConfig.NetworkDesktopPath -LocalPath $exampleConfig.LocalDesktopPath -AllowEmptyNetwork
Assert-Equal 'example has no path error' $exampleErrors.Count 0
$placeholderErrors = Get-DesktopConfigErrors -NetworkPath '\\CHANGE-ME\DesktopShare\Desktop' -LocalPath $exampleConfig.LocalDesktopPath
Assert-Contains 'placeholder still rejected' ([string]::Join("`n", @($placeholderErrors))) 'CHANGE-ME'

$validErrors = Get-DesktopConfigErrors -NetworkPath '\\fs01\Desktop\Common' -LocalPath 'C:\Users\TestUser\AppData\Local\DesktopSwitch\LocalDesktop'
Assert-Equal 'valid pair' $validErrors.Count 0
$rootErrors = Get-DesktopConfigErrors -NetworkPath '\\fs01\Desktop\Common' -LocalPath 'C:\'
Assert-Contains 'drive root rejected' ([string]::Join("`n", @($rootErrors))) 'корнем'
$sameErrors = Get-DesktopConfigErrors -NetworkPath '\\fs01\Desktop\Common' -LocalPath '\\fs01\Desktop\Common'
$sameText = [string]::Join("`n", @($sameErrors))
Assert-Contains 'unc local rejected' $sameText 'локальном'
Assert-Contains 'same path rejected' $sameText 'различаться'
$emptyErrors = Get-DesktopConfigErrors -NetworkPath '' -LocalPath 'C:\Cache' -AllowEmptyNetwork
Assert-Equal 'empty network allowed' $emptyErrors.Count 0
$emptyDenied = Get-DesktopConfigErrors -NetworkPath '' -LocalPath 'C:\Cache'
Assert-Contains 'empty network explained' ([string]::Join("`n", @($emptyDenied))) 'NetworkDesktopPath'

$feedJson = @'
{"items":[
  {"id":"n1","title":"Новый принтер","body":"На 3 этаже","kind":"news","publishedAt":"2026-10-01T10:00:00","url":"https://intranet.example/n1"},
  {"id":"m1","title":"Окно обслуживания","body":"Сервер с 22:00","kind":"maintenance","publishedAt":"2026-10-10T09:00:00"}
]}
'@
$feed = @(Sort-Notices (ConvertFrom-NewsFeed $feedJson))
Assert-Equal 'feed count' $feed.Count 2
Assert-Equal 'maintenance sorted first' $feed[0].Kind 'maintenance'
Assert-Equal 'headline is maintenance' (Get-WidgetHeadline $feed).Kind 'maintenance'
$unseen = @(Get-NoticesToShow -Items $feed -SeenIds @('n1') -Max 3)
Assert-Equal 'seen news hidden' $unseen.Count 1
Assert-Equal 'maintenance still shown' $unseen[0].Id 'm1'
$balloon = Format-NoticeBalloon $unseen
Assert-Equal 'maintenance balloon' $balloon.Title 'Технические работы'
Assert-Contains 'balloon text' $balloon.Text 'Окно обслуживания'
$rss = @'
<?xml version="1.0"?>
<rss version="2.0"><channel><item>
  <title>Плановые работы</title>
  <description>&lt;p&gt;Сеть с 22:00&lt;/p&gt;</description>
  <link>https://intranet.example/rss1</link>
  <guid>rss-1</guid>
  <category>maintenance</category>
  <pubDate>Fri, 10 Oct 2026 09:00:00 GMT</pubDate>
</item></channel></rss>
'@
$rssItems = @(ConvertFrom-NewsFeed $rss)
Assert-Equal 'rss count' $rssItems.Count 1
Assert-Equal 'rss kind' $rssItems[0].Kind 'maintenance'
Assert-Equal 'rss id' $rssItems[0].Id 'rss-1'
Assert-Contains 'rss body without tags' $rssItems[0].Body 'Сеть с 22:00'
$ticketErrors = Test-TicketDraft -Subject 'ab' -Body '1234'
Assert-True 'short ticket rejected' ($ticketErrors.Count -ge 2)
$validTicket = Test-TicketDraft -Subject 'Не печатает' -Body 'Принтер на третьем этаже'
Assert-Equal 'valid ticket' $validTicket.Count 0
$payload = New-TicketPayload -Subject ' Не печатает ' -Body 'Принтер молчит' -Category 'Инцидент' -User ' CONTOSO\ivan ' -Computer ' PC-1 ' -CreatedAt '2026-10-10T12:00:00'
Assert-Equal 'ticket subject trimmed' $payload.subject 'Не печатает'
Assert-Equal 'ticket user' $payload.user 'CONTOSO\ivan'
Assert-Equal 'ticket computer' $payload.computer 'PC-1'
Assert-Equal 'domain login from identity' (Format-WindowsLogin -IdentityName 'CONTOSO\ivan' -Domain 'OTHER' -User 'other') 'CONTOSO\ivan'
Assert-Equal 'domain login from environment' (Format-WindowsLogin -IdentityName '' -Domain 'CONTOSO' -User 'ivan') 'CONTOSO\ivan'
Assert-Equal 'local login fallback' (Format-WindowsLogin -IdentityName '' -Domain '' -User 'ivan') 'ivan'
$deskUrl = Expand-ServiceDeskUrl -Url 'https://sd.example/new?user={login}&pc={computer}' -Login 'CONTOSO\ivan' -Computer 'PC-1'
Assert-Equal 'portal placeholders' $deskUrl 'https://sd.example/new?user=CONTOSO%5Civan&pc=PC-1'
$savedUser = $env:USERNAME
$savedDomain = $env:USERDOMAIN
$savedComputer = $env:COMPUTERNAME
try {
    $env:USERNAME = 'ivan'
    $env:USERDOMAIN = 'CONTOSO'
    $env:COMPUTERNAME = 'PC-1'
    $session = Get-WindowsSessionIdentity
} finally {
    if ($null -eq $savedUser) { Remove-Item Env:USERNAME -ErrorAction SilentlyContinue } else { $env:USERNAME = $savedUser }
    if ($null -eq $savedDomain) { Remove-Item Env:USERDOMAIN -ErrorAction SilentlyContinue } else { $env:USERDOMAIN = $savedDomain }
    if ($null -eq $savedComputer) { Remove-Item Env:COMPUTERNAME -ErrorAction SilentlyContinue } else { $env:COMPUTERNAME = $savedComputer }
}
Assert-True 'session has login' (-not [string]::IsNullOrWhiteSpace([string]$session.Login))
Assert-True 'session has computer' (-not [string]::IsNullOrWhiteSpace([string]$session.Computer))
if ([string]$session.Login -eq 'CONTOSO\ivan') {
    Assert-Equal 'session computer from environment' $session.Computer 'PC-1'
}
$widgetCfg = Get-EffectiveDesktopConfig ([pscustomobject]@{
    Widget = [pscustomobject]@{
        ServiceDeskUrl = 'not a url'
        NewsUrl = 'https://intranet.example/news.json'
        NewsPollMinutes = 0
        Corner = 'nope'
        Enabled = $false
    }
})
Assert-Equal 'bad portal dropped' $widgetCfg.ServiceDeskUrl ''
Assert-Equal 'news url kept' $widgetCfg.NewsUrl 'https://intranet.example/news.json'
Assert-Equal 'poll floor' $widgetCfg.NewsPollMinutes 1
Assert-Equal 'corner fallback' $widgetCfg.WidgetCorner 'BottomRight'
Assert-Equal 'widget can be disabled' $widgetCfg.WidgetEnabled $false

foreach ($name in @('DesktopSwitch.Logic.ps1', 'DesktopSwitch.ps1', 'DesktopSwitch.Widget.ps1', 'Install-DesktopSwitch.ps1', 'Uninstall-DesktopSwitch.ps1')) {
    $path = Join-Path $root $name
    $tokens = $null
    $parseErrors = $null
    [void][System.Management.Automation.Language.Parser]::ParseFile($path, [ref]$tokens, [ref]$parseErrors)
    if ($parseErrors -and @($parseErrors).Count -gt 0) {
        Write-Host ("FAIL parse {0}" -f $name)
        foreach ($parseError in @($parseErrors)) { Write-Host $parseError.ToString() }
        $script:Failed++
    } else {
        Write-Host ("ok   parse {0}" -f $name)
    }
}

if ($script:Failed -gt 0) {
    Write-Host ("{0} test(s) failed" -f $script:Failed)
    exit 1
}
Write-Host 'All tests passed.'
exit 0
