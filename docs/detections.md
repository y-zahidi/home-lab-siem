# Detections — Playbook

Each rule shipped in [`config/wazuh/rules/local_rules.xml`](../config/wazuh/rules/local_rules.xml) has a corresponding analyst playbook below. Format:

- **What triggers it** — the underlying behaviour
- **Sample log line** — what you'll see in Wazuh
- **Triage** — first 5 minutes
- **Escalation** — when to wake someone up
- **False positives** — known noise

---

## 100100 — SSH brute-force (T1110.001)

**What triggers it.** Five or more failed SSH logins from the same source IP within 60 seconds. Underlying decoder is the standard `sshd` decoder (`5712`).

**Sample log line:**
```
Failed password for invalid user admin from 203.0.113.42 port 51234 ssh2
```

**Triage (first 5 min).**
1. Open the alert → check the `srcip` and the `target` host.
2. Look for a *successful* login from the same `srcip` in the next 30 min — that's the real signal.
3. `geoip` lookup on the source IP. If it's a known country your org doesn't operate in, that's a strong signal.

**Escalation.**
- If a successful login follows the brute-force attempts → escalate immediately (T1078 — Valid Accounts).
- If the targeted account is a service account or `root` → escalate immediately.

**False positives.**
- A legitimate user typing the wrong password on a Yubikey-protected account 5 times in a row.
- An automated backup script with stale credentials.
- Internal CI/CD jobs that hit a misconfigured SSH key.

**Tuning tip.** Whitelist your `nagios`/`zabbix`/CI source IPs in `local_rules.xml` with an `if_matched_sid` exclusion — don't blanket-disable rule 5712.

---

## 100101 — Suspicious PowerShell (T1059.001)

**What triggers it.** Sysmon Event ID 4104 (PowerShell script-block logging) where the command line contains one of:
- `-EncodedCommand` / `-enc` (base64-encoded payload)
- `IEX (` (Invoke-Expression — the offensive PowerShell idiom)
- `DownloadString` (in-memory download + execute)
- `Invoke-Mimikatz`
- `FromBase64String`

**Sample log line:**
```
powershell.exe -nop -w hidden -enc JABjAGwAaQBlAG4AdAA9AE4AZQB3...
```

**Triage.**
1. Decode the `-enc` payload (`echo "<b64>" | base64 -d`). If the decoded script connects to an external IP or downloads a file → live incident.
2. Check the parent process. PowerShell spawned from `winword.exe` or `excel.exe` = phishing macro execution (T1566.001).
3. Check the user. Was it run by a service account that shouldn't be using PowerShell? Strong signal.

**Escalation.**
- Always escalate. False positives are rare for this rule.

**False positives.**
- Legitimate PSRemoting jobs from ops engineers (whitelist their workstations).
- Some EDR/AV products that legitimately use encoded PowerShell internally.

**Tuning tip.** Pair this rule with rule `100101-resp` that triggers Wazuh Active Response to *kill* the PowerShell process when it matches AND the parent is an Office app. Test this in audit-only mode first.

---

## 100102 — Port scan from a single source (T1046)

**What triggers it.** A Suricata `SCAN nmap` signature firing in the EVE JSON output, ingested by Wazuh through syslog.

**Sample log line:**
```
{"src_ip":"10.0.0.5","dest_ip":"10.0.0.10","alert":{"signature":"ET SCAN nmap -sS"}}
```

**Triage.**
1. Identify the `src_ip`. Is it an internal asset or external?
2. If internal: pivot to the asset's process list — what process opened the connection? Could be a legitimate vuln scanner (Nessus / Tenable / OpenVAS).
3. If external: confirm the destination service is intentionally exposed. If yes — usually safe to ignore (the internet scans you constantly). If no — block the source at the firewall.

**Escalation.**
- Internal port scan from a workstation (not a known scanner) → escalate. Probable lateral-movement recon.

**False positives.**
- Scheduled vulnerability scanners (Nessus, Qualys, Rapid7).
- Network monitoring tools doing service-discovery sweeps.

**Tuning tip.** Maintain a list of authorized scanner IPs in a separate `cdb_lists/scanners.list` file and exclude them via `<list lookup="address_match_key">cdb_lists/scanners</list>`.

---

## 100103 — File integrity violation in protected paths (T1565.001)

**What triggers it.** Wazuh's `syscheck` (FIM) detects a modify/add/delete on a file under:
- `/etc/`
- `C:\Windows\System32\`

**Sample log line:**
```
File '/etc/sudoers' modified
Old md5sum was: a1b2c3...
New md5sum is:  9f8e7d...
```

**Triage.**
1. Open the FIM diff in the dashboard — what changed?
2. Cross-reference with change-management tickets. Was this an approved change?
3. Look at *who* made the change (audit log on Linux, Sysmon EID 11 on Windows).

**Escalation.**
- Modification of `/etc/sudoers`, `/etc/passwd`, `/etc/shadow`, or `C:\Windows\System32\drivers\etc\hosts` outside a change window → immediate escalation.
- Any new file added to `C:\Windows\System32\` that isn't part of a Microsoft-signed update → immediate escalation (T1574 — Hijack Execution Flow).

**False positives.**
- Apt/yum updates touching files in `/etc/`.
- Microsoft Patch Tuesday touching files in `System32`.

**Tuning tip.** Schedule FIM scans *outside* your normal patching window so legitimate updates and malicious modifications don't blur together.

---

## 100104 — Probable web shell upload (T1505.003)

**What triggers it.** A new file appears in a path matching `*/uploads/*.php` (or similar for ASP.NET) — typical signature of a web shell dropped through an upload-form vulnerability.

**Sample log line:**
```
File '/var/www/html/uploads/img_4827.php' added
```

**Triage.**
1. Read the file. If it contains `eval(`, `system(`, `passthru(`, `base64_decode(` → 99% chance it's a web shell.
2. Find the HTTP request that uploaded it (Suricata HTTP logs — same timestamp).
3. Identify the source IP and the upload form that was abused.

**Escalation.**
- Always escalate. Web shells = full RCE = the attacker is already inside your perimeter.

**Response (don't wait).**
- Quarantine the file (move to `/quarantine/<timestamp>/`, *don't delete* — you'll need it for forensics).
- Block the source IP at the WAF/firewall.
- Pull the web server's access logs for the last 24h, filter by that source IP.
- Look for further uploads or lateral movement (DB queries, outbound connections).

**False positives.**
- A developer testing the upload form with a benign `.php` file. Real, but rare in production.

**Tuning tip.** Pair with a Suricata rule that alerts on HTTP `Content-Type: application/x-php` in upload responses for an even earlier detection.

---

## How to add your own rule

1. Edit `config/wazuh/rules/local_rules.xml` — pick a rule ID in the `100xxx` range.
2. Tag it with the right MITRE technique (`<mitre><id>Txxxx</id></mitre>`).
3. Restart the manager: `docker compose restart wazuh.manager`.
4. Generate the matching event (or use Atomic Red Team).
5. Verify the alert fires in the dashboard (Wazuh → Modules → Security events).
6. Document the playbook entry here.

If a rule is too noisy, *tune it before disabling it.* The right tools are `<frequency>`, `<timeframe>`, `<if_sid>`, `<if_matched_sid>`, and CDB lists for whitelist exclusions.
