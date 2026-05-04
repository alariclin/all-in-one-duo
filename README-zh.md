[English](README.md) | [简体中文](README-zh.md) | [Русский](README-ru.md) | [فارسی](README-fa.md)

<img width="459" height="427" alt="A-Box 标志" src="https://github.com/user-attachments/assets/0a3b2ac1-1d05-4cae-968f-24c2a7bc9953" />

# A-Box

> 一键部署的 Linux 网络网关工具箱  
> Born May 1, 2026

**A-Box** 是一款面向 Linux 服务器的一键网络网关部署与运维工具箱。它把服务部署、系统调优、流量管理、访问控制、健康检查、参数导出、网络质量测试和多语言终端界面集中到一个脚本内。

**致谢:** 感谢 Xray-core、sing-box、Hysteria 及相关开源项目提供的技术启发与生态支持。A-Box 是独立自动化工具箱。

[![Version](https://img.shields.io/badge/Version-2026.05.04-success.svg?style=flat-square)]()
[![License: Apache-2.0](https://img.shields.io/badge/License-Apache_2.0-blue.svg?style=flat-square)](LICENSE)
[![GitHub Stars](https://img.shields.io/github/stars/alariclin/a-box?style=flat-square&color=yellow)](https://github.com/alariclin/a-box/stargazers)
[![GitHub Forks](https://img.shields.io/github/forks/alariclin/a-box?style=flat-square&color=orange)](https://github.com/alariclin/a-box/network/members)

---

## 合规与免责声明

本项目定位为授权环境下的网络架构测试、网络安全研究与合规隐私保护自动化工具。

1. **法律合规性:** 严禁利用本项目从事任何违反所在国家或地区法律法规的活动。
2. **责任界定:** 因用户违反法律法规、不当操作或滥用工具而产生的法律、运维和安全风险，由使用者自行承担。
3. **技术属性:** 本项目涉及的路由与加密技术用于提升数据传输安全性与私密性。严禁用于非法攻击、未授权访问或危害网络基础设施安全。
4. **条款接受:** 下载、复制或运行本脚本即视为已阅读、理解并接受本声明。

---

## 快速部署

全球通道：

```bash
curl -fsSL https://raw.githubusercontent.com/alariclin/a-box/main/install.sh > A-Box.sh && sudo bash A-Box.sh
```

镜像通道：

```bash
curl -fsSL https://ghp.ci/https://raw.githubusercontent.com/alariclin/a-box/main/install.sh > A-Box.sh && sudo bash A-Box.sh
```

指定语言启动：

```bash
sudo bash A-Box.sh --lang zh
sudo bash A-Box.sh --lang en
```

静态自测与状态检查：

```bash
sudo bash A-Box.sh --self-test
sudo bash A-Box.sh --status
```

安装后打开控制台：

```bash
sb
```

---

## 核心能力

| 模块 | 说明 |
| :--- | :--- |
| 一键部署 | 支持 Xray-core、sing-box、官方 Hysteria 2。 |
| 协议组合 | 支持 VLESS-Reality、VLESS-XHTTP-Reality、Shadowsocks-2022、Hysteria 2。 |
| 推荐端口 | Vision `443/TCP`，XHTTP `8443/TCP`，HY2 `443/UDP`，SS-2022 `2053/TCP+UDP`。 |
| SNI 策略 | 443 默认 `www.apple.com`；非 443 默认 `www.microsoft.com`；非 443 使用 Apple/iCloud 类 SNI 会提示风险。 |
| XHTTP 导出 | 默认导出 `stream-one + h2 + smux:false`。 |
| HY2 模式 | 支持自有域名 ACME、自签证书 + 指纹锁定、端口跳跃、masquerade。 |
| 工具箱 | 内置测速、IP 检测、本地 SNI 测试、WARP 管理、2G Swap。 |
| 运维防护 | BBR/FQ、KeepAlive、Fail2Ban、logrotate、健康探针、Geo 更新、月流量管控、SS 白名单、`--status` 状态检查。 |
| 参数导出 | 输出 URI、二维码、Clash/Mihomo YAML、sing-box 出站示例、v2rayN/v2rayNG JSON。 |
| 部署切换保护 | 安装新核心前会提示并停止旧托管服务；彻底删除使用菜单 16。 |

---

## 菜单速览

| 菜单 | 功能 | 适用场景 |
| :--- | :--- | :--- |
| 1 | Xray Vision | 长期主力 TCP 通道。 |
| 2 | Xray XHTTP | 桌面高吞吐链路。 |
| 3 | Xray SS-2022 | 回程/落地入站，建议配合白名单。 |
| 4 | 官方 HY2 | UDP/QUIC/H3，适合移动和丢包链路。 |
| 5 | Xray + 官方 HY2 四合一 | Vision + XHTTP + HY2 + SS-2022。 |
| 6 | sing-box Vision | 低内存 Vision 部署。 |
| 7 | sing-box SS-2022 | 低内存 SS-2022 部署。 |
| 8 | sing-box Vision + SS-2022 | 轻量双协议组合。 |
| 9 | sing-box HY2 | sing-box 承载 HY2。 |
| 10 | sing-box 三合一 | Vision + HY2 + SS-2022，不含 XHTTP。 |
| 11 | 综合工具箱 | 测速、IP 检测、SNI 测试、WARP、Swap。 |
| 12 | VPS 优化 | BBR/FQ、句柄、KeepAlive、防护与探针。 |
| 13 | 参数显示 | 查看链接、二维码和客户端配置。 |
| 14 | 脚本说明书 | 查看完整功能说明。 |
| 15 | OTA / Geo 更新 | 更新脚本和 Geo 数据。 |
| 16 | 卸载清理 | 删除服务、配置和防火墙规则。 |
| 17 | 环境初始化 | 清理残留进程、规则和破损配置。 |
| 18 | 月流量管控 | vnStat 统计，超额自动停止服务。 |
| 19 | SS-2022 白名单 | 只允许指定前置 IP/CIDR 访问。 |
| 20 | 语言设置 | 中文 / 英文切换。 |

---

## 综合工具箱

| 子菜单 | 功能 |
| :--- | :--- |
| 1 | bench.sh：基础硬件与下载测速。 |
| 2 | Check.Place：IP 质量、区域服务和路由检测。 |
| 3 | 本地 SNI 测试：对 100 个常见域名测试 DNS、TCP、TLS、TTFB。 |
| 4 | Cloudflare WARP：调用 WARP 管理脚本处理出站网络。 |
| 5 | 2G Swap：创建 `/swapfile`，降低小内存机器 OOM 风险。 |

---

## 推荐组合

| 目标 | 推荐 |
| :--- | :--- |
| 综合模式 | 菜单 `5`：Xray + 官方 HY2 四合一。 |
| 低内存模式 | 菜单 `10`：sing-box 三合一。 |
| 长期主力 | Vision `443/TCP`。 |
| 高吞吐备用 | XHTTP `8443/TCP`。 |
| 移动/丢包链路 | HY2 `443/UDP`。 |
| 前置回程 | SS-2022 `2053/TCP+UDP` + 白名单。 |

---

## 系统要求

| 项目 | 要求 |
| :--- | :--- |
| 系统 | Debian 10+、Ubuntu 20.04+、CentOS/RHEL/Rocky/AlmaLinux 8+、Alpine Linux。 |
| 初始化系统 | Systemd 或 OpenRC。 |
| CPU | amd64 / x86_64，arm64 / aarch64。 |
| 权限 | root 或 sudo。 |
| 网络 | 可访问系统软件源和 GitHub Release。 |

---

## 反馈

- [GitHub Issues](https://github.com/alariclin/a-box/issues)

---

## 许可证

本项目采用 [Apache License 2.0](LICENSE) 许可证。
