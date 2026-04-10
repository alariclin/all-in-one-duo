# Aio-box

- **[中文说明](#-中文说明) | [English Description](#-english-description)**
- **致谢:** 感谢开源社区中优秀的网络代理与路由项目（如 Xray-core、Sing-box、Hysteria 等）提供的底层技术启发与支持。本项目为独立的学习与自动化部署工具。
- Credits: We would like to express our gratitude to excellent open-source network proxy and routing projects (such as Xray-core, Sing-box, Hysteria, etc.) for their underlying technical inspiration and support. This project is an independent tool for learning and automated deployment.

[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](https://opensource.org/licenses/MIT)
[![GitHub Stars](https://img.shields.io/github/stars/alariclin/aio-box?style=flat&color=yellow)](https://github.com/alariclin/aio-box/stargazers)
[![GitHub Forks](https://img.shields.io/github/forks/alariclin/aio-box?style=flat&color=orange)](https://github.com/alariclin/aio-box/network/members)
[![GitHub Issues](https://img.shields.io/github/issues/alariclin/aio-box?style=flat&color=red)](https://github.com/alariclin/aio-box/issues)

---

<a name="-中文说明"></a>

**Aio-box** 是一款专注于 Linux 服务器网络环境配置、安全加固与路由优化的自动化运维脚本。本项目旨在通过一键式部署，简化复杂的网络协议栈（如 TCP/UDP 复用）的配置流程，并提供底层的系统参数调优与环境自检修复功能，适用于网络安全研究、技术测试及个人服务器的自动化管理。

> **免责声明 (Disclaimer)**: 本项目仅供学习、研究和技术交流使用。用户在使用本脚本时必须遵守其所在国家和地区的法律法规。任何因不当使用造成的后果由使用者自行承担。

### ✨ 核心特性
* **现代化网络协议集成架构**: 自动化部署并整合最新一代的网络路由核心（支持 VLESS、Hysteria 2、Shadowsocks 等协议），实现端口的高效复用（如同一端口兼容 TCP 与 UDP），优化连接效率。
* **高可用性与进程物理隔离**: 提供灵活的双核（Hybrid）或单核（Sing-box）部署模式。通过脚本逻辑隔离不同服务进程，有效避免端口冲突（Deadlock），确保服务的持续稳定运行。
* **Auto-Fix 环境异常自检与修复**: 针对复杂宿主环境设计的白盒级诊断机制。一键排查并清理僵尸进程、释放被死锁的端口、修复错误的网络转发规则（如残留的 NAT 映射），恢复系统至纯净状态。
* **Linux 内核级性能释放**: 集成自动化调优模块，一键启用 BBR 拥塞控制算法，并智能提升系统资源限制（如调整文件描述符 `fs.file-max` 和 `ulimit` 至 1,048,576 极限值），最大化网络吞吐量。
* **多维测速与 IP 审计**: 内置主流的 VPS 硬件信息测速（bench.sh）与全球 IP 纯净度检测工具，帮助用户实时掌握服务器质量。
* **OTA 平滑升级与安全卸载**: 支持从 GitHub 实时获取并更新最新脚本代码。提供“无残留物理级核弹卸载”和“保留环境变量的软卸载”两种模式，保护服务器宿主安全。

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
Modern Network Protocol Integration: Automates the deployment of next-generation routing cores (supporting protocols like VLESS, Hysteria 2, and Shadowsocks), achieving efficient port multiplexing (e.g., concurrent TCP and UDP on a single port) to optimize connection efficiency.
*High Availability & Process Isolation: Offers flexible Dual-Core (Hybrid) or Single-Core (Sing-box) deployment modes. The script logically isolates different service processes to effectively prevent port conflicts (deadlocks) and ensure continuous service operation.
*Auto-Fix Environmental Diagnostics: Features an innovative white-box diagnostic mechanism. With a single click, it identifies and purges zombie processes, resolves port deadlocks, clears erroneous network forwarding rules, and restores the system's network configuration to a pristine state.
*Linux Kernel Performance Unleashed: Includes an automated tuning module that enables the BBR congestion control algorithm and intelligently elevates system resource limits (e.g., adjusting file descriptors fs.file-max and ulimit to their maximum theoretical values) to maximize network throughput.
*Comprehensive Benchmarking: Integrates hardware performance testing (bench.sh) and global IP quality/reputation auditing tools to help users monitor their server's performance and status.
*Seamless OTA Updates & Secure Uninstallation: Supports real-time retrieval and updating of the latest script code from GitHub. Provides two uninstallation modes: a "zero-residue nuclear wipe" and a "soft uninstall" that retains environment variables, ensuring system integrity.
*Cross-Platform Daemon Compatibility: Intelligently identifies and seamlessly integrates with major Linux initialization systems (Systemd and OpenRC), offering broad support for mainstream Linux distributions and lightweight systems (such as Alpine).

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
