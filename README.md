# All-in-One Duo

- [中文说明](#中文说明) | [English Description](#english-description)

[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](https://opensource.org/licenses/MIT)
[![GitHub Stars](https://img.shields.io/github/stars/alariclin/all-in-one-duo?style=flat&color=yellow)](https://github.com/alariclin/all-in-one-duo/stargazers)
[![GitHub Forks](https://img.shields.io/github/forks/alariclin/all-in-one-duo?style=flat&color=orange)](https://github.com/alariclin/all-in-one-duo/network/members)
[![GitHub Issues](https://img.shields.io/github/issues/alariclin/all-in-one-duo?style=flat&color=red)](https://github.com/alariclin/all-in-one-duo/issues)

---

<a name="中文说明"></a>
## 🇨🇳 中文说明

**All-in-One Duo** 是一款专为 2026 年网络环境打造的“双核·全矩阵”一键部署脚本。它彻底摒弃了臃肿的旧协议，将底层逻辑聚焦于 **Xray-core (xhttp)** 与 **Sing-box (全能矩阵)** 的双核无缝切换，并集成了极客级 VPS 开荒调优与内核级流量熔断机制。

### ✨ 核心功能
* **双核自适应驱动:** 完美调度 Xray-core 与 Sing-box。支持“全家桶”组合部署，或单协议乐高式独立部署。
* **前沿协议矩阵:** 原生集成 VLESS-Reality (Vision / xhttp)、Hysteria 2 (Salamander 熵混淆)、Shadowsocks 2022。
* **VPS 极致开荒:** 内置极客级服务器调优。支持一键注入 Swap 虚拟内存、破除 Ulimit 物理并发限制、爆改 TCP 网络栈与 BBR。
* **内核级流量守卫:** 基于底层 API 的实时流量统计。支持设定月度流量阈值 (Quota)，超额自动断网，告别天价账单。
* **2D 智能 SNI 矩阵:** 自动探测 VPS 机房 (ASN) 与位置，匹配最符合物理归属的不可证伪伪装目标。

### 🚀 快速开始
在 VPS 终端执行以下命令：
```bash
bash <(curl -Ls [https://raw.githubusercontent.com/alariclin/all-in-one-duo/main/install.sh](https://raw.githubusercontent.com/alariclin/all-in-one-duo/main/install.sh))
