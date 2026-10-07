# User Support Checklist

A step-by-step workflow for handling a support request, from first contact to closure. It shows where each script in this toolkit fits, so that evidence is gathered the same way every time.

Use it as a prompt, not a script. Skip steps that clearly do not apply, but do not skip the notes: the next engineer relies on them.

---

## 1. Open the ticket

- [ ] Log the ticket before starting work, however small the request
- [ ] Record the user's name, contact details, location and device name
- [ ] Confirm the user's identity before any account change, such as a password reset or access request
- [ ] Check for a known issue or an open major incident that already explains the problem

## 2. Understand the problem

Ask open questions first, then narrow down.

- [ ] What were you trying to do, and what happened instead?
- [ ] What is the exact error message? Ask for a screenshot where possible
- [ ] When did it last work?
- [ ] What changed since then? New software, updates, password, location, device
- [ ] Is anyone else affected?
- [ ] Does it happen every time, or only sometimes?
- [ ] What is the business impact, and is there a deadline?

Repeat the problem back to the user in one sentence to confirm that you have understood it.

## 3. Set the priority

Priority comes from impact and urgency, not from who is asking or how the request is worded.

| | Low urgency | Medium urgency | High urgency |
| --- | --- | --- | --- |
| **One user** | Low | Low | Medium |
| **A team or site** | Low | Medium | High |
| **The whole business or a critical service** | Medium | High | Critical |

- [ ] Set the priority and tell the user when to expect the next update
- [ ] If the priority is High or Critical, follow the [major incident process](https://github.com/Tolsty593/incident-management-playbook/blob/main/MajorIncidentProcess.md)

## 4. Gather evidence

Collect facts before changing anything. Save the output and attach it to the ticket.

| Symptom | Script | Example |
| --- | --- | --- |
| Slow machine, freezing, low disk space, general health | `Get-SystemHealth.ps1` | `.\Get-SystemHealth.ps1 -OutputPath C:\Temp\health.txt` |
| Missing application, wrong version, licence or compatibility question | `Get-InstalledSoftware.ps1` | `.\Get-InstalledSoftware.ps1 -Name '*Office*'` |
| Crashes, blue screens, services failing, unexplained errors | `Export-EventLogs.ps1` | `.\Export-EventLogs.ps1 -Hours 48 -Compress` |
| No internet, cannot reach a site or system, slow connection | `Network-Diagnostics.ps1` | `.\Network-Diagnostics.ps1 -OutputPath C:\Temp\network.txt` |

All four scripts are read-only. They collect information and do not change any settings.

- [ ] Run the script that matches the symptom
- [ ] Attach the output to the ticket
- [ ] Note anything that the "Findings" or "Assessment" line highlights

### Running the scripts

Open PowerShell in the folder that contains the scripts. If Windows blocks a script from running, this command allows scripts in the current PowerShell window only, and the setting is discarded when the window is closed:

```powershell
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass
```

On a managed company device, follow your organisation's policy on running scripts. Each script has built-in help, for example:

```powershell
Get-Help .\Get-SystemHealth.ps1 -Examples
```

## 5. Troubleshoot

- [ ] Search the knowledge base and previous tickets for the same error
- [ ] Try to reproduce the problem
- [ ] Start with the simplest and most likely cause
- [ ] Change one thing at a time, and test after each change
- [ ] Record each step and its result in the ticket as you go
- [ ] Undo any change that did not help
- [ ] Offer a workaround if the fix will take time

## 6. Escalate when needed

Escalate when the problem is outside your access or knowledge, when the time allowed at your level has run out, or when the impact is growing.

A good escalation lets the next team start work without contacting the user again. Include:

- [ ] A one-sentence summary of the problem
- [ ] Who is affected, and the business impact
- [ ] When it started and what changed
- [ ] Exact error messages and screenshots
- [ ] Script output and exported logs
- [ ] Everything already tried, with results
- [ ] The best time and way to contact the user

- [ ] Tell the user that the ticket has been escalated, who has it, and when to expect an update
- [ ] Stay the owner of the user's experience until the next team confirms that they have picked it up

## 7. Resolve and close

- [ ] Confirm with the user that the problem is fixed before closing the ticket
- [ ] Record the cause and the fix in plain language
- [ ] Choose the correct category and closure code so that reporting stays accurate
- [ ] Create or update a knowledge base article if the fix is likely to be needed again
- [ ] Raise a problem record if the same issue keeps returning

---

## Good practice

**Communication**

- Use plain language and avoid jargon
- Set expectations early, and give an update when you said you would, even if there is no news
- Never blame the user. Most errors are caused by confusing systems, not careless people
- Give every user the same patience and respect, whatever their role

**Working method**

- Write notes for the engineer who picks up the ticket after you
- Gather evidence before making changes
- Prefer the smallest change that fixes the problem
- If you fix the same thing three times, write it down or automate it

**Security**

- Verify identity before resetting passwords or granting access
- Never ask a user for their password
- Use administrator rights only for the task that needs them
- Report anything that looks like a security incident straight away
