# All-in-One Duo

- **[🇨🇳 中文说明](#-中文说明) | [🌐 English Description](#-english-description)**
- **致谢 / Credits:** 感谢 [Xray-core](https://github.com/XTLS/Xray-core) 与 [Sing-box](https://github.com/SagerNet/sing-box) 提供的强大核心引擎。 / Thanks to [Xray-core](https://github.com/XTLS/Xray-core) and [Sing-box](https://github.com/SagerNet/sing-box).

[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](https://opensource.org/licenses/MIT)
[![GitHub Stars](https://img.shields.io/github/stars/alariclin/all-in-one-duo?style=flat&color=yellow)](https://github.com/alariclin/all-in-one-duo/stargazers)
[![GitHub Forks](https://img.shields.io/github/forks/alariclin/all-in-one-duo?style=flat&color=orange)](https://github.com/alariclin/all-in-one-duo/network/members)
[![GitHub Issues](https://img.shields.io/github/issues/alariclin/all-in-one-duo?style=flat&color=red)](https://github.com/alariclin/all-in-one-duo/issues)

---

<a name="-中文说明"></a>
## 🇨🇳 中文说明

**All-in-One Duo** 是一款专为 2026 年极端网络审查环境打造的“双核·全矩阵”一键防弹部署脚本。它彻底摒弃了臃肿的旧协议，将底层逻辑聚焦于 **Xray-core (xhttp)** 与 **Sing-box (全能矩阵)** 的双核无缝切换，并集成了极客级 VPS 开荒调优与内核级流量熔断机制。

### ✨ 核心功能
* **双核自适应驱动:** 完美调度 Xray-core 与 Sing-box。支持“全家桶”组合部署，或单协议乐高式独立部署。
* **前沿协议矩阵:** 原生集成 VLESS-Reality (Vision / xhttp)、Hysteria 2 (Salamander 熵混淆)、Shadowsocks 2022。
* **VPS 极致开荒:** 内置极客级服务器调优。支持一键手动注入 Swap 虚拟内存、破除 Ulimit 物理并发限制、爆改 TCP 网络栈与 BBR。
* **内核级流量守卫:** 基于底层 API 的实时精准流量统计。支持设定月度流量阈值 (Quota)，超额自动物理断网，告别天价账单。
* **2D 智能 SNI 矩阵:** 自动探测 VPS 机房 (ASN) 与国家地理位置，匹配物理上最真实、不可证伪的伪装目标。
* **多层防弹衣:** 战前僵尸端口冲突清场、针对 RHEL/CentOS 的 SELinux 自动物理放行、强制时钟对齐免疫握手失败。

### 🚀 快速开始

在您的 VPS 终端 (Root 用户) 执行以下命令：

```bash
bash <(curl -Ls [https://raw.githubusercontent.com/alariclin/all-in-one-duo/main/install.sh](https://raw.githubusercontent.com/alariclin/all-in-one-duo/main/install.sh))
```
**中国大陆机器极速安装镜像:**
```bash
bash <(curl -Ls [https://ghp.ci/https://raw.githubusercontent.com/alariclin/all-in-one-duo/main/install.sh](https://ghp.ci/https://raw.githubusercontent.com/alariclin/all-in-one-duo/main/install.sh))
```

#### ⚡ 全局快捷指令
首次安装完成后，无论何时登录 VPS，只需在终端输入 **两个字母** 即可瞬间调出中控面板（支持云端代码自动热更新）：
```bash
sb
```

### 📂 架构指南
| 引擎模式 | 场景应用 | 技术特性 |
| :--- | :--- | :--- |
| **🛡️ Xray-core** | TCP 极限隐匿 | xhttp `packet-up` 模式, 1-1500 Padding 动态填充 |
| **⚡ Sing-box** | 全能暴力吞吐 | 极致性能, ACME 真实证书申请, Nginx 伪装落地 |

### 🛠️ 运维与诊断工具
* **[选项 09] 流量监控**: 内核 API 精准查账，支持自定义月度熔断限额。
* **[选项 10] 诊断测速**: IP 欺诈度风险检测 (Check.Place) + VPS 全球网络性能跑分。
* **[选项 11] 开荒调优**: 物理并发破壁，注入虚拟内存，调教服务器至巅峰性能。
* **[选项 12] 账户管理**: 动态查看或添加多用户配置。
* **[选项 13] 提取节点**: 一键生成各协议的通用 URI 订阅链接。
* **[选项 14] 详细参数**: 一键透视所有底层加密指纹 (Private Key / Short ID / CA)。

---

<a name="-english-description"></a>
## 🌐 English Description

**All-in-One Duo** is a high-performance, bulletproof deployment script designed for the extreme network conditions of 2026. Built on a "Dual-Core" engine, it seamlessly switches between **Xray-core (xhttp)** and **Sing-box (Omni-Matrix)**, focusing exclusively on next-gen stealth protocols and kernel-level optimizations.

### ✨ Key Features
* **Dual-Core Engine:** Native support for both Xray and Sing-box. Deploy the "Full Suite" or modular protocols like Lego blocks.
* **Elite Protocol Matrix:** VLESS-Reality (Vision / xhttp), Hysteria 2 (Salamander obfuscation), and Shadowsocks 2022.
* **VPS Initial Setup:** Geek-level tuning including manual Swap injection, Ulimit lifting, and deep TCP/BBR network stack optimization.
* **Traffic Guard:** Real-time monitoring via kernel APIs. Set monthly quotas with an auto-killswitch to prevent unexpected VPS overage billing.
* **ASN-Aware SNI:** Automatically detects your VPS provider (ASN) and region to match the most authentic, unfalsifiable SNI targets.
* **Bulletproof Architecture:** Auto-cleanup of port conflicts, SELinux bypass for RHEL/CentOS, and forced time synchronization.

### 🚀 Quick Start

Run the following command in your VPS terminal (Root):

```bash
bash <(curl -Ls [https://raw.githubusercontent.com/alariclin/all-in-one-duo/main/install.sh](https://raw.githubusercontent.com/alariclin/all-in-one-duo/main/install.sh))
```
**China Mirror (Fast Install):**
```bash
bash <(curl -Ls [https://ghp.ci/https://raw.githubusercontent.com/alariclin/all-in-one-duo/main/install.sh](https://ghp.ci/https://raw.githubusercontent.com/alariclin/all-in-one-duo/main/install.sh))
```

#### ⚡ Global Shortcut
Once installed, simply type the following **two letters** in your terminal to launch the console anytime (Supports auto OTA updates):
```bash
sb
```

### 📂 Architecture Guide
| Engine Mode | Best Use Case | Highlights |
| :--- | :--- | :--- |
| **🛡️ Xray-core** | Extreme Stealth | xhttp `packet-up` mode, 1-1500 dynamic padding |
| **⚡ Sing-box** | High Throughput | Native performance, ACME auto-cert, Nginx masquerade |

### 🛠️ Management & Diagnostics
* **[Option 09] Traffic Stats**: API-based precision monitoring with monthly quota guard.
* **[Option 10] Diagnostics**: `Check.Place` (IP Risk Check) & `bench.sh` (Global Performance).
* **[Option 11] VPS Tuning**: Unlock kernel-level concurrency and inject Swap memory.
* **[Option 12] Account Manager**: View or add multiple users dynamically.
* **[Option 13] Export Nodes**: Generate universal URI links for all deployed protocols.
* **[Option 14] Parameters**: One-click view of Private Keys, Short IDs, and cert status.

---

## ⚠️ 系统要求 / Requirements
* **OS**: Debian 10+, Ubuntu 20.04+, CentOS 8+, AlmaLinux.
* **Init**: Systemd is strictly required. / 必须支持 Systemd 守护进程。
* **Network**: Full IPv4 / IPv6 Dual-stack support. / 完美支持双栈解析。

## 🤝 反馈与交流 / Feedback
Submit issues or logs at: / 如果遇到 Bug 请提交 Issue:
* [GitHub Issues](https://github.com/alariclin/all-in-one-duo/issues)

## 📄 许可证 / License
Licensed under the [MIT License](https://opensource.org/licenses/MIT).
