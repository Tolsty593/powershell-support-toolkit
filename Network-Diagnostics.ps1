<#
.SYNOPSIS
    Runs the common first-line network checks and suggests where the fault is.

.DESCRIPTION
    Works through the same steps a support engineer would follow by hand,
    from the machine outwards:

      1. Network adapter - is there an active adapter with an IPv4 address?
      2. Default gateway - does the local router answer?
      3. Internet        - do well-known public addresses answer a ping?
      4. DNS             - do host names resolve to addresses?
      5. TCP port        - can a connection be opened to a host and port?

    Each check is reported as PASS, WARN or FAIL, followed by a one-line
    assessment of the most likely cause.

    The script is read-only. It does not change any network settings.

.PARAMETER PingTarget
    Public IP addresses to ping. Default is 1.1.1.1 and 8.8.8.8.

.PARAMETER DnsName
    Host names to resolve. Default is www.microsoft.com.

.PARAMETER TcpHost
    The host to open a TCP connection to. Default is www.microsoft.com.

.PARAMETER TcpPort
    The TCP ports to test on TcpHost. Default is 443 (HTTPS).

.PARAMETER PingCount
    How many pings to send to each address. Default is 3.

.PARAMETER TimeoutMs
    How long to wait for each reply or connection, in milliseconds.
    Default is 2000.

.PARAMETER OutputPath
    Optional. Path of a text file to save the report to, for example
    C:\Temp\network.txt. The folder is created if it does not exist.

.PARAMETER PassThru
    Returns the individual check results as objects instead of a text report.

.EXAMPLE
    .\Network-Diagnostics.ps1

    Runs the standard checks and shows the report.

.EXAMPLE
    .\Network-Diagnostics.ps1 -DnsName intranet.contoso.com -TcpHost intranet.contoso.com -TcpPort 443, 3389

    Checks whether an internal host resolves and accepts connections on two ports.

.EXAMPLE
    .\Network-Diagnostics.ps1 -OutputPath C:\Temp\network.txt

    Runs the checks and saves a copy of the report to attach to a ticket.

.NOTES
    Requires Windows PowerShell 5.1 or PowerShell 7 on Windows 8.1,
    Windows Server 2012 R2 or later.
    Many company networks block ping to the internet. The assessment allows
    for this when the DNS and TCP checks pass.
#>
[CmdletBinding()]
param(
    [string[]]$PingTarget = @('1.1.1.1', '8.8.8.8'),

    [string[]]$DnsName = @('www.microsoft.com'),

    [string]$TcpHost = 'www.microsoft.com',

    [ValidateRange(1, 65535)]
    [int[]]$TcpPort = @(443),

    [ValidateRange(1, 10)]
    [int]$PingCount = 3,

    [ValidateRange(500, 10000)]
    [int]$TimeoutMs = 2000,

    [string]$OutputPath,

    [switch]$PassThru
)

function New-CheckResult {
    param([string]$Check, [string]$Target, [string]$Status, [string]$Detail)

    [pscustomobject]@{
        Check  = $Check
        Target = $Target
        Status = $Status
        Detail = $Detail
    }
}

function Test-Ping {
    # Uses the .NET Ping class so that it behaves the same in PowerShell 5.1 and 7.
    param([string]$Address, [int]$Count, [int]$Timeout)

    $times = @()
    $ping = New-Object -TypeName System.Net.NetworkInformation.Ping
    try {
        for ($i = 0; $i -lt $Count; $i++) {
            try {
                $reply = $ping.Send($Address, $Timeout)
                if ($reply.Status -eq [System.Net.NetworkInformation.IPStatus]::Success) {
                    $times += $reply.RoundtripTime
                }
            }
            catch {
                # A failed send counts as a lost reply.
            }
        }
    }
    finally {
        $ping.Dispose()
    }

    $average = $null
    if ($times.Count -gt 0) {
        $average = [int][math]::Round(($times | Measure-Object -Average).Average)
    }

    [pscustomobject]@{
        Sent      = $Count
        Received  = $times.Count
        AverageMs = $average
    }
}

function Test-TcpPort {
    param([string]$HostName, [int]$Port, [int]$Timeout)

    $client = New-Object -TypeName System.Net.Sockets.TcpClient
    try {
        $connect = $client.BeginConnect($HostName, $Port, $null, $null)
        if (-not $connect.AsyncWaitHandle.WaitOne($Timeout, $false)) {
            return $false
        }
        # EndConnect throws if the connection was refused.
        $client.EndConnect($connect)
        return $true
    }
    catch {
        return $false
    }
    finally {
        $client.Close()
    }
}

function Get-PingStatus {
    # Turns a ping result into a status and a readable detail line.
    param($Ping, [string]$NoReplyStatus = 'FAIL', [string]$NoReplyNote = '')

    if ($Ping.Received -eq 0) {
        $detail = "No reply ($($Ping.Sent) sent)"
        if ($NoReplyNote) { $detail = "$detail. $NoReplyNote" }
        return @{ Status = $NoReplyStatus; Detail = $detail }
    }

    $detail = "$($Ping.Received) of $($Ping.Sent) replies, average $($Ping.AverageMs) ms"
    if ($Ping.Received -lt $Ping.Sent) {
        return @{ Status = 'WARN'; Detail = "$detail (packet loss)" }
    }
    return @{ Status = 'PASS'; Detail = $detail }
}

$results = @()

# --- 1. Network adapter ------------------------------------------------------
$adapters = @()
try {
    $adapters = @(
        Get-NetIPConfiguration -ErrorAction Stop |
            Where-Object { $_.NetAdapter.Status -eq 'Up' -and $_.IPv4Address }
    )
}
catch {
    Write-Warning "Could not read the network adapter configuration: $($_.Exception.Message)"
}

$gateways = @()
$selfAssigned = $false

if ($adapters.Count -eq 0) {
    $results += New-CheckResult -Check 'Adapter' -Target '-' -Status 'FAIL' -Detail 'No active network adapter with an IPv4 address'
}

foreach ($adapter in $adapters) {
    # Where-Object { $_ } drops empty values, for example when no gateway is set.
    $addresses = @($adapter.IPv4Address | ForEach-Object { $_.IPAddress } | Where-Object { $_ })
    $gateway   = @($adapter.IPv4DefaultGateway | ForEach-Object { $_.NextHop } | Where-Object { $_ })
    # AddressFamily 2 is IPv4.
    $dnsServers = @($adapter.DNSServer | Where-Object { $_.AddressFamily -eq 2 } | ForEach-Object { $_.ServerAddresses } | Where-Object { $_ })

    $gateways += $gateway

    $status = 'PASS'
    $detail = "IP $($addresses -join ', ')"
    if ($gateway.Count -gt 0) { $detail = "$detail; gateway $($gateway -join ', ')" }
    if ($dnsServers.Count -gt 0) { $detail = "$detail; DNS $($dnsServers -join ', ')" }

    # A 169.254.x.x address means Windows assigned one itself because DHCP did not answer.
    if (@($addresses | Where-Object { $_ -like '169.254.*' }).Count -gt 0) {
        $status = 'WARN'
        $detail = "$detail (self-assigned address, DHCP did not answer)"
        $selfAssigned = $true
    }

    $results += New-CheckResult -Check 'Adapter' -Target $adapter.InterfaceAlias -Status $status -Detail $detail
}

# --- 2. Default gateway ------------------------------------------------------
$gateways = @($gateways | Where-Object { $_ } | Sort-Object -Unique)

if ($adapters.Count -gt 0 -and $gateways.Count -eq 0) {
    $results += New-CheckResult -Check 'Gateway' -Target '-' -Status 'FAIL' -Detail 'No default gateway is configured'
}

foreach ($gateway in $gateways) {
    $ping = Test-Ping -Address $gateway -Count $PingCount -Timeout $TimeoutMs
    $outcome = Get-PingStatus -Ping $ping -NoReplyStatus 'WARN' -NoReplyNote 'Some routers do not answer ping'
    $results += New-CheckResult -Check 'Gateway' -Target $gateway -Status $outcome.Status -Detail $outcome.Detail
}

# --- 3. Internet by IP address -----------------------------------------------
foreach ($target in $PingTarget) {
    $ping = Test-Ping -Address $target -Count $PingCount -Timeout $TimeoutMs
    $outcome = Get-PingStatus -Ping $ping
    $results += New-CheckResult -Check 'Internet ping' -Target $target -Status $outcome.Status -Detail $outcome.Detail
}

# --- 4. DNS ------------------------------------------------------------------
foreach ($name in $DnsName) {
    try {
        $resolved = @([System.Net.Dns]::GetHostAddresses($name) | ForEach-Object { $_.IPAddressToString })
        $shown = @($resolved | Select-Object -First 3)
        $results += New-CheckResult -Check 'DNS' -Target $name -Status 'PASS' -Detail "Resolved to $($shown -join ', ')"
    }
    catch {
        $results += New-CheckResult -Check 'DNS' -Target $name -Status 'FAIL' -Detail 'Name did not resolve'
    }
}

# --- 5. TCP port -------------------------------------------------------------
foreach ($port in $TcpPort) {
    $target = "${TcpHost}:$port"
    if (Test-TcpPort -HostName $TcpHost -Port $port -Timeout $TimeoutMs) {
        $results += New-CheckResult -Check 'TCP port' -Target $target -Status 'PASS' -Detail 'Connection opened'
    }
    else {
        $results += New-CheckResult -Check 'TCP port' -Target $target -Status 'FAIL' -Detail 'Could not connect'
    }
}

if ($PassThru) {
    return $results
}

# --- Assessment --------------------------------------------------------------
# A check group is "ok" when at least one of its results did not fail.
function Test-Group {
    param([string]$Check, [string[]]$Accept)
    @($results | Where-Object { $_.Check -eq $Check -and $Accept -contains $_.Status }).Count -gt 0
}

$adapterOk  = Test-Group -Check 'Adapter' -Accept 'PASS', 'WARN'
$gatewayOk  = Test-Group -Check 'Gateway' -Accept 'PASS'
$internetOk = Test-Group -Check 'Internet ping' -Accept 'PASS', 'WARN'
$dnsOk      = Test-Group -Check 'DNS' -Accept 'PASS'
$tcpOk      = Test-Group -Check 'TCP port' -Accept 'PASS'

$anythingReachable = $internetOk -or $dnsOk -or $tcpOk

if (-not $adapterOk -and -not $anythingReachable) {
    $assessment = 'No active network connection. Check the cable or Wi-Fi, and that the adapter is enabled.'
}
elseif ($selfAssigned -and -not $anythingReachable) {
    $assessment = 'The adapter has a self-assigned 169.254.x.x address, so no DHCP server answered. Check the connection to the router or switch, then renew the address.'
}
elseif ($dnsOk -and $tcpOk -and $internetOk) {
    if (@($results | Where-Object { $_.Status -eq 'FAIL' }).Count -eq 0) {
        $assessment = 'All checks passed. Basic connectivity is healthy, so look at the specific application or service.'
    }
    else {
        $assessment = 'Basic connectivity is working, but at least one individual check failed. See the FAIL lines above.'
    }
}
elseif ($dnsOk -and $tcpOk) {
    $assessment = 'Connectivity is working. Ping to the internet failed, which usually means ping is blocked by a firewall.'
}
elseif ($dnsOk) {
    $assessment = "Names resolve, but the connection to $TcpHost failed. A firewall or proxy may be blocking the port, or the service may be down."
}
elseif ($internetOk) {
    $assessment = 'The internet is reachable by IP address but names do not resolve. This points to DNS: check the DNS servers shown for the adapter.'
}
elseif ($gatewayOk) {
    $assessment = 'The local network is working, but nothing beyond the gateway answers. This points to the router, the internet provider or a firewall.'
}
else {
    $assessment = 'The default gateway does not answer and nothing beyond it is reachable. This points to the local network: Wi-Fi, cable, switch or router.'
}

$report = @()
$report += "NETWORK DIAGNOSTICS: $env:COMPUTERNAME"
$report += "Run at: $((Get-Date).ToString('yyyy-MM-dd HH:mm'))"
$report += ''
$report += ($results | Format-Table -AutoSize -Wrap | Out-String -Width 200).Trim()
$report += ''
$report += "Assessment: $assessment"

$text = $report -join [Environment]::NewLine
$text

if ($OutputPath) {
    $folder = Split-Path -Path $OutputPath -Parent
    if ($folder -and -not (Test-Path -Path $folder)) {
        New-Item -Path $folder -ItemType Directory -Force | Out-Null
    }
    Set-Content -Path $OutputPath -Value $text -Encoding UTF8
    Write-Host "Report saved to $OutputPath"
}
