#!/usr/bin/env bash
# ====================================================================================================
# Aio-box Ultimate Console [Dual-Core Hybrid | Auto-Fix | Enterprise V9.9 Final Perfected (Speed Edition)]
# [Deep Deterministic Reasoning Audited: Instant Menu Startup, Auto-Healing Shortcut, Zero-Block Init]
# ====================================================================================================

umask 077
export DEBIAN_FRONTEND=noninteractive
export LANG=en_US.UTF-8
export LC_ALL=C
export PATH=/usr/local/sbin:/usr/local/bin:/sbin:/bin:/usr/sbin:/usr/bin

# 禁用核心转储，防止敏感内存数据泄露，安全设定企业级高并发句柄数为 1048576 (100万)
ulimit -c 0 
ulimit -n 1048576

RED='\033[0;31m' GREEN='\033[0;32m' YELLOW='\033[0;33m' BLUE='\033[0;36m' PURPLE='\033[0;35m' CYAN='\033[0;36m' NC='\033[0m' BOLD='\033[1m'

trap 'echo -e "\n${RED}[!] 捕捉到中断信号，正在清理环境...${NC}"; rm -rf /dev/shm/aio_box_* /dev/shm/aio_geo_update 2>/dev/null; rm -f /var/run/aio_box.lock; exit 1' INT TERM

LOG_FILE="/var/log/aio_box_enterprise.log"
[[ ! -f "$LOG_FILE" ]] && touch "$LOG_FILE" && chmod 600 "$LOG_FILE"

if [[ -z "${AIO_LOG_PIPED:-}" ]]; then
    export AIO_LOG_PIPED=1
    exec > >(tee >(sed -r 's/\x1B\[[0-9;]*[a-zA-Z]//g' >> "$LOG_FILE")) 2>&1
fi

if [[ $EUID -ne 0 ]]; then
    if command -v sudo >/dev/null 2>&1; then
        exec sudo bash "$0" "$@"
    else
        echo -e "${RED}[!] 致命错误: 必须拥有 Root 权限！${NC}"
        exit 1
    fi
fi

exec 9<> /var/run/aio_box.lock
if ! flock -n 9; then
    echo -e "${RED}[!] 致命异常: 检测到并行实例，互斥锁已激活！${NC}"
    exit 1
fi

sed -i '/acme.sh.env/d' ~/.bashrc >/dev/null 2>&1 || true

has_ipv6() {
    if ping6 -c 1 -W 2 2606:4700:4700::1111 >/dev/null 2>&1 || ip -6 addr show scope global | grep -q inet6; then
        return 0
    else
        return 1
    fi
}

# ====================================================================
# 系统算力深度调优模块 (仅在部署或优化时调用，不阻塞主菜单)
# ====================================================================
audit_hardware_resources() {
    echo -e "${CYAN} -> [硬件审计] 探测 CPU、内存拓扑及指令周期...${NC}"
    
    export TOTAL_MEM=$(free -m | awk '/^Mem:/{print $2}')
    export GOMEMLIMIT_MB=$(( TOTAL_MEM * 85 / 100 ))
    [[ $GOMEMLIMIT_MB -lt 256 ]] && GOMEMLIMIT_MB=256

    if [[ "$TOTAL_MEM" -lt 1024 ]]; then
        echo -e "${YELLOW} -> [警告] 内存临界 (${TOTAL_MEM}MB)，已计算安全 GOMEMLIMIT 为 ${GOMEMLIMIT_MB}MB。${NC}"
        local SWAP_MEM=$(free -m | awk '/^Swap:/{print $2}')
        if [[ "$SWAP_MEM" -eq 0 ]]; then
            local VAR_AVAIL=$(df -kP /var | tail -n 1 | awk '{print int($4/1024)}')
            if [[ -n "$VAR_AVAIL" && "$VAR_AVAIL" -gt 1536 ]]; then
                echo -e "${YELLOW} -> [算力干预] 磁盘安全验证通过，开辟 1024MB 虚拟内存防御 OOM Killer...${NC}"
                dd if=/dev/zero of=/var/aio_swap.img bs=1M count=1024 status=none
                chmod 600 /var/aio_swap.img
                mkswap /var/aio_swap.img >/dev/null 2>&1
                swapon /var/aio_swap.img >/dev/null 2>&1
                if ! grep -q "aio_swap" /etc/fstab; then
                    echo '/var/aio_swap.img none swap sw 0 0' >> /etc/fstab
                fi
                echo -e "${GREEN}    ✔ Swap 热插拔挂载完毕 (1024MB)。${NC}"
            elif [[ -n "$VAR_AVAIL" && "$VAR_AVAIL" -gt 800 ]]; then
                echo -e "${YELLOW} -> [算力干预] 磁盘空间有限，开辟 512MB 虚拟内存防御 OOM Killer...${NC}"
                dd if=/dev/zero of=/var/aio_swap.img bs=1M count=512 status=none
                chmod 600 /var/aio_swap.img
                mkswap /var/aio_swap.img >/dev/null 2>&1
                swapon /var/aio_swap.img >/dev/null 2>&1
                if ! grep -q "aio_swap" /etc/fstab; then
                    echo '/var/aio_swap.img none swap sw 0 0' >> /etc/fstab
                fi
                echo -e "${GREEN}    ✔ Swap 热插拔挂载完毕 (512MB)。${NC}"
            else
                echo -e "${RED} -> [高危警报] 磁盘剩余空间严重不足 (${VAR_AVAIL}MB)，跳过 Swap 创建以保护系统核心层！${NC}"
            fi
        else
            echo -e "${GREEN}    ✔ 检测到存量 Swap (${SWAP_MEM}MB)。${NC}"
        fi
    fi

    if grep -q "aes" /proc/cpuinfo 2>/dev/null; then
        export CPU_HAS_AES=1
        echo -e "${GREEN}    ✔ 硬件支持 AES-NI，性能满血。${NC}"
    else
        export CPU_HAS_AES=0
        echo -e "${YELLOW}    ! 未探测到 AES-NI，将使用软件模拟。${NC}"
    fi
    
    export LOGICAL_CPU_CORES=$(nproc 2>/dev/null || echo 1)
    echo -e "${GREEN}    ✔ 识别到 ${LOGICAL_CPU_CORES} 个逻辑核心。${NC}"

    if [[ -d "/sys/devices/system/cpu/cpu0/cpufreq" ]]; then
        echo -e "${CYAN} -> [算力越狱] 强锁全核心频率至 Performance 模式...${NC}"
        for cpu in /sys/devices/system/cpu/cpu[0-9]*; do
            echo "performance" > "$cpu/cpufreq/scaling_governor" 2>/dev/null || true
        done
        echo -e "${GREEN}    ✔ CPU 已锁定最高 P-State。${NC}"
    fi
}

enable_rps_rfs_and_offload() {
    echo -e "${CYAN} -> [网卡硬解] 接管物理驱动栈 (Offload/RPS/RFS/XPS)...${NC}"
    local INTERFACE=$(ip route get 8.8.8.8 2>/dev/null | awk '{for(i=1;i<=NF;i++) if($i=="dev") print $(i+1)}' | head -n 1)
    [[ -z "$INTERFACE" ]] && INTERFACE=$(ip link | awk -F: '$0 !~ "lo|vir|wl|^[^0-9]"{print $2;getline}' | head -n 1 | tr -d ' ')
    
    if [[ -n "$INTERFACE" ]]; then
        if command -v ethtool >/dev/null 2>&1; then
            ethtool -K "$INTERFACE" tso on gso on gro on rx-checksum on tx-checksum on 2>/dev/null || true
            local max_rx=$(ethtool -g "$INTERFACE" 2>/dev/null | grep -i "RX:" | head -n 1 | awk '{print $2}')
            [[ -n "$max_rx" && "$max_rx" =~ ^[0-9]+$ ]] && ethtool -G "$INTERFACE" rx "$max_rx" tx "$max_rx" 2>/dev/null || true
            echo -e "${GREEN}    ✔ 网卡硬件级卸载已稳健激活。${NC}"
        fi

        if [[ -d "/sys/class/net/$INTERFACE/queues" ]]; then
            local cpu_count=$(nproc)
            local rps_mask=$(printf "%x" $(( (1 << cpu_count) - 1 )))
            
            # [语法修复] 取消 for 循环声明处的重定向，改为内部执行时安全跳过
            for rps_flow in /sys/class/net/$INTERFACE/queues/rx-*/rps_cpus; do
                [[ -f "$rps_flow" ]] && echo "$rps_mask" > "$rps_flow" 2>/dev/null || true
            done
            for xps_flow in /sys/class/net/$INTERFACE/queues/tx-*/xps_cpus; do
                [[ -f "$xps_flow" ]] && echo "$rps_mask" > "$xps_flow" 2>/dev/null || true
            done
            echo 65536 > /proc/sys/net/core/rps_sock_flow_entries 2>/dev/null || true
            for rfc_flow in /sys/class/net/$INTERFACE/queues/rx-*/rps_flow_cnt; do
                [[ -f "$rfc_flow" ]] && echo 32768 > "$rfc_flow" 2>/dev/null || true
            done
            
            echo -e "${GREEN}    ✔ 网络软中断已均衡至全核心 (RPS/XPS)。${NC}"
        fi
    fi
}

calibrate_system_clock() {
    # [秒进修复] 时钟同步放入后台独立进程池运行，彻底剥离阻塞，绝不卡顿主线程
    (
        if command -v chronyc >/dev/null 2>&1; then
            chronyc makestep >/dev/null 2>&1
        elif command -v ntpdate >/dev/null 2>&1; then
            ntpdate -u pool.ntp.org >/dev/null 2>&1
        else
            local HTTP_DATE=$(curl -s --head -m 5 http://google.com | grep ^Date: | sed 's/Date: //g' || true)
            [[ -n "$HTTP_DATE" ]] && date -s "$HTTP_DATE" >/dev/null 2>&1 || true
        fi
    ) >/dev/null 2>&1 &
}

# ====================================================================
# 基础环境初始化 (秒开版)
# ====================================================================
init_system_environment() {
    if [[ -n $(find /etc -name "redhat-release" 2>/dev/null) ]] || grep </proc/version -q -i "centos" || grep -q -i "almalinux" /etc/os-release 2>/dev/null || grep -q -i "rocky" /etc/os-release 2>/dev/null; then
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
        echo -e "${RED}\n[!] 异常中断: Aio-box 无法适配当前异构系统。\n${NC}"
        exit 1
    fi

    if command -v systemctl >/dev/null 2>&1; then
        INIT_SYS="systemd"
    elif command -v rc-service >/dev/null 2>&1; then
        INIT_SYS="openrc"
    else
        echo -e "${RED}[!] 异常: 未找到 Systemd/OpenRC！${NC}"
        exit 1
    fi

    # 仅在初次或环境缺失时安装依赖，平时静默跳过
    if ! command -v jq >/dev/null || ! command -v fuser >/dev/null || ! command -v unzip >/dev/null || ! command -v qrencode >/dev/null || ! command -v iptables >/dev/null || ! command -v numactl >/dev/null || ! command -v ethtool >/dev/null; then
        echo -e "${YELLOW}[*] 初次运行，正在初始化核心依赖包 (OS: ${release})...${NC}"
        
        if [[ "${release}" == "ubuntu" || "${release}" == "debian" ]]; then
            apt-get update -y -q >/dev/null 2>&1
        elif [[ "${release}" == "centos" ]]; then
            yum makecache -y -q >/dev/null 2>&1
            ${installType} epel-release >/dev/null 2>&1
        elif [[ "${release}" == "alpine" ]]; then
            apk update -q >/dev/null 2>&1
        fi
        
        local deps=(wget curl jq openssl python3 bc unzip vnstat iptables tar psmisc lsof qrencode ca-certificates grep awk sed dirmngr xz-utils coreutils ethtool numactl)
        has_ipv6 && deps+=(ip6tables)
        
        if [[ "${release}" == "ubuntu" || "${release}" == "debian" ]]; then
            deps+=(cron uuid-runtime iptables-persistent netfilter-persistent fail2ban irqbalance)
        elif [[ "${release}" == "centos" ]]; then
            deps+=(cronie util-linux bind-utils firewalld iproute fail2ban ntpdate irqbalance)
        elif [[ "${release}" == "alpine" ]]; then
            deps+=(util-linux bind-tools coreutils iproute2 procps fail2ban chrony irqbalance)
        fi
        
        ${installType} "${deps[@]}" >/dev/null 2>&1
        hash -r 2>/dev/null || true
        
        if [[ "$INIT_SYS" == "systemd" ]]; then
            service_manager start cron crond vnstat fail2ban irqbalance 2>/dev/null || true
        elif [[ "$INIT_SYS" == "openrc" ]]; then
            service_manager start crond vnstatd fail2ban irqbalance 2>/dev/null || true
        fi
    fi

    IPT=$(command -v iptables || echo "/sbin/iptables")
    has_ipv6 && IPT6=$(command -v ip6tables || echo "/sbin/ip6tables") || IPT6="true"
}

get_architecture() {
    local ARCH=$(uname -m)
    case "$ARCH" in
        x86_64|amd64) XRAY_ARCH="64"; SB_ARCH="amd64"; HY2_ARCH="amd64" ;;
        aarch64|armv8) XRAY_ARCH="arm64-v8a"; SB_ARCH="arm64"; HY2_ARCH="arm64" ;;
        riscv64) XRAY_ARCH="riscv64"; SB_ARCH="riscv64"; HY2_ARCH="riscv64" ;;
        s390x) XRAY_ARCH="s390x"; SB_ARCH="s390x"; HY2_ARCH="s390x" ;;
        *) echo -e "${RED}[!] 异常: 无法解析 CPU 架构: $ARCH${NC}"; exit 1 ;;
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
        tr -dc 'a-f0-9' < /dev/urandom | head -c 32 | sed 's/^\(........\)\(....\)\(....\)\(....\)\(............\)$/\1-\2-\3-\4-\5/'
    fi
}

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

save_firewall_rules() {
    command -v netfilter-persistent >/dev/null 2>&1 && netfilter-persistent save >/dev/null 2>&1
    command -v rc-service >/dev/null 2>&1 && rc-service iptables save >/dev/null 2>&1
}

allowPort() {
    local port=$1
    local type=${2:-tcp}
    
    if command -v iptables >/dev/null 2>&1; then
        if [[ "$type" == "tcp" ]] && ! $IPT -C INPUT -p tcp --dport "${port}" --syn -m limit --limit 200/s --limit-burst 500 -j ACCEPT 2>/dev/null; then
             $IPT -I INPUT -p tcp --dport "${port}" --syn -m limit --limit 200/s --limit-burst 500 -m comment --comment "Aio-box-SYN-Mitigation" -j ACCEPT >/dev/null 2>&1
        fi
    fi

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
    while $IPT -w -t nat -S PREROUTING 2>/dev/null | grep -q "20000:50000"; do
        local LOCAL_RULE=$($IPT -w -t nat -S PREROUTING 2>/dev/null | grep "20000:50000" | head -n 1 | sed 's/^-A /-D /')
        [[ -z "$LOCAL_RULE" ]] && break
        eval $IPT -w -t nat $LOCAL_RULE 2>/dev/null || break
    done
    if has_ipv6; then
        while $IPT6 -w -t nat -S PREROUTING 2>/dev/null | grep -q "20000:50000"; do
            local LOCAL_RULE6=$($IPT6 -w -t nat -S PREROUTING 2>/dev/null | grep "20000:50000" | head -n 1 | sed 's/^-A /-D /')
            [[ -z "$LOCAL_RULE6" ]] && break
            eval $IPT6 -w -t nat $LOCAL_RULE6 2>/dev/null || break
        done
    fi
}

clean_input_rules() {
    while $IPT -w -S INPUT 2>/dev/null | grep -qE "Aio-box-|Aio-box-SYN-Mitigation"; do
        local LOCAL_RULE=$($IPT -w -S INPUT 2>/dev/null | grep -E "Aio-box-|Aio-box-SYN-Mitigation" | head -n 1 | sed 's/^-A /-D /')
        [[ -z "$LOCAL_RULE" ]] && break
        eval $IPT -w $LOCAL_RULE 2>/dev/null || break
    done
    if has_ipv6; then
        while $IPT6 -w -S INPUT 2>/dev/null | grep -q "Aio-box-"; do
            local LOCAL_RULE6=$($IPT6 -w -S INPUT 2>/dev/null | grep "Aio-box-" | head -n 1 | sed 's/^-A /-D /')
            [[ -z "$LOCAL_RULE6" ]] && break
            eval $IPT6 -w $LOCAL_RULE6 2>/dev/null || break
        done
    fi
}

release_ports() {
    echo -e "${YELLOW}[*] 执行系统级死锁句柄清理...${NC}"
    service_manager stop xray sing-box hysteria
    killall -9 xray sing-box hysteria 2>/dev/null || true
    
    local ports_to_clean=($VLESS_PORT $HY2_PORT $SS_PORT 443 8443 2053)
    for p in $(echo "${ports_to_clean[@]}" | tr ' ' '\n' | sort -u); do
        fuser -k -9 "${p}/tcp" 2>/dev/null || true
        fuser -k -9 "${p}/udp" 2>/dev/null || true
        local PIDS=$(lsof -ti:"${p}" 2>/dev/null)
        if [[ -n "$PIDS" ]]; then
            for pid in $PIDS; do
                kill -9 "$pid" 2>/dev/null || true
            done
        fi
    done
    sleep 1
}

setup_shortcut() {
    mkdir -p /etc/ddr
    # [自愈机制] 如果快捷脚本不存在，或者缺少最新版标识，自动强制从远端下载覆盖！解决报错死循环
    if [[ ! -f /etc/ddr/aio.sh ]] || ! grep -q "V9.9 Final Perfected (Speed Edition)" /etc/ddr/aio.sh 2>/dev/null || [[ "$1" == "update" ]]; then
        curl -fLs --connect-timeout 10 "https://raw.githubusercontent.com/alariclin/aio-box/main/install.sh" > /tmp/aio.sh.tmp && mv -f /tmp/aio.sh.tmp /etc/ddr/aio.sh
        chmod +x /etc/ddr/aio.sh
    fi
    if [[ ! -f /usr/local/bin/sb ]]; then
        printf '#!/bin/bash\nsudo bash /etc/ddr/aio.sh "$@"\n' > /usr/local/bin/sb
        chmod +x /usr/local/bin/sb
    fi
}

setup_geo_cron() {
    cat > /etc/ddr/geo_update.sh << 'EOF'
#!/bin/bash
PATH=/usr/local/sbin:/usr/local/bin:/sbin:/bin:/usr/sbin:/usr/bin
GEOIP_URL="https://github.com/Loyalsoldier/v2ray-rules-dat/releases/latest/download/geoip.dat"
GEOSITE_URL="https://github.com/Loyalsoldier/v2ray-rules-dat/releases/latest/download/geosite.dat"
GEOIP_SUM_URL="${GEOIP_URL}.sha256sum"
GEOSITE_SUM_URL="${GEOSITE_URL}.sha256sum"

GEO_TMP_DIR="/dev/shm/aio_geo_update"
mkdir -p "$GEO_TMP_DIR"

(curl -sL -m 60 "$GEOIP_URL" -o "$GEO_TMP_DIR/geoip.dat" || curl -sL -m 60 "https://ghp.ci/$GEOIP_URL" -o "$GEO_TMP_DIR/geoip.dat") &
(curl -sL -m 60 "$GEOSITE_URL" -o "$GEO_TMP_DIR/geosite.dat" || curl -sL -m 60 "https://ghp.ci/$GEOSITE_URL" -o "$GEO_TMP_DIR/geosite.dat") &
(curl -sL -m 30 "$GEOIP_SUM_URL" -o "$GEO_TMP_DIR/geoip.dat.sha256sum" || curl -sL -m 30 "https://ghp.ci/$GEOIP_SUM_URL" -o "$GEO_TMP_DIR/geoip.dat.sha256sum") &
(curl -sL -m 30 "$GEOSITE_SUM_URL" -o "$GEO_TMP_DIR/geosite.dat.sha256sum" || curl -sL -m 30 "https://ghp.ci/$GEOSITE_SUM_URL" -o "$GEO_TMP_DIR/geosite.dat.sha256sum") &
wait

SIZE_IP=$(wc -c < "$GEO_TMP_DIR/geoip.dat" 2>/dev/null | tr -d ' ')
SIZE_SITE=$(wc -c < "$GEO_TMP_DIR/geosite.dat" 2>/dev/null | tr -d ' ')

VALID_IP=true; VALID_SITE=true
if [[ -f "$GEO_TMP_DIR/geoip.dat.sha256sum" ]]; then
    cd "$GEO_TMP_DIR" && sha256sum -c geoip.dat.sha256sum >/dev/null 2>&1 || VALID_IP=false
fi
if [[ -f "$GEO_TMP_DIR/geosite.dat.sha256sum" ]]; then
    cd "$GEO_TMP_DIR" && sha256sum -c geosite.dat.sha256sum >/dev/null 2>&1 || VALID_SITE=false
fi

if [[ -n "$SIZE_IP" && "$SIZE_IP" -gt 500000 && "$VALID_IP" == "true" && -n "$SIZE_SITE" && "$SIZE_SITE" -gt 500000 && "$VALID_SITE" == "true" ]]; then
    if [[ -d "/usr/local/share/xray" ]]; then
        mv -f "$GEO_TMP_DIR/geoip.dat" /usr/local/share/xray/geoip.dat
        mv -f "$GEO_TMP_DIR/geosite.dat" /usr/local/share/xray/geosite.dat
        systemctl restart xray 2>/dev/null || rc-service xray restart 2>/dev/null
    fi
    if [[ -d "/etc/sing-box" ]]; then
        cp -f /usr/local/share/xray/geoip.dat /etc/sing-box/geoip.dat 2>/dev/null || mv -f "$GEO_TMP_DIR/geoip.dat" /etc/sing-box/geoip.dat 2>/dev/null
        cp -f /usr/local/share/xray/geosite.dat /etc/sing-box/geosite.dat 2>/dev/null || mv -f "$GEO_TMP_DIR/geosite.dat" /etc/sing-box/geosite.dat 2>/dev/null
        systemctl restart sing-box 2>/dev/null || rc-service sing-box restart 2>/dev/null
    fi
fi
rm -rf "$GEO_TMP_DIR"
EOF
    chmod +x /etc/ddr/geo_update.sh
    
    crontab -l 2>/dev/null | grep -v '/etc/ddr/geo_update.sh' > /tmp/cronjob || true
    echo "0 3 * * 1 /bin/bash /etc/ddr/geo_update.sh >/dev/null 2>&1" >> /tmp/cronjob
    crontab /tmp/cronjob 2>/dev/null && rm -f /tmp/cronjob
}

fetch_github_release() {
    local repo=$1; local keyword=$2; local output_file=$3
    echo -e "${YELLOW} -> 并行提取资产 (RAM-IO) [${repo}]...${NC}"
    
    local api_url="https://api.github.com/repos/${repo}/releases/latest"
    local download_url=$(curl -sL -m 10 "$api_url" | jq -r ".assets[] | select(.name | contains(\"$keyword\")) | .browser_download_url" 2>/dev/null | head -n 1)
    
    if [[ -z "$download_url" || "$download_url" == "null" ]]; then
        local release_html=$(curl -sL -m 15 "https://github.com/${repo}/releases/latest")
        local asset_path=$(echo "$release_html" | grep -oP "href=\"[^\"]*${keyword}[^\"]*\"" | head -n 1 | cut -d '"' -f 2)
        [[ -n "$asset_path" ]] && download_url="https://github.com${asset_path}"
    fi

    if [[ -z "$download_url" || "$download_url" == "null" ]]; then
        download_url=$(curl -sL -m 10 "https://ghp.ci/$api_url" | jq -r ".assets[] | select(.name | contains(\"$keyword\")) | .browser_download_url" 2>/dev/null | head -n 1)
    fi

    if [[ -z "$download_url" || "$download_url" == "null" ]]; then
        echo -e "${YELLOW} -> 全维出站阻塞，降级至备用仓库...${NC}"
        local fallback_url=""
        case "$keyword" in
            *"Xray"*) fallback_url="https://raw.githubusercontent.com/alariclin/aio-box/main/core/Xray-linux-${XRAY_ARCH}.zip" ;;
            *"sing-box"*) fallback_url="https://raw.githubusercontent.com/alariclin/aio-box/main/core/sing-box-linux-${SB_ARCH}.tar.gz" ;;
            *"hysteria"*) fallback_url="https://raw.githubusercontent.com/alariclin/aio-box/main/core/hysteria-linux-${HY2_ARCH}" ;;
        esac

        if [[ -n "$fallback_url" ]]; then
            local mirrors=("" "https://ghp.ci/" "https://mirror.ghproxy.com/")
            for mirror in "${mirrors[@]}"; do
                if curl -fLs --connect-timeout 10 "${mirror}${fallback_url}" -o "$output_file" && [[ -s "$output_file" ]]; then
                    echo -e "${GREEN}    ✔ 资产提取至内存成功！${NC}"; return 0
                fi
            done
        fi
        echo -e "${RED}[!] 致命异常: 资产下载完全失败。${NC}"; exit 1
    fi

    local mirrors=("" "https://ghp.ci/" "https://mirror.ghproxy.com/")
    for mirror in "${mirrors[@]}"; do
        if curl -fLs --connect-timeout 15 -m 120 "${mirror}${download_url}" -o "$output_file" && [[ -s "$output_file" ]]; then
            echo -e "${GREEN}    ✔ 核心资产提取成功！${NC}"; return 0
        fi
    done
    echo -e "${RED}[!] 致命异常: 目标源响应超时。${NC}"; exit 1
}

fetch_geo_data() {
    local file_name=$1; local official_url=$2
    local mirrors=("" "https://ghp.ci/" "https://mirror.ghproxy.com/")
    for mirror in "${mirrors[@]}"; do
        if curl -fLs --connect-timeout 10 -m 60 "${mirror}${official_url}" -o "$file_name" && [[ -s "$file_name" ]]; then return 0; fi
    done
    
    local fallback_geo_url="https://raw.githubusercontent.com/alariclin/aio-box/main/core/$(basename "$file_name")"
    for mirror in "${mirrors[@]}"; do
        if curl -fLs --connect-timeout 10 -m 60 "${mirror}${fallback_geo_url}" -o "$file_name" && [[ -s "$file_name" ]]; then
            echo -e "${GREEN}    ✔ Geo 数据回源提取成功！${NC}"; return 0
        fi
    done
    echo -e "${RED}[!] 致命异常: 路由数据库下载失败！${NC}"; exit 1
}

pre_install_setup() {
    local CORE=$1; local MODE=$2
    local DEF_V_SNI="www.microsoft.com"; local DEF_H_SNI="images.apple.com"
    local DEF_V_PORT=443; local DEF_H_PORT=443; local DEF_S_PORT=2053

    echo -e "\n${CYAN}======================================================================${NC}"
    echo -e "${BOLD}🚀 配置向导 [Engine: $CORE | Mode: $MODE]${NC}"
    echo -e "${BLUE}----------------------------------------------------------------------${NC}"

    if [[ "$MODE" == *"VLESS"* || "$MODE" == *"ALL"* ]]; then
        read -t 300 -ep "   [VLESS] 伪装 SNI (回车默认: $DEF_V_SNI): " INPUT_V_SNI || INPUT_V_SNI=""
        VLESS_SNI=${INPUT_V_SNI:-$DEF_V_SNI}
        read -t 300 -ep "   [VLESS] 监听端口 (回车默认: $DEF_V_PORT): " INPUT_V_PORT || INPUT_V_PORT=""
        VLESS_PORT=${INPUT_V_PORT:-$DEF_V_PORT}
    fi

    if [[ "$MODE" == *"HY2"* || "$MODE" == *"ALL"* ]]; then
        read -t 300 -ep "   [HY2] 伪装 SNI (回车默认: $DEF_H_SNI): " INPUT_H_SNI || INPUT_H_SNI=""
        HY2_SNI=${INPUT_H_SNI:-$DEF_H_SNI}
        read -t 300 -ep "   [HY2] 监听端口 (回车默认: $DEF_H_PORT): " INPUT_H_PORT || INPUT_H_PORT=""
        HY2_PORT=${INPUT_H_PORT:-$DEF_H_PORT}
    fi

    if [[ "$MODE" == *"SS"* || "$MODE" == *"ALL"* ]]; then
        read -t 300 -ep "   [SS] 监听端口 (回车默认: $DEF_S_PORT): " INPUT_S_PORT || INPUT_S_PORT=""
        SS_PORT=${INPUT_S_PORT:-$DEF_S_PORT}
    fi
    echo -e "${CYAN}======================================================================${NC}\n"

    VLESS_SNI=${VLESS_SNI:-$DEF_V_SNI}; HY2_SNI=${HY2_SNI:-$DEF_H_SNI}
    VLESS_PORT=${VLESS_PORT:-$DEF_V_PORT}; HY2_PORT=${HY2_PORT:-$DEF_H_PORT}; SS_PORT=${SS_PORT:-$DEF_S_PORT}
    
    [[ "$MODE" == *"VLESS"* || "$MODE" == *"ALL"* ]] && allowPort "$VLESS_PORT" "tcp"
    [[ "$MODE" == *"HY2"* || "$MODE" == *"ALL"* ]] && allowPort "$HY2_PORT" "udp"
    [[ "$MODE" == *"SS"* || "$MODE" == *"ALL"* ]] && { allowPort "$SS_PORT" "tcp"; allowPort "$SS_PORT" "udp"; }
}

# ====================================================================
# 核心部署模块 (调用重资源函数)
# ====================================================================
deploy_official_hy2() {
    local IS_SILENT=$1
    if [[ "$IS_SILENT" != "SILENT" ]]; then 
        clear; echo -e "${BOLD}${GREEN} 部署 Hysteria 2 (原生) ${NC}"
        # 真正开始安装时，才拉起高能效审计和时钟对齐
        audit_hardware_resources
        enable_rps_rfs_and_offload
        calibrate_system_clock
        pre_install_setup "hysteria" "HY2"
        release_ports
        get_architecture
    fi
    
    mkdir -p /dev/shm/aio_box_core
    fetch_github_release "apernet/hysteria" "hysteria-linux-${HY2_ARCH}" "/dev/shm/aio_box_core/hysteria_core"
    mv /dev/shm/aio_box_core/hysteria_core /usr/local/bin/hysteria; chmod +x /usr/local/bin/hysteria
    rm -rf /dev/shm/aio_box_core
    
    HY2_PASS=$(head -c 24 /dev/urandom | base64 | tr -dc 'a-zA-Z0-9' | head -c 12)
    HY2_OBFS=$(head -c 24 /dev/urandom | base64 | tr -dc 'a-zA-Z0-9' | head -c 8)
    
    mkdir -p /etc/hysteria; openssl ecparam -genkey -name prime256v1 -out /etc/hysteria/server.key 2>/dev/null
    openssl req -new -x509 -days 36500 -key /etc/hysteria/server.key -out /etc/hysteria/server.crt -subj "/CN=${HY2_SNI}" 2>/dev/null

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

    if [[ "$INIT_SYS" == "systemd" ]]; then
        cat > /etc/systemd/system/hysteria.service << SVC_EOF
[Unit]
Description=Hysteria 2 Service
After=network.target
[Service]
Environment="GOMAXPROCS=${LOGICAL_CPU_CORES}"
Environment="GOGC=100"
Environment="GOMEMLIMIT=${GOMEMLIMIT_MB}MiB"
LimitRTPRIO=infinity
CPUSchedulingPolicy=fifo
CPUSchedulingPriority=40
IOSchedulingClass=realtime
IOSchedulingPriority=0
OOMScoreAdjust=-500
CapabilityBoundingSet=CAP_NET_ADMIN CAP_NET_BIND_SERVICE CAP_SYS_PTRACE CAP_DAC_READ_SEARCH CAP_SYS_NICE
AmbientCapabilities=CAP_NET_ADMIN CAP_NET_BIND_SERVICE CAP_SYS_PTRACE CAP_DAC_READ_SEARCH CAP_SYS_NICE
ExecStartPre=-/bin/sh -c '$IPT -w -t nat -D PREROUTING -p udp --dport 20000:50000 -j REDIRECT --to-ports $HY2_PORT 2>/dev/null || true'
$(has_ipv6 && echo "ExecStartPre=-/bin/sh -c '$IPT6 -w -t nat -D PREROUTING -p udp --dport 20000:50000 -j REDIRECT --to-ports $HY2_PORT 2>/dev/null || true'")
ExecStartPre=-/bin/sh -c '$IPT -w -t nat -A PREROUTING -p udp --dport 20000:50000 -j REDIRECT --to-ports $HY2_PORT 2>/dev/null || true'
$(has_ipv6 && echo "ExecStartPre=-/bin/sh -c '$IPT6 -w -t nat -A PREROUTING -p udp --dport 20000:50000 -j REDIRECT --to-ports $HY2_PORT 2>/dev/null || true'")
ExecStart=/usr/local/bin/hysteria server -c /etc/hysteria/config.yaml
ExecStopPost=-/bin/sh -c '$IPT -w -t nat -D PREROUTING -p udp --dport 20000:50000 -j REDIRECT --to-ports $HY2_PORT 2>/dev/null || true'
$(has_ipv6 && echo "ExecStopPost=-/bin/sh -c '$IPT6 -w -t nat -D PREROUTING -p udp --dport 20000:50000 -j REDIRECT --to-ports $HY2_PORT 2>/dev/null || true'")
Restart=always
RestartSec=10
LimitNOFILE=1048576
LimitNPROC=1048576
LimitMEMLOCK=infinity
LimitCORE=0
[Install]
WantedBy=multi-user.target
SVC_EOF
    elif [[ "$INIT_SYS" == "openrc" ]]; then
        mkdir -p /etc/conf.d; echo 'rc_ulimit="-n 1048576 -c 0 -l unlimited"' > /etc/conf.d/hysteria
        cat > /etc/init.d/hysteria << SVC_EOF
#!/sbin/openrc-run
description="Hysteria 2 Service"
export GOMAXPROCS=${LOGICAL_CPU_CORES}
export GOGC=100
export GOMEMLIMIT=${GOMEMLIMIT_MB}MiB
command="/usr/local/bin/hysteria"
command_args="server -c /etc/hysteria/config.yaml"
command_background="yes"
pidfile="/run/hysteria.pid"
depend() { need net; }
start_pre() {
  $IPT -w -t nat -D PREROUTING -p udp --dport 20000:50000 -j REDIRECT --to-ports $HY2_PORT 2>/dev/null || true
  $(has_ipv6 && echo "$IPT6 -w -t nat -D PREROUTING -p udp --dport 20000:50000 -j REDIRECT --to-ports $HY2_PORT 2>/dev/null || true")
  $IPT -w -t nat -A PREROUTING -p udp --dport 20000:50000 -j REDIRECT --to-ports $HY2_PORT 2>/dev/null || true
  $(has_ipv6 && echo "$IPT6 -w -t nat -A PREROUTING -p udp --dport 20000:50000 -j REDIRECT --to-ports $HY2_PORT 2>/dev/null || true")
  return 0
}
stop_post() {
  $IPT -w -t nat -D PREROUTING -p udp --dport 20000:50000 -j REDIRECT --to-ports $HY2_PORT 2>/dev/null || true
  $(has_ipv6 && echo "$IPT6 -w -t nat -D PREROUTING -p udp --dport 20000:50000 -j REDIRECT --to-ports $HY2_PORT 2>/dev/null || true")
  return 0
}
SVC_EOF
        chmod +x /etc/init.d/hysteria
    fi

    service_manager start hysteria
    sleep 2; is_service_running hysteria || { echo -e "${RED}[!] 错误：Hysteria 2 启动失败！${NC}"; exit 1; }

    setup_geo_cron

    if [[ "$IS_SILENT" != "SILENT" ]]; then
        cat > /etc/ddr/.env << ENV_EOF
CORE="hysteria"; MODE="HY2"; UUID=""; VLESS_SNI=""; VLESS_PORT=""; HY2_SNI="$HY2_SNI"; HY2_PORT="$HY2_PORT"; SS_PORT=""; PUBLIC_KEY=""; SHORT_ID=""; HY2_PASS="$HY2_PASS"; HY2_OBFS="$HY2_OBFS"; SS_PASS=""; LINK_IP="${GLOBAL_PUBLIC_IP}"
ENV_EOF
        view_config "deploy"
    fi
}

deploy_xray() {
    local MODE=$1; clear; echo -e "${BOLD}${GREEN} 部署 Xray-core [$MODE] ${NC}"
    # 按需唤醒底层性能架构
    audit_hardware_resources
    enable_rps_rfs_and_offload
    calibrate_system_clock
    pre_install_setup "xray" "$MODE"; release_ports; get_architecture
    
    mkdir -p /dev/shm/aio_box_core
    fetch_github_release "XTLS/Xray-core" "Xray-linux-${XRAY_ARCH}.zip" "/dev/shm/aio_box_core/xray_core.zip"
    
    (fetch_geo_data "/dev/shm/aio_box_core/geoip.dat" "https://github.com/Loyalsoldier/v2ray-rules-dat/releases/latest/download/geoip.dat") &
    (fetch_geo_data "/dev/shm/aio_box_core/geosite.dat" "https://github.com/Loyalsoldier/v2ray-rules-dat/releases/latest/download/geosite.dat") &
    wait
    
    mkdir -p /dev/shm/aio_box_core/ext
    unzip -qo "/dev/shm/aio_box_core/xray_core.zip" -d /dev/shm/aio_box_core/ext || { echo -e "${RED}[!] 异常: 解压失败！${NC}"; exit 1; }
    mv /dev/shm/aio_box_core/ext/xray /usr/local/bin/xray; chmod +x /usr/local/bin/xray
    mkdir -p /usr/local/share/xray /usr/local/etc/xray
    mv /dev/shm/aio_box_core/geoip.dat /usr/local/share/xray/; mv /dev/shm/aio_box_core/geosite.dat /usr/local/share/xray/
    rm -rf /dev/shm/aio_box_core
    
    KEYPAIR=$(/usr/local/bin/xray x25519)
    PK=$(echo "$KEYPAIR" | grep -i "Private" | awk '{print $NF}')
    PBK=$(echo "$KEYPAIR" | grep -i "Public" | awk '{print $NF}')
    [[ -z "$PK" ]] && { echo -e "${RED}[!] 异常: 密钥生成失败！${NC}"; exit 1; }
    
    UUID=$(generate_robust_uuid); 
    SHORT_ID=$(head -c 16 /dev/urandom | xxd -p | head -c 8)
    SS_PASS=$(head -c 24 /dev/urandom | base64 | tr -dc 'a-zA-Z0-9' | head -c 16)

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
      { "type": "field", "protocol": ["bittorrent"], "outboundTag": "block" }
    ]
  },
  "inbounds": ${INBOUNDS},
  "outbounds": [
    { "protocol": "freedom", "tag": "direct" },
    { "protocol": "blackhole", "tag": "block" }
  ]
}
EOF

    if [[ "$INIT_SYS" == "systemd" ]]; then
        cat > /etc/systemd/system/xray.service << SVC_EOF
[Unit]
Description=Xray Service
After=network.target nss-lookup.target
[Service]
Environment="GOMAXPROCS=${LOGICAL_CPU_CORES}"
Environment="GOGC=100"
Environment="GOMEMLIMIT=${GOMEMLIMIT_MB}MiB"
LimitRTPRIO=infinity
CPUSchedulingPolicy=fifo
CPUSchedulingPriority=40
IOSchedulingClass=realtime
IOSchedulingPriority=0
OOMScoreAdjust=-500
CapabilityBoundingSet=CAP_NET_ADMIN CAP_NET_BIND_SERVICE CAP_SYS_PTRACE CAP_DAC_READ_SEARCH CAP_SYS_NICE
AmbientCapabilities=CAP_NET_ADMIN CAP_NET_BIND_SERVICE CAP_SYS_PTRACE CAP_DAC_READ_SEARCH CAP_SYS_NICE
ExecStart=/usr/local/bin/xray run -config /usr/local/etc/xray/config.json
Restart=always
RestartSec=10
LimitNOFILE=1048576
LimitNPROC=1048576
LimitMEMLOCK=infinity
LimitCORE=0
[Install]
WantedBy=multi-user.target
SVC_EOF
    elif [[ "$INIT_SYS" == "openrc" ]]; then
        mkdir -p /etc/conf.d; echo 'rc_ulimit="-n 1048576 -c 0 -l unlimited"' > /etc/conf.d/xray
        cat > /etc/init.d/xray << SVC_EOF
#!/sbin/openrc-run
description="Xray Service"
export GOMAXPROCS=${LOGICAL_CPU_CORES}
export GOGC=100
export GOMEMLIMIT=${GOMEMLIMIT_MB}MiB
command="/usr/local/bin/xray"
command_args="run -config /usr/local/etc/xray/config.json"
command_background="yes"
pidfile="/run/xray.pid"
depend() { need net; }
SVC_EOF
        chmod +x /etc/init.d/xray
    fi

    service_manager start xray
    sleep 2; is_service_running xray || { echo -e "${RED}[!] 错误：Xray 启动失败！${NC}"; exit 1; }

    setup_geo_cron

    if [[ "$MODE" == "ALL" ]]; then
        deploy_official_hy2 "SILENT"
    fi

    cat > /etc/ddr/.env << ENV_EOF
CORE="xray"; MODE="$MODE"; UUID="$UUID"; VLESS_SNI="$VLESS_SNI"; VLESS_PORT="$VLESS_PORT"; HY2_SNI="$HY2_SNI"; HY2_PORT="$HY2_PORT"; SS_PORT="$SS_PORT"; PUBLIC_KEY="$PBK"; SHORT_ID="$SHORT_ID"; HY2_PASS="$HY2_PASS"; HY2_OBFS="$HY2_OBFS"; SS_PASS="$SS_PASS"; LINK_IP="${GLOBAL_PUBLIC_IP}"
ENV_EOF
    view_config "deploy"
}

deploy_singbox() {
    local MODE=$1; clear; echo -e "${BOLD}${GREEN} 部署 Sing-box 聚合引擎 [$MODE] ${NC}"
    # 按需唤醒底层性能架构
    audit_hardware_resources
    enable_rps_rfs_and_offload
    calibrate_system_clock
    pre_install_setup "singbox" "$MODE"; release_ports; get_architecture
    
    mkdir -p /dev/shm/aio_box_core
    fetch_github_release "SagerNet/sing-box" "linux-${SB_ARCH}.tar.gz" "/dev/shm/aio_box_core/singbox_core.tar.gz"
    tar -xzf "/dev/shm/aio_box_core/singbox_core.tar.gz" -C /dev/shm/aio_box_core || { echo -e "${RED}[!] 异常: 提取失败！${NC}"; exit 1; }
    
    if [[ -f /dev/shm/aio_box_core/sing-box ]]; then
        mv /dev/shm/aio_box_core/sing-box /usr/local/bin/sing-box
    else
        find /dev/shm/aio_box_core/sing-box-* -maxdepth 1 -type f -name "sing-box" -exec mv {} /usr/local/bin/sing-box \; -quit 2>/dev/null
    fi
    chmod +x /usr/local/bin/sing-box
    rm -rf /dev/shm/aio_box_core

    KEYPAIR=$(/usr/local/bin/sing-box generate reality-keypair)
    PK=$(echo "$KEYPAIR" | grep -i "Private" | awk '{print $NF}')
    PBK=$(echo "$KEYPAIR" | grep -i "Public" | awk '{print $NF}')
    [[ -z "$PK" ]] && { echo -e "${RED}[!] 异常: 签名失败！${NC}"; exit 1; }

    UUID=$(generate_robust_uuid); 
    SHORT_ID=$(head -c 16 /dev/urandom | xxd -p | head -c 8)
    SS_PASS=$(head -c 24 /dev/urandom | base64 | tr -dc 'a-zA-Z0-9' | head -c 16)
    HY2_PASS=$(head -c 24 /dev/urandom | base64 | tr -dc 'a-zA-Z0-9' | head -c 12)
    HY2_OBFS=$(head -c 24 /dev/urandom | base64 | tr -dc 'a-zA-Z0-9' | head -c 8)
    
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

    if [[ "$INIT_SYS" == "systemd" ]]; then
        cat > /etc/systemd/system/sing-box.service << SVC_EOF
[Unit]
Description=Sing-Box Service
After=network.target nss-lookup.target
[Service]
Environment="GOMAXPROCS=${LOGICAL_CPU_CORES}"
Environment="GOGC=100"
Environment="GOMEMLIMIT=${GOMEMLIMIT_MB}MiB"
LimitRTPRIO=infinity
CPUSchedulingPolicy=fifo
CPUSchedulingPriority=40
IOSchedulingClass=realtime
IOSchedulingPriority=0
OOMScoreAdjust=-500
CapabilityBoundingSet=CAP_NET_ADMIN CAP_NET_BIND_SERVICE CAP_SYS_PTRACE CAP_DAC_READ_SEARCH CAP_SYS_NICE
AmbientCapabilities=CAP_NET_ADMIN CAP_NET_BIND_SERVICE CAP_SYS_PTRACE CAP_DAC_READ_SEARCH CAP_SYS_NICE
$(if [[ "$MODE" == *"HY2"* ]] || [[ "$MODE" == *"ALL"* ]]; then 
    echo -e "ExecStartPre=-/bin/sh -c '$IPT -w -t nat -D PREROUTING -p udp --dport 20000:50000 -j REDIRECT --to-ports $HY2_PORT 2>/dev/null || true'"
    has_ipv6 && echo -e "ExecStartPre=-/bin/sh -c '$IPT6 -w -t nat -D PREROUTING -p udp --dport 20000:50000 -j REDIRECT --to-ports $HY2_PORT 2>/dev/null || true'"
    echo -e "ExecStartPre=-/bin/sh -c '$IPT -w -t nat -A PREROUTING -p udp --dport 20000:50000 -j REDIRECT --to-ports $HY2_PORT 2>/dev/null || true'"
    has_ipv6 && echo -e "ExecStartPre=-/bin/sh -c '$IPT6 -w -t nat -A PREROUTING -p udp --dport 20000:50000 -j REDIRECT --to-ports $HY2_PORT 2>/dev/null || true'"
fi)
ExecStart=/usr/local/bin/sing-box run -c /etc/sing-box/config.json
$(if [[ "$MODE" == *"HY2"* ]] || [[ "$MODE" == *"ALL"* ]]; then 
    echo -e "ExecStopPost=-/bin/sh -c '$IPT -w -t nat -D PREROUTING -p udp --dport 20000:50000 -j REDIRECT --to-ports $HY2_PORT 2>/dev/null || true'"
    has_ipv6 && echo -e "ExecStopPost=-/bin/sh -c '$IPT6 -w -t nat -D PREROUTING -p udp --dport 20000:50000 -j REDIRECT --to-ports $HY2_PORT 2>/dev/null || true'"
fi)
Restart=always
RestartSec=10
LimitNOFILE=1048576
LimitNPROC=1048576
LimitMEMLOCK=infinity
LimitCORE=0
[Install]
WantedBy=multi-user.target
SVC_EOF
    elif [[ "$INIT_SYS" == "openrc" ]]; then
        mkdir -p /etc/conf.d
        echo 'rc_ulimit="-n 1048576 -c 0 -l unlimited"' > /etc/conf.d/sing-box
        cat > /etc/init.d/sing-box << SVC_EOF
#!/sbin/openrc-run
description="Sing-Box Service"
export GOMAXPROCS=${LOGICAL_CPU_CORES}
export GOGC=100
export GOMEMLIMIT=${GOMEMLIMIT_MB}MiB
command="/usr/local/bin/sing-box"
command_args="run -c /etc/sing-box/config.json"
command_background="yes"
pidfile="/run/sing-box.pid"
depend() { need net; }
$(if [[ "$MODE" == *"HY2"* ]] || [[ "$MODE" == *"ALL"* ]]; then echo "start_pre() {
  $IPT -w -t nat -D PREROUTING -p udp --dport 20000:50000 -j REDIRECT --to-ports $HY2_PORT 2>/dev/null || true
  $(has_ipv6 && echo "$IPT6 -w -t nat -D PREROUTING -p udp --dport 20000:50000 -j REDIRECT --to-ports $HY2_PORT 2>/dev/null || true")
  $IPT -w -t nat -A PREROUTING -p udp --dport 20000:50000 -j REDIRECT --to-ports $HY2_PORT 2>/dev/null || true
  $(has_ipv6 && echo "$IPT6 -w -t nat -A PREROUTING -p udp --dport 20000:50000 -j REDIRECT --to-ports $HY2_PORT 2>/dev/null || true")
  return 0
}
stop_post() {
  $IPT -w -t nat -D PREROUTING -p udp --dport 20000:50000 -j REDIRECT --to-ports $HY2_PORT 2>/dev/null || true
  $(has_ipv6 && echo "$IPT6 -w -t nat -D PREROUTING -p udp --dport 20000:50000 -j REDIRECT --to-ports $HY2_PORT 2>/dev/null || true")
  return 0
}"; fi)
SVC_EOF
        chmod +x /etc/init.d/sing-box
    fi

    service_manager start sing-box
    sleep 2; is_service_running sing-box || { echo -e "${RED}[!] 错误：Sing-box 启动失败！${NC}"; exit 1; }

    setup_geo_cron

    cat > /etc/ddr/.env << ENV_EOF
CORE="singbox"; MODE="$MODE"; UUID="$UUID"; VLESS_SNI="$VLESS_SNI"; VLESS_PORT="$VLESS_PORT"; HY2_SNI="$HY2_SNI"; HY2_PORT="$HY2_PORT"; SS_PORT="$SS_PORT"; PUBLIC_KEY="$PBK"; SHORT_ID="$SHORT_ID"; HY2_PASS="$HY2_PASS"; HY2_OBFS="$HY2_OBFS"; SS_PASS="$SS_PASS"; LINK_IP="${GLOBAL_PUBLIC_IP}"
ENV_EOF
    view_config "deploy"
}

setup_traffic_monitor() {
    cat > /etc/ddr/traffic_monitor.sh << 'EOF'
#!/bin/bash
PATH=/usr/local/sbin:/usr/local/bin:/sbin:/bin:/usr/sbin:/usr/bin
source /etc/ddr/.env
if [[ -z "$TRAFFIC_LIMIT_GB" ]]; then
    exit 0
fi

INTERFACE=$(ip route get 8.8.8.8 2>/dev/null | awk '{for(i=1;i<=NF;i++) if($i=="dev") print $(i+1)}' | head -n 1)
if [[ -z "$INTERFACE" ]]; then
    INTERFACE=$(ip link | awk -F: '$0 !~ "lo|vir|wl|^[^0-9]"{print $2;getline}' | head -n 1 | tr -d ' ')
fi

if vnstat --json >/dev/null 2>&1; then
    JSON_OUT=$(vnstat -i "$INTERFACE" --json 2>/dev/null)
    TOTAL_BYTES=$(echo "$JSON_OUT" | jq -r --arg iface "$INTERFACE" '[.interfaces[]? | select(.name == $iface) | .traffic.month[]? | select(.date.year == '$(date +%Y)' and .date.month == '$(date +%-m)')] | if length > 0 then .[0].rx + .[0].tx else 0 end' 2>/dev/null)
    
    if [[ -n "$TOTAL_BYTES" && "$TOTAL_BYTES" -gt 0 ]]; then
        USED_GB=$(echo "scale=4; $TOTAL_BYTES / 1073741824" | bc)
    else
        USED_GB=0
    fi
else
    USED_LINE=$(vnstat -i "$INTERFACE" -m 2>/dev/null | grep "$(date +'%Y-%m')")
    if [[ -n "$USED_LINE" ]]; then
        TOTAL_STR=$(echo "$USED_LINE" | awk -F'|' '{print $3}' | xargs)
        VAL=$(echo "$TOTAL_STR" | awk '{print $1}')
        UNIT=$(echo "$TOTAL_STR" | awk '{print $2}')
        
        USED_GB=0
        if [[ "$UNIT" == *"GiB"* || "$UNIT" == *"GB"* ]]; then
            USED_GB=$VAL
        elif [[ "$UNIT" == *"TiB"* || "$UNIT" == *"TB"* ]]; then
            USED_GB=$(echo "$VAL * 1024" | bc)
        elif [[ "$UNIT" == *"MiB"* || "$UNIT" == *"MB"* ]]; then
            USED_GB=$(echo "scale=2; $VAL / 1024" | bc)
        elif [[ "$UNIT" == *"KiB"* || "$UNIT" == *"KB"* ]]; then
            USED_GB=$(echo "scale=4; $VAL / 1048576" | bc)
        fi
    fi
fi

if (( $(echo "$USED_GB >= $TRAFFIC_LIMIT_GB" | bc -l) )); then
    if command -v systemctl >/dev/null 2>&1; then
        systemctl stop xray sing-box hysteria 2>/dev/null
    else
        rc-service xray stop 2>/dev/null
        rc-service sing-box stop 2>/dev/null
        rc-service hysteria stop 2>/dev/null
    fi
    killall -9 xray sing-box hysteria 2>/dev/null
fi
EOF
    chmod +x /etc/ddr/traffic_monitor.sh
    touch /tmp/cronjob
    crontab -l 2>/dev/null | grep -v '/etc/ddr/traffic_monitor.sh' > /tmp/cronjob || true
    echo "* * * * * /bin/bash /etc/ddr/traffic_monitor.sh >/dev/null 2>&1" >> /tmp/cronjob
    crontab /tmp/cronjob
    rm -f /tmp/cronjob
}

disable_traffic_monitor() {
    touch /tmp/cronjob
    crontab -l 2>/dev/null | grep -v '/etc/ddr/traffic_monitor.sh' > /tmp/cronjob || true
    crontab /tmp/cronjob 2>/dev/null
    rm -f /tmp/cronjob
    rm -f /etc/ddr/traffic_monitor.sh
}

traffic_management_menu() {
    clear
    echo -e "${CYAN}======================================================================${NC}"
    echo -e "${BOLD}${GREEN}   物理层月度流量精准管控${NC}"
    echo -e "${CYAN}======================================================================${NC}"
    
    local INTERFACE=$(ip route get 8.8.8.8 2>/dev/null | awk '{for(i=1;i<=NF;i++) if($i=="dev") print $(i+1)}' | head -n 1)
    [[ -z "$INTERFACE" ]] && INTERFACE=$(ip link | awk -F: '$0 !~ "lo|vir|wl|^[^0-9]"{print $2;getline}' | head -n 1 | tr -d ' ')
    
    echo -e "${YELLOW}[网卡 ${INTERFACE} 月度流量计量表]${NC}"
    if command -v vnstat >/dev/null 2>&1; then
        local USED_LINE=$(vnstat -i "$INTERFACE" -m 2>/dev/null | grep "$(date +'%Y-%m')")
        if [[ -n "$USED_LINE" ]]; then
            vnstat -i "$INTERFACE" -m 2>/dev/null | head -n 6 | grep -v '^$'
        else
            echo -e "${YELLOW}暂无数据...${NC}"
        fi
    else
        echo -e "${RED}[!] 未检测到 vnstat。${NC}"
    fi
    echo -e "${BLUE}----------------------------------------------------------------------${NC}"
    
    source /etc/ddr/.env 2>/dev/null
    if [[ -n "$TRAFFIC_LIMIT_GB" ]]; then
        echo -e "设定的上限: ${GREEN}${TRAFFIC_LIMIT_GB} GB${NC}"
    else
        echo -e "设定的上限: ${RED}未开启${NC}"
    fi
    echo -e "${CYAN}======================================================================${NC}"
    echo -e "${YELLOW}1. 设定/修改每月流量上限${NC}"
    echo -e "${YELLOW}2. 取消流量限制${NC}"
    echo -e "${GREEN}0. 返回${NC}"
    echo -e "${CYAN}======================================================================${NC}"
    read -ep " 请选择 [0-2]: " tr_choice
    
    case $tr_choice in
        1)
            read -ep " 请输入上限(GB): " limit_gb
            if [[ "$limit_gb" =~ ^[0-9]+$ ]]; then
                sed -i '/TRAFFIC_LIMIT_GB/d' /etc/ddr/.env 2>/dev/null
                echo "TRAFFIC_LIMIT_GB=\"$limit_gb\"" >> /etc/ddr/.env
                setup_traffic_monitor
                echo -e "${GREEN}✔ 已设为 ${limit_gb} GB！${NC}"
            else
                echo -e "${RED}[!] 必须输入纯数字。${NC}"
            fi
            read -ep "按回车返回..."
            ;;
        2)
            sed -i '/TRAFFIC_LIMIT_GB/d' /etc/ddr/.env 2>/dev/null
            disable_traffic_monitor
            echo -e "${GREEN}✔ 限制已取消。${NC}"
            read -ep "按回车返回..."
            ;;
        *) return 0 ;;
    esac
}

generate_qr() {
    local url=$1
    if command -v qrencode >/dev/null 2>&1; then
        echo -e "\n${CYAN}================ 扫码导入 =================${NC}"
        echo -e "${url}" | qrencode -s 1 -m 2 -t UTF8
        echo -e "${CYAN}===========================================${NC}\n"
    fi
}

view_config() {
    local CALLER=$1; clear; [[ ! -f /etc/ddr/.env ]] && { echo -e "${RED}配置未找到!${NC}"; sleep 2; return 0; }
    source /etc/ddr/.env
    
    local F_IP="${LINK_IP}"
    [[ "${LINK_IP}" =~ ":" ]] && F_IP="[${LINK_IP}]"

    echo -e "${BLUE}======================================================================${NC}\n${BOLD}${CYAN}   网络参数 (${MODE}) ${NC}\n${BLUE}======================================================================${NC}"
    
    if [[ "$MODE" == *"VLESS"* ]] || [[ "$MODE" == *"ALL"* ]] || [[ "$MODE" == "VLESS_SS" ]]; then
        VLESS_URL="vless://$UUID@$F_IP:$VLESS_PORT?encryption=none&flow=xtls-rprx-vision&security=reality&sni=$VLESS_SNI&fp=chrome&pbk=$PUBLIC_KEY&sid=$SHORT_ID&type=tcp#Aio-VLESS"
        echo -e "${YELLOW}[ VLESS URI ]${NC}\n${GREEN}${VLESS_URL}${NC}"
        generate_qr "$VLESS_URL"
    fi
    if [[ "$MODE" == *"HY2"* ]] || [[ "$MODE" == *"ALL"* ]]; then
        HY2_URL="hysteria2://$HY2_PASS@$F_IP:$HY2_PORT/?insecure=1&sni=$HY2_SNI&alpn=h3&obfs=salamander&obfs-password=$HY2_OBFS&mport=20000-50000#Aio-Hy2"
        echo -e "${YELLOW}[ Hysteria 2 URI ]${NC}\n${GREEN}${HY2_URL}${NC}"
        generate_qr "$HY2_URL"
    fi
    if [[ "$MODE" == *"SS"* ]] || [[ "$MODE" == *"ALL"* ]] || [[ "$MODE" == "VLESS_SS" ]]; then
        SS_BASE64=$(echo -n "2022-blake3-aes-128-gcm:${SS_PASS}" | base64 -w 0 2>/dev/null || echo -n "2022-blake3-aes-128-gcm:${SS_PASS}" | base64 | tr -d '\n')
        SS_URL="ss://${SS_BASE64}@$F_IP:$SS_PORT#Aio-SS"
        echo -e "${YELLOW}[ SS URI ]${NC}\n${GREEN}${SS_URL}${NC}"
        generate_qr "$SS_URL"
    fi
    
    echo -e "${BLUE}----------------------------------------------------------------------${NC}"
    echo -e "${YELLOW}[ Clash Meta YAML ]${NC}"
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

    read -ep "按回车返回..."
}

show_usage() {
    clear
    echo -e "${CYAN}======================================================================${NC}"
    echo -e "${BOLD}${GREEN}     功能说明${NC}"
    echo -e "${CYAN}======================================================================${NC}"
    echo -e "${YELLOW}支持 VLESS-Reality, Shadowsocks-2022, Hysteria 2 等部署。${NC}"
    echo -e "${YELLOW}内置 VPS 测速、内核级优化、硬件卸载、防宕机 Swap 生成、流量管控等功能。${NC}"
    echo -e "${CYAN}======================================================================${NC}"
    read -ep " 按回车返回..."
}

update_script() {
    clear; echo -e "${CYAN}======================================================================${NC}"
    echo -e "${BOLD}${GREEN}   热更新${NC}"
    echo -e "${CYAN}======================================================================${NC}"
    
    local OTA_URL="https://raw.githubusercontent.com/alariclin/aio-box/main/install.sh"
    mkdir -p /dev/shm/aio_box_core
    if curl -fLs --connect-timeout 10 -m 30 "$OTA_URL" -o /dev/shm/aio_box_core/aio_update.sh || curl -fLs --connect-timeout 10 -m 30 "https://ghp.ci/$OTA_URL" -o /dev/shm/aio_box_core/aio_update.sh || curl -fLs --connect-timeout 10 -m 30 "https://mirror.ghproxy.com/$OTA_URL" -o /dev/shm/aio_box_core/aio_update.sh; then
        if grep -q "Aio-box Ultimate Console" /dev/shm/aio_box_core/aio_update.sh; then
            mv /dev/shm/aio_box_core/aio_update.sh /etc/ddr/aio.sh
            chmod +x /etc/ddr/aio.sh
            echo -e "${GREEN}✔ 更新成功！${NC}"
            sleep 1
            rm -rf /dev/shm/aio_box_core
            exec /etc/ddr/aio.sh
        else
            echo -e "${RED}[!] 校验失败。${NC}"
        fi
    else
        echo -e "${RED}[!] 下载失败。${NC}"
    fi
    rm -rf /dev/shm/aio_box_core
    read -ep "按回车返回..."
}

force_update_geo() {
    clear
    echo -e "${CYAN}======================================================================${NC}"
    echo -e "${BOLD}${GREEN}   更新路由库${NC}"
    echo -e "${CYAN}======================================================================${NC}"
    setup_geo_cron
    bash /etc/ddr/geo_update.sh
    echo -e "${GREEN}✔ 更新完成。${NC}"
    read -ep "按回车返回..."
}

ota_and_geo_menu() {
    clear
    echo -e "${CYAN}======================================================================${NC}"
    echo -e "${BOLD}${GREEN}   更新选项${NC}"
    echo -e "${CYAN}======================================================================${NC}"
    echo -e "${YELLOW}1. 升级主脚本${NC}"
    echo -e "${YELLOW}2. 更新路由库${NC}"
    echo -e "${GREEN}0. 返回${NC}"
    echo -e "${CYAN}======================================================================${NC}"
    read -ep " 请选择 [0-2]: " ota_choice
    case $ota_choice in
        1) update_script ;;
        2) force_update_geo ;;
        *) return 0 ;;
    esac
}

clean_uninstall_menu() {
    clear
    echo -e "${CYAN}======================================================================${NC}"
    echo -e "${BOLD}${RED}   卸载选项${NC}"
    echo -e "${CYAN}======================================================================${NC}"
    echo -e "${YELLOW}1. 完全清理 (彻底删除环境、配置与虚拟内存 Swap)${NC}"
    echo -e "${YELLOW}2. 仅清理配置${NC}"
    echo -e "${GREEN}0. 返回${NC}"
    echo -e "${CYAN}======================================================================${NC}"
    read -ep " 请选择 [0-2]: " un_choice
    
    case $un_choice in
        1) do_cleanup "full" ;;
        2) do_cleanup "keep" ;;
        0|*) return 0 ;;
    esac
}

do_cleanup() {
    clear; echo -e "${RED}正在清理...${NC}"
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
    
    touch /tmp/cronjob
    crontab -l 2>/dev/null | grep -vE '/etc/ddr/traffic_monitor.sh|/etc/ddr/geo_update.sh' > /tmp/cronjob || true
    crontab /tmp/cronjob 2>/dev/null
    rm -f /tmp/cronjob
    rm -f /etc/ddr/traffic_monitor.sh /etc/ddr/geo_update.sh
    
    [[ "$INIT_SYS" == "systemd" ]] && systemctl daemon-reload 2>/dev/null || true
    
    if [[ "$1" == "full" ]]; then
        rm -rf /etc/ddr /usr/local/bin/sb
        
        # [彻底卸除] 处理残留 Swap 盘以归还最基础的真实磁盘空间
        if grep -q "aio_swap" /etc/fstab; then
            swapoff /var/aio_swap.img 2>/dev/null || true
            rm -f /var/aio_swap.img
            sed -i '/aio_swap/d' /etc/fstab
            echo -e "${GREEN}✔ 虚拟内存 Swap 擦除完毕。${NC}"
        fi
        
        echo -e "${GREEN}✔ 物理层完全清场完毕，服务器已恢复原生状态。${NC}"
        rm -f /var/run/aio_box.lock
        exit 0
    else
        rm -f /etc/ddr/.env
        echo -e "${GREEN}✔ 配置已移除。${NC}"
        read -ep "按回车返回..."
    fi
}

check_virgin_state() {
    clear
    init_system_environment
    echo -e "\n\033[1;33m========================================================================================\033[0m"
    echo -e "\033[1;33m 环境修复 \033[0m"
    echo -e "\033[1;33m========================================================================================\033[0m\n"

    echo -e "\033[1;36m[1/5] 清理进程与端口...\033[0m"
    service_manager stop xray sing-box hysteria
    killall -9 xray sing-box hysteria 2>/dev/null || true
    
    # [漏洞填补] 在 Alpine 或者轻量系统里增强对游留端口的暴力清理
    local ports_to_clean=(80 443 2053 8443)
    for p in "${ports_to_clean[@]}"; do
        fuser -k -9 "${p}/tcp" 2>/dev/null || true
        fuser -k -9 "${p}/udp" 2>/dev/null || true
        local PIDS=$(lsof -ti:"${p}" 2>/dev/null)
        if [[ -n "$PIDS" ]]; then
            for pid in $PIDS; do kill -9 "$pid" 2>/dev/null || true; done
        fi
    done

    echo -e "\n\033[1;36m[2/5] 修复防火墙...\033[0m"
    clean_nat_rules
    clean_input_rules
    save_firewall_rules

    echo -e "\n\033[1;36m[3/5] 清理注册项...\033[0m"
    rm -f /etc/systemd/system/xray.service /etc/systemd/system/sing-box.service /etc/systemd/system/hysteria.service 2>/dev/null
    rm -f /etc/init.d/xray /etc/init.d/sing-box /etc/init.d/hysteria 2>/dev/null
    [[ "$INIT_SYS" == "systemd" ]] && systemctl daemon-reload 2>/dev/null || true

    echo -e "\n\033[1;36m[4/5] 删除配置文件...\033[0m"
    rm -rf /usr/local/etc/xray /etc/sing-box /etc/hysteria /usr/local/bin/xray /usr/local/bin/sing-box /usr/local/bin/hysteria 2>/dev/null

    echo -e "\n\033[1;36m[5/5] 测试出网...\033[0m"
    if curl -I -s -m 5 https://www.google.com | head -n 1 | grep -qE "200|301|302"; then
        echo -e "${GREEN}  ✔ 正常。${NC}"
    else
        echo -e "${RED}  [!] 受阻！${NC}"
    fi

    echo -e "\n\033[1;33m========================================================================================\033[0m"
    echo -e "${GREEN}修复完成！${NC}"
    read -ep "按回车返回..."
}

tune_vps() {
    clear; echo -e "${CYAN}注入极限内核优化参数...${NC}"
    
    # 按需唤醒底层性能架构
    audit_hardware_resources
    enable_rps_rfs_and_offload
    
    cat > /etc/security/limits.d/aio-box.conf <<EOF
* soft nofile 1048576
* hard nofile 1048576
* soft nproc 1048576
* hard nproc 1048576
root soft nofile 1048576
root hard nofile 1048576
EOF

    modprobe tcp_bbr 2>/dev/null || true
    modprobe nf_conntrack 2>/dev/null || true
    
    cat > /etc/sysctl.d/99-aio-box-tune.conf << 'EOF'
fs.file-max = 1048576
fs.nr_open = 1048576
fs.inotify.max_user_instances = 8192
net.ipv4.ip_forward = 1
net.ipv4.tcp_syncookies = 3
net.ipv4.tcp_fin_timeout = 30
net.ipv4.tcp_keepalive_time = 1200
net.ipv4.tcp_max_syn_backlog = 8192
net.ipv4.tcp_max_tw_buckets = 5000
net.ipv4.tcp_tw_reuse = 1
net.ipv4.ip_local_port_range = 1024 65535
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
    
    echo -e "${GREEN}✔ 优化参数已挂载！${NC}"
    read -ep "按回车返回..."
}

vps_benchmark_menu() {
    clear
    echo -e "${CYAN}======================================================================${NC}"
    echo -e "${BOLD}${GREEN}   测速与审计${NC}"
    echo -e "${CYAN}======================================================================${NC}"
    echo -e "${YELLOW}1. 运行 bench.sh${NC}"
    echo -e "${YELLOW}2. 运行 Check.Place${NC}"
    echo -e "${GREEN}0. 返回${NC}"
    echo -e "${CYAN}======================================================================${NC}"
    read -ep " 请选择 [0-2]: " bench_choice
    case $bench_choice in
        1) 
            clear; echo -e "${GREEN}正在运行 bench.sh...${NC}"
            wget -qO- https://bench.sh | bash
            read -ep "按回车返回..."
            ;;
        2)
            clear; echo -e "${GREEN}正在运行 Check.Place...${NC}"
            bash <(curl -Ls https://Check.Place) -I
            read -ep "按回车返回..."
            ;;
        0|*) return 0 ;;
    esac
}

# ====================================================================
# 入口点：环境静默初始化并弹出菜单
# ====================================================================
init_system_environment
setup_shortcut

GLOBAL_PUBLIC_IP=""

while true; do
    if [[ -z "$GLOBAL_PUBLIC_IP" || "$GLOBAL_PUBLIC_IP" == "N/A" ]]; then
        GLOBAL_PUBLIC_IP=$(curl -s4m2 api.ipify.org 2>/dev/null || curl -s6m2 api64.ipify.org 2>/dev/null || echo "N/A")
    fi
    
    STATUS_STR=""
    is_service_running xray && STATUS_STR="${GREEN}Xray-Core(Running)${NC} "
    is_service_running sing-box && STATUS_STR+="${CYAN}Sing-Box(Running)${NC} "
    is_service_running hysteria && STATUS_STR+="${PURPLE}Hy2-Native(Running)${NC} "
    [[ -z "$STATUS_STR" ]] && STATUS_STR="${RED}已停机${NC}"
    
    source /etc/ddr/.env 2>/dev/null && CUR_MODE="[${CORE}-${MODE}]" || CUR_MODE=""
    
    clear; echo -e "${BLUE}========================================================================================${NC}\n${BOLD}${YELLOW} =======================Aio-box Ultimate Enterprise Final===============================${NC}\n${BLUE}========================================================================================${NC}"
    echo -e " IP: ${YELLOW}$GLOBAL_PUBLIC_IP${NC} | 状态: $STATUS_STR $CUR_MODE\n${BLUE}----------------------------------------------------------------------------------------${NC}"
    echo -e " ${YELLOW}[ Xray-core ]${NC}                   ${YELLOW}[ Sing-box ]${NC}"
    echo -e " ${GREEN}1.${NC} VLESS-Reality                ${GREEN}6.${NC} VLESS-Reality"
    echo -e " ${GREEN}2.${NC} Shadowsocks-2022           ${GREEN}7.${NC} Shadowsocks-2022"
    echo -e " ${GREEN}3.${NC} VLESS + SS-2022             ${GREEN}8.${NC} VLESS + SS-2022"
    echo -e " ${GREEN}4.${NC} Hysteria 2 (原生)           ${GREEN}9.${NC} Hysteria 2 (Sing-box)"
    echo -e " ${GREEN}5.${NC} 全协议 (Xray+Hy2)           ${GREEN}10.${NC} 全协议 (Sing-box)"
    echo -e "${BLUE}----------------------------------------------------------------------------------------${NC}"
    echo -e " ${GREEN}11.${NC} 测速与检测"
    echo -e " ${GREEN}12.${NC} 内核优化"
    echo -e " ${GREEN}13.${NC} 查看配置"
    echo -e " ${GREEN}14.${NC} 说明文档"
    echo -e " ${GREEN}15.${NC} 更新"
    echo -e " ${GREEN}16.${NC} 卸载"
    echo -e " ${GREEN}17.${NC} 修复"
    echo -e " ${GREEN}18.${NC} 流量管控"
    echo -e " ${GREEN}0.${NC}  退出"
    echo -e "${BLUE}========================================================================================${NC}"
    read -ep " 请输入指令号: " choice
    
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
