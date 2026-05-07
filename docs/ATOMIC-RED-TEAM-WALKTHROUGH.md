# Atomic Red Team — running the lab against itself

This walkthrough fires two well-known [Atomic Red Team](https://github.com/redcanaryco/atomic-red-team) tests against the lab's endpoints and shows what comes out the other side in **Wazuh** when the stack works correctly.

The goal is not to prove "Wazuh detects everything out of the box" — it isn't supposed to. The goal is to give you a repeatable closed-loop you can use to **tune your own rules**: simulate, observe, tune, simulate again.

The two techniques covered here:

| MITRE ID | Technique | Why pick it |
|---|---|---|
| **T1110.001** | Brute Force: Password Guessing | Highest-volume noise on any internet-exposed Linux. Every SOC sees this. Built-in Wazuh rules light up immediately. |
| **T1059.001** | Command and Scripting Interpreter: PowerShell | Most common Windows post-exploitation primitive. Requires Sysmon to see anything useful. |

If you don't have the lab running yet, do that first — [`README.md`](../README.md) → *Quick start*.

---

## 0 · Prerequisites

| Component | Where | What |
|---|---|---|
| Wazuh manager / dashboard | host | from `docker compose up` in this repo |
| Linux endpoint | VM or container | Ubuntu / Debian, Wazuh agent enrolled |
| Windows endpoint | VM | Windows 10/11, Wazuh agent enrolled, **Sysmon** installed with the [SwiftOnSecurity config](https://github.com/SwiftOnSecurity/sysmon-config) |
| Atomic Red Team | both endpoints | installed via the official PowerShell installer |

The Sysmon config matters: without it, T1059.001 will fire on the host but Wazuh will only see Windows event logs that don't include the command line. SwiftOnSecurity's config logs ProcessCreate (event 1) with the full command line, which is what the rule below pivots on.

### Install Atomic Red Team

#### Linux endpoint

```bash
sudo apt-get update && sudo apt-get install -y powershell      # if pwsh isn't there yet
pwsh -Command "Install-Module -Name invoke-atomicredteam, powershell-yaml -Scope CurrentUser -Force"
pwsh -Command "Import-Module invoke-atomicredteam ; Install-AtomicRedTeam -getAtomics"
```

#### Windows endpoint (PowerShell, **as Administrator**)

```powershell
# Allow scripts in this session
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass -Force

# Install the framework + the atomics yaml repo
IEX (IWR 'https://raw.githubusercontent.com/redcanaryco/invoke-atomicredteam/master/install-atomicredteam.ps1' -UseBasicParsing)
Install-AtomicRedTeam -getAtomics

# Quick smoke test
Invoke-AtomicTest T1059.001 -ShowDetails
```

> **Important** — Atomic tests can trigger your AV / EDR. On the Windows VM, exclude `C:\AtomicRedTeam` from Defender's real-time protection *only for the test* and re-enable it after.

---

## 1 · T1110.001 — Brute force SSH (Linux)

### What it does

Repeatedly fails SSH authentication from the Linux endpoint to itself (or another host on the same network). Generates `sshd: Failed password` log lines that the Wazuh agent ships to the manager.

### Run it

From a *different* machine (your attacker box), spray the Linux endpoint with `hydra`:

```bash
# Replace 10.0.0.10 with the IP of the lab Linux endpoint
hydra -l root -P /usr/share/wordlists/rockyou.txt ssh://10.0.0.10 -t 4
```

Or, if you'd rather use Atomic Red Team itself:

```bash
pwsh
Invoke-AtomicTest T1110.001 -TestNumbers 1
# This drops a small Python helper that issues N failed SSH login attempts
```

### What you should see in Wazuh

Built-in rules in `0095-sshd_rules.xml` (or `0090-sshd_rules.xml` depending on your Wazuh version):

| Rule ID | Description |
|---|---|
| `5710` | sshd: Attempt to login using a non-existent user |
| `5712` | sshd: brute force trying to get access (parent rule) |
| `5760` | sshd: authentication failed |
| `5763` | sshd: brute force trying to get access (frequency) — fires after 8 hits in 120 s |

In the Wazuh dashboard:

```
Threat Hunting → Events
filter: rule.groups: "sshd_brute_force"   AND  agent.name: <your-linux-endpoint>
```

You should see rule `5763` with severity 10 within a couple of minutes.

### What to tune

Look at the **time-frame** and **threshold** on rule 5712 / 5763 (default is 8 attempts in 120 s). For an internal lab that's probably fine; for a public-facing prod SSH I'd drop it to 5 in 60 s.

```xml
<!-- /var/ossec/etc/rules/local_rules.xml on the manager -->
<group name="sshd,authentication_failures,">
  <rule id="100100" level="10" frequency="5" timeframe="60">
    <if_matched_sid>5760</if_matched_sid>
    <description>SSH brute force tightened — 5 fails in 60s</description>
    <mitre>
      <id>T1110.001</id>
    </mitre>
  </rule>
</group>
```

Reload rules:

```bash
docker compose exec wazuh-manager /var/ossec/bin/wazuh-control restart
```

Re-run the test, confirm the new rule fires on a smaller threshold.

---

## 2 · T1059.001 — Suspicious PowerShell (Windows)

### What it does

Runs an encoded PowerShell command that looks like a typical post-exploitation primitive. With **Sysmon + SwiftOnSecurity config** enrolled into Wazuh, the manager sees a ProcessCreate (event 1) with the full command line, including the `-EncodedCommand` flag.

### Enroll Sysmon into Wazuh

Add this block to the agent's `C:\Program Files (x86)\ossec-agent\ossec.conf`:

```xml
<localfile>
  <location>Microsoft-Windows-Sysmon/Operational</location>
  <log_format>eventchannel</log_format>
</localfile>
```

Restart the agent:

```powershell
Restart-Service -Name WazuhSvc
```

You can verify the channel is being read on the manager side:

```bash
docker compose exec wazuh-manager tail -f /var/ossec/logs/archives/archives.json | grep "Sysmon"
```

### Run the test

```powershell
Invoke-AtomicTest T1059.001 -TestNumbers 1   # encoded command
```

Test 1 launches:

```
powershell.exe -EncodedCommand JABzAD0AIgBoAGEAcgBpAGIAbwAiADsAVwByAGkAdABlAC0ASABvAHMAdAAgACQAcwA=
```

(decodes to `Write-Host "haribo"` — harmless, but the *shape* of the command is exactly what malware uses).

### What you should see in Wazuh

Without custom rules, Wazuh's default ruleset will surface the Sysmon ProcessCreate event under rule `61603` (Sysmon: Process creation). That's not loud enough for a hunt — it fires on every process. We want a **specific rule on suspicious PowerShell command lines**.

Add this to `local_rules.xml` on the manager:

```xml
<group name="sysmon,powershell_suspicious,">

  <rule id="100200" level="0">
    <if_sid>61603</if_sid>
    <field name="win.eventdata.image" type="pcre2">(?i)\\powershell(_ise)?\.exe</field>
    <description>Sysmon: PowerShell process creation (parent for filters below)</description>
  </rule>

  <rule id="100201" level="10">
    <if_sid>100200</if_sid>
    <field name="win.eventdata.commandLine" type="pcre2">(?i)-(e|en|enc|enco|encod|encode|encoded|encodedc|encodedcom|encodedcomm|encodedcomma|encodedcomman|encodedcommand)\b</field>
    <description>PowerShell -EncodedCommand — possible obfuscation (T1059.001)</description>
    <mitre><id>T1059.001</id></mitre>
  </rule>

  <rule id="100202" level="12">
    <if_sid>100200</if_sid>
    <field name="win.eventdata.commandLine" type="pcre2">(?i)downloadstring|downloadfile|invoke-expression|iex\b|frombase64string</field>
    <description>PowerShell download/execution primitives (T1059.001 / T1105)</description>
    <mitre>
      <id>T1059.001</id>
      <id>T1105</id>
    </mitre>
  </rule>

</group>
```

Reload rules, re-run the test, then in the Wazuh dashboard:

```
Threat Hunting → Events
filter: rule.id: 100201   OR   rule.id: 100202
```

You should see the encoded-command line and the matching rule. Click on the event to see the full command line, the parent process, the user, and the host.

### What to tune

- **Allow-list** legitimate parent processes (e.g. SCCM, your own management tools) so they don't trigger the level 10 rule.
- Add detections for `-NoProfile -WindowStyle Hidden` combos — also extremely common in malware.
- Add a frequency rule: 3+ hits of `100201` from the same host in 5 minutes is much more interesting than one.

---

## 3 · Closing the loop

The walkthrough is intentionally short and concrete. The point isn't the two specific tests — it's the loop:

1. Pick a MITRE technique from the [Atomic Red Team coverage matrix](https://atomicredteam.io/atomic-red-team/matrix/).
2. Run it against the lab.
3. Watch Wazuh — does any rule fire?
4. If yes, is it precise enough? Tune.
5. If no, write a rule, reload, re-run.

Two more high-value MITRE IDs to try once you're comfortable with the loop above:

- **T1003.001** — LSASS memory dump (Windows, Sysmon event 10)
- **T1218.011** — Rundll32 abuse (Windows, Sysmon event 1)

Each one teaches you a different Sysmon event ID, which is the real skill the lab is here to build.

---

## 4 · Cleanup

```powershell
# Roll back artefacts the tests leave behind
Invoke-AtomicTest T1110.001 -Cleanup
Invoke-AtomicTest T1059.001 -Cleanup

# Re-enable Defender real-time protection if you disabled it
Set-MpPreference -DisableRealtimeMonitoring $false
```

That's the whole walkthrough — adapt the indicators above to your own environment, and please don't run any of this against assets you don't own or have written authorisation to test.
