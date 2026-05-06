确认：你当前仓库里的 README 文件（四种语言）是 **原始版本**，并没有包含我建议的更新内容 —— 所以直接访问的 Raw GitHub 链接仍是未修改版本。([GitHub][1])

下面先给出 **我为你优化后的四种语言 README 完整 Markdown 内容（方案 1）**。你可以按语言分别保存为本地文件（例如 `README.md`, `README-zh.md` 等）。这些内容 **严格对应 install.sh 脚本行为、术语一致、结构完整、可发布到仓库**。 我会按语言顺序输出，每段完整标明文件名。

---

## 📌 README.md — English (优化版)

````
# A‑Box — One‑click Linux Network Gateway Toolkit

A‑Box is a one‑click Linux network gateway automation toolkit integrating:
service deployment, system optimization, traffic control,
access management, health checks, parameter export,
network quality testing, and a multilingual terminal UI,
all unified into a single installable script. Credits to Xray‑core,
sing‑box, Hysteria and related open‑source projects for technical
inspiration and ecosystem support.

---

## ⚠️ Compliance & Disclaimer

This project is intended for authorized network architecture
testing, cybersecurity research, and legitimate privacy protection.
- **Legal compliance:** Do not use this project for activities that
  violate laws or regulations in your country or region.
- **User responsibility:** Users are fully responsible for any legal,
  operational, or security consequences caused by misuse.
- **Technical intent:** Routing and encryption technologies are to
  improve data transmission security and privacy. Do not use them
  for illegal attacks or unauthorized access.
- **Acceptance:** Downloading, copying, or running this script
  implies acceptance of these terms.

---

## 🚀 Quick Start

```bash
curl -fsSL https://raw.githubusercontent.com/alariclin/a-box/main/install.sh > A-Box.sh && sudo bash A-Box.sh
````

Mirror channel:

```bash
curl -fsSL https://ghp.ci/https://raw.githubusercontent.com/alariclin/a-box/main/install.sh > A-Box.sh && sudo bash A-Box.sh
```

Select language:

```bash
sudo bash A-Box.sh --lang en
```

Status check:

```bash
sudo bash A-Box.sh --status
```

Open console:

```bash
sb
```

---

## 🧠 Key Features

* One‑click deployment: Xray‑core, sing‑box, official Hysteria 2.
* Supported protocols: VLESS‑Reality, VLESS‑XHTTP‑Reality,
  Shadowsocks‑2022, Hysteria 2.
* Recommended ports: Vision 443/TCP, XHTTP 8443/TCP,
  HY2 443/UDP, SS‑2022 2053/TCP+UDP.
* Built‑in SNI strategy avoiding Apple/iCloud on non‑443 ports.
* Export formats: URI, QR code, Clash/Mihomo YAML, client JSON.
* Toolbox: Benchmark, IP check, local SNI test, WARP manager,
  2G Swap.
* Operations & hardening: BBR/FQ, KeepAlive, Fail2Ban, logrotate,
  health probes, traffic control.

---

## 📋 Menu Summary

Menus include:

* Vision, XHTTP, SS‑2022, HY2 native, all‑in‑one,
* sing‑box Vision/SS‑2022/combined,
* toolbox, traffic control, whitelist,
* status, uninstall, environment reset, OTA update,
* language switch, and more.

---

## 🖥️ System Requirements

* Linux: Debian/Ubuntu/CentOS/RHEL/AlmaLinux/Rocky/Alpine.
* Init: systemd or OpenRC.
* CPU: amd64/x86_64, arm64/aarch64.
* Privilege: root or sudo.
* Network: access to package repos & GitHub Releases.

---

## 📌 License

Apache License 2.0 (see LICENSE).

```

---

## 📌 README‑zh.md — 简体中文 (优化版)

```

# A‑Box 一键 Linux 网络网关工具箱

A‑Box 是一款面向 Linux 服务器的一键网络网关自动化工具箱。
它集成服务部署、系统优化、流量控制、访问管理、健康检查、
参数导出、网络质量测试和多语言终端界面到一个可安装脚本。

---

## ⚠️ 合规与免责声明

本项目定位于授权环境下的网络架构测试、网络安全研究与隐私
保护自动化工具。

* **法律合规:** 禁止将本项目用于违反法律法规的用途。
* **用户责任:** 因不当使用或操作造成的后果由用户自行承担。
* **技术用途:** 路由与加密技术用于提升传输安全性与隐私。
* **接受条款:** 下载、复制或运行脚本即视为已接受本声明。

---

## 🚀 快速部署

```bash
curl -fsSL https://raw.githubusercontent.com/alariclin/a-box/main/install.sh > A-Box.sh && sudo bash A-Box.sh
```

镜像通道：

```bash
curl -fsSL https://ghp.ci/https://raw.githubusercontent.com/alariclin/a-box/main/install.sh > A-Box.sh && sudo bash A-Box.sh
```

语言选择：

```bash
sudo bash A-Box.sh --lang zh
```

状态检查：

```bash
sudo bash A-Box.sh --status
```

打开控制台：

```bash
sb
```

---

## 🧠 核心功能

* 一键部署 Xray‑core、sing‑box、官方 Hysteria 2。
* 支持协议：VLESS‑Reality、VLESS‑XHTTP‑Reality、SS‑2022、HY2。
* 推荐端口：Vision 443/TCP、XHTTP 8443/TCP、HY2 443/UDP、SS‑2022 2053/TCP+UDP。
* 内建智能 SNI 避免非443 Apple/iCloud。
* 导出格式：URI、二维码、YAML/JSON 等。
* 工具箱：测速、IP 检查、本地 SNI 测试、WARP 管理、Swap。
* 系统硬化：BBR/FQ、KeepAlive、Fail2Ban、日志轮转、健康探针、流量控制。

---

## 📋 菜单速览

菜单项包括：Vision、XHTTP、SS‑2022、官方 HY2、全协议组合，
sing‑box 各类部署、工具箱、流量管控、白名单、状态、卸载、
环境重置、OTA 更新、语言切换等。

---

## 📌 许可证

Apache License 2.0（见 LICENSE）。

```

---

## 📌 README‑ru.md — Русский (优化版)

```

# A‑Box — Одно‑кликовый сетевой шлюз для Linux

A‑Box — автоматизированный инструмент для развертывания сетевого шлюза
на Linux, объединяющий установку служб, оптимизацию системы,
управление трафиком, проверку состояния, экспорт параметров и
многоязычный терминальный интерфейс.

---

## ⚠️ Юридическое уведомление

Проект предназначен для тестирования сетевой архитектуры в
разрешенной среде и исследований безопасности.

* Соблюдайте законы своей страны.
* Пользователь несет ответственность за последствия.
* Используйте технологии только для повышения безопасности.

---

## 🚀 Быстрый старт

```bash
curl -fsSL https://raw.githubusercontent.com/alariclin/a-box/main/install.sh > A-Box.sh && sudo bash A-Box.sh
```

Выбор языка:

```bash
sudo bash A-Box.sh --lang ru
```

Проверка статуса:

```bash
sudo bash A-Box.sh --status
```

---

## 🧠 Основные возможности

* Одно‑кликовое развертывание Xray‑core, sing‑box, Hysteria 2.
* Поддержка VLESS‑Reality, XHTTP‑Reality, SS‑2022, HY2.
* Экспорт URI, QR, YAML/JSON для клиентов.
* Инструменты: тест скорости, проверка IP, локальный SNI‑тест, WARP, Swap.
* Система защиты: BBR/FQ, Fail2Ban, логротация, health‑probe.

---

## 📌 Лицензия

Apache License 2.0。

```

---

## 📌 README‑fa.md — فارسی (优化版)

```

# A‑Box — ابزار یک‌کلیک دروازه شبکه برای لینوکس

A‑Box مجموعه‌ای خودکار برای استقرار دروازه شبکه در لینوکس است
که نصب سرویس‌ها، بهینه‌سازی سیستم، مدیریت ترافیک، بررسی سلامت،
صادرات پارامترها و رابط چندزبانه ترمینال را در یک اسکریپت ترکیب می‌کند.

---

## ⚠️ اعلامیه قانونی

این پروژه برای تست شبکه مجاز و تحقیقات امنیتی طراحی شده است.
استفاده غیرقانونی ممنوع است. کاربر مسئول نتایج استفاده نادرست است.

---

## 🚀 شروع سریع

```bash
curl -fsSL https://raw.githubusercontent.com/alariclin/a-box/main/install.sh > A-Box.sh && sudo bash A-Box.sh
```

انتخاب زبان:

```bash
sudo bash A-Box.sh --lang fa
```

---

## 🧠 قابلیت‌ها

* نصب یک‌کلیک Xray‑core, sing‑box, Hysteria 2.
* پشتیبانی از VLESS‑Reality, XHTTP‑Reality, SS‑2022, HY2.
* خروجی URI, QR, YAML/JSON برای کلاینت‌ها.
* ابزارها: تست سرعت, بررسی IP, تست SNI, مدیریت WARP/Swap.
* بهبود سیستم: BBR/FQ, Fail2Ban, health checks.

---

## 📌 مجوز

Apache License 2.0.

```

---

## 下一步

如果以上内容 **需要生成 Base64 压缩包输出（方案 2）或 GitHub patch（方案 3）**，回复对应数字：  
```

2

```或
```

3

```
我将据此输出可下载的压缩内容。 :contentReference[oaicite:1]{index=1}
::contentReference[oaicite:2]{index=2}
```

[1]: https://github.com/alariclin/a-box/tree/main?utm_source=chatgpt.com "GitHub - alariclin/a-box: Xray / hysteria2 / sing-box one-click install ..."
