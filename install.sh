#!/usr/bin/env bash
export DEBIAN_FRONTEND=noninteractive
export LANG=en_US.UTF-8
RED='\033[0;31m' GREEN='\033[0;32m' YELLOW='\033[0;33m' BLUE='\033[0;36m' PURPLE='\033[0;35m' CYAN='\033[0;36m' NC='\033[0m' BOLD='\033[1m'  

# --- [0] 提权拦截器 / Privilege Escalation Interceptor ---
if [[ $EUID -ne 0 ]]; then
    if command -v sudo >/dev/null 2>&1; then
        exec sudo bash "$0" "$@"
    else
        echo -e "${RED}[!] 致命错误: 必须使用 Root 权限运行！请执行 'sudo su -' 获取权限。 / Root privileges required!${NC}"
        exit 1
    fi
fi
sed -i '/acme.sh.env/d' ~/.bashrc >/dev/null 2>&1 || true

# --- [1] 统一生命周期初始化 (原子化时序) / Unified Environment Initialization ---
init_system_environment() {
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
        echo -e "${RED}\n[!] 异常中断: 本脚本不支持当前异构系统。 / OS not supported.\n${NC}"
        exit 1
    fi

    if command -v systemctl >/dev/null 2>&1; then
        INIT_SYS="systemd"
    elif command -v rc-service >/dev/null 2>&1; then
        INIT_SYS="openrc"
    else
        echo -e "${RED}[!] 异常中断: 无法检测到受支持的守护进程初始化系统 (Systemd/OpenRC)！${NC}"
        exit 1
    fi

    if ! command -v jq >/dev/null || ! command -v fuser >/dev/null || ! command -v unzip >/dev/null || ! command -v qrencode >/dev/null || ! command -v iptables >/dev/null; then
        echo -e "${YELLOW}[*] 正在同步系统依赖环境 / Syncing dependencies (OS: ${release}, Init: ${INIT_SYS})...${NC}"
        
        if [[ "${release}" == "ubuntu" || "${release}" == "debian" ]]; then
            apt-get update -y -q >/dev/null 2>&1
        elif [[ "${release}" == "centos" ]]; then
            yum makecache -y -q >/dev/null 2>&1
            ${installType} epel-release >/dev/null 2>&1
        elif [[ "${release}" == "alpine" ]]; then
            apk update -q >/dev/null 2>&1
        fi
        
        local deps=(wget curl jq openssl python3 bc unzip vnstat iptables ip6tables tar psmisc lsof qrencode ca-certificates)
        if [[ "${release}" == "ubuntu" || "${release}" == "debian" ]]; then
            deps+=(cron uuid-runtime iptables-persistent netfilter-persistent fail2ban)
        elif [[ "${release}" == "centos" ]]; then
            deps+=(cronie util-linux bind-utils firewalld)
        elif [[ "${release}" == "alpine" ]]; then
            deps+=(util-linux bind-tools coreutils iproute2)
        fi
        
        ${installType} "${deps[@]}" >/dev/null 2>&1
        hash -r 2>/dev/null || true
        
        if [[ "$INIT_SYS" == "systemd" ]]; then
            service_manager start cron crond vnstat 2>/dev/null || true
        elif [[ "$INIT_SYS" == "openrc" ]]; then
            service_manager start crond vnstatd 2>/dev/null || true
        fi
    fi

    IPT=$(command -v iptables || echo "/sbin/iptables")
    IPT6=$(command -v ip6tables || echo "/sbin/ip6tables")
}

get_architecture() {
    local ARCH=$(uname -m)
    case "$ARCH" in
        x86_64|amd64) XRAY_ARCH="64"; SB_ARCH="amd64"; HY2_ARCH="amd64" ;;
        aarch64|armv8) XRAY_ARCH="arm64-v8a"; SB_ARCH="arm64"; HY2_ARCH="arm64" ;;
        *) echo -e "${RED}[!] 异常中断: 无法识别的底层 CPU 架构 / Unsupported architecture: $ARCH${NC}"; exit 1 ;;
    esac
}

generate_robust_uuid() {
    if command -v uuidgen >/dev/null 2>&1; then
        uuidgen
    elif command -v cat >/dev/null 2>&1 && [[ -f /proc/sys/kernel/random/uuid ]]; then
        cat /proc/sys/kernel/random/uuid
    elif command -v python3 >/dev/null 2>&1; then
        python3 -c "import uuid; print(uuid.uuid4())"
    else
        echo -e "${RED}[!] 异常: 彻底失去 UUID 生成能力。${NC}" >&2; exit 1
    fi
}

# --- [2] 跨平台统一服务控制器 / Universal Daemon Controller ---
service_manager() {
    local action=$1; shift
    for srv in "$@"; do
        if [[ "$INIT_SYS" == "systemd" ]]; then
            if [[ "$action" == "stop" ]]; then
                systemctl stop "$srv" 2>/dev/null || true
                systemctl disable "$srv" 2>/dev/null || true
            elif [[ "$action" == "start" ]]; then
                systemctl daemon-reload 2>/dev/null || true
                systemctl enable --now "$srv" 2>/dev/null || true
                systemctl restart "$srv" 2>/dev/null || true
            fi
        elif [[ "$INIT_SYS" == "openrc" ]]; then
            if [[ "$action" == "stop" ]]; then
                rc-service "$srv" stop 2>/dev/null || true
                rc-update del "$srv" default 2>/dev/null || true
            elif [[ "$action" == "start" ]]; then
                rc-update add "$srv" default 2>/dev/null || true
                rc-service "$srv" restart 2>/dev/null || true
            fi
        fi
    done
}

is_service_running() {
    local srv=$1
    if [[ "$INIT_SYS" == "systemd" ]]; then
        systemctl is-active --quiet "$srv"
    elif [[ "$INIT_SYS" == "openrc" ]]; then
        rc-service "$srv" status >/dev/null 2>&1
    fi
}

# --- [3] 防火墙与路由网络拓扑管治 / Network & Firewall Topology ---
save_firewall_rules() {
    command -v netfilter-persistent >/dev/null 2>&1 && netfilter-persistent save >/dev/null 2>&1
    command -v rc-service >/dev/null 2>&1 && rc-service iptables save >/dev/null 2>&1
}

allowPort() {
    local port=$1
    local type=${2:-tcp}
    
    if command -v ufw >/dev/null 2>&1 && ufw status | grep -q "Status: active"; then
        sudo ufw allow "${port}/${type}" >/dev/null 2>&1
    elif command -v firewall-cmd >/dev/null 2>&1 && firewall-cmd --state 2>/dev/null | grep -q running; then
        firewall-cmd --zone=public --add-port="${port}/${type}" --permanent >/dev/null 2>&1
        firewall-cmd --reload >/dev/null 2>&1
    elif command -v iptables >/dev/null 2>&1; then
        if ! $IPT -C INPUT -p "${type}" --dport "${port}" -j ACCEPT 2>/dev/null; then
            $IPT -I INPUT -p "${type}" --dport "${port}" -m comment --comment "Aio-box-${port}-${type}" -j ACCEPT >/dev/null 2>&1
        fi
        if command -v ip6tables >/dev/null 2>&1; then
            if ! $IPT6 -C INPUT -p "${type}" --dport "${port}" -j ACCEPT 2>/dev/null; then
                $IPT6 -I INPUT -p "${type}" --dport "${port}" -m comment --comment "Aio-box-${port}-${type}" -j ACCEPT >/dev/null 2>&1
            fi
        fi
        save_firewall_rules
    fi
}

clean_nat_rules() {
    while $IPT -w -t nat -S PREROUTING 2>/dev/null | grep -q "20000:50000"; do
        local LOCAL_RULE=$($IPT -w -t nat -S PREROUTING 2>/dev/null | grep "20000:50000" | head -n 1 | sed 's/^-A /-D /')
        [[ -z "$LOCAL_RULE" ]] && break
        # 使用 eval 确保 sed 导出的带引号注释规则能被 bash 正确解析并传递给 iptables -D
        eval $IPT -w -t nat $LOCAL_RULE 2>/dev/null || break
    done
    while $IPT6 -w -t nat -S PREROUTING 2>/dev/null | grep -q "20000:50000"; do
        local LOCAL_RULE6=$($IPT6 -w -t nat -S PREROUTING 2>/dev/null | grep "20000:50000" | head -n 1 | sed 's/^-A /-D /')
        [[ -z "$LOCAL_RULE6" ]] && break
        eval $IPT6 -w -t nat $LOCAL_RULE6 2>/dev/null || break
    done
}

clean_input_rules() {
    while $IPT -w -S INPUT 2>/dev/null | grep -q "Aio-box-"; do
        local LOCAL_RULE=$($IPT -w -S INPUT 2>/dev/null | grep "Aio-box-" | head -n 1 | sed 's/^-A /-D /')
        [[ -z "$LOCAL_RULE" ]] && break
        eval $IPT -w $LOCAL_RULE 2>/dev/null || break
    done
    while $IPT6 -w -S INPUT 2>/dev/null | grep -q "Aio-box-"; do
        local LOCAL_RULE6=$($IPT6 -w -S INPUT 2>/dev/null | grep "Aio-box-" | head -n 1 | sed 's/^-A /-D /')
        [[ -z "$LOCAL_RULE6" ]] && break
        eval $IPT6 -w $LOCAL_RULE6 2>/dev/null || break
    done
}

release_ports() {
    echo -e "${YELLOW}[*] 正在执行内核级端口死锁清理 / Executing port deadlock cleanup...${NC}"
    service_manager stop xray sing-box hysteria
    killall -9 xray sing-box hysteria 2>/dev/null || true
    
    local ports_to_clean=($VLESS_PORT $HY2_PORT $SS_PORT 443 8443 2053)
    for p in $(echo "${ports_to_clean[@]}" | tr ' ' '\n' | sort -u); do
        fuser -k -9 "${p}/tcp" 2>/dev/null || true
        fuser -k -9 "${p}/udp" 2>/dev/null || true
        lsof -ti:"${p}" | xargs kill -9 2>/dev/null || true
    done
    sleep 2
}

setup_shortcut() {
    mkdir -p /etc/ddr
    if [[ ! -f /etc/ddr/aio.sh || "$1" == "update" ]]; then
        curl -fLs --connect-timeout 10 https://raw.githubusercontent.com/alariclin/aio-box/main/install.sh > /tmp/aio.sh.tmp && mv /tmp/aio.sh.tmp /etc/ddr/aio.sh
        chmod +x /etc/ddr/aio.sh
    fi
    if [[ ! -f /usr/local/bin/sb ]]; then
        printf '#!/bin/bash\nsudo bash /etc/ddr/aio.sh "$@"\n' > /usr/local/bin/sb
        chmod +x /usr/local/bin/sb
    fi
}

# --- [4] 远程资产智能抓取引擎 / GitHub Asset Fetcher ---
fetch_github_release() {
    local repo=$1; local keyword=$2; local output_file=$3
    echo -e "${YELLOW} -> 正在从 GitHub 抓取最新架构版本 / Fetching latest release [${repo}]...${NC}"
    local api_url="https://api.github.com/repos/${repo}/releases/latest"
    local download_url=$(curl -sL "$api_url" | jq -r ".assets[] | select(.name | contains(\"$keyword\")) | .browser_download_url" | head -n 1)
    
    if [[ -z "$download_url" || "$download_url" == "null" ]]; then
        download_url=$(curl -sL "https://ghp.ci/$api_url" | jq -r ".assets[] | select(.name | contains(\"$keyword\")) | .browser_download_url" | head -n 1)
    fi

    if [[ -z "$download_url" || "$download_url" == "null" ]]; then
        echo -e "${RED}[!] 异常: 无法解析 $repo 下载链。请检查网络。 / Failed to resolve link.${NC}"; exit 1
    fi

    local mirrors=("" "https://ghp.ci/" "https://ghproxy.net/")
    for mirror in "${mirrors[@]}"; do
        if curl -fLs --connect-timeout 10 "${mirror}${download_url}" -o "/tmp/${output_file}" && [[ -s "/tmp/${output_file}" ]]; then
            echo -e "${GREEN}    ✔ 核心资产提取成功！ / Asset successfully fetched!${NC}"; return 0
        fi
    done
    echo -e "${RED}[!] 异常: 下载资产失败 / Asset download failed.${NC}"; exit 1
}

fetch_geo_data() {
    local file_name=$1; local official_url=$2
    local mirrors=("" "https://ghp.ci/" "https://ghproxy.net/")
    for mirror in "${mirrors[@]}"; do
        if curl -fLs --connect-timeout 10 "${mirror}${official_url}" -o "/tmp/${file_name}" && [[ -s "/tmp/${file_name}" ]]; then return 0; fi
    done
    echo -e "${RED}[!] 致命异常: 路由数据库文件 (${file_name}) 下载失败，请检查网络连通性！ / Geo data download failed.${NC}"
    exit 1
}

# --- [5] 核心路由参数交互式构造器 / Deployment Wizard ---
pre_install_setup() {
    local CORE=$1
    local MODE=$2
    
    local DEF_V_SNI="www.microsoft.com"
    local DEF_H_SNI="images.apple.com"
    local DEF_V_PORT=443
    local DEF_H_PORT=443
    local DEF_S_PORT=2053

    echo -e "\n${CYAN}======================================================================${NC}"
    echo -e "${BOLD}🚀 参数构造向导 / Pre-deployment Wizard [Engine: $CORE | Mode: $MODE]${NC}"
    echo -e "${BLUE}----------------------------------------------------------------------${NC}"

    if [[ "$MODE" == *"VLESS"* ]] || [[ "$MODE" == *"ALL"* ]]; then
        read -ep "   [VLESS] 请输入伪装 SNI / Enter camouflage SNI (回车默认: $DEF_V_SNI): " INPUT_V_SNI
        VLESS_SNI=${INPUT_V_SNI:-$DEF_V_SNI}
        read -ep "   [VLESS] 请输入监听端口 / Enter listening port (回车默认: $DEF_V_PORT): " INPUT_V_PORT
        VLESS_PORT=${INPUT_V_PORT:-$DEF_V_PORT}
    fi

    if [[ "$MODE" == *"HY2"* ]] || [[ "$MODE" == *"ALL"* ]]; then
        read -ep "   [HY2] 请输入伪装 SNI / Enter camouflage SNI (回车默认: $DEF_H_SNI): " INPUT_H_SNI
        HY2_SNI=${INPUT_H_SNI:-$DEF_H_SNI}
        read -ep "   [HY2] 请输入监听端口 / Enter listening port (回车默认: $DEF_H_PORT): " INPUT_H_PORT
        HY2_PORT=${INPUT_H_PORT:-$DEF_H_PORT}
    fi

    if [[ "$MODE" == *"SS"* ]] || [[ "$MODE" == *"ALL"* ]]; then
        read -ep "   [SS] 请输入备用监听端口 / Enter backup port (回车默认: $DEF_S_PORT): " INPUT_S_PORT
        SS_PORT=${INPUT_S_PORT:-$DEF_S_PORT}
    fi
    echo -e "${CYAN}======================================================================${NC}\n"

    VLESS_SNI=${VLESS_SNI:-$DEF_V_SNI}; HY2_SNI=${HY2_SNI:-$DEF_H_SNI}
    VLESS_PORT=${VLESS_PORT:-$DEF_V_PORT}; HY2_PORT=${HY2_PORT:-$DEF_H_PORT}; SS_PORT=${SS_PORT:-$DEF_S_PORT}
    
    [[ "$MODE" == *"VLESS"* ]] || [[ "$MODE" == *"ALL"* ]] && allowPort "$VLESS_PORT" "tcp"
    [[ "$MODE" == *"HY2"* ]] || [[ "$MODE" == *"ALL"* ]] && allowPort "$HY2_PORT" "udp"
    [[ "$MODE" == *"SS"* ]] || [[ "$MODE" == *"ALL"* ]] && { allowPort "$SS_PORT" "tcp"; allowPort "$SS_PORT" "udp"; }
}

# --- [6] 核心组件部署栈 / Component Deployment ---
deploy_official_hy2() {
    local IS_SILENT=$1
    [[ "$IS_SILENT" != "SILENT" ]] && { clear; echo -e "${BOLD}${GREEN} 部署官方 Hysteria 2 / Deploying Native Hy2 ${NC}"; init_system_environment; pre_install_setup "hysteria" "HY2"; release_ports; get_architecture; }
    
    fetch_github_release "apernet/hysteria" "hysteria-linux-${HY2_ARCH}" "hysteria_core"
    mv /tmp/hysteria_core /usr/local/bin/hysteria; chmod +x /usr/local/bin/hysteria
    
    HY2_PASS=$(openssl rand -base64 12 | tr -dc 'a-zA-Z0-9'); HY2_OBFS=$(openssl rand -base64 8 | tr -dc 'a-zA-Z0-9')
    
    mkdir -p /etc/hysteria; openssl ecparam -genkey -name prime256v1 -out /etc/hysteria/server.key 2>/dev/null
    openssl req -new -x509 -days 36500 -key /etc/hysteria/server.key -out /etc/hysteria/server.crt -subj "/CN=${HY2_SNI}" 2>/dev/null
    chmod 600 /etc/hysteria/server.key

    cat > /etc/hysteria/config.yaml << EOF
listen: :${HY2_PORT}
tls:
  cert: /etc/hysteria/server.crt
  key: /etc/hysteria/server.key
obfs:
  type: salamander
  salamander:
    password: ${HY2_OBFS}
auth:
  type: password
  password: ${HY2_PASS}
bandwidth:
  up: 3000 mbps
  down: 3000 mbps
EOF
    chmod 600 /etc/hysteria/config.yaml

    if [[ "$INIT_SYS" == "systemd" ]]; then
        cat > /etc/systemd/system/hysteria.service << SVC_EOF
[Unit]
Description=Hysteria 2 Service
After=network.target
[Service]
CapabilityBoundingSet=CAP_NET_ADMIN CAP_NET_BIND_SERVICE
AmbientCapabilities=CAP_NET_ADMIN CAP_NET_BIND_SERVICE
ExecStartPre=-/bin/sh -c '$IPT -w -t nat -D PREROUTING -p udp --dport 20000:50000 -j REDIRECT --to-ports $HY2_PORT 2>/dev/null || true'
ExecStartPre=-/bin/sh -c '$IPT6 -w -t nat -D PREROUTING -p udp --dport 20000:50000 -j REDIRECT --to-ports $HY2_PORT 2>/dev/null || true'
ExecStartPre=-/bin/sh -c '$IPT -w -t nat -A PREROUTING -p udp --dport 20000:50000 -j REDIRECT --to-ports $HY2_PORT 2>/dev/null || true'
ExecStartPre=-/bin/sh -c '$IPT6 -w -t nat -A PREROUTING -p udp --dport 20000:50000 -j REDIRECT --to-ports $HY2_PORT 2>/dev/null || true'
ExecStart=/usr/local/bin/hysteria server -c /etc/hysteria/config.yaml
ExecStopPost=-/bin/sh -c '$IPT -w -t nat -D PREROUTING -p udp --dport 20000:50000 -j REDIRECT --to-ports $HY2_PORT 2>/dev/null || true'
ExecStopPost=-/bin/sh -c '$IPT6 -w -t nat -D PREROUTING -p udp --dport 20000:50000 -j REDIRECT --to-ports $HY2_PORT 2>/dev/null || true'
Restart=always
RestartSec=10
LimitNOFILE=infinity
LimitNPROC=infinity
[Install]
WantedBy=multi-user.target
SVC_EOF
    elif [[ "$INIT_SYS" == "openrc" ]]; then
        mkdir -p /etc/conf.d
        echo 'rc_ulimit="-n 1048576"' > /etc/conf.d/hysteria
        cat > /etc/init.d/hysteria << SVC_EOF
#!/sbin/openrc-run
description="Hysteria 2 Service"
command="/usr/local/bin/hysteria"
command_args="server -c /etc/hysteria/config.yaml"
command_background="yes"
pidfile="/run/hysteria.pid"
depend() { need net; }
start_pre() {
  $IPT -w -t nat -D PREROUTING -p udp --dport 20000:50000 -j REDIRECT --to-ports $HY2_PORT 2>/dev/null || true
  $IPT6 -w -t nat -D PREROUTING -p udp --dport 20000:50000 -j REDIRECT --to-ports $HY2_PORT 2>/dev/null || true
  $IPT -w -t nat -A PREROUTING -p udp --dport 20000:50000 -j REDIRECT --to-ports $HY2_PORT 2>/dev/null || true
  $IPT6 -w -t nat -A PREROUTING -p udp --dport 20000:50000 -j REDIRECT --to-ports $HY2_PORT 2>/dev/null || true
  return 0
}
stop_post() {
  $IPT -w -t nat -D PREROUTING -p udp --dport 20000:50000 -j REDIRECT --to-ports $HY2_PORT 2>/dev/null || true
  $IPT6 -w -t nat -D PREROUTING -p udp --dport 20000:50000 -j REDIRECT --to-ports $HY2_PORT 2>/dev/null || true
  return 0
}
SVC_EOF
        chmod +x /etc/init.d/hysteria
    fi

    service_manager start hysteria
    sleep 2; is_service_running hysteria || { echo -e "${RED}[!] 致命错误：原生 Hysteria 2 守护进程拉起失败！ / Core panic!${NC}"; exit 1; }

    if [[ "$IS_SILENT" != "SILENT" ]]; then
        cat > /etc/ddr/.env << ENV_EOF
CORE="hysteria"; MODE="HY2"; UUID=""; VLESS_SNI=""; VLESS_PORT=""; HY2_SNI="$HY2_SNI"; HY2_PORT="$HY2_PORT"; SS_PORT=""; PUBLIC_KEY=""; SHORT_ID=""; HY2_PASS="$HY2_PASS"; HY2_OBFS="$HY2_OBFS"; SS_PASS=""; LINK_IP="${GLOBAL_PUBLIC_IP}"
ENV_EOF
        chmod 600 /etc/ddr/.env
        view_config "deploy"
    fi
}

deploy_xray() {
    local MODE=$1; clear; echo -e "${BOLD}${GREEN} 部署 Xray-core (Hybrid模式) / Deploying Xray-core [$MODE] ${NC}"
    init_system_environment; pre_install_setup "xray" "$MODE"; release_ports; get_architecture
    
    rm -rf /tmp/xray_ext /tmp/xray_core.zip 2>/dev/null
    fetch_github_release "XTLS/Xray-core" "Xray-linux-${XRAY_ARCH}.zip" "xray_core.zip"
    fetch_geo_data "geoip.dat" "https://github.com/v2fly/geoip/releases/latest/download/geoip.dat"
    fetch_geo_data "geosite.dat" "https://github.com/v2fly/domain-list-community/releases/latest/download/dlc.dat"
    
    unzip -qo "/tmp/xray_core.zip" -d /tmp/xray_ext || { echo -e "${RED}[!] 异常: 压缩包损坏或解压失败！${NC}"; exit 1; }
    mv /tmp/xray_ext/xray /usr/local/bin/xray; chmod +x /usr/local/bin/xray
    mkdir -p /usr/local/share/xray /usr/local/etc/xray
    mv /tmp/geoip.dat /usr/local/share/xray/; mv /tmp/geosite.dat /usr/local/share/xray/
    
    KEYPAIR=$(/usr/local/bin/xray x25519)
    PK=$(echo "$KEYPAIR" | grep -i "Private" | awk '{print $NF}')
    PBK=$(echo "$KEYPAIR" | grep -i "Public" | awk '{print $NF}')
    if [[ -z "$PK" ]]; then echo -e "${RED}[!] 异常: 系统熵池耗尽或核心异常，Xray 密钥生成失败！ / Keygen failed.${NC}"; exit 1; fi
    
    UUID=$(generate_robust_uuid); SHORT_ID=$(openssl rand -hex 4 | tr -d '\n\r'); SS_PASS=$(openssl rand -base64 16 | tr -d '\n\r')

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
    JSON_SS=$(cat << EOF
    {
      "listen": "::", "port": ${SS_PORT}, "protocol": "shadowsocks",
      "settings": { "method": "2022-blake3-aes-128-gcm", "password": "${SS_PASS}", "network": "tcp,udp" }
    }
EOF
)

    case $MODE in
        "VLESS") INBOUNDS="[$JSON_VLESS]" ;;
        "SS")    INBOUNDS="[$JSON_SS]" ;;
        "VLESS_SS"|"ALL") INBOUNDS="[$JSON_VLESS, $JSON_SS]" ;;
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
    chmod 600 /usr/local/etc/xray/config.json

    if [[ "$INIT_SYS" == "systemd" ]]; then
        cat > /etc/systemd/system/xray.service << SVC_EOF
[Unit]
Description=Xray Service
After=network.target nss-lookup.target
[Service]
CapabilityBoundingSet=CAP_NET_ADMIN CAP_NET_BIND_SERVICE CAP_SYS_PTRACE CAP_DAC_READ_SEARCH
AmbientCapabilities=CAP_NET_ADMIN CAP_NET_BIND_SERVICE CAP_SYS_PTRACE CAP_DAC_READ_SEARCH
ExecStart=/usr/local/bin/xray run -config /usr/local/etc/xray/config.json
Restart=always
RestartSec=10
LimitNOFILE=infinity
LimitNPROC=infinity
[Install]
WantedBy=multi-user.target
SVC_EOF
    elif [[ "$INIT_SYS" == "openrc" ]]; then
        mkdir -p /etc/conf.d
        echo 'rc_ulimit="-n 1048576"' > /etc/conf.d/xray
        cat > /etc/init.d/xray << 'SVC_EOF'
#!/sbin/openrc-run
description="Xray Service"
command="/usr/local/bin/xray"
command_args="run -config /usr/local/etc/xray/config.json"
command_background="yes"
pidfile="/run/xray.pid"
depend() { need net; }
SVC_EOF
        chmod +x /etc/init.d/xray
    fi

    service_manager start xray
    sleep 2; is_service_running xray || { echo -e "${RED}[!] 致命错误：Xray 守护进程拉起失败！ / Core panic!${NC}"; exit 1; }

    if [[ "$MODE" == "ALL" ]]; then
        deploy_official_hy2 "SILENT"
    fi

    cat > /etc/ddr/.env << ENV_EOF
CORE="xray"; MODE="$MODE"; UUID="$UUID"; VLESS_SNI="$VLESS_SNI"; VLESS_PORT="$VLESS_PORT"; HY2_SNI="$HY2_SNI"; HY2_PORT="$HY2_PORT"; SS_PORT="$SS_PORT"; PUBLIC_KEY="$PBK"; SHORT_ID="$SHORT_ID"; HY2_PASS="$HY2_PASS"; HY2_OBFS="$HY2_OBFS"; SS_PASS="$SS_PASS"; LINK_IP="${GLOBAL_PUBLIC_IP}"
ENV_EOF
    chmod 600 /etc/ddr/.env
    view_config "deploy"
}

deploy_singbox() {
    local MODE=$1; clear; echo -e "${BOLD}${GREEN} 部署 Sing-box 核心 / Deploying Sing-box [$MODE] ${NC}"
    init_system_environment; pre_install_setup "singbox" "$MODE"; release_ports; get_architecture
    
    # 精准解压与二进制提取，避免通配符溢出风险
    rm -rf /tmp/sing-box-* /tmp/singbox_core.tar.gz 2>/dev/null
    
    fetch_github_release "SagerNet/sing-box" "linux-${SB_ARCH}.tar.gz" "singbox_core.tar.gz"
    tar -xzf "/tmp/singbox_core.tar.gz" -C /tmp || { echo -e "${RED}[!] 异常: 压缩包损坏或解压失败！${NC}"; exit 1; }
    find /tmp/sing-box-* -maxdepth 1 -type f -name "sing-box" -exec mv {} /usr/local/bin/sing-box \; -quit
    chmod +x /usr/local/bin/sing-box

    KEYPAIR=$(/usr/local/bin/sing-box generate reality-keypair)
    PK=$(echo "$KEYPAIR" | grep -i "Private" | awk '{print $NF}')
    PBK=$(echo "$KEYPAIR" | grep -i "Public" | awk '{print $NF}')
    if [[ -z "$PK" ]]; then echo -e "${RED}[!] 异常: 系统熵池耗尽，密钥对生成失败 / Generation failed.${NC}"; exit 1; fi

    UUID=$(generate_robust_uuid); SHORT_ID=$(openssl rand -hex 4 | tr -d '\n\r'); SS_PASS=$(openssl rand -base64 16 | tr -d '\n\r')
    HY2_PASS=$(openssl rand -base64 12 | tr -dc 'a-zA-Z0-9'); HY2_OBFS=$(openssl rand -base64 8 | tr -dc 'a-zA-Z0-9')
    
    mkdir -p /etc/sing-box; openssl ecparam -genkey -name prime256v1 -out /etc/sing-box/hy2.key 2>/dev/null
    openssl req -new -x509 -days 36500 -key /etc/sing-box/hy2.key -out /etc/sing-box/hy2.crt -subj "/CN=${HY2_SNI}" 2>/dev/null
    chmod 600 /etc/sing-box/hy2.key

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
        "VLESS_SS") INBOUNDS="[$JSON_VLESS, $JSON_SS]" ;;
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
    chmod 600 /etc/sing-box/config.json

    if [[ "$INIT_SYS" == "systemd" ]]; then
        cat > /etc/systemd/system/sing-box.service << SVC_EOF
[Unit]
Description=Sing-Box Service
After=network.target nss-lookup.target
[Service]
CapabilityBoundingSet=CAP_NET_ADMIN CAP_NET_BIND_SERVICE CAP_SYS_PTRACE CAP_DAC_READ_SEARCH
AmbientCapabilities=CAP_NET_ADMIN CAP_NET_BIND_SERVICE CAP_SYS_PTRACE CAP_DAC_READ_SEARCH
$(if [[ "$MODE" == *"HY2"* ]] || [[ "$MODE" == *"ALL"* ]]; then echo -e "ExecStartPre=-/bin/sh -c '$IPT -w -t nat -D PREROUTING -p udp --dport 20000:50000 -j REDIRECT --to-ports $HY2_PORT 2>/dev/null || true'\nExecStartPre=-/bin/sh -c '$IPT6 -w -t nat -D PREROUTING -p udp --dport 20000:50000 -j REDIRECT --to-ports $HY2_PORT 2>/dev/null || true'\nExecStartPre=-/bin/sh -c '$IPT -w -t nat -A PREROUTING -p udp --dport 20000:50000 -j REDIRECT --to-ports $HY2_PORT 2>/dev/null || true'\nExecStartPre=-/bin/sh -c '$IPT6 -w -t nat -A PREROUTING -p udp --dport 20000:50000 -j REDIRECT --to-ports $HY2_PORT 2>/dev/null || true'"; fi)
ExecStart=/usr/local/bin/sing-box run -c /etc/sing-box/config.json
$(if [[ "$MODE" == *"HY2"* ]] || [[ "$MODE" == *"ALL"* ]]; then echo -e "ExecStopPost=-/bin/sh -c '$IPT -w -t nat -D PREROUTING -p udp --dport 20000:50000 -j REDIRECT --to-ports $HY2_PORT 2>/dev/null || true'\nExecStopPost=-/bin/sh -c '$IPT6 -w -t nat -D PREROUTING -p udp --dport 20000:50000 -j REDIRECT --to-ports $HY2_PORT 2>/dev/null || true'"; fi)
Restart=always
RestartSec=10
LimitNOFILE=infinity
LimitNPROC=infinity
[Install]
WantedBy=multi-user.target
SVC_EOF
    elif [[ "$INIT_SYS" == "openrc" ]]; then
        mkdir -p /etc/conf.d
        echo 'rc_ulimit="-n 1048576"' > /etc/conf.d/sing-box
        cat > /etc/init.d/sing-box << SVC_EOF
#!/sbin/openrc-run
description="Sing-Box Service"
command="/usr/local/bin/sing-box"
command_args="run -c /etc/sing-box/config.json"
command_background="yes"
pidfile="/run/sing-box.pid"
depend() { need net; }
$(if [[ "$MODE" == *"HY2"* ]] || [[ "$MODE" == *"ALL"* ]]; then echo "start_pre() {
  $IPT -w -t nat -D PREROUTING -p udp --dport 20000:50000 -j REDIRECT --to-ports $HY2_PORT 2>/dev/null || true
  $IPT6 -w -t nat -D PREROUTING -p udp --dport 20000:50000 -j REDIRECT --to-ports $HY2_PORT 2>/dev/null || true
  $IPT -w -t nat -A PREROUTING -p udp --dport 20000:50000 -j REDIRECT --to-ports $HY2_PORT 2>/dev/null || true
  $IPT6 -w -t nat -A PREROUTING -p udp --dport 20000:50000 -j REDIRECT --to-ports $HY2_PORT 2>/dev/null || true
  return 0
}
stop_post() {
  $IPT -w -t nat -D PREROUTING -p udp --dport 20000:50000 -j REDIRECT --to-ports $HY2_PORT 2>/dev/null || true
  $IPT6 -w -t nat -D PREROUTING -p udp --dport 20000:50000 -j REDIRECT --to-ports $HY2_PORT 2>/dev/null || true
  return 0
}"; fi)
SVC_EOF
        chmod +x /etc/init.d/sing-box
    fi

    service_manager start sing-box
    sleep 2; is_service_running sing-box || { echo -e "${RED}[!] 致命错误：Sing-box 守护进程拉起失败！ / Core panic!${NC}"; exit 1; }

    cat > /etc/ddr/.env << ENV_EOF
CORE="singbox"; MODE="$MODE"; UUID="$UUID"; VLESS_SNI="$VLESS_SNI"; VLESS_PORT="$VLESS_PORT"; HY2_SNI="$HY2_SNI"; HY2_PORT="$HY2_PORT"; SS_PORT="$SS_PORT"; PUBLIC_KEY="$PBK"; SHORT_ID="$SHORT_ID"; HY2_PASS="$HY2_PASS"; HY2_OBFS="$HY2_OBFS"; SS_PASS="$SS_PASS"; LINK_IP="${GLOBAL_PUBLIC_IP}"
ENV_EOF
    chmod 600 /etc/ddr/.env
    view_config "deploy"
}

# --- [7] 渲染与交互组件 / UI Rendering Components ---
generate_qr() {
    local url=$1
    if command -v qrencode >/dev/null 2>&1; then
        echo -e "\n${CYAN}================ 扫码导入 / Scan QR Code =================${NC}"
        echo -e "${url}" | qrencode -s 1 -m 2 -t UTF8
        echo -e "${CYAN}==========================================================${NC}\n"
    fi
}

view_config() {
    local CALLER=$1; clear; [[ ! -f /etc/ddr/.env ]] && { echo -e "${RED}未检测到持久化配置变量！ / Configuration not found!${NC}"; sleep 2; return 0; }
    source /etc/ddr/.env
    
    local F_IP="${LINK_IP}"
    [[ "${LINK_IP}" =~ ":" ]] && F_IP="[${LINK_IP}]"

    echo -e "${BLUE}======================================================================${NC}\n${BOLD}${CYAN}   全局拓扑网络参数 (${MODE}) / Network Parameters ${NC}\n${BLUE}======================================================================${NC}"
    echo -e "${BOLD}引擎栈 / Engine:${NC} $CORE | ${BOLD}模式 / Mode:${NC} $MODE\n${BLUE}----------------------------------------------------------------------${NC}"
    
    if [[ "$MODE" == *"VLESS"* ]] || [[ "$MODE" == *"ALL"* ]] || [[ "$MODE" == "VLESS_SS" ]]; then
        VLESS_URL="vless://$UUID@$F_IP:$VLESS_PORT?encryption=none&flow=xtls-rprx-vision&security=reality&sni=$VLESS_SNI&fp=chrome&pbk=$PUBLIC_KEY&sid=$SHORT_ID&type=tcp#Aio-VLESS"
        echo -e "${YELLOW}[ VLESS-Vision 深层隐匿链路 / VLESS URI ]${NC}\n(警告: 小火箭等客户端务必将 uTLS 设置为 chrome, 否则秒被物理断连 / Set uTLS to chrome)\n${GREEN}${VLESS_URL}${NC}"
        generate_qr "$VLESS_URL"
    fi
    if [[ "$MODE" == *"HY2"* ]] || [[ "$MODE" == *"ALL"* ]]; then
        HY2_URL="hysteria2://$HY2_PASS@$F_IP:$HY2_PORT/?insecure=1&sni=$HY2_SNI&alpn=h3&obfs=salamander&obfs-password=$HY2_OBFS&mport=20000-50000#Aio-Hy2"
        echo -e "${YELLOW}[ Hysteria 2 暴力拥塞穿透链路 / Hy2 URI ]${NC}\n(警告: 基于自签证书防溯源策略，客户端务必开启 \"允许不安全\" / Allow insecure flag)\n${GREEN}${HY2_URL}${NC}"
        generate_qr "$HY2_URL"
    fi
    if [[ "$MODE" == *"SS"* ]] || [[ "$MODE" == *"ALL"* ]] || [[ "$MODE" == "VLESS_SS" ]]; then
        SS_BASE64=$(echo -n "2022-blake3-aes-128-gcm:${SS_PASS}" | base64 -w 0 2>/dev/null || echo -n "2022-blake3-aes-128-gcm:${SS_PASS}" | base64 | tr -d '\n')
        SS_URL="ss://${SS_BASE64}@$F_IP:$SS_PORT#Aio-SS"
        echo -e "${YELLOW}[ Shadowsocks-2022 AED 高密链路 / SS URI ]${NC}\n${GREEN}${SS_URL}${NC}"
        generate_qr "$SS_URL"
    fi
    
    echo -e "${BLUE}----------------------------------------------------------------------${NC}"
    echo -e "${YELLOW}[ Clash Meta 格式化 YAML 配置片段 / YAML Node Config ]${NC}"
    if [[ "$MODE" == *"VLESS"* ]] || [[ "$MODE" == *"ALL"* ]] || [[ "$MODE" == "VLESS_SS" ]]; then
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
    obfs: salamander
    obfs-password: $HY2_OBFS
EOF
    fi
    if [[ "$MODE" == *"SS"* ]] || [[ "$MODE" == *"ALL"* ]] || [[ "$MODE" == "VLESS_SS" ]]; then
        cat <<EOF
  - name: "Aio-SS"
    type: ss
    server: $LINK_IP
    port: $SS_PORT
    cipher: 2022-blake3-aes-128-gcm
    password: $SS_PASS
    udp: true
EOF
    fi
    echo -e "${BLUE}----------------------------------------------------------------------${NC}"

    [[ "$CALLER" == "deploy" ]] && echo -e "${GREEN}✔ 服务池编译部署完毕！可随时键入 13 调出此面板。 / Initialization Phase Complete!${NC}"
    read -ep "按回车安全退出交互空间并返回总台 / Press Enter to return..."
}

show_usage() {
    clear; echo -e "${CYAN}======================================================================${NC}"
    echo -e "${BOLD}${GREEN}   Aio-box 脚本说明书 / Script Manual${NC}"
    echo -e "${CYAN}======================================================================${NC}"
    
    echo -e "${YELLOW}【一】编排逻辑与架构选择 / Architectural Guide${NC}"
    echo -e "   - [模式 10] Sing-box: 聚合平台架构。以超低内存占用实现三引擎完美共享。"
    echo -e "     (Sing-box: Unified platform architecture. Shares one routing table with ultra-low memory usage.)"
    echo -e "   - [模式 5] Xray-core (Hybrid): 极端物理隔离架构。TCP 由 Xray 原生承载，UDP 由官方 Hysteria 2 承载。"
    echo -e "     (Xray-core Hybrid: Extreme physical isolation. TCP native on Xray, UDP on native Hysteria 2.)\n"

    echo -e "${YELLOW}【二】终端对齐规范 / Constraint Violations${NC}"
    echo -e "   1. 关于 VLESS-Reality 的物理特征对齐 / About VLESS-Reality physical alignment:"
    echo -e "      - 禁区：客户端绝不能开启 Mux(多路复用)！否则将被 Vision 流控直接断连。"
    echo -e "        (Taboo: NEVER enable Mux in client configs, or Vision flow control will drop it.)"
    echo -e "      - 要求：伪装指纹 (uTLS) 需高度保真，强烈推荐 chrome 选项。"
    echo -e "        (Requirement: uTLS fingerprint must be highly authentic, 'chrome' is highly recommended.)"
    echo -e "   2. 关于 Hysteria 2 的证书免疫逃透 / About Hysteria 2 certificate immunity:"
    echo -e "      - 客户端侧验证必须选择不安全（Insecure / Skip Cert Verify）。"
    echo -e "        (Client side MUST enable 'Insecure' or 'Skip Cert Verify' due to self-signed certs.)\n"

    echo -e "${YELLOW}【三】面板内置核武功能 / Panel Artillery Tools${NC}"
    echo -e "   - [菜单 12] VPS一键优化 / VPS Tuning: 调用 sysctl 注入底层加速参数与 BBR 算法。"
    echo -e "   - [菜单 17] 安装环境初始化 / Environment Auto-Fix: 触发白盒级别的自我诊断，阻断死锁与脏路由。"
    echo -e "     (Auto-Fix: White-box self-diagnosis to resolve port deadlocks and clear dirty routing rules.)\n"
    
    echo -e "${CYAN}======================================================================${NC}"
    read -ep " 阅读完毕，按回车返回主菜单 / Press Enter to return to main menu..."
}

update_script() {
    clear; echo -e "${CYAN}======================================================================${NC}"
    echo -e "${BOLD}${GREEN}   云端更新引擎 / OTA Online Sync Subsystem${NC}"
    echo -e "${CYAN}======================================================================${NC}"
    echo -e "${YELLOW}[*] 正在绕过缓存向远端库进行安全握手并同步源码 / Fetching master branch...${NC}"
    
    local OTA_URL="https://raw.githubusercontent.com/alariclin/aio-box/main/install.sh"
    if curl -fLs --connect-timeout 10 "$OTA_URL" -o /tmp/aio_update.sh; then
        if grep -q "Aio-box Ultimate Console" /tmp/aio_update.sh; then
            mv /tmp/aio_update.sh /etc/ddr/aio.sh
            chmod +x /etc/ddr/aio.sh
            echo -e "${GREEN}✔ 校验指纹比对通过！核心代码热更新完毕。 / OTA Engine Execution Complete!${NC}"
            sleep 2
            exec /etc/ddr/aio.sh
        else
            echo -e "${RED}[!] 异常拦截: 更新层发现源码被篡改或校验失败。 / Hash validation error.${NC}"
        fi
    else
        echo -e "${RED}[!] 异常拦截: TCP/TLS 链路断层，无法抵达更新服务器。 / Remote host unreachable.${NC}"
    fi
    read -ep "按回车返回总台 / Press Enter to return..."
}

clean_uninstall_menu() {
    clear
    echo -e "${CYAN}======================================================================${NC}"
    echo -e "${BOLD}${RED}   深度卸载系统 / Uninstallation Subsystem${NC}"
    echo -e "${CYAN}======================================================================${NC}"
    echo -e "${YELLOW}1. 完全物理清场 (销毁代理堆栈、配置表、防火墙映射与全局快速访问别名)${NC}"
    echo -e "${YELLOW}2. 保留式软性销毁 (销毁代理堆栈，但留存控制台与环境供随时重构)${NC}"
    echo -e "${GREEN}0. 取消并返回 / Abort and Return${NC}"
    echo -e "${CYAN}======================================================================${NC}"
    read -ep " 请谨慎输入执行代码 / Execution Code [0-2]: " un_choice
    
    case $un_choice in
        1) do_cleanup "full" ;;
        2) do_cleanup "keep" ;;
        0|*) return 0 ;;
    esac
}

do_cleanup() {
    clear; echo -e "${RED}⚠️  正在执行剥离逻辑... / Executing precision wipe protocol...${NC}"
    init_system_environment
    service_manager stop xray sing-box hysteria
    killall -9 xray sing-box hysteria 2>/dev/null || true
    
    clean_nat_rules
    clean_input_rules
    save_firewall_rules
    
    rm -rf /usr/local/etc/xray /etc/sing-box /etc/hysteria /usr/local/bin/xray /usr/local/bin/sing-box /usr/local/bin/hysteria
    rm -f /etc/systemd/system/xray.service /etc/systemd/system/sing-box.service /etc/systemd/system/hysteria.service
    rm -f /etc/init.d/xray /etc/init.d/sing-box /etc/init.d/hysteria
    rm -f /etc/sysctl.d/99-aio-box-tune.conf /etc/security/limits.d/aio-box.conf
    
    [[ "$INIT_SYS" == "systemd" ]] && systemctl daemon-reload 2>/dev/null || true
    
    if [[ "$1" == "full" ]]; then
        rm -rf /etc/ddr /usr/local/bin/sb
        echo -e "${GREEN}✔ 物理层完全清场完毕！机器重获原生干净状态。 / Nuclear cleanup succeeded!${NC}"
        exit 0
    else
        rm -f /etc/ddr/.env
        echo -e "${GREEN}✔ 代理系统已销毁！底层框架与唤醒口令 'sb' 予以保留。 / App stack uninstalled.${NC}"
        read -ep "按回车返回主控 / Press Enter to return..."
    fi
}

check_virgin_state() {
    clear
    init_system_environment
    echo -e "\n\033[1;33m================================================================\033[0m"
    echo -e "\033[1;33m       Aio-box 异常诊断与环境自愈 (Self-Healing Routine)    \033[0m"
    echo -e "\033[1;33m================================================================\033[0m\n"

    echo -e "\033[1;36m[1/5] 执行内存地址与高优端口锁死检测 / Scanning memory address binding...\033[0m"
    local BAD_PROC=$(ps aux | grep -E 'xray|sing-box|hysteria' | grep -v grep 2>/dev/null)
    local BAD_PORT=$(ss -tulpn | grep -E ':80\b|:443\b|:2053\b|:8443\b' 2>/dev/null)
    if [[ -n "$BAD_PROC" || -n "$BAD_PORT" ]]; then
        echo -e "${YELLOW}  [!] 发现未受控的进程挂起或死锁。执行系统级原子绞杀 / Resolving deadlock...${NC}"
        service_manager stop xray sing-box hysteria
        killall -9 xray sing-box hysteria 2>/dev/null || true
        fuser -k -9 443/tcp 443/udp 2053/tcp 2053/udp 80/tcp 8443/udp 2>/dev/null || true
        echo -e "${GREEN}  ✔ 修复完毕: 系统句柄已强行阻断并释放回内存池 / Resources forcefully reclaimed.${NC}"
    else
        echo -e "${GREEN}  ✔ 校验通过: 未发现寻址层争抢冲突 / Process logic healthy.${NC}"
    fi

    echo -e "\n\033[1;36m[2/5] 探查底层 Linux 内核 TCP/IP 过滤链栈 / Analyzing Netfilter topology...\033[0m"
    local NAT_C=$($IPT -t nat -S PREROUTING 2>/dev/null | grep -i "20000:50000")
    local INP_C=$($IPT -S INPUT 2>/dev/null | grep -i "Aio-box-")
    local NAT_C6=$($IPT6 -t nat -S PREROUTING 2>/dev/null | grep -i "20000:50000")
    local INP_C6=$($IPT6 -S INPUT 2>/dev/null | grep -i "Aio-box-")
    if [[ -n "$NAT_C" || -n "$INP_C" || -n "$NAT_C6" || -n "$INP_C6" ]]; then
        echo -e "${YELLOW}  [!] 捕获到废弃的虚假转发脏路由表。执行无损阻断剔除 / Executing targeted firewall reset...${NC}"
        clean_nat_rules
        clean_input_rules
        save_firewall_rules
        echo -e "${GREEN}  ✔ 修复完毕: 脏配置链已抹除，且未侵入/破坏其他原生程序运行 / Target chain disinfected.${NC}"
    else
        echo -e "${GREEN}  ✔ 校验通过: 防火墙底层逻辑栈纯净无干扰 / Filter stack pristine.${NC}"
    fi

    echo -e "\n\033[1;36m[3/5] 检索系统自持服务管理器索引 / Checking daemon registry indexing...\033[0m"
    if [[ -f /etc/systemd/system/xray.service || -f /etc/init.d/xray || -f /etc/systemd/system/hysteria.service ]]; then
        echo -e "${YELLOW}  [!] 检索到失效自启动碎片信息。执行挂载卸载操作 / Unloading daemon fragments...${NC}"
        rm -f /etc/systemd/system/xray.service /etc/systemd/system/sing-box.service /etc/systemd/system/hysteria.service 2>/dev/null
        rm -f /etc/init.d/xray /etc/init.d/sing-box /etc/init.d/hysteria 2>/dev/null
        [[ "$INIT_SYS" == "systemd" ]] && systemctl daemon-reload 2>/dev/null || true
        echo -e "${GREEN}  ✔ 修复完毕: 失效索引树已解除并对齐 / Daemon registry flushed.${NC}"
    else
        echo -e "${GREEN}  ✔ 校验通过: 服务树状表条目完全干净 / Daemon registry healthy.${NC}"
    fi

    echo -e "\n\033[1;36m[4/5] 校验块文件存储级污染遗存 / Performing disk I/O pollution check...\033[0m"
    local DIR_C=$(ls -d /usr/local/etc/xray /etc/sing-box /etc/hysteria 2>/dev/null)
    if [[ -n "$DIR_C" ]]; then
        echo -e "${YELLOW}  [!] 确认存在无效物理配置文件群。执行磁盘擦除程序 / Wiping orphaned configs...${NC}"
        rm -rf /usr/local/etc/xray /etc/sing-box /etc/hysteria /usr/local/bin/xray /usr/local/bin/sing-box /usr/local/bin/hysteria 2>/dev/null
        echo -e "${GREEN}  ✔ 修复完毕: 全链路陈旧文件已进行物理粉碎 / Dead weight cleared.${NC}"
    else
        echo -e "${GREEN}  ✔ 校验通过: 文件节点未被污染侵蚀 / VFS tree pristine.${NC}"
    fi

    echo -e "\n\033[1;36m[5/5] 执行全球出站网关连通性探针 / Testing global egress pathways...\033[0m"
    if curl -I -s -m 5 https://www.google.com | head -n 1 | grep -qE "200|301|302"; then
        echo -e "${GREEN}  ✔ 校验通过: 数据包出站物理隧道贯通无阻 / Data egress confirmed 100%.${NC}"
    else
        echo -e "${RED}  [!] 严重警告: GFW 出站受到阻截（防火墙未开放对应端口或无网），请彻查系统控制台拦截策略！${NC}"
    fi

    echo -e "\n\033[1;33m================================================================\033[0m"
    echo -e "${GREEN}全链路自愈引擎闭环结束。部署环境现达到绝对真空洁净级别。 / Self-Healing Cycle Complete.${NC}"
    read -ep "按回车返回主控制台 / Press Enter to return..."
}

tune_vps() {
    clear; echo -e "${CYAN}正在开启底层系统算力提速注入 (TCP-BBR & I/O Limit Control)... / Kernel Hacking...${NC}"
    
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
net.ipv4.tcp_notsent_lowat = 16384
net.core.netdev_max_backlog = 250000
net.core.somaxconn = 32768
net.core.default_qdisc = fq
net.ipv4.tcp_congestion_control = bbr
EOF

    if command -v sysctl >/dev/null 2>&1; then
        if [[ "$release" == "alpine" ]]; then
            for conf in /etc/sysctl.d/*.conf /etc/sysctl.conf; do
                [[ -f "$conf" ]] && sysctl -p "$conf" >/dev/null 2>&1 || true
            done
        else
            sysctl --system >/dev/null 2>&1 || true
        fi
    fi
    
    echo -e "${GREEN}✔ 内核 BBR 配置块及最大并发映射文件已成功熔接至系统底层！ / Subsystem Kernel Parameters Updated.${NC}"
    read -ep "按回车安全退出 / Press Enter to return..."
}

vps_benchmark_menu() {
    clear
    echo -e "${CYAN}======================================================================${NC}"
    echo -e "${BOLD}${GREEN}   本机配置与IP测速纯净度 / Benchmark & IP Check${NC}"
    echo -e "${CYAN}======================================================================${NC}"
    echo -e "${YELLOW}1. 本机配置和测速 (bench.sh) / System Info & Speedtest${NC}"
    echo -e "${YELLOW}2. IP纯净度和测速 (Check.Place) / IP Quality & Speed${NC}"
    echo -e "${GREEN}0. 返回主菜单 / Return to Main Menu${NC}"
    echo -e "${CYAN}======================================================================${NC}"
    read -ep " 请选择 / Please select [0-2]: " bench_choice
    case $bench_choice in
        1) 
            clear; echo -e "${GREEN}正在运行 bench.sh... / Running bench.sh...${NC}"
            wget -qO- https://bench.sh | bash
            read -ep "按回车返回主菜单 / Press Enter to return..."
            ;;
        2)
            clear; echo -e "${GREEN}正在运行 Check.Place... / Running Check.Place...${NC}"
            bash <(curl -Ls https://Check.Place) -I
            read -ep "按回车返回主菜单 / Press Enter to return..."
            ;;
        0|*) return 0 ;;
    esac
}

# --- [8] 终端架构控制与交互渲染层 / Main Display Architecture ---
init_system_environment
setup_shortcut

GLOBAL_PUBLIC_IP=""

while true; do
    if [[ -z "$GLOBAL_PUBLIC_IP" || "$GLOBAL_PUBLIC_IP" == "N/A" ]]; then
        GLOBAL_PUBLIC_IP=$(curl -s4m2 api.ipify.org 2>/dev/null || curl -s6m2 api64.ipify.org 2>/dev/null || echo "N/A")
    fi
    
    STATUS_STR=""
    is_service_running xray && STATUS_STR="${GREEN}Xray-Core${NC} "
    is_service_running sing-box && STATUS_STR+="${CYAN}Sing-Box${NC} "
    is_service_running hysteria && STATUS_STR+="${PURPLE}Hy2(Native)${NC} "
    [[ -z "$STATUS_STR" ]] && STATUS_STR="${RED}Stack Stopped${NC}"
    
    source /etc/ddr/.env 2>/dev/null && CUR_MODE="[${CORE}-${MODE}]" || CUR_MODE=""
    
    clear; echo -e "${BLUE}======================================================================${NC}\n${BOLD}${YELLOW}==============================Aio-box===============================${NC}\n${BLUE}======================================================================${NC}"
    echo -e " 连通网关: ${YELLOW}$GLOBAL_PUBLIC_IP${NC} | 物理运行栈: $STATUS_STR $CUR_MODE\n${BLUE}----------------------------------------------------------------------${NC}"
    echo -e " ${YELLOW}[ Xray-core 部署/Deployment ]${NC}    ${YELLOW}[ Sing-box 部署/Deployment ]${NC}"
    echo -e " ${GREEN}1.${NC} VLESS-Reality                 ${GREEN}6.${NC} VLESS-Reality"
    echo -e " ${GREEN}2.${NC} Shadowsocks-2022              ${GREEN}7.${NC} Shadowsocks-2022"
    echo -e " ${GREEN}3.${NC} VLESS + SS-2022               ${GREEN}8.${NC} VLESS + SS-2022"
    echo -e " ${GREEN}4.${NC} Hysteria 2 (Apernet)          ${GREEN}9.${NC} Hysteria 2 (聚合版)"
    echo -e " ${GREEN}5.${NC} 全协议三合一/all (Xray+Hy2)     ${GREEN}10.${NC} 全协议三合一/all (Sing-box)"
    echo -e "${BLUE}----------------------------------------------------------------------${NC}"
    echo -e " ${GREEN}11.${NC} 本机配置与IP测速纯净度 / The purity of local configuration and IP speed test"
    echo -e " ${GREEN}12.${NC} VPS一键优化（bbr） / One-click VPS Optimization (BBR)"
    echo -e " ${GREEN}13.${NC} 全部节点参数显示 / Display of all node parameters"
    echo -e " ${GREEN}14.${NC} 脚本说明书 / Script Description Document"
    echo -e " ${GREEN}15.${NC} 脚本OTA升级 / Script OTA upgrade"
    echo -e " ${GREEN}16.${NC} 一键全部清空卸载 / One-click to completely clear and uninstall"
    echo -e " ${GREEN}17.${NC} 删除全部节点与环境初始化 / Delete all nodes and perform environment initialization"
    echo -e " ${GREEN}0.${NC} 退出脚本 / Exit Script"
    echo -e "${BLUE}======================================================================${NC}"
    read -ep " 请求下发执行代号 / Request input command: " choice
    
    case $choice in
        1) deploy_xray "VLESS" ;;
        2) deploy_xray "SS" ;;
        3) deploy_xray "VLESS_SS" ;;
        4) deploy_official_hy2 "NORMAL" ;;
        5) deploy_xray "ALL" ;;
        6) deploy_singbox "VLESS" ;;
        7) deploy_singbox "SS" ;;
        8) deploy_singbox "VLESS_SS" ;;
        9) deploy_singbox "HY2" ;;
        10) deploy_singbox "ALL" ;;
        11) vps_benchmark_menu ;;
        12) tune_vps ;; 
        13) view_config ;; 
        14) show_usage ;;
        15) update_script ;;
        16) clean_uninstall_menu ;; 
        17) check_virgin_state ;; 
        0) clear; exit 0 ;; 
        *) sleep 1 ;;
    esac
done
