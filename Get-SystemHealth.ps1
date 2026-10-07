<#
.SYNOPSIS
    Collects a quick health snapshot of the local Windows machine.

.DESCRIPTION
    Gathers the information a support engineer usually asks for first:
    operating system and uptime, hardware, CPU and memory load, disk space,
    pending restart status, automatic services that are not running, the
    processes using the most memory, and recent Critical and Error events.

    A short "Findings" list at the top of the report highlights anything
    that needs attention.

    The script is read-only. It does not change any settings.

.PARAMETER DiskWarningPercent
    A drive is flagged as LOW when its free space is below this percentage.
    Default is 15.

.PARAMETER TopProcesses
    How many processes to list, ordered by memory use. Default is 5.

.PARAMETER EventHours
    How many hours back to look for Critical and Error events in the System
    log. Default is 24.

.PARAMETER OutputPath
    Optional. Path of a text file to save the report to, for example
    C:\Temp\health.txt. The folder is created if it does not exist.

.PARAMETER PassThru
    Returns the collected data as an object instead of a text report, so it
    can be used by other scripts.

.EXAMPLE
    .\Get-SystemHealth.ps1

    Shows the health report on screen.

.EXAMPLE
    .\Get-SystemHealth.ps1 -OutputPath C:\Temp\health.txt

    Shows the report and saves a copy to attach to a ticket.

.EXAMPLE
    $health = .\Get-SystemHealth.ps1 -PassThru
    $health.Disks | Where-Object Status -eq 'LOW'

    Captures the data as an object and lists only the drives that are low on space.

.NOTES
    Requires Windows PowerShell 5.1 or PowerShell 7 on Windows.
    Run as administrator for the most complete results.
#>
[CmdletBinding()]
param(
    [ValidateRange(1, 99)]
    [int]$DiskWarningPercent = 15,

    [ValidateRange(1, 50)]
    [int]$TopProcesses = 5,

    [ValidateRange(1, 720)]
    [int]$EventHours = 24,

    [string]$OutputPath,

    [switch]$PassThru
)

$now = Get-Date

# --- Operating system and hardware -------------------------------------------
try {
    $os   = Get-CimInstance -ClassName Win32_OperatingSystem -ErrorAction Stop
    $cs   = Get-CimInstance -ClassName Win32_ComputerSystem -ErrorAction Stop
    $bios = Get-CimInstance -ClassName Win32_BIOS -ErrorAction Stop
    $cpu  = @(Get-CimInstance -ClassName Win32_Processor -ErrorAction Stop)
}
catch {
    throw "Could not read system information (WMI/CIM query failed): $($_.Exception.Message)"
}

$uptime = $now - $os.LastBootUpTime

# Win32_OperatingSystem reports memory in KB, so dividing by 1MB gives GB.
$memTotalGB = [math]::Round($os.TotalVisibleMemorySize / 1MB, 1)
$memFreeGB  = [math]::Round($os.FreePhysicalMemory / 1MB, 1)
$memUsedPct = [int][math]::Round((1 - ($os.FreePhysicalMemory / $os.TotalVisibleMemorySize)) * 100)

$cpuLoads = @($cpu | ForEach-Object { $_.LoadPercentage } | Where-Object { $null -ne $_ })
$cpuLoad = $null
if ($cpuLoads.Count -gt 0) {
    $cpuLoad = [int][math]::Round(($cpuLoads | Measure-Object -Average).Average)
}

$system = [pscustomobject]@{
    ComputerName      = $env:COMPUTERNAME
    CurrentUser       = "$env:USERDOMAIN\$env:USERNAME"
    OperatingSystem   = $os.Caption
    Version           = "$($os.Version) (build $($os.BuildNumber))"
    Architecture      = $os.OSArchitecture
    Manufacturer      = $cs.Manufacturer
    Model             = $cs.Model
    SerialNumber      = $bios.SerialNumber
    Domain            = $cs.Domain
    LastBoot          = $os.LastBootUpTime.ToString('yyyy-MM-dd HH:mm')
    Uptime            = '{0}d {1}h {2}m' -f $uptime.Days, $uptime.Hours, $uptime.Minutes
    Processor         = "$($cpu[0].Name)".Trim()
    Cores             = ($cpu | Measure-Object -Property NumberOfCores -Sum).Sum
    LogicalProcessors = ($cpu | Measure-Object -Property NumberOfLogicalProcessors -Sum).Sum
    CpuLoadPercent    = $cpuLoad
    MemoryTotalGB     = $memTotalGB
    MemoryFreeGB      = $memFreeGB
    MemoryUsedPercent = $memUsedPct
}

# --- Disks -------------------------------------------------------------------
$disks = @()
try {
    $disks = @(
        Get-CimInstance -ClassName Win32_LogicalDisk -Filter 'DriveType=3' -ErrorAction Stop |
            Where-Object { $_.Size -gt 0 } |
            ForEach-Object {
                $freePct = [int][math]::Round(($_.FreeSpace / $_.Size) * 100)
                $status = 'OK'
                if ($freePct -lt $DiskWarningPercent) { $status = 'LOW' }

                [pscustomobject]@{
                    Drive       = $_.DeviceID
                    Label       = $_.VolumeName
                    SizeGB      = [math]::Round($_.Size / 1GB, 1)
                    FreeGB      = [math]::Round($_.FreeSpace / 1GB, 1)
                    FreePercent = $freePct
                    Status      = $status
                }
            }
    )
}
catch {
    Write-Warning "Could not read disk information: $($_.Exception.Message)"
}

# --- Pending restart ---------------------------------------------------------
$rebootReasons = @()
if (Test-Path -Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending') {
    $rebootReasons += 'Windows component servicing'
}
if (Test-Path -Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired') {
    $rebootReasons += 'Windows Update'
}
$sessionManager = Get-ItemProperty -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager' -Name 'PendingFileRenameOperations' -ErrorAction SilentlyContinue
if ($sessionManager -and $sessionManager.PendingFileRenameOperations) {
    $rebootReasons += 'Pending file rename operations'
}

# --- Automatic services that are not running ---------------------------------
$stoppedServices = @()
try {
    $stoppedServices = @(
        Get-CimInstance -ClassName Win32_Service -Filter "StartMode='Auto' AND State<>'Running'" -ErrorAction Stop |
            Sort-Object -Property DisplayName |
            Select-Object -Property DisplayName, Name, State
    )
}
catch {
    Write-Warning "Could not read services: $($_.Exception.Message)"
}

# --- Processes using the most memory -----------------------------------------
$processes = @(
    Get-Process |
        Sort-Object -Property WorkingSet64 -Descending |
        Select-Object -First $TopProcesses |
        ForEach-Object {
            [pscustomobject]@{
                Name       = $_.ProcessName
                Id         = $_.Id
                MemoryMB   = [int][math]::Round($_.WorkingSet64 / 1MB)
                CpuSeconds = [int][math]::Round([double]$_.CPU)
            }
        }
)

# --- Recent Critical and Error events ----------------------------------------
$events = @()
try {
    $events = @(
        Get-WinEvent -FilterHashtable @{
            LogName   = 'System'
            Level     = 1, 2
            StartTime = $now.AddHours(-$EventHours)
        } -ErrorAction Stop
    )
}
catch {
    # "No events found" is a good result, not a failure.
    if ($_.FullyQualifiedErrorId -notlike 'NoMatchingEventsFound*') {
        Write-Warning "Could not read the System event log: $($_.Exception.Message)"
    }
}

# Get-WinEvent returns newest first, so the first event in each group is the latest.
$eventSummary = @(
    $events |
        Group-Object -Property ProviderName, Id |
        Sort-Object -Property Count -Descending |
        Select-Object -First 10 |
        ForEach-Object {
            [pscustomobject]@{
                Count    = $_.Count
                Level    = $_.Group[0].LevelDisplayName
                Source   = $_.Group[0].ProviderName
                EventId  = $_.Group[0].Id
                LastSeen = $_.Group[0].TimeCreated.ToString('yyyy-MM-dd HH:mm')
            }
        }
)

# --- Findings ----------------------------------------------------------------
$findings = @()
foreach ($disk in ($disks | Where-Object { $_.Status -eq 'LOW' })) {
    $findings += "Drive $($disk.Drive) is low on space: $($disk.FreePercent)% free ($($disk.FreeGB) GB)."
}
if ($memUsedPct -ge 90) {
    $findings += "Memory use is high: $memUsedPct% in use."
}
if ($null -ne $cpuLoad -and $cpuLoad -ge 90) {
    $findings += "CPU load is high: $cpuLoad%."
}
if ($uptime.TotalDays -ge 14) {
    $findings += "The machine has been up for $($uptime.Days) days. A restart is worth trying if it is slow or misbehaving."
}
if ($rebootReasons.Count -gt 0) {
    $findings += "A restart is pending: $($rebootReasons -join ', ')."
}
if ($stoppedServices.Count -gt 0) {
    $findings += "$($stoppedServices.Count) automatic service(s) are not running."
}
if ($events.Count -gt 0) {
    $findings += "$($events.Count) Critical or Error event(s) in the System log in the last $EventHours hour(s)."
}
if ($findings.Count -eq 0) {
    $findings += 'No issues flagged.'
}

$result = [pscustomobject]@{
    Collected       = $now
    System          = $system
    Disks           = $disks
    RebootPending   = ($rebootReasons.Count -gt 0)
    RebootReasons   = $rebootReasons
    StoppedServices = $stoppedServices
    TopProcesses    = $processes
    RecentErrors    = $eventSummary
    Findings        = $findings
}

if ($PassThru) {
    return $result
}

# --- Text report -------------------------------------------------------------
function Format-Section {
    param(
        [string]$Title,
        $Data,
        [switch]$AsList,
        [string]$EmptyText = 'None.'
    )

    $lines = @('', $Title, ('-' * $Title.Length))
    if ($null -eq $Data -or @($Data).Count -eq 0) {
        $lines += $EmptyText
    }
    elseif ($AsList) {
        $lines += ($Data | Format-List | Out-String -Width 200).Trim()
    }
    else {
        $lines += ($Data | Format-Table -AutoSize | Out-String -Width 200).Trim()
    }
    $lines
}

$report = @()
$report += "SYSTEM HEALTH REPORT: $($system.ComputerName)"
$report += "Collected: $($now.ToString('yyyy-MM-dd HH:mm'))"

$report += ''
$report += 'Findings'
$report += '--------'
$report += $findings | ForEach-Object { "- $_" }

$report += Format-Section -Title 'System' -Data $system -AsList
$report += Format-Section -Title 'Disks' -Data $disks -EmptyText 'No fixed disks found.'
$report += Format-Section -Title 'Automatic services not running (some stop by design once their work is done)' -Data $stoppedServices
$report += Format-Section -Title "Top $TopProcesses processes by memory" -Data $processes
$report += Format-Section -Title "Critical and Error events, System log, last $EventHours hour(s)" -Data $eventSummary -EmptyText 'None found.'

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
