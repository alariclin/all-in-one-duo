# Aio-box

- **[中文说明](#-中文说明) | [English Description](#-english-description)**
- **致谢 / Credits:** 感谢 Xray-core 与 Sing-box 提供的强大网络路由与加密核心。

[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](https://opensource.org/licenses/MIT)
[![GitHub Stars](https://img.shields.io/github/stars/alariclin/aio-box?style=flat&color=yellow)](https://github.com/alariclin/aio-box/stargazers)
[![GitHub Forks](https://img.shields.io/github/forks/alariclin/aio-box?style=flat&color=orange)](https://github.com/alariclin/aio-box/network/members)
[![GitHub Issues](https://img.shields.io/github/issues/alariclin/aio-box?style=flat&color=red)](https://github.com/alariclin/aio-box/issues)

---

<a name="-中文说明"></a>

**Aio-box** 是一款专为网络安全、强隐私保护与路由优化打造的“双核·高可用”一键部署环境。本项目聚焦于 **Xray-core (v26+)** 与 **Sing-box (Testing)** 的原生深度集成，提供物理级防封锁与系统级并发性能优化。

### ✨ 核心特性
* **TCP/UDP 443 双栈复用**: 完美实现 VLESS (TCP) 与 Hysteria 2 (UDP) 共享物理 443 端口，极致伪装并提升连接成功率。
* **新一代路由协议引擎**: Xray v26.3.27 原生支持，内置 Sing-box 端口跳跃 (NAT Hopping) 与 Chrome 指纹强校验，有效抵御 DPI 探测。
* **动态 SNI 与自签发证书**: 支持自定义私有域名，并根据用户输入的 SNI 自动生成防探测的 100 年期自签发安全加密证书。
* **高可用本地化**: `sb` 快捷指令本地化物理执行，自带离线核心缓存，彻底免疫远程访问异常或网络波动。
* **自动提权与防呆设计**: 脚本自动获取 Root 权限，屏蔽退格键乱码与误触崩溃，提供极致流畅的极客交互体验。

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

### 📂 架构一览
| 引擎模式 | 适用场景 | 核心技术点 |
| :--- | :--- | :--- |
| **🛡️ Xray-core** | 强隐私网络隔离 | `TCP-Vision` 极致流控, v26 原生 Hy2 支持 |
| **⚡ Sing-box** | 高并发吞吐路由 | 原生端口跳跃, Chrome Root Store 指纹校验 |

### 🛠️ 系统管理功能
* **[选项 11] 本机参数与IP网络测速诊断**: 本机参数明细与服务器综合网络基准测试。
* **[选项 13] 参数明细与节点链接**: 渲染各协议的通用 URI 与 **Clash Meta (Mihomo) YAML** 拓扑配置。
* **[选项 14] 脚本源码 OTA 热更新**: 一键强制从云端同步并校验最新源码至本地库。
* **[选项 15] 彻底清空卸载环境**: 智能双轨卸载，可选择物理清场或保留本地核心缓存火种。

---

<a name="-english-description"></a>
## English Description

**Aio-boxo** is a high-availability, robust deployment environment designed for network security and routing optimization. Built on a dual-core architecture, it seamlessly integrates Xray-core and Sing-box, featuring automated YAML topology generation, offline core caching, and kernel-level TCP/BBR tuning.

### ✨ Key Features
* **TCP/UDP 443 Dual-Stack Multiplexing**: Seamlessly enables VLESS (TCP) and Hysteria 2 (UDP) to share a single physical port 443, offering unparalleled obfuscation and boosting connection success rates.
* **Next-Generation Routing Protocol Engine**: Natively powered by Xray v26.3.27, featuring built-in Sing-box Port Hopping (NAT Hopping) and robust Chrome fingerprint validation to effectively thwart DPI detection.
* **Dynamic SNI & Self-Signed Certificates**: Supports custom private domains and automatically generates detection-resistant, 100-year self-signed security certificates based on the user-provided SNI.
* **High-Availability Local Execution**: The `sb` shortcut command executes locally on the device; equipped with an offline core cache, it remains completely immune to remote access failures or network fluctuations.
* **Automatic Privilege Escalation & Fail-Safe Design**: The script automatically acquires Root privileges and incorporates safeguards to prevent garbled text from backspace inputs or accidental crashes, delivering an exceptionally smooth and seamless interaction experience for power users.

### 🚀 Quick Start

**Global High-Speed ​​Channel (Recommended for Overseas Servers):**
```bash
sudo bash -c "$(curl -Ls https://raw.githubusercontent.com/alariclin/aio-box/main/install.sh)"
```

### 📂 Architecture Overview
| Engine Base | Target Use Case | Technical Highlights |
| :--- | :--- | :--- |
| **🛡️ Xray-core** | Strong Privacy | `TCP-Vision` flow control, REALITY dynamic padding |
| **⚡ Sing-box** | High Concurrency | ACME automation, Port-hopping, Multiplexing |

### 🛠️ System Management
[Option 9] Quota Guard: Precision API bandwidth tracking with an automated network killswitch.
[Option 10] Diagnostics: Interactive tests for IP Reputation, Streaming Unlock, and Global Speedtests.
[Option 11] VPS Tuning: Unlock kernel concurrency (Ulimit) and optimize TCP BBR congestion stacks.
[Option 13] Export Topology: Instantly render Universal URIs and Clash Meta (Mihomo) YAML structures.
[Option 14] OTA Update: Force-sync the local dashboard instance with the latest cloud repository.
[Option 15] Clean Uninstall: Smart uninstaller with the option to complete purge or keep offline caches.
---

## ⚠️ 系统要求 / System Requirements
* **OS**: Debian 10+, Ubuntu 20.04+, CentOS 8+, AlmaLinux.
* **Init System**: Systemd is strictly required for daemon persistence.
* **Network**: Dual-stack IPv4 / IPv6 resolution fully supported.

## 🤝 反馈与交流 / Feedback & Support
Submit logs or suggestions at:
* [GitHub Issues](https://github.com/alariclin/all-in-one-duo/issues)

## 📄 许可证 / License
Released under the [MIT License](https://opensource.org/licenses/MIT).
