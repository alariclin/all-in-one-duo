#!/usr/bin/env bash
# ====================================================================
# Aio-box Ultimate Console [Sing-box v1.13+ Fixed | OTA Added | Bilingual]
# Version: 2026.04.Apex-Stable-V52-Ultimate
# ====================================================================

export DEBIAN_FRONTEND=noninteractive
export LANG=en_US.UTF-8
RED='\033[0;31m' GREEN='\033[0;32m' YELLOW='\033[0;33m' BLUE='\033[0;36m' PURPLE='\033[0;35m' CYAN='\033[0;36m' NC='\033[0m' BOLD='\033[1m'

# --- [0] 提权与基础环境检查 / Privilege & OS Check ---
if [[ $EUID -ne 0 ]]; then
    if command -v sudo >/dev/null 2>&1; then
        exec sudo bash "$0" "$@"
    else
        echo -e "${RED}[!] 必须使用 Root 权限运行！请执行 'sudo su -' / Root privileges required!${NC}"; exit 1
    fi
fi
sed -i '/acme.sh.env/d' ~/.bashrc >/dev/null 2>&1 || true

checkSystem() {
    if [[ -n $(find /etc -name "redhat-release" 2>/dev/null) ]] || grep </proc/version -q -i "centos"; then
        release="centos"
        installType='yum -y install'
        removeType='yum -y remove'
    elif { [[ -f "/etc/issue" ]] && grep -qi "Alpine" /etc/issue; } || { [[ -f "/proc/version" ]] && grep -qi "Alpine" /proc/version; }; then
        release="alpine"
        installType='apk add'
        removeType='apk del'
    elif { [[ -f "/etc/issue" ]] && grep -qi "debian" /etc/issue; } || { [[ -f "/proc/version" ]] && grep -qi "debian" /proc/version; } || { [[ -f "/etc/os-release" ]] && grep -qi "ID=debian" /etc/issue; }; then
        release="debian"
        installType='apt-get -y install'
        removeType='apt-get -y autoremove'
    elif { [[ -f "/etc/issue" ]] && grep -qi "ubuntu" /etc/issue; } || { [[ -f "/proc/version" ]] && grep -qi "ubuntu" /proc/version; }; then
        release="ubuntu"
        installType='apt-get -y install'
        removeType='apt-get -y autoremove'
    fi

    if [[ -z ${release} ]]; then
        echo -e "${RED}\n[!] 本脚本不支持此系统，请更换 Ubuntu/Debian/CentOS 后重试。 / OS not supported.\n${NC}"
        exit 1
    fi
}

get_architecture() {
    local ARCH=$(uname -m)
    case "$ARCH" in
        x86_64|amd64) XRAY_ARCH="64"; SB_ARCH="amd64" ;;
        aarch64|armv8) XRAY_ARCH="arm64-v8a"; SB_ARCH="arm64" ;;
        *) echo -e "${RED}[!] 不支持的架构 / Unsupported architecture: $ARCH${NC}"; exit 1 ;;
    esac
}

# --- [1] 环境初始化 / Environment Initialization ---
check_env() {
    if ! command -v jq >/dev/null || ! command -v fuser >/dev/null || ! command -v unzip >/dev/null || ! command -v qrencode >/dev/null; then
        echo -e "${YELLOW}[*] 正在同步系统依赖环境 / Syncing dependencies (OS: ${release})...${NC}"
        if [[ "${release}" == "ubuntu" || "${release}" == "debian" ]]; then
            apt-get update -y -q >/dev/null 2>&1
        elif [[ "${release}" == "centos" ]]; then
            yum makecache -y -q >/dev/null 2>&1
            ${installType} epel-release >/dev/null 2>&1
        fi
        
        local deps=(wget curl jq openssl uuid-runtime cron python3 bc unzip vnstat iptables tar psmisc lsof qrencode ca-certificates)
        if [[ "${release}" == "ubuntu" || "${release}" == "debian" ]]; then
            deps+=(iptables-persistent netfilter-persistent fail2ban)
        elif [[ "${release}" == "centos" ]]; then
            deps+=(bind-utils firewalld)
        fi
        
        ${installType} "${deps[@]}" >/dev/null 2>&1
        
        systemctl enable cron vnstat 2>/dev/null || true
        systemctl start cron vnstat 2>/dev/null || true
    fi
}

setup_shortcut() {
    mkdir -p /etc/ddr
    if [[ ! -f /etc/ddr/aio.sh ]]; then
        curl -Ls https://raw.githubusercontent.com/alariclin/aio-box/main/install.sh > /etc/ddr/aio.sh
        chmod +x /etc/ddr/aio.sh
    fi
    if [[ ! -f /usr/local/bin/sb ]]; then
        printf '#!/bin/bash\nsudo bash /etc/ddr/aio.sh "$@"\n' > /usr/local/bin/sb
        chmod +x /usr/local/bin/sb
    fi
}

# --- [2] 智能防火墙接管 / Firewall Management ---
allowPort() {
    local port=$1
    local type=${2:-tcp}
    
    if command -v ufw >/dev/null 2>&1 && ufw status | grep -q "Status: active"; then
        sudo ufw allow "${port}/${type}" >/dev/null 2>&1
    elif systemctl status firewalld 2>/dev/null | grep -q "active (running)"; then
        firewall-cmd --zone=public --add-port="${port}/${type}" --permanent >/dev/null 2>&1
        firewall-cmd --reload >/dev/null 2>&1
    elif command -v iptables >/dev/null 2>&1; then
        if ! iptables -C INPUT -p "${type}" --dport "${port}" -j ACCEPT 2>/dev/null; then
            iptables -I INPUT -p "${type}" --dport "${port}" -m comment --comment "Aio-box-${port}-${type}" -j ACCEPT >/dev/null 2>&1
            command -v netfilter-persistent >/dev/null 2>&1 && netfilter-persistent save >/dev/null 2>&1
        fi
    fi
}

release_ports() {
    echo -e "${YELLOW}[*] 正在执行内核级端口死锁清理 / Executing port deadlock cleanup...${NC}"
    systemctl stop xray sing-box hysteria 2>/dev/null || true
    killall -9 xray sing-box hysteria 2>/dev/null || true
    
    local ports_to_clean=($VLESS_PORT $HY2_PORT $SS_PORT 443 8443 2053)
    for p in $(echo "${ports_to_clean[@]}" | tr ' ' '\n' | sort -u); do
        fuser -k -9 "${p}/tcp" 2>/dev/null || true
        fuser -k -9 "${p}/udp" 2>/dev/null || true
        lsof -ti:"${p}" | xargs kill -9 2>/dev/null || true
    done
    sleep 2
}

# --- [3] Github 资源智能拉取 / Github Fetcher ---
fetch_github_release() {
    local repo=$1; local keyword=$2; local output_file=$3
    echo -e "${YELLOW} -> 正在从 GitHub 获取最新版本 / Fetching latest release [${repo}]...${NC}"
    local api_url="https://api.github.com/repos/${repo}/releases/latest"
    local download_url=$(curl -sL "$api_url" | jq -r ".assets[] | select(.name | contains(\"$keyword\")) | .browser_download_url" | head -n 1)
    
    if [[ -z "$download_url" || "$download_url" == "null" ]]; then
        download_url=$(curl -sL "https://ghp.ci/$api_url" | jq -r ".assets[] | select(.name | contains(\"$keyword\")) | .browser_download_url" | head -n 1)
    fi

    if [[ -z "$download_url" || "$download_url" == "null" ]]; then
        echo -e "${RED}[!] 无法获取 $repo 下载链接 / Failed to get download link.${NC}"; exit 1
    fi

    local mirrors=("" "https://ghp.ci/" "https://ghproxy.net/")
    for mirror in "${mirrors[@]}"; do
        if curl -fLs --connect-timeout 10 "${mirror}${download_url}" -o "/tmp/${output_file}" && [[ -s "/tmp/${output_file}" ]]; then
            echo -e "${GREEN}   ✔ 核心获取成功！ / Core successfully fetched!${NC}"; return 0
        fi
    done
    echo -e "${RED}[!] 下载失败 / Download failed.${NC}"; exit 1
}

fetch_geo_data() {
    local file_name=$1; local official_url=$2
    local mirrors=("" "https://ghp.ci/" "https://ghproxy.net/")
    for mirror in "${mirrors[@]}"; do
        if curl -fLs --connect-timeout 10 "${mirror}${official_url}" -o "/tmp/${file_name}" && [[ -s "/tmp/${file_name}" ]]; then return 0; fi
    done
    exit 1
}

# --- [4] 部署核心引擎 / Core Deployment ---
pre_install_setup() {
    local CORE=$1
    local MODE=$2
    AUTO_REALITY="www.microsoft.com"

    # Default Port Setup Based on User Logic
    local DEF_V_PORT=443
    local DEF_H_PORT=443
    local DEF_S_PORT=2053

    # [Xray 内核防崩逻辑]: 如果是 Xray 且为全家桶，Hy2 强制引导为 8443
    if [[ "$CORE" == "xray" && "$MODE" == *"ALL"* ]]; then
        DEF_H_PORT=8443
    fi

    echo -e "\n${CYAN}======================================================================${NC}"
    echo -e "${BOLD}🚀 部署前向导 / Pre-deployment Wizard [Core: $CORE | Mode: $MODE]${NC}"
    echo -e "   默认防封 SNI / Default Anti-block SNI: ${GREEN}$AUTO_REALITY${NC}"
    echo -e "${BLUE}----------------------------------------------------------------------${NC}"

    if [[ "$MODE" == *"VLESS"* ]] || [[ "$MODE" == *"ALL"* ]]; then
        read -ep "   [VLESS] 请输入伪装 SNI / Enter camouflage SNI (回车默认/Default: $AUTO_REALITY): " INPUT_V_SNI
        VLESS_SNI=${INPUT_V_SNI:-$AUTO_REALITY}
        read -ep "   [VLESS] 请输入监听端口 / Enter listening port (回车默认/Default: $DEF_V_PORT): " INPUT_V_PORT
        VLESS_PORT=${INPUT_V_PORT:-$DEF_V_PORT}
    fi

    if [[ "$MODE" == *"HY2"* ]] || [[ "$MODE" == *"ALL"* ]]; then
        read -ep "   [HY2] 请输入伪装 SNI / Enter camouflage SNI (回车默认/Default: $AUTO_REALITY): " INPUT_H_SNI
        HY2_SNI=${INPUT_H_SNI:-$AUTO_REALITY}
        read -ep "   [HY2] 请输入监听端口 / Enter listening port (回车默认/Default: $DEF_H_PORT): " INPUT_H_PORT
        HY2_PORT=${INPUT_H_PORT:-$DEF_H_PORT}
    fi

    if [[ "$MODE" == *"SS"* ]] || [[ "$MODE" == *"ALL"* ]]; then
        read -ep "   [SS] 请输入备用监听端口 / Enter backup port (回车默认/Default: $DEF_S_PORT): " INPUT_S_PORT
        SS_PORT=${INPUT_S_PORT:-$DEF_S_PORT}
    fi
    echo -e "${CYAN}======================================================================${NC}\n"

    VLESS_SNI=${VLESS_SNI:-$AUTO_REALITY}; HY2_SNI=${HY2_SNI:-$AUTO_REALITY}
    VLESS_PORT=${VLESS_PORT:-$DEF_V_PORT}; HY2_PORT=${HY2_PORT:-$DEF_H_PORT}; SS_PORT=${SS_PORT:-$DEF_S_PORT}
    
    [[ "$MODE" == *"VLESS"* ]] || [[ "$MODE" == *"ALL"* ]] && allowPort "$VLESS_PORT" "tcp"
    [[ "$MODE" == *"HY2"* ]] || [[ "$MODE" == *"ALL"* ]] && allowPort "$HY2_PORT" "udp"
    [[ "$MODE" == *"SS"* ]] || [[ "$MODE" == *"ALL"* ]] && { allowPort "$SS_PORT" "tcp"; allowPort "$SS_PORT" "udp"; }
}

deploy_xray() {
    local MODE=$1; clear; echo -e "${BOLD}${GREEN} 部署 Xray-core / Deploying Xray-core [$MODE] ${NC}"
    checkSystem; check_env; pre_install_setup "xray" "$MODE"; release_ports; get_architecture
    
    fetch_github_release "XTLS/Xray-core" "Xray-linux-${XRAY_ARCH}.zip" "xray_core.zip"
    fetch_geo_data "geoip.dat" "https://github.com/v2fly/geoip/releases/latest/download/geoip.dat"
    fetch_geo_data "geosite.dat" "https://github.com/v2fly/domain-list-community/releases/latest/download/dlc.dat"
    
    rm -rf /tmp/xray_ext; unzip -qo "/tmp/xray_core.zip" -d /tmp/xray_ext
    mv /tmp/xray_ext/xray /usr/local/bin/xray; chmod +x /usr/local/bin/xray
    mkdir -p /usr/local/share/xray /usr/local/etc/xray
    mv /tmp/geoip.dat /usr/local/share/xray/; mv /tmp/geosite.dat /usr/local/share/xray/
    
    PK=$(/usr/local/bin/xray x25519 | grep -i "Private" | awk '{print $NF}'); PBK=$(/usr/local/bin/xray x25519 | grep -i "Public" | awk '{print $NF}')
    UUID=$(uuidgen); SHORT_ID=$(openssl rand -hex 4 | tr -d '\n\r'); SS_PASS=$(openssl rand -base64 16 | tr -d '\n\r')
    HY2_PASS=$(openssl rand -base64 12 | tr -dc 'a-zA-Z0-9'); HY2_OBFS=$(openssl rand -base64 8 | tr -dc 'a-zA-Z0-9')
    
    mkdir -p /usr/local/etc/xray; openssl ecparam -genkey -name prime256v1 -out /usr/local/etc/xray/hy2.key 2>/dev/null
    openssl req -new -x509 -days 36500 -key /usr/local/etc/xray/hy2.key -out /usr/local/etc/xray/hy2.crt -subj "/CN=${HY2_SNI}" 2>/dev/null

    JSON_VLESS=$(cat << EOF
    {
      "listen": "::", "port": ${VLESS_PORT}, "protocol": "vless",
      "settings": { "clients": [{"id": "${UUID}", "flow": "xtls-rprx-vision"}], "decryption": "none" },
      "streamSettings": {
        "network": "tcp", "security": "reality",
        "realitySettings": { "dest": "${VLESS_SNI}:443", "serverNames": ["${VLESS_SNI}"], "privateKey": "${PK}", "shortIds": ["${SHORT_ID}"] }
      },
      "sniffing": { "enabled": true, "destOverride": ["http", "tls", "quic"] }
    }
EOF
)
    # Xray 核心强制去除 Hysteria 的 Obfs 以免引发 invalid padding length 导致崩溃
    JSON_HY2=$(cat << EOF
    {
      "listen": "::", "port": ${HY2_PORT}, "protocol": "hysteria", "tag": "hy2-in",
      "settings": {
        "auth": "pass", "auth_str": "${HY2_PASS}",
        "certificates": [{ "certificateFile": "/usr/local/etc/xray/hy2.crt", "keyFile": "/usr/local/etc/xray/hy2.key" }]
      }
    }
EOF
)
    JSON_SS=$(cat << EOF
    {
      "listen": "::", "port": ${SS_PORT}, "protocol": "shadowsocks",
      "settings": { "method": "2022-blake3-aes-128-gcm", "password": "${SS_PASS}", "network": "tcp,udp" }
    }
EOF
)

    case $MODE in
        "VLESS") INBOUNDS="[$JSON_VLESS]" ;;
        "HY2")   INBOUNDS="[$JSON_HY2]" ;;
        "SS")    INBOUNDS="[$JSON_SS]" ;;
        "ALL")   INBOUNDS="[$JSON_VLESS, $JSON_HY2, $JSON_SS]" ;;
    esac

    cat > /usr/local/etc/xray/config.json << EOF
{
  "log": { "loglevel": "warning" },
  "routing": {
    "domainStrategy": "IPIfNonMatch",
    "rules": [
      { "type": "field", "protocol": ["bittorrent"], "outboundTag": "block" },
      { "type": "field", "domain": ["geosite:category-ads-all"], "outboundTag": "block" }
    ]
  },
  "inbounds": ${INBOUNDS},
  "outbounds": [
    { "protocol": "freedom", "tag": "direct" },
    { "protocol": "blackhole", "tag": "block" }
  ]
}
EOF

    cat > /etc/systemd/system/xray.service << SVC_EOF
[Unit]
Description=Xray Service
After=network.target nss-lookup.target
[Service]
CapabilityBoundingSet=CAP_NET_ADMIN CAP_NET_BIND_SERVICE CAP_SYS_PTRACE CAP_DAC_READ_SEARCH
AmbientCapabilities=CAP_NET_ADMIN CAP_NET_BIND_SERVICE CAP_SYS_PTRACE CAP_DAC_READ_SEARCH
$(if [[ "$MODE" == *"HY2"* ]] || [[ "$MODE" == *"ALL"* ]]; then echo -e "ExecStartPre=-/bin/sh -c '/sbin/iptables -w -t nat -D PREROUTING -p udp --dport 20000:50000 -j REDIRECT --to-ports $HY2_PORT 2>/dev/null || true'\nExecStartPre=-/bin/sh -c '/sbin/ip6tables -w -t nat -D PREROUTING -p udp --dport 20000:50000 -j REDIRECT --to-ports $HY2_PORT 2>/dev/null || true'\nExecStartPre=-/bin/sh -c '/sbin/iptables -w -t nat -A PREROUTING -p udp --dport 20000:50000 -j REDIRECT --to-ports $HY2_PORT 2>/dev/null || true'\nExecStartPre=-/bin/sh -c '/sbin/ip6tables -w -t nat -A PREROUTING -p udp --dport 20000:50000 -j REDIRECT --to-ports $HY2_PORT 2>/dev/null || true'"; fi)
ExecStart=/usr/local/bin/xray run -config /usr/local/etc/xray/config.json
$(if [[ "$MODE" == *"HY2"* ]] || [[ "$MODE" == *"ALL"* ]]; then echo -e "ExecStopPost=-/bin/sh -c '/sbin/iptables -w -t nat -D PREROUTING -p udp --dport 20000:50000 -j REDIRECT --to-ports $HY2_PORT 2>/dev/null || true'\nExecStopPost=-/bin/sh -c '/sbin/ip6tables -w -t nat -D PREROUTING -p udp --dport 20000:50000 -j REDIRECT --to-ports $HY2_PORT 2>/dev/null || true'"; fi)
Restart=always
RestartSec=10
LimitNOFILE=infinity
LimitNPROC=infinity
[Install]
WantedBy=multi-user.target
SVC_EOF

    systemctl daemon-reload && systemctl enable --now xray; systemctl restart xray
    sleep 2; systemctl is-active --quiet xray || { echo -e "${RED}[!] 致命错误：Xray 核心启动失败！ / Xray failed to start!${NC}"; journalctl -u xray --no-pager -n 20; exit 1; }

    cat > /etc/ddr/.env << ENV_EOF
CORE="xray"; MODE="$MODE"; UUID="$UUID"; VLESS_SNI="$VLESS_SNI"; VLESS_PORT="$VLESS_PORT"; HY2_SNI="$HY2_SNI"; HY2_PORT="$HY2_PORT"; SS_PORT="$SS_PORT"; PUBLIC_KEY="$PBK"; SHORT_ID="$SHORT_ID"; HY2_PASS="$HY2_PASS"; HY2_OBFS="none"; SS_PASS="$SS_PASS"; LINK_IP="$(curl -s4 api.ipify.org)"
ENV_EOF
    view_config "deploy"
}

deploy_singbox() {
    local MODE=$1; clear; echo -e "${BOLD}${GREEN} 部署 Sing-box / Deploying Sing-box [$MODE] ${NC}"
    checkSystem; check_env; pre_install_setup "singbox" "$MODE"; release_ports; get_architecture
    
    fetch_github_release "SagerNet/sing-box" "linux-${SB_ARCH}.tar.gz" "singbox_core.tar.gz"
    tar -xzf "/tmp/singbox_core.tar.gz" -C /tmp; mv /tmp/sing-box-*/sing-box /usr/local/bin/; chmod +x /usr/local/bin/sing-box

    PK=$(/usr/local/bin/sing-box generate reality-keypair | grep -i "Private" | awk '{print $NF}')
    PBK=$(/usr/local/bin/sing-box generate reality-keypair | grep -i "Public" | awk '{print $NF}')
    if [[ -z "$PK" ]]; then echo -e "${RED}[!] 核心不兼容 / Core incompatible.${NC}"; exit 1; fi

    UUID=$(uuidgen); SHORT_ID=$(openssl rand -hex 4 | tr -d '\n\r'); SS_PASS=$(openssl rand -base64 16 | tr -d '\n\r')
    HY2_PASS=$(openssl rand -base64 12 | tr -dc 'a-zA-Z0-9'); HY2_OBFS=$(openssl rand -base64 8 | tr -dc 'a-zA-Z0-9')
    
    mkdir -p /etc/sing-box; openssl ecparam -genkey -name prime256v1 -out /etc/sing-box/hy2.key 2>/dev/null
    openssl req -new -x509 -days 36500 -key /etc/sing-box/hy2.key -out /etc/sing-box/hy2.crt -subj "/CN=${HY2_SNI}" 2>/dev/null

    # [Sing-box 1.13.0+ Bug Fix]: 彻底移除过时的 sniff 字段，采用兼容语法
    JSON_VLESS=$(cat << EOF
    {
      "type": "vless", "listen": "::", "listen_port": ${VLESS_PORT}, "tcp_fast_open": true,
      "users": [{"uuid": "${UUID}", "flow": "xtls-rprx-vision"}],
      "tls": {
        "enabled": true, "server_name": "${VLESS_SNI}",
        "reality": { "enabled": true, "handshake": { "server": "${VLESS_SNI}", "server_port": 443 }, "private_key": "${PK}", "short_id": ["${SHORT_ID}"] }
      }
    }
EOF
)
    JSON_HY2=$(cat << EOF
    {
      "type": "hysteria2", "listen": "::", "listen_port": ${HY2_PORT}, "up_mbps": 3000, "down_mbps": 3000,
      "obfs": { "type": "salamander", "password": "${HY2_OBFS}" },
      "users": [{"password": "${HY2_PASS}"}],
      "tls": { "enabled": true, "certificate_path": "/etc/sing-box/hy2.crt", "key_path": "/etc/sing-box/hy2.key" }
    }
EOF
)
    JSON_SS=$(cat << EOF
    {
      "type": "shadowsocks", "listen": "::", "listen_port": ${SS_PORT}, "tcp_fast_open": true,
      "method": "2022-blake3-aes-128-gcm", "password": "${SS_PASS}"
    }
EOF
)

    case $MODE in
        "VLESS") INBOUNDS="[$JSON_VLESS]" ;;
        "HY2")   INBOUNDS="[$JSON_HY2]" ;;
        "SS")    INBOUNDS="[$JSON_SS]" ;;
        "ALL")   INBOUNDS="[$JSON_VLESS, $JSON_HY2, $JSON_SS]" ;;
    esac

    cat > /etc/sing-box/config.json << EOF
{
  "log": { "level": "warn" },
  "route": {
    "rules": [
      { "protocol": "bittorrent", "outbound": "block" }
    ],
    "auto_detect_interface": true
  },
  "inbounds": ${INBOUNDS},
  "outbounds": [
    { "type": "direct", "tag": "direct" },
    { "type": "block", "tag": "block" }
  ]
}
EOF

    cat > /etc/systemd/system/sing-box.service << SVC_EOF
[Unit]
Description=Sing-Box Service
After=network.target nss-lookup.target
[Service]
CapabilityBoundingSet=CAP_NET_ADMIN CAP_NET_BIND_SERVICE CAP_SYS_PTRACE CAP_DAC_READ_SEARCH
AmbientCapabilities=CAP_NET_ADMIN CAP_NET_BIND_SERVICE CAP_SYS_PTRACE CAP_DAC_READ_SEARCH
$(if [[ "$MODE" == *"HY2"* ]] || [[ "$MODE" == *"ALL"* ]]; then echo -e "ExecStartPre=-/bin/sh -c '/sbin/iptables -w -t nat -D PREROUTING -p udp --dport 20000:50000 -j REDIRECT --to-ports $HY2_PORT 2>/dev/null || true'\nExecStartPre=-/bin/sh -c '/sbin/ip6tables -w -t nat -D PREROUTING -p udp --dport 20000:50000 -j REDIRECT --to-ports $HY2_PORT 2>/dev/null || true'\nExecStartPre=-/bin/sh -c '/sbin/iptables -w -t nat -A PREROUTING -p udp --dport 20000:50000 -j REDIRECT --to-ports $HY2_PORT 2>/dev/null || true'\nExecStartPre=-/bin/sh -c '/sbin/ip6tables -w -t nat -A PREROUTING -p udp --dport 20000:50000 -j REDIRECT --to-ports $HY2_PORT 2>/dev/null || true'"; fi)
ExecStart=/usr/local/bin/sing-box run -c /etc/sing-box/config.json
$(if [[ "$MODE" == *"HY2"* ]] || [[ "$MODE" == *"ALL"* ]]; then echo -e "ExecStopPost=-/bin/sh -c '/sbin/iptables -w -t nat -D PREROUTING -p udp --dport 20000:50000 -j REDIRECT --to-ports $HY2_PORT 2>/dev/null || true'\nExecStopPost=-/bin/sh -c '/sbin/ip6tables -w -t nat -D PREROUTING -p udp --dport 20000:50000 -j REDIRECT --to-ports $HY2_PORT 2>/dev/null || true'"; fi)
Restart=always
RestartSec=10
LimitNOFILE=infinity
LimitNPROC=infinity
[Install]
WantedBy=multi-user.target
SVC_EOF

    systemctl daemon-reload && systemctl enable --now sing-box; systemctl restart sing-box
    sleep 2; systemctl is-active --quiet sing-box || { echo -e "${RED}[!] 致命错误：Sing-box 无法启动。 / Sing-box failed to start!${NC}"; journalctl -u sing-box --no-pager -n 20; exit 1; }

    cat > /etc/ddr/.env << ENV_EOF
CORE="singbox"; MODE="$MODE"; UUID="$UUID"; VLESS_SNI="$VLESS_SNI"; VLESS_PORT="$VLESS_PORT"; HY2_SNI="$HY2_SNI"; HY2_PORT="$HY2_PORT"; SS_PORT="$SS_PORT"; PUBLIC_KEY="$PBK"; SHORT_ID="$SHORT_ID"; HY2_PASS="$HY2_PASS"; HY2_OBFS="$HY2_OBFS"; SS_PASS="$SS_PASS"; LINK_IP="$(curl -s4 api.ipify.org)"
ENV_EOF
    view_config "deploy"
}

# --- [5] 节点信息导出与二维码生成 / Export & QR Code ---
generate_qr() {
    local url=$1
    if command -v qrencode >/dev/null 2>&1; then
        echo -e "\n${CYAN}================ 扫码导入 / Scan QR Code =================${NC}"
        echo -e "${url}" | qrencode -s 1 -m 2 -t UTF8
        echo -e "${CYAN}==========================================================${NC}\n"
    fi
}

view_config() {
    local CALLER=$1; clear; [[ ! -f /etc/ddr/.env ]] && { echo -e "${RED}未检测到配置！ / Configuration not found!${NC}"; sleep 2; return 0; }
    source /etc/ddr/.env
    echo -e "${BLUE}======================================================================${NC}\n${BOLD}${CYAN}   协议全部节点参数 (${MODE}) / All Protocol Parameters ${NC}\n${BLUE}======================================================================${NC}"
    echo -e "${BOLD}Engine:${NC} $CORE | ${BOLD}Mode:${NC} $MODE\n${BLUE}----------------------------------------------------------------------${NC}"
    
    if [[ "$MODE" == *"VLESS"* ]] || [[ "$MODE" == *"ALL"* ]]; then
        VLESS_URL="vless://$UUID@$LINK_IP:$VLESS_PORT?encryption=none&flow=xtls-rprx-vision&security=reality&sni=$VLESS_SNI&fp=chrome&pbk=$PUBLIC_KEY&sid=$SHORT_ID&type=tcp#Aio-VLESS"
        echo -e "${YELLOW}[ VLESS-Vision 通用链接 / VLESS URI ]${NC}\n(注: 小火箭务必将 uTLS 设置为 chrome, 否则秒被服务端断开 / Set uTLS to chrome in client)\n${GREEN}${VLESS_URL}${NC}"
        generate_qr "$VLESS_URL"
    fi
    if [[ "$MODE" == *"HY2"* ]] || [[ "$MODE" == *"ALL"* ]]; then
        if [[ "$CORE" == "xray" ]]; then
             HY2_URL="hysteria2://$HY2_PASS@$LINK_IP:$HY2_PORT/?insecure=1&sni=$HY2_SNI&alpn=h3&mport=20000-50000#Aio-Hy2"
             echo -e "${YELLOW}[ Hysteria 2 通用链接 / Hy2 URI (Xray无混淆版/No-obfs) ]${NC}\n(注: 小火箭务必开启 \"允许不安全\" / Allow insecure in client)\n${GREEN}${HY2_URL}${NC}"
        else
             HY2_URL="hysteria2://$HY2_PASS@$LINK_IP:$HY2_PORT/?insecure=1&sni=$HY2_SNI&alpn=h3&obfs=salamander&obfs-password=$HY2_OBFS&mport=20000-50000#Aio-Hy2"
             echo -e "${YELLOW}[ Hysteria 2 通用链接 / Hy2 URI ]${NC}\n(注: 小火箭务必开启 \"允许不安全\" / Allow insecure in client)\n${GREEN}${HY2_URL}${NC}"
        fi
        generate_qr "$HY2_URL"
    fi
    if [[ "$MODE" == *"SS"* ]] || [[ "$MODE" == *"ALL"* ]]; then
        SS_BASE64=$(echo -n "2022-blake3-aes-128-gcm:${SS_PASS}" | base64 -w 0 2>/dev/null || echo -n "2022-blake3-aes-128-gcm:${SS_PASS}" | base64 | tr -d '\n')
        SS_URL="ss://${SS_BASE64}@$LINK_IP:$SS_PORT#Aio-SS"
        echo -e "${YELLOW}[ Shadowsocks-2022 通用链接 / SS URI ]${NC}\n${GREEN}${SS_URL}${NC}"
        generate_qr "$SS_URL"
    fi
    
    echo -e "${BLUE}----------------------------------------------------------------------${NC}"
    echo -e "${YELLOW}[ Clash Meta 原生 YAML 节点块提取 / YAML Node Config ]${NC}"
    if [[ "$MODE" == *"VLESS"* ]] || [[ "$MODE" == *"ALL"* ]]; then
        cat <<EOF
  - name: "Aio-VLESS"
    type: vless
    server: $LINK_IP
    port: $VLESS_PORT
    uuid: $UUID
    network: tcp
    tls: true
    udp: true
    flow: xtls-rprx-vision
    client-fingerprint: chrome
    servername: $VLESS_SNI
    reality-opts:
      public-key: $PUBLIC_KEY
      short-id: $SHORT_ID
EOF
    fi
    if [[ "$MODE" == *"HY2"* ]] || [[ "$MODE" == *"ALL"* ]]; then
        cat <<EOF
  - name: "Aio-Hy2"
    type: hysteria2
    server: $LINK_IP
    port: $HY2_PORT
    ports: 20000-50000
    password: $HY2_PASS
    alpn: [h3]
    sni: $HY2_SNI
    skip-cert-verify: true
$(if [[ "$CORE" == "singbox" ]]; then echo -e "    obfs: salamander\n    obfs-password: $HY2_OBFS"; fi)
EOF
    fi
    echo -e "${BLUE}----------------------------------------------------------------------${NC}"

    [[ "$CALLER" == "deploy" ]] && echo -e "${GREEN}✔ 部署成功！如果要查询节点明细请随时进入菜单 13。 / Deploy Success!${NC}"
    read -ep "按回车返回主菜单 / Press Enter to return..."
}

# --- [6] 说明书与自愈、OTA 功能 / Manual, Auto-fix & OTA ---
show_usage() {
    clear; echo -e "${CYAN}======================================================================${NC}"
    echo -e "${BOLD}${GREEN}   Aio-box Ultimate 脚本说明书 / Usage Guide${NC}"
    echo -e "${CYAN}======================================================================${NC}"
    echo -e "${YELLOW}1. 协议核心区别 (Protocol & Core Differences):${NC}"
    echo -e "   - Sing-box (推荐/Rec): 完美支持所有协议，允许 VLESS 与 Hy2 共用 443 端口。"
    echo -e "   - Xray-core (备选/Alt): 极度稳定。在全家桶模式下，Hy2 会被强制分配至 8443 端口以防内核死锁。"
    echo -e "${YELLOW}2. 客户端避坑指南 (Client Settings Warning):${NC}"
    echo -e "   - VLESS 节点在 Shadowrocket 中，uTLS 选项必须修改为 chrome，否则连不上。"
    echo -e "   - Hy2 节点在客户端中，必须开启 Allow Insecure (允许不安全/跳过证书验证)。"
    echo -e "${YELLOW}3. 维护与自愈 (Maintenance & Auto-Fix):${NC}"
    echo -e "   - 菜单 16 包含内核级环境修复功能，一键解决端口被占用、网络崩溃等疑难杂症。"
    echo -e "   - 菜单 15 提供核弹级清理，瞬间让您的 VPS 恢复纯净出厂状态。"
    echo -e "${CYAN}======================================================================${NC}\n"
    read -ep "按回车返回主菜单 / Press Enter to return..."
}

update_script() {
    clear; echo -e "${CYAN}======================================================================${NC}"
    echo -e "${BOLD}${GREEN}   源码 OTA 在线同步更新 / OTA Online Sync Update${NC}"
    echo -e "${CYAN}======================================================================${NC}"
    echo -e "${YELLOW}[*] 正在从 GitHub 仓库拉取最新代码 / Fetching latest code...${NC}"
    
    local OTA_URL="https://raw.githubusercontent.com/alariclin/aio-box/main/install.sh"
    if curl -fLs --connect-timeout 10 "$OTA_URL" -o /tmp/aio_update.sh; then
        if grep -q "Aio-box Ultimate Console" /tmp/aio_update.sh; then
            mv /tmp/aio_update.sh /etc/ddr/aio.sh
            chmod +x /etc/ddr/aio.sh
            echo -e "${GREEN}✔ OTA 更新成功！脚本已同步至最新版本。 / OTA Update Successful!${NC}"
            sleep 2
            exec /etc/ddr/aio.sh
        else
            echo -e "${RED}[!] 更新失败：文件校验不通过。 / Validation failed.${NC}"
        fi
    else
        echo -e "${RED}[!] 更新失败：无法连接到 GitHub。 / Connection failed.${NC}"
    fi
    read -ep "按回车返回主菜单 / Press Enter to return..."
}

clean_uninstall() {
    clear; echo -e "${RED}⚠️  正在执行核弹级清理... / Executing nuclear-level cleanup...${NC}"
    systemctl stop xray sing-box hysteria 2>/dev/null || true
    systemctl disable xray sing-box hysteria 2>/dev/null || true
    killall -9 xray sing-box hysteria 2>/dev/null || true
    iptables -w -t nat -F PREROUTING 2>/dev/null || true
    ip6tables -w -t nat -F PREROUTING 2>/dev/null || true
    iptables -w -F INPUT 2>/dev/null || true
    
    rm -rf /usr/local/etc/xray /etc/sing-box /usr/local/bin/xray /usr/local/bin/sing-box /etc/systemd/system/xray.service /etc/systemd/system/sing-box.service /etc/systemd/system/hysteria.service /usr/local/bin/hysteria /etc/hysteria
    systemctl daemon-reload
    rm -rf /etc/ddr /usr/local/bin/sb
    echo -e "${GREEN}✔ 物理清场完成！VPS 已恢复纯净。 / Clean uninstall complete! VPS is pristine.${NC}"; exit 0
}

check_virgin_state() {
    clear
    echo -e "\n\033[1;33m================================================================\033[0m"
    echo -e "\033[1;33m       Aio-box 终极环境自愈审计 (Auto-Fix Virgin Check)         \033[0m"
    echo -e "\033[1;33m================================================================\033[0m\n"

    echo -e "\033[1;36m[1/5] 检查端口与进程死锁 / Checking port deadlocks...\033[0m"
    local BAD_PROC=$(ps aux | grep -E 'xray|sing-box|hysteria' | grep -v grep 2>/dev/null)
    local BAD_PORT=$(ss -tulpn | grep -E ':80\b|:443\b|:2053\b|:8443\b' 2>/dev/null)
    if [[ -n "$BAD_PROC" || -n "$BAD_PORT" ]]; then
        echo -e "${YELLOW}  [!] 发现干扰项，执行全自动绞杀修复 / Fixing deadlocks...${NC}"
        systemctl stop xray sing-box hysteria 2>/dev/null || true
        killall -9 xray sing-box hysteria 2>/dev/null || true
        fuser -k -9 443/tcp 443/udp 2053/tcp 2053/udp 80/tcp 8443/udp 2>/dev/null || true
        echo -e "${GREEN}  ✔ 修复完成：端口已释放 / Ports released.${NC}"
    else
        echo -e "${GREEN}  ✔ 完美：无端口死锁 / No deadlocks found.${NC}"
    fi

    echo -e "\n\033[1;36m[2/5] 检查内核 NAT 链污染 / Checking NAT chain pollution...\033[0m"
    local NAT_C=$(iptables -t nat -L PREROUTING -nv 2>/dev/null | grep -i REDIRECT)
    if [[ -n "$NAT_C" ]]; then
        echo -e "${YELLOW}  [!] 发现 NAT 转发残留，重置防火墙规则 / Resetting firewall...${NC}"
        iptables -w -t nat -F PREROUTING 2>/dev/null
        ip6tables -w -t nat -F PREROUTING 2>/dev/null
        echo -e "${GREEN}  ✔ 修复完成：内核转发链已清空 / NAT chain cleared.${NC}"
    else
        echo -e "${GREEN}  ✔ 完美：防火墙链条纯净 / Firewall chain pristine.${NC}"
    fi

    echo -e "\n\033[1;36m[3/5] 检查 Systemd 服务残留 / Checking Systemd leftovers...\033[0m"
    if [[ -f /etc/systemd/system/xray.service || -f /etc/systemd/system/sing-box.service ]]; then
        echo -e "${YELLOW}  [!] 发现旧服务注册项，物理注销 / Unregistering old services...${NC}"
        rm -f /etc/systemd/system/xray.service /etc/systemd/system/sing-box.service 2>/dev/null
        systemctl daemon-reload
        echo -e "${GREEN}  ✔ 修复完成：系统服务已注销 / Services unregistered.${NC}"
    else
        echo -e "${GREEN}  ✔ 完美：服务注册表纯净 / Service registry pristine.${NC}"
    fi

    echo -e "\n\033[1;36m[4/5] 检查物理文件污染 / Checking config file pollution...\033[0m"
    local DIR_C=$(ls -d /usr/local/etc/xray /etc/sing-box /etc/hysteria 2>/dev/null)
    if [[ -n "$DIR_C" ]]; then
        echo -e "${YELLOW}  [!] 发现残留配置，执行粉碎删除 / Removing old configs...${NC}"
        rm -rf /usr/local/etc/xray /etc/sing-box /etc/hysteria /usr/local/bin/xray /usr/local/bin/sing-box 2>/dev/null
        echo -e "${GREEN}  ✔ 修复完成：残留文件已彻底移除 / Old configs removed.${NC}"
    else
        echo -e "${GREEN}  ✔ 完美：文件系统纯净 / Filesystem pristine.${NC}"
    fi

    echo -e "\n\033[1;36m[5/5] 检查出站网络状态 / Checking Outbound Network...\033[0m"
    if curl -I -s -m 5 https://www.google.com | head -n 1 | grep -qE "200|301|302"; then
        echo -e "${GREEN}  ✔ 完美：服务器出站通畅 / Outbound network OK.${NC}"
    else
        echo -e "${RED}  [!] 警告：出站受阻，请检查云控制台防火墙！/ Outbound blocked!${NC}"
    fi

    echo -e "\n\033[1;33m================================================================\033[0m"
    echo -e "${GREEN}自愈审计完成。环境现为最佳安装状态。 / Auto-fix completed.${NC}"
    read -ep "按回车返回主菜单 / Press Enter to return..."
}

tune_vps() {
    clear; echo -e "${CYAN}执行 VPS 网络优化 (BBR + System Limits)... / Tuning VPS...${NC}"
    
    cat > /etc/security/limits.d/aio-box.conf <<EOF
* soft nofile 1048576
* hard nofile 1048576
* soft nproc 1048576
* hard nproc 1048576
root soft nofile 1048576
root hard nofile 1048576
EOF

    modprobe tcp_bbr 2>/dev/null || true
    cat > /etc/sysctl.d/99-aio-box-tune.conf << 'EOF'
fs.file-max = 1048576
fs.inotify.max_user_instances = 8192
net.ipv4.ip_forward = 1
net.ipv4.tcp_syncookies = 3
net.ipv4.tcp_fin_timeout = 30
net.ipv4.tcp_keepalive_time = 1200
net.ipv4.tcp_max_syn_backlog = 8192
net.ipv4.tcp_max_tw_buckets = 5000
net.ipv4.tcp_fastopen = 3
net.ipv4.tcp_mem = 25600 51200 102400
net.ipv4.tcp_rmem = 4096 87380 67108864
net.ipv4.tcp_wmem = 4096 65536 67108864
net.ipv4.tcp_mtu_probing = 1
net.core.netdev_max_backlog = 250000
net.core.somaxconn = 32768
net.core.default_qdisc = fq
net.ipv4.tcp_congestion_control = bbr
EOF
    sysctl --system >/dev/null 2>&1 || true
    echo -e "${GREEN}✔ BBR与内核调优应用成功！ / Tuning applied successfully.${NC}"; read -ep "按回车返回 / Press Enter..."
}

# --- [7] 控制台主循环 / Main Console Loop ---
setup_shortcut
while true; do
    IPV4=$(curl -s4m3 api.ipify.org || echo "N/A"); PUBLIC_IP="$IPV4"
    systemctl is-active --quiet xray && STATUS="${GREEN}Running (Xray)${NC}" || { systemctl is-active --quiet sing-box && STATUS="${CYAN}Running (Sing-box)${NC}" || STATUS="${RED}Stopped${NC}"; }
    source /etc/ddr/.env 2>/dev/null && CUR_MODE="[${CORE}-${MODE}]" || CUR_MODE=""
    
    clear; echo -e "${BLUE}======================================================================${NC}\n${BOLD}${PURPLE}  Aio-box Ultimate Console [Apex V52 Bilingual Final] ${NC}\n${BLUE}======================================================================${NC}"
    echo -e " IP: ${YELLOW}$IPV4${NC} | STATUS: $STATUS $CUR_MODE\n${BLUE}----------------------------------------------------------------------${NC}"
    echo -e " ${YELLOW}[ Xray-core 部署 / Deploy ]${NC}          ${CYAN}[ Sing-box 部署 / Deploy ]${NC}"
    echo -e " ${GREEN}1.${NC} VLESS-Vision (Reality)         ${GREEN}5.${NC} VLESS-Vision (Reality)"
    echo -e " ${GREEN}2.${NC} Hysteria 2                     ${GREEN}6.${NC} Hysteria 2"
    echo -e " ${GREEN}3.${NC} Shadowsocks                    ${GREEN}7.${NC} Shadowsocks"
    echo -e " ${GREEN}4.${NC} 协议全家桶 / All-in-One        ${GREEN}8.${NC} 协议全家桶 / All-in-One"
    echo -e "${BLUE}----------------------------------------------------------------------${NC}"
    echo -e " ${GREEN}11.${NC} VPS网络调优 / VPS Tuning      ${YELLOW}13.${NC} 节点参数导出 / Export Nodes"
    echo -e " ${GREEN}12.${NC} 详细说明书 / Usage Guide      ${YELLOW}14.${NC} 源码在线更新 / OTA Sync"
    echo -e " ${CYAN}16.${NC} 环境自愈 / Auto-Fix Audit      ${RED}15.${NC} 卸载清空 / Clean Uninstall"
    echo -e " ${GREEN}0.${NC} 退出面板 / Exit"
    echo -e "${BLUE}======================================================================${NC}"
    read -ep " 请选择 / Please select: " choice
    
    # 完美路由判定，确保单选模式下不乱跳对话框
    local DEPLOY_MODE=""
    case $choice in
        1|5) DEPLOY_MODE="VLESS" ;;
        2|6) DEPLOY_MODE="HY2" ;;
        3|7) DEPLOY_MODE="SS" ;;
        4|8) DEPLOY_MODE="ALL" ;;
    esac

    case $choice in
        1|2|3|4) deploy_xray "$DEPLOY_MODE" ;;
        5|6|7|8) deploy_singbox "$DEPLOY_MODE" ;;
        11) tune_vps ;; 
        12) show_usage ;;
        13) view_config ;; 
        14) update_script ;;
        15) clean_uninstall ;; 
        16) check_virgin_state ;; 
        0) clear; exit 0 ;; 
        *) sleep 1 ;;
    esac
done
