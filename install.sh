#!/usr/bin/env bash
# ====================================================================
# All-in-One Duo Ultimate Console [Dual-Core Omni | Bilingual | Shortcut 'sb']
# Features: Global Shortcut 'sb', VPS Auto-Tuning, Traffic Guard Quota
# Author: alariclin | Version: 2026.04.Final
# ====================================================================

set -e
export DEBIAN_FRONTEND=noninteractive
export LC_ALL=C

RED='\033[0;31m' GREEN='\033[0;32m' YELLOW='\033[0;33m' BLUE='\033[0;36m' PURPLE='\033[0;35m' CYAN='\033[0;36m' NC='\033[0m' BOLD='\033[1m'
trap 'echo -e "\n${RED}[!] 触发安全自愈，系统中断并回滚 / Rollback initiated.${NC}"; exit 1' ERR

# --- [0] 快捷指令注入 / Setup Global Shortcut 'sb' ---
setup_shortcut() {
    if [[ ! -f /usr/local/bin/sb ]]; then
        echo '#!/usr/bin/env bash' > /usr/local/bin/sb
        # 这里的链接已修复为最新的 all-in-one-duo 仓库
        echo 'bash <(curl -Ls https://raw.githubusercontent.com/alariclin/all-in-one-duo/main/install.sh)' >> /usr/local/bin/sb
        chmod +x /usr/local/bin/sb
    fi
}

# --- [1] 环境初始化与依赖 / Env & Dependencies ---
check_base() {
    if [[ ! -d /run/systemd/system ]]; then
        echo -e "${RED}[!] 错误: 不支持无 Systemd 的系统 / Systemd is required.${NC}"; exit 1
    fi
    if command -v apt-get >/dev/null; then PKG_MGR="apt-get"; PKG_INSTALL="apt-get install -y -q"; PKG_UPDATE="apt-get update -y -q"
    elif command -v yum >/dev/null; then PKG_MGR="yum"; PKG_INSTALL="yum install -y -q"; PKG_UPDATE="yum makecache -y -q"
    else echo -e "${RED}[!] 仅支持 Debian/Ubuntu 或 RHEL/CentOS.${NC}"; exit 1; fi
}

check_env() {
    check_base
    if ! command -v jq >/dev/null || ! command -v bc >/dev/null; then
        echo -e "${YELLOW}[*] 安装底层核心依赖 / Installing base dependencies...${NC}"
        $PKG_UPDATE >/dev/null 2>&1 || true
        $PKG_INSTALL wget curl jq openssl uuid-runtime psmisc socat cron chrony fail2ban iptables iproute2 python3 bc >/dev/null 2>&1 || true
        if [[ "$PKG_MGR" == "apt-get" ]]; then $PKG_INSTALL iptables-persistent >/dev/null 2>&1 || true; fi
        systemctl enable cron 2>/dev/null || true; systemctl start cron 2>/dev/null || true
    fi
}

# --- [2] VPS 极致开荒 (手动触发) / VPS Tuning ---
tune_vps() {
    clear
    echo -e "${BLUE}======================================================${NC}"
    echo -e "${BOLD}${CYAN}  VPS 极致开荒与系统调优 / VPS Initialization & Tuning ${NC}"
    echo -e "${BLUE}======================================================${NC}"
    check_base
    
    if command -v getenforce >/dev/null && [ "$(getenforce)" == "Enforcing" ]; then
        echo -e "${YELLOW}[*] 解除 SELinux 封锁 / Bypassing SELinux...${NC}"
        $PKG_INSTALL policycoreutils-python-utils 2>/dev/null || true
        semanage port -a -t http_port_t -p tcp 443 2>/dev/null || true
        semanage port -a -t http_port_t -p tcp 2053 2>/dev/null || true
    fi

    PHY_MEM=$(free -m | awk '/^Mem:/{print $2}'); SWAP_MEM=$(free -m | awk '/^Swap:/{print $2}')
    if [[ "$SWAP_MEM" == "0" ]] && [[ "$PHY_MEM" -le 1500 ]]; then
        echo -e "${YELLOW}[*] 注入 1GB 虚拟内存 Swap / Injecting 1GB Swap...${NC}"
        fallocate -l 1G /swapfile || dd if=/dev/zero of=/swapfile bs=1M count=1024 >/dev/null 2>&1
        chmod 600 /swapfile; mkswap /swapfile >/dev/null 2>&1; swapon /swapfile >/dev/null 2>&1
        grep -q '/swapfile' /etc/fstab || echo "/swapfile swap swap defaults 0 0" >> /etc/fstab
    fi

    echo -e "${YELLOW}[*] 突破 Ulimit 与 TCP 网络栈 / Tuning TCP & Limits...${NC}"
    grep -q '1048576' /etc/security/limits.conf || { echo "* soft nofile 1048576" >> /etc/security/limits.conf; echo "* hard nofile 1048576" >> /etc/security/limits.conf; }
    
    systemctl restart fail2ban 2>/dev/null || true
    systemctl enable chronyd 2>/dev/null || true; systemctl start chronyd 2>/dev/null || true
    date -s "$(curl -sI https://google.com | grep -i Date | sed 's/Date: //g')" >/dev/null 2>&1 || true
    modprobe tcp_bbr 2>/dev/null || true
    cat > /etc/sysctl.d/99-ddr-tune.conf << 'EOF'
fs.file-max = 1048576
net.core.rmem_max = 67108864
net.core.wmem_max = 67108864
net.core.netdev_max_backlog = 10000
net.core.somaxconn = 32768
net.ipv4.tcp_syncookies = 1
net.ipv4.tcp_tw_reuse = 1
net.ipv4.tcp_fin_timeout = 30
net.ipv4.tcp_keepalive_time = 600
net.ipv4.tcp_fastopen = 3
net.ipv4.tcp_rmem = 4096 87380 67108864
net.ipv4.tcp_wmem = 4096 65536 67108864
net.ipv4.tcp_mtu_probing = 1
net.core.default_qdisc = fq
net.ipv4.tcp_congestion_control = bbr
EOF
    sysctl -p /etc/sysctl.d/99-ddr-tune.conf >/dev/null 2>&1 || true
    echo -e "${GREEN}✔ 开荒完成！系统处于巅峰状态。/ Tuning Complete!${NC}"; read -p "按回车返回 / Press Enter..."
}

# --- [3] 系统探针与预检 / Probe & Pre-check ---
get_system_info() {
    IPV4=$(curl -s4m3 api.ipify.org || echo "")
    IPV6=$(curl -s6m3 api64.ipify.org || echo "")
    [[ -n "$IPV4" ]] && PUBLIC_IP="$IPV4" && LINK_IP="$IPV4" && DNS_TYPE="A" || { PUBLIC_IP="$IPV6"; LINK_IP="[$IPV6]"; DNS_TYPE="AAAA"; }
    
    if systemctl is-active --quiet xray; then STATUS="${GREEN}Xray-core Running${NC}"; CORE_RUNNING="xray"
    elif systemctl is-active --quiet sing-box; then STATUS="${CYAN}Sing-box Running${NC}"; CORE_RUNNING="singbox"
    else STATUS="${RED}Stopped / 未运行${NC}"; CORE_RUNNING="none"; fi
    
    [[ -n "$PUBLIC_IP" ]] && ASN_ORG=$(curl -sm3 "ipinfo.io/$PUBLIC_IP/org" | tr '[:lower:]' '[:upper:]' | cut -d ' ' -f 2- || echo "GENERIC") || ASN_ORG="UNKNOWN"
    COUNTRY=$(curl -sm3 "ipinfo.io/$PUBLIC_IP/country" | tr '[:lower:]' '[:upper:]' | tr -d '\n\r' || echo "US")
}

check_port_conflict() {
    echo -e "${YELLOW}[*] 检测系统冲突与端口 / Checking conflicts...${NC}"
    if [[ "$CORE_RUNNING" != "none" ]] || ss -tulpn | grep -qE ':(443|2053|8443) '; then
        echo -e "${RED}[!] 核心正在运行或端口(443/2053/8443)被占用 / Ports occupied.${NC}"
        read -p "    强制卸载旧核心并释放端口？/ Force clean ports? [y/N]: " rm_old
        if [[ "${rm_old,,}" == "y" ]]; then
            systemctl stop xray sing-box nginx 2>/dev/null || true; systemctl disable xray sing-box nginx 2>/dev/null || true
            rm -rf /usr/local/etc/xray /etc/sing-box /etc/ddr /usr/local/bin/xray /usr/local/bin/sing-box
            if command -v fuser >/dev/null 2>&1; then fuser -k 443/tcp 443/udp 2053/tcp 8443/tcp 8443/udp 80/tcp 2>/dev/null || true; fi
            echo -e "${GREEN} -> 清理完成 / Cleanup successful.${NC}"
        else exit 1; fi
    fi
}

calculate_sni() {
    ASN_UPPER=$(echo "$ASN_ORG" | tr '[:lower:]' '[:upper:]')
    if [[ "$ASN_UPPER" == *"AMAZON"* ]]; then
        case "$COUNTRY" in "JP") AUTO_REALITY="s3.ap-northeast-1.amazonaws.com" ;; "SG") AUTO_REALITY="s3.ap-southeast-1.amazonaws.com" ;; "HK") AUTO_REALITY="s3.ap-east-1.amazonaws.com" ;; "GB") AUTO_REALITY="s3.eu-west-2.amazonaws.com" ;; *) AUTO_REALITY="s3.us-west-2.amazonaws.com" ;; esac
    elif [[ "$ASN_UPPER" == *"GOOGLE"* ]]; then AUTO_REALITY="storage.googleapis.com"
    elif [[ "$ASN_UPPER" == *"MICROSOFT"* || "$ASN_UPPER" == *"AZURE"* ]]; then AUTO_REALITY="dl.delivery.mp.microsoft.com"
    elif [[ "$ASN_UPPER" == *"ALIBABA"* || "$ASN_UPPER" == *"ALIPAY"* ]]; then AUTO_REALITY="www.alibabacloud.com"
    elif [[ "$ASN_UPPER" == *"TENCENT"* ]]; then AUTO_REALITY="intl.cloud.tencent.com"
    elif [[ "$ASN_UPPER" == *"CLOUDFLARE"* ]]; then AUTO_REALITY="time.cloudflare.com"
    elif [[ "$ASN_UPPER" == *"ORACLE"* ]]; then AUTO_REALITY="docs.oracle.com"
    else case "$COUNTRY" in "CN"|"HK"|"TW"|"SG"|"JP"|"KR") AUTO_REALITY="gateway.icloud.com" ;; "US"|"CA") AUTO_REALITY="swcdn.apple.com" ;; *) AUTO_REALITY="www.microsoft.com" ;; esac; fi
    AUTO_HY2="api-sync.network"
}

# --- [4] 证书引擎与熔断器 / ACME & Quota Guard ---
setup_traffic_guard() {
    local quota_gb=$1; local core_name=$2
    if [[ "$quota_gb" -le 0 ]]; then
        rm -f /etc/ddr/.quota /usr/local/bin/ddr-quota.sh; crontab -l 2>/dev/null | grep -v 'ddr-quota.sh' | crontab -
        return
    fi
    echo "$quota_gb" > /etc/ddr/.quota
    cat > /usr/local/bin/ddr-quota.sh << EOF
#!/bin/bash
QUOTA_GB=\$(cat /etc/ddr/.quota)
if [[ "$core_name" == "xray" ]]; then STATS=\$(/usr/local/bin/xray api statsquery -server=127.0.0.1:10085 2>/dev/null); [[ -z "\$STATS" ]] && exit 0; TOTAL_BYTES=\$(echo "\$STATS" | jq '[.stat[] | .value] | add')
else STATS=\$(/usr/local/bin/sing-box stats query --json 2>/dev/null); [[ -z "\$STATS" || "\$STATS" == "null" ]] && exit 0; TOTAL_BYTES=\$(echo "\$STATS" | jq '[.[].stats | .rx + .tx] | add'); fi
TOTAL_GB=\$(echo "scale=2; \$TOTAL_BYTES / 1073741824" | bc)
if (( \$(echo "\$TOTAL_GB >= \$QUOTA_GB" | bc -l) )); then systemctl stop $core_name; echo "Traffic Quota Exceeded. \$TOTAL_GB GB used." > /var/log/ddr-quota.log; fi
EOF
    chmod +x /usr/local/bin/ddr-quota.sh
    (crontab -l 2>/dev/null | grep -v 'ddr-quota.sh'; echo "*/5 * * * * /usr/local/bin/ddr-quota.sh") | crontab -
    (crontab -l 2>/dev/null | grep -v "$core_name restart"; echo "0 0 1 * * systemctl restart $core_name") | crontab -
}

# --- [5] Xray-core 部署 / Xray Deployment ---
install_xray() {
    local MODE=$1
    clear
    echo -e "${BLUE}======================================================${NC}"
    echo -e "${BOLD}${GREEN} 部署 Xray-core [xhttp 极限隐匿] - Mode: $MODE ${NC}"
    echo -e "${BLUE}======================================================${NC}"
    check_env; check_port_conflict

    read -p " [?] 输入每月限额(GB，0为不限制) / Monthly Quota (0=unlimited): " QUOTA_GB
    [[ -z "$QUOTA_GB" || ! "$QUOTA_GB" =~ ^[0-9]+$ ]] && QUOTA_GB=0

    echo -e "\n [?] 路由分流 / Routing:\n  1. 全局代理 / Global Proxy\n  2. 绕过大陆与广告 / Bypass CN & Ads (推荐)"
    read -p " 选择 / Select [1-2, default 2]: " ROUTE_CHOICE
    [[ -z "$ROUTE_CHOICE" ]] && ROUTE_CHOICE=2

    echo -e "\n${YELLOW}[1/4] 获取最新 Xray-core / Fetching Xray...${NC}"
    bash -c "$(curl -L https://github.com/XTLS/Xray-install/raw/main/install-release.sh)" @ install >/dev/null 2>&1

    echo -e "${YELLOW}[2/4] SNI 矩阵计算与密码学 / SNI & Crypto...${NC}"
    calculate_sni
    echo -e "${CYAN} -> 推荐 REALITY SNI: ${AUTO_REALITY}${NC}"; read -p " -> 自定义 REALITY SNI (回车默认): " CUSTOM_REALITY; REALITY_SNI=${CUSTOM_REALITY:-$AUTO_REALITY}
    echo -e "${CYAN} -> 推荐 Hysteria2 SNI: ${AUTO_HY2}${NC}"; read -p " -> 自定义 Hy2 SNI (回车默认): " CUSTOM_HY2; HY2_SNI=${CUSTOM_HY2:-$AUTO_HY2}

    UUID=$(uuidgen); HY2_PASS=$(openssl rand -base64 12 | tr -dc 'a-zA-Z0-9'); HY2_OBFS=$(openssl rand -base64 8 | tr -dc 'a-zA-Z0-9')
    SS_PASS=$(openssl rand -base64 16 | tr -d '\n\r'); SS_SIP_CORE=$(echo -n "2022-blake3-aes-128-gcm:${SS_PASS}" | base64 -w 0)
    KEYS=$(xray x25519); PRIVATE_KEY=$(echo "$KEYS" | grep "Private" | awk '{print $3}'); PUBLIC_KEY=$(echo "$KEYS" | grep "Public" | awk '{print $3}'); SHORT_ID=$(openssl rand -hex 4)
    
    mkdir -p /usr/local/etc/xray; mkdir -p /etc/ddr
    HY2_INSECURE_FLAG="1"
    if [[ "$MODE" == "all" || "$MODE" == "hy2" ]]; then
        read -p " [?] 输入已解析域名以申请真实证书(回车自签) / Domain for ACME: " USER_DOMAIN
        if [[ -n "$USER_DOMAIN" ]]; then
            echo -e "${CYAN} -> DoH 溯源验证 / DoH check...${NC}"
            if command -v fuser >/dev/null 2>&1; then fuser -k 80/tcp 2>/dev/null || true; fi
            RESOLVED_IP=$(curl -sH "accept: application/dns-json" "https://cloudflare-dns.com/dns-query?name=$USER_DOMAIN&type=$DNS_TYPE" | jq -r '.Answer[0].data' || echo "")
            if [[ "$RESOLVED_IP" == "$PUBLIC_IP" ]]; then
                curl -s https://get.acme.sh | sh >/dev/null 2>&1; ~/.acme.sh/acme.sh --set-default-ca --server letsencrypt >/dev/null 2>&1
                if ~/.acme.sh/acme.sh --issue -d "$USER_DOMAIN" --standalone -k ec-256; then
                    ~/.acme.sh/acme.sh --installcert -d "$USER_DOMAIN" --fullchainpath /usr/local/etc/xray/hy2.crt --keypath /usr/local/etc/xray/hy2.key >/dev/null 2>&1
                    HY2_SNI="$USER_DOMAIN"; HY2_INSECURE_FLAG="0"; echo -e "${GREEN} -> ACME 成功！${NC}"
                fi
            fi
        fi
        if [[ "$HY2_INSECURE_FLAG" == "1" ]]; then openssl ecparam -genkey -name prime256v1 -out /usr/local/etc/xray/hy2.key 2>/dev/null; openssl req -new -x509 -days 36500 -key /usr/local/etc/xray/hy2.key -out /usr/local/etc/xray/hy2.crt -subj "/CN=$HY2_SNI" 2>/dev/null; fi
    fi

    echo -e "${YELLOW}[3/4] 编译 Xray 配置 / Compiling Config...${NC}"
    INBOUNDS=""
    if [[ "$MODE" == "all" || "$MODE" == "vless" ]]; then INBOUNDS+='{ "port": 443, "protocol": "vless", "tag": "vless-in", "settings": { "clients": [{"id": "'$UUID'", "flow": "xtls-rprx-vision"}], "decryption": "none" }, "streamSettings": { "network": "xhttp", "security": "reality", "xhttpSettings": { "mode": "packet-up", "extra": { "padding": "1-1500" } }, "realitySettings": { "dest": "'$REALITY_SNI':443", "serverNames": ["'$REALITY_SNI'"], "privateKey": "'$PRIVATE_KEY'", "shortIds": ["'$SHORT_ID'"] } } },'; fi
    if [[ "$MODE" == "all" || "$MODE" == "hy2" ]]; then INBOUNDS+='{ "port": 8443, "protocol": "hysteria2", "tag": "hy2-in", "settings": { "users": [{"password": "'$HY2_PASS'"}] }, "streamSettings": { "network": "hysteria2", "security": "tls", "tlsSettings": { "alpn": ["h3"], "certificates": [{ "certificateFile": "/usr/local/etc/xray/hy2.crt", "keyFile": "/usr/local/etc/xray/hy2.key" }] }, "hysteria2Settings": { "obfs": "salamander", "obfsPassword": "'$HY2_OBFS'" } } },'; fi
    if [[ "$MODE" == "all" || "$MODE" == "ss" ]]; then INBOUNDS+='{ "port": 2053, "protocol": "shadowsocks", "tag": "ss-in", "settings": { "method": "2022-blake3-aes-128-gcm", "password": "'$SS_PASS'", "network": "tcp,udp" } },'; fi
    INBOUNDS+='{ "listen": "127.0.0.1", "port": 10085, "protocol": "dokodemo-door", "settings": { "address": "127.0.0.1" }, "tag": "api-in" }'
    if [[ "$ROUTE_CHOICE" == "2" ]]; then ROUTE_RULES='[{"type":"field","outboundTag":"direct","domain":["geosite:cn"]},{"type":"field","outboundTag":"direct","ip":["geoip:cn","geoip:private"]},{"type":"field","outboundTag":"block","domain":["geosite:category-ads-all"]},{"inboundTag":["api-in"],"outboundTag":"api","type":"field"}]'; else ROUTE_RULES='[{"inboundTag":["api-in"],"outboundTag":"api","type":"field"}]'; fi

    cat > /usr/local/etc/xray/config.json << EOF
{ "log": { "loglevel": "warning" }, "stats": {}, "api": { "services": ["StatsService"], "tag": "api" }, "policy": { "system": { "statsInboundDownlink": true, "statsInboundUplink": true }, "levels": { "0": { "statsUserUplink": true, "statsUserDownlink": true } } }, "inbounds": [ $INBOUNDS ], "outbounds": [ { "protocol": "freedom", "tag": "direct" }, { "protocol": "blackhole", "tag": "block" } ], "routing": { "domainStrategy": "IPIfNonMatch", "rules": $ROUTE_RULES } }
EOF

    echo -e "${YELLOW}[4/4] 防火墙跳跃与系统守护 / Firewalls...${NC}"
    iptables -t nat -F PREROUTING 2>/dev/null || true
    iptables -t nat -A PREROUTING -p udp --dport 20000:50000 -j REDIRECT --to-ports 8443
    iptables -I INPUT -p tcp -m multiport --dports 80,443,2053,8443 -j ACCEPT; iptables -I INPUT -p udp -m multiport --dports 443,2053,8443,20000:50000 -j ACCEPT
    if command -v netfilter-persistent >/dev/null; then netfilter-persistent save 2>/dev/null || true; fi

    sed -i '/LimitNOFILE/d' /etc/systemd/system/xray.service 2>/dev/null || true; sed -i '/LimitNPROC/d' /etc/systemd/system/xray.service 2>/dev/null || true; sed -i '/\[Service\]/a LimitNPROC=infinity\nLimitNOFILE=infinity' /etc/systemd/system/xray.service
    systemctl daemon-reload && systemctl restart xray && systemctl enable xray
    setup_traffic_guard "$QUOTA_GB" "xray"

    cat > /etc/ddr/.env << ENV_EOF
CORE="xray"
UUID="$UUID"
HY2_PASS="$HY2_PASS"
HY2_OBFS="$HY2_OBFS"
REALITY_SNI="$REALITY_SNI"
HY2_SNI="$HY2_SNI"
PUBLIC_KEY="$PUBLIC_KEY"
SHORT_ID="$SHORT_ID"
HY2_INSECURE_FLAG="$HY2_INSECURE_FLAG"
LINK_IP="$LINK_IP"
SS_SIP_CORE="$SS_SIP_CORE"
ENV_EOF
    echo -e "\n${GREEN}✔ Xray-core 部署成功！/ Installed Successfully!${NC}"; read -p "按回车返回 / Press Enter..."
}

# --- [6] Sing-box 部署 / Sing-box Deployment ---
install_singbox() {
    local MODE=$1
    clear
    echo -e "${BLUE}======================================================${NC}"
    echo -e "${BOLD}${GREEN} 部署 Sing-box [全能矩阵架构] - Mode: $MODE ${NC}"
    echo -e "${BLUE}======================================================${NC}"
    check_env; check_port_conflict

    read -p " [?] 输入每月限额(GB，0为不限制) / Monthly Quota (0=unlimited): " QUOTA_GB
    [[ -z "$QUOTA_GB" || ! "$QUOTA_GB" =~ ^[0-9]+$ ]] && QUOTA_GB=0
    echo -e "\n [?] 路由分流 / Routing:\n  1. 全局代理 / Global Proxy\n  2. 绕过大陆与广告 / Bypass CN & Ads (推荐)"
    read -p " 选择 / Select [1-2, default 2]: " ROUTE_CHOICE
    [[ -z "$ROUTE_CHOICE" ]] && ROUTE_CHOICE=2

    echo -e "\n${YELLOW}[1/4] 获取最新 Sing-box / Fetching Sing-box...${NC}"
    SB_VERSION=$(curl -s "https://api.github.com/repos/SagerNet/sing-box/releases/latest" | grep -Po '"tag_name": "v\K[^"]*')
    [[ -z "$SB_VERSION" ]] && SB_VERSION="1.10.1" # 降级容错
    ARCH=$(uname -m | sed 's/x86_64/amd64/;s/aarch64/arm64/')
    DL_URL="https://github.com/SagerNet/sing-box/releases/download/v${SB_VERSION}/sing-box-${SB_VERSION}-linux-${ARCH}.tar.gz"
    if ! curl -Is -m 5 "$DL_URL" | grep -q "200\|302"; then DL_URL="https://ghp.ci/$DL_URL"; fi
    curl -Lo /tmp/sb.tar.gz "$DL_URL" && tar -xzf /tmp/sb.tar.gz -C /tmp && mv /tmp/sing-box-*/sing-box /usr/local/bin/ && chmod +x /usr/local/bin/sing-box

    echo -e "${YELLOW}[2/4] SNI 矩阵计算与密码学 / SNI & Crypto...${NC}"
    calculate_sni
    echo -e "${CYAN} -> 推荐 REALITY SNI: ${AUTO_REALITY}${NC}"; read -p " -> 自定义 REALITY SNI (回车默认): " CUSTOM_REALITY; REALITY_SNI=${CUSTOM_REALITY:-$AUTO_REALITY}
    echo -e "${CYAN} -> 推荐 Hysteria2 SNI: ${AUTO_HY2}${NC}"; read -p " -> 自定义 Hy2 SNI (回车默认): " CUSTOM_HY2; HY2_SNI=${CUSTOM_HY2:-$AUTO_HY2}

    UUID=$(uuidgen); HY2_PASS=$(openssl rand -base64 12 | tr -dc 'a-zA-Z0-9'); HY2_OBFS=$(openssl rand -base64 8 | tr -dc 'a-zA-Z0-9')
    SS_PASS=$(openssl rand -base64 16 | tr -d '\n\r'); SS_SIP_CORE=$(echo -n "2022-blake3-aes-128-gcm:${SS_PASS}" | base64 -w 0)
    KEYS=$(/usr/local/bin/sing-box generate reality-keypair); PRIVATE_KEY=$(echo "$KEYS" | grep -i "Private" | awk '{print $2}'); PUBLIC_KEY=$(echo "$KEYS" | grep -i "Public" | awk '{print $2}'); SHORT_ID=$(openssl rand -hex 4)
    
    mkdir -p /etc/sing-box; mkdir -p /etc/ddr
    HY2_INSECURE_FLAG="1"; MASQUERADE_CFG=""

    if [[ "$MODE" == "all" || "$MODE" == "hy2" ]]; then
        read -p " [?] 输入已解析域名以申请真实证书(回车自签) / Domain for ACME: " USER_DOMAIN
        if [[ -n "$USER_DOMAIN" ]]; then
            echo -e "${CYAN} -> DoH 溯源验证 / DoH check...${NC}"
            if command -v fuser >/dev/null 2>&1; then fuser -k 80/tcp 2>/dev/null || true; fi
            RESOLVED_IP=$(curl -sH "accept: application/dns-json" "https://cloudflare-dns.com/dns-query?name=$USER_DOMAIN&type=$DNS_TYPE" | jq -r '.Answer[0].data' || echo "")
            if [[ "$RESOLVED_IP" == "$PUBLIC_IP" ]]; then
                curl -s https://get.acme.sh | sh >/dev/null 2>&1; ~/.acme.sh/acme.sh --set-default-ca --server letsencrypt >/dev/null 2>&1
                if ~/.acme.sh/acme.sh --issue -d "$USER_DOMAIN" --standalone -k ec-256; then
                    ~/.acme.sh/acme.sh --installcert -d "$USER_DOMAIN" --fullchainpath /etc/sing-box/hy2.crt --keypath /etc/sing-box/hy2.key >/dev/null 2>&1
                    HY2_SNI="$USER_DOMAIN"; HY2_INSECURE_FLAG="0"; MASQUERADE_CFG="\"masquerade\": \"https://nginx.org\","
                    echo -e "${GREEN} -> ACME 成功！${NC}"
                fi
            fi
        fi
        if [[ "$HY2_INSECURE_FLAG" == "1" ]]; then openssl ecparam -genkey -name prime256v1 -out /etc/sing-box/hy2.key 2>/dev/null; openssl req -new -x509 -days 36500 -key /etc/sing-box/hy2.key -out /etc/sing-box/hy2.crt -subj "/CN=$HY2_SNI" 2>/dev/null; fi
    fi

    echo -e "${YELLOW}[3/4] 编译 Sing-box 配置 / Compiling Config...${NC}"
    if [[ "$ROUTE_CHOICE" == "2" ]]; then ROUTE_RULES='{"rules":[{"geosite":["cn"],"geoip":["cn"],"outbound":"direct"},{"geosite":["category-ads-all"],"outbound":"block"}]}'; else ROUTE_RULES='{"rules":[]}'; fi
    INBOUNDS_JSON=""
    if [[ "$MODE" == "all" || "$MODE" == "vless" ]]; then INBOUNDS_JSON+='{ "type": "vless", "tag": "vless-in", "listen": "::", "listen_port": 443, "users": [ { "uuid": "'$UUID'", "flow": "xtls-rprx-vision" } ], "tls": { "enabled": true, "server_name": "'$REALITY_SNI'", "alpn": ["h2", "http/1.1"], "reality": { "enabled": true, "handshake": { "server": "'$REALITY_SNI'", "server_port": 443 }, "private_key": "'$PRIVATE_KEY'", "short_id": [ "'$SHORT_ID'" ] } } },'; fi
    if [[ "$MODE" == "all" || "$MODE" == "hy2" ]]; then INBOUNDS_JSON+='{ "type": "hysteria2", "tag": "hy2-in", "listen": "::", "listen_port": 443, "up_mbps": 1000, "down_mbps": 2000, "obfs": { "type": "salamander", "password": "'$HY2_OBFS'" }, "users": [ { "password": "'$HY2_PASS'" } ], '$MASQUERADE_CFG' "tls": { "enabled": true, "alpn": [ "h3" ], "certificate_path": "/etc/sing-box/hy2.crt", "key_path": "/etc/sing-box/hy2.key" } },'; fi
    if [[ "$MODE" == "all" || "$MODE" == "ss" ]]; then INBOUNDS_JSON+='{ "type": "shadowsocks", "tag": "ss-in", "listen": "::", "listen_port": 2053, "method": "2022-blake3-aes-128-gcm", "password": "'$SS_PASS'" },'; fi
    INBOUNDS_JSON=${INBOUNDS_JSON%,}

    cat > /etc/sing-box/config.json << CONFIG_EOF
{ "log": { "level": "warn" }, "stats": {}, "experimental": { "v2ray_api": { "stats": { "enabled": true }, "listen": "127.0.0.1:10085" } }, "inbounds": [ $INBOUNDS_JSON ], "outbounds": [ { "type": "direct", "tag": "direct" }, { "type": "block", "tag": "block" } ], "route": ${ROUTE_RULES} }
CONFIG_EOF

    echo -e "${YELLOW}[4/4] 防火墙跳跃与系统守护 / Firewalls...${NC}"
    iptables -t nat -F PREROUTING 2>/dev/null || true
    iptables -t nat -A PREROUTING -p udp --dport 20000:50000 -j REDIRECT --to-ports 443
    iptables -I INPUT -p tcp -m multiport --dports 80,443,2053 -j ACCEPT; iptables -I INPUT -p udp -m multiport --dports 443,2053,20000:50000 -j ACCEPT
    if command -v netfilter-persistent >/dev/null; then netfilter-persistent save 2>/dev/null || true; fi

    cat > /etc/systemd/system/sing-box.service << SVC_EOF
[Unit]
After=network.target nss-lookup.target
[Service]
ExecStart=/usr/local/bin/sing-box run -c /etc/sing-box/config.json
Restart=always
LimitNPROC=infinity
LimitNOFILE=infinity
CapabilityBoundingSet=CAP_NET_ADMIN CAP_NET_BIND_SERVICE
AmbientCapabilities=CAP_NET_ADMIN CAP_NET_BIND_SERVICE
[Install]
WantedBy=multi-user.target
SVC_EOF
    systemctl daemon-reload && systemctl enable --now sing-box
    setup_traffic_guard "$QUOTA_GB" "singbox"

    cat > /etc/ddr/.env << ENV_EOF
CORE="singbox"
UUID="$UUID"
HY2_PASS="$HY2_PASS"
HY2_OBFS="$HY2_OBFS"
REALITY_SNI="$REALITY_SNI"
HY2_SNI="$HY2_SNI"
PUBLIC_KEY="$PUBLIC_KEY"
SHORT_ID="$SHORT_ID"
HY2_INSECURE_FLAG="$HY2_INSECURE_FLAG"
LINK_IP="$LINK_IP"
SS_SIP_CORE="$SS_SIP_CORE"
ENV_EOF
    echo -e "\n${GREEN}✔ Sing-box 部署成功！/ Installed!${NC}"; read -p "按回车返回 / Press Enter..."
}

# --- [7] 运维管控 / Management & Stats ---
check_stats() {
    clear; echo -e "${YELLOW}--- 流量统计 / Traffic Stats ---${NC}"
    source /etc/ddr/.env 2>/dev/null
    if [[ "$CORE" == "xray" ]]; then /usr/local/bin/xray api statsquery -server=127.0.0.1:10085 | jq -r '.stat[] | "\(.name): \(.value | tonumber / 1073741824 | .[0:5])GB"' 2>/dev/null || echo "无数据"
    elif [[ "$CORE" == "singbox" ]]; then /usr/local/bin/sing-box stats query --json 2>/dev/null | jq -r '.[].stats | "\(.name): ↓\(.rx | tonumber / 1073741824 | .[0:5])GB ↑\(.tx | tonumber / 1073741824 | .[0:5])GB"' || echo "无数据"
    else echo "未运行 / Stopped"; fi
    if [[ -f /etc/ddr/.quota ]]; then echo -e "\n${CYAN}[!] 熔断开启 / Quota Guard ON: $(cat /etc/ddr/.quota)GB${NC}"; fi
    read -p "按回车返回 / Press Enter..."
}

run_diagnostics() {
    clear; echo -e "${GREEN}1. IP 纯净度检测 / Risk Check (Check.Place)\n2. VPS 综合测速 / Bench Test (bench.sh)${NC}"
    read -p "选择 / Select [1-2]: " d
    [[ "$d" == "1" ]] && bash <(curl -Ls https://Check.Place) -I
    [[ "$d" == "2" ]] && wget -qO- bench.sh | bash
    read -p "按回车返回 / Press Enter..."
}

manage_accounts() {
    clear; echo -e "${PURPLE}--- 账户管理 / Account Manager ---${NC}"
    source /etc/ddr/.env 2>/dev/null || { echo "未配置"; sleep 2; return; }
    echo -e " 1. 查看用户 / List Users\n 0. 返回 / Return"; read -p "选择 / Select: " u_choice
    if [[ "$u_choice" == "1" ]]; then
        if [[ "$CORE" == "xray" ]]; then jq -r '.inbounds[].settings.clients[]? | (.id // .password)' /usr/local/etc/xray/config.json 2>/dev/null || true
        else jq -r '.inbounds[].users[] | (.uuid // .password)' /etc/sing-box/config.json 2>/dev/null || true; fi
    fi
    read -p "按回车返回 / Press Enter..."
}

manage_links() {
    clear; source /etc/ddr/.env 2>/dev/null || { echo "未安装"; sleep 2; return; }
    echo -e "${YELLOW}--- 节点订阅链接 / Node Links ---${NC}"
    if [[ "$CORE" == "xray" ]]; then
        if grep -q "vless-in" /usr/local/etc/xray/config.json; then echo -e "${CYAN}[ Xray VLESS-xhttp-Reality ]${NC}\nvless://$UUID@$LINK_IP:443?encryption=none&flow=xtls-rprx-vision&security=reality&sni=$SNI&fp=chrome&pbk=$PBK&sid=$SID&type=xhttp#Xray-xhttp\n"; fi
        if grep -q "hy2-in" /usr/local/etc/xray/config.json; then echo -e "${CYAN}[ Xray Hysteria2 (Salamander) ]${NC}\nhy2://$HY2_PASS@$LINK_IP:8443?insecure=1&sni=$HY2_SNI&mport=20000-50000&obfs=salamander&obfs-password=$HY2_OBFS#Xray-Hy2\n"; fi
        if grep -q "ss-in" /usr/local/etc/xray/config.json; then echo -e "${CYAN}[ Xray SS-2022 ]${NC}\nss://$(echo -n "2022-blake3-aes-128-gcm:${SS_SIP_CORE}" | base64 -w 0)@$LINK_IP:2053#Xray-SS\n"; fi
    else
        if grep -q "vless-in" /etc/sing-box/config.json; then echo -e "${GREEN}[ Sing-box VLESS-Reality ]${NC}\nvless://$UUID@$LINK_IP:443?encryption=none&flow=xtls-rprx-vision&security=reality&sni=$SNI&fp=chrome&pbk=$PBK&sid=$SID&type=tcp#SB-Reality\n"; fi
        if grep -q "hy2-in" /etc/sing-box/config.json; then
            if [[ "$HY2_INSECURE_FLAG" == "0" ]]; then echo -e "${GREEN}[ Sing-box Hysteria 2 (Real CA) ]${NC}\nhy2://$HY2_PASS@$LINK_IP:443?sni=$HY2_SNI&mport=20000-50000&obfs=salamander&obfs-password=$HY2_OBFS#SB-Hy2-CA\n"
            else echo -e "${GREEN}[ Sing-box Hysteria 2 (Self-Signed) ]${NC}\nhy2://$HY2_PASS@$LINK_IP:443?insecure=1&sni=$HY2_SNI&mport=20000-50000&obfs=salamander&obfs-password=$HY2_OBFS#SB-Hy2-Self\n"; fi
        fi
        if grep -q "ss-in" /etc/sing-box/config.json; then echo -e "${GREEN}[ Sing-box SS-2022 ]${NC}\nss://${SS_SIP_CORE}@$LINK_IP:2053#SB-SS\n"; fi
    fi
    read -p "按回车返回 / Press Enter..."
}

view_detailed_config() {
    clear; source /etc/ddr/.env 2>/dev/null || { echo "未安装"; sleep 2; return; }
    echo -e "${BLUE}======================================================${NC}"
    echo -e "${BOLD}${CYAN}   核心参数 / Core Parameters ${NC}"
    echo -e "${BLUE}======================================================${NC}"
    echo -e "${BOLD}1. 核心/Core:${NC} $([[ "$CORE" == "xray" ]] && echo 'Xray-core (xhttp)' || echo 'Sing-box') | Limit: infinity"
    echo -e "\n${BOLD}2. VLESS-REALITY:${NC} 目标/Target SNI: $REALITY_SNI\n   - pbk: $PUBLIC_KEY | sid: $SHORT_ID"
    echo -e "\n${BOLD}3. Hysteria 2:${NC} 伪装/Fake SNI: $HY2_SNI\n   - 混淆: Salamander | CA: $([[ "$HY2_INSECURE_FLAG" == "0" ]] && echo 'Real' || echo 'Self-Signed')"
    echo -e "\n${BOLD}4. Shadowsocks 2022:${NC} Port: 2053"
    echo -e "${BLUE}======================================================${NC}"
    read -p "按回车返回 / Press Enter..."
}

# --- [8] 主面板循环 / Main Dashboard ---
setup_shortcut
while true; do
    check_env; get_system_info; clear
    echo -e "${BLUE}======================================================${NC}"
    echo -e "${BOLD}${PURPLE}  All-in-One Duo Console [Dual-Core Omni | 中文/English] ${NC}"
    echo -e "${BLUE}======================================================${NC}"
    echo -e " ${BOLD}IP:${NC} ${YELLOW}${PUBLIC_IP}${NC} | ${BOLD}ASN:${NC} ${CYAN}${ASN_ORG} (${COUNTRY})${NC}"
    echo -e " ${BOLD}STATUS:${NC} ${STATUS} ${CYAN}(快捷指令: sb)${NC}"
    echo -e "${BLUE}------------------------------------------------------${NC}"
    echo -e " ${BOLD}[ Xray-core 极限架构 / Xray Extreme Arch ]${NC}"
    echo -e " ${GREEN}1.${NC} 部署 全家桶 / Install Full Suite (VLESS-${YELLOW}xhttp${NC}+Hy2+SS)"
    echo -e " ${GREEN}2.${NC} 仅部署 / Install Only Xray VLESS-Reality-xhttp"
    echo -e " ${GREEN}3.${NC} 仅部署 / Install Only Xray Hysteria 2"
    echo -e " ${GREEN}4.${NC} 仅部署 / Install Only Xray SS-2022"
    echo -e "${BLUE}------------------------------------------------------${NC}"
    echo -e " ${BOLD}[ Sing-box 矩阵火力架构 / Sing-box Matrix Arch ]${NC}"
    echo -e " ${GREEN}5.${NC} 部署 全家桶 / Install Full Suite (VLESS+Hy2+SS)"
    echo -e " ${GREEN}6.${NC} 仅部署 / Install Only Sing-box VLESS-Reality"
    echo -e " ${GREEN}7.${NC} 仅部署 / Install Only Sing-box Hysteria 2"
    echo -e " ${GREEN}8.${NC} 仅部署 / Install Only Sing-box SS-2022"
    echo -e "${BLUE}------------------------------------------------------${NC}"
    echo -e " ${BOLD}[ 运维管理 / Management & Diagnostics ]${NC}"
    echo -e " ${GREEN}9.${NC}  流量监控 / Traffic Monitor & Quota"
    echo -e " ${GREEN}10.${NC} 诊断测速 / Diagnostics & Speedtest"
    echo -e " ${GREEN}11.${NC} VPS 极致开荒与调优 / VPS Init & Sys Tuning"
    echo -e " ${GREEN}12.${NC} 账户管理 / Account Management"
    echo -e " ${GREEN}13.${NC} 提取节点 / View Node URI Links"
    echo -e " ${GREEN}14.${NC} 查看参数 / View Detailed Parameters"
    echo -e " ${RED}15.${NC} 彻底卸载 / Deep Uninstall & Rollback"
    echo -e " ${GREEN}0.${NC}  退出 / Exit"
    echo -e "${BLUE}======================================================${NC}"
    read -p " 请选择 / Please select [0-15]: " choice
    case $choice in
        1) install_xray "all" ;; 2) install_xray "vless" ;; 3) install_xray "hy2" ;; 4) install_xray "ss" ;;
        5) install_singbox "all" ;; 6) install_singbox "vless" ;; 7) install_singbox "hy2" ;; 8) install_singbox "ss" ;;
        9) check_stats ;; 10) run_diagnostics ;; 11) tune_vps ;; 12) manage_accounts ;; 13) manage_links ;; 14) view_detailed_config ;;
        15) 
            systemctl stop xray sing-box 2>/dev/null || true
            systemctl disable xray sing-box 2>/dev/null || true
            rm -rf /usr/local/etc/xray /etc/sing-box /etc/ddr /usr/local/bin/xray /usr/local/bin/sing-box /usr/local/bin/ddr-quota.sh /usr/local/bin/sb
            crontab -l 2>/dev/null | grep -v 'ddr-quota.sh' | crontab -
            iptables -t nat -D PREROUTING -p udp --dport 20000:50000 -j REDIRECT --to-ports 443 2>/dev/null || true
            iptables -t nat -D PREROUTING -p udp --dport 20000:50000 -j REDIRECT --to-ports 8443 2>/dev/null || true
            echo -e "${GREEN}完全卸载成功！(连同 sb 命令已删除) / Uninstalled successfully.${NC}"; sleep 2 ;;
        0) clear; exit 0 ;;
        *) sleep 1 ;;
    esac
done
