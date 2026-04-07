# Aio-box

- **[中文说明](#-中文说明) | [English Description](#-english-description)**
- **致谢 / Credits:** 感谢 Xray-core 与 Sing-box 提供的强大网络路由与加密核心。

[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](https://opensource.org/licenses/MIT)
[![GitHub Stars](https://img.shields.io/github/stars/alariclin/aio-box?style=flat&color=yellow)](https://github.com/alariclin/aio-box/stargazers)
[![GitHub Forks](https://img.shields.io/github/forks/alariclin/aio-box?style=flat&color=orange)](https://github.com/alariclin/aio-box/network/members)
[![GitHub Issues](https://img.shields.io/github/issues/alariclin/aio-box?style=flat&color=red)](https://github.com/alariclin/aio-box/issues)

---

<a name="-中文说明"></a>
## 中文说明

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
sudo bash -c "$(curl -Ls [https://raw.githubusercontent.com/alariclin/aio-box/main/install.sh](https://raw.githubusercontent.com/alariclin/aio-box/main/install.sh))"
