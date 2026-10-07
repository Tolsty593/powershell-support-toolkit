# PowerShell Support Toolkit

Read-only PowerShell scripts that gather the diagnostic information a support engineer needs at the start of a ticket: system health, installed software, event logs and network status.

## Purpose

The goal of this repository is to reduce manual effort, improve troubleshooting efficiency, and support operational excellence through automation.

## Toolkit Contents

| File | What it does |
| --- | --- |
| [Get-SystemHealth.ps1](Get-SystemHealth.ps1) | One report covering uptime, CPU, memory, disk space, pending restarts, stopped services and recent errors, with a list of findings at the top |
| [Get-InstalledSoftware.ps1](Get-InstalledSoftware.ps1) | Inventory of installed software with version, publisher and install date, with optional export to CSV |
| [Export-EventLogs.ps1](Export-EventLogs.ps1) | Exports recent Windows event log entries to CSV files, ready to attach to a ticket |
| [Network-Diagnostics.ps1](Network-Diagnostics.ps1) | Checks the adapter, gateway, internet, DNS and a TCP port, then suggests where the fault is |
| [User-Support-Checklist.md](User-Support-Checklist.md) | A troubleshooting workflow from first contact to closure, showing which script to use for which symptom |

## Getting Started

1. Click the green **Code** button at the top of this page and choose **Download ZIP**.
2. Extract the ZIP file to a folder, for example `C:\SupportToolkit`.
3. Open the folder in File Explorer, click the address bar, type `powershell` and press Enter.
4. Allow scripts to run in this PowerShell window only. The setting is discarded when the window is closed:

   ```powershell
   Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass
   ```

5. Run a script:

   ```powershell
   .\Get-SystemHealth.ps1
   ```

On a managed company device, follow your organisation's policy on running scripts.

Every script has built-in help with examples:

```powershell
Get-Help .\Get-SystemHealth.ps1 -Full
```

## Usage

### Get-SystemHealth.ps1

```powershell
# Show the report on screen
.\Get-SystemHealth.ps1

# Save a copy to attach to a ticket
.\Get-SystemHealth.ps1 -OutputPath C:\Temp\health.txt

# Flag drives with less than 20% free, and look back 72 hours for errors
.\Get-SystemHealth.ps1 -DiskWarningPercent 20 -EventHours 72

# Return the data as an object for use in other scripts
$health = .\Get-SystemHealth.ps1 -PassThru
$health.Disks
```

The report starts with a list of findings, for example:

```text
Findings
--------
- Drive C: is low on space: 7% free (18 GB).
- Memory use is high: 93% in use.
- The machine has been up for 21 days. A restart is worth trying if it is slow or misbehaving.
- A restart is pending: Windows Update.
- 2 automatic service(s) are not running.
```

### Get-InstalledSoftware.ps1

```powershell
# List everything
.\Get-InstalledSoftware.ps1

# Check whether an application is installed, and which version
.\Get-InstalledSoftware.ps1 -Name '*Office*'

# List everything from one publisher
.\Get-InstalledSoftware.ps1 -Publisher 'Adobe*' | Format-Table -AutoSize

# Save the full inventory as a CSV file that opens in Excel
.\Get-InstalledSoftware.ps1 -OutputPath C:\Temp\software.csv
```

The script reads the registry rather than the `Win32_Product` class. Querying `Win32_Product` is slow and makes Windows Installer check every installed package, which can trigger repairs.

### Export-EventLogs.ps1

```powershell
# Last 24 hours of Critical, Error and Warning events from System and Application
.\Export-EventLogs.ps1

# Three days of Critical and Error events, saved to a chosen folder
.\Export-EventLogs.ps1 -Hours 72 -Level Critical, Error -OutputPath C:\Temp\Logs

# Include the Security log and bundle everything into one zip file
# (run PowerShell as administrator to read the Security log)
.\Export-EventLogs.ps1 -LogName System, Application, Security -Compress
```

### Network-Diagnostics.ps1

```powershell
# Run the standard checks
.\Network-Diagnostics.ps1

# Check whether an internal system resolves and accepts connections
.\Network-Diagnostics.ps1 -DnsName intranet.contoso.com -TcpHost intranet.contoso.com -TcpPort 443, 3389

# Save a copy of the report
.\Network-Diagnostics.ps1 -OutputPath C:\Temp\network.txt
```

Each check is reported as PASS, WARN or FAIL, followed by an assessment of the most likely cause. An illustrative example:

```text
Check         Target                Status Detail
-----         ------                ------ ------
Adapter       Wi-Fi                 PASS   IP 192.168.1.57; gateway 192.168.1.1; DNS 192.168.1.1
Gateway       192.168.1.1           PASS   3 of 3 replies, average 2 ms
Internet ping 1.1.1.1               PASS   3 of 3 replies, average 14 ms
DNS           www.microsoft.com     FAIL   Name did not resolve
TCP port      www.microsoft.com:443 FAIL   Could not connect

Assessment: The internet is reachable by IP address but names do not resolve. This points to DNS: check the DNS servers shown for the adapter.
```

## Design Principles

- **Read-only.** The scripts collect information. They do not change settings, install or remove anything.
- **Nothing to install.** They use only what is built into Windows and PowerShell.
- **Plain-language results.** Each report highlights what needs attention, so it is useful to the engineer and readable in a ticket.
- **Reusable output.** Reports can be saved to a file, and `-PassThru` returns objects for use in other scripts.
- **Self-documenting.** Every script has comment-based help with a description, parameters and examples.

## Requirements

- Windows PowerShell 5.1 or PowerShell 7, on Windows
- `Network-Diagnostics.ps1` needs Windows 8.1, Windows Server 2012 R2 or later
- Some information needs an administrator PowerShell window, such as the Security event log

## Why Automation Matters

Support engineers often spend significant time gathering diagnostic information. Automation helps:

- Reduce investigation times
- Improve consistency
- Reduce manual effort
- Improve customer outcomes

## Related Projects

- [Incident Management Playbook](https://github.com/Tolsty593/incident-management-playbook)
- [AI Adoption Playbook](https://github.com/Tolsty593/ai-adoption-playbook)

## Author

Gladwyn

Support Engineer | Service Delivery Professional | AI & Automation Enthusiast
