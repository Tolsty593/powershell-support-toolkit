<#
.SYNOPSIS
    Exports recent Windows Event Log entries to CSV files.

.DESCRIPTION
    Collects events from one or more Windows event logs for a chosen time
    window and severity, and saves one CSV file per log. The files open in
    Excel and can be attached to a ticket or sent to a vendor.

    By default the script exports Critical, Error and Warning events from the
    System and Application logs for the last 24 hours.

    The script only reads the event logs. It does not clear or change them.

.PARAMETER LogName
    The event logs to export. Default is System and Application.
    Reading the Security log requires an administrator PowerShell window.

.PARAMETER Hours
    How many hours back to collect events from. Default is 24.

.PARAMETER Level
    The severities to include: Critical, Error, Warning, Information.
    Default is Critical, Error and Warning.

.PARAMETER MaxEvents
    The most events to export from each log. The newest events are kept.
    Default is 5000.

.PARAMETER OutputPath
    The folder to save the files in. It is created if it does not exist.
    Default is a folder called EventLogExport in the current location.

.PARAMETER Compress
    Also creates a single zip file containing the exported CSV files.

.EXAMPLE
    .\Export-EventLogs.ps1

    Exports the last 24 hours of Critical, Error and Warning events from the
    System and Application logs.

.EXAMPLE
    .\Export-EventLogs.ps1 -Hours 72 -Level Critical, Error -OutputPath C:\Temp\Logs

    Exports three days of Critical and Error events to C:\Temp\Logs.

.EXAMPLE
    .\Export-EventLogs.ps1 -LogName System, Application, Security -Compress

    Exports three logs and bundles them into one zip file. Run as
    administrator so that the Security log can be read.

.NOTES
    Requires Windows PowerShell 5.1 or PowerShell 7 on Windows.
#>
[CmdletBinding()]
param(
    [string[]]$LogName = @('System', 'Application'),

    [ValidateRange(1, 8760)]
    [int]$Hours = 24,

    [ValidateSet('Critical', 'Error', 'Warning', 'Information')]
    [string[]]$Level = @('Critical', 'Error', 'Warning'),

    [ValidateRange(1, 100000)]
    [int]$MaxEvents = 5000,

    [string]$OutputPath = (Join-Path -Path $PWD.Path -ChildPath 'EventLogExport'),

    [switch]$Compress
)

# Event level numbers used by Windows. Level 0 is also shown as Information.
$levelMap = @{
    Critical    = @(1)
    Error       = @(2)
    Warning     = @(3)
    Information = @(4, 0)
}
$levelIds = @($Level | ForEach-Object { $levelMap[$_] } | Sort-Object -Unique)

$startTime = (Get-Date).AddHours(-$Hours)
$stamp     = Get-Date -Format 'yyyyMMdd-HHmmss'
$computer  = $env:COMPUTERNAME

if (-not (Test-Path -Path $OutputPath)) {
    New-Item -Path $OutputPath -ItemType Directory -Force | Out-Null
}

$exportedFiles = @()

$summary = foreach ($log in $LogName) {
    $events = @()
    $status = 'Exported'

    try {
        $events = @(
            Get-WinEvent -FilterHashtable @{
                LogName   = $log
                Level     = $levelIds
                StartTime = $startTime
            } -MaxEvents $MaxEvents -ErrorAction Stop
        )
    }
    catch {
        if ($_.FullyQualifiedErrorId -like 'NoMatchingEventsFound*') {
            $status = 'No matching events'
        }
        else {
            # Typical causes: the log name is wrong, or the log needs administrator rights.
            $status = "Failed: $($_.Exception.Message)"
            Write-Warning "Could not read the '$log' log: $($_.Exception.Message)"
        }
    }

    $fileName = ''
    if ($events.Count -gt 0) {
        # Some log names contain characters that are not allowed in file names.
        $safeLogName = $log -replace '[\\/:*?"<>|]', '-'
        $fileName = '{0}_{1}_{2}.csv' -f $computer, $safeLogName, $stamp
        $filePath = Join-Path -Path $OutputPath -ChildPath $fileName

        $events |
            Select-Object -Property @{ Name = 'TimeCreated'; Expression = { $_.TimeCreated.ToString('yyyy-MM-dd HH:mm:ss') } },
                @{ Name = 'Level'; Expression = { $_.LevelDisplayName } },
                Id,
                ProviderName,
                MachineName,
                Message |
            Export-Csv -Path $filePath -NoTypeInformation -Encoding UTF8

        $exportedFiles += $filePath

        if ($events.Count -eq $MaxEvents) {
            $status = "Exported (stopped at the newest $MaxEvents events)"
        }
    }

    [pscustomobject]@{
        LogName = $log
        Events  = $events.Count
        Status  = $status
        File    = $fileName
    }
}

$summary

if ($exportedFiles.Count -eq 0) {
    Write-Host 'Nothing was exported.'
    return
}

Write-Host "Files saved in $OutputPath"

if ($Compress) {
    $zipPath = Join-Path -Path $OutputPath -ChildPath ('{0}_EventLogs_{1}.zip' -f $computer, $stamp)
    Compress-Archive -Path $exportedFiles -DestinationPath $zipPath -Force
    Write-Host "Zip file created: $zipPath"
}
