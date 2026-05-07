# home-lab-siem

> Reproducible reference deployment of the multi-layer SIEM stack I worked
> with during my **cybersecurity internship at the Préfecture de Tétouan
> (SSIC, May 2024)**, packaged as a single docker-compose project so anyone
> can spin it up locally for study.

![Status](https://img.shields.io/badge/status-active-success)
![License](https://img.shields.io/badge/license-MIT-blue)
![Docker](https://img.shields.io/badge/Docker-Compose-2496ED?logo=docker&logoColor=white)
![Wazuh](https://img.shields.io/badge/Wazuh-4.7-005571?logo=wazuh&logoColor=white)
![Suricata](https://img.shields.io/badge/Suricata-7.0-EE0000)

---

## Scope

During my internship at the Préfecture de Tétouan, I worked on:

- Deploying a multi-layer **SIEM** with **Wazuh + Suricata + Sysmon + MISP +
  VirusTotal** for endpoint, network and threat-intel telemetry.
- Configuring and hardening a **FortiGate NGFW** in production (rule-base
  review, IPS profiles, SSL inspection, GeoIP filtering).
- Performing authenticated vulnerability scans with **Nessus** and internal
  pentests, with findings reported using **CVSS** scoring.

This repository is the **reproducible lab side** of that work: a clean
docker-compose stack that brings up Wazuh + Suricata locally, so I (and
anyone studying this stack) can practice deployment, agent enrollment and
dashboard navigation outside the production environment.

> **No real or sensitive data from the internship is included in this repo.**
> Production-only components (FortiGate VM, Nessus license, MISP feeds with
> sensitive IOCs) are not part of the lab; only the open-source SIEM core
> is shipped here.

---

## Stack shipped in this repo

| Layer | Component | Purpose |
|------|--------|-----|
| Log management & HIDS | **Wazuh manager + indexer + dashboard** | Log shipping, file integrity monitoring, rules engine |
| Network IDS | **Suricata** | EVE JSON output ingested by Wazuh |
| Endpoint telemetry (Windows) | **Sysmon** | Process / network / DNS visibility |
| Container orchestration | **Docker Compose** | Single-command spin-up |

Components from the production deployment that are **not** in this lab:

- **FortiGate NGFW** — requires a paid VM image; configuration patterns are
  documented but the firewall itself is not emulated locally.
- **MISP** — adds operational overhead; covered in `docs/` as an optional
  add-on, not bundled by default.
- **Nessus** — commercial scanner, run separately in production.

---

## Dashboard preview

The stack actually runs — these screenshots are from a live `docker compose
up` on this exact code:

| Login | Modules overview |
|:---:|:---:|
| ![Login](screenshots/01-login.png) | ![Modules](screenshots/02-modules-overview.png) |
| **MITRE ATT&CK Framework (built-in)** | **Rules management (4 372 built-in rules)** |
| ![MITRE](screenshots/03-mitre-attack-framework.png) | ![Rules](screenshots/04-rules-management.png) |
| **Manager status (all daemons green)** | **Administration view** |
| ![Status](screenshots/06-manager-status.png) | ![Admin](screenshots/05-management-admin.png) |

The MITRE ATT&CK mapping shown above is the **built-in Wazuh feature** — every
default Wazuh ruleset is already tagged with the relevant ATT&CK technique
out of the box.

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
                          │  Suricata (IDS, EVE JSON output)    │
                          └────────────────┬────────────────────┘
                                           │
                                           ▼
                       ┌──────────────────────────────────────────┐
                       │       Wazuh Manager (rule engine)        │
                       │  • Decoders + built-in rules             │
                       │  • Alerts → Wazuh Indexer (OpenSearch)   │
                       └────────────────┬─────────────────────────┘
                                        │
                                        ▼
                       ┌──────────────────────────────────────────┐
                       │   Wazuh Indexer (OpenSearch)             │
                       │   + Wazuh Dashboard (Kibana fork)        │
                       │   → analyst UI                           │
                       └──────────────────────────────────────────┘
```

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
- Default password: `SecretPassword` — **change before any real use**, see
  [`docs/HARDENING.md`](docs/HARDENING.md).

### Enroll a Linux agent

```bash
curl -so wazuh-agent.deb \
  https://packages.wazuh.com/4.x/apt/pool/main/w/wazuh-agent/wazuh-agent_4.7.0-1_amd64.deb
sudo WAZUH_MANAGER='wazuh.manager' dpkg -i ./wazuh-agent.deb
sudo systemctl enable --now wazuh-agent
```

For Windows endpoints, install the Wazuh agent and Sysmon with the
SwiftOnSecurity baseline.

---

## What this repo is NOT

- It is **not** a copy of the Préfecture's production deployment — that
  stays at the Préfecture.
- It does **not** contain custom detection rules tuned for that environment;
  the `config/wazuh/rules/local_rules.xml` shipped here is a placeholder and
  uses only the default Wazuh ruleset (4 000+ rules built-in, already
  MITRE ATT&CK-tagged).
- It is **not** production-hardened. See `docs/HARDENING.md` for the
  changes you would need before exposing it.

---

## Roadmap

- [x] Single-node Wazuh + Suricata stack via docker compose
- [x] Self-signed certs generation script
- [x] Live screenshots of the dashboard
- [ ] Documented MISP integration (optional add-on)
- [ ] Sysmon SwiftOnSecurity ruleset for Windows agents
- [ ] Atomic Red Team simulation walkthrough

---

## License

MIT — see [LICENSE](LICENSE). Inspired by real production work at the
Préfecture de Tétouan; contains no sensitive material from that engagement.

---

## About me

**Yassir Zahidi** — Computer Engineering Student & Specialized Technician
in Cybersecurity, based in Rabat, Morocco.

- LinkedIn: <https://linkedin.com/in/yassir-zahidi>
- GitHub: <https://github.com/y-zahidi>
- Email: yassirzahidi8@gmail.com
