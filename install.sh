#!/usr/bin/env bash
# ====================================================================
# Aio-box Ultimate Console [Triple-Source Gear | Shortcut 'sb']
# Features: Anti-Apple-SNI, Xray-v26-Native, Sing-box-Testing, Mirror-Fix
# Author: Nobody | Version: 2026.04
# Repo: https://github.com/alariclin/aio-box
# ====================================================================

set -e
export DEBIAN_FRONTEND=noninteractive
export LC_ALL=C

RED='\033[0;31m' GREEN='\033[0;32m' YELLOW='\033[0;33m' BLUE='\033[0;36m' PURPLE='\033[0;35m' CYAN='\033[0;36m' NC='\033[0m' BOLD='\033[1m'
trap 'echo -e "\n${RED}[!] 触发安全自愈，系统中断并回滚。${NC}"; exit 1' ERR

# --- [1] Root 权限强阻断 ---
[[ $EUID -ne 0 ]] && { echo -e "${RED}[!] 必须使用 Root 权限运行此控制台！请执行 'sudo su -'${NC}"; exit 1; }

# 用户备份镜像源地址
USER_MIRROR_BASE="https://raw.githubusercontent.com/alariclin/aio-box/main/core"

# --- [2] 本地化快捷指令与 OTA 引擎 ---
setup_shortcut() {
    mkdir -p /etc/ddr
    if [[ ! -f /etc/ddr/aio.sh || "$1" == "update" ]]; then
        curl -Ls https://raw.githubusercontent.com/alariclin/aio-box/main/install.sh > /etc/ddr/aio.sh
        chmod +x /etc/ddr/aio.sh
    fi
    [[ ! -f /usr/local/bin/sb ]] && { echo 'bash /etc/ddr/aio.sh' > /usr/local/bin/sb; chmod +x /usr/local/bin/sb; }
}

check_env() {
    if ! command -v jq >/dev/null || ! command -v unzip >/dev/null || ! command -v bc >/dev/null; then
        echo -e "${YELLOW}[*] 正在同步系统依赖环境...${NC}"
        apt-get update -y -q || yum makecache -y -q
        apt-get install -y -q wget curl jq openssl uuid-runtime cron fail2ban python3 bc unzip || \
        yum install -y -q wget curl jq openssl uuid-runtime cronie fail2ban python3 bc unzip
        systemctl enable cron 2>/dev/null || systemctl enable cronie 2>/dev/null
        systemctl start cron 2>/dev/null || systemctl start cronie 2>/dev/null
    fi
}

# --- [3] 本地缓存防失联与多源下载 ---
fetch_core() {
    local file_name=$1; local official_url=$2; local cache_dir="/etc/ddr/.core_cache"
    mkdir -p "$cache_dir"

    if [[ -f "${cache_dir}/${file_name}" ]]; then
        echo -e "${GREEN} -> 检测到本地物理缓存 [${file_name}]，离线提取中...${NC}"; cp "${cache_dir}/${file_name}" "/tmp/${file_name}"; return 0
    fi

    echo -e "${YELLOW} -> 正在拉取云端核心资源 [${file_name}]...${NC}"
    local mirrors=("" "https://ghp.ci/" "https://ghproxy.net/" "https://mirror.ghproxy.com/")
    for mirror in "${mirrors[@]}"; do
        if curl -fL --connect-timeout 10 "${mirror}${official_url}" -o "/tmp/${file_name}" 2>/dev/null; then
            if [[ -s "/tmp/${file_name}" ]]; then
                cp "/tmp/${file_name}" "${cache_dir}/${file_name}"
                echo -e "${GREEN}   ✔ 获取成功！核心已持久化至本地缓存。${NC}"; return 0
            fi
        fi
    done

    echo -e "${PURPLE} -> 官方源受阻，尝试个人备份仓库提取...${NC}"
    if curl -fL --connect-timeout 10 "${USER_MIRROR_BASE}/${file_name}" -o "/tmp/${file_name}" 2>/dev/null; then
        if [[ -s "/tmp/${file_name}" ]]; then
            cp "/tmp/${file_name}" "${cache_dir}/${file_name}"
            echo -e "${GREEN}   ✔ 备份源提取成功！${NC}"; return 0
        fi
    fi
    echo -e "${RED}[!] 致命错误：核心源均不可访问。${NC}"; exit 1
}

# --- [4] 防封 SNI 计算 (剔除 Apple) ---
calculate_sni() {
    ASN_ORG=$(curl -sm3 "ipinfo.io/org" || echo "GENERIC")
    ASN_UPPER=$(echo "$ASN_ORG" | tr '[:lower:]' '[:upper:]')
    if [[ "$ASN_UPPER" == *"GOOGLE"* ]]; then AUTO_REALITY="storage.googleapis.com"
    elif [[ "$ASN_UPPER" == *"AMAZON"* || "$ASN_UPPER" == *"AWS"* ]]; then AUTO_REALITY="s3.amazonaws.com"
    elif [[ "$ASN_UPPER" == *"MICROSOFT"* || "$ASN_UPPER" == *"AZURE"* ]]; then AUTO_REALITY="dl.delivery.mp.microsoft.com"
    else AUTO_REALITY="www.microsoft.com"; fi
}

# --- [5] Xray-core 部署 (v26.3.27 原生 Hy2) ---
install_xray() {
    clear; echo -e "${BOLD}${GREEN} 部署 Xray-core [v26.3.27 原生协议架构] ${NC}"; check_env
    XRAY_VER="v26.3.27"; ARCH=$(uname -m | sed 's/x86_64/64/;s/aarch64/arm64-v8a/')
    fetch_core "Xray-linux-${ARCH}.zip" "https://github.com/XTLS/Xray-core/releases/download/${XRAY_VER}/Xray-linux-${ARCH}.zip"
    fetch_core "geoip.dat" "https://github.com/v2fly/geoip/releases/latest/download/geoip.dat"
    fetch_core "geosite.dat" "https://github.com/v2fly/domain-list-community/releases/latest/download/dlc.dat"
    
    rm -rf /tmp/xray_ext; unzip -qo "/tmp/Xray-linux-${ARCH}.zip" -d /tmp/xray_ext
    mv /tmp/xray_ext/xray /usr/local/bin/xray; chmod +x /usr/local/bin/xray
    mkdir -p /usr/local/share/xray; mv /tmp/geoip.dat /usr/local/share/xray/; mv /tmp/geosite.dat /usr/local/share/xray/

    # 🚨 Key-Guard 安全阻断
    KEYS=$(/usr/local/bin/xray x25519 2>&1 || true)
    PK=$(echo "$KEYS" | grep -i "Private" | awk '{print $NF}'); PBK=$(echo "$KEYS" | grep -i "Public" | awk '{print $NF}')
    [[ -z "$PK" ]] && { echo -e "${RED}[!] 密钥生成失败！VPS 架构可能不兼容，已物理阻断安装。${NC}"; exit 1; }

    calculate_sni; UUID=$(uuidgen); SHORT_ID=$(openssl rand -hex 4); REALITY_SNI=$AUTO_REALITY
    SS_PASS=$(openssl rand -base64 16 | tr -d '\n\r'); HY2_PASS=$(openssl rand -base64 12 | tr -dc 'a-zA-Z0-9'); HY2_OBFS=$(openssl rand -base64 8 | tr -dc 'a-zA-Z0-9')
    mkdir -p /usr/local/etc/xray; openssl ecparam -genkey -name prime256v1 -out /usr/local/etc/xray/hy2.key 2>/dev/null
    openssl req -new -x509 -days 36500 -key /usr/local/etc/xray/hy2.key -out /usr/local/etc/xray/hy2.crt -subj "/CN=www.microsoft.com" 2>/dev/null

    INBOUNDS='[
      { "port": 443, "protocol": "vless", "settings": { "clients": [{"id": "'$UUID'", "flow": "xtls-rprx-vision"}], "decryption": "none" }, "streamSettings": { "network": "tcp", "security": "reality", "realitySettings": { "dest": "'$REALITY_SNI':443", "serverNames": ["'$REALITY_SNI'"], "privateKey": "'$PK'", "shortIds": ["'$SHORT_ID'"] } } },
      { "port": 8443, "protocol": "hysteria", "tag": "hy2-in", "settings": { "clients": [{"password": "'$HY2_PASS'"}] }, "streamSettings": { "network": "hysteria", "security": "tls", "tlsSettings": { "alpn": ["h3"], "certificates": [{ "certificateFile": "/usr/local/etc/xray/hy2.crt", "keyFile": "/usr/local/etc/xray/hy2.key" }] }, "hysteriaSettings": { "version": 2, "obfs": "salamander", "obfsPassword": "'$HY2_OBFS'" } } },
      { "port": 2053, "protocol": "shadowsocks", "settings": { "method": "2022-blake3-aes-128-gcm", "password": "'$SS_PASS'", "network": "tcp,udp" } },
      { "listen": "127.0.0.1", "port": 10085, "protocol": "dokodemo-door", "settings": { "address": "127.0.0.1" }, "tag": "api-in" }
    ]'

    cat > /usr/local/etc/xray/config.json << EOF
{ "log": { "loglevel": "warning" }, "inbounds": $INBOUNDS, "outbounds": [{ "protocol": "freedom" }], "routing": { "rules": [{"inboundTag":["api-in"],"outboundTag":"api","type":"field"}] } }
EOF
    cat > /etc/systemd/system/xray.service << SVC_EOF
[Unit]
After=network.target
[Service]
ExecStart=/usr/local/bin/xray run -config /usr/local/etc/xray/config.json
Restart=always
LimitNOFILE=1048576
LimitNPROC=infinity
[Install]
WantedBy=multi-user.target
SVC_EOF
    systemctl daemon-reload && systemctl enable --now xray; systemctl restart xray
    cat > /etc/ddr/.env << ENV_EOF
CORE="xray"
UUID="$UUID"
REALITY_SNI="$REALITY_SNI"
PUBLIC_KEY="$PBK"
SHORT_ID="$SHORT_ID"
HY2_PASS="$HY2_PASS"
SS_PASS="$SS_PASS"
LINK_IP="$PUBLIC_IP"
ENV_EOF
    echo -e "${GREEN}✔ Xray-core 部署成功！${NC}"; read -p "按回车返回..."
}

# --- [6] Sing-box 部署 (Testing 原生高并发特性) ---
install_singbox() {
    clear; echo -e "${BOLD}${GREEN} 部署 Sing-box [Testing 原生高并发架构] ${NC}"; check_env
    SB_VER="1.13.6"; ARCH=$(uname -m | sed 's/x86_64/amd64/;s/aarch64/arm64/')
    fetch_core "sing-box-${SB_VER}-linux-${ARCH}.tar.gz" "https://github.com/SagerNet/sing-box/releases/download/v${SB_VER}/sing-box-${SB_VER}-linux-${ARCH}.tar.gz"
    tar -xzf "/tmp/sing-box-${SB_VER}-linux-${ARCH}.tar.gz" -C /tmp; mv /tmp/sing-box-*/sing-box /usr/local/bin/; chmod +x /usr/local/bin/sing-box

    # 🚨 Key-Guard 安全阻断
    KEYS=$(/usr/local/bin/sing-box generate reality-keypair 2>&1 || true)
    PK=$(echo "$KEYS" | grep -i "Private" | awk '{print $NF}'); PBK=$(echo "$KEYS" | grep -i "Public" | awk '{print $NF}')
    [[ -z "$PK" ]] && { echo -e "${RED}[!] 密钥生成失败！VPS 架构可能不兼容，已物理阻断安装。${NC}"; exit 1; }

    calculate_sni; UUID=$(uuidgen); SHORT_ID=$(openssl rand -hex 4); SS_PASS=$(openssl rand -base64 16 | tr -d '\n\r')
    HY2_PASS=$(openssl rand -base64 12 | tr -dc 'a-zA-Z0-9'); HY2_OBFS=$(openssl rand -base64 8 | tr -dc 'a-zA-Z0-9')
    mkdir -p /etc/sing-box; openssl ecparam -genkey -name prime256v1 -out /etc/sing-box/hy2.key 2>/dev/null
    openssl req -new -x509 -days 36500 -key /etc/sing-box/hy2.key -out /etc/sing-box/hy2.crt -subj "/CN=www.microsoft.com" 2>/dev/null

    INBOUNDS='[
      { "type": "vless", "listen": "::", "listen_port": 443, "tcp_fast_open": true, "users": [{"uuid": "'$UUID'", "flow": "xtls-rprx-vision"}], "tls": { "enabled": true, "server_name": "'$REALITY_SNI'", "reality": { "enabled": true, "handshake": { "server": "'$REALITY_SNI'", "server_port": 443 }, "private_key": "'$PK'", "short_id": ["'$SHORT_ID'"] }, "utls": { "enabled": true, "fingerprint": "chrome" } } },
      { "type": "hysteria2", "listen": "::", "listen_port": 443, "up_mbps": 3000, "down_mbps": 3000, "port_hopping": "20000-50000", "port_hopping_interval": "30s", "obfs": { "type": "salamander", "password": "'$HY2_OBFS'" }, "users": [{"password": "'$HY2_PASS'"}], "tls": { "enabled": true, "certificate_path": "/etc/sing-box/hy2.crt", "key_path": "/etc/sing-box/hy2.key" } },
      { "type": "shadowsocks", "listen": "::", "listen_port": 2053, "tcp_fast_open": true, "method": "2022-blake3-aes-128-gcm", "password": "'$SS_PASS'" }
    ]'

    cat > /etc/sing-box/config.json << EOF
{ "log": { "level": "warn" }, "inbounds": $INBOUNDS, "outbounds": [{ "type": "direct" }] }
EOF
    cat > /etc/systemd/system/sing-box.service << SVC_EOF
[Unit]
After=network.target
[Service]
ExecStart=/usr/local/bin/sing-box run -c /etc/sing-box/config.json
Restart=always
LimitNOFILE=1048576
LimitNPROC=infinity
[Install]
WantedBy=multi-user.target
SVC_EOF
    systemctl daemon-reload && systemctl enable --now sing-box; systemctl restart sing-box
    cat > /etc/ddr/.env << ENV_EOF
CORE="singbox"
UUID="$UUID"
REALITY_SNI="$REALITY_SNI"
PUBLIC_KEY="$PBK"
SHORT_ID="$SHORT_ID"
HY2_PASS="$HY2_PASS"
HY2_OBFS="$HY2_OBFS"
SS_PASS="$SS_PASS"
LINK_IP="$PUBLIC_IP"
ENV_EOF
    echo -e "${GREEN}✔ Sing-box 部署成功！${NC}"; read -p "按回车返回..."
}

# --- [7] 运维辅助功能 ---
view_config() {
    clear; source /etc/ddr/.env 2>/dev/null || { echo "未检测到配置！"; sleep 2; return; }
    echo -e "${BLUE}======================================================${NC}\n${BOLD}${CYAN}   节点参数明细与配置提取 (uTLS Chrome) ${NC}\n${BLUE}======================================================${NC}"
    echo -e "${BOLD}1. 引擎:${NC} $CORE | ${BOLD}UUID:${NC} $UUID\n${BOLD}2. REALITY SNI:${NC} $REALITY_SNI\n${BOLD}3. PBK:${NC} $PUBLIC_KEY | ${BOLD}SID:${NC} $SHORT_ID\n${BLUE}------------------------------------------------------${NC}"
    echo -e "${YELLOW}[ 通用 URI 链接 ]${NC}\nvless://$UUID@$LINK_IP:443?encryption=none&flow=xtls-rprx-vision&security=reality&sni=$REALITY_SNI&fp=chrome&pbk=$PUBLIC_KEY&sid=$SHORT_ID&type=tcp#Aio-box\n"
    echo -e "${PURPLE}[ Clash Meta (Mihomo) YAML ]${NC}\nproxies:\n  - name: Aio-box-Vision\n    type: vless\n    server: $LINK_IP\n    port: 443\n    uuid: $UUID\n    network: tcp\n    tls: true\n    flow: xtls-rprx-vision\n    servername: $REALITY_SNI\n    client-fingerprint: chrome\n    reality-opts:\n      public-key: $PUBLIC_KEY\n      short-id: $SHORT_ID\n${BLUE}======================================================${NC}"
    read -p "按回车返回主菜单..."
}

clean_uninstall() {
    clear; echo -e "${RED}⚠️  卸载交互向导${NC}\n 1. 仅删除核心与配置 (保留本地缓存及 sb 指令)\n 2. 彻底抹除 (删除脚本本体、物理缓存及快捷键)"
    read -p " 请选择 [1-2]: " clean_choice
    systemctl stop xray sing-box 2>/dev/null || true
    rm -rf /usr/local/etc/xray /etc/sing-box /usr/local/bin/xray /usr/local/bin/sing-box
    if [[ "$clean_choice" == "2" ]]; then
        rm -rf /etc/ddr /usr/local/bin/sb; echo -e "${GREEN}✔ 系统环境已物理清空。${NC}"; exit 0
    else
        rm -f /etc/ddr/.env; echo -e "${GREEN}✔ 核心与配置已清理，火种已保留。${NC}"; sleep 2
    fi
}

tune_vps_and_bench() {
    clear; echo -e "${CYAN}正在优化并发栈并执行诊断...${NC}"
    grep -q '1048576' /etc/security/limits.conf || { echo "* soft nofile 1048576" >> /etc/security/limits.conf; echo "* hard nofile 1048576" >> /etc/security/limits.conf; }
    modprobe tcp_bbr 2>/dev/null || true
    cat > /etc/sysctl.d/99-ddr-tune.conf << 'EOF'
fs.file-max = 1048576
net.core.default_qdisc = fq
net.ipv4.tcp_congestion_control = bbr
net.ipv4.tcp_fastopen = 3
EOF
    sysctl -p /etc/sysctl.d/99-ddr-tune.conf >/dev/null 2>&1 || true
    bash <(curl -Ls https://Check.Place) -I || true
    wget -qO- bench.sh | bash || true
    read -p "按回车返回..."
}

# --- [8] 主控制台循环 ---
setup_shortcut
while true; do
    IPV4=$(curl -s4m3 api.ipify.org || echo "N/A"); PUBLIC_IP="$IPV4"
    systemctl is-active --quiet xray && STATUS="${GREEN}Running (Xray)${NC}" || { systemctl is-active --quiet sing-box && STATUS="${CYAN}Running (Sing-box)${NC}" || STATUS="${RED}Stopped${NC}"; }
    clear; echo -e "${BLUE}======================================================${NC}\n${BOLD}${PURPLE}  Aio-box Ultimate Console [Final V16] ${NC}\n${BLUE}======================================================${NC}"
    echo -e " IP: ${YELLOW}$IPV4${NC} | STATUS: $STATUS ${CYAN}(指令: sb)${NC}\n${BLUE}------------------------------------------------------${NC}"
    echo -e " ${GREEN}1.${NC} 部署 Xray-core 全家桶 (VLESS+Hy2+SS)\n ${GREEN}2.${NC} 部署 Sing-box  全家桶 (VLESS+Hy2+SS)\n ${BLUE}------------------------------------------------------${NC}\n ${GREEN}11.${NC} 本机参数与IP网络测速诊断\n ${GREEN}13.${NC} 参数明细与节点链接 (内置 uTLS 指纹)\n ${YELLOW}14.${NC} 脚本源码 OTA 热更新\n ${RED}15.${NC} 彻底清空卸载环境\n ${GREEN}0.${NC}  退出面板\n${BLUE}======================================================${NC}"
    read -p " 请选择: " choice
    case $choice in
        1) install_xray ;; 
        2) install_singbox ;;
        11) tune_vps_and_bench ;;
        13) view_config ;; 
        14) setup_shortcut "update"; echo -e "OTA 成功。"; exit 0 ;;
        15) clean_uninstall ;; 
        0) exit 0 ;; 
        *) sleep 1 ;;
    esac
done
