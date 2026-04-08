#!/usr/bin/env bash
# ====================================================================
# Aio-box Ultimate Console [True 443 Coexistence & JSON Bug Fixed]
# Version: 2026.04.Apex-Stable-V45-Perfect
# ====================================================================

export DEBIAN_FRONTEND=noninteractive
RED='\033[0;31m' GREEN='\033[0;32m' YELLOW='\033[0;33m' BLUE='\033[0;36m' PURPLE='\033[0;35m' CYAN='\033[0;36m' NC='\033[0m' BOLD='\033[1m'

if [[ $EUID -ne 0 ]]; then
    if command -v sudo >/dev/null 2>&1; then
        exec sudo bash "$0" "$@"
    else
        echo -e "${RED}[!] 必须使用 Root 权限运行！请执行 'sudo su -'${NC}"; exit 1
    fi
fi
sed -i '/acme.sh.env/d' ~/.bashrc >/dev/null 2>&1 || true

setup_shortcut() {
    mkdir -p /etc/ddr
    if [[ ! -f /etc/ddr/aio.sh || "$1" == "update" ]]; then
        curl -Ls https://raw.githubusercontent.com/alariclin/aio-box/main/install.sh > /etc/ddr/aio.sh
        chmod +x /etc/ddr/aio.sh
    fi
    if [[ ! -f /usr/local/bin/sb ]]; then
        printf '#!/bin/bash\nsudo bash /etc/ddr/aio.sh "$@"\n' > /usr/local/bin/sb
        chmod +x /usr/local/bin/sb
    fi
}

check_env() {
    if ! command -v jq >/dev/null || ! command -v fuser >/dev/null || ! command -v unzip >/dev/null || ! command -v lsof >/dev/null; then
        echo -e "${YELLOW}[*] 正在同步系统依赖环境...${NC}"
        apt-get update -y -q || yum makecache -y -q
        local deps=(wget curl jq openssl uuid-runtime cron fail2ban python3 bc unzip vnstat iptables tar psmisc lsof)
        if command -v apt-get >/dev/null; then apt-get install -y -q "${deps[@]}"; else yum install -y -q "${deps[@]}"; fi
        systemctl enable cron vnstat 2>/dev/null || true
        systemctl start cron vnstat 2>/dev/null || true
    fi
}

get_architecture() {
    local ARCH=$(uname -m)
    case "$ARCH" in
        x86_64) XRAY_ARCH="64"; SB_ARCH="amd64" ;;
        aarch64) XRAY_ARCH="arm64-v8a"; SB_ARCH="arm64" ;;
        *) echo -e "${RED}[!] 不支持的架构: $ARCH${NC}"; exit 1 ;;
    esac
}

fetch_github_release() {
    local repo=$1; local keyword=$2; local output_file=$3
    echo -e "${YELLOW} -> 正在从 GitHub 获取最新版本 [${repo}]...${NC}"
    local api_url="https://api.github.com/repos/${repo}/releases/latest"
    local download_url=$(curl -sL "$api_url" | jq -r ".assets[] | select(.name | contains(\"$keyword\")) | .browser_download_url" | head -n 1)
    
    if [[ -z "$download_url" || "$download_url" == "null" ]]; then
        download_url=$(curl -sL "https://ghp.ci/$api_url" | jq -r ".assets[] | select(.name | contains(\"$keyword\")) | .browser_download_url" | head -n 1)
    fi

    if [[ -z "$download_url" || "$download_url" == "null" ]]; then
        echo -e "${RED}[!] 无法获取 $repo 下载链接。${NC}"; exit 1
    fi

    local mirrors=("" "https://ghp.ci/" "https://ghproxy.net/")
    for mirror in "${mirrors[@]}"; do
        if curl -fLs --connect-timeout 10 "${mirror}${download_url}" -o "/tmp/${output_file}" && [[ -s "/tmp/${output_file}" ]]; then
            echo -e "${GREEN}   ✔ 核心获取成功！${NC}"; return 0
        fi
    done
    echo -e "${RED}[!] 下载失败。${NC}"; exit 1
}

fetch_geo_data() {
    local file_name=$1; local official_url=$2
    local mirrors=("" "https://ghp.ci/" "https://ghproxy.net/")
    for mirror in "${mirrors[@]}"; do
        if curl -fLs --connect-timeout 10 "${mirror}${official_url}" -o "/tmp/${file_name}" && [[ -s "/tmp/${file_name}" ]]; then return 0; fi
    done
    exit 1
}

pre_install_setup() {
    local MODE=$1
    AUTO_REALITY="www.microsoft.com"

    echo -e "\n${CYAN}======================================================================${NC}"
    echo -e "${BOLD}🚀 部署前向导：正统 443 端口部署方案${NC}"
    echo -e "   强制使用防封 SNI: ${GREEN}$AUTO_REALITY${NC}"
    echo -e "${BLUE}----------------------------------------------------------------------${NC}"

    if [[ "$MODE" == *"VLESS"* ]] || [[ "$MODE" == *"ALL"* ]]; then
        read -ep "   [VLESS] 请输入伪装 SNI (回车默认使用微软): " INPUT_V_SNI
        VLESS_SNI=${INPUT_V_SNI:-$AUTO_REALITY}
        read -ep "   [VLESS] 请输入监听端口 (回车默认使用 443): " INPUT_V_PORT
        VLESS_PORT=${INPUT_V_PORT:-443}
    fi

    if [[ "$MODE" == *"HY2"* ]] || [[ "$MODE" == *"ALL"* ]]; then
        read -ep "   [HY2] 请输入伪装 SNI (回车默认使用微软): " INPUT_H_SNI
        HY2_SNI=${INPUT_H_SNI:-$AUTO_REALITY}
        read -ep "   [HY2] 请输入监听端口 (回车默认使用 443): " INPUT_H_PORT
        HY2_PORT=${INPUT_H_PORT:-443}
    fi

    if [[ "$MODE" == *"SS"* ]] || [[ "$MODE" == *"ALL"* ]]; then
        read -ep "   [SS] 请输入备用监听端口 (回车默认 2053): " INPUT_S_PORT
        SS_PORT=${INPUT_S_PORT:-2053}
    fi
    echo -e "${CYAN}======================================================================${NC}\n"

    VLESS_SNI=${VLESS_SNI:-$AUTO_REALITY}; HY2_SNI=${HY2_SNI:-$AUTO_REALITY}
    VLESS_PORT=${VLESS_PORT:-443}; HY2_PORT=${HY2_PORT:-443}; SS_PORT=${SS_PORT:-2053}
}

release_ports() {
    echo -e "${YELLOW}[*] 正在执行内核级端口强制释放清理...${NC}"
    systemctl stop xray sing-box hysteria 2>/dev/null || true
    killall -9 xray sing-box hysteria 2>/dev/null || true
    
    local ports_to_clean=($VLESS_PORT $HY2_PORT $SS_PORT 443 2053)
    for p in $(echo "${ports_to_clean[@]}" | tr ' ' '\n' | sort -u); do
        fuser -k -9 ${p}/tcp 2>/dev/null || true
        fuser -k -9 ${p}/udp 2>/dev/null || true
        lsof -ti:${p} | xargs kill -9 2>/dev/null || true
    done
    sleep 2
}

deploy_xray() {
    local MODE=$1; clear; echo -e "${BOLD}${GREEN} 部署 Xray-core [$MODE] ${NC}"; check_env; pre_install_setup "$MODE"
    release_ports
    
    get_architecture
    fetch_github_release "XTLS/Xray-core" "Xray-linux-${XRAY_ARCH}.zip" "xray_core.zip"
    fetch_geo_data "geoip.dat" "https://github.com/v2fly/geoip/releases/latest/download/geoip.dat"
    fetch_geo_data "geosite.dat" "https://github.com/v2fly/domain-list-community/releases/latest/download/dlc.dat"
    
    rm -rf /tmp/xray_ext; unzip -qo "/tmp/xray_core.zip" -d /tmp/xray_ext
    mv /tmp/xray_ext/xray /usr/local/bin/xray; chmod +x /usr/local/bin/xray
    mkdir -p /usr/local/share/xray /usr/local/etc/xray; mv /tmp/geoip.dat /usr/local/share/xray/; mv /tmp/geosite.dat /usr/local/share/xray/
    
    PK=$(/usr/local/bin/xray x25519 | grep -i "Private" | awk '{print $NF}'); PBK=$(/usr/local/bin/xray x25519 | grep -i "Public" | awk '{print $NF}')
    UUID=$(uuidgen); SHORT_ID=$(openssl rand -hex 4 | tr -d '\n\r'); SS_PASS=$(openssl rand -base64 16 | tr -d '\n\r')
    HY2_PASS=$(openssl rand -base64 12 | tr -dc 'a-zA-Z0-9'); HY2_OBFS=$(openssl rand -base64 8 | tr -dc 'a-zA-Z0-9')
    
    mkdir -p /usr/local/etc/xray; openssl ecparam -genkey -name prime256v1 -out /usr/local/etc/xray/hy2.key 2>/dev/null
    openssl req -new -x509 -days 36500 -key /usr/local/etc/xray/hy2.key -out /usr/local/etc/xray/hy2.crt -subj "/CN=${HY2_SNI}" 2>/dev/null

    JSON_VLESS=$(cat << EOF
    {
      "listen": "0.0.0.0", "port": ${VLESS_PORT}, "protocol": "vless",
      "settings": { "clients": [{"id": "${UUID}", "flow": "xtls-rprx-vision"}], "decryption": "none" },
      "streamSettings": {
        "network": "tcp", "security": "reality",
        "realitySettings": { "dest": "${VLESS_SNI}:443", "serverNames": ["${VLESS_SNI}"], "privateKey": "${PK}", "shortIds": ["${SHORT_ID}"] }
      }
    }
EOF
)
    JSON_HY2=$(cat << EOF
    {
      "listen": "0.0.0.0", "port": ${HY2_PORT}, "protocol": "hysteria", "tag": "hy2-in",
      "settings": {
        "auth": "pass", "auth_str": "${HY2_PASS}", "certificates": [{ "certificateFile": "/usr/local/etc/xray/hy2.crt", "keyFile": "/usr/local/etc/xray/hy2.key" }]
      }
    }
EOF
)
    JSON_SS=$(cat << EOF
    {
      "listen": "0.0.0.0", "port": ${SS_PORT}, "protocol": "shadowsocks",
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
{ "log": { "loglevel": "warning" }, "inbounds": ${INBOUNDS}, "outbounds": [{ "protocol": "freedom" }] }
EOF

    cat > /etc/systemd/system/xray.service << SVC_EOF
[Unit]
After=network.target
[Service]
$(if [[ "$MODE" == *"HY2"* ]] || [[ "$MODE" == *"ALL"* ]]; then echo -e "ExecStartPre=-/bin/sh -c '/sbin/iptables -t nat -D PREROUTING -p udp --dport 20000:50000 -j REDIRECT --to-ports $HY2_PORT 2>/dev/null || true'\nExecStartPre=-/bin/sh -c '/sbin/ip6tables -t nat -D PREROUTING -p udp --dport 20000:50000 -j REDIRECT --to-ports $HY2_PORT 2>/dev/null || true'\nExecStartPre=-/bin/sh -c '/sbin/iptables -t nat -A PREROUTING -p udp --dport 20000:50000 -j REDIRECT --to-ports $HY2_PORT 2>/dev/null || true'\nExecStartPre=-/bin/sh -c '/sbin/ip6tables -t nat -A PREROUTING -p udp --dport 20000:50000 -j REDIRECT --to-ports $HY2_PORT 2>/dev/null || true'"; fi)
ExecStart=/usr/local/bin/xray run -config /usr/local/etc/xray/config.json
$(if [[ "$MODE" == *"HY2"* ]] || [[ "$MODE" == *"ALL"* ]]; then echo -e "ExecStopPost=-/bin/sh -c '/sbin/iptables -t nat -D PREROUTING -p udp --dport 20000:50000 -j REDIRECT --to-ports $HY2_PORT 2>/dev/null || true'\nExecStopPost=-/bin/sh -c '/sbin/ip6tables -t nat -D PREROUTING -p udp --dport 20000:50000 -j REDIRECT --to-ports $HY2_PORT 2>/dev/null || true'"; fi)
Restart=always
LimitNOFILE=1048576
LimitNPROC=infinity
[Install]
WantedBy=multi-user.target
SVC_EOF

    systemctl daemon-reload && systemctl enable --now xray; systemctl restart xray
    sleep 2; systemctl is-active --quiet xray || { echo -e "${RED}[!] 致命错误：Xray 核心启动失败！${NC}"; journalctl -u xray --no-pager -n 20; exit 1; }

    cat > /etc/ddr/.env << ENV_EOF
CORE="xray"; MODE="$MODE"; UUID="$UUID"; VLESS_SNI="$VLESS_SNI"; VLESS_PORT="$VLESS_PORT"; HY2_SNI="$HY2_SNI"; HY2_PORT="$HY2_PORT"; SS_PORT="$SS_PORT"; PUBLIC_KEY="$PBK"; SHORT_ID="$SHORT_ID"; HY2_PASS="$HY2_PASS"; HY2_OBFS="$HY2_OBFS"; SS_PASS="$SS_PASS"; LINK_IP="$(curl -s4 api.ipify.org)"
ENV_EOF
    view_config "deploy"
}

deploy_singbox() {
    local MODE=$1; clear; echo -e "${BOLD}${GREEN} 部署 Sing-box [$MODE] ${NC}"; check_env; pre_install_setup "$MODE"
    release_ports

    get_architecture
    fetch_github_release "SagerNet/sing-box" "linux-${SB_ARCH}.tar.gz" "singbox_core.tar.gz"
    tar -xzf "/tmp/singbox_core.tar.gz" -C /tmp; mv /tmp/sing-box-*/sing-box /usr/local/bin/; chmod +x /usr/local/bin/sing-box

    PK=$(/usr/local/bin/sing-box generate reality-keypair | grep -i "Private" | awk '{print $NF}'); PBK=$(/usr/local/bin/sing-box generate reality-keypair | grep -i "Public" | awk '{print $NF}')
    if [[ -z "$PK" ]]; then echo -e "${RED}[!] 核心不兼容 / Core incompatible.${NC}"; exit 1; fi

    UUID=$(uuidgen); SHORT_ID=$(openssl rand -hex 4 | tr -d '\n\r'); SS_PASS=$(openssl rand -base64 16 | tr -d '\n\r')
    HY2_PASS=$(openssl rand -base64 12 | tr -dc 'a-zA-Z0-9'); HY2_OBFS=$(openssl rand -base64 8 | tr -dc 'a-zA-Z0-9')
    
    mkdir -p /etc/sing-box; openssl ecparam -genkey -name prime256v1 -out /etc/sing-box/hy2.key 2>/dev/null
    openssl req -new -x509 -days 36500 -key /etc/sing-box/hy2.key -out /etc/sing-box/hy2.crt -subj "/CN=${HY2_SNI}" 2>/dev/null

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
{ "log": { "level": "warn" }, "inbounds": ${INBOUNDS}, "outbounds": [{ "type": "direct" }] }
EOF

    cat > /etc/systemd/system/sing-box.service << SVC_EOF
[Unit]
After=network.target
[Service]
$(if [[ "$MODE" == *"HY2"* ]] || [[ "$MODE" == *"ALL"* ]]; then echo -e "ExecStartPre=-/bin/sh -c '/sbin/iptables -t nat -D PREROUTING -p udp --dport 20000:50000 -j REDIRECT --to-ports $HY2_PORT 2>/dev/null || true'\nExecStartPre=-/bin/sh -c '/sbin/ip6tables -t nat -D PREROUTING -p udp --dport 20000:50000 -j REDIRECT --to-ports $HY2_PORT 2>/dev/null || true'\nExecStartPre=-/bin/sh -c '/sbin/iptables -t nat -A PREROUTING -p udp --dport 20000:50000 -j REDIRECT --to-ports $HY2_PORT 2>/dev/null || true'\nExecStartPre=-/bin/sh -c '/sbin/ip6tables -t nat -A PREROUTING -p udp --dport 20000:50000 -j REDIRECT --to-ports $HY2_PORT 2>/dev/null || true'"; fi)
ExecStart=/usr/local/bin/sing-box run -c /etc/sing-box/config.json
$(if [[ "$MODE" == *"HY2"* ]] || [[ "$MODE" == *"ALL"* ]]; then echo -e "ExecStopPost=-/bin/sh -c '/sbin/iptables -t nat -D PREROUTING -p udp --dport 20000:50000 -j REDIRECT --to-ports $HY2_PORT 2>/dev/null || true'\nExecStopPost=-/bin/sh -c '/sbin/ip6tables -t nat -D PREROUTING -p udp --dport 20000:50000 -j REDIRECT --to-ports $HY2_PORT 2>/dev/null || true'"; fi)
Restart=always
LimitNOFILE=1048576
LimitNPROC=infinity
[Install]
WantedBy=multi-user.target
SVC_EOF

    systemctl daemon-reload && systemctl enable --now sing-box; systemctl restart sing-box
    sleep 2; systemctl is-active --quiet sing-box || { echo -e "${RED}[!] 致命错误：Sing-box 无法启动。${NC}"; journalctl -u sing-box --no-pager -n 20; exit 1; }

    cat > /etc/ddr/.env << ENV_EOF
CORE="singbox"; MODE="$MODE"; UUID="$UUID"; VLESS_SNI="$VLESS_SNI"; VLESS_PORT="$VLESS_PORT"; HY2_SNI="$HY2_SNI"; HY2_PORT="$HY2_PORT"; SS_PORT="$SS_PORT"; PUBLIC_KEY="$PBK"; SHORT_ID="$SHORT_ID"; HY2_PASS="$HY2_PASS"; HY2_OBFS="$HY2_OBFS"; SS_PASS="$SS_PASS"; LINK_IP="$(curl -s4 api.ipify.org)"
ENV_EOF
    view_config "deploy"
}

show_usage() {
    clear; echo -e "${CYAN}======================================================================${NC}"
    echo -e "${BOLD}${GREEN}   Aio-box Ultimate 脚本详细功能与使用说明${NC}"
    echo -e "${CYAN}======================================================================${NC}"
    echo -e "1-8. 协议部署: 支持 Xray-core 与 Sing-box 核心。可单选或三合一安装。"
    echo -e "     - VLESS-Vision: 顶级 TCP 伪装，防主动探测与精确识别。"
    echo -e "     - Hysteria 2: 顶级 UDP 加速，内置 20000-50000 端口跳跃防封机制。"
    echo -e "     - SS-2022: 经典轻量级备用协议，兼顾全平台客户端兼容性。"
    echo -e "9.   流量监控: 设置每月流量上限(GB)，一旦超量将自动停止核心服务。"
    echo -e "10.  网络诊断: 包含本机 IP 欺诈度检测及全球基准测速。"
    echo -e "11.  VPS优化: 解除 Linux 最大连接数限制，开启 BBR-Brutal 加速。"
    echo -e "13.  节点参数: 随时查看当前已安装的配置信息及通用 URI 链接。"
    echo -e "14.  OTA更新: 一键同步 GitHub 最新版脚本代码并无损热更新。"
    echo -e "15.  彻底卸载: 核弹级物理清理，强制斩杀顽固进程并重置防火墙。"
    echo -e "16.  环境预检: 彻底检查死锁端口、幽灵进程等异常，确立安装纯净度。\n"
    read -ep "按回车返回主菜单 / Press Enter to return..."
}

setup_quota() {
    clear; echo -e "${CYAN}=== 流量监控与自动熔断设置 / Quota Guard ===${NC}"
    read -ep "请输入每月流量熔断上限 (GB，输入 0 取消限制): " QUOTA_GB
    if [[ "$QUOTA_GB" -gt 0 ]]; then
        cat > /etc/ddr/quota.sh << 'EOF'
#!/bin/bash
QUOTA_VAL=$(cat /etc/ddr/.quota_val 2>/dev/null || echo 0)
TOTAL_TX=$(vnstat --oneline 2>/dev/null | awk -F';' '{print $10}')
[[ -z "$TOTAL_TX" ]] && exit 0
VALUE=$(echo $TOTAL_TX | sed 's/[^0-9.]*//g')
[[ "$TOTAL_TX" == *"T"* ]] && VALUE=$(echo "$VALUE * 1024" | bc)
if (( $(echo "$VALUE >= $QUOTA_VAL" | bc -l) )); then
    systemctl stop xray sing-box 2>/dev/null
    killall -9 xray sing-box hysteria 2>/dev/null || true
fi
EOF
        echo "$QUOTA_GB" > /etc/ddr/.quota_val; chmod +x /etc/ddr/quota.sh
        (crontab -l 2>/dev/null | grep -v "quota.sh"; echo "*/10 * * * * /etc/ddr/quota.sh") | crontab -
        echo -e "${GREEN}✔ 流量熔断已启动，上限 ${QUOTA_GB}GB。${NC}"
    else
        crontab -l 2>/dev/null | grep -v "quota.sh" | crontab - || true; echo -e "${YELLOW}✔ 流量限制已解除。${NC}"
    fi
    read -ep "按回车返回..."
}

diagnostics() {
    clear; echo -e "${CYAN}=== 本机参数与网络诊断测速 / Diagnostics ===${NC}"
    echo -e " ${GREEN}1.${NC} IP 信誉与流媒体解锁检测 (IP纯净度与欺诈分析)\n ${GREEN}2.${NC} 全球节点基准测速 (硬件性能与网速测试)\n ${YELLOW}0.${NC} 返回主菜单"
    read -ep "请选择 [0-2]: " d_ch
    case $d_ch in 1) bash <(curl -Ls https://Check.Place) -I ;; 2) wget -qO- bench.sh | bash ;; esac
    read -ep "按回车返回..."
}

tune_vps() {
    clear; echo -e "${CYAN}正在执行 VPS 全面优化...${NC}"
    grep -q '1048576' /etc/security/limits.conf || { echo "* soft nofile 1048576" >> /etc/security/limits.conf; echo "* hard nofile 1048576" >> /etc/security/limits.conf; }
    modprobe tcp_bbr 2>/dev/null || true
    cat > /etc/sysctl.d/99-ddr-tune.conf << 'EOF'
fs.file-max=1048576
net.core.default_qdisc=fq
net.ipv4.tcp_congestion_control=bbr
net.ipv4.tcp_fastopen=3
EOF
    sysctl -p /etc/sysctl.d/99-ddr-tune.conf >/dev/null 2>&1 || true
    echo -e "${GREEN}✔ 优化完成。 / Tuning complete.${NC}"; read -ep "按回车返回..."
}

view_config() {
    local CALLER=$1; clear; [[ ! -f /etc/ddr/.env ]] && { echo -e "${RED}未检测到配置！${NC}"; sleep 2; return 0; }
    source /etc/ddr/.env
    echo -e "${BLUE}======================================================================${NC}\n${BOLD}${CYAN}   协议全部节点参数 (${MODE}) / All Protocol Parameters ${NC}\n${BLUE}======================================================================${NC}"
    echo -e "${BOLD}Engine:${NC} $CORE | ${BOLD}Mode:${NC} $MODE\n${BLUE}----------------------------------------------------------------------${NC}"
    
    if [[ "$MODE" == *"VLESS"* ]] || [[ "$MODE" == *"ALL"* ]]; then
        echo -e "${YELLOW}[ VLESS-Vision 通用链接 ]${NC}\n(注: 小火箭务必将 uTLS 设置为 chrome, 否则秒被服务端断开)\nvless://$UUID@$LINK_IP:$VLESS_PORT?encryption=none&flow=xtls-rprx-vision&security=reality&sni=$VLESS_SNI&fp=chrome&pbk=$PUBLIC_KEY&sid=$SHORT_ID&type=tcp#Aio-VLESS\n"
    fi
    if [[ "$MODE" == *"HY2"* ]] || [[ "$MODE" == *"ALL"* ]]; then
        if [[ "$CORE" == "xray" ]]; then
             echo -e "${YELLOW}[ Hysteria 2 通用链接 ]${NC}\n(注: 小火箭务必开启 \"允许不安全\" 或 \"跳过证书验证\")\nhysteria2://$HY2_PASS@$LINK_IP:$HY2_PORT/?insecure=1&sni=$HY2_SNI&alpn=h3&mport=20000-50000#Aio-Hy2\n"
        else
             echo -e "${YELLOW}[ Hysteria 2 通用链接 ]${NC}\n(注: 小火箭务必开启 \"允许不安全\" 或 \"跳过证书验证\")\nhysteria2://$HY2_PASS@$LINK_IP:$HY2_PORT/?insecure=1&sni=$HY2_SNI&alpn=h3&obfs=salamander&obfs-password=$HY2_OBFS&mport=20000-50000#Aio-Hy2\n"
        fi
    fi
    if [[ "$MODE" == *"SS"* ]] || [[ "$MODE" == *"ALL"* ]]; then
        SS_BASE64=$(echo -n "2022-blake3-aes-128-gcm:${SS_PASS}" | base64 -w 0 2>/dev/null || echo -n "2022-blake3-aes-128-gcm:${SS_PASS}" | base64 | tr -d '\n')
        echo -e "${YELLOW}[ Shadowsocks-2022 通用链接 ]${NC}\nss://${SS_BASE64}@${LINK_IP}:$SS_PORT#Aio-SS\n"
    fi
    
    if [[ "$CALLER" == "deploy" ]]; then
        echo -e "${GREEN}✔ 部署成功！如果要查询节点明细请随时进入菜单 13。${NC}"
    fi
    read -ep "按回车返回主菜单..."
}

clean_uninstall() {
    clear; echo -e "${RED}⚠️  核弹级卸载交互向导 / Nuclear Uninstall Wizard${NC}\n 1. 仅删除核心与配置 / Remove core & config\n 2. 彻底物理清场 (恢复处女态) / Complete Purge"
    read -ep " 请选择 [1-2]: " clean_choice
    
    echo -e "${YELLOW}[*] 正在执行暴力进程绞杀...${NC}"
    systemctl stop xray sing-box hysteria 2>/dev/null || true
    systemctl disable xray sing-box hysteria 2>/dev/null || true
    killall -9 xray sing-box hysteria 2>/dev/null || true
    
    local ipt_cmd=$(command -v iptables || echo "/sbin/iptables")
    local ip6t_cmd=$(command -v ip6tables || echo "/sbin/ip6tables")
    
    echo -e "${YELLOW}[*] 正在粉碎 iptables/NAT 残留链...${NC}"
    $ipt_cmd -t nat -F PREROUTING 2>/dev/null || true
    $ip6t_cmd -t nat -F PREROUTING 2>/dev/null || true
    $ipt_cmd -F INPUT 2>/dev/null || true
    
    echo -e "${YELLOW}[*] 正在销毁物理文件与系统服务...${NC}"
    rm -rf /usr/local/etc/xray /etc/sing-box /usr/local/bin/xray /usr/local/bin/sing-box /etc/systemd/system/xray.service /etc/systemd/system/sing-box.service /etc/systemd/system/hysteria.service /usr/local/bin/hysteria /etc/hysteria
    systemctl daemon-reload
    
    if [[ "$clean_choice" == "2" ]]; then
        crontab -l 2>/dev/null | grep -v "/etc/ddr/quota.sh" | crontab - 2>/dev/null || true
        rm -rf /etc/ddr /usr/local/bin/sb
        echo -e "${GREEN}✔ 环境与防火墙规则已 100% 物理清空，VPS 现已恢复处女态！${NC}"; exit 0
    else
        rm -f /etc/ddr/.env
        echo -e "${GREEN}✔ 核心与防火墙规则已清理，快捷键缓存保留。${NC}"; sleep 2
    fi
}

check_virgin_state() {
    clear
    echo -e "\n\033[1;33m========================================================\033[0m"
    echo -e "\033[1;33m       Aio-box 终极环境纯净度审计 (Virgin State Check)     \033[0m"
    echo -e "\033[1;33m========================================================\033[0m\n"

    echo -e "\033[1;36m[1/6] 检查物理端口死锁 (443/2053 等)...\033[0m"
    local PORT_CHECK=$(ss -tulpn | grep -E ':80\b|:443\b|:2053\b|:8443\b|:54321\b' 2>/dev/null)
    if [[ -z "$PORT_CHECK" ]]; then
        echo -e "\033[1;32m  ✔ 完美：关键端口全部空闲，无任何监听。\033[0m"
    else
        echo -e "\033[1;31m  [!] 警告：发现以下端口被占用：\033[0m\n$PORT_CHECK"
    fi

    echo -e "\n\033[1;36m[2/6] 检查幽灵进程残留...\033[0m"
    local PROC_CHECK=$(ps aux | grep -E 'xray|sing-box|hysteria' | grep -v grep 2>/dev/null)
    if [[ -z "$PROC_CHECK" ]]; then
        echo -e "\033[1;32m  ✔ 完美：无任何代理引擎及僵尸进程存活。\033[0m"
    else
        echo -e "\033[1;31m  [!] 警告：发现以下残留进程：\033[0m\n$PROC_CHECK"
    fi

    echo -e "\n\033[1;36m[3/6] 检查内核 NAT 流量黑洞...\033[0m"
    local NAT_CHECK=$(iptables -t nat -L PREROUTING -nv 2>/dev/null | grep -i REDIRECT)
    if [[ -z "$NAT_CHECK" ]]; then
        echo -e "\033[1;32m  ✔ 完美：底层防火墙转发链纯净，无幽灵跳转。\033[0m"
    else
        echo -e "\033[1;31m  [!] 警告：发现残留的流量重定向规则：\033[0m\n$NAT_CHECK"
    fi

    echo -e "\n\033[1;36m[4/6] 检查 Systemd 服务注册表...\033[0m"
    local SVC_CHECK=$(systemctl status xray sing-box hysteria 2>&1 | grep -i "active (running)")
    if [[ -z "$SVC_CHECK" ]]; then
        echo -e "\033[1;32m  ✔ 完美：历史服务已被彻底剥离系统。\033[0m"
    else
        echo -e "\033[1;31m  [!] 警告：系统仍在尝试运行以下服务：\033[0m\n$SVC_CHECK"
    fi

    echo -e "\n\033[1;36m[5/6] 检查核心文件与配置污染...\033[0m"
    local FILE_CHECK=$(ls -d /usr/local/etc/xray /etc/sing-box /usr/local/bin/xray /usr/local/bin/sing-box /etc/ddr /etc/hysteria 2>/dev/null)
    if [[ -z "$FILE_CHECK" ]]; then
        echo -e "\033[1;32m  ✔ 完美：硬盘相关目录已被彻底粉碎。\033[0m"
    else
        echo -e "\033[1;31m  [!] 警告：发现残留文件或目录：\033[0m\n$FILE_CHECK"
    fi

    echo -e "\n\033[1;36m[6/6] 检查 VPS 外部出站网络健康度...\033[0m"
    if curl -I -s -m 5 https://www.google.com | head -n 1 | grep -qE "200|301|302"; then
        echo -e "\033[1;32m  ✔ 完美：服务器出站连通性正常，DNS 解析正常。\033[0m"
    else
        echo -e "\033[1;31m  [!] 警告：服务器无法访问外部网络，请检查 GCP 整体出站策略。\033[0m"
    fi

    echo -e "\n\033[1;33m========================================================\033[0m"
    read -ep "按回车返回主菜单..."
}

setup_shortcut
while true; do
    IPV4=$(curl -s4m3 api.ipify.org || echo "N/A"); PUBLIC_IP="$IPV4"
    systemctl is-active --quiet xray && STATUS="${GREEN}Running (Xray)${NC}" || { systemctl is-active --quiet sing-box && STATUS="${CYAN}Running (Sing-box)${NC}" || STATUS="${RED}Stopped${NC}"; }
    source /etc/ddr/.env 2>/dev/null && CUR_MODE="[${CORE}-${MODE}]" || CUR_MODE=""
    
    clear; echo -e "${BLUE}======================================================================${NC}\n${BOLD}${PURPLE}  Aio-box Ultimate Console [Apex V45 Perfect] ${NC}\n${BLUE}======================================================================${NC}"
    echo -e " IP: ${YELLOW}$IPV4${NC} | STATUS: $STATUS $CUR_MODE\n${BLUE}----------------------------------------------------------------------${NC}"
    echo -e " ${YELLOW}[ Xray-core 部署 / Deploy ]${NC}       ${CYAN}[ Sing-box 部署 / Deploy ]${NC}"
    echo -e " ${GREEN}1.${NC} VLESS-Vision (REALITY)          ${GREEN}5.${NC} VLESS-Vision (REALITY)"
    echo -e " ${GREEN}2.${NC} Hysteria 2                      ${GREEN}6.${NC} Hysteria 2"
    echo -e " ${GREEN}3.${NC} Shadowsocks                     ${GREEN}7.${NC} Shadowsocks"
    echo -e " ${GREEN}4.${NC} 协议全家桶 / All-in-One         ${GREEN}8.${NC} 协议全家桶 / All-in-One"
    echo -e "${BLUE}----------------------------------------------------------------------${NC}"
    echo -e " ${YELLOW}[ 系统与维护 / System & Management ]${NC}"
    echo -e " ${GREEN}9.${NC}  流量监控与熔断 / Quota Guard    ${GREEN}10.${NC} 网络诊断测速 / Diagnostics"
    echo -e " ${GREEN}11.${NC} VPS 全面优化 / VPS Tuning       ${GREEN}12.${NC} 详细功能说明 / Usage Guide"
    echo -e " ${YELLOW}13.${NC} 全部节点参数 / Export Nodes     ${YELLOW}14.${NC} 源码 OTA 更新 / OTA Update"
    echo -e " ${RED}15.${NC} 彻底清空卸载 / Clean Purge      ${CYAN}16.${NC} 环境纯净度检查 / Virgin Check"
    echo -e " ${GREEN}0.${NC}  退出面板 / Exit Dashboard"
    echo -e "${BLUE}======================================================================${NC}"
    read -ep " 请选择 / Please select [0-16]: " choice
    case $choice in
        1|2|3|4) deploy_xray "$([[ $choice == 1 ]] && echo VLESS || [[ $choice == 2 ]] && echo HY2 || [[ $choice == 3 ]] && echo SS || echo ALL)" ;;
        5|6|7|8) deploy_singbox "$([[ $choice == 5 ]] && echo VLESS || [[ $choice == 6 ]] && echo HY2 || [[ $choice == 7 ]] && echo SS || echo ALL)" ;;
        9) setup_quota ;; 10) diagnostics ;; 11) tune_vps ;; 12) show_usage ;; 13) view_config "" ;; 
        14) setup_shortcut "update"; echo -e "OTA 成功。 / OTA Successful."; exit 0 ;;
        15) clean_uninstall ;; 16) check_virgin_state ;; 0) clear; exit 0 ;; *) sleep 1 ;;
    esac
done
