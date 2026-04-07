# All-in-One Duo

- [中文说明](#-中文说明) | [English Description](#-english-description)
- 感谢 [Xray-core](https://github.com/XTLS/Xray-core) 与 [Sing-box](https://github.com/SagerNet/sing-box) 提供核心引擎支持。

[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](https://opensource.org/licenses/MIT)
[![GitHub Stars](https://img.shields.io/github/stars/alariclin/all-in-one-duo?style=flat&color=yellow)](https://github.com/alariclin/all-in-one-duo/stargazers)
[![GitHub Forks](https://img.shields.io/github/forks/alariclin/all-in-one-duo?style=flat&color=orange)](https://github.com/alariclin/all-in-one-duo/network/members)
[![GitHub Issues](https://img.shields.io/github/issues/alariclin/all-in-one-duo?style=flat&color=red)](https://github.com/alariclin/all-in-one-duo/issues)

---

<a name="-中文说明"></a>
## 中文说明

**All-in-One Duo** 是一款专为 2026 年网络对抗环境打造的“双核·全矩阵”一键防弹部署脚本。
它深度集成了 **Xray-core (xhttp)** 与 **Sing-box (全能矩阵)**，并提供极客级 VPS 深度开荒、内核级流量熔断与 2D SNI 自动匹配机制。

### ✨ 核心功能
* **双核自由切换**: 完美调度 Xray 与 Sing-box。支持“全家桶”组合或协议乐高式拆分部署。
* **前沿协议支持**: 原生集成 VLESS-Reality (Vision / xhttp)、Hysteria 2 (蝾螈熵混淆)、SS-2022。
* **VPS 极致开荒**: 自动注入 Swap 虚拟内存、破除系统 Ulimit 物理限额、深度爆改 TCP 网络栈与 BBR。
* **内核流量守卫**: 基于 API 的毫秒级查账，支持设定月度流量额度，超额自动断网，杜绝天价账单。
* **2D 智能 SNI**: 自动感知 VPS 机房 (ASN) 与国家，匹配物理上最真实、不可证伪的伪装域名。
* **物理防弹衣**: 战前清场占用端口、SELinux 自动放行、强制时钟对齐免疫握手故障。

### 🚀 快速开始
在你的 VPS 终端执行以下命令（Root 用户）：
```bash
bash <(curl -Ls [https://raw.githubusercontent.com/alariclin/all-in-one-duo/main/install.sh](https://raw.githubusercontent.com/alariclin/all-in-one-duo/main/install.sh))
```
**中国大陆极速安装镜像:**
```bash
bash <(curl -Ls [https://ghp.ci/https://raw.githubusercontent.com/alariclin/all-in-one-duo/main/install.sh](https://ghp.ci/https://raw.githubusercontent.com/alariclin/all-in-one-duo/main/install.sh))
```

#### ⚡ 全局快捷指令
首次安装完成后，无论何时登录 VPS，只需在终端输入 **两个字母** 即可瞬间调出中控看板：
```bash
sb
```

---

<a name="-english-description"></a>
## English Description

**All-in-One Duo** is a next-generation, bulletproof deployment script designed for the extreme network conditions of 2026. Built on a "Dual-Core" engine, it switches seamlessly between **Xray-core (xhttp)** and **Sing-box (Omni-Matrix)**, focusing on elite stealth and kernel-level performance.

### ✨ Key Features
* **Dual-Core Engine**: Native support for both Xray and Sing-box. Deploy "Full Suite" or modular protocols.
* **Modern Protocol Stack**: VLESS-Reality (Vision / xhttp), Hysteria 2 (Salamander obfs), and Shadowsocks 2022.
* **VPS Initial Setup**: Professional tuning including auto Swap injection, Ulimit lifting, and deep TCP/BBR optimization.
* **Traffic Guard**: Real-time API monitoring. Set monthly quotas with an auto-killswitch to prevent billing overages.
* **ASN-Aware SNI**: Automatically detects your VPS provider to match authentic, unfalsifiable SNI targets.
* **Bulletproof Architecture**: Auto-cleanup of port conflicts, SELinux bypass, and forced time synchronization.

### 🚀 Quick Start
Run this command in your VPS terminal (Root):
```bash
bash <(curl -Ls [https://raw.githubusercontent.com/alariclin/all-in-one-duo/main/install.sh](https://raw.githubusercontent.com/alariclin/all-in-one-duo/main/install.sh))
```

#### ⚡ Global Shortcut
Once installed, simply type the following command to launch the console anytime:
```bash
sb
```

---

## 📂 架构指南 (Architecture)

| 引擎模式 (Engine) | 场景应用 (Use Case) | 技术特性 (Highlights) |
| :--- | :--- | :--- |
| **🛡️ Xray-core** | TCP 极限隐匿 (Stealth) | xhttp `packet-up` 模式, 1-1500 Padding 填充 |
| **⚡ Sing-box** | 全能调度 (Performance) | 暴力 UDP 吞吐, ACME 真实证书, Nginx 伪装 |

## 🛠️ 运维与诊断 (Management Tools)
* **[选项 09] 流量监控**: 内核 API 精准查账，支持月度熔断限额设定。
* **[选项 10] 诊断测速**: IP 欺诈度检测 (Check.Place) + VPS 全球 Bench 跑分。
* **[选项 11] 开荒调优**: 物理并发破壁，注入虚拟内存，调教服务器至巅峰性能。
* **[选项 14] 参数透视**: 一键获取所有 Private Key、Short ID 及证书指纹状态。

## ⚠️ 系统要求 (Requirements)
* **OS**: Debian 10+, Ubuntu 20.04+, CentOS 8+, AlmaLinux.
* **Init**: Systemd is required.
* **Network**: Dual-stack IPv4 / IPv6 support.

## 🤝 反馈 (Feedback)
Submit issues or logs at: [GitHub Issues](https://github.com/alariclin/all-in-one-duo/issues)

## 📄 许可证 (License)
Licensed under the [MIT License](https://opensource.org/licenses/MIT).
