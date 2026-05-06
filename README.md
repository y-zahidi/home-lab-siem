# 🛡️ home-lab-siem

> A reproducible **multi-layer SIEM lab** based on the architecture I deployed during my cybersecurity internship at the **Préfecture de Tétouan (SSIC)**, packaged as a docker-compose stack you can spin up in 5 minutes.

![Status](https://img.shields.io/badge/status-active-success)
![License](https://img.shields.io/badge/license-MIT-blue)
![Docker](https://img.shields.io/badge/Docker-Compose-2496ED?logo=docker&logoColor=white)
![Wazuh](https://img.shields.io/badge/Wazuh-4.7-005571?logo=wazuh&logoColor=white)
![Suricata](https://img.shields.io/badge/Suricata-7.0-EE0000)

---

## TL;DR

This lab gives you a **production-shaped SIEM in a single command**:

- **Wazuh** (manager + indexer + dashboard) — log management, HIDS, file integrity monitoring, MITRE ATT&CK mapping
- **Suricata** — network IDS/IPS with EVE JSON output ingested by Wazuh
- **Sysmon** rules ready for Windows endpoints (with the SwiftOnSecurity baseline)
- **5 custom detection rules** (SSH brute-force, suspicious PowerShell, port scan, file-integrity violations, web shell upload patterns)
- **Docs** explaining the architecture, why each component exists, and how a real SOC analyst would respond to the alerts

```bash
git clone https://github.com/y-zahidi/home-lab-siem.git
cd home-lab-siem
docker compose up -d
# Wait ~3 min for Wazuh to bootstrap, then:
open https://localhost:443   # admin / admin (change it!)
```

---

## Why this repo exists

During my internship at the **Préfecture de Tétouan**, I deployed an internal SIEM using **Wazuh + Suricata + Sysmon + MISP + VirusTotal** integrated with a **FortiGate** firewall. The goal of this repo is to:

1. Re-implement the same architecture in a way that anyone can spin up locally
2. Document the design decisions I made (why Wazuh over ELK alone, why Suricata over Snort, etc.)
3. Ship a small set of **opinionated detection rules** that catch the most common attacker behaviours
4. Be a learning resource for other students and aspiring SOC analysts in Morocco

> **No real or sensitive data from the internship is included here.** Everything is synthesized for the lab.

---

## Architecture

```
                           ┌──────────────────────────────────────┐
                           │       Endpoints (lab targets)        │
                           │                                      │
                           │  ┌──────────────┐  ┌──────────────┐  │
                           │  │ Linux box    │  │ Windows box  │  │
                           │  │ Wazuh agent  │  │ Wazuh agent  │  │
                           │  │ + auditd     │  │ + Sysmon     │  │
                           │  └──────┬───────┘  └──────┬───────┘  │
                           └─────────┼─────────────────┼──────────┘
                                     │                 │
                                     ▼                 ▼
                          ┌─────────────────────────────────────┐
                          │  Suricata (IDS/IPS, EVE JSON out)   │
                          │  Mirrors traffic from a span port   │
                          └────────────────┬────────────────────┘
                                           │
                                           ▼
                       ┌──────────────────────────────────────────┐
                       │       Wazuh Manager (brain)              │
                       │  • Decoders + rule engine                │
                       │  • Alerts → Wazuh Indexer (OpenSearch)   │
                       │  • Active Response (block IP, kill PID)  │
                       └────────────────┬─────────────────────────┘
                                        │
                                        ▼
                       ┌──────────────────────────────────────────┐
                       │   Wazuh Indexer (OpenSearch)             │
                       │   + Wazuh Dashboard (Kibana fork)        │
                       │   → SOC analyst UI                       │
                       └──────────────────────────────────────────┘
```

---

## Why this stack (and not just ELK)

| Need | Choice | Why |
|------|--------|-----|
| Log shipping & parsing | Wazuh agent | Lightweight, native enrollment, built-in decoders for 100+ apps |
| HIDS / FIM / Rootcheck | Wazuh manager | Built-in, no extra agent (vs OSSEC + Beats + custom) |
| Network IDS | Suricata | EVE JSON, multi-threaded, ET Open ruleset, easy Wazuh ingest |
| Search & storage | Wazuh Indexer (OpenSearch) | Bundled with Wazuh, Apache 2.0, no Elastic license drama |
| Endpoint telemetry (Windows) | Sysmon + SwiftOnSecurity ruleset | The de-facto baseline for process/network monitoring |
| MITRE ATT&CK mapping | Built into Wazuh | Each rule is tagged with the relevant ATT&CK technique |

Trade-offs I'm making here:

- **Single-node Wazuh.** Production should be a 3-node indexer cluster + dedicated manager. For a lab, single-node is fine.
- **No MISP yet.** MISP integration was part of my Préfecture deployment but adds operational overhead. There's a `docs/MISP_INTEGRATION.md` describing how to plug it in.
- **No FortiGate emulation.** I documented the firewall integration patterns I used, but emulating a FortiGate locally requires a paid VM image. The repo covers everything down to the SIEM layer.

---

## Quick start

### Prerequisites

- Docker Engine 24+ and Docker Compose v2
- ~6 GB free RAM (Wazuh indexer is the heavy one)
- Linux or macOS host (Windows works too via WSL2)

### Bring up the stack

```bash
git clone https://github.com/y-zahidi/home-lab-siem.git
cd home-lab-siem

# 1. Generate the Wazuh self-signed certs (one-shot)
./scripts/generate-certs.sh

# 2. Start the stack
docker compose up -d

# 3. Tail the logs and wait for "Server started" on the manager
docker compose logs -f wazuh.manager
```

### Access the dashboard

- URL: <https://localhost:443>
- Default user: `admin`
- Default password: `SecretPassword` (CHANGE THIS — see `docs/HARDENING.md`)

### Enroll an agent

```bash
# Linux example
curl -so wazuh-agent.deb \
  https://packages.wazuh.com/4.x/apt/pool/main/w/wazuh-agent/wazuh-agent_4.7.0-1_amd64.deb
sudo WAZUH_MANAGER='wazuh.manager' dpkg -i ./wazuh-agent.deb
sudo systemctl enable --now wazuh-agent
```

For Windows, see `docs/WINDOWS_AGENT.md` (covers Sysmon install + agent enrollment).

---

## Detections shipped in this repo

All custom rules live in [`config/wazuh/rules/local_rules.xml`](config/wazuh/rules/local_rules.xml). Each is mapped to a MITRE ATT&CK technique.

| Rule ID | Detection | MITRE ATT&CK |
|---------|-----------|--------------|
| 100100 | SSH brute-force (5+ failed attempts in 60 s) | T1110.001 — Password Guessing |
| 100101 | Suspicious PowerShell (encoded command, IEX, downloadstring) | T1059.001 — PowerShell |
| 100102 | Port scan from a single source (Suricata-based) | T1046 — Network Service Scanning |
| 100103 | File integrity violation in `/etc` or `C:\Windows\System32` | T1565.001 — Stored Data Manipulation |
| 100104 | Probable web shell upload (.php in `/uploads`, .aspx in `/wwwroot/uploads`) | T1505.003 — Web Shell |

Each rule has a corresponding playbook in [`docs/detections.md`](docs/detections.md):

- **What triggers it** (with sample log lines)
- **What you should see in the dashboard**
- **What an analyst should do next** (triage steps, escalation criteria, false-positive notes)

---

## Lessons learned

These are the actual takeaways from the production deployment, applied to this lab:

1. **Always tune out the noise on day 1.** Out-of-the-box Wazuh fires hundreds of alerts/hour from `sudo`, `cron`, and `systemd-logind`. The first PR I made on the Préfecture's repo was a tuning ruleset that filtered ~85% of the volume.
2. **Active Response is a foot-gun if you don't constrain it.** A typo in an `ip-blacklist` config can lock a SOC analyst out of the manager. Use it in audit-only mode for the first weeks.
3. **Self-signed certs work, but document the rotation.** Wazuh certs are valid 10 years out of the box, but the manager-to-indexer cert chain breaks silently if you reinstall one component. Keep a `scripts/generate-certs.sh` checked in.
4. **The dashboard is not a SOC.** A dashboard is a starting point. Real triage happens in tickets — plan the integration with Jira / GLPI / TheHive before go-live.

---

## Roadmap

- [x] Single-node Wazuh + Suricata + custom rules
- [x] 5 baseline detection rules with playbooks
- [ ] MISP integration (threat intel feeds)
- [ ] Active Response examples (audit-mode + production-mode)
- [ ] Windows agent + Sysmon SwiftOnSecurity ruleset
- [ ] Atomic Red Team simulation scripts (T1110.001, T1059.001)
- [ ] CI: lint Wazuh rule XML on every PR
- [ ] Helm chart for Kubernetes deployment

---

## License

MIT — see [LICENSE](LICENSE). The configurations are inspired by real production work at the Préfecture de Tétouan, but contain no sensitive material from that engagement.

---

## About me

I'm **Yassir Zahidi**, Computer Engineering student at ISMAGI (Rabat) with a 2-year Cybersecurity background (ISMO Tétouan). Currently looking for a **PFE / internship in cybersecurity, DevSecOps or IT infrastructure** for 2026.

- 🌐 [LinkedIn](https://www.linkedin.com/in/yassir-zahidi/)
- 📧 yassirzahidi8@gmail.com
- 💻 [github.com/y-zahidi](https://github.com/y-zahidi)
