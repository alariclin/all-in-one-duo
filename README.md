# 📦 Aio-box Ultimate Console

- **[📖 中文说明](#-中文说明) | [🌐 English Description](#-english-description)**
- **致谢 / Credits:** 感谢开源社区中优秀的网络路由与加密项目（如 Xray-core、Sing-box、Hysteria 等）提供的底层技术启发与支持。本项目为独立的学习与自动化运维工具。 / We express our gratitude to excellent open-source projects for their technical inspiration. This project is an independent tool for learning and automated deployment.

[![Version](https://img.shields.io/badge/Version-Apex_V56-success.svg?style=flat-square)]()
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg?style=flat-square)](https://opensource.org/licenses/MIT)
[![GitHub Stars](https://img.shields.io/github/stars/alariclin/aio-box?style=flat-square&color=yellow)](https://github.com/alariclin/aio-box/stargazers)
[![GitHub Forks](https://img.shields.io/github/forks/alariclin/aio-box?style=flat-square&color=orange)](https://github.com/alariclin/aio-box/network/members)

---

<a name="-中文说明"></a>

## 📖 中文说明

**Aio-box** 是一款企业级、专注于 Linux 服务器网络环境配置、安全加固与路由优化的自动化运维环境。本项目旨在通过高保真的自动化脚本，解决异构网络协议栈在同一宿主机下的并发与冲突问题。内置系统参数极限调优与独创的“白盒自愈”机制，是网络安全研究、全栈技术测试及自动化 DevOps 管理的极佳脚手架。

> **⚠️ 合规与免责声明 (Disclaimer)**: 本项目仅供网络架构学习、加密协议研究和技术交流使用。严禁用于任何非法用途。用户在使用本脚本时必须严格遵守其所在国家和地区的法律法规，任何因违反法规或不当使用造成的直接/间接后果，由使用者自行承担。

### 📑 目录
1. [✨ 核心特性](#-核心特性)
2. [🏗️ 架构对比](#-架构对比)
3. [🚀 快速部署](#-快速部署)
4. [🛠️ 运维与管理](#-运维与管理)
5. [❓ 常见问题 (FAQ)](#-常见问题)

### ✨ 核心特性

* **全栈协议整合与端口拟态**: 自动化部署最新一代网络路由核心（VLESS-Vision、Hysteria 2、Shadowsocks），支持复杂的协议栈整合。通过内核级转发，实现同一物理端口（如 443）的高效复用与拟态伪装。
* **Auto-Fix 终极环境自愈引擎**: 针对复杂或被污染的宿主环境，脚本内置白盒级原子诊断。一键释放寻址层死锁端口、抹除脏防火墙规则（精准狙击废弃的 NAT/INPUT 链，绝对保护 Docker 容器路由池），并将系统网络状态恢复至绝对纯净的“出厂态”。
* **Linux 物理内核算力释放**: 摒弃表层优化，脚本直击 Linux 内核参数。一键重载 BBR 拥塞控制算法，并智能将底层 TCP 窗口、文件描述符 (`fs.file-max`) 和最大并发限制 (`ulimit`) 拉升至 `1,048,576` 的物理极限。
* **高优测速与信誉审计**: 面板深度集成全球公认的基准测试组件：`bench.sh`（全面评估 CPU、I/O 与国际网关速率）与 `Check.Place`（深入探查 IP 的欺诈评分与原生解锁纯净度）。
* **无痕清场与原子级 OTA**: 提供零残留的“外科手术级卸载”机制，绝不残留暗病。支持从 GitHub 云端秒级热更新（OTA），确保底层架构永远保持最新。

### 🏗️ 架构对比

本控制台提供两种顶级的运行架构，以满足不同资源与网络环境的需求：

| 特性维度 | 🚀 双核混编模式 (Xray-Hybrid) | ⚡ 单核全能模式 (Sing-box) |
| :--- | :--- | :--- |
| **核心引擎** | Xray-core + 官方 Hysteria 2 | 纯 Sing-box 核心 |
| **设计哲学** | 极致隔离，物理级强强联手 | 极致轻量，聚合平台架构 |
| **资源占用** | 中等 (双进程常驻内存) | 极低 (单一进程极速调度) |
| **协议分配** | Xray 独占 TCP；Hy2 独占 UDP | Sing-box 内部虚拟分发 |
| **适用场景** | 追求绝对的吞吐量上限与极高并发 | 小内存机器 (如 256M/512M VPS) |


### 🚀 快速部署

无需手动切换用户，请直接在终端复制并执行以下一键安装指令（指令已物理纯化，可直接粘贴）：

**全球高速通道 (推荐海外服务器使用):**
```bash
sudo bash -c "$(curl -Ls https://raw.githubusercontent.com/alariclin/aio-box/main/install.sh)"
```

**分发加速镜像 (中国大陆机器推荐):**
```bash
sudo bash -c "$(curl -Ls https://ghp.ci/https://raw.githubusercontent.com/alariclin/aio-box/main/install.sh)"
```
#### ⚡ 全局管理
安装完成后，在终端输入以下指令即可瞬间唤醒中控面板（支持离线唤醒）：
```bash
sb
```
<a name="-english-description"></a>

## English Description

**Aio-box is an automated operations script focused on Linux server network environment configuration, security hardening, and routing optimization. This project aims to simplify the complex deployment of network protocol stacks (such as TCP/UDP multiplexing) through one-click execution. It also provides low-level system parameter tuning and environmental self-diagnostic repair features, making it suitable for network security research, technical testing, and automated server management.

Disclaimer: This project is intended strictly for educational, research, and technical exchange purposes. Users must comply with the laws and regulations of their respective countries and regions when using this script. The user bears full responsibility for any consequences arising from improper use.

### ✨ Key Features
* Modern Network Protocol Integration: Automates the deployment of next-generation routing cores (supporting protocols like VLESS, Hysteria 2, and Shadowsocks), achieving efficient port multiplexing (e.g., concurrent TCP and UDP on a single port) to optimize connection efficiency.
* High Availability & Process Isolation: Offers flexible Dual-Core (Hybrid) or Single-Core (Sing-box) deployment modes. The script logically isolates different service processes to effectively prevent port conflicts (deadlocks) and ensure continuous service operation.
* Auto-Fix Environmental Diagnostics: Features an innovative white-box diagnostic mechanism. With a single click, it identifies and purges zombie processes, resolves port deadlocks, clears erroneous network forwarding rules, and restores the system's network configuration to a pristine state.
* Linux Kernel Performance Unleashed: Includes an automated tuning module that enables the BBR congestion control algorithm and intelligently elevates system resource limits (e.g., adjusting file descriptors fs.file-max and ulimit to their maximum theoretical values) to maximize network throughput.
* Comprehensive Benchmarking: Integrates hardware performance testing (bench.sh) and global IP quality/reputation auditing tools to help users monitor their server's performance and status.
* Seamless OTA Updates & Secure Uninstallation: Supports real-time retrieval and updating of the latest script code from GitHub. Provides two uninstallation modes: a "zero-residue nuclear wipe" and a "soft uninstall" that retains environment variables, ensuring system integrity.
* Cross-Platform Daemon Compatibility: Intelligently identifies and seamlessly integrates with major Linux initialization systems (Systemd and OpenRC), offering broad support for mainstream Linux distributions and lightweight systems (such as Alpine).

### 🚀 Quick Start

**Global High-Speed Channel (Recommended for Overseas Servers):**
```bash
sudo bash -c "$(curl -Ls https://raw.githubusercontent.com/alariclin/aio-box/main/install.sh)"
```
#### ⚡ Global Management
Once installation is complete, simply enter the following command in the terminal to instantly launch the Control Panel (offline launch supported):
```bash
sb
```
## ⚠️ 系统要求 / System Requirements
*OS: Debian 10+, Ubuntu 20.04+, CentOS 8+, AlmaLinux, Rocky Linux, Alpine Linux (Full Support).
*Init System: Systemd or OpenRC is strictly required for daemon persistence.
*Network: Dual-stack IPv4 / IPv6 resolution fully supported.

## 🤝 反馈与交流 / Feedback & Support
If you encounter any issues or have suggestions, please submit them via:
* [GitHub Issues](https://github.com/alariclin/all-in-one-duo/issues)

## 📄 许可证 / License
Released under the [MIT License](https://opensource.org/licenses/MIT).
