[English](README.md) | [简体中文](README-zh.md) | [Русский](README-ru.md) | [فارسی](README-fa.md)

<img width="1254" height="1254" alt="图标" src="https://github.com/user-attachments/assets/d45171b6-17f2-45da-9c60-e6b8b64301c1" />





> ابزار یک‌مرحله‌ای درگاه شبکه برای Linux  


**A-Box** یک ابزار خودکار برای راه‌اندازی و نگهداری درگاه شبکه روی سرورهای Linux است. این ابزار نصب سرویس، بهینه‌سازی سیستم، مدیریت ترافیک، کنترل دسترسی، بررسی سلامت، خروجی گرفتن از پارامترها، تست کیفیت شبکه و رابط چندزبانه ترمینال را در یک اسکریپت جمع می‌کند.

**قدردانی:** از پروژه‌های متن‌باز Xray-core، sing-box، Hysteria و پروژه‌های مرتبط برای الهام فنی و پشتیبانی اکوسیستم سپاس‌گزاریم. A-Box یک ابزار مستقل برای خودکارسازی است.

[![Version](https://img.shields.io/badge/Version-2026.05.04-success.svg?style=flat-square)]()
[![License: Apache-2.0](https://img.shields.io/badge/License-Apache_2.0-blue.svg?style=flat-square)](LICENSE)
[![GitHub Stars](https://img.shields.io/github/stars/alariclin/a-box?style=flat-square&color=yellow)](https://github.com/alariclin/a-box/stargazers)
[![GitHub Forks](https://img.shields.io/github/forks/alariclin/a-box?style=flat-square&color=orange)](https://github.com/alariclin/a-box/network/members)

---

## انطباق و سلب مسئولیت

این پروژه برای تست معماری شبکه، پژوهش امنیت سایبری و محافظت قانونی از حریم خصوصی در محیط‌های مجاز طراحی شده است.

1. **رعایت قانون:** استفاده از این پروژه برای هر فعالیتی که با قوانین کشور یا منطقه شما در تضاد باشد ممنوع است.
2. **مسئولیت کاربر:** پیامدهای حقوقی، عملیاتی و امنیتی ناشی از استفاده نادرست یا سوءاستفاده، بر عهده کاربر است.
3. **هدف فنی:** فناوری‌های مسیریابی و رمزنگاری در این پروژه برای بهبود امنیت و حریم خصوصی انتقال داده طراحی شده‌اند. استفاده برای حمله غیرقانونی، دسترسی غیرمجاز یا آسیب به زیرساخت شبکه ممنوع است.
4. **پذیرش شرایط:** دانلود، کپی یا اجرای اسکریپت به معنی مطالعه، درک و پذیرش این شرایط است.

---

## شروع سریع

مسیر جهانی:

```bash
curl -fsSL https://raw.githubusercontent.com/alariclin/a-box/main/install.sh > A-Box.sh && sudo bash A-Box.sh
```

مسیر آینه:

```bash
curl -fsSL https://ghp.ci/https://raw.githubusercontent.com/alariclin/a-box/main/install.sh > A-Box.sh && sudo bash A-Box.sh
```

انتخاب زبان:

```bash
sudo bash A-Box.sh --lang zh
sudo bash A-Box.sh --lang en
```

خودآزمایی و وضعیت:

```bash
sudo bash A-Box.sh --self-test
sudo bash A-Box.sh --status
```

باز کردن کنسول پس از نصب:

```bash
sb
```

---

## قابلیت‌های اصلی

| بخش | توضیح |
| :--- | :--- |
| نصب یک‌مرحله‌ای | پشتیبانی از Xray-core، sing-box و نسخه رسمی Hysteria 2. |
| مجموعه پروتکل‌ها | VLESS-Reality، VLESS-XHTTP-Reality، Shadowsocks-2022، Hysteria 2. |
| پورت‌های پیشنهادی | Vision `443/TCP`، XHTTP `8443/TCP`، HY2 `443/UDP`، SS-2022 `2053/TCP+UDP`. |
| سیاست SNI | پورت 443 به‌صورت پیش‌فرض `www.apple.com`؛ پورت غیر 443 به‌صورت پیش‌فرض `www.microsoft.com`؛ SNI مشابه Apple/iCloud روی پورت غیر 443 هشدار می‌دهد. |
| خروجی XHTTP | خروجی `stream-one + h2 + smux:false`. |
| حالت‌های HY2 | گواهی ACME برای دامنه، گواهی خودامضا با pinning، پرش پورت، masquerade. |
| جعبه ابزار | Benchmark، بررسی IP، تست محلی SNI، مدیر WARP، Swap دو گیگابایتی. |
| نگهداری | BBR/FQ، KeepAlive، Fail2Ban، logrotate، health probe، Geo update، محدودیت ماهانه ترافیک، SS whitelist، `--status`. |
| خروجی پارامترها | URI، QR، فایل YAML برای Clash/Mihomo، نمونه outbound برای sing-box، JSON برای v2rayN/v2rayNG. |
| محافظت هنگام تغییر نصب | پیش از نصب core جدید، سرویس‌های قدیمی مدیریت‌شده متوقف می‌شوند؛ حذف کامل از منوی 16 انجام می‌شود. |

---

## خلاصه منو

| منو | عملکرد | کاربرد |
| :--- | :--- | :--- |
| 1 | Xray Vision | مسیر TCP اصلی و بلندمدت. |
| 2 | Xray XHTTP | مسیر پرسرعت برای دسکتاپ. |
| 3 | Xray SS-2022 | ورودی relay / landing؛ استفاده از whitelist توصیه می‌شود. |
| 4 | Official HY2 | UDP / QUIC / H3 برای موبایل یا شبکه‌های ناپایدار. |
| 5 | Xray + official HY2 all-in-one | Vision + XHTTP + HY2 + SS-2022. |
| 6 | sing-box Vision | نصب Vision برای سرورهای کم‌حافظه. |
| 7 | sing-box SS-2022 | نصب SS-2022 برای سرورهای کم‌حافظه. |
| 8 | sing-box Vision + SS-2022 | ترکیب سبک دو پروتکل. |
| 9 | sing-box HY2 | اجرای HY2 روی sing-box. |
| 10 | sing-box all-in-one | Vision + HY2 + SS-2022؛ بدون XHTTP. |
| 11 | Toolbox | Benchmark، بررسی IP، تست SNI، WARP، Swap. |
| 12 | VPS optimization | BBR/FQ، محدودیت فایل، KeepAlive، حفاظت و probe. |
| 13 | Display node parameters | لینک‌ها، QR و تنظیمات کلاینت. |
| 14 | Manual | راهنمای کامل در ترمینال. |
| 15 | OTA / Geo update | به‌روزرسانی اسکریپت و داده‌های Geo. |
| 16 | Uninstall | حذف سرویس‌ها، تنظیمات و قوانین firewall. |
| 17 | Environment reset | پاک‌سازی فرایندها، قوانین و تنظیمات خراب قدیمی. |
| 18 | Monthly traffic control | قطع ترافیک بر اساس vnStat. |
| 19 | SS-2022 whitelist | اجازه دسترسی فقط به IP/CIDR مشخص. |
| 20 | Language | تغییر رابط چینی / انگلیسی. |

---

## Toolbox

| زیرمنو | عملکرد |
| :--- | :--- |
| 1 | bench.sh: تست سخت‌افزار و سرعت دانلود. |
| 2 | Check.Place: کیفیت IP، سرویس‌های منطقه‌ای و مسیر شبکه. |
| 3 | Local SNI test: تست DNS، TCP، TLS و TTFB برای 100 دامنه رایج. |
| 4 | Cloudflare WARP: اجرای مدیر WARP برای مدیریت خروجی شبکه. |
| 5 | 2G Swap: ایجاد `/swapfile` برای کاهش خطر OOM روی سرورهای کم‌حافظه. |

---

## ترکیب‌های پیشنهادی

| هدف | پیشنهاد |
| :--- | :--- |
| حالت متعادل | منوی `5`: Xray + official HY2 all-in-one. |
| حالت کم‌حافظه | منوی `10`: sing-box all-in-one. |
| مسیر TCP اصلی | Vision `443/TCP`. |
| مسیر پشتیبان پرسرعت | XHTTP `8443/TCP`. |
| موبایل / شبکه ناپایدار | HY2 `443/UDP`. |
| مسیر relay / landing | SS-2022 `2053/TCP+UDP` + whitelist. |

---

## نیازمندی‌های سیستم

| مورد | نیازمندی |
| :--- | :--- |
| سیستم‌عامل | Debian 10+، Ubuntu 20.04+، CentOS/RHEL/Rocky/AlmaLinux 8+، Alpine Linux. |
| Init system | Systemd یا OpenRC. |
| CPU | amd64 / x86_64، arm64 / aarch64. |
| دسترسی | root یا sudo. |
| شبکه | دسترسی به مخازن بسته سیستم و GitHub Releases. |

---

## بازخورد

- [GitHub Issues](https://github.com/alariclin/a-box/issues)

---

## مجوز

این پروژه تحت مجوز [Apache License 2.0](LICENSE) منتشر شده است.
