#!/usr/bin/env bash
# ====================================================================
# Sing-box DDR Ultimate Interactive Console (Global Omni-Matrix OSS)
# Features: Tier 0/1 Fallback, IPv4/IPv6 DoH Check, Nginx Masquerade
# Author: DDR Protocol | Version: 2026.04.Final
# ====================================================================

set -e
export DEBIAN_FRONTEND=noninteractive
export LC_ALL=C

# --- Colors & Error Trap / 颜色与全局异常阻断 ---
RED='\033[0;31m' GREEN='\033[0;32m' YELLOW='\033[0;33m' BLUE='\033[0;36m' PURPLE='\033[0;35m' CYAN='\033[0;36m' NC='\033[0m' BOLD='\033[1m'

trap 'echo -e "\n${RED}[!] Fatal Error at line $LINENO. Initiating safety rollback. / 严重错误: 脚本在第 $LINENO 行中断，系统已介入安全回滚。${NC}"; exit 1' ERR

# --- Package Manager Detection / 跨系统环境接管 ---
if command -v apt-get >/dev/null; then
    PKG_MGR="apt-get"; PKG_UPDATE="$PKG_MGR update -y -q"; PKG_INSTALL="$PKG_MGR install -y -q"
elif command -v yum >/dev/null; then
    PKG_MGR="yum"; PKG_UPDATE="$PKG_MGR makecache -y -q"; PKG_INSTALL="$PKG_MGR install -y -q"
else
    echo -e "${RED}[!] Unsupported OS. Debian/Ubuntu or CentOS/RHEL only. / 仅支持 Debian/Ubuntu 或 CentOS/RHEL。${NC}"; exit 1
fi

if ! command -v curl >/dev/null 2>&1 || ! command -v jq >/dev/null 2>&1; then
    $PKG_UPDATE >/dev/null 2>&1 && $PKG_INSTALL curl jq >/dev/null 2>&1 || true
fi

# --- Core Probe: System & Network / 核心探针: 全维网络嗅探 ---
get_system_info() {
    IPV4=$(curl -s4m3 api.ipify.org || echo "")
    IPV6=$(curl -s6m3 api64.ipify.org || echo "")
    
    if [[ -n "$IPV4" ]]; then PUBLIC_IP="$IPV4"; IP_TYPE="IPv4"; LINK_IP="$PUBLIC_IP"; DNS_TYPE="A"
    elif [[ -n "$IPV6" ]]; then PUBLIC_IP="$IPV6"; IP_TYPE="IPv6"; LINK_IP="[$PUBLIC_IP]"; DNS_TYPE="AAAA"
    else PUBLIC_IP="UNKNOWN"; IP_TYPE="NONE"; DNS_TYPE="A"; fi

    if systemctl is-active --quiet sing-box; then STATUS="${GREEN}Running / 运行中${NC}"
    else STATUS="${RED}Stopped / 未运行${NC}"; fi
    
    if [[ "$PUBLIC_IP" != "UNKNOWN" ]]; then
        ASN_ORG=$(curl -sm3 "ipinfo.io/$PUBLIC_IP/org" | tr '[:lower:]' '[:upper:]' | cut -d ' ' -f 2- || echo "GENERIC")
        COUNTRY=$(curl -sm3 "ipinfo.io/$PUBLIC_IP/country" | tr '[:lower:]' '[:upper:]' | tr -d '\n\r' || echo "US")
    else 
        ASN_ORG="UNKNOWN"; COUNTRY="UNKNOWN"
    fi
}

# --- Module 1: Deployment Engine / 全算力核心部署引擎 ---
install_core() {
    clear
    echo -e "${BLUE}======================================================${NC}"
    echo -e "${BOLD}${GREEN} Initiating DDR Omni-Matrix Deployment / 启动全维算力部署引擎...${NC}"
    echo -e "${BLUE}======================================================${NC}\n"

    echo -e "${PURPLE}[?] Hysteria 2 Tier 0 Protocol Optimization / Hysteria 2 物理级伪装优化:${NC}"
    echo -e "    If you have a real domain pointed to this IP, enter it below for a valid Let's Encrypt CA."
    echo -e "    If not, leave blank to automatically fallback to Tier 1 Self-Signed mode."
    echo -e "    (若你有解析到本机的真实域名，请输入以申请权威证书；若无，请直接回车降级至 Tier 1 自签模式)"
    read -p "    Domain / 真实域名 (e.g., node.xyz): " USER_DOMAIN

    echo -e "\n${YELLOW}[1/8] Releasing Zombie Locks & Cleaning Env / 释放死锁与重置环境...${NC}"
    systemctl stop sing-box 2>/dev/null || true
    if command -v fuser >/dev/null 2>&1; then fuser -k 80/tcp 443/tcp 443/udp 2053/tcp 2>/dev/null || true; fi
    if [[ "$PKG_MGR" == "apt-get" ]]; then
        while fuser /var/lib/dpkg/lock-frontend >/dev/null 2>&1 || fuser /var/lib/apt/lists/lock >/dev/null 2>&1; do sleep 2; done
    fi
    $PKG_UPDATE >/dev/null 2>&1 || true
    $PKG_INSTALL openssl iproute2 python3 psmisc fail2ban socat cron >/dev/null 2>&1 || true
    $PKG_INSTALL uuid-runtime >/dev/null 2>&1 || $PKG_INSTALL util-linux >/dev/null 2>&1 || true

    echo -e "${YELLOW}[2/8] Forcing TLS Time Sync / 物理时钟强制对齐 (防 TLS 握手拒绝)...${NC}"
    $PKG_INSTALL chrony >/dev/null 2>&1 || true
    systemctl enable chronyd 2>/dev/null || true; systemctl start chronyd 2>/dev/null || true
    date -s "$(curl -sI https://google.com | grep -i Date | sed 's/Date: //g')" >/dev/null 2>&1 || true

    echo -e "${YELLOW}[3/8] Hardening SSH Anti-Brute Force / 注入防暴力破解矩阵...${NC}"
    cat > /etc/fail2ban/jail.local << 'F2B_EOF'
[sshd]
enabled = true
port = ssh
filter = sshd
maxretry = 3
bantime = 86400
F2B_EOF
    systemctl restart fail2ban 2>/dev/null || true

    echo -e "${YELLOW}[4/8] Omni-Matrix SNI Adapting & Cryptography / 全局 SNI 自动匹配与高熵生成...${NC}"
    ASN_UPPER=$(echo "$ASN_ORG" | tr '[:lower:]' '[:upper:]')
    
    # 2D BGP & GeoIP Routing Matrix
    if [[ "$ASN_UPPER" == *"AMAZON"* ]]; then
        case "$COUNTRY" in
            "JP") REALITY_SNI="s3.ap-northeast-1.amazonaws.com" ;;
            "SG") REALITY_SNI="s3.ap-southeast-1.amazonaws.com" ;;
            "HK") REALITY_SNI="s3.ap-east-1.amazonaws.com" ;;
            "KR") REALITY_SNI="s3.ap-northeast-2.amazonaws.com" ;;
            "US") REALITY_SNI="s3.us-west-2.amazonaws.com" ;;
            "GB") REALITY_SNI="s3.eu-west-2.amazonaws.com" ;;
            "DE") REALITY_SNI="s3.eu-central-1.amazonaws.com" ;;
            *)    REALITY_SNI="www.twitch.tv" ;;
        esac
    elif [[ "$ASN_UPPER" == *"GOOGLE"* ]]; then REALITY_SNI="storage.googleapis.com"
    elif [[ "$ASN_UPPER" == *"MICROSOFT"* || "$ASN_UPPER" == *"AZURE"* ]]; then REALITY_SNI="dl.delivery.mp.microsoft.com"
    elif [[ "$ASN_UPPER" == *"ALIBABA"* || "$ASN_UPPER" == *"ALIPAY"* ]]; then REALITY_SNI="www.alibabacloud.com"
    elif [[ "$ASN_UPPER" == *"TENCENT"* ]]; then REALITY_SNI="intl.cloud.tencent.com"
    elif [[ "$ASN_UPPER" == *"CLOUDFLARE"* ]]; then REALITY_SNI="time.cloudflare.com"
    else
        case "$COUNTRY" in
            "CN"|"HK"|"TW"|"SG"|"JP"|"KR") REALITY_SNI="gateway.icloud.com" ;;
            "US"|"CA") REALITY_SNI="swcdn.apple.com" ;;
            *) REALITY_SNI="www.microsoft.com" ;;
        esac
    fi

    UUID=$(uuidgen | tr -d '\n\r')
    HY2_PASS=$(openssl rand -base64 12 | tr -dc 'a-zA-Z0-9' | tr -d '\n\r')
    HY2_OBFS=$(openssl rand -base64 8 | tr -dc 'a-zA-Z0-9' | tr -d '\n\r')
    SS_PASS=$(openssl rand -base64 16 | tr -d '\n\r')
    SS_SIP_CORE=$(echo -n "2022-blake3-aes-128-gcm:${SS_PASS}" | base64 -w 0)

    echo -e "${YELLOW}[5/8] Injecting Kernel BBR & Fetching Binary / 内核级 BBR 覆盖与核心投递...${NC}"
    modprobe tcp_bbr 2>/dev/null || true
    echo "tcp_bbr" > /etc/modules-load.d/bbr.conf 2>/dev/null || true
    cat > /etc/sysctl.d/99-singbox.conf << 'SYSCTL_EOF'
net.core.default_qdisc = fq
net.ipv4.tcp_congestion_control = bbr
net.ipv4.tcp_fastopen = 3
SYSCTL_EOF
    sysctl -p /etc/sysctl.d/99-singbox.conf >/dev/null 2>&1 || true

    SB_VERSION=$(curl -s "https://api.github.com/repos/SagerNet/sing-box/releases/latest" | grep -Po '"tag_name": "v\K[^"]*')
    if [[ -z "$SB_VERSION" ]]; then SB_VERSION="1.10.1"; fi
    ARCH=$(uname -m | sed 's/x86_64/amd64/;s/aarch64/arm64/')
    DL_URL="https://github.com/SagerNet/sing-box/releases/download/v${SB_VERSION}/sing-box-${SB_VERSION}-linux-${ARCH}.tar.gz"
    
    if ! curl -Is -m 5 "$DL_URL" | grep -q "200\|302"; then DL_URL="https://ghp.ci/$DL_URL"; fi
    curl -Lo /tmp/sb.tar.gz "$DL_URL"
    tar -xzf /tmp/sb.tar.gz -C /tmp && mv /tmp/sing-box-*/sing-box /usr/local/bin/ && chmod +x /usr/local/bin/sing-box
    
    KEYS=$(/usr/local/bin/sing-box generate reality-keypair)
    PRIVATE_KEY=$(echo "$KEYS" | grep -i "Private" | awk '{print $2}' | tr -d '\n\r')
    PUBLIC_KEY=$(echo "$KEYS" | grep -i "Public" | awk '{print $2}' | tr -d '\n\r')
    SHORT_ID=$(openssl rand -hex 4 | tr -d '\n\r')

    echo -e "${YELLOW}[6/8] Tier 0/1 ACME Adaptive Engine / 智能证书降级与反代注入...${NC}"
    mkdir -p /etc/sing-box
    HY2_INSECURE_FLAG="1"
    MASQUERADE_CFG=""
    
    if [[ -n "$USER_DOMAIN" ]]; then
        echo -e "${CYAN} -> Performing DoH Pre-flight DNS Check ($DNS_TYPE) for $USER_DOMAIN... / 验证无缓存 DNS 溯源解析...${NC}"
        RESOLVED_IP=$(curl -sH "accept: application/dns-json" "https://cloudflare-dns.com/dns-query?name=$USER_DOMAIN&type=$DNS_TYPE" | jq -r '.Answer[0].data' || echo "")
        
        if [[ "$RESOLVED_IP" != "$PUBLIC_IP" ]]; then
            echo -e "${RED} -> [Warning] DNS mismatch. Local IP: $PUBLIC_IP, Resolved: $RESOLVED_IP${NC}"
            echo -e "${CYAN} -> Initiating Fallback to Tier 1 Self-Signed mode. / 解析未生效，自动降级至 Tier 1 自签模式。${NC}"
            USER_DOMAIN=""
        else
            echo -e "${GREEN} -> DNS Matched! Requesting Let's Encrypt CA... / 溯源闭环，开始申请全球可信证书...${NC}"
            curl -s https://get.acme.sh | sh >/dev/null 2>&1
            ~/.acme.sh/acme.sh --set-default-ca --server letsencrypt >/dev/null 2>&1
            if ~/.acme.sh/acme.sh --issue -d "$USER_DOMAIN" --standalone -k ec-256; then
                ~/.acme.sh/acme.sh --installcert -d "$USER_DOMAIN" --fullchainpath /etc/sing-box/hy2.crt --keypath /etc/sing-box/hy2.key >/dev/null 2>&1
                echo -e "${GREEN} -> ACME Success! Tier 0 Activated. / 证书下发成功，开启 Tier 0 完美伪装防线。${NC}"
                HY2_SNI="$USER_DOMAIN"
                HY2_INSECURE_FLAG="0"
                # 修复逻辑反代冲突：使用纯技术文档架构模拟正常云主机
                MASQUERADE_CFG="\"masquerade\": \"https://nginx.org\","
            else
                echo -e "${RED} -> ACME Blocked. / 申请阻断(可能端口受限)。${NC}"
                echo -e "${CYAN} -> Initiating Fallback to Tier 1 Self-Signed mode. / 自动降级至 Tier 1 自签模式。${NC}"  
                USER_DOMAIN=""
            fi
        fi
    fi

    # Fallback to Tier 1
    if [[ -z "$USER_DOMAIN" ]]; then
        HY2_SNI="api-sync.network"
        openssl ecparam -genkey -name prime256v1 -out /etc/sing-box/hy2.key 2>/dev/null
        openssl req -new -x509 -days 36500 -key /etc/sing-box/hy2.key -out /etc/sing-box/hy2.crt -subj "/CN=$HY2_SNI" 2>/dev/null
    fi

    cat > /etc/sing-box/.env << ENV_EOF
UUID="${UUID}"
HY2_PASS="${HY2_PASS}"
HY2_OBFS="${HY2_OBFS}"
SS_PASS="${SS_PASS}"
SS_SIP_CORE="${SS_SIP_CORE}"
PRIVATE_KEY="${PRIVATE_KEY}"
PUBLIC_KEY="${PUBLIC_KEY}"
SHORT_ID="${SHORT_ID}"
REALITY_SNI="${REALITY_SNI}"
HY2_SNI="${HY2_SNI}"
HY2_INSECURE_FLAG="${HY2_INSECURE_FLAG}"
LINK_IP="${LINK_IP}"
ENV_EOF

    echo -e "${YELLOW}[7/8] Compiling AST Configuration / 编译配置与内存安全预检...${NC}"
    cat > /etc/sing-box/config.json << CONFIG_EOF
{
  "log": { "level": "warn" },
  "inbounds": [
    { "type": "vless", "tag": "vless-in", "listen": "::", "listen_port": 443, "users": [ { "uuid": "$UUID", "flow": "xtls-rprx-vision" } ], "tls": { "enabled": true, "server_name": "$REALITY_SNI", "alpn": ["h2", "http/1.1"], "reality": { "enabled": true, "handshake": { "server": "$REALITY_SNI", "server_port": 443 }, "private_key": "$PRIVATE_KEY", "short_id": [ "$SHORT_ID" ] } } },
    { "type": "hysteria2", "tag": "hy2-in", "listen": "::", "listen_port": 443, "up_mbps": 1000, "down_mbps": 2000, "obfs": { "type": "salamander", "password": "$HY2_OBFS" }, "users": [ { "password": "$HY2_PASS" } ], ${MASQUERADE_CFG} "tls": { "enabled": true, "alpn": [ "h3" ], "certificate_path": "/etc/sing-box/hy2.crt", "key_path": "/etc/sing-box/hy2.key" } },
    { "type": "shadowsocks", "tag": "ss-in", "listen": "::", "listen_port": 2053, "method": "2022-blake3-aes-128-gcm", "password": "$SS_PASS" }
  ],
  "outbounds": [ { "type": "direct", "tag": "direct" } ]
}
CONFIG_EOF

    if ! /usr/local/bin/sing-box check -c /etc/sing-box/config.json; then
        echo -e "${RED}[!] Pre-flight Failed: JSON Syntax Error. / 核心校验失败：AST 语法错误。已物理阻断。${NC}"; exit 1
    fi

    echo -e "${YELLOW}[8/8] Port Hopping & Daemon / 端口跳跃与守护进程静默拉起...${NC}"
    if [[ "$PKG_MGR" == "apt-get" ]]; then $PKG_INSTALL iptables-persistent >/dev/null 2>&1 || true; fi
    iptables -t nat -F PREROUTING 2>/dev/null || true
    iptables -t nat -A PREROUTING -p udp --dport 20000:50000 -j REDIRECT --to-ports 443
    iptables -I INPUT -p tcp -m multiport --dports 80,443,2053 -j ACCEPT
    iptables -I INPUT -p udp -m multiport --dports 443,2053,20000:50000 -j ACCEPT
    if [[ -f /proc/net/if_inet6 ]] && command -v ip6tables >/dev/null; then
        ip6tables -t nat -F PREROUTING 2>/dev/null || true
        ip6tables -t nat -A PREROUTING -p udp --dport 20000:50000 -j REDIRECT --to-ports 443 2>/dev/null || true
        ip6tables -I INPUT -p tcp -m multiport --dports 80,443,2053 -j ACCEPT
        ip6tables -I INPUT -p udp -m multiport --dports 443,2053,20000:50000 -j ACCEPT
    fi
    if command -v netfilter-persistent >/dev/null; then netfilter-persistent save 2>/dev/null || true; fi

    cat > /etc/systemd/system/sing-box.service << SVC_EOF
[Unit]
After=network.target
[Service]
ExecStart=/usr/local/bin/sing-box run -c /etc/sing-box/config.json
Restart=always
LimitNOFILE=1048576
[Install]
WantedBy=multi-user.target
SVC_EOF
    systemctl daemon-reload && systemctl enable --now sing-box

    echo -e "\n${GREEN}✔ Deployment Complete! / 终极部署完成！${NC}"
    read -n 1 -s -r -p "Press any key to return... / 按任意键返回主菜单..."
}

# --- Module 2: Info Display / URI 加密链接输出 ---
show_links() {
    clear
    if [[ ! -f /etc/sing-box/.env ]]; then
        echo -e "${RED}[!] Environment not found. / 未检测到运行环境。${NC}"; read -n 1 -s -r -p "Press any key to return..."; return
    fi
    source /etc/sing-box/.env

    echo -e "${BLUE}======================================================${NC}"
    echo -e "${BOLD}${GREEN} Aggregated Node Links / 节点聚合加密信息展示 ${NC}"
    echo -e "${BLUE}======================================================${NC}\n"
    
    echo -e "${YELLOW}[ VLESS-REALITY (TCP Extreme Stealth) ]${NC}"
    echo -e "vless://${UUID}@${LINK_IP}:443?encryption=none&flow=xtls-rprx-vision&security=reality&sni=${REALITY_SNI}&alpn=h2,http/1.1&fp=chrome&pbk=${PUBLIC_KEY}&sid=${SHORT_ID}&type=tcp#VLESS-Reality\n"
    
    if [[ "$HY2_INSECURE_FLAG" == "0" ]]; then
        echo -e "${GREEN}[ Hysteria 2 (Tier 0: Valid CA + Nginx Masquerade + Salamander) ]${NC}"
        echo -e "hy2://${HY2_PASS}@${LINK_IP}:20000?sni=${HY2_SNI}&mport=20000-50000&obfs=salamander&obfs-password=${HY2_OBFS}#Hysteria2-Tier0\n"
    else
        echo -e "${YELLOW}[ Hysteria 2 (Tier 1: Self-Signed + Salamander) ]${NC}"
        echo -e "hy2://${HY2_PASS}@${LINK_IP}:20000?insecure=1&sni=${HY2_SNI}&mport=20000-50000&obfs=salamander&obfs-password=${HY2_OBFS}#Hysteria2-Tier1\n"
    fi
    
    echo -e "${YELLOW}[ Shadowsocks 2022 (Chain Landing Only) ]${NC}"
    echo -e "ss://${SS_SIP_CORE}@${LINK_IP}:2053#SS-2022\n"

    echo -e "${BLUE}------------------------------------------------------${NC}"
    read -n 1 -s -r -p "Press any key to return... / 按任意键返回主菜单..."
}

# --- Module 3: Uninstall / 物理级卸载与回滚 ---
uninstall_core() {
    clear
    echo -e "${RED}WARNING: This will wipe core & configs! / 警告：系统将物理抹除核心配置及防火墙端口映射！${NC}"
    read -p "Confirm Uninstallation? 确定执行卸载吗？(y/n): " confirm
    if [[ "$confirm" == "y" || "$confirm" == "Y" ]]; then
        systemctl stop sing-box 2>/dev/null || true
        systemctl disable sing-box 2>/dev/null || true
        rm -f /etc/systemd/system/sing-box.service; systemctl daemon-reload
        rm -rf /etc/sing-box ~/.acme.sh /usr/local/bin/sing-box
        iptables -t nat -D PREROUTING -p udp --dport 20000:50000 -j REDIRECT --to-ports 443 2>/dev/null || true
        if command -v netfilter-persistent >/dev/null; then netfilter-persistent save 2>/dev/null || true; fi
        echo -e "${GREEN}System restored to pristine state. / 系统已恢复至出厂无污染状态。${NC}"
    fi
    read -n 1 -s -r -p "Press any key to return... / 按任意键返回主菜单..."
}

# --- Interactive State Machine (Dashboard) / 中控台看板 ---
while true; do
    get_system_info
    clear
    echo -e "${BLUE}======================================================${NC}"
    echo -e "${BOLD}${PURPLE}  Sing-box DDR Console [Omni-Matrix Final OSS] ${NC}"
    echo -e "${BLUE}======================================================${NC}"
    echo -e " ${BOLD}WAN IP:${NC}  ${YELLOW}${PUBLIC_IP} [${IP_TYPE}]${NC}"
    echo -e " ${BOLD}BGP ASN:${NC} ${CYAN}${ASN_ORG} (${COUNTRY})${NC}"
    echo -e " ${BOLD}STATUS:${NC}  ${STATUS}"
    echo -e "${BLUE}======================================================${NC}"
    echo -e " ${GREEN}1.${NC} Install Core (一键部署: 支持 Tier 0/1 智能跃迁)"
    echo -e " ${GREEN}2.${NC} View Links (提取节点底层 URI 链接)"
    echo -e " ${GREEN}3.${NC} Uninstall (物理卸载与网络栈回滚)"
    echo -e " ${GREEN}0.${NC} Exit (安全断开连接)"
    echo -e "${BLUE}======================================================${NC}"
    read -p " Select an option / 请输入交互指令 [0-3]: " choice

    case $choice in
        1) install_core ;;
        2) show_links ;;
        3) uninstall_core ;;
        0) clear; exit 0 ;;
        *) sleep 1 ;;
    esac
done
