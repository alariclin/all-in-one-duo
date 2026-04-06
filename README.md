# Sing-box- auto

- [基于 Deterministic Deep Reasoning (DDR) 逻辑构建的物理级防弹脚本]

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)

[！[ 唱盒 ]（https://img.shields.io/badge/Core-Sing--box-blue）]（https://github.com/SagerNet/sing-box） 

[！[ 语言：双语 （https://img.shields.io/badge/Language-Bilingual-green）]（#english 版 ）  
[![OS: Linux](https://img.shields.io/badge/OS-Linux-orange)](#)

Sing-box 2026 终极一键部署脚本。

---

## 🚀 功能特性 (Features)

* **全维 SNI 矩阵:** 自动识别 VPS 厂商（AWS/GCP/Azure/阿里/腾讯等）及地理位置，动态匹配物理不可证伪的 SNI 域名。
* **智能证书降级 (Tier 0/1):** * **Tier 0:** 检测到真实域名解析后，自动申请 Let's Encrypt 证书并挂载 Nginx 文档站伪装。
    * **Tier 1:** 无域名环境自动自愈，生成高阶平庸域名自签证书。
* **Salamander 混淆:** 强制注入 Hysteria 2 熵混淆算法。
* **内核级调优:** 强制激活 BBR、物理时钟强制对齐、TCP Fast Open 优化。
* ** 多协议集成：** VLESS-REALITY （TCP） + Hysteria 2 （UDP） + SS-2022 （落地）。  
* **故障自愈:** 自动解除 APT/DPKG 锁死，自动修复机房 DNS 污染。
* **双栈支持:** 完美支持 IPv4/IPv6 协议栈，适配纯 IPv6 机器。

---

## ⚡ 快速开始 (Quick Start)

### 安装 (Installation)

在终端执行以下命令（Root 用户）：

```bash
bash <(curl -Ls [https://raw.githubusercontent.com/alariclin/sing-box-auto-ddr/refs/heads/main/install.sh](https://raw.githubusercontent.com/alariclin/sing-box-auto-ddr/refs/heads/main/install.sh))
