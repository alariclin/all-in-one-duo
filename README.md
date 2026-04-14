# 📦 Aio-box

- **[📖 中文说明](#-中文说明) | [🌐 English Description](#-english-description)**
- **致谢 / Credits:** 感谢开源社区中优秀的网络路由与加密项目（如 Xray-core、Sing-box、Hysteria 等）提供的底层技术启发与支持。本项目为独立的学习与自动化运维工具。 / We express our gratitude to excellent open-source projects for their technical inspiration. This project is an independent tool for learning and automated deployment.

[![Version](https://img.shields.io/badge/Version-Apex_V56-success.svg?style=flat-square)]()
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg?style=flat-square)](https://opensource.org/licenses/MIT)
[![GitHub Stars](https://img.shields.io/github/stars/alariclin/aio-box?style=flat-square&color=yellow)](https://github.com/alariclin/aio-box/stargazers)
[![GitHub Forks](https://img.shields.io/github/forks/alariclin/aio-box?style=flat-square&color=orange)](https://github.com/alariclin/aio-box/network/members)

---

<a name="-中文说明"></a>

## 📖 中文说明

**Aio-box** 是一款专为 Linux 服务器设计的自动化网络加密隧道部署脚本。它集成了当前主流的网络安全代理协议（如 VLESS-Reality、Shadowsocks-2022、Hysteria 2 等），旨在帮助用户快速搭建安全、私密且高效的跨域数据传输环境，同时提供系统底层调优与防封锁自愈机制。

> ⚠️ 合规与免责声明：本项目定位为网络架构测试、网络安全研究与个人隐私保护的自动化部署工具。
> 1. 法律合规性 (Legal Compliance)：严禁利用本项目提供的脚本及技术手段从事任何违反所在国家或地区法律法规的活动。用户在使用本工具时，必须确保其行为符合当地电信管理、网络安全及互联网信息服务的相关规定。
> 2. 责任界定 (Liability)：本项目仅供授权环境下的技术交流、协议研究与合规的隐私安全加固使用。因用户违反法律法规、不当操作或滥用工具而产生的任何直接或间接法律责任、安全风险，均由使用者本人承担，项目开发者不承担任何连带责任。
> 3. 技术属性 (Technical Purpose)：本项目所涉及的加密协议与路由技术，旨在提升数据传输的安全性与私密性。严禁将本工具用于任何形式的非法攻击、非法跨境接入或其他危害网络基础设施安全的目的。
> 4. 最终解释权 (Final Interpretation)：下载、复制或运行本脚本即视为您已完全阅读、理解并同意本声明的所有条款。

---

### 📑 目录
1. [✨ 核心特性](#-features-cn)
2. [🏗️ 架构对比](#-arch-cn)
3. [🚀 快速部署](#-deploy-cn)
4. [🛠️ 运维与管理](#-ops-cn)

<a name="-features-cn"></a>
### ✨ 核心特性

* **一键全栈加密协议部署**: 自动化配置最新一代安全代理协议。通过 Xray-core 或 Sing-box 引擎，实现 VLESS-Vision 伪装、Shadowsocks-2022 高强加密以及 Hysteria 2 UDP 暴力穿透，支持单端口多协议复用。
* **终极环境自愈引擎**: 内置白盒级诊断机制。一键释放死锁端口，精准抹除可能导致暴露的废弃防火墙规则，确保代理环境纯净稳定。
* **物理级网络算力释放**: 深度优化 Linux 内核参数。一键激活 BBR 拥塞控制算法，大幅提升 TCP 并发上限，压榨服务器每一滴网络性能。
* **高优测速与信誉审计**: 集成 `bench.sh` 和 `Check.Place`，全面评估 VPS 物理性能及 IP 的欺诈评级与纯净度。
* **OTA热更新与无痕清场**: 支持脚本源码无损热更新，并提供“核弹级”卸载模式，彻底清除所有节点配置和防火墙痕迹，不留后门。

---
<a name="-arch-cn"></a>
### 🏗️ 架构对比

本控制台提供两种顶级的运行架构，以满足不同资源与网络环境的需求：

| 特性维度 | 🚀 双核混编模式 (Xray-Hybrid) | ⚡ 单核全能模式 (Sing-box) |
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
curl -fsSL https://raw.githubusercontent.com/alariclin/aio-box/main/install.sh | sudo bash
```

**分发加速镜像 (中国大陆机器推荐):**
```bash
curl -fsSL https://ghp.ci/https://raw.githubusercontent.com/alariclin/aio-box/main/install.sh | sudo bash
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
* 1-10: 核心架构编排 - 分别对应 Xray (1-5) 与 Sing-box (6-10) 的部署组合。
* 11: 测速与 IP 审计 - 调用 bench.sh 与 Check.Place 检测 VPS 性能与 IP 欺诈分。
* 12: VPS 一键优化 - 物理注入 BBR 算法并提升内核并发句柄。
* 13: 节点参数显示 - 以明文及 Clash Meta YAML 格式输出当前配置。
* 14: 脚本说明书 - 所有功能详细解释避坑指南。
* 15: 脚本OTA升级与Geo资源更新 - 绕过缓存同步 GitHub 远端源码，实现脚本无损热更新。
* 16: 一键清空 - 提供物理级完全清场模式，彻底粉碎节点、配置与防火墙规则。
* 17: 环境自愈 - 扫描死锁、清理脏路由、连通性探测。
* 18: 流量管控 - 基于 vnstat 监控流量，支持到达月度阈值后自动熔断服务以防超支。

---
---

<a name="-english-description"></a>
## 🌐 Project Introduction

**Aio-box** It is an automated network encryption tunnel deployment script specifically designed for Linux servers. It integrates the current mainstream network security proxy protocols (such as VLESS-Reality, Shadowsocks-2022, Hysteria 2, etc.), aiming to help users quickly set up a secure, private and efficient cross-domain data transmission environment, while providing system-level optimization and anti-blockage self-healing mechanisms.

> **⚠️ Compliance & Disclaimer**: This project is positioned as a tool for enterprise-level network architecture testing, cybersecurity research, and personal privacy protection. It is strictly prohibited to use this script for any activities that violate the laws and regulations of the country or region where you are located. Users must bear all direct and indirect legal responsibilities arising from improper use on their own.

---

### 📑 Table of Contents
1. [✨ Key Features](#-key-features)
2. [🏗️ Architecture Comparison](#-architecture-comparison)
3. [🚀 Quick Start](#-quick-start)
4. [🛠️ Management & Operations](#-management--operations)

---
<a name="-key-features"></a>
### ✨ Key Features

* **One-click Full-stack Encryption Protocol Deployment**: Automate the configuration of the latest generation of secure proxy protocols. Through the Xray-core or Sing-box engine, achieve VLESS-Vision camouflage, Shadowsocks-2022 high-strength encryption, and Hysteria 2 UDP brute-force penetration, supporting multi-protocol multiplexing on a single port.
* **Ultimate Environment Self-healing Engine**: Built-in white-box level diagnostic mechanism. One-click release of deadlocked ports, precisely erase abandoned firewall rules that may lead to exposure, ensuring a clean and stable proxy environment.
* **Physical-level Network Computing Power Release**: Deeply optimize Linux kernel parameters. One-click activation of the BBR congestion control algorithm, significantly increasing the TCP concurrent upper limit, squeezing every bit of network performance from the server.
* **High-quality Speed Testing and Reputation Audit**: Integrated with `bench.sh` and `Check.Place`, comprehensively assess the physical performance of VPS and the fraud rating and purity of IP addresses.
* **OTA Hot Update and Traceless Cleanup**: Supports lossless hot update of script source code and provides a "nuclear-level" uninstallation mode, thoroughly removing all node configurations and firewall traces, leaving no backdoors.

---
<a name="-architecture-comparison"></a>
### 🏗️ Architecture Comparison

The console provides two top-tier deployment architectures to meet different resource and network requirements:

| Dimension | 🚀 Dual-Core Hybrid (Xray-Hybrid) | ⚡ Single-Core Omni (Sing-box) |
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
curl -fsSL https://raw.githubusercontent.com/alariclin/aio-box/main/install.sh | sudo bash
```
<a name="-management--operations"></a>
#### 🛠️ Management
Once installation is complete, simply enter the following command in the terminal to instantly launch the Control Panel (offline launch supported):
```bash
sb
```
---
### 📋 Panel Menu Overview:
* **1-10**: Core Architecture Arrangement - Corresponding to the deployment combinations of Xray (1-5) and Sing-box (6-10).
* **11**: Speed Measurement and IP Audit - Calling bench.sh and Check.Place to detect VPS performance and IP fraud scores.
* **12**: One-click VPS Optimization - Physically inject BBR algorithm and enhance kernel concurrent handles.
* **13**: Node Parameter Display - Outputs current topology configuration in plain text and Clash Meta YAML format.
* **14**: Script Manual - Detailed explanations of all functions and a guide to avoid pitfalls.
* **15**: Script OTA & Geo Resource Update - Overcomes cache synchronization and synchronizes remote source code from GitHub to achieve lossless hot update of the script.
* **16**:  One-click Clearing - Provides a physical-level complete clearance mode to completely destroy nodes, configurations, and firewall rules.
* **17**: Environment Self-healing - Scans for deadlocks, cleans up dirty routes, and conducts connectivity detection.
* **18**: Traffic Control - Monitors traffic based on vnstat and supports automatic service disconnection upon reaching monthly thresholds to prevent over-consumption.

---

## 💻 系统要求 / System Requirements
* **OS**: Debian 10+, Ubuntu 20.04+, CentOS 8+, AlmaLinux, Rocky Linux, Alpine Linux (Full Support).
* **Init System**: Systemd or OpenRC is strictly required for daemon persistence.
* **Network**: Dual-stack IPv4 / IPv6 resolution fully supported.

## 🤝 反馈与交流 / Feedback & Support
If you encounter any issues or have suggestions, please submit them via:
* [GitHub Issues](https://github.com/alariclin/aio-box/issues)
## 📄 许可证 / License
Released under the [MIT License](https://opensource.org/licenses/MIT).
