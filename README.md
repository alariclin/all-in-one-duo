[English](README.md) | [简体中文](README-zh.md) | [Русский](README-ru.md) | [فارسی](README-fa.md)

<img width="620" height="705" alt="屏幕快照 2026-05-06 的 00 11 48 上午" src="https://github.com/user-attachments/assets/d4292198-ae7d-46c0-89de-4543643d7229" />





> One-click Linux Network Gateway Toolkit  

**A-Box** is a one-click Linux network gateway automation toolkit. It combines service deployment, system tuning, traffic control, access management, health checks, parameter export, network quality testing, and a multilingual terminal UI into a single script.

**Credits:** Thanks to Xray-core, sing-box, Hysteria, and related open-source projects for technical inspiration and ecosystem support. A-Box is an independent automation toolkit.

[![Version](https://img.shields.io/badge/Version-2026.05.04-success.svg?style=flat-square)]()
[![License: Apache-2.0](https://img.shields.io/badge/License-Apache_2.0-blue.svg?style=flat-square)](LICENSE)
[![GitHub Stars](https://img.shields.io/github/stars/alariclin/a-box?style=flat-square&color=yellow)](https://github.com/alariclin/a-box/stargazers)
[![GitHub Forks](https://img.shields.io/github/forks/alariclin/a-box?style=flat-square&color=orange)](https://github.com/alariclin/a-box/network/members)

---

## Compliance & Disclaimer

This project is intended for network architecture testing, cybersecurity research, and legitimate privacy protection in authorized environments.

1. **Legal compliance:** Do not use this project for any activity that violates laws or regulations in your country or region.
2. **User responsibility:** Users are fully responsible for legal, operational, and security consequences caused by misuse or improper operation.
3. **Technical intent:** The routing and encryption technologies involved are intended to improve data transmission security and privacy. Do not use this tool for illegal attacks, unauthorized access, or harm to network infrastructure.
4. **Acceptance:** Downloading, copying, or running this script means that you have read, understood, and accepted these terms.

---

## Quick Start

Global channel:

```bash
curl -fsSL https://raw.githubusercontent.com/alariclin/a-box/main/install.sh > A-Box.sh && sudo bash A-Box.sh
```

Mirror channel:

```bash
curl -fsSL https://ghp.ci/https://raw.githubusercontent.com/alariclin/a-box/main/install.sh > A-Box.sh && sudo bash A-Box.sh
```

Language selection:

```bash
sudo bash A-Box.sh --lang zh
sudo bash A-Box.sh --lang en
```

Self-test and status:

```bash
sudo bash A-Box.sh --self-test
sudo bash A-Box.sh --status
```

Open the console after installation:

```bash
sb
```

---

## Key Features

| Module | Description |
| :--- | :--- |
| One-click deployment | Supports Xray-core, sing-box, and official Hysteria 2. |
| Protocol set | VLESS-Reality, VLESS-XHTTP-Reality, Shadowsocks-2022, Hysteria 2. |
| Recommended ports | Vision `443/TCP`, XHTTP `8443/TCP`, HY2 `443/UDP`, SS-2022 `2053/TCP+UDP`. |
| SNI policy | Port 443 defaults to `www.apple.com`; non-443 defaults to `www.microsoft.com`; Apple/iCloud-like non-443 SNI triggers a warning. |
| XHTTP export | Exports `stream-one + h2 + smux:false`. |
| HY2 modes | ACME domain certificate, self-signed certificate with pinning, port hopping, masquerade. |
| Toolbox | Benchmark, IP check, local SNI test, WARP manager, 2G Swap. |
| Operations | BBR/FQ, KeepAlive, Fail2Ban, logrotate, health probe, Geo update, monthly quota cutoff, SS whitelist, `--status`. |
| Export formats | URI, QR, Clash/Mihomo YAML, sing-box outbound examples, v2rayN/v2rayNG JSON. |
| Deployment switch protection | Installing a new core stops managed old services first; full removal is available from menu 16. |

---

## Menu Summary

| Menu | Function | Use case |
| :--- | :--- | :--- |
| 1 | Xray Vision | Long-term primary TCP path. |
| 2 | Xray XHTTP | High-throughput desktop path. |
| 3 | Xray SS-2022 | Relay / landing inbound; whitelist recommended. |
| 4 | Official HY2 | UDP / QUIC / H3 path for mobile or lossy links. |
| 5 | Xray + official HY2 all-in-one | Vision + XHTTP + HY2 + SS-2022. |
| 6 | sing-box Vision | Low-memory Vision deployment. |
| 7 | sing-box SS-2022 | Low-memory SS-2022 deployment. |
| 8 | sing-box Vision + SS-2022 | Lightweight two-protocol setup. |
| 9 | sing-box HY2 | HY2 on sing-box. |
| 10 | sing-box all-in-one | Vision + HY2 + SS-2022; no XHTTP. |
| 11 | Toolbox | Benchmark, IP check, SNI test, WARP, Swap. |
| 12 | VPS optimization | BBR/FQ, file limits, KeepAlive, protection, probes. |
| 13 | Display node parameters | Links, QR codes, and client configs. |
| 14 | Manual | Full terminal help. |
| 15 | OTA / Geo update | Update script and Geo data. |
| 16 | Uninstall | Remove services, configs, and firewall rules. |
| 17 | Environment reset | Clean stale processes, rules, and broken configs. |
| 18 | Monthly traffic control | vnStat-based traffic cutoff. |
| 19 | SS-2022 whitelist | Allow only specified frontend IP/CIDR. |
| 20 | Language | Chinese / English UI switch. |

---

## Toolbox

| Submenu | Function |
| :--- | :--- |
| 1 | bench.sh: hardware and download benchmark. |
| 2 | Check.Place: IP quality, regional service, and route check. |
| 3 | Local SNI test: DNS, TCP, TLS, and TTFB test for 100 common domains. |
| 4 | Cloudflare WARP: run WARP manager for outbound network handling. |
| 5 | 2G Swap: create `/swapfile` to reduce OOM risk on low-memory hosts. |

---

## Recommended Setups

| Goal | Recommended option |
| :--- | :--- |
| Balanced setup | Menu `5`: Xray + official HY2 all-in-one. |
| Low-memory setup | Menu `10`: sing-box all-in-one. |
| Primary TCP path | Vision `443/TCP`. |
| High-throughput backup | XHTTP `8443/TCP`. |
| Mobile / lossy network | HY2 `443/UDP`. |
| Relay / landing path | SS-2022 `2053/TCP+UDP` + whitelist. |

---

## System Requirements

| Item | Requirement |
| :--- | :--- |
| OS | Debian 10+, Ubuntu 20.04+, CentOS/RHEL/Rocky/AlmaLinux 8+, Alpine Linux. |
| Init system | Systemd or OpenRC. |
| CPU | amd64 / x86_64, arm64 / aarch64. |
| Privilege | root or sudo. |
| Network | Access to system package repositories and GitHub Releases. |

---

## Feedback

- [GitHub Issues](https://github.com/alariclin/a-box/issues)

---

## License

This project is licensed under the [Apache License 2.0](LICENSE).
