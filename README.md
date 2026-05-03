<img width="459" height="427" alt="屏幕快照 2026-05-04 的 06 18 37 上午" src="https://github.com/user-attachments/assets/0a3b2ac1-1d05-4cae-968f-24c2a7bc9953" />
## 📦 A-Box


> One-click Linux Network Gateway Toolkit  
> Born May 1, 2026

- **[📖 中文说明](#-中文说明) | [🌐 English](#-english)**
- **Credits:** Thanks to Xray-core, sing-box, Hysteria, and related open-source projects for technical inspiration and ecosystem support. A-BOX is an independent automation toolkit.

[![Version](https://img.shields.io/badge/Version-2026.05.04-success.svg?style=flat-square)]()
[![License: Apache-2.0](https://img.shields.io/badge/License-Apache_2.0-blue.svg?style=flat-square)](LICENSE)
[![GitHub Stars](https://img.shields.io/github/stars/alariclin/A-BOX?style=flat-square&color=yellow)](https://github.com/alariclin/A-BOX/stargazers)
[![GitHub Forks](https://img.shields.io/github/forks/alariclin/A-BOX?style=flat-square&color=orange)](https://github.com/alariclin/A-BOX/network/members)

---

<a name="-中文说明"></a>

## 📖 中文说明

**A-BOX** 是一款面向 Linux 服务器的一键网络网关部署与运维工具箱。它把服务部署、系统调优、流量管理、访问控制、健康检查、参数导出、网络质量测试和双语交互集中到一个脚本内。

> ⚠️ 合规与免责声明：本项目定位为网络架构测试、网络安全研究与个人隐私保护的自动化部署工具。
> 1. 法律合规性：严禁利用本项目提供的脚本及技术手段从事任何违反所在国家或地区法律法规的活动。用户在使用本工具时，必须确保其行为符合当地电信管理、网络安全及互联网信息服务的相关规定。
> 2. 责任界定：本项目仅供授权环境下的技术交流、协议研究与合规的隐私安全加固使用。因用户违反法律法规、不当操作或滥用工具而产生的任何直接或间接法律责任、安全风险，均由使用者本人承担，项目开发者不承担任何连带责任。
> 3. 技术属性：本项目所涉及的加密协议与路由技术，旨在提升数据传输的安全性与私密性。严禁将本工具用于任何形式的非法攻击、非法跨境接入或其他危害网络基础设施安全的目的。
> 4. 最终解释权：下载、复制或运行本脚本即视为您已完全阅读、理解并同意本声明的所有条款。

---

## 🚀 快速部署

全球通道：

```bash
curl -fsSL https://raw.githubusercontent.com/alariclin/A-BOX/main/install.sh > A-BOX.sh && sudo bash A-BOX.sh
```

镜像通道：

```bash
curl -fsSL https://ghp.ci/https://raw.githubusercontent.com/alariclin/A-BOX/main/install.sh > A-BOX.sh && sudo bash A-BOX.sh
```

指定语言启动：

```bash
sudo bash A-BOX.sh --lang zh
sudo bash A-BOX.sh --lang en
```

静态自测：

```bash
sudo bash A-BOX.sh --self-test
```

安装后打开控制台：

```bash
sb
```

---

## ✨ 核心能力

| 模块 | 说明 |
| :--- | :--- |
| 一键部署 | 支持 Xray-core、sing-box、官方 Hysteria 2。 |
| 协议组合 | 支持 VLESS-Reality、VLESS-XHTTP-Reality、Shadowsocks-2022、Hysteria 2。 |
| 推荐端口 | Vision `443/TCP`，XHTTP `8443/TCP`，HY2 `443/UDP`，SS-2022 `2053/TCP+UDP`。 |
| SNI策略 | 443 默认 `www.apple.com`；非 443 默认 `www.microsoft.com`；非 443 使用 Apple/iCloud 类 SNI 会提示风险。 |
| XHTTP优化 | 默认导出 `stream-one + h2 + smux:false`。 |
| HY2模式 | 支持自有域名 ACME、自签证书 + 指纹锁定、端口跳跃、masquerade。 |
| 语言切换 | 首次运行选择中文/英文；菜单 `20` 可切换；支持 `--lang zh/en`。 |
| 工具箱 | 内置测速、IP检测、本地 SNI 测试、WARP 管理、2G Swap。 |
| 运维防护 | BBR/FQ、KeepAlive、Fail2Ban、logrotate、健康探针、Geo 更新、月流量管控、SS 白名单。 |
| 参数导出 | 输出 URI、二维码、Clash/Mihomo YAML、sing-box 出站示例、v2rayN/v2rayNG JSON。 |

---

## 🧩 菜单速览

| 菜单 | 功能 | 适用场景 |
| :--- | :--- | :--- |
| 1 | Xray Vision | 长期主力 TCP 通道。 |
| 2 | Xray XHTTP | 桌面高吞吐链路。 |
| 3 | Xray SS-2022 | 回程/落地入站，建议配合白名单。 |
| 4 | 官方 HY2 | UDP/QUIC/H3，适合移动和丢包链路。 |
| 5 | Xray + 官方 HY2 四合一 | 综合模式：Vision + XHTTP + HY2 + SS-2022。 |
| 6 | sing-box Vision | 低内存 Vision 部署。 |
| 7 | sing-box SS-2022 | 低内存 SS-2022 部署。 |
| 8 | sing-box Vision + SS-2022 | 轻量双协议组合。 |
| 9 | sing-box HY2 | sing-box 承载 HY2。 |
| 10 | sing-box 三合一 | Vision + HY2 + SS-2022，不含 XHTTP。 |
| 11 | 综合工具箱 | 测速、IP检测、SNI测试、WARP、Swap。 |
| 12 | VPS 优化 | BBR/FQ、句柄、KeepAlive、防护与探针。 |
| 13 | 参数显示 | 查看链接、二维码和客户端配置。 |
| 14 | 脚本说明书 | 查看完整功能说明。 |
| 15 | OTA / Geo 更新 | 更新脚本和 Geo 数据。 |
| 16 | 卸载清理 | 删除服务、配置和防火墙规则。 |
| 17 | 环境初始化 | 清理残留进程、规则和破损配置。 |
| 18 | 月流量管控 | vnStat 统计，超额自动停止服务。 |
| 19 | SS-2022 白名单 | 只允许指定前置 IP/CIDR 访问。 |
| 20 | 语言设置 | 中文/英文切换。 |

---

## 🧰 综合工具箱

| 子菜单 | 功能 |
| :--- | :--- |
| 1 | bench.sh：基础硬件与下载测速。 |
| 2 | Check.Place：IP质量、区域服务和路由检测。 |
| 3 | 本地 SNI 测试：对 100 个常见域名测试 DNS、TCP、TLS、TTFB。 |
| 4 | Cloudflare WARP：调用 WARP 管理脚本处理出站网络。 |
| 5 | 2G Swap：创建 `/swapfile`，降低小内存机器 OOM 风险。 |

---

## 🏗️ 推荐组合

| 目标 | 推荐 |
| :--- | :--- |
| 综合模式 | 菜单 `5`：Xray + 官方 HY2 四合一。 |
| 低内存模式 | 菜单 `10`：sing-box 三合一。 |
| 长期主力 | Vision `443/TCP`。 |
| 高吞吐备用 | XHTTP `8443/TCP`。 |
| 移动/丢包链路 | HY2 `443/UDP`。 |
| 前置回程 | SS-2022 `2053/TCP+UDP` + 白名单。 |

---

## 💻 系统要求

| 项目 | 要求 |
| :--- | :--- |
| 系统 | Debian 10+、Ubuntu 20.04+、CentOS/RHEL/Rocky/AlmaLinux 8+、Alpine Linux。 |
| 初始化系统 | Systemd 或 OpenRC。 |
| CPU | amd64 / x86_64，arm64 / aarch64。 |
| 权限 | root 或 sudo。 |
| 网络 | 可访问系统软件源和 GitHub Release。 |

---

<a name="-english"></a>

## 🌐 English

**A-BOX** is a one-click Linux network gateway automation toolkit. It combines service deployment, system tuning, traffic control, access management, health checks, parameter export, network quality testing, and bilingual UI into a single script.

> ⚠️ Compliance & Disclaimer: This project is positioned as an automated tool for network architecture testing, cybersecurity research, and personal privacy protection.
> 1. Legal Compliance: It is strictly prohibited to use the scripts and technologies provided by this project for any activities that violate the laws and regulations of your country or region. Users must ensure their actions comply with local telecommunications, cybersecurity, and internet service regulations.
> 2. Limitation of Liability: This project is intended for technical exchange, protocol research, and legitimate privacy enhancement under authorized environments. The user shall bear full responsibility for any legal consequences or security risks arising from non-compliance or improper use. The developers shall not be held liable for any such actions.
> 3. Technical Intent: The encryption protocols and routing technologies involved are designed to enhance data transmission security. Use of this tool for illegal attacks, unauthorized network access, or endangering network infrastructure is strictly forbidden.
> 4. Acceptance of Terms: By downloading, copying, or running this script, you acknowledge that you have read, understood, and agreed to all terms of this disclaimer.

### Quick Start

```bash
curl -fsSL https://raw.githubusercontent.com/alariclin/A-BOX/main/install.sh > A-BOX.sh && sudo bash A-BOX.sh
```

Mirror:

```bash
curl -fsSL https://ghp.ci/https://raw.githubusercontent.com/alariclin/A-BOX/main/install.sh > A-BOX.sh && sudo bash A-BOX.sh
```

Language:

```bash
sudo bash A-BOX.sh --lang zh
sudo bash A-BOX.sh --lang en
```

Self-test:

```bash
sudo bash A-BOX.sh --self-test
```

Launcher after installation:

```bash
sb
```

### Key Features

| Module | Description |
| :--- | :--- |
| Deployment | Xray-core, sing-box, and official Hysteria 2. |
| Protocols | VLESS-Reality, VLESS-XHTTP-Reality, Shadowsocks-2022, Hysteria 2. |
| Default ports | Vision `443/TCP`, XHTTP `8443/TCP`, HY2 `443/UDP`, SS-2022 `2053/TCP+UDP`. |
| SNI policy | Port 443 defaults to `www.apple.com`; non-443 defaults to `www.microsoft.com`; Apple/iCloud-like non-443 SNI triggers a warning. |
| XHTTP | Exports `stream-one + h2 + smux:false`. |
| Toolbox | Benchmark, IP check, local SNI benchmark, WARP manager, 2G Swap. |
| Operations | BBR/FQ, KeepAlive, Fail2Ban, logrotate, health probe, Geo update, monthly quota cutoff, SS whitelist. |
| Export | URI, QR, Clash/Mihomo YAML, sing-box outbound examples, v2rayN/v2rayNG JSON. |

### Menu Summary

| Menu | Function |
| :--- | :--- |
| 1-5 | Xray / official HY2 deployment modes. |
| 6-10 | sing-box deployment modes. |
| 11 | Toolbox. |
| 12 | VPS optimization. |
| 13 | Display node parameters. |
| 14 | Manual. |
| 15 | OTA and Geo update. |
| 16 | Uninstall. |
| 17 | Environment reset. |
| 18 | Monthly traffic limit. |
| 19 | SS-2022 whitelist. |
| 20 | Language switch. |

---

## 🤝 Feedback

- [GitHub Issues](https://github.com/alariclin/A-BOX/issues)

---

## 📄 License

This project is licensed under the [Apache License 2.0](LICENSE).
