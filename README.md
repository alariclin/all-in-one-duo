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

**Aio-box** 是一款企业级、专注于 Linux 服务器网络环境配置、安全加固与路由优化的自动化运维环境。本项目旨在通过高保真的自动化脚本，解决异构网络协议栈在同一宿主机下的并发与冲突问题。内置系统参数极限调优与独创的“白盒自愈”机制，是网络安全研究、全栈技术测试及自动化 DevOps 管理的极佳脚手架。

> **⚠️ 合规与免责声明 (Disclaimer)**: 本项目仅供网络架构学习、加密协议研究和技术交流使用。严禁用于任何非法用途。用户在使用本脚本时必须严格遵守其所在国家和地区的法律法规，任何因违反法规或不当使用造成的直接/间接后果，由使用者自行承担。

### 📑 目录
1. [✨ 核心特性](#-features-cn)
2. [🏗️ 架构对比](#-arch-cn)
3. [🚀 快速部署](#-deploy-cn)
4. [🛠️ 运维与管理](#-ops-cn)
5. [❓ 常见问题 (FAQ)](#-faq-cn)

<a name="-features-cn"></a>
### ✨ 核心特性

* **全栈协议整合与端口拟态**: 自动化部署最新一代网络路由核心（VLESS-Vision、Hysteria 2、Shadowsocks），支持复杂的协议栈整合。通过内核级转发，实现同一物理端口（如 443）的高效复用与拟态伪装。
* **Auto-Fix 终极环境自愈引擎**: 针对复杂或被污染的宿主环境，脚本内置白盒级原子诊断。一键释放寻址层死锁端口、抹除脏防火墙规则（精准狙击废弃的 NAT/INPUT 链，绝对保护 Docker 容器路由池），并将系统网络状态恢复至绝对纯净的“出厂态”。
* **Linux 物理内核算力释放**: 摒弃表层优化，脚本直击 Linux 内核参数。一键重载 BBR 拥塞控制算法，并智能将底层 TCP 窗口、文件描述符 (`fs.file-max`) 和最大并发限制 (`ulimit`) 拉升至 `1,048,576` 的物理极限。
* **高优测速与信誉审计**: 面板深度集成全球公认的基准测试组件：`bench.sh`（全面评估 CPU、I/O 与国际网关速率）与 `Check.Place`（深入探查 IP 的欺诈评分与原生解锁纯净度）。
* **无痕清场与原子级 OTA**: 提供零残留的“外科手术级卸载”机制，绝不残留暗病。支持从 GitHub 云端秒级热更新（OTA），确保底层架构永远保持最新。

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

<a name="-deploy-cn"></a>
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

<a name="-ops-cn"></a>
#### ⚡ 全局管理
安装完成后，在终端输入以下指令即可瞬间唤醒中控面板（支持离线唤醒）：
```bash
sb
```

### 面板菜单速览：
1-10: 核心架构编排 - 分别对应 Xray (1-5) 与 Sing-box (6-10) 的部署组合。

11: 系统 Benchmark & IP 审计 - 启动 bench.sh 与 Check.Place 跑分。

12: VPS 一键优化 - 物理注入 BBR 算法并提升内核并发句柄。

13: 节点参数显示 - 以明文及 Clash Meta YAML 格式输出当前拓扑配置。

14: 脚本说明书 - 查阅针对 VLESS-Vision 指纹对齐及 Hy2 证书避坑指南。

15: 脚本 OTA 升级 - 热加载 GitHub 最新发行版源码。

16: 一键清空卸载 - 执行防御式卸载，物理销毁残留碎片。

17: 环境自愈 (Auto-Fix) - 扫描死锁、清理脏路由、连通性探测。


<a name="-faq-cn"></a>
### ❓常见问题 (FAQ)
Q: VLESS 节点为什么连上后瞬间断开？

A: 脚本强制启用了 xtls-rprx-vision。客户端严禁开启 Mux（多路复用），伪装指纹（Fingerprint）必须设置为 chrome。

Q: 为什么 Alpine 系统上优化内核会失败？

A: 已完美修复此问题。脚本会智能回退并手动注入配置，实现 100% 优化成功率。

Q: 卸载会损坏 Docker 规则吗？

A: 绝对不会。脚本采用正则精准锚定清理带有 Aio-box- 注释的规则，不使用野蛮的 iptables -F。


<a name="-english-description"></a>


# 📦 Aio-box

- **致谢 / Credits:** We express our deepest gratitude to the excellent open-source network routing and encryption projects (such as Xray-core, Sing-box, Hysteria, etc.) for providing the underlying technical inspiration and support. This project is an independent tool designed for technical learning and automated operations.

[![Version](https://img.shields.io/badge/Version-Apex_V56-success.svg?style=flat-square)]()
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg?style=flat-square)](https://opensource.org/licenses/MIT)
[![GitHub Stars](https://img.shields.io/github/stars/alariclin/aio-box?style=flat-square&color=yellow)](https://github.com/alariclin/aio-box/stargazers)
[![GitHub Forks](https://img.shields.io/github/forks/alariclin/aio-box?style=flat-square&color=orange)](https://github.com/alariclin/aio-box/network/members)

---

## 🌐 Project Introduction

**Aio-box** is an enterprise-grade automated operations environment focused on Linux server network configuration, security hardening, and routing optimization. This project aims to resolve concurrency and conflict issues between heterogeneous network protocol stacks on the same host through high-fidelity automation scripts. With built-in kernel-level parameter tuning and a pioneering "White-box Self-Healing" mechanism, it serves as an ideal scaffold for network security research, full-stack technical testing, and automated DevOps management.

> **⚠️ Compliance & Disclaimer**: This project is intended strictly for network architecture research, cryptographic protocol study, and technical exchange. Use for any illegal purposes is strictly prohibited. Users must strictly comply with the laws and regulations of their respective jurisdictions. The user bears full responsibility for any direct or indirect consequences arising from improper use.

---

### 📑 Table of Contents
1. ✨ Key Features
2. 🏗️ Architecture Comparison
3. 🚀 Quick Start
4. 🛠️ Management & Operations
5. ❓ Frequently Asked Questions (FAQ)

---

### ✨ Key Features

* **Full-Stack Protocol Integration & Port Multiplexing**: Automates the deployment of next-generation routing cores (VLESS-Vision, Hysteria 2, Shadowsocks). It achieves efficient multiplexing and mimicry camouflage on a single physical port (e.g., 443) through advanced kernel-level forwarding.
* **Auto-Fix Ultimate Self-Healing Engine**: Features an atomic diagnostic mechanism for complex or polluted host environments. With a single click, it resolves addressing-layer port deadlocks, prunes "dirty" firewall rules (precisely targeting orphaned NAT/INPUT chains while protecting Docker container networking), and restores the system network state to a pristine condition.
* **Linux Physical Kernel Performance Unleashed**: Direct interaction with Linux kernel parameters. Enables the BBR congestion control algorithm and intelligently elevates TCP windows, file descriptors (`fs.file-max`), and concurrency limits (`ulimit`) to their physical ceiling of `1,048,576`.
* **High-Priority Benchmarking & Reputation Audit**: Deeply integrates globally recognized baseline testing components: `bench.sh` (comprehensive assessment of CPU, I/O, and international gateway speeds) and `Check.Place` (in-depth analysis of IP fraud scores and native streaming unlock purity).
* **Surgical Cleanup & Atomic OTA Updates**: Provides a zero-residue "surgical uninstallation" protocol. Supports instant Over-The-Air (OTA) updates directly from the GitHub Cloud, ensuring the underlying architecture remains cutting-edge.

---

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
Released under the [MIT License](https://opensource.org/licenses/MIT). Copyright © 2026.
