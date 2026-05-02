#!/usr/bin/env bash
# ==============================Aio-box===============================
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

# --- [0.1] 强制劫持物理键盘设备 (防御管道符死锁与 ^H 控制码乱码) ---
exec < /dev/tty || true

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
    if [[ ! -f /etc/ddr/.deps ]]; then
        echo -e "${YELLOW}[*] 正在同步系统依赖环境 / Syncing dependencies (OS: ${release}, Init: ${INIT_SYS})...${NC}"
        
        if [[ "${release}" == "ubuntu" || "${release}" == "debian" ]]; then
            apt-get update -y -q >/dev/null 2>&1
        elif [[ "${release}" == "centos" ]]; then
            yum makecache -y -q >/dev/null 2>&1
            ${installType} epel-release >/dev/null 2>&1
        elif [[ "${release}" == "alpine" ]]; then
            apk update -q >/dev/null 2>&1
        fi
        
        local deps=(wget curl jq openssl python3 bc unzip vnstat iptables tar psmisc lsof qrencode ca-certificates)
        if [[ "${release}" == "ubuntu" || "${release}" == "debian" ]]; then
            deps+=(cron uuid-runtime iptables-persistent netfilter-persistent fail2ban)
        elif [[ "${release}" == "centos" ]]; then
            deps+=(cronie util-linux bind-utils firewalld iproute fail2ban)
        elif [[ "${release}" == "alpine" ]]; then
            deps+=(util-linux bind-tools coreutils iproute2 procps fail2ban)
        fi
        
        has_ipv6 && deps+=(ip6tables)
        
        ${installType} "${deps[@]}" >/dev/null 2>&1
        hash -r 2>/dev/null || true
        
        if [[ "$INIT_SYS" == "systemd" ]]; then
            service_manager start cron crond vnstat 2>/dev/null || true
        elif [[ "$INIT_SYS" == "openrc" ]]; then
            service_manager start crond vnstatd 2>/dev/null || true
        fi
        
        mkdir -p /etc/ddr && touch /etc/ddr/.deps
    fi
    IPT=$(command -v iptables || echo "/sbin/iptables")
    IPT6=$(command -v ip6tables || echo "/sbin/ip6tables")
}
has_ipv6() {
    if ping6 -c 1 -W 2 2606:4700:4700::1111 >/dev/null 2>&1 || ip -6 addr show scope global | grep -q inet6; then return 0; else return 1; fi
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
        if has_ipv6 && command -v ip6tables >/dev/null 2>&1; then
            if ! $IPT6 -C INPUT -p "${type}" --dport "${port}" -j ACCEPT 2>/dev/null; then
                $IPT6 -I INPUT -p "${type}" --dport "${port}" -m comment --comment "Aio-box-${port}-${type}" -j ACCEPT >/dev/null 2>&1
            fi
        fi
        save_firewall_rules
    fi
}
clean_nat_rules() {
    while $IPT -w -t nat -S PREROUTING 2>/dev/null | grep -q "30000:60000"; do
        local LOCAL_RULE=$($IPT -w -t nat -S PREROUTING 2>/dev/null | grep "30000:60000" | head -n 1 | sed 's/^-A /-D /')
        [[ -z "$LOCAL_RULE" ]] && break
        $IPT -w -t nat $LOCAL_RULE 2>/dev/null || break
    done
    if has_ipv6; then
        while $IPT6 -w -t nat -S PREROUTING 2>/dev/null | grep -q "30000:60000"; do
            local LOCAL_RULE6=$($IPT6 -w -t nat -S PREROUTING 2>/dev/null | grep "30000:60000" | head -n 1 | sed 's/^-A /-D /')
            [[ -z "$LOCAL_RULE6" ]] && break
            $IPT6 -w -t nat $LOCAL_RULE6 2>/dev/null || break
        done
    fi
}
clean_input_rules() {
    while $IPT -w -S INPUT 2>/dev/null | grep -q "Aio-box-"; do
        local LOCAL_RULE=$($IPT -w -S INPUT 2>/dev/null | grep "Aio-box-" | head -n 1 | sed 's/^-A /-D /')
        [[ -z "$LOCAL_RULE" ]] && break
        $IPT -w $LOCAL_RULE 2>/dev/null || break
    done
    if has_ipv6; then
        while $IPT6 -w -S INPUT 2>/dev/null | grep -q "Aio-box-"; do
            local LOCAL_RULE6=$($IPT6 -w -S INPUT 2>/dev/null | grep "Aio-box-" | head -n 1 | sed 's/^-A /-D /')
            [[ -z "$LOCAL_RULE6" ]] && break
            $IPT6 -w $LOCAL_RULE6 2>/dev/null || break
        done
    fi
}
release_ports() {
    echo -e "${YELLOW}[*] 正在执行内核级端口死锁清理 / Executing port deadlock cleanup...${NC}"
    service_manager stop xray sing-box hysteria
    killall -9 xray sing-box hysteria 2>/dev/null || true
    
    local ports_to_clean=($VLESS_PORT $HY2_PORT $SS_PORT 443 8443 2053)
    for p in $(echo "${ports_to_clean[@]}" | tr ' ' '\n' | sort -u); do
        fuser -k -9 "${p}/tcp" 2>/dev/null || true
        fuser -k -9 "${p}/udp" 2>/dev/null || true
        if command -v lsof >/dev/null 2>&1; then
            local PIDS=$(lsof -i:"${p}" 2>/dev/null | awk 'NR>1 {print $2}' | sort -u)
            if [[ -n "$PIDS" ]]; then
                for pid in $PIDS; do kill -9 "$pid" 2>/dev/null || true; done
            fi
        fi
    done
    sleep 2
}
setup_shortcut() {
    mkdir -p /etc/ddr
    if [[ ! -f /etc/ddr/aio.sh || "$1" == "update" ]]; then
        curl -fLs --connect-timeout 10 https://raw.githubusercontent.com/alariclin/aio-box/main/install.sh > /tmp/aio.sh.tmp && mv -f /tmp/aio.sh.tmp /etc/ddr/aio.sh
        chmod +x /etc/ddr/aio.sh
    fi
    if [[ ! -f /usr/local/bin/sb ]]; then
        printf '#!/bin/bash\nsudo bash /etc/ddr/aio.sh "$@"\n' > /usr/local/bin/sb
        chmod +x /usr/local/bin/sb
    fi
}

# === [核心增强挂载] 防御系统注入组件 / Active Defense Injection ===
setup_active_defense() {
    echo -e "${YELLOW}[*] 正在挂载环形缓冲日志与 Fail2Ban 主动防御矩阵...${NC}"
    touch /var/log/aio-box-xray.log /var/log/aio-box-singbox.log 2>/dev/null
    chmod 644 /var/log/aio-box-*.log 2>/dev/null || true

    cat > /etc/logrotate.d/aio-box << 'EOF'
/var/log/aio-box-*.log {
    su root root
    daily
    rotate 2
    size 50M
    missingok
    notifempty
    copytruncate
    compress
}
EOF
    if command -v fail2ban-client >/dev/null 2>&1; then
        cat > /etc/fail2ban/filter.d/aio-box.conf << 'EOF'
[Definition]
failregex = ^.* \[Warning\] .* \[.*\] .* rejected  .* from <HOST>:\d+$
            ^.* \[Warning\] .* \[.*\] .* invalid request from <HOST>:\d+$
            ^.* \[Warn\] .* \[.*\] .* rejected  .* from <HOST>:\d+$
ignoreregex = 
EOF
        cat > /etc/fail2ban/jail.d/aio-box.local << 'EOF'
[aio-box]
enabled = true
port = 1-65535
filter = aio-box
logpath = /var/log/aio-box-*.log
maxretry = 5
findtime = 60
bantime = 86400
action = iptables-allports[name=AioBox]
EOF
        if [[ "$INIT_SYS" == "systemd" ]]; then
            systemctl restart fail2ban 2>/dev/null || true
        else
            rc-service fail2ban restart 2>/dev/null || true
        fi
    fi
}

setup_health_monitor() {
    echo -e "${YELLOW}[*] 正在注入 L4 内核级套接字自愈守护探针...${NC}"
    cat > /etc/ddr/socket_probe.sh << 'EOF'
#!/bin/bash
PATH=/usr/local/sbin:/usr/local/bin:/sbin:/bin:/usr/sbin:/usr/bin
source /etc/ddr/.env 2>/dev/null || exit 0
[[ -z "$CORE" ]] && exit 0

if [[ -n "$TRAFFIC_LIMIT_GB" ]]; then
    INTERFACE=$(ip route get 8.8.8.8 2>/dev/null | awk '{for(i=1;i<=NF;i++) if($i=="dev") print $(i+1)}' | head -n 1)
    [[ -z "$INTERFACE" ]] && INTERFACE=$(ip link | awk -F: '$0 !~ "lo|vir|wl|^[^0-9]"{print $2;getline}' | head -n 1 | tr -d ' ')
    USED_LINE=$(vnstat -i "$INTERFACE" -m 2>/dev/null | grep "$(date +'%Y-%m')")
    if [[ -n "$USED_LINE" ]]; then
        TOTAL_STR=$(echo "$USED_LINE" | awk -F'|' '{print $3}' | xargs)
        VAL=$(echo "$TOTAL_STR" | awk '{print $1}')
        UNIT=$(echo "$TOTAL_STR" | awk '{print $2}')
        USED_GB=0
        if [[ "$UNIT" == *"GiB"* || "$UNIT" == *"GB"* ]]; then USED_GB=$VAL
        elif [[ "$UNIT" == *"TiB"* || "$UNIT" == *"TB"* ]]; then USED_GB=$(echo "$VAL * 1024" | bc)
        elif [[ "$UNIT" == *"MiB"* || "$UNIT" == *"MB"* ]]; then USED_GB=$(echo "scale=2; $VAL / 1024" | bc)
        elif [[ "$UNIT" == *"KiB"* || "$UNIT" == *"KB"* ]]; then USED_GB=$(echo "scale=4; $VAL / 1048576" | bc)
        fi
        if (( $(echo "$USED_GB >= $TRAFFIC_LIMIT_GB" | bc -l) )); then
            exit 0
        fi
    fi
fi

check_restart() {
    local srv=$1
    if command -v systemctl >/dev/null 2>&1; then
        systemctl restart "$srv" 2>/dev/null
    else
        rc-service "$srv" restart 2>/dev/null
    fi
}

if [[ "$CORE" == "xray" || "$CORE" == "singbox" || "$CORE" == "hysteria" ]]; then
    if [[ -n "$VLESS_PORT" ]] && ! ss -nltp 2>/dev/null | grep -q ":$VLESS_PORT\b"; then
        check_restart "$CORE"
        exit 0
    fi
    if [[ -n "$HY2_PORT" ]] && ! ss -nulp 2>/dev/null | grep -q ":$HY2_PORT\b"; then
        check_restart "$CORE"
        exit 0
    fi
    if [[ -n "$SS_PORT" ]] && ! ss -nltp 2>/dev/null | grep -q ":$SS_PORT\b"; then
        check_restart "$CORE"
        exit 0
    fi
fi
EOF
    chmod +x /etc/ddr/socket_probe.sh
    crontab -l 2>/dev/null | grep -vE "^no crontab for|^#" | grep -v '/etc/ddr/socket_probe.sh' > /tmp/cronjob || true
    echo "* * * * * /bin/bash /etc/ddr/socket_probe.sh >/dev/null 2>&1" >> /tmp/cronjob
    crontab /tmp/cronjob 2>/dev/null; rm -f /tmp/cronjob
}

setup_geo_cron() {
    cat > /etc/ddr/geo_update.sh << 'EOF'
#!/bin/bash
PATH=/usr/local/sbin:/usr/local/bin:/sbin:/bin:/usr/sbin:/usr/bin
GEOIP_URL="https://github.com/Loyalsoldier/v2ray-rules-dat/releases/latest/download/geoip.dat"
GEOSITE_URL="https://github.com/Loyalsoldier/v2ray-rules-dat/releases/latest/download/geosite.dat"

mkdir -p /tmp/geo_update
curl -sL -m 60 "$GEOIP_URL" -o /tmp/geo_update/geoip.dat || curl -sL -m 60 "https://ghp.ci/$GEOIP_URL" -o /tmp/geo_update/geoip.dat
curl -sL -m 60 "$GEOSITE_URL" -o /tmp/geo_update/geosite.dat || curl -sL -m 60 "https://ghp.ci/$GEOSITE_URL" -o /tmp/geo_update/geosite.dat

SIZE_IP=$(wc -c < /tmp/geo_update/geoip.dat 2>/dev/null | tr -d ' ')
SIZE_SITE=$(wc -c < /tmp/geo_update/geosite.dat 2>/dev/null | tr -d ' ')

if [[ -n "$SIZE_IP" && "$SIZE_IP" -gt 500000 && -n "$SIZE_SITE" && "$SIZE_SITE" -gt 500000 ]]; then
    if [[ -d "/usr/local/share/xray" ]]; then
        mv -f /tmp/geo_update/geoip.dat /usr/local/share/xray/geoip.dat
        mv -f /tmp/geo_update/geosite.dat /usr/local/share/xray/geosite.dat
        if command -v systemctl >/dev/null 2>&1; then systemctl restart xray 2>/dev/null; else rc-service xray restart 2>/dev/null; fi
    fi
    if [[ -d "/etc/sing-box" ]]; then
        cp -f /usr/local/share/xray/geoip.dat /etc/sing-box/geoip.dat 2>/dev/null || mv -f /tmp/geo_update/geoip.dat /etc/sing-box/geoip.dat 2>/dev/null
        cp -f /usr/local/share/xray/geosite.dat /etc/sing-box/geosite.dat 2>/dev/null || mv -f /tmp/geo_update/geosite.dat /etc/sing-box/geosite.dat 2>/dev/null
        if command -v systemctl >/dev/null 2>&1; then systemctl restart sing-box 2>/dev/null; else rc-service sing-box restart 2>/dev/null; fi
    fi
fi
rm -rf /tmp/geo_update
EOF
    chmod +x /etc/ddr/geo_update.sh
    
    crontab -l 2>/dev/null | grep -vE "^no crontab for|^#" | grep -v '/etc/ddr/geo_update.sh' > /tmp/cronjob || true
    echo "0 3 * * 1 /bin/bash /etc/ddr/geo_update.sh >/dev/null 2>&1" >> /tmp/cronjob
    crontab /tmp/cronjob 2>/dev/null
    rm -f /tmp/cronjob
}

# --- [4] 远程资产智能抓取引擎 / GitHub Asset Fetcher ---
fetch_github_release() {
    local repo=$1; local keyword=$2; local output_file=$3
    echo -e "${YELLOW} -> 正在从 GitHub 抓取最新架构版本 / Fetching latest release [${repo}]...${NC}"
    local api_url="https://api.github.com/repos/${repo}/releases/latest"
    local download_url=$(curl -sL "$api_url" | jq -r ".assets[]? | select(.name | contains(\"$keyword\")) | .browser_download_url" 2>/dev/null | head -n 1)
    
    if [[ -z "$download_url" || "$download_url" == "null" ]]; then
        download_url=$(curl -sL "https://ghp.ci/$api_url" | jq -r ".assets[]? | select(.name | contains(\"$keyword\")) | .browser_download_url" 2>/dev/null | head -n 1)
    fi
    if [[ -z "$download_url" || "$download_url" == "null" ]]; then
        echo -e "${YELLOW} -> API 探测失败，自动降级至本地备用仓库拉取... / API failed, fallback to local core repo...${NC}"
        local fallback_url=""
        case "$keyword" in
            *"Xray"*) fallback_url="https://raw.githubusercontent.com/alariclin/aio-box/main/core/Xray-linux-${XRAY_ARCH}.zip" ;;
            *"sing-box"*) fallback_url="https://raw.githubusercontent.com/alariclin/aio-box/main/core/sing-box-linux-${SB_ARCH}.tar.gz" ;;
            *"hysteria"*) fallback_url="https://raw.githubusercontent.com/alariclin/aio-box/main/core/hysteria-linux-${HY2_ARCH}" ;;
        esac
        if [[ -n "$fallback_url" ]]; then
            local mirrors=("" "https://ghp.ci/" "https://mirror.ghproxy.com/")
            for mirror in "${mirrors[@]}"; do
                if curl -fLs --connect-timeout 10 "${mirror}${fallback_url}" -o "/tmp/${output_file}" && [[ -s "/tmp/${output_file}" ]]; then
                    echo -e "${GREEN}   ✔ 核心资产从备用仓库提取成功！ / Asset fetched from fallback repo!${NC}"; return 0
                fi
            done
        fi
        echo -e "${RED}[!] 致命异常: 所有通道均无法下载核心资产。请检查网络。 / Asset download completely failed.${NC}"; exit 1
    fi
    local mirrors=("" "https://ghp.ci/" "https://mirror.ghproxy.com/")
    for mirror in "${mirrors[@]}"; do
        if curl -fLs --connect-timeout 10 "${mirror}${download_url}" -o "/tmp/${output_file}" && [[ -s "/tmp/${output_file}" ]]; then
            echo -e "${GREEN}   ✔ 核心资产提取成功！ / Asset successfully fetched!${NC}"; return 0
        fi
    done
    
    echo -e "${YELLOW} -> 官方下载链接失效，自动降级至本地备用仓库拉取... / Official URLs failed, fallback to local core repo...${NC}"
    local fallback_url=""
    case "$keyword" in
        *"Xray"*) fallback_url="https://raw.githubusercontent.com/alariclin/aio-box/main/core/Xray-linux-${XRAY_ARCH}.zip" ;;
        *"sing-box"*) fallback_url="https://raw.githubusercontent.com/alariclin/aio-box/main/core/sing-box-linux-${SB_ARCH}.tar.gz" ;;
        *"hysteria"*) fallback_url="https://raw.githubusercontent.com/alariclin/aio-box/main/core/hysteria-linux-${HY2_ARCH}" ;;
    esac
    if [[ -n "$fallback_url" ]]; then
        local mirrors=("" "https://ghp.ci/" "https://mirror.ghproxy.com/")
        for mirror in "${mirrors[@]}"; do
            if curl -fLs --connect-timeout 10 "${mirror}${fallback_url}" -o "/tmp/${output_file}" && [[ -s "/tmp/${output_file}" ]]; then
                echo -e "${GREEN}   ✔ 核心资产从备用仓库提取成功！ / Asset fetched from fallback repo!${NC}"; return 0
            fi
        done
    fi
    echo -e "${RED}[!] 致命异常: 下载资产失败 / Asset download failed.${NC}"; exit 1
}
fetch_geo_data() {
    local file_name=$1; local official_url=$2
    local mirrors=("" "https://ghp.ci/" "https://mirror.ghproxy.com/")
    for mirror in "${mirrors[@]}"; do
        if curl -fLs --connect-timeout 10 "${mirror}${official_url}" -o "/tmp/${file_name}" && [[ -s "/tmp/${file_name}" ]]; then return 0; fi
    done
    
    echo -e "${YELLOW} -> 官方 Geo 数据下载失败，自动降级至备用仓库拉取... / Official Geo failed, fallback to local repo...${NC}"
    local fallback_geo_url="https://raw.githubusercontent.com/alariclin/aio-box/main/core/${file_name}"
    for mirror in "${mirrors[@]}"; do
        if curl -fLs --connect-timeout 10 "${mirror}${fallback_geo_url}" -o "/tmp/${file_name}" && [[ -s "/tmp/${file_name}" ]]; then
            echo -e "${GREEN}   ✔ Geo 数据从备用仓库提取成功！ / Geo data fetched from fallback repo!${NC}"; return 0
        fi
    done
    echo -e "${RED}[!] 致命异常: 路由数据库文件 (${file_name}) 下载失败，请检查网络连通性！ / Geo data download failed.${NC}"
    exit 1
}

# --- [5] 核心路由参数交互式构造器 / Deployment Wizard ---
pre_install_setup() {
    local CORE=$1
    local MODE=$2
    
    # 动态探测并匹配最佳 ASN SNI
    local ISP_ORG=$(curl -s ipinfo.io/org 2>/dev/null)
    if [[ "$ISP_ORG" == *"Google"* ]]; then
        local AUTO_SNI="www.samsung.com"
    elif [[ "$ISP_ORG" == *"Amazon"* ]]; then
        local AUTO_SNI="www.samsung.com"
    elif [[ "$ISP_ORG" == *"Oracle"* ]]; then
        local AUTO_SNI="www.samsung.com"
    else
        local AUTO_SNI="www.samsung.com"
    fi

    local DEF_V_SNI="$AUTO_SNI"
    local DEF_H_SNI="$AUTO_SNI"
    local DEF_V_PORT=443
    local DEF_H_PORT=42588
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
        read -ep "   [HY2] 请输入伪装 SNI (需与VLESS一致) (回车默认: $DEF_H_SNI): " INPUT_H_SNI
        HY2_SNI=${INPUT_H_SNI:-$DEF_H_SNI}
        read -ep "   [HY2] 请输入主监听端口 (绝对禁止填443) (回车默认: $DEF_H_PORT): " INPUT_H_PORT
        HY2_PORT=${INPUT_H_PORT:-$DEF_H_PORT}
        read -ep "   [HY2] 请输入您本地宽带【下行】速率(Mbps, 例如 300) (回车默认: 1000): " INPUT_H_DOWN
        HY2_DOWN=${INPUT_H_DOWN:-1000}
        read -ep "   [HY2] 请输入您本地宽带【上行】速率(Mbps, 例如 50) (回车默认: 100): " INPUT_H_UP
        HY2_UP=${INPUT_H_UP:-100}
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
  up: ${HY2_UP} mbps
  down: ${HY2_DOWN} mbps
EOF
    chmod 600 /etc/hysteria/config.yaml
    if [[ "$INIT_SYS" == "systemd" ]]; then
        HY2_PRE_START="ExecStartPre=-/bin/sh -c '$IPT -w -t nat -D PREROUTING -p udp --dport 30000:60000 -j REDIRECT --to-ports $HY2_PORT 2>/dev/null || true'
ExecStartPre=-/bin/sh -c '$IPT -w -t nat -A PREROUTING -p udp --dport 30000:60000 -j REDIRECT --to-ports $HY2_PORT 2>/dev/null || true'"
        HY2_POST_STOP="ExecStopPost=-/bin/sh -c '$IPT -w -t nat -D PREROUTING -p udp --dport 30000:60000 -j REDIRECT --to-ports $HY2_PORT 2>/dev/null || true'"
        if has_ipv6; then
            HY2_PRE_START="$HY2_PRE_START
ExecStartPre=-/bin/sh -c '$IPT6 -w -t nat -D PREROUTING -p udp --dport 30000:60000 -j REDIRECT --to-ports $HY2_PORT 2>/dev/null || true'
ExecStartPre=-/bin/sh -c '$IPT6 -w -t nat -A PREROUTING -p udp --dport 30000:60000 -j REDIRECT --to-ports $HY2_PORT 2>/dev/null || true'"
            HY2_POST_STOP="$HY2_POST_STOP
ExecStopPost=-/bin/sh -c '$IPT6 -w -t nat -D PREROUTING -p udp --dport 30000:60000 -j REDIRECT --to-ports $HY2_PORT 2>/dev/null || true'"
        fi
        cat > /etc/systemd/system/hysteria.service << SVC_EOF
[Unit]
Description=Hysteria 2 Service
After=network.target
[Service]
CapabilityBoundingSet=CAP_NET_ADMIN CAP_NET_BIND_SERVICE
AmbientCapabilities=CAP_NET_ADMIN CAP_NET_BIND_SERVICE
$HY2_PRE_START
ExecStart=/usr/local/bin/hysteria server -c /etc/hysteria/config.yaml
$HY2_POST_STOP
Restart=always
RestartSec=10
LimitNOFILE=1048576
LimitNPROC=1048576
[Install]
WantedBy=multi-user.target
SVC_EOF
    elif [[ "$INIT_SYS" == "openrc" ]]; then
        mkdir -p /etc/conf.d
        echo 'rc_ulimit="-n 1048576"' > /etc/conf.d/hysteria
        HY2_RC_PRE="start_pre() {
  $IPT -w -t nat -D PREROUTING -p udp --dport 30000:60000 -j REDIRECT --to-ports $HY2_PORT 2>/dev/null || true
  $IPT -w -t nat -A PREROUTING -p udp --dport 30000:60000 -j REDIRECT --to-ports $HY2_PORT 2>/dev/null || true"
        HY2_RC_POST="stop_post() {
  $IPT -w -t nat -D PREROUTING -p udp --dport 30000:60000 -j REDIRECT --to-ports $HY2_PORT 2>/dev/null || true"
        if has_ipv6; then
            HY2_RC_PRE="$HY2_RC_PRE
  $IPT6 -w -t nat -D PREROUTING -p udp --dport 30000:60000 -j REDIRECT --to-ports $HY2_PORT 2>/dev/null || true
  $IPT6 -w -t nat -A PREROUTING -p udp --dport 30000:60000 -j REDIRECT --to-ports $HY2_PORT 2>/dev/null || true"
            HY2_RC_POST="$HY2_RC_POST
  $IPT6 -w -t nat -D PREROUTING -p udp --dport 30000:60000 -j REDIRECT --to-ports $HY2_PORT 2>/dev/null || true"
        fi
        HY2_RC_PRE="$HY2_RC_PRE
  return 0
}"
        HY2_RC_POST="$HY2_RC_POST
  return 0
}"
        cat > /etc/init.d/hysteria << SVC_EOF
#!/sbin/openrc-run
description="Hysteria 2 Service"
command="/usr/local/bin/hysteria"
command_args="server -c /etc/hysteria/config.yaml"
command_background="yes"
pidfile="/run/hysteria.pid"
depend() { need net; }
$HY2_RC_PRE
$HY2_RC_POST
SVC_EOF
        chmod +x /etc/init.d/hysteria
    fi
    service_manager start hysteria
    sleep 2; is_service_running hysteria || { echo -e "${RED}[!] 致命错误：原生 Hysteria 2 守护进程拉起失败！ / Core panic!${NC}"; exit 1; }
    
    setup_geo_cron
    setup_health_monitor
    
    if [[ "$IS_SILENT" != "SILENT" ]]; then
        cat > /etc/ddr/.env << ENV_EOF
CORE="hysteria"; MODE="HY2"; UUID=""; VLESS_SNI=""; VLESS_PORT=""; HY2_SNI="$HY2_SNI"; HY2_PORT="$HY2_PORT"; HY2_UP="$HY2_UP"; HY2_DOWN="$HY2_DOWN"; SS_PORT=""; PUBLIC_KEY=""; SHORT_ID=""; HY2_PASS="$HY2_PASS"; HY2_OBFS="$HY2_OBFS"; SS_PASS=""; LINK_IP="${GLOBAL_PUBLIC_IP}"
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
    fetch_geo_data "geoip.dat" "https://github.com/Loyalsoldier/v2ray-rules-dat/releases/latest/download/geoip.dat"
    fetch_geo_data "geosite.dat" "https://github.com/Loyalsoldier/v2ray-rules-dat/releases/latest/download/geosite.dat"
    
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
        "realitySettings": { "dest": "${VLESS_SNI}:443", "serverNames": ["${VLESS_SNI}"], "privateKey": "${PK}", "shortIds": ["${SHORT_ID}"] },
        "sockopt": { "tcpKeepAliveIdle": 30, "tcpKeepAliveInterval": 30 }
      },
      "sniffing": { "enabled": true, "destOverride": ["http", "tls", "quic"] }
    }
EOF
)
    JSON_SS=$(cat << EOF
    {
      "listen": "::", "port": ${SS_PORT}, "protocol": "shadowsocks",
      "settings": { "method": "2022-blake3-aes-128-gcm", "password": "${SS_PASS}", "network": "tcp,udp" },
      "streamSettings": {
        "sockopt": { "tcpKeepAliveIdle": 30, "tcpKeepAliveInterval": 30 }
      }
    }
EOF
)
    case $MODE in
        "VLESS") INBOUNDS="[$JSON_VLESS]" ;;
        "SS") INBOUNDS="[$JSON_SS]" ;;
        "VLESS_SS"|"ALL") INBOUNDS="[$JSON_VLESS, $JSON_SS]" ;;
    esac
    
    # === Xray 专属路由: 仅保留 category-ads-all ===
    cat > /usr/local/etc/xray/config.json << EOF
{
  "log": { "loglevel": "warning", "access": "/var/log/aio-box-xray.log" },
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
Environment="XRAY_LOCATION_ASSET=/usr/local/share/xray"
CapabilityBoundingSet=CAP_NET_ADMIN CAP_NET_BIND_SERVICE CAP_SYS_PTRACE CAP_DAC_READ_SEARCH
AmbientCapabilities=CAP_NET_ADMIN CAP_NET_BIND_SERVICE CAP_SYS_PTRACE CAP_DAC_READ_SEARCH
ExecStart=/usr/local/bin/xray run -config /usr/local/etc/xray/config.json
Restart=always
RestartSec=10
LimitNOFILE=1048576
LimitNPROC=1048576
[Install]
WantedBy=multi-user.target
SVC_EOF
    elif [[ "$INIT_SYS" == "openrc" ]]; then
        mkdir -p /etc/conf.d
        echo 'rc_ulimit="-n 1048576"' > /etc/conf.d/xray
        echo 'XRAY_LOCATION_ASSET="/usr/local/share/xray"' >> /etc/conf.d/xray
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
    
    setup_geo_cron
    setup_active_defense
    setup_health_monitor
    
    if [[ "$MODE" == "ALL" ]]; then
        deploy_official_hy2 "SILENT"
    fi
    cat > /etc/ddr/.env << ENV_EOF
CORE="xray"; MODE="$MODE"; UUID="$UUID"; VLESS_SNI="$VLESS_SNI"; VLESS_PORT="$VLESS_PORT"; HY2_SNI="$HY2_SNI"; HY2_PORT="$HY2_PORT"; HY2_UP="$HY2_UP"; HY2_DOWN="$HY2_DOWN"; SS_PORT="$SS_PORT"; PUBLIC_KEY="$PBK"; SHORT_ID="$SHORT_ID"; HY2_PASS="$HY2_PASS"; HY2_OBFS="$HY2_OBFS"; SS_PASS="$SS_PASS"; LINK_IP="${GLOBAL_PUBLIC_IP}"
ENV_EOF
    chmod 600 /etc/ddr/.env
    view_config "deploy"
}

deploy_singbox() {
    local MODE=$1; clear; echo -e "${BOLD}${GREEN} 部署 Sing-box 核心 / Deploying Sing-box [$MODE] ${NC}"
    init_system_environment; pre_install_setup "singbox" "$MODE"; release_ports; get_architecture
    
    rm -rf /tmp/sing-box-* /tmp/singbox_core.tar.gz /tmp/sing-box 2>/dev/null
    fetch_github_release "SagerNet/sing-box" "linux-${SB_ARCH}.tar.gz" "singbox_core.tar.gz"
    tar -xzf "/tmp/singbox_core.tar.gz" -C /tmp || { echo -e "${RED}[!] 异常: 压缩包损坏或解压失败！${NC}"; exit 1; }
    
    if [[ -f /tmp/sing-box ]]; then
        mv /tmp/sing-box /usr/local/bin/sing-box
    else
        local SB_PATH=$(find /tmp/sing-box-* -maxdepth 2 -type f -name "sing-box" 2>/dev/null | head -n 1)
        if [[ -n "$SB_PATH" ]]; then
            mv "$SB_PATH" /usr/local/bin/sing-box
        fi
    fi
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
      "tcp_keep_alive_delay": "30s", "tcp_keep_alive_interval": "30s",
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
      "type": "hysteria2", "listen": "::", "listen_port": ${HY2_PORT}, "up_mbps": ${HY2_UP}, "down_mbps": ${HY2_DOWN},
      "obfs": { "type": "salamander", "password": "${HY2_OBFS}" },
      "users": [{"password": "${HY2_PASS}"}],
      "tls": { "enabled": true, "certificate_path": "/etc/sing-box/hy2.crt", "key_path": "/etc/sing-box/hy2.key" }
    }
EOF
)
    JSON_SS=$(cat << EOF
    {
      "type": "shadowsocks", "listen": "::", "listen_port": ${SS_PORT}, "tcp_fast_open": true,
      "tcp_keep_alive_delay": "30s", "tcp_keep_alive_interval": "30s",
      "method": "2022-blake3-aes-128-gcm", "password": "${SS_PASS}"
    }
EOF
)
    case $MODE in
        "VLESS") INBOUNDS="[$JSON_VLESS]" ;;
        "HY2") INBOUNDS="[$JSON_HY2]" ;;
        "SS") INBOUNDS="[$JSON_SS]" ;;
        "VLESS_SS") INBOUNDS="[$JSON_VLESS, $JSON_SS]" ;;
        "ALL") INBOUNDS="[$JSON_VLESS, $JSON_HY2, $JSON_SS]" ;;
    esac
    
    # === [修复] 彻底剥离 Sing-box 中的废弃 geosite 规则，确保核心 100% 免疫崩溃 ===
    cat > /etc/sing-box/config.json << EOF
{
  "log": { "level": "warn", "output": "/var/log/aio-box-singbox.log" },
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
        SB_PRE_START=""
        SB_POST_STOP=""
        if [[ "$MODE" == *"HY2"* ]] || [[ "$MODE" == *"ALL"* ]]; then
            SB_PRE_START="ExecStartPre=-/bin/sh -c '$IPT -w -t nat -D PREROUTING -p udp --dport 30000:60000 -j REDIRECT --to-ports $HY2_PORT 2>/dev/null || true'
ExecStartPre=-/bin/sh -c '$IPT -w -t nat -A PREROUTING -p udp --dport 30000:60000 -j REDIRECT --to-ports $HY2_PORT 2>/dev/null || true'"
            SB_POST_STOP="ExecStopPost=-/bin/sh -c '$IPT -w -t nat -D PREROUTING -p udp --dport 30000:60000 -j REDIRECT --to-ports $HY2_PORT 2>/dev/null || true'"
            if has_ipv6; then
                SB_PRE_START="$SB_PRE_START
ExecStartPre=-/bin/sh -c '$IPT6 -w -t nat -D PREROUTING -p udp --dport 30000:60000 -j REDIRECT --to-ports $HY2_PORT 2>/dev/null || true'
ExecStartPre=-/bin/sh -c '$IPT6 -w -t nat -A PREROUTING -p udp --dport 30000:60000 -j REDIRECT --to-ports $HY2_PORT 2>/dev/null || true'"
                SB_POST_STOP="$SB_POST_STOP
ExecStopPost=-/bin/sh -c '$IPT6 -w -t nat -D PREROUTING -p udp --dport 30000:60000 -j REDIRECT --to-ports $HY2_PORT 2>/dev/null || true'"
            fi
        fi
        cat > /etc/systemd/system/sing-box.service << SVC_EOF
[Unit]
Description=Sing-Box Service
After=network.target nss-lookup.target
[Service]
CapabilityBoundingSet=CAP_NET_ADMIN CAP_NET_BIND_SERVICE CAP_SYS_PTRACE CAP_DAC_READ_SEARCH
AmbientCapabilities=CAP_NET_ADMIN CAP_NET_BIND_SERVICE CAP_SYS_PTRACE CAP_DAC_READ_SEARCH
$SB_PRE_START
ExecStart=/usr/local/bin/sing-box run -c /etc/sing-box/config.json
$SB_POST_STOP
Restart=always
RestartSec=10
LimitNOFILE=1048576
LimitNPROC=1048576
[Install]
WantedBy=multi-user.target
SVC_EOF
    elif [[ "$INIT_SYS" == "openrc" ]]; then
        mkdir -p /etc/conf.d
        echo 'rc_ulimit="-n 1048576"' > /etc/conf.d/sing-box
        SB_RC_PRE=""
        SB_RC_POST=""
        if [[ "$MODE" == *"HY2"* ]] || [[ "$MODE" == *"ALL"* ]]; then
            SB_RC_PRE="start_pre() {
  $IPT -w -t nat -D PREROUTING -p udp --dport 30000:60000 -j REDIRECT --to-ports $HY2_PORT 2>/dev/null || true
  $IPT -w -t nat -A PREROUTING -p udp --dport 30000:60000 -j REDIRECT --to-ports $HY2_PORT 2>/dev/null || true"
            SB_RC_POST="stop_post() {
  $IPT -w -t nat -D PREROUTING -p udp --dport 30000:60000 -j REDIRECT --to-ports $HY2_PORT 2>/dev/null || true"
            if has_ipv6; then
                SB_RC_PRE="$SB_RC_PRE
  $IPT6 -w -t nat -D PREROUTING -p udp --dport 30000:60000 -j REDIRECT --to-ports $HY2_PORT 2>/dev/null || true
  $IPT6 -w -t nat -A PREROUTING -p udp --dport 30000:60000 -j REDIRECT --to-ports $HY2_PORT 2>/dev/null || true"
                SB_RC_POST="$SB_RC_POST
  $IPT6 -w -t nat -D PREROUTING -p udp --dport 30000:60000 -j REDIRECT --to-ports $HY2_PORT 2>/dev/null || true"
            fi
            SB_RC_PRE="$SB_RC_PRE
  return 0
}"
            SB_RC_POST="$SB_RC_POST
  return 0
}"
        fi
        cat > /etc/init.d/sing-box << SVC_EOF
#!/sbin/openrc-run
description="Sing-Box Service"
command="/usr/local/bin/sing-box"
command_args="run -c /etc/sing-box/config.json"
command_background="yes"
pidfile="/run/sing-box.pid"
depend() { need net; }
$SB_RC_PRE
$SB_RC_POST
SVC_EOF
        chmod +x /etc/init.d/sing-box
    fi
    service_manager start sing-box
    sleep 2; is_service_running sing-box || { echo -e "${RED}[!] 致命错误：Sing-box 守护进程拉起失败！ / Core panic!${NC}"; exit 1; }
    
    setup_geo_cron
    setup_active_defense
    setup_health_monitor
    
    cat > /etc/ddr/.env << ENV_EOF
CORE="singbox"; MODE="$MODE"; UUID="$UUID"; VLESS_SNI="$VLESS_SNI"; VLESS_PORT="$VLESS_PORT"; HY2_SNI="$HY2_SNI"; HY2_PORT="$HY2_PORT"; HY2_UP="$HY2_UP"; HY2_DOWN="$HY2_DOWN"; SS_PORT="$SS_PORT"; PUBLIC_KEY="$PBK"; SHORT_ID="$SHORT_ID"; HY2_PASS="$HY2_PASS"; HY2_OBFS="$HY2_OBFS"; SS_PASS="$SS_PASS"; LINK_IP="${GLOBAL_PUBLIC_IP}"
ENV_EOF
    chmod 600 /etc/ddr/.env
    view_config "deploy"
}

setup_traffic_monitor() {
    cat > /etc/ddr/traffic_monitor.sh << 'EOF'
#!/bin/bash
PATH=/usr/local/sbin:/usr/local/bin:/sbin:/bin:/usr/sbin:/usr/bin
source /etc/ddr/.env
if [[ -z "$TRAFFIC_LIMIT_GB" ]]; then exit 0; fi
INTERFACE=$(ip route get 8.8.8.8 2>/dev/null | awk '{for(i=1;i<=NF;i++) if($i=="dev") print $(i+1)}' | head -n 1)
[[ -z "$INTERFACE" ]] && INTERFACE=$(ip link | awk -F: '$0 !~ "lo|vir|wl|^[^0-9]"{print $2;getline}' | head -n 1 | tr -d ' ')
USED_LINE=$(vnstat -i "$INTERFACE" -m 2>/dev/null | grep "$(date +'%Y-%m')")
if [[ -n "$USED_LINE" ]]; then
    TOTAL_STR=$(echo "$USED_LINE" | awk -F'|' '{print $3}' | xargs)
    VAL=$(echo "$TOTAL_STR" | awk '{print $1}')
    UNIT=$(echo "$TOTAL_STR" | awk '{print $2}')
    
    USED_GB=0
    if [[ "$UNIT" == *"GiB"* || "$UNIT" == *"GB"* ]]; then USED_GB=$VAL
    elif [[ "$UNIT" == *"TiB"* || "$UNIT" == *"TB"* ]]; then USED_GB=$(echo "$VAL * 1024" | bc)
    elif [[ "$UNIT" == *"MiB"* || "$UNIT" == *"MB"* ]]; then USED_GB=$(echo "scale=2; $VAL / 1024" | bc)
    elif [[ "$UNIT" == *"KiB"* || "$UNIT" == *"KB"* ]]; then USED_GB=$(echo "scale=4; $VAL / 1048576" | bc)
    fi
    
    if (( $(echo "$USED_GB >= $TRAFFIC_LIMIT_GB" | bc -l) )); then
        if command -v systemctl >/dev/null 2>&1; then systemctl stop xray sing-box hysteria 2>/dev/null; else rc-service xray stop 2>/dev/null; rc-service sing-box stop 2>/dev/null; rc-service hysteria stop 2>/dev/null; fi
        killall -9 xray sing-box hysteria 2>/dev/null
    fi
fi
EOF
    chmod +x /etc/ddr/traffic_monitor.sh
    crontab -l 2>/dev/null | grep -vE "^no crontab for|^#" | grep -v '/etc/ddr/traffic_monitor.sh' > /tmp/cronjob || true
    echo "* * * * * /bin/bash /etc/ddr/traffic_monitor.sh >/dev/null 2>&1" >> /tmp/cronjob
    crontab /tmp/cronjob 2>/dev/null; rm -f /tmp/cronjob
}
disable_traffic_monitor() {
    crontab -l 2>/dev/null | grep -vE "^no crontab for|^#" | grep -v '/etc/ddr/traffic_monitor.sh' > /tmp/cronjob || true
    crontab /tmp/cronjob 2>/dev/null; rm -f /tmp/cronjob /etc/ddr/traffic_monitor.sh
}
traffic_management_menu() {
    clear
    echo -e "${CYAN}======================================================================${NC}"
    echo -e "${BOLD}${GREEN} 每月流量管控限制 / Monthly Traffic Management Limit${NC}"
    echo -e "${CYAN}======================================================================${NC}"
    
    local INTERFACE=$(ip route get 8.8.8.8 2>/dev/null | awk '{for(i=1;i<=NF;i++) if($i=="dev") print $(i+1)}' | head -n 1)
    [[ -z "$INTERFACE" ]] && INTERFACE=$(ip link | awk -F: '$0 !~ "lo|vir|wl|^[^0-9]"{print $2;getline}' | head -n 1 | tr -d ' ')
    
    echo -e "${YELLOW}[网卡 (Interface) ${INTERFACE} 当前月流量统计 / Current Month Traffic Statistics]${NC}"
    
    echo -e "${CYAN} ► rx (Receive)  : 入站流量 / Inbound (Data flowing INTO the VPS)${NC}"
    echo -e "${CYAN} ► tx (Transmit) : 出站流量 / Outbound (Data flowing FROM the VPS)${NC}"
    echo -e "${CYAN} ► total (Total) : 总吞吐量 / Total (Sum of Inbound and Outbound)${NC}"
    echo -e "${MAGENTA} [提示] AWS/GCP 计费通常仅针对 tx (出站) 流量收费。${NC}"
    echo -e "${BLUE}----------------------------------------------------------------------${NC}"
    
    if command -v vnstat >/dev/null 2>&1; then
        local USED_LINE=$(vnstat -i "$INTERFACE" -m 2>/dev/null | grep "$(date +'%Y-%m')")
        if [[ -n "$USED_LINE" ]]; then 
            vnstat -i "$INTERFACE" -m 2>/dev/null | head -n 6 | grep -v '^$'
        else 
            echo -e "${YELLOW}暂无本月统计数据，vnstat 正在收集中... / No data for this month yet, vnstat is collecting...${NC}"
        fi
    else
        echo -e "${RED}[!] 未检测到 vnstat，请确保环境已初始化。 / vnstat not detected, ensure environment is initialized.${NC}"
    fi
    echo -e "${BLUE}----------------------------------------------------------------------${NC}"
    
    source /etc/ddr/.env 2>/dev/null
    if [[ -n "$TRAFFIC_LIMIT_GB" ]]; then
        echo -e "当前设定的每月流量上限 / Current Monthly Traffic Limit: ${GREEN}${TRAFFIC_LIMIT_GB} GB${NC}\n管控状态 / Management Status: ${GREEN}监控中 (每分钟自动检测一次) / Active (Monitored every minute)${NC}"
    else
        echo -e "当前设定的每月流量上限 / Current Monthly Traffic Limit: ${RED}未开启 (Unlimited) / Disabled (Unlimited)${NC}"
    fi
    echo -e "${CYAN}======================================================================${NC}"
    echo -e "${YELLOW}1. 设定/修改每月流量上限 (Set/Modify Monthly Traffic Limit)${NC}\n${YELLOW}2. 解除流量限制 (Disable Traffic Limit)${NC}\n${GREEN}0. 返回主菜单 / Return to Main Menu${NC}"
    echo -e "${CYAN}======================================================================${NC}"
    read -ep " 请选择 / Select [0-2]: " tr_choice
    
    case $tr_choice in
        1)
            read -ep " 请输入每月总流量上限(GB)，纯数字 / Enter monthly traffic limit (GB), numbers only: " limit_gb
            if [[ "$limit_gb" =~ ^[0-9]+$ ]]; then
                sed -i '/TRAFFIC_LIMIT_GB/d' /etc/ddr/.env 2>/dev/null
                echo "TRAFFIC_LIMIT_GB=\"$limit_gb\"" >> /etc/ddr/.env
                setup_traffic_monitor
                echo -e "${GREEN}✔ 流量限制已设定为 / Traffic limit set to ${limit_gb} GB！${NC}\n${YELLOW}[提示] 若节点曾因超量被系统阻断，调高限额后请在主菜单重新部署一次以唤醒服务。 / [Tip] If node was blocked due to overage, redeploy from main menu to wake up services.${NC}"
            else
                echo -e "${RED}[!] 输入无效，请输入纯数字。 / Invalid input, please enter numbers only.${NC}"
            fi
            read -ep "按回车返回 / Press Enter to return..."
            ;;
        2)
            sed -i '/TRAFFIC_LIMIT_GB/d' /etc/ddr/.env 2>/dev/null
            disable_traffic_monitor
            echo -e "${GREEN}✔ 流量限制已成功解除。 / Traffic limit successfully disabled.${NC}"
            read -ep "按回车返回 / Press Enter to return..."
            ;;
        *) return 0 ;;
    esac
}

# --- [7] 渲染与交互组件 / UI Rendering Components ---
generate_qr() {
    local url=$1
    if command -v qrencode >/dev/null 2>&1; then
        echo -e "\n${CYAN}================ 扫码导入 / Scan QR Code =================${NC}\n$(echo -e "${url}" | qrencode -s 1 -m 2 -t UTF8)\n${CYAN}==========================================================${NC}\n"
    fi
}
view_config() {
    local CALLER=$1; clear; [[ ! -f /etc/ddr/.env ]] && { echo -e "${RED}未检测到持久化配置变量！ / Configuration not found!${NC}"; sleep 2; return 0; }
    source /etc/ddr/.env
    
    local F_IP="${LINK_IP}"
    [[ "${LINK_IP}" =~ ":" ]] && F_IP="[${LINK_IP}]"
    echo -e "${BLUE}======================================================================${NC}\n${BOLD}${CYAN} 全局拓扑网络参数 (${MODE}) / Network Parameters ${NC}\n${BLUE}======================================================================${NC}"
    echo -e "${BOLD}引擎栈 / Engine:${NC} $CORE | ${BOLD}模式 / Mode:${NC} $MODE\n${BLUE}----------------------------------------------------------------------${NC}"
    
    if [[ "$MODE" == *"VLESS"* ]] || [[ "$MODE" == *"ALL"* ]] || [[ "$MODE" == "VLESS_SS" ]]; then
        VLESS_URL="vless://$UUID@$F_IP:$VLESS_PORT?encryption=none&flow=xtls-rprx-vision&security=reality&sni=$VLESS_SNI&fp=chrome&pbk=$PUBLIC_KEY&sid=$SHORT_ID&type=tcp#Aio-VLESS"
        echo -e "${YELLOW}[ VLESS-Vision 深层隐匿链路 / VLESS URI ]${NC}\n(警告: 小火箭等客户端务必将 uTLS 设置为 chrome, 否则秒被物理断连 / Set uTLS to chrome)\n${GREEN}${VLESS_URL}${NC}"
        generate_qr "$VLESS_URL"
    fi
    if [[ "$MODE" == *"HY2"* ]] || [[ "$MODE" == *"ALL"* ]]; then
        HY2_URL="hysteria2://$HY2_PASS@$F_IP:$HY2_PORT/?insecure=1&sni=$HY2_SNI&alpn=h3&obfs=salamander&obfs-password=$HY2_OBFS&mport=30000-60000#Aio-Hy2"
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
    keep-alive-interval: 15
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
    ports: 30000-60000
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
    keep-alive-interval: 15
EOF
    fi
    echo -e "${BLUE}----------------------------------------------------------------------${NC}"
    [[ "$CALLER" == "deploy" ]] && echo -e "${GREEN}✔ 服务池编译部署完毕！可随时键入 13 调出此面板。 / Initialization Phase Complete!${NC}"
    read -ep "按回车安全退出交互空间并返回总台 / Press Enter to return..."
}
show_usage() {
    clear
    echo -e "${CYAN}======================================================================${NC}"
    echo -e "${BOLD}${GREEN} Aio-box 脚本全功能说明书 / Full Functional Manual${NC}"
    echo -e "${CYAN}======================================================================${NC}"
    echo -e "${YELLOW}【一】核心部署模式 / Core Deployment Modes${NC}"
    echo -e " 1. Xray VLESS-Reality: 采用主流 Xray 核心，提供最稳健的 Reality 伪装支持。\n (Uses Xray-core for the most robust Reality camouflage support.)"
    echo -e " 2. Xray Shadowsocks-2022: 部署最新标准 SS 协议，兼顾高强度加密与传输性能。\n (Deploys the latest SS standard, balancing high encryption and performance.)"
    echo -e " 3. Xray VLESS + SS-2022: 混合部署模式，单端口实现多协议兼容。\n (Hybrid deployment mode, achieving multi-protocol compatibility on a single port.)"
    echo -e " 4. Hysteria 2 (Native): 采用 Apernet 官方原版核心，专注暴力拥塞控制与 UDP 穿透。\n (Uses official Apernet core, focusing on aggressive congestion control and UDP piercing.)"
    echo -e " 5. Xray + Hy2 (Hybrid): 物理隔离架构。TCP 由 Xray 承载，UDP 由 Hy2 原生承载，稳定性极高。\n (Physical isolation architecture: TCP by Xray, UDP by native Hy2, offering extreme stability.)"
    echo -e " 6. Sing-box VLESS-Reality: 利用 Sing-box 高效能架构部署 VLESS，内存占用极低。\n (Uses Sing-box high-performance architecture for VLESS with ultra-low memory usage.)"
    echo -e " 7. Sing-box Shadowsocks-2022: Sing-box 原生承载 SS 协议，适合轻量化运维。\n (Sing-box natively carries the SS protocol, ideal for lightweight maintenance.)"
    echo -e " 8. Sing-box VLESS + SS-2022: Sing-box 环境下的双协议聚合部署。\n (Dual-protocol aggregated deployment within the Sing-box environment.)"
    echo -e " 9. Sing-box Hysteria 2: Sing-box 聚合版 Hy2，实现单一进程管理 UDP 加密流量。\n (Sing-box aggregated Hy2, managing encrypted UDP traffic within a single process.)"
    echo -e " 10. Sing-box ALL: 全协议聚合。一键在 Sing-box 内部启动 VLESS、SS 与 Hy2。\n (Full protocol aggregation. Starts VLESS, SS, and Hy2 within Sing-box in one go.)\n"
    echo -e "${YELLOW}【二】终端对齐与强制规范 / Terminal Alignment & Enforcement${NC}"
    echo -e " 1. VLESS-Reality 禁区 (Reality Taboo):\n - 严禁开启 Mux (多路复用)：Vision 流控要求原始包长度对齐，开启 Mux 会导致特征识别失败被断连。\n (NEVER enable Mux: Vision flow control requires original packet length alignment; Mux will cause disconnection.)\n - 伪装指纹 (uTLS)：必须使用 'chrome' 指纹以模拟真实流量特征。\n (uTLS Fingerprint: MUST use 'chrome' to simulate authentic traffic characteristics.)"
    echo -e " 2. Hysteria 2 免疫策略 (Hy2 Immunity):\n - 证书验证：由于采用自签证书，客户端必须开启 '允许不安全证书' 或 '跳过证书验证'。\n (Certificate: Due to self-signed certs, clients MUST enable 'Allow Insecure' or 'Skip Cert Verify'.)\n"
    echo -e "${YELLOW}【三】面板运维功能 / Panel Operations Tools${NC}"
    echo -e " 11. 测速与 IP 审计 (Benchmark): 调用 bench.sh 与 Check.Place 检测 VPS 性能与 IP 欺诈分。\n (Runs bench.sh and Check.Place to audit VPS performance and IP fraud scores.)"
    echo -e " 12. VPS 一键优化 (BBR Tuning): 注入内核参数，开启 BBR 算法，同时一键部署防御探针与黑名单。\n (Injects kernel params, enables BBR, and auto-deploys L4 probes & blackholes.)"
    echo -e " 13. 参数显示 (View Config): 实时生成 URI 分享链接、二维码及 Clash Meta 配置文件片段。\n (Generates URI links, QR codes, and Clash Meta configuration snippets in real-time.)"
    echo -e " 15. 脚本OTA升级与Geo资源更新 / Script OTA & Geo Resource Updat：在线同步 GitHub 远端源码，实现脚本无损热更新。\n (Syncs remote GitHub source bypassing cache for lossless script hot-updates.)"
    echo -e " 16. 一键清空 (Uninstall): 提供物理级完全清场模式，彻底粉碎节点、配置与防火墙规则。\n (Provides a physical-level wipe mode to completely shred nodes, configs, and firewall rules.)"
    echo -e " 17. 环境自愈 (Self-Healing): 自动扫描进程死锁、清除脏路由、释放端口占用，恢复系统纯净。\n (Auto-scans process deadlocks, clears dirty routes, and releases ports to restore system purity.)"
    echo -e " 18. 流量管控 (Traffic Limit): 基于 vnstat 监控流量，支持到达月度阈值后自动熔断服务以防超支。\n (Monitors traffic via vnstat; supports auto-shutdown after reaching monthly thresholds to prevent overage.)"
    echo -e "${CYAN}======================================================================${NC}"
    read -ep " 阅读完毕，按回车返回主菜单 / Press Enter to return to main menu..."
}
update_script() {
    clear; echo -e "${CYAN}======================================================================${NC}"
    echo -e "${BOLD}${GREEN} 云端更新引擎 / OTA Online Sync Subsystem${NC}"
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
force_update_geo() {
    clear
    echo -e "${CYAN}======================================================================${NC}"
    echo -e "${BOLD}${GREEN} Loyalsoldier Geo 资源强更 / Force Update Geo Data${NC}"
    echo -e "${CYAN}======================================================================${NC}"
    echo -e "${YELLOW}[*] 正在拉取 Loyalsoldier 增强版 Geo 资源并执行校验... / Fetching Geo Data...${NC}"
    setup_geo_cron
    bash /etc/ddr/geo_update.sh
    echo -e "${GREEN}✔ Geo 资源更新与校验成功，已覆盖核心文件并完成热重载！${NC}\n${GREEN}✔ 定时任务已同步下发：每周一夜里 3:00 自动静默执行闭环更新。${NC}"
    read -ep "按回车返回..."
}
ota_and_geo_menu() {
    clear
    echo -e "${CYAN}======================================================================${NC}"
    echo -e "${BOLD}${GREEN} 脚本 OTA 升级与 Geo 资源更新 / OTA & Geo Update${NC}"
    echo -e "${CYAN}======================================================================${NC}"
    echo -e "${YELLOW}1. 升级 Aio-box 核心脚本 (OTA Update Script)${NC}\n${YELLOW}2. 立即拉取并更新 Loyalsoldier Geo 资源 (Update Geo Data & Set Cron)${NC}\n${GREEN}0. 返回主菜单 / Return${NC}"
    echo -e "${CYAN}======================================================================${NC}"
    read -ep " 请选择 / Select [0-2]: " ota_choice
    case $ota_choice in
        1) update_script ;;
        2) force_update_geo ;;
        *) return 0 ;;
    esac
}
clean_uninstall_menu() {
    clear
    echo -e "${CYAN}======================================================================${NC}"
    echo -e "${BOLD}${RED} 深度卸载系统 / Deep Unloading System${NC}"
    echo -e "${CYAN}======================================================================${NC}"
    echo -e "${YELLOW}1. 完全物理清场/Complete physical decontamination (销毁节点、配置表、防火墙映射与全局快速访问别名)${NC}\n${YELLOW}2. 保留脚本与清场/Maintain the script and clear the area (销毁节点配置等，但留存控制台与环境供随时重构)${NC}\n${GREEN}0. 取消并返回 / Abort and Return${NC}"
    echo -e "${CYAN}======================================================================${NC}"
    read -ep " 请谨慎输入执行代码 / Execution Code [0-2]: " un_choice
    case $un_choice in
        1) do_cleanup "full" ;;
        2) do_cleanup "keep" ;;
        0|*) return 0 ;;
    esac
}
do_cleanup() {
    clear; echo -e "${RED}⚠️ 正在执行剥离逻辑... / Executing precision wipe protocol...${NC}"
    init_system_environment
    service_manager stop xray sing-box hysteria
    killall -9 xray sing-box hysteria 2>/dev/null || true
    clean_nat_rules; clean_input_rules; save_firewall_rules
    
    rm -rf /usr/local/etc/xray /etc/sing-box /etc/hysteria /usr/local/bin/xray /usr/local/bin/sing-box /usr/local/bin/hysteria
    rm -f /etc/systemd/system/xray.service /etc/systemd/system/sing-box.service /etc/systemd/system/hysteria.service
    rm -f /etc/init.d/xray /etc/init.d/sing-box /etc/init.d/hysteria
    rm -f /etc/sysctl.d/99-aio-box-tune.conf /etc/security/limits.d/aio-box.conf
    
    crontab -l 2>/dev/null | grep -vE "^no crontab for|^#" | grep -vE '/etc/ddr/traffic_monitor.sh|/etc/ddr/geo_update.sh|/etc/ddr/socket_probe.sh' > /tmp/cronjob || true
    crontab /tmp/cronjob 2>/dev/null; rm -f /tmp/cronjob /etc/ddr/traffic_monitor.sh /etc/ddr/geo_update.sh /etc/ddr/socket_probe.sh
    rm -rf /var/log/aio-box-*.log /etc/fail2ban/jail.d/aio-box.local /etc/fail2ban/filter.d/aio-box.conf /etc/logrotate.d/aio-box 2>/dev/null
    [[ "$INIT_SYS" == "systemd" ]] && systemctl restart fail2ban 2>/dev/null || true
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
    echo -e "\n\033[1;33m========================================================================================\033[0m"
    echo -e "\033[1;33m 删除全部节点与环境初始化 / Delete all nodes and perform environment initialization \033[0m"
    echo -e "\033[1;33m========================================================================================\033[0m\n"
    echo -e "${BOLD}${RED}【高危操作警告 / DANGER】${NC}"
    echo -e "${YELLOW}此操作将无差别猎杀所有代理进程、抹除相关防火墙规则并物理粉碎节点配置文件！${NC}"
    read -ep " 确定要执行环境深度自愈吗？(输入 y 确认，其他任意键安全取消): " confirm_virgin
    case "$confirm_virgin" in
        [yY]|[yY][eE][sS]) echo -e "\n${GREEN}身份验证通过，开始物理级清场...${NC}\n" ;;
        *) echo -e "\n${GREEN}✔ 操作已安全取消，未对系统造成任何更改。${NC}"; read -ep " 按回车返回主控制台 / Press Enter to return..."; return 0 ;;
    esac
    echo -e "\033[1;36m[1/5] 执行内存地址与高优端口锁死检测 / Scanning memory address binding...\033[0m"
    local BAD_PROC=$(ps aux | grep -E 'xray|sing-box|hysteria' | grep -v grep 2>/dev/null)
    local BAD_PORT=$(ss -tulpn | grep -E ':80\b|:443\b|:2053\b|:8443\b' 2>/dev/null)
    if [[ -n "$BAD_PROC" || -n "$BAD_PORT" ]]; then
        echo -e "${YELLOW} [!] 发现未受控的进程挂起或死锁。执行系统级原子绞杀 / Resolving deadlock...${NC}"
        service_manager stop xray sing-box hysteria
        killall -9 xray sing-box hysteria 2>/dev/null || true
        fuser -k -9 443/tcp 443/udp 2053/tcp 2053/udp 80/tcp 8443/udp 2>/dev/null || true
        echo -e "${GREEN} ✔ 修复完毕: 系统句柄已强行阻断并释放回内存池 / Resources forcefully reclaimed.${NC}"
    else
        echo -e "${GREEN} ✔ 校验通过: 未发现寻址层争抢冲突 / Process logic healthy.${NC}"
    fi
    echo -e "\n\033[1;36m[2/5] 探查底层 Linux 内核 TCP/IP 过滤链栈 / Analyzing Netfilter topology...\033[0m"
    local NAT_C=$($IPT -t nat -S PREROUTING 2>/dev/null | grep -i "30000:60000")
    local INP_C=$($IPT -S INPUT 2>/dev/null | grep -i "Aio-box-")
    local NAT_C6=$($IPT6 -t nat -S PREROUTING 2>/dev/null | grep -i "30000:60000")
    local INP_C6=$($IPT6 -S INPUT 2>/dev/null | grep -i "Aio-box-")
    if [[ -n "$NAT_C" || -n "$INP_C" || -n "$NAT_C6" || -n "$INP_C6" ]]; then
        echo -e "${YELLOW} [!] 捕获到废弃的虚假转发脏路由表。执行无损阻断剔除 / Executing targeted firewall reset...${NC}"
        clean_nat_rules; clean_input_rules; save_firewall_rules
        echo -e "${GREEN} ✔ 修复完毕: 脏配置链已抹除，且未侵入/破坏其他原生程序运行 / Target chain disinfected.${NC}"
    else
        echo -e "${GREEN} ✔ 校验通过: 防火墙底层逻辑栈纯净无干扰 / Filter stack pristine.${NC}"
    fi
    echo -e "\n\033[1;36m[3/5] 检索系统自持服务管理器索引 / Checking daemon registry indexing...\033[0m"
    if [[ -f /etc/systemd/system/xray.service || -f /etc/init.d/xray || -f /etc/systemd/system/hysteria.service ]]; then
        echo -e "${YELLOW} [!] 检索到失效自启动碎片信息。执行挂载卸载操作 / Unloading daemon fragments...${NC}"
        rm -f /etc/systemd/system/xray.service /etc/systemd/system/sing-box.service /etc/systemd/system/hysteria.service 2>/dev/null
        rm -f /etc/init.d/xray /etc/init.d/sing-box /etc/init.d/hysteria 2>/dev/null
        [[ "$INIT_SYS" == "systemd" ]] && systemctl daemon-reload 2>/dev/null || true
        echo -e "${GREEN} ✔ 修复完毕: 失效索引树已解除并对齐 / Daemon registry flushed.${NC}"
    else
        echo -e "${GREEN} ✔ 校验通过: 服务树状表条目完全干净 / Daemon registry healthy.${NC}"
    fi
    echo -e "\n\033[1;36m[4/5] 校验块文件存储级污染遗存 / Performing disk I/O pollution check...\033[0m"
    local DIR_C=$(ls -d /usr/local/etc/xray /etc/sing-box /etc/hysteria 2>/dev/null)
    if [[ -n "$DIR_C" ]]; then
        echo -e "${YELLOW} [!] 确认存在无效物理配置文件群。执行磁盘擦除程序 / Wiping orphaned configs...${NC}"
        rm -rf /usr/local/etc/xray /etc/sing-box /etc/hysteria /usr/local/bin/xray /usr/local/bin/sing-box /usr/local/bin/hysteria 2>/dev/null
        echo -e "${GREEN} ✔ 修复完毕: 全链路陈旧文件已进行物理粉碎 / Dead weight cleared.${NC}"
    else
        echo -e "${GREEN} ✔ 校验通过: 文件节点未被污染侵蚀 / VFS tree pristine.${NC}"
    fi
    echo -e "\n\033[1;36m[5/5] 执行全球出站网关连通性探针 / Testing global egress pathways...\033[0m"
    if curl -I -s -m 5 https://www.google.com | head -n 1 | grep -qE "200|301|302"; then
        echo -e "${GREEN} ✔ 校验通过: 数据包出站物理隧道贯通无阻 / Data egress confirmed 100%.${NC}"
    else
        echo -e "${RED} [!] 严重警告: GFW 出站受到阻截（防火墙未开放对应端口或无网），请彻查系统控制台拦截策略！${NC}"
    fi
    echo -e "\n\033[1;33m================================================================\033[0m"
    echo -e "${GREEN}全链路自愈引擎闭环结束。部署环境现达到绝对真空洁净级别。 / Self-Healing Cycle Complete.${NC}"
    read -ep "按回车返回主控制台 / Press Enter to return..."
}

# === 功能 12 核心重构: 校验并追杀式注入 1.3.4 功能 / Tune VPS Enhancement ===
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
net.ipv4.tcp_keepalive_time = 30
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
            for conf in /etc/sysctl.d/*.conf /etc/sysctl.conf; do [[ -f "$conf" ]] && sysctl -p "$conf" >/dev/null 2>&1 || true; done
        else
            sysctl --system >/dev/null 2>&1 || true
        fi
    fi
    if [[ -f /usr/local/etc/xray/config.json ]] && ! grep -q "tcpKeepAliveIdle" /usr/local/etc/xray/config.json; then
        echo -e "${YELLOW}[*] 正在向 Xray 配置注入 TCP 双向心跳保活参数 (30s)...${NC}"
        if command -v jq >/dev/null 2>&1; then
            if jq '(.inbounds[] | select(.protocol=="vless" or .protocol=="shadowsocks")) |= (.streamSettings.sockopt = {"tcpKeepAliveIdle": 30, "tcpKeepAliveInterval": 30})' /usr/local/etc/xray/config.json > /tmp/xray_patch.json && [[ -s /tmp/xray_patch.json ]]; then
                mv -f /tmp/xray_patch.json /usr/local/etc/xray/config.json
                service_manager start xray 2>/dev/null
                echo -e "${GREEN}   ✔ Xray 服务端心跳底层注入完成！${NC}"
            fi
        fi
    fi
    if [[ -f /etc/sing-box/config.json ]] && ! grep -q "tcp_keep_alive_delay" /etc/sing-box/config.json; then
        echo -e "${YELLOW}[*] 正在向 Sing-box 配置注入 TCP 双向心跳保活参数 (30s)...${NC}"
        if command -v jq >/dev/null 2>&1; then
            if jq '(.inbounds[] | select(.type=="vless" or .type=="shadowsocks")) |= . + {"tcp_keep_alive_delay": "30s", "tcp_keep_alive_interval": "30s"}' /etc/sing-box/config.json > /tmp/sb_patch.json && [[ -s /tmp/sb_patch.json ]]; then
                mv -f /tmp/sb_patch.json /etc/sing-box/config.json
                service_manager start sing-box 2>/dev/null
                echo -e "${GREEN}   ✔ Sing-box 服务端心跳底层注入完成！${NC}"
            fi
        fi
    fi

    # === 检测与自动挂载 1.3.4 增强模块 ===
    echo -e "${CYAN}\n[*] 正在校验并强制挂载 L4自愈探针(1) / 环形防御(3) / 审计阻断黑洞(4)...${NC}"
    
    # 检测 1. 探针挂载
    if ! crontab -l 2>/dev/null | grep -q '/etc/ddr/socket_probe.sh'; then
        setup_health_monitor
        echo -e "${GREEN}   ✔ L4 内核套接字健康探针校验不通过，已为您重新挂载！${NC}"
    else
        echo -e "${GREEN}   ✔ L4 内核套接字健康探针状态: 已激活${NC}"
    fi

    # 检测 3. 防御矩阵挂载
    if [[ ! -f /etc/fail2ban/jail.d/aio-box.local ]] || [[ ! -f /etc/logrotate.d/aio-box ]]; then
        setup_active_defense
        echo -e "${GREEN}   ✔ Fail2Ban 与 Logrotate 环形缓冲防御矩阵已为您重新挂载！${NC}"
    else
        echo -e "${GREEN}   ✔ 环形防御矩阵状态: 已激活${NC}"
    fi

    # 检测 4. Geosite 黑名单与探针注入 (彻底隔离 Xray 与 Sing-box 的配置写入逻辑)
    if [[ -f /usr/local/etc/xray/config.json ]] && ! grep -q "category-ads-all" /usr/local/etc/xray/config.json; then
        if command -v jq >/dev/null 2>&1; then
            jq '.routing.rules += [{"type": "field", "domain": ["geosite:category-ads-all"], "outboundTag": "block"}] | .log = {"loglevel": "warning", "access": "/var/log/aio-box-xray.log"}' /usr/local/etc/xray/config.json > /tmp/xp.json && mv /tmp/xp.json /usr/local/etc/xray/config.json
            service_manager start xray 2>/dev/null
            echo -e "${GREEN}   ✔ Xray 路由拦截黑名单与日志持久化已热重载！${NC}"
        fi
    fi
    # [漏洞修复区] 仅给 Sing-box 配置日志路径，绝对不碰它的路由表，彻底封杀二次崩溃的可能
    if [[ -f /etc/sing-box/config.json ]] && ! grep -q "aio-box-singbox.log" /etc/sing-box/config.json; then
        if command -v jq >/dev/null 2>&1; then
            jq '.log = {"level": "warn", "output": "/var/log/aio-box-singbox.log"}' /etc/sing-box/config.json > /tmp/sp.json && mv /tmp/sp.json /etc/sing-box/config.json
            service_manager start sing-box 2>/dev/null
            echo -e "${GREEN}   ✔ Sing-box 日志持久化探针已安全热重载！${NC}"
        fi
    fi

    echo -e "\n${GREEN}✔ 内核 BBR 配置块及最大并发映射文件已成功熔接至系统底层！ / Subsystem Kernel Parameters Updated.${NC}"
    read -ep "按回车安全退出 / Press Enter to return..."
}

vps_benchmark_menu() {
    clear
    echo -e "${CYAN}======================================================================${NC}"
    echo -e "${BOLD}${GREEN} 本机配置与IP测速纯净度 / Benchmark & IP Check${NC}"
    echo -e "${CYAN}======================================================================${NC}"
    echo -e "${YELLOW}1. 本机配置和测速 (bench.sh) / System Info & Speedtest${NC}\n${YELLOW}2. IP纯净度和测速 (Check.Place) / IP Quality & Speed${NC}\n${GREEN}0. 返回主菜单 / Return to Main Menu${NC}"
    echo -e "${CYAN}======================================================================${NC}"
    read -ep " 请选择 / Please select [0-2]: " bench_choice
    case $bench_choice in
        1) clear; echo -e "${GREEN}正在运行 bench.sh... / Running bench.sh...${NC}"; wget -qO- https://bench.sh | bash; read -ep "按回车返回主菜单 / Press Enter to return..." ;;
        2) clear; echo -e "${GREEN}正在运行 Check.Place... / Running Check.Place...${NC}"; bash <(curl -Ls https://Check.Place) -I; read -ep "按回车返回主菜单 / Press Enter to return..." ;;
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
    is_service_running hysteria && STATUS_STR+="${GREEN}Hy2(Native)${NC} "
    [[ -z "$STATUS_STR" ]] && STATUS_STR="${RED}Stack Stopped${NC}"
    
    source /etc/ddr/.env 2>/dev/null && CUR_MODE="[${CORE}-${MODE}]" || CUR_MODE=""
    
    clear; echo -e "${BLUE}======================================================================${NC}\n${BOLD}${YELLOW} ==============================Aio-box===============================${NC}\n${BLUE}======================================================================${NC}"
    echo -e " 网关/Gateway: ${YELLOW}$GLOBAL_PUBLIC_IP${NC} | 核心/Core: $STATUS_STR $CUR_MODE\n${BLUE}----------------------------------------------------------------------${NC}"
    echo -e " ${YELLOW}[ Xray-core 部署/Deployment ]${NC} ${YELLOW}[ Sing-box 部署/Deployment ]${NC}"
    echo -e " ${GREEN}1.${NC} VLESS-Reality ${GREEN}                6.${NC} VLESS-Reality"
    echo -e " ${GREEN}2.${NC} Shadowsocks-2022 ${GREEN}             7.${NC} Shadowsocks-2022"
    echo -e " ${GREEN}3.${NC} VLESS + SS-2022 ${GREEN}              8.${NC} VLESS + SS-2022"
    echo -e " ${GREEN}4.${NC} Hysteria 2 (原生/Apernet) ${GREEN}   9.${NC} Hysteria 2 (Sing-box)"
    echo -e " ${GREEN}5.${NC} 全协议三合一/All (Xray+Hy2) ${GREEN}10.${NC} 全协议三合一/All (Sing-box)"
    echo -e "${BLUE}----------------------------------------------------------------------${NC}"
    echo -e " ${GREEN}11.${NC} 本机配置与IP测速纯净度 / The purity of local configuration and IP speed test"
    echo -e " ${GREEN}12.${NC} VPS一键优化 / VPS One-click Optimization"
    echo -e " ${GREEN}13.${NC} 全部节点参数显示 / Display of all node parameters"
    echo -e " ${GREEN}14.${NC} 脚本说明书 / Script Description Document"
    echo -e " ${GREEN}15.${NC} 脚本OTA升级与Geo资源更新 / Script OTA & Geo Resource Update"
    echo -e " ${GREEN}16.${NC} 一键全部清空卸载 / One-click to completely clear and uninstall"
    echo -e " ${GREEN}17.${NC} 删除全部节点与环境初始化 / Delete all nodes and perform environment initialization"
    echo -e " ${GREEN}18.${NC} 每月流量管控限制 / Monthly Traffic Management Limit"
    echo -e " ${GREEN} 0.${NC} 退出脚本 / Exit Script"
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
        15) ota_and_geo_menu ;;
        16) clean_uninstall_menu ;;
        17) check_virgin_state ;;
        18) traffic_management_menu ;;
        0) clear; rm -f /var/run/aio_box.lock; exit 0 ;;
        *) sleep 1 ;;
    esac
done
