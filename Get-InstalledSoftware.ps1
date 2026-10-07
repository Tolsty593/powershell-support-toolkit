<#
.SYNOPSIS
    Lists the software installed on the local Windows machine.

.DESCRIPTION
    Builds an inventory of installed applications by reading the uninstall
    entries in the registry: 64-bit and 32-bit applications installed for all
    users, and applications installed for the current user only.

    The registry is used instead of the Win32_Product WMI class on purpose.
    Querying Win32_Product is slow and makes Windows Installer run a
    consistency check on every MSI package, which can trigger repairs.

    The script is read-only. It does not install, remove or change anything.

.PARAMETER Name
    Only return software whose name matches this pattern. Wildcards are
    allowed. Default is * (everything).

.PARAMETER Publisher
    Only return software whose publisher matches this pattern. Wildcards are
    allowed. Default is * (everything).

.PARAMETER OutputPath
    Optional. Path of a CSV file to save the inventory to, for example
    C:\Temp\software.csv. The folder is created if it does not exist.

.PARAMETER IncludeSystemComponents
    Also list system components, updates and hotfixes, which are hidden by
    default in the same way that Windows hides them in "Installed apps".

.EXAMPLE
    .\Get-InstalledSoftware.ps1

    Lists all installed software.

.EXAMPLE
    .\Get-InstalledSoftware.ps1 -Name '*Office*'

    Checks whether Microsoft Office is installed, and which version.

.EXAMPLE
    .\Get-InstalledSoftware.ps1 -Publisher 'Adobe*' | Format-Table -AutoSize

    Lists everything published by Adobe as a table.

.EXAMPLE
    .\Get-InstalledSoftware.ps1 -OutputPath C:\Temp\software.csv

    Saves the full inventory as a CSV file that opens in Excel.

.NOTES
    Requires Windows PowerShell 5.1 or PowerShell 7 on Windows.
    Applications installed only for other user accounts are not listed.
    Microsoft Store apps are not listed. Use Get-AppxPackage for those.
#>
[CmdletBinding()]
param(
    [string]$Name = '*',

    [string]$Publisher = '*',

    [string]$OutputPath,

    [switch]$IncludeSystemComponents
)

if ([Environment]::Is64BitOperatingSystem -and -not [Environment]::Is64BitProcess) {
    Write-Warning 'This is 32-bit PowerShell on 64-bit Windows, so 64-bit applications will be missed. Run the script from 64-bit PowerShell.'
}

$nativeArchitecture = '32-bit'
if ([Environment]::Is64BitOperatingSystem) { $nativeArchitecture = '64-bit' }

$sources = @(
    @{
        Key          = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall'
        Scope        = 'All users'
        Architecture = $nativeArchitecture
    },
    @{
        Key          = 'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall'
        Scope        = 'All users'
        Architecture = '32-bit'
    },
    @{
        Key          = 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall'
        Scope        = 'Current user'
        Architecture = ''
    }
)

$updateTypes = @('Update', 'Hotfix', 'Security Update')

$software = foreach ($source in $sources) {
    if (-not (Test-Path -Path $source.Key)) { continue }

    foreach ($entry in (Get-ItemProperty -Path "$($source.Key)\*" -ErrorAction SilentlyContinue)) {
        # Entries without a display name are not shown to users by Windows either.
        if ([string]::IsNullOrWhiteSpace($entry.DisplayName)) { continue }

        if (-not $IncludeSystemComponents) {
            if ($entry.SystemComponent -eq 1) { continue }
            if ($entry.ParentKeyName) { continue }
            if ($updateTypes -contains $entry.ReleaseType) { continue }
        }

        # InstallDate is stored as text in the form yyyyMMdd, and is often missing.
        $installDate = ''
        $parsed = [datetime]::MinValue
        if ([datetime]::TryParseExact("$($entry.InstallDate)", 'yyyyMMdd', [cultureinfo]::InvariantCulture, [System.Globalization.DateTimeStyles]::None, [ref]$parsed)) {
            $installDate = $parsed.ToString('yyyy-MM-dd')
        }

        [pscustomobject]@{
            Name         = "$($entry.DisplayName)".Trim()
            Version      = "$($entry.DisplayVersion)"
            Publisher    = "$($entry.Publisher)"
            InstallDate  = $installDate
            Architecture = $source.Architecture
            Scope        = $source.Scope
        }
    }
}

$software = @(
    $software |
        Where-Object { $_.Name -like $Name -and $_.Publisher -like $Publisher } |
        Sort-Object -Property Name, Version, Architecture, Scope -Unique
)

if ($OutputPath) {
    $folder = Split-Path -Path $OutputPath -Parent
    if ($folder -and -not (Test-Path -Path $folder)) {
        New-Item -Path $folder -ItemType Directory -Force | Out-Null
    }
    $software | Export-Csv -Path $OutputPath -NoTypeInformation -Encoding UTF8
    Write-Host "$($software.Count) item(s) saved to $OutputPath"
}
else {
    $software
}
