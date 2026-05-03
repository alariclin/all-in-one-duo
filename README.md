# 📦 Aio-box

- **[📖 中文说明](#-中文说明) | [🌐 English Description](#-english-description)**
- **致谢:** 感谢开源社区中优秀的网络路由与加密项目（如 Xray-core、Sing-box、Hysteria 等）提供的底层技术启发与支持。本项目为独立的学习与自动化运维工具。
- Credits：Thanks to the excellent network routing and encryption projects in the open-source community (such as Xray-core, Sing-box, Hysteria, etc.) for providing the underlying technical inspiration and support. This project is an independent learning and automated operation and maintenance tool.

[![Version](https://img.shields.io/badge/Version-Apex_V56-success.svg?style=flat-square)]()
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg?style=flat-square)](https://opensource.org/licenses/MIT)
[![GitHub Stars](https://img.shields.io/github/stars/alariclin/aio-box?style=flat-square&color=yellow)](https://github.com/alariclin/aio-box/stargazers)
[![GitHub Forks](https://img.shields.io/github/forks/alariclin/aio-box?style=flat-square&color=orange)](https://github.com/alariclin/aio-box/network/members)

---

<a name="-中文说明"></a>

## 📖 中文说明

**Aio-box** 是一款专为 Linux 服务器设计的自动化网络加密隧道部署脚本。它集成了当前主流的网络安全代理协议（如 VLESS-Reality、Shadowsocks-2022、Hysteria 2 等），旨在帮助用户快速搭建安全、私密且高效的跨域数据传输环境，同时提供系统底层调优与防封锁自愈机制。

> ⚠️ 合规与免责声明：本项目定位为网络架构测试、网络安全研究与个人隐私保护的自动化部署工具。
> 1. 法律合规性：严禁利用本项目提供的脚本及技术手段从事任何违反所在国家或地区法律法规的活动。用户在使用本工具时，必须确保其行为符合当地电信管理、网络安全及互联网信息服务的相关规定。
> 2. 责任界定：本项目仅供授权环境下的技术交流、协议研究与合规的隐私安全加固使用。因用户违反法律法规、不当操作或滥用工具而产生的任何直接或间接法律责任、安全风险，均由使用者本人承担，项目开发者不承担任何连带责任。
> 3. 技术属性：本项目所涉及的加密协议与路由技术，旨在提升数据传输的安全性与私密性。严禁将本工具用于任何形式的非法攻击、非法跨境接入或其他危害网络基础设施安全的目的。
> 4. 最终解释权：下载、复制或运行本脚本即视为您已完全阅读、理解并同意本声明的所有条款。

---

### 📑 目录
1. [✨ 核心特性](#-features-cn)
2. [🏗️ 架构对比](#-arch-cn)
3. [🚀 快速部署](#-deploy-cn)
4. [🛠️ 运维与管理](#-ops-cn)

<a name="-features-cn"></a>
### ✨ 核心亮点

* **自动化加密隧道部署**: 一键自动化安装 VLESS-Reality、Hysteria 2、Shadowsocks 等主流安全传输协议。支持自定义 SNI 和标准服务端口的物理链路复用与高性能分发。
* **零信任资产校验体系**: 摒弃非官方镜像源，核心二进制文件强制启用 SHA-256 与 ELF/ZIP 幻数结构强校验，彻底阻断任何形式的供应链投毒攻击。
* **原生防阻断与端口跳跃**: 深度集成 Reality 架构与 uTLS 指纹模拟。完美融合 Hysteria 2 官方内核级端口跳跃（Port Hopping）与动态 iptables/ip6tables 转发，提升极端网络下的穿透存活率。
* **物理内核协议栈调优**: 自动注入并激活 BBR 拥塞控制算法，修复内核级 TCP KeepAlive。将系统 TCP 并发句柄及文件描述符提升至物理极限，彻底释放服务器带宽潜能。
* **环境自愈**: 依托原子化临时文件（mktemp）与 ss 精确端口抓取，脚本能在不伤及宿主机原有合规业务（如 Nginx/Docker）的前提下，实现精准的死锁清理与服务自愈。
* **自动化配额熔断机制**: 依托 vnstat 实时链路流量监控，支持预设月度流量使用阈值。在流量触顶时立刻触发服务原子级熔断保护，防止云服务超支。

---
<a name="-arch-cn"></a>
### 🏗️ 架构对比

本控制台提供两种顶级的运行架构，以满足不同资源与网络环境的需求：

| 特性维度 | 双核混编模式 (Xray-Hybrid) | 单核全能模式 (Sing-box) |
| :--- | :--- | :--- |
| **核心引擎** | Xray-core + 官方 Hysteria 2 | 纯 Sing-box 核心 |
| **设计哲学** | 极致隔离，物理级强强联手 | 极致轻量，聚合平台架构 |
| **资源占用** | 中等 (双进程常驻内存) | 极低 (单一进程极速调度) |
| **协议分配** | Xray 独占 TCP；Hy2 独占 UDP | Sing-box 内部虚拟分发 |
| **适用场景** | 追求绝对的吞吐量上限与极高并发 | 小内存机器 (如 256M/512M VPS) |
---
<a name="-deploy-cn"></a>
### 🚀 快速部署

无需手动切换用户，请直接在终端复制并执行以下一键安装指令（指令已物理纯化，可直接粘贴）：

**全球高速通道 (推荐海外服务器使用):**
```bash
curl -fsSL https://raw.githubusercontent.com/alariclin/aio-box/main/install.sh > aio.sh && sudo bash aio.sh
```
**分发加速镜像 (中国大陆机器推荐):**
```bash
curl -fsSL https://ghp.ci/https://raw.githubusercontent.com/alariclin/aio-box/main/install.sh > aio.sh && sudo bash aio.sh
```
---
<a name="-ops-cn"></a>
#### 🛠️ 运维与管理
安装完成后，在终端输入以下指令即可瞬间唤醒中控面板（支持离线唤醒）：
```bash
sb
```
---
### 📋面板菜单速览：

* **1-10: 核心架构编排** - 分别对应 Xray (1-5) 与 Sing-box (6-10) 的顶级加密协议组合。
* **11: 测速与 IP 审计** - 调用 bench.sh 与 Check.Place 检测 VPS 硬件性能与 IP 纯净度。
* **12: VPS 一键优化** - 物理注入 BBR 算法，提升并发句柄，并修复双向 TCP KeepAlive。
* **13: 节点参数显示** - 以明文高保真格式及 Clash Meta YAML / v2rayN JSON 格式输出当前拓扑配置。
* **14: 脚本说明书** - 详尽的协议工作原理、客户端对接指南与防坑说明。
* **15: OTA 升级与 Geo 资源** - 绕过本地缓存强制拉取 GitHub 远端源码热更新，及 Loyalsoldier Geo 路由数据闭环更替。
* **16: 一键清空卸载** - 提供物理级完全清场与保留脚本两种模式，彻底粉碎配置并逆向抹除 iptables 锚定规则。
* **17: 删除节点与环境初始化** - L4 内核套接字深度自愈，自动扫描进程死锁、清除脏路由表并重置系统环境。
* **18: 每月流量管控限制** - 基于网卡物理口径精确计算流量，支持到达阈值后的强行阻断机制。
* **19: SS-2022 白名单管理** - 支持 IPv4 与 IPv6 (CIDR) 双栈混合录入，动态新增/删除或开启全网 DROP，防御主动探测。

---
---

<a name="-english-description"></a>
## 🌐 Project Introduction

**Aio-box** It is an automated network encryption tunnel deployment script specifically designed for Linux servers. It integrates the current mainstream network security proxy protocols (such as VLESS-Reality, Shadowsocks-2022, Hysteria 2, etc.), aiming to help users quickly set up a secure, private and efficient cross-domain data transmission environment, while providing system-level optimization and anti-blockage self-healing mechanisms.

> ⚠️ Compliance & Disclaimer：This project is positioned as an automated tool for network architecture testing, cybersecurity research, and personal privacy protection.

> 1. Legal Compliance: It is strictly prohibited to use the scripts and technologies provided by this project for any activities that violate the laws and regulations of your country or region. Users must ensure their actions comply with local telecommunications, cybersecurity, and internet service regulations.
> 2. Limitation of Liability: This project is intended for technical exchange, protocol research, and legitimate privacy enhancement under authorized environments. The user shall bear full responsibility for any legal consequences or security risks arising from non-compliance or improper use. The developers shall not be held liable for any such actions.
> 3. Technical Intent: The encryption protocols and routing technologies involved are designed to enhance data transmission security. Use of this tool for illegal attacks, unauthorized network access, or endangering network infrastructure is strictly forbidden.
> 4. Acceptance of Terms: By downloading, copying, or running this script, you acknowledge that you have read, understood, and agreed to all terms of this disclaimer.

---

### 📑 Table of Contents
1. [✨ Key Features](#-key-features)
2. [🏗️ Architecture Comparison](#-architecture-comparison)
3. [🚀 Quick Start](#-quick-start)
4. [🛠️ Management & Operations](#-management--operations)

---
<a name="-key-features"></a>
### ✨ Key Features

* **Automated Encryption Tunnel Deployment**: Automatically install popular secure transmission protocols such as VLESS-Reality, Hysteria 2, and Shadowsocks with a single click. Supports custom SNI and physical link multiplexing of standard server ports.
* **Zero-Trust Asset Verification**: Abandons unofficial mirror sources. Core binaries forcefully enforce SHA-256 and ELF/ZIP magic number validation, completely blocking supply chain poisoning attacks.
* **Native Port Hopping & Mimicry**: Deeply integrates Reality architecture with uTLS fingerprint simulation. Perfectly merges Hysteria 2's official native port hopping with dynamic iptables/ip6tables forwarding to enhance survival rates in extreme network conditions.
* **Physical Kernel Protocol Stack Optimization**: Automatically injects and activates the BBR congestion control algorithm and fixes kernel-level TCP KeepAlive. Pushes the system's TCP concurrent handles and file descriptors to absolute limits.
* **Isolated L4 Probes & Self-Healing**: Utilizing atomic temporary files (mktemp) and precise port grabbing (ss), the script achieves accurate deadlock clearing without affecting existing legitimate processes (like Nginx/Docker).
* **Automated Quota Circuit Breaker**: Relying on vnstat's real-time link monitoring, it supports preset monthly traffic thresholds. Triggers an automatic atomic service shutdown when traffic reaches the limit to prevent cloud over-billing.

---
<a name="-architecture-comparison"></a>
### 🏗️ Architecture Comparison

The console provides two top-tier deployment architectures to meet different resource and network requirements:

| Dimension | Dual-Core Hybrid (Xray-Hybrid) | Single-Core Omni (Sing-box) |
| :--- | :--- | :--- |
| **Core Engines** | Xray-core + Official Hysteria 2 | Pure Sing-box Core |
| **Philosophy** | Physical Isolation, Best of Both | Lightweight, Unified Platform |
| **Resource Usage** | Moderate (Dual daemons resident) | Extremely Low (Fastest scheduling) |
| **Protocol Logic** | Xray for TCP; Native Hy2 for UDP | Internal Virtual Distribution |
| **Best For** | Maximum throughput & high concurrency | Low-RAM VPS (e.g., 256MB/512MB) |

---
<a name="-quick-start"></a>
### 🚀 Quick Start

**Global High-Speed Channel (Recommended for Overseas Servers):**
```bash
curl -fsSL https://raw.githubusercontent.com/alariclin/aio-box/main/install.sh > aio.sh && sudo bash aio.sh
```
<a name="-management--operations"></a>
#### 🛠️ Management
Once installation is complete, simply enter the following command in the terminal to instantly launch the Control Panel (offline launch supported):
```bash
sb
```
---
### 📋 Panel Menu Overview:

* **1-10: Core Architecture Arrangement** - Correspond to top-tier encryption deployments for Xray (1-5) and Sing-box (6-10).
* **11: Speed & IP Audit** - Calls bench.sh and Check.Place to detect VPS hardware performance and IP purity.
* **12: One-click VPS Optimization** - Physically injects BBR algorithm, enhances concurrent handles, and fixes bidirectional TCP KeepAlive.
* **13: View Node Parameters** - Outputs the current topology configuration in plaintext, Clash Meta YAML, and v2rayN JSON formats.
* **14: Script Manual** - Detailed protocol working principles, client docking guidelines, and pitfall avoidance.
* **15: OTA & Geo Update** - Bypasses local caches to forcefully pull GitHub remote source code for hot updates and seamlessly replaces Loyalsoldier Geo routing data.
* **16: One-click Uninstall** - Offers a physical-level complete clear mode to shatter configurations and reversely erase iptables anchor rules.
* **17: Delete Nodes & Initialization** - Deep self-healing of L4 kernel sockets, automatically scans for process deadlocks, clears dirty route tables, and resets the system environment.
* **18: Monthly Traffic Control** - Calculates traffic accurately based on physical NIC capacity, supporting forced blocking mechanisms upon reaching limits.
* **19: SS-2022 Whitelist Manager** - Supports IPv4 and IPv6 (CIDR) dual-stack mixed entry, dynamic addition/deletion, or turning on network-wide DROP to defend against active probing.

---

## 💻 系统要求 / System Requirements

* **操作系统 / OS**: Debian 10+, Ubuntu 20.04+, CentOS 8+, AlmaLinux, Rocky Linux, Alpine Linux.
* **初始化系统 / Init System**: 必须具备 **Systemd** 或 **OpenRC** 环境以支持守护进程 / **Systemd** or **OpenRC** is strictly required for daemon persistence.
* **网络环境 / Network**: 完整支持 **IPv4 / IPv6** 双栈解析 / Full **IPv4 / IPv6** dual-stack resolution supported.

## 🤝 反馈与交流 / Feedback & Support

如果您在使用过程中遇到任何问题或有改进建议，欢迎通过以下方式参与讨论：

If you encounter any issues or have suggestions, please join the discussion via:

* **[GitHub Issues](https://github.com/alariclin/aio-box/issues)**: 提交缺陷报告或新功能提议 / Submit bug reports or feature requests.

## 📄 许可证 / License

[![License](https://img.shields.io/badge/License-Apache_2.0-blue.svg)](LICENSE)

本项目采用的许可证授权是 **[Apache License 2.0](LICENSE)** 。

This project is licensed under the **[Apache License 2.0](LICENSE)**.
