[English](README.md) | [简体中文](README-zh.md) | [Русский](README-ru.md) | [فارسی](README-fa.md)

<img width="441" height="450" alt="屏幕快照 2026-05-04 的 09 27 40 上午" src="https://github.com/user-attachments/assets/80a146fa-3a09-4fdc-883d-41e24e3df032" />


# A-Box

> Инструментарий для развертывания сетевого шлюза Linux в один шаг  
> Born May 1, 2026

**A-Box** — это автоматизированный инструмент для развертывания и обслуживания сетевого шлюза на Linux-сервере. Он объединяет установку сервисов, системную оптимизацию, управление трафиком, контроль доступа, проверки состояния, экспорт параметров, сетевые тесты и многоязычный терминальный интерфейс в одном скрипте.

**Благодарности:** Спасибо проектам Xray-core, sing-box, Hysteria и связанным open-source проектам за технические идеи и развитие экосистемы. A-Box является независимым инструментарием автоматизации.

[![Version](https://img.shields.io/badge/Version-2026.05.04-success.svg?style=flat-square)]()
[![License: Apache-2.0](https://img.shields.io/badge/License-Apache_2.0-blue.svg?style=flat-square)](LICENSE)
[![GitHub Stars](https://img.shields.io/github/stars/alariclin/a-box?style=flat-square&color=yellow)](https://github.com/alariclin/a-box/stargazers)
[![GitHub Forks](https://img.shields.io/github/forks/alariclin/a-box?style=flat-square&color=orange)](https://github.com/alariclin/a-box/network/members)

---

## Соответствие требованиям и отказ от ответственности

Проект предназначен для тестирования сетевой архитектуры, исследований в области кибербезопасности и легитимной защиты приватности только в авторизованных средах.

1. **Соблюдение закона:** Запрещено использовать проект для любых действий, нарушающих законы или правила вашей страны или региона.
2. **Ответственность пользователя:** Пользователь самостоятельно несет ответственность за юридические, эксплуатационные и безопасностные последствия неправильного использования.
3. **Техническое назначение:** Используемые технологии маршрутизации и шифрования предназначены для повышения безопасности и приватности передачи данных. Запрещено применять инструмент для незаконных атак, несанкционированного доступа или нанесения вреда сетевой инфраструктуре.
4. **Принятие условий:** Загрузка, копирование или запуск скрипта означает, что вы прочитали, поняли и приняли эти условия.

---

## Быстрый старт

Глобальный канал:

```bash
curl -fsSL https://raw.githubusercontent.com/alariclin/a-box/main/install.sh > A-Box.sh && sudo bash A-Box.sh
```

Зеркальный канал:

```bash
curl -fsSL https://ghp.ci/https://raw.githubusercontent.com/alariclin/a-box/main/install.sh > A-Box.sh && sudo bash A-Box.sh
```

Выбор языка:

```bash
sudo bash A-Box.sh --lang zh
sudo bash A-Box.sh --lang en
```

Самопроверка и статус:

```bash
sudo bash A-Box.sh --self-test
sudo bash A-Box.sh --status
```

Открыть консоль после установки:

```bash
sb
```

---

## Основные возможности

| Модуль | Описание |
| :--- | :--- |
| Установка в один шаг | Поддержка Xray-core, sing-box и официального Hysteria 2. |
| Набор протоколов | VLESS-Reality, VLESS-XHTTP-Reality, Shadowsocks-2022, Hysteria 2. |
| Рекомендуемые порты | Vision `443/TCP`, XHTTP `8443/TCP`, HY2 `443/UDP`, SS-2022 `2053/TCP+UDP`. |
| Политика SNI | Для 443 используется `www.apple.com`; для не-443 используется `www.microsoft.com`; Apple/iCloud-подобный SNI на не-443 порту вызывает предупреждение. |
| Экспорт XHTTP | Экспортирует `stream-one + h2 + smux:false`. |
| Режимы HY2 | ACME-сертификат для домена, самоподписанный сертификат с pinning, port hopping, masquerade. |
| Инструменты | Benchmark, проверка IP, локальный SNI-тест, WARP manager, 2G Swap. |
| Эксплуатация | BBR/FQ, KeepAlive, Fail2Ban, logrotate, health probe, Geo update, месячный лимит трафика, SS whitelist, `--status`. |
| Экспорт параметров | URI, QR, Clash/Mihomo YAML, примеры outbound для sing-box, JSON для v2rayN/v2rayNG. |
| Защита при переключении | Перед установкой нового core старые управляемые сервисы останавливаются; полное удаление доступно в меню 16. |

---

## Краткое меню

| Меню | Функция | Назначение |
| :--- | :--- | :--- |
| 1 | Xray Vision | Основной долгосрочный TCP-канал. |
| 2 | Xray XHTTP | Высокая пропускная способность для desktop-сценариев. |
| 3 | Xray SS-2022 | Relay / landing inbound; рекомендуется whitelist. |
| 4 | Official HY2 | UDP / QUIC / H3 для мобильных или нестабильных сетей. |
| 5 | Xray + official HY2 all-in-one | Vision + XHTTP + HY2 + SS-2022. |
| 6 | sing-box Vision | Vision для серверов с малым объемом памяти. |
| 7 | sing-box SS-2022 | SS-2022 для малых серверов. |
| 8 | sing-box Vision + SS-2022 | Легкая двухпротокольная конфигурация. |
| 9 | sing-box HY2 | HY2 на sing-box. |
| 10 | sing-box all-in-one | Vision + HY2 + SS-2022; без XHTTP. |
| 11 | Toolbox | Benchmark, IP check, SNI test, WARP, Swap. |
| 12 | VPS optimization | BBR/FQ, лимиты файлов, KeepAlive, защита, probes. |
| 13 | Display node parameters | Ссылки, QR-коды и клиентские конфигурации. |
| 14 | Manual | Полная справка в терминале. |
| 15 | OTA / Geo update | Обновление скрипта и Geo-данных. |
| 16 | Uninstall | Удаление сервисов, конфигураций и правил firewall. |
| 17 | Environment reset | Очистка старых процессов, правил и поврежденных конфигураций. |
| 18 | Monthly traffic control | Ограничение трафика на основе vnStat. |
| 19 | SS-2022 whitelist | Разрешить доступ только заданным IP/CIDR. |
| 20 | Language | Переключение китайского / английского интерфейса. |

---

## Toolbox

| Подменю | Функция |
| :--- | :--- |
| 1 | bench.sh: тест железа и скорости загрузки. |
| 2 | Check.Place: качество IP, региональные сервисы и маршруты. |
| 3 | Local SNI test: DNS, TCP, TLS и TTFB для 100 распространенных доменов. |
| 4 | Cloudflare WARP: запуск WARP manager для управления исходящей сетью. |
| 5 | 2G Swap: создание `/swapfile` для снижения риска OOM на малых серверах. |

---

## Рекомендуемые комбинации

| Цель | Рекомендация |
| :--- | :--- |
| Сбалансированный режим | Меню `5`: Xray + official HY2 all-in-one. |
| Режим для малой памяти | Меню `10`: sing-box all-in-one. |
| Основной TCP-канал | Vision `443/TCP`. |
| Высокоскоростной резерв | XHTTP `8443/TCP`. |
| Мобильная / нестабильная сеть | HY2 `443/UDP`. |
| Relay / landing path | SS-2022 `2053/TCP+UDP` + whitelist. |

---

## Системные требования

| Пункт | Требование |
| :--- | :--- |
| ОС | Debian 10+, Ubuntu 20.04+, CentOS/RHEL/Rocky/AlmaLinux 8+, Alpine Linux. |
| Init system | Systemd или OpenRC. |
| CPU | amd64 / x86_64, arm64 / aarch64. |
| Права | root или sudo. |
| Сеть | Доступ к системным репозиториям и GitHub Releases. |

---

## Обратная связь

- [GitHub Issues](https://github.com/alariclin/a-box/issues)

---

## Лицензия

Проект распространяется по лицензии [Apache License 2.0](LICENSE).
