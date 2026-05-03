#!/usr/bin/env bash
# ==============================Aio-box===============================
set -o pipefail
export DEBIAN_FRONTEND=noninteractive
export LANG=en_US.UTF-8

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;36m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
NC='\033[0m'
BOLD='\033[1m'

DEPS_MARKER="/etc/ddr/.deps.v20260504"
SCRIPT_URL="https://raw.githubusercontent.com/alariclin/aio-box/main/install.sh"

die() {
    echo -e "${RED}[!] $*${NC}" >&2
    exit 1
}

need_interactive_tty() {
    if [[ ! -t 0 ]]; then
        if [[ -r /dev/tty ]]; then
            exec < /dev/tty
        else
            die "当前环境无可交互 TTY，无法运行交互式菜单。"
        fi
    fi
}

if [[ $EUID -ne 0 ]]; then
    if [[ -f "$0" && -r "$0" && "$0" != "bash" && "$0" != "-bash" ]] && command -v sudo >/dev/null 2>&1; then
        exec sudo bash "$0" "$@"
    fi
    die "非 root 管道/标准输入执行无法自动提权；请使用: curl -fsSL <URL> | sudo bash"
fi

need_interactive_tty

exec 9>/var/run/aio_box.lock
flock -n 9 || die "检测到另一个 Aio-box 实例正在运行。"

# --- [ Input Validation & Network ] ---
valid_port() {
    [[ "$1" =~ ^[0-9]+$ ]] && (( "$1" >= 1 && "$1" <= 65535 ))
}

valid_positive_int() {
    [[ "$1" =~ ^[1-9][0-9]*$ ]]
}

valid_domain() {
    [[ "$1" =~ ^([A-Za-z0-9]([A-Za-z0-9-]{0,61}[A-Za-z0-9])?\.)+[A-Za-z]{2,63}$ ]]
}

valid_sni() {
    valid_domain "$1"
}

valid_url_https() {
    local url="$1"
    local rest host port
    [[ "$url" == https://* ]] || return 1
    [[ "$url" =~ [\"\`\$\\] ]] && return 1
    [[ "$url" =~ [[:space:]] ]] && return 1
    rest="${url#https://}"
    host="${rest%%/*}"
    [[ -n "$host" ]] || return 1
    if [[ "$host" == *:* ]]; then
        port="${host##*:}"
        host="${host%%:*}"
        valid_port "$port" || return 1
    fi
    valid_domain "$host" || return 1
    return 0
}

valid_ipv4_cidr() {
    local input="$1"
    local addr="${input%/*}"
    local mask=""
    [[ "$input" == */* ]] && mask="${input#*/}"
    if [[ -n "$mask" ]]; then
        [[ "$mask" =~ ^[0-9]+$ ]] || return 1
        (( mask >= 0 && mask <= 32 )) || return 1
    fi
    [[ "$addr" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]] || return 1
    local IFS=.
    local -a octets
    local n
    read -r -a octets <<< "$addr"
    for n in "${octets[@]}"; do
        [[ "$n" =~ ^[0-9]+$ ]] || return 1
        (( n >= 0 && n <= 255 )) || return 1
    done
    return 0
}

valid_ipv6_cidr() {
    local input="$1"
    local addr="${input%/*}"
    local mask=""
    [[ "$input" == */* ]] && mask="${input#*/}"
    if [[ -n "$mask" ]]; then
        [[ "$mask" =~ ^[0-9]+$ ]] || return 1
        (( mask >= 0 && mask <= 128 )) || return 1
    fi
    [[ "$addr" == *:* ]] || return 1
    [[ "$addr" =~ ^[0-9A-Fa-f:]+$ ]] || return 1
    [[ "$addr" != *":::"* ]] || return 1
    return 0
}

shell_quote() {
    printf '%q' "$1"
}

pin_sha256_colon() {
    openssl x509 -noout -fingerprint -sha256 -in "$1" | cut -d= -f2
}

get_public_ip() {
    local ip=""
    local apis=(
        "https://api.ipify.org"
        "https://ifconfig.me/ip"
        "https://icanhazip.com"
    )
    for api in "${apis[@]}"; do
        ip=$(curl -s4m5 "$api" 2>/dev/null | tr -d '[:space:]')
        if [[ "$ip" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]]; then
            printf '%s\n' "$ip"
            return 0
        fi
    done
    ip=$(curl -s6m5 https://api64.ipify.org 2>/dev/null | tr -d '[:space:]')
    if [[ "$ip" =~ : ]]; then
        printf '%s\n' "$ip"
        return 0
    fi
    printf 'N/A\n'
}

get_active_interface() {
    local iface
    iface=$(ip route get 8.8.8.8 2>/dev/null | awk '{for(i=1;i<=NF;i++) if($i=="dev"){print $(i+1); exit}}')
    [[ -z "$iface" ]] && iface=$(ip -o route show to default 2>/dev/null | awk '{print $5; exit}')
    [[ -z "$iface" ]] && iface=$(ip link | awk -F: '$0 !~ "lo|vir|wl|^[^0-9]"{print $2;getline}' | head -n 1 | tr -d ' ')
    printf '%s\n' "$iface"
}

verify_domain_points_to_self() {
    local domain="$1"
    local pub_ip="$2"
    local resolved=""
    resolved=$(getent ahosts "$domain" 2>/dev/null | awk '{print $1}' | sort -u)
    [[ -z "$resolved" ]] && die "域名无法解析: $domain"
    
    if [[ "$pub_ip" != "N/A" ]] && ! echo "$resolved" | grep -Fxq "$pub_ip"; then
        echo -e "${YELLOW}[!] 域名已解析，但未发现解析到当前公网 IP: $pub_ip${NC}"
        echo -e "${YELLOW}解析结果:${NC}\n$resolved"
        read -ep "仍然继续？[y/N]: " continue_domain
        [[ "$continue_domain" =~ ^[Yy]$ ]] || die "已取消部署。"
    fi
}

# --- [ Initialization ] ---
init_system_environment() {
    if [[ -f /etc/os-release ]]; then
        . /etc/os-release
        case "$ID" in
            debian) release="debian"; installType='apt-get -y install'; removeType='apt-get -y autoremove' ;;
            ubuntu) release="ubuntu"; installType='apt-get -y install'; removeType='apt-get -y autoremove' ;;
            alpine) release="alpine"; installType='apk add'; removeType='apk del' ;;
            centos|rhel|rocky|almalinux) release="centos"; installType='yum -y install'; removeType='yum -y remove' ;;
        esac
    fi

    if [[ -z "$release" ]]; then
        if [[ -n $(find /etc -name "redhat-release" 2>/dev/null) ]] || grep -qi "centos" /proc/version; then
            release="centos"
            installType='yum -y install'
            removeType='yum -y remove'
        elif { [[ -f "/etc/issue" ]] && grep -qi "Alpine" /etc/issue; } || { [[ -f "/proc/version" ]] && grep -qi "Alpine" /proc/version; }; then
            release="alpine"
            installType='apk add'
            removeType='apk del'
        elif { [[ -f "/etc/issue" ]] && grep -qi "debian" /etc/issue; } || { [[ -f "/proc/version" ]] && grep -qi "debian" /proc/version; }; then
            release="debian"
            installType='apt-get -y install'
            removeType='apt-get -y autoremove'
        elif { [[ -f "/etc/issue" ]] && grep -qi "ubuntu" /etc/issue; } || { [[ -f "/proc/version" ]] && grep -qi "ubuntu" /proc/version; }; then
            release="ubuntu"
            installType='apt-get -y install'
            removeType='apt-get -y autoremove'
        fi
    fi

    [[ -z ${release} ]] && die "本脚本不支持当前异构系统。"

    if command -v systemctl >/dev/null 2>&1; then
        INIT_SYS="systemd"
    elif command -v rc-service >/dev/null 2>&1; then
        INIT_SYS="openrc"
    else
        die "无法检测到受支持的守护进程初始化系统 (Systemd/OpenRC)！"
    fi

    if [[ ! -f "$DEPS_MARKER" ]]; then
        echo -e "${YELLOW}[*] 正在同步系统依赖环境 (OS: ${release}, Init: ${INIT_SYS})...${NC}"
        if [[ "${release}" == "ubuntu" || "${release}" == "debian" ]]; then
            apt-get update -y -q >/dev/null 2>&1
        elif [[ "${release}" == "centos" ]]; then
            yum makecache -y -q >/dev/null 2>&1
            ${installType} epel-release >/dev/null 2>&1
        elif [[ "${release}" == "alpine" ]]; then
            apk update -q >/dev/null 2>&1
        fi
        
        local deps=()
        case "$release" in
            debian|ubuntu)
                deps=(wget curl jq openssl bc unzip vnstat iptables tar psmisc lsof qrencode ca-certificates iproute2 coreutils cron uuid-runtime iptables-persistent netfilter-persistent fail2ban)
                command -v ufw >/dev/null 2>&1 && ufw disable >/dev/null 2>&1 || true
                ;;
            centos)
                deps=(wget curl jq openssl bc unzip vnstat iptables tar psmisc lsof qrencode ca-certificates coreutils cronie util-linux bind-utils iproute fail2ban iptables-services epel-release)
                ;;
            alpine)
                deps=(bash wget curl jq openssl bc unzip vnstat iptables tar psmisc lsof qrencode ca-certificates iproute2 coreutils util-linux bind-tools procps fail2ban iptables-openrc)
                ;;
        esac
        ${installType} "${deps[@]}" >/dev/null 2>&1 || die "基础依赖包安装失败。"
        mkdir -p /etc/ddr && touch "$DEPS_MARKER"
    fi

    ensure_commands

    start_unit_if_exists() {
        local unit="$1"
        systemctl list-unit-files "$unit.service" >/dev/null 2>&1 || return 0
        systemctl enable --now "$unit" >/dev/null 2>&1 || true
    }

    if [[ "$INIT_SYS" == "systemd" ]]; then
        case "$release" in
            debian|ubuntu) start_unit_if_exists cron ;;
            centos) start_unit_if_exists crond ;;
        esac
        start_unit_if_exists vnstat
        if [[ "${release}" == "centos" ]]; then
            systemctl disable --now firewalld 2>/dev/null || true
            systemctl enable --now iptables ip6tables 2>/dev/null || true
        fi
    elif [[ "$INIT_SYS" == "openrc" ]]; then
        rc-update add crond default 2>/dev/null || true
        rc-update add vnstatd default 2>/dev/null || true
        rc-service crond start 2>/dev/null || true
        rc-service vnstatd start 2>/dev/null || true
    fi

    IPT=$(command -v iptables || echo "/sbin/iptables")
    IPT6=$(command -v ip6tables || echo "/sbin/ip6tables")
}

ensure_commands() {
    local missing_pkgs=()
    need_cmd_pkg() {
        local cmd="$1"; local deb="$2"; local rpm="$3"; local apk="$4"
        command -v "$cmd" >/dev/null 2>&1 && return 0
        case "$release" in
            debian|ubuntu) missing_pkgs+=("$deb") ;;
            centos) missing_pkgs+=("$rpm") ;;
            alpine) missing_pkgs+=("$apk") ;;
        esac
    }

    need_cmd_pkg curl curl curl curl
    need_cmd_pkg wget wget wget wget
    need_cmd_pkg jq jq jq jq
    need_cmd_pkg openssl openssl openssl openssl
    need_cmd_pkg bc bc bc bc
    need_cmd_pkg unzip unzip unzip unzip
    need_cmd_pkg tar tar tar tar
    need_cmd_pkg iptables iptables iptables iptables
    need_cmd_pkg ss iproute2 iproute iproute2
    need_cmd_pkg lsof lsof lsof lsof
    need_cmd_pkg qrencode qrencode qrencode qrencode
    need_cmd_pkg vnstat vnstat vnstat vnstat
    need_cmd_pkg getent libc-bin glibc-common libc-utils

    if (( ${#missing_pkgs[@]} > 0 )); then
        local unique_pkgs
        unique_pkgs=$(printf '%s\n' "${missing_pkgs[@]}" | awk '!seen[$0]++')
        echo -e "${YELLOW}[*] 检测到缺失依赖包，正在补装...${NC}"
        # shellcheck disable=SC2086
        ${installType} $unique_pkgs >/dev/null 2>&1 || die "依赖补装失败。"
    fi

    local required=(curl jq openssl bc unzip tar iptables ss lsof vnstat)
    local c
    for c in "${required[@]}"; do
        command -v "$c" >/dev/null 2>&1 || die "关键依赖缺失: $c"
    done
}

has_ipv6() {
    ip -6 addr show scope global 2>/dev/null | grep -q inet6 && return 0
    ip -6 route show default 2>/dev/null | grep -q '^default' && return 0
    return 1
}

ipv6_nat_redirect_usable() {
    command -v ip6tables >/dev/null 2>&1 || return 1
    # Test if we can actually read the NAT table. If not, it's disabled in the kernel.
    $IPT6 -w -t nat -L PREROUTING >/dev/null 2>&1 || return 1
    return 0
}

get_architecture() {
    local ARCH=$(uname -m)
    case "$ARCH" in
        x86_64|amd64) XRAY_ARCH="64"; SB_ARCH="amd64"; HY2_ARCH="amd64" ;;
        aarch64|armv8) XRAY_ARCH="arm64-v8a"; SB_ARCH="arm64"; HY2_ARCH="arm64" ;;
        *) die "无法识别的底层 CPU 架构: $ARCH" ;;
    esac
}

rand_alnum() {
    local len="$1"
    local out=""
    while [[ ${#out} -lt "$len" ]]; do
        out="${out}$(openssl rand -base64 32 | tr -dc 'a-zA-Z0-9')"
    done
    printf '%s\n' "${out:0:$len}"
}

generate_robust_uuid() {
    if command -v uuidgen >/dev/null 2>&1; then
        uuidgen
    elif [[ -r /proc/sys/kernel/random/uuid ]]; then
        cat /proc/sys/kernel/random/uuid
    else
        local u
        u=$(cat /dev/urandom | tr -dc 'a-f0-9' | fold -w 32 | head -n 1)
        echo "${u:0:8}-${u:8:4}-4${u:13:3}-8${u:17:3}-${u:20:12}"
    fi
}

fetch_geo_data() {
    local file_name="$1"
    local official_url="$2"
    local out="/tmp/${file_name}"
    local size=""
    rm -f "$out"
    if curl -fLs --connect-timeout 10 -m 60 "$official_url" -o "$out"; then
        size=$(wc -c < "$out" 2>/dev/null | tr -d ' ')
        [[ -n "$size" && "$size" -gt 500000 ]] && return 0
    fi
    rm -f "$out"
    die "Geo 数据文件 ${file_name} 下载或校验失败。"
}

# --- [ Service Manager ] ---
service_manager() {
    local action=$1; shift
    for srv in "$@"; do
        if [[ "$INIT_SYS" == "systemd" ]]; then
            case "$action" in
                stop)
                    systemctl disable --now "$srv" 2>/dev/null || true
                    ;;
                start)
                    systemctl daemon-reload 2>/dev/null || true
                    systemctl enable "$srv" 2>/dev/null || true
                    systemctl restart "$srv" 2>/dev/null || true
                    sleep 2
                    if ! systemctl is-active --quiet "$srv"; then
                        journalctl -u "$srv" --no-pager -n 50 2>/dev/null
                        die "服务 $srv 拉起失败！"
                    fi
                    ;;
            esac
        elif [[ "$INIT_SYS" == "openrc" ]]; then
            case "$action" in
                stop)
                    rc-service "$srv" stop 2>/dev/null || true
                    rc-update del "$srv" default 2>/dev/null || true
                    ;;
                start)
                    rc-update add "$srv" default 2>/dev/null || true
                    rc-service "$srv" restart 2>/dev/null || true
                    sleep 2
                    if ! rc-service "$srv" status >/dev/null 2>&1; then
                        die "服务 $srv 拉起失败！"
                    fi
                    ;;
            esac
        fi
    done
}

stop_all_managed_services() {
    service_manager stop xray sing-box hysteria >/dev/null 2>&1 || true
    for srv in xray sing-box hysteria; do
        if [[ "$INIT_SYS" == "systemd" ]]; then
            local pid
            pid=$(systemctl show -p MainPID --value "$srv" 2>/dev/null || true)
            [[ "$pid" =~ ^[0-9]+$ && "$pid" -gt 1 ]] && kill -TERM "$pid" 2>/dev/null || true
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

# --- [ Firewall ] ---
save_firewall_rules() {
    command -v netfilter-persistent >/dev/null 2>&1 && netfilter-persistent save >/dev/null 2>&1
    command -v rc-service >/dev/null 2>&1 && rc-service iptables save >/dev/null 2>&1
    if [[ -d /etc/sysconfig ]]; then
        command -v iptables-save >/dev/null 2>&1 && iptables-save > /etc/sysconfig/iptables 2>/dev/null
        command -v ip6tables-save >/dev/null 2>&1 && ip6tables-save > /etc/sysconfig/ip6tables 2>/dev/null
    fi
}

allowPort() {
    local port=$1
    local type=${2:-tcp}
    
    if command -v iptables >/dev/null 2>&1; then
        if ! $IPT -w -C INPUT -p "${type}" --dport "${port}" -j ACCEPT 2>/dev/null; then
            $IPT -w -I INPUT -p "${type}" --dport "${port}" -m comment --comment "Aio-box-${port}-${type}" -j ACCEPT >/dev/null 2>&1 || die "IPv4 防火墙放行失败: ${port}/${type}"
        fi
        if has_ipv6 && command -v ip6tables >/dev/null 2>&1; then
            if ! $IPT6 -w -C INPUT -p "${type}" --dport "${port}" -j ACCEPT 2>/dev/null; then
                $IPT6 -w -I INPUT -p "${type}" --dport "${port}" -m comment --comment "Aio-box-${port}-${type}" -j ACCEPT >/dev/null 2>&1 || die "IPv6 防火墙放行失败: ${port}/${type}"
            fi
        fi
    fi
}

clean_nat_rules() {
    while $IPT -w -t nat -S PREROUTING 2>/dev/null | grep -q "Aio-box-HY2-HOP"; do
        local LOCAL_RULE=$($IPT -w -t nat -S PREROUTING 2>/dev/null | grep "Aio-box-HY2-HOP" | head -n 1 | sed 's/^-A /-D /')
        [[ -z "$LOCAL_RULE" ]] && break
        $IPT -w -t nat $LOCAL_RULE 2>/dev/null || break
    done
    if command -v ip6tables >/dev/null 2>&1 && $IPT6 -w -t nat -S PREROUTING >/dev/null 2>&1; then
        while $IPT6 -w -t nat -S PREROUTING 2>/dev/null | grep -q "Aio-box-HY2-HOP"; do
            local LOCAL_RULE6=$($IPT6 -w -t nat -S PREROUTING 2>/dev/null | grep "Aio-box-HY2-HOP" | head -n 1 | sed 's/^-A /-D /')
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
    if command -v ip6tables >/dev/null 2>&1 && $IPT6 -w -S INPUT >/dev/null 2>&1; then
        while $IPT6 -w -S INPUT 2>/dev/null | grep -q "Aio-box-"; do
            local LOCAL_RULE6=$($IPT6 -w -S INPUT 2>/dev/null | grep "Aio-box-" | head -n 1 | sed 's/^-A /-D /')
            [[ -z "$LOCAL_RULE6" ]] && break
            $IPT6 -w $LOCAL_RULE6 2>/dev/null || break
        done
    fi
}

release_ports() {
    echo -e "${YELLOW}[*] 正在停止 Aio-box 托管服务并检查端口占用...${NC}"
    stop_all_managed_services
    sleep 1

    local p proto holder
    local ports_to_check=(
        ${VLESS_PORT:-}
        ${XHTTP_PORT:-}
        ${HY2_BASE_PORT:-}
        ${HY2_MONITOR_PORT:-}
        ${SS_PORT:-}
    )

    for p in $(printf '%s\n' "${ports_to_check[@]}" | awk 'NF' | sort -u); do
        for proto in tcp udp; do
            holder=$(ss -H -n -l -p -A "${proto}" 2>/dev/null | grep -E "[:.]${p}\b" | grep -vE 'xray|sing-box|hysteria' || true)
            [[ -z "$holder" ]] && continue
            echo -e "${RED}[!] 端口 ${p}/${proto} 已被非 Aio-box 进程占用：${NC}"
            echo "$holder"
            die "请先手动释放端口 ${p}/${proto}。脚本不会自动 kill 非托管进程。"
        done
    done
}

check_selected_ports_free() {
    echo -e "${YELLOW}[*] 正在检查新选择端口是否被非 Aio-box 进程占用...${NC}"
    local p proto holder
    local ports_to_check=(
        ${VLESS_PORT:-}
        ${XHTTP_PORT:-}
        ${HY2_BASE_PORT:-}
        ${HY2_MONITOR_PORT:-}
        ${SS_PORT:-}
    )

    # Check for duplicate selections within the user's current configuration
    local seen_ports=""
    for p in $(printf '%s\n' "${ports_to_check[@]}" | awk 'NF && /^[0-9]+$/'); do
        if echo "$seen_ports" | grep -wq "$p"; then
            die "端口冲突：您不能在当前配置中为多个协议指定相同的端口 ($p)。"
        fi
        seen_ports="$seen_ports $p"
    done

    # Check if any port falls within the HY2 hopping range
    if [[ "$HY2_HOP" == "true" && -n "$HY2_RANGE_START" && -n "$HY2_RANGE_END" ]]; then
        for p in $(printf '%s\n' "${ports_to_check[@]}" | awk 'NF && /^[0-9]+$/'); do
            if (( p >= HY2_RANGE_START && p <= HY2_RANGE_END )); then
                die "端口冲突：您指定的基础端口 ($p) 不能落在 Hysteria 2 跳跃区间 (${HY2_RANGE_START}-${HY2_RANGE_END}) 内。"
            fi
        done
    fi

    for p in $(printf '%s\n' "${ports_to_check[@]}" | awk 'NF && /^[0-9]+$/' | sort -u); do
        for proto in tcp udp; do
            holder=$(ss -H -n -l -p -A "${proto}" 2>/dev/null | grep -E "[:.]${p}\b" | grep -vE 'xray|sing-box|hysteria' || true)
            [[ -z "$holder" ]] && continue
            echo -e "${RED}[!] 新选择端口 ${p}/${proto} 已被非 Aio-box 进程占用：${NC}"
            echo "$holder"
            die "请先手动释放端口 ${p}/${proto}。"
        done
    done

    if [[ "$HY2_HOP" == "true" && -n "$HY2_RANGE_START" && -n "$HY2_RANGE_END" ]]; then
        holder=$(ss -H -n -l -p -A udp 2>/dev/null | awk -v start="$HY2_RANGE_START" -v end="$HY2_RANGE_END" '{
            match($4, /:([0-9]+)$/, a);
            if (a[1] >= start && a[1] <= end) print $0;
        }' | grep -vE 'xray|sing-box|hysteria' || true)
        
        if [[ -n "$holder" ]]; then
            echo -e "${RED}[!] HY2 UDP 跳跃区间 ${HY2_RANGE_START}-${HY2_RANGE_END} 已被非 Aio-box 进程占用：${NC}"
            echo "$holder"
            die "请先手动释放 HY2 UDP 跳跃区间内的占用端口。"
        fi
    fi
}

setup_shortcut() {
    mkdir -p /etc/ddr
    if [[ "$1" == "update" ]]; then
        curl -fLs --connect-timeout 10 "$SCRIPT_URL" -o /tmp/aio.sh.tmp || die "快捷入口脚本下载失败。"
        bash -n /tmp/aio.sh.tmp || die "更新脚本语法校验失败。"
        grep -q "==============================Aio-box===============================" /tmp/aio.sh.tmp || die "更新脚本文本指纹不匹配。"
        mv -f /tmp/aio.sh.tmp /etc/ddr/aio.sh
    elif [[ -f "$0" && -r "$0" && "$0" != "bash" && "$0" != "-bash" ]]; then
        cp -f "$0" /etc/ddr/aio.sh
    elif [[ ! -f /etc/ddr/aio.sh ]]; then
        curl -fLs --connect-timeout 10 "$SCRIPT_URL" -o /tmp/aio.sh.tmp || die "无法从远端创建持久化入口。"
        bash -n /tmp/aio.sh.tmp || die "持久化脚本语法校验失败。"
        grep -q "==============================Aio-box===============================" /tmp/aio.sh.tmp || die "持久化脚本文本指纹不匹配。"
        mv -f /tmp/aio.sh.tmp /etc/ddr/aio.sh
    fi
    chmod +x /etc/ddr/aio.sh

    cat > /usr/local/bin/sb <<'EOF'
#!/usr/bin/env bash
if [[ $EUID -eq 0 ]]; then
    exec bash /etc/ddr/aio.sh "$@"
elif command -v sudo >/dev/null 2>&1; then
    exec sudo bash /etc/ddr/aio.sh "$@"
else
    echo "Root privileges required. Please run: su -"
    exit 1
fi
EOF
    chmod +x /usr/local/bin/sb
}

# --- [ Active Defense ] ---
setup_active_defense() {
    echo -e "${YELLOW}[*] 正在挂载环形缓冲日志与 Fail2Ban 主动防御矩阵...${NC}"
    touch /var/log/aio-box-xray-access.log /var/log/aio-box-xray-error.log /var/log/aio-box-singbox.log 2>/dev/null
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
failregex = ^.*(?:rejected|invalid request|bad request|authentication failed).* from <HOST>[: ].*$
            ^.*<HOST>.*(?:rejected|invalid|unauthorized|forbidden).*$
ignoreregex = 
EOF
        cat > /etc/fail2ban/jail.d/aio-box.local << 'EOF'
[aio-box]
enabled = true
port = 1-65535
filter = aio-box
logpath = /var/log/aio-box-xray-error.log
          /var/log/aio-box-singbox.log
maxretry = 8
findtime = 120
bantime = 3600
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

IPT=$(command -v iptables || echo "/sbin/iptables")
IPT6=$(command -v ip6tables || echo "/sbin/ip6tables")

has_ipv6() {
    ip -6 addr show scope global 2>/dev/null | grep -q inet6 && return 0
    ip -6 route show default 2>/dev/null | grep -q '^default' && return 0
    return 1
}

ipv6_nat_redirect_usable() {
    command -v ip6tables >/dev/null 2>&1 || return 1
    $IPT6 -w -t nat -L PREROUTING >/dev/null 2>&1 || return 1
    return 0
}

get_month_total_bytes() {
    local iface="$1"
    local mode="${2:-total}"
    local line
    line=$(vnstat -i "$iface" --oneline b 2>/dev/null) || return 1
    case "$mode" in
        rx)    echo "$line" | awk -F';' '{print $9}' ;;
        tx)    echo "$line" | awk -F';' '{print $10}' ;;
        total) echo "$line" | awk -F';' '{print $11}' ;;
        *) return 1 ;;
    esac
}

bytes_to_gb() {
    awk -v b="$1" 'BEGIN { printf "%.2f", b / 1024 / 1024 / 1024 }'
}

if [[ -n "$TRAFFIC_LIMIT_GB" ]]; then
    INTERFACE=$(ip route get 8.8.8.8 2>/dev/null | awk '{for(i=1;i<=NF;i++) if($i=="dev"){print $(i+1); exit}}')
    [[ -z "$INTERFACE" ]] && INTERFACE=$(ip -o route show to default 2>/dev/null | awk '{print $5; exit}')
    [[ -z "$INTERFACE" ]] && INTERFACE=$(ip link | awk -F: '$0 !~ "lo|vir|wl|^[^0-9]"{print $2;getline}' | head -n 1 | tr -d ' ')
    USED_BYTES=$(get_month_total_bytes "$INTERFACE" "${TRAFFIC_LIMIT_MODE:-total}") || exit 0
    USED_GB=$(bytes_to_gb "$USED_BYTES")
    if (( $(echo "$USED_GB >= $TRAFFIC_LIMIT_GB" | bc -l) )); then
        exit 0
    fi
fi

check_restart() {
    local srv=$1
    [[ "$srv" == "singbox" ]] && srv="sing-box"
    [[ "$srv" == "xray-core" ]] && srv="xray"
    if command -v systemctl >/dev/null 2>&1; then
        systemctl restart "$srv" >/dev/null 2>&1 || true
    else
        rc-service "$srv" restart >/dev/null 2>&1 || true
    fi
}

if [[ "$CORE" == "xray" || "$CORE" == "singbox" || "$CORE" == "hysteria" ]]; then
    HY2_SRV="$CORE"
    [[ "$CORE" == "singbox" ]] && HY2_SRV="sing-box"
    [[ "$CORE" == "xray" && "$MODE" == *"ALL"* ]] && HY2_SRV="hysteria"

    if [[ "$HY2_HOP" == "true" && "$HY2_HOP_IMPL" == "manual" && -n "$HY2_RANGE_START" && -n "$HY2_RANGE_END" ]]; then
        if ! $IPT -w -t nat -S PREROUTING 2>/dev/null | grep -q "Aio-box-HY2-HOP"; then
            check_restart "$HY2_SRV"
            exit 0
        fi
        if has_ipv6 && ipv6_nat_redirect_usable; then
            if ! $IPT6 -w -t nat -S PREROUTING 2>/dev/null | grep -q "Aio-box-HY2-HOP"; then
                check_restart "$HY2_SRV"
                exit 0
            fi
        fi
    fi

    if [[ -n "$VLESS_PORT" ]] && ! ss -H -nlt 2>/dev/null | awk '{print $4}' | grep -Eq "[:.]${VLESS_PORT}$"; then
        check_restart "$CORE"
        exit 0
    fi
    if [[ -n "$XHTTP_PORT" ]] && ! ss -H -nlt 2>/dev/null | awk '{print $4}' | grep -Eq "[:.]${XHTTP_PORT}$"; then
        check_restart "$CORE"
        exit 0
    fi
    if [[ -n "$HY2_MONITOR_PORT" ]] && ! ss -H -nlu 2>/dev/null | awk '{print $4}' | grep -Eq "[:.]${HY2_MONITOR_PORT}$"; then
        check_restart "$HY2_SRV"
        exit 0
    fi
    if [[ -n "$SS_PORT" ]] && ! ss -H -nlt 2>/dev/null | awk '{print $4}' | grep -Eq "[:.]${SS_PORT}$"; then
        check_restart "$CORE"
        exit 0
    fi
fi
EOF
    chmod +x /etc/ddr/socket_probe.sh
    local tmp_cron
    tmp_cron=$(mktemp)
    crontab -l 2>/dev/null | grep -vE "^no crontab for|^#" | grep -v '/etc/ddr/socket_probe.sh' > "$tmp_cron" || true
    echo "* * * * * /bin/bash /etc/ddr/socket_probe.sh >/dev/null 2>&1" >> "$tmp_cron"
    crontab "$tmp_cron" 2>/dev/null
    rm -f "$tmp_cron"
}

setup_geo_cron() {
    cat > /etc/ddr/geo_update.sh << 'EOF'
#!/usr/bin/env bash
PATH=/usr/local/sbin:/usr/local/bin:/sbin:/bin:/usr/sbin:/usr/bin

GEOIP_URL="https://github.com/Loyalsoldier/v2ray-rules-dat/releases/latest/download/geoip.dat"
GEOSITE_URL="https://github.com/Loyalsoldier/v2ray-rules-dat/releases/latest/download/geosite.dat"

fetch_one() {
    local url="$1"
    local out="$2"
    local size=""
    rm -f "$out"
    if curl -fLs --connect-timeout 10 -m 60 "$url" -o "$out"; then
        size=$(wc -c < "$out" 2>/dev/null | tr -d ' ')
        [[ -n "$size" && "$size" -gt 500000 ]] && return 0
    fi
    return 1
}

targets=0
[[ -d "/usr/local/share/xray" ]] && targets=$((targets + 1))
[[ -d "/etc/sing-box" ]] && targets=$((targets + 1))

if (( targets == 0 )); then
    echo "未检测到 Xray/sing-box，Geo 数据无需更新。"
    exit 0
fi

tmpdir=$(mktemp -d /tmp/aio-geo.XXXXXX) || exit 1
trap 'rm -rf "$tmpdir"' EXIT

fetch_one "$GEOIP_URL" "$tmpdir/geoip.dat" || exit 1
fetch_one "$GEOSITE_URL" "$tmpdir/geosite.dat" || exit 1

if [[ -d "/usr/local/share/xray" ]]; then
    install -m 644 "$tmpdir/geoip.dat" /usr/local/share/xray/geoip.dat
    install -m 644 "$tmpdir/geosite.dat" /usr/local/share/xray/geosite.dat
    if command -v systemctl >/dev/null 2>&1; then systemctl restart xray 2>/dev/null || true; else rc-service xray restart 2>/dev/null || true; fi
fi

if [[ -d "/etc/sing-box" ]]; then
    install -m 644 "$tmpdir/geoip.dat" /etc/sing-box/geoip.dat
    install -m 644 "$tmpdir/geosite.dat" /etc/sing-box/geosite.dat
    if command -v systemctl >/dev/null 2>&1; then systemctl restart sing-box 2>/dev/null || true; else rc-service sing-box restart 2>/dev/null || true; fi
fi

exit 0
EOF
    chmod +x /etc/ddr/geo_update.sh
    
    local tmp_cron
    tmp_cron=$(mktemp)
    crontab -l 2>/dev/null | grep -vE "^no crontab for|^#" | grep -v '/etc/ddr/geo_update.sh' > "$tmp_cron" || true
    echo "0 3 * * 1 /bin/bash /etc/ddr/geo_update.sh >/dev/null 2>&1" >> "$tmp_cron"
    crontab "$tmp_cron" 2>/dev/null
    rm -f "$tmp_cron"
}

validate_downloaded_asset() {
    local f="/tmp/$1"
    case "$1" in
        xray_core.zip)
            unzip -tqq "$f" >/dev/null 2>&1 || die "Xray 压缩包校验失败。"
            ;;
        singbox_core.tar.gz)
            tar -tzf "$f" >/dev/null 2>&1 || die "Sing-box 压缩包校验失败。"
            ;;
        hysteria_core)
            [[ "$(head -c 4 "$f" | od -An -tx1 | tr -d ' \n')" == "7f454c46" ]] || die "Hysteria 下载结果不是 ELF 可执行文件。"
            ;;
        *)
            die "未定义的下载校验规则: $1"
            ;;
    esac
}

# --- [ Asset Fetcher ] ---
fetch_github_release() {
    local repo=$1; local output_file=$2
    local api_url="https://api.github.com/repos/${repo}/releases/latest"
    local asset_re=""

    case "${repo}:${output_file}" in
        XTLS/Xray-core:xray_core.zip)
            asset_re="^Xray-linux-${XRAY_ARCH//+/\\+}\\.zip$"
            ;;
        SagerNet/sing-box:singbox_core.tar.gz)
            asset_re="^sing-box-.*-linux-${SB_ARCH}\\.tar\\.gz$"
            ;;
        apernet/hysteria:hysteria_core)
            asset_re="^hysteria-linux-${HY2_ARCH}$"
            ;;
        *)
            die "未定义的资产匹配规则: ${repo}:${output_file}"
            ;;
    esac

    echo -e "${YELLOW} -> 正在从 GitHub 抓取最新架构版本 [${repo}]...${NC}"

    local download_url
    download_url=$(curl -sL "$api_url" | jq -r --arg re "$asset_re" '
        .assets[]? | select(.name | test($re)) | .browser_download_url
    ' | head -n 1)

    if [[ -z "$download_url" || "$download_url" == "null" ]]; then
        download_url=$(curl -sL "https://ghp.ci/$api_url" | jq -r --arg re "$asset_re" '
            .assets[]? | select(.name | test($re)) | .browser_download_url
        ' | head -n 1)
    fi

    if [[ -n "$download_url" && "$download_url" != "null" ]]; then
        local mirrors=("" "https://ghp.ci/" "https://mirror.ghproxy.com/")
        for mirror in "${mirrors[@]}"; do
            if curl -fLs --connect-timeout 10 "${mirror}${download_url}" -o "/tmp/${output_file}" && [[ -s "/tmp/${output_file}" ]]; then
                validate_downloaded_asset "$output_file"
                echo -e "${GREEN}   ✔ 核心资产提取成功！${NC}"
                return 0
            fi
        done
    fi

    die "所有通道均无法下载核心资产。请检查网络。"
}

write_env() {
    local env_core="$1"
    local env_mode="$2"
    local env_file="/etc/ddr/.env"
    local old_traffic_limit_gb=""
    local old_traffic_limit_mode=""

    if [[ -f "$env_file" ]]; then
        old_traffic_limit_gb=$(grep '^TRAFFIC_LIMIT_GB=' "$env_file" | tail -n 1 | cut -d= -f2- | tr -d '"')
        old_traffic_limit_mode=$(grep '^TRAFFIC_LIMIT_MODE=' "$env_file" | tail -n 1 | cut -d= -f2- | tr -d '"')
    fi

    umask 077
    {
        printf 'CORE=%s\n' "$(shell_quote "$env_core")"
        printf 'MODE=%s\n' "$(shell_quote "$env_mode")"
        printf 'UUID=%s\n' "$(shell_quote "${UUID:-}")"
        printf 'VLESS_SNI=%s\n' "$(shell_quote "${VLESS_SNI:-}")"
        printf 'VLESS_PORT=%s\n' "$(shell_quote "${VLESS_PORT:-}")"
        printf 'XHTTP_PORT=%s\n' "$(shell_quote "${XHTTP_PORT:-}")"
        printf 'HY2_BASE_PORT=%s\n' "$(shell_quote "${HY2_BASE_PORT:-}")"
        printf 'HY2_DOMAIN=%s\n' "$(shell_quote "${HY2_DOMAIN:-}")"
        printf 'HY2_UP=%s\n' "$(shell_quote "${HY2_UP:-}")"
        printf 'HY2_DOWN=%s\n' "$(shell_quote "${HY2_DOWN:-}")"
        printf 'SS_PORT=%s\n' "$(shell_quote "${SS_PORT:-}")"
        printf 'PUBLIC_KEY=%s\n' "$(shell_quote "${PBK:-}")"
        printf 'SHORT_ID=%s\n' "$(shell_quote "${SHORT_ID:-}")"
        printf 'HY2_PASS=%s\n' "$(shell_quote "${HY2_PASS:-}")"
        printf 'HY2_OBFS=%s\n' "$(shell_quote "${HY2_OBFS:-}")"
        printf 'SS_PASS=%s\n' "$(shell_quote "${SS_PASS:-}")"
        printf 'LINK_IP=%s\n' "$(shell_quote "${GLOBAL_PUBLIC_IP:-}")"
        printf 'HY2_CERT_SHA256_FP=%s\n' "$(shell_quote "${HY2_CERT_SHA256_FP:-}")"
        printf 'HY2_CERT_PUBKEY_SHA256_B64=%s\n' "$(shell_quote "${HY2_CERT_PUBKEY_SHA256_B64:-}")"
        printf 'HY2_HOP=%s\n' "$(shell_quote "${HY2_HOP:-}")"
        printf 'HY2_HOP_IMPL=%s\n' "$(shell_quote "${HY2_HOP_IMPL:-none}")"
        printf 'HY2_MONITOR_PORT=%s\n' "$(shell_quote "${HY2_MONITOR_PORT:-}")"
        printf 'HY2_URI_PORTS=%s\n' "$(shell_quote "${HY2_URI_PORTS:-}")"
        printf 'HY2_CLASH_PORTS=%s\n' "$(shell_quote "${HY2_CLASH_PORTS:-}")"
        printf 'HY2_SB_PORTS=%s\n' "$(shell_quote "${HY2_SB_PORTS:-}")"
        printf 'HY2_RANGE_START=%s\n' "$(shell_quote "${HY2_RANGE_START:-}")"
        printf 'HY2_RANGE_END=%s\n' "$(shell_quote "${HY2_RANGE_END:-}")"
        printf 'INGRESS_IF=%s\n' "$(shell_quote "${INGRESS_IF:-}")"
        printf 'ENABLE_KEEPALIVE=%s\n' "$(shell_quote "${ENABLE_KEEPALIVE:-}")"
        
        [[ -n "$old_traffic_limit_gb" ]] && printf 'TRAFFIC_LIMIT_GB=%s\n' "$(shell_quote "$old_traffic_limit_gb")"
        [[ -n "$old_traffic_limit_mode" ]] && printf 'TRAFFIC_LIMIT_MODE=%s\n' "$(shell_quote "$old_traffic_limit_mode")"
    } > "$env_file"
    chmod 600 "$env_file"
}

# --- [5] Pre-install Wizard ---
pre_install_setup() {
    local CORE=$1
    local MODE=$2
    
    local AUTO_SNI="www.samsung.com"
    local DEF_V_PORT=443
    local DEF_X_PORT=8443
    local DEF_H_PORT=443
    local DEF_S_PORT=24043

    if [[ "$CORE" == "xray" && "$MODE" == *"ALL"* ]]; then
        DEF_V_PORT=8443
    fi

    INGRESS_IF=$(get_active_interface)
    [[ -z "$INGRESS_IF" ]] && die "无法识别公网入接口。"

    echo -e "\n${CYAN}======================================================================${NC}"
    echo -e "${BOLD}🚀 参数构造向导 [Engine: $CORE | Mode: $MODE]${NC}"
    echo -e "${BLUE}----------------------------------------------------------------------${NC}"
    
    if [[ "$MODE" == *"VISION"* || "$MODE" == *"XHTTP"* || "$MODE" == *"ALL"* || "$MODE" == "VLESS_SS" ]]; then
        read -ep "   [REALITY] 请输入伪装 SNI (回车默认: $AUTO_SNI): " INPUT_V_SNI
        VLESS_SNI=${INPUT_V_SNI:-$AUTO_SNI}
        valid_sni "$VLESS_SNI" || die "SNI 格式非法: $VLESS_SNI"
    fi
    if [[ "$MODE" == *"VISION"* || "$MODE" == *"ALL"* || "$MODE" == "VLESS_SS" ]]; then
        read -ep "   [VLESS-Vision] 请输入监听端口 (回车默认: $DEF_V_PORT): " INPUT_V_PORT
        VLESS_PORT=${INPUT_V_PORT:-$DEF_V_PORT}
        valid_port "$VLESS_PORT" || die "端口非法: $VLESS_PORT"
    fi
    if [[ "$MODE" == *"XHTTP"* || "$MODE" == *"ALL"* ]]; then
        read -ep "   [VLESS-XHTTP] 请输入监听端口 (回车默认: $DEF_X_PORT): " INPUT_X_PORT
        XHTTP_PORT=${INPUT_X_PORT:-$DEF_X_PORT}
        valid_port "$XHTTP_PORT" || die "端口非法: $XHTTP_PORT"
    fi
    if [[ "$MODE" == *"HY2"* || "$MODE" == *"ALL"* ]]; then
        read -ep "   [HY2] 请输入主监听端口 (回车默认: $DEF_H_PORT): " INPUT_H_PORT
        HY2_BASE_PORT=${INPUT_H_PORT:-$DEF_H_PORT}
        valid_port "$HY2_BASE_PORT" || die "端口非法: $HY2_BASE_PORT"
        
        read -ep "   [HY2] 是否拥有已解析到本机的域名？(留空使用自签证书): " INPUT_H_DOMAIN
        HY2_DOMAIN="$INPUT_H_DOMAIN"
        if [[ -n "$HY2_DOMAIN" ]]; then
            valid_domain "$HY2_DOMAIN" || die "域名格式非法: $HY2_DOMAIN"
            if [[ "$GLOBAL_PUBLIC_IP" != "N/A" ]]; then
                verify_domain_points_to_self "$HY2_DOMAIN" "$GLOBAL_PUBLIC_IP"
            fi
            if [[ "$CORE" == "xray" && "$MODE" == *"ALL"* && "$VLESS_PORT" == "443" ]]; then
                echo -e "${YELLOW}[!] Xray ALL 模式下 HY2 ACME 将强制使用 HTTP-01 (TCP 80)，以避免与 Xray TCP 443 产生冲突。${NC}"
            fi
        fi
        
        read -ep "   [HY2] 是否开启端口跳跃 (中国移动等单端口被限速环境建议开启)? [y/N]: " INPUT_H_HOP
        if [[ "$INPUT_H_HOP" =~ ^[Yy]$ ]]; then 
            HY2_HOP="true"
            HY2_RANGE_START=20000
            HY2_RANGE_END=25000
            
            if [[ "$CORE" == "hysteria" || ( "$CORE" == "xray" && "$MODE" == *"ALL"* ) ]]; then
                HY2_HOP_IMPL="official"
                HY2_URI_PORTS="${HY2_RANGE_START}-${HY2_RANGE_END}"
                HY2_MONITOR_PORT="$HY2_RANGE_START"
            else
                HY2_HOP_IMPL="manual"
                HY2_URI_PORTS="${HY2_BASE_PORT},${HY2_RANGE_START}-${HY2_RANGE_END}"
                HY2_MONITOR_PORT="$HY2_BASE_PORT"
            fi
            
            HY2_CLASH_PORTS="${HY2_RANGE_START}-${HY2_RANGE_END}"
            HY2_SB_PORTS="${HY2_RANGE_START}:${HY2_RANGE_END}"
        else 
            HY2_HOP="false"
            HY2_HOP_IMPL="none"
            HY2_URI_PORTS="$HY2_BASE_PORT"
            HY2_CLASH_PORTS=""
            HY2_SB_PORTS=""
            HY2_MONITOR_PORT="$HY2_BASE_PORT"
        fi
        
        read -ep "   [HY2] 下行速率(Mbps) (回车默认: 1000): " INPUT_H_DOWN
        HY2_DOWN=${INPUT_H_DOWN:-1000}
        valid_positive_int "$HY2_DOWN" || die "速率非法: $HY2_DOWN"
        read -ep "   [HY2] 上行速率(Mbps) (回车默认: 100): " INPUT_H_UP
        HY2_UP=${INPUT_H_UP:-100}
        valid_positive_int "$HY2_UP" || die "速率非法: $HY2_UP"
        
        read -ep "   [HY2] 请输入 HTTP/3 伪装站点 URL (回车默认使用 VLESS SNI 或 https://www.samsung.com/): " INPUT_H_MASQ
        HY2_MASQ_URL=${INPUT_H_MASQ:-"https://${VLESS_SNI:-www.samsung.com}/"}
        valid_url_https "$HY2_MASQ_URL" || die "HY2 伪装 URL 非法: $HY2_MASQ_URL"
    fi
    if [[ "$MODE" == *"SS"* || "$MODE" == *"ALL"* || "$MODE" == "VLESS_SS" ]]; then
        read -ep "   [SS-2022] 请输入回程监听端口(仅TCP) (回车默认: $DEF_S_PORT): " INPUT_S_PORT
        SS_PORT=${INPUT_S_PORT:-$DEF_S_PORT}
        valid_port "$SS_PORT" || die "端口非法: $SS_PORT"
        
        read -ep "   [SS-2022] 请输入前置机白名单 IP/CIDR (留空全网开放, 多个用空格分隔): " INPUT_SS_WL
        SS_WHITELIST_IP="$INPUT_SS_WL"
        
        if [[ -n "$SS_WHITELIST_IP" ]]; then
            for ip in $SS_WHITELIST_IP; do
                if [[ "$ip" == *:* ]]; then
                    valid_ipv6_cidr "$ip" || die "IPv6 白名单地址非法: $ip"
                else
                    valid_ipv4_cidr "$ip" || die "IPv4 白名单地址非法: $ip"
                fi
            done
        fi
    fi
    
    read -ep "   [全局] 是否开启 TCP KeepAlive (45s) 防治NAT空闲断连? [y/N]: " INPUT_KA
    if [[ "$INPUT_KA" =~ ^[Yy]$ ]]; then ENABLE_KEEPALIVE="true"; else ENABLE_KEEPALIVE="false"; fi
    
    echo -e "${CYAN}======================================================================${NC}\n"

    echo -e "${YELLOW}[*] 正在执行防火墙规则前置装载...${NC}"
    check_selected_ports_free
    
    if [[ "$MODE" == *"VISION"* || "$MODE" == *"ALL"* || "$MODE" == "VLESS_SS" ]]; then
        allowPort "$VLESS_PORT" "tcp"
    fi
    if [[ "$MODE" == *"XHTTP"* || "$MODE" == *"ALL"* ]]; then
        allowPort "$XHTTP_PORT" "tcp"
    fi
    if [[ "$MODE" == *"HY2"* || "$MODE" == *"ALL"* ]]; then
        if [[ -n "$HY2_DOMAIN" && ( "$CORE" == "hysteria" || "$MODE" == *"ALL"* ) ]]; then
            allowPort 80 tcp
            allowPort 443 tcp
        fi
        if [[ "$HY2_HOP" == "true" ]]; then 
            allowPort "${HY2_RANGE_START}:${HY2_RANGE_END}" "udp"
            if [[ "$HY2_HOP_IMPL" == "manual" ]]; then
                allowPort "$HY2_BASE_PORT" "udp"
            fi
        else 
            allowPort "$HY2_BASE_PORT" "udp"
        fi
    fi
    if [[ "$MODE" == *"SS"* || "$MODE" == *"ALL"* || "$MODE" == "VLESS_SS" ]]; then
        if [[ -n "$SS_WHITELIST_IP" ]]; then
            for ip in $SS_WHITELIST_IP; do
                if [[ "$ip" == *:* ]]; then
                    if command -v ip6tables >/dev/null 2>&1; then
                        if ! $IPT6 -w -C INPUT -p tcp --dport "$SS_PORT" -s "$ip" -j ACCEPT 2>/dev/null; then
                            $IPT6 -w -I INPUT -p tcp --dport "$SS_PORT" -s "$ip" -m comment --comment "Aio-box-${SS_PORT}-tcp-WL6" -j ACCEPT >/dev/null 2>&1 || die "IPv6 白名单规则写入失败: $ip"
                        fi
                    fi
                else
                    if ! $IPT -w -C INPUT -p tcp --dport "$SS_PORT" -s "$ip" -j ACCEPT 2>/dev/null; then
                        $IPT -w -I INPUT -p tcp --dport "$SS_PORT" -s "$ip" -m comment --comment "Aio-box-${SS_PORT}-tcp-WL" -j ACCEPT >/dev/null 2>&1 || die "IPv4 白名单规则写入失败: $ip"
                    fi
                fi
            done
            if ! $IPT -w -C INPUT -p tcp --dport "$SS_PORT" -j DROP 2>/dev/null; then
                $IPT -w -A INPUT -p tcp --dport "$SS_PORT" -m comment --comment "Aio-box-${SS_PORT}-tcp-DROP" -j DROP >/dev/null 2>&1 || die "IPv4 SS DROP 规则写入失败。"
            fi
            if command -v ip6tables >/dev/null 2>&1; then
                if ! $IPT6 -w -C INPUT -p tcp --dport "$SS_PORT" -j DROP 2>/dev/null; then
                    $IPT6 -w -A INPUT -p tcp --dport "$SS_PORT" -m comment --comment "Aio-box-${SS_PORT}-tcp-DROP6" -j DROP >/dev/null 2>&1 || die "IPv6 SS DROP 规则写入失败。"
                fi
            fi
        else
            allowPort "$SS_PORT" "tcp"
        fi
    fi
    save_firewall_rules
}

# --- [6] Component Deployment ---
deploy_official_hy2() {
    local IS_SILENT=$1
    if [[ "$IS_SILENT" != "SILENT" ]]; then
        clear; echo -e "${BOLD}${GREEN} 部署官方 Hysteria 2 ${NC}"
        init_system_environment
        source /etc/ddr/.env 2>/dev/null || true
        release_ports
        clean_nat_rules
        clean_input_rules
        save_firewall_rules
        pre_install_setup "hysteria" "HY2"
        get_architecture
    fi
    
    fetch_github_release "apernet/hysteria" "hysteria_core"
    install -m 755 /tmp/hysteria_core /usr/local/bin/hysteria || die "安装 hysteria 失败。"
    /usr/local/bin/hysteria version >/dev/null 2>&1 || die "Hysteria 执行校验失败。"
    
    HY2_PASS=$(rand_alnum 20)
    HY2_OBFS=$(rand_alnum 16)
    
    mkdir -p /etc/hysteria
    
    if [[ -n "$HY2_DOMAIN" ]]; then
        TLS_CONFIG="acme:
  domains:
    - ${HY2_DOMAIN}
  email: admin@${HY2_DOMAIN}
  type: http
  http:
    altPort: 80"
        HY2_CERT_SHA256_FP=""
        HY2_CERT_PUBKEY_SHA256_B64=""
    else
        openssl ecparam -genkey -name prime256v1 -out /etc/hysteria/server.key 2>/dev/null
        openssl req -new -x509 -days 36500 -key /etc/hysteria/server.key -out /etc/hysteria/server.crt -subj "/CN=localhost" 2>/dev/null
        chmod 600 /etc/hysteria/server.key
        
        HY2_CERT_SHA256_FP=$(pin_sha256_colon /etc/hysteria/server.crt | tr -d ':')
        HY2_CERT_PUBKEY_SHA256_B64=$(openssl x509 -in /etc/hysteria/server.crt -noout -pubkey | openssl pkey -pubin -outform der | openssl dgst -sha256 -binary | base64)
        
        TLS_CONFIG="tls:
  cert: /etc/hysteria/server.crt
  key: /etc/hysteria/server.key"
    fi
    
    if [[ "$HY2_HOP" == "true" ]]; then
        HY2_LISTEN=":${HY2_RANGE_START}-${HY2_RANGE_END}"
    else
        HY2_LISTEN=":${HY2_BASE_PORT}"
    fi
    
    cat > /etc/hysteria/config.yaml << EOF
listen: ${HY2_LISTEN}
${TLS_CONFIG}
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
masquerade:
  type: proxy
  proxy:
    url: ${HY2_MASQ_URL}
    rewriteHost: true
EOF
    chmod 600 /etc/hysteria/config.yaml

    if [[ "$INIT_SYS" == "systemd" ]]; then
        cat > /etc/systemd/system/hysteria.service << SVC_EOF
[Unit]
Description=Hysteria 2 Service
After=network-online.target
Wants=network-online.target
[Service]
CapabilityBoundingSet=CAP_NET_ADMIN CAP_NET_BIND_SERVICE
AmbientCapabilities=CAP_NET_ADMIN CAP_NET_BIND_SERVICE
ExecStart=/usr/local/bin/hysteria server -c /etc/hysteria/config.yaml
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
        cat > /etc/init.d/hysteria << SVC_EOF
#!/sbin/openrc-run
description="Hysteria 2 Service"
command="/usr/local/bin/hysteria"
command_args="server -c /etc/hysteria/config.yaml"
command_background="yes"
pidfile="/run/hysteria.pid"
depend() { need net; }
SVC_EOF
        chmod +x /etc/init.d/hysteria
    fi
    service_manager start hysteria
    
    setup_geo_cron
    setup_health_monitor
    
    if [[ "$IS_SILENT" != "SILENT" ]]; then
        write_env "hysteria" "HY2"
        view_config "deploy"
    fi
}

deploy_xray() {
    local MODE=$1; clear; echo -e "${BOLD}${GREEN} 部署 Xray-core (Hybrid模式) [$MODE] ${NC}"
    init_system_environment
    source /etc/ddr/.env 2>/dev/null || true
    release_ports
    clean_nat_rules
    clean_input_rules
    save_firewall_rules
    pre_install_setup "xray" "$MODE"
    get_architecture
    
    rm -rf /tmp/xray_ext /tmp/xray_core.zip 2>/dev/null
    fetch_github_release "XTLS/Xray-core" "xray_core.zip"
    
    unzip -qo "/tmp/xray_core.zip" -d /tmp/xray_ext || die "压缩包损坏或解压失败！"
    [[ -f /tmp/xray_ext/xray ]] || die "解压后未找到 xray 主程序。"
    install -m 755 /tmp/xray_ext/xray /usr/local/bin/xray || die "安装 xray 失败。"
    /usr/local/bin/xray version >/dev/null 2>&1 || die "Xray 执行校验失败。"
    mkdir -p /usr/local/share/xray /usr/local/etc/xray
    
    fetch_geo_data "geoip.dat" "https://github.com/Loyalsoldier/v2ray-rules-dat/releases/latest/download/geoip.dat"
    fetch_geo_data "geosite.dat" "https://github.com/Loyalsoldier/v2ray-rules-dat/releases/latest/download/geosite.dat"
    install -m 644 /tmp/geoip.dat /usr/local/share/xray/geoip.dat
    install -m 644 /tmp/geosite.dat /usr/local/share/xray/geosite.dat

    KEYPAIR=$(/usr/local/bin/xray x25519)
    PK=$(echo "$KEYPAIR" | grep -i "Private" | awk '{print $NF}')
    PBK=$(echo "$KEYPAIR" | grep -i "Public" | awk '{print $NF}')
    if [[ -z "$PK" ]]; then die "Xray 密钥生成失败！"; fi
    
    UUID=$(generate_robust_uuid)
    SHORT_ID=$(openssl rand -hex 4 | tr -d '\n\r')
    SS_PASS=$(openssl rand -base64 16 | tr -d '\n\r')
    [[ -n "$SS_PASS" ]] || die "SS-2022 密钥生成失败。"
    
    KA_JSON=""
    if [[ "$ENABLE_KEEPALIVE" == "true" ]]; then
        KA_JSON='"sockopt": { "tcpKeepAliveIdle": 45, "tcpKeepAliveInterval": 45 }'
    fi

    JSON_VLESS_VISION=$(cat << EOF
    {
      "listen": "::", "port": ${VLESS_PORT:-443}, "protocol": "vless",
      "settings": { "clients": [{"id": "${UUID}", "flow": "xtls-rprx-vision"}], "decryption": "none" },
      "streamSettings": {
        "network": "tcp", "security": "reality",
        "realitySettings": { "target": "${VLESS_SNI}:443", "serverNames": ["${VLESS_SNI}"], "privateKey": "${PK}", "shortIds": ["${SHORT_ID}"] }
        ${KA_JSON:+,$KA_JSON}
      },
      "sniffing": { "enabled": true, "destOverride": ["http", "tls", "quic"] }
    }
EOF
)

    JSON_XHTTP=$(cat << EOF
    {
      "listen": "::", "port": ${XHTTP_PORT:-8443}, "protocol": "vless",
      "settings": { "clients": [{"id": "${UUID}"}], "decryption": "none" },
      "streamSettings": {
        "network": "xhttp", "security": "reality",
        "xhttpSettings": { "mode": "auto", "path": "/xhttp" },
        "realitySettings": { "target": "${VLESS_SNI}:443", "serverNames": ["${VLESS_SNI}"], "privateKey": "${PK}", "shortIds": ["${SHORT_ID}"] }
        ${KA_JSON:+,$KA_JSON}
      },
      "sniffing": { "enabled": true, "destOverride": ["http", "tls", "quic"] }
    }
EOF
)

    JSON_SS=$(cat << EOF
    {
      "listen": "::", "port": ${SS_PORT:-24043}, "protocol": "shadowsocks",
      "settings": { "method": "2022-blake3-aes-128-gcm", "password": "${SS_PASS}", "network": "tcp" }
      ${KA_JSON:+,"streamSettings": { $KA_JSON }}
    }
EOF
)

    INBOUNDS_ARRAY=()
    if [[ "$MODE" == *"VISION"* || "$MODE" == *"ALL"* || "$MODE" == "VLESS_SS" ]]; then
        INBOUNDS_ARRAY+=("$JSON_VLESS_VISION")
    fi
    if [[ "$MODE" == *"XHTTP"* || "$MODE" == *"ALL"* ]]; then
        INBOUNDS_ARRAY+=("$JSON_XHTTP")
    fi
    if [[ "$MODE" == *"SS"* || "$MODE" == *"ALL"* || "$MODE" == "VLESS_SS" ]]; then
        INBOUNDS_ARRAY+=("$JSON_SS")
    fi
    INBOUNDS="[$(IFS=,; echo "${INBOUNDS_ARRAY[*]}")]"
    
    cat > /usr/local/etc/xray/config.json << EOF
{
  "log": { "loglevel": "warning", "access": "/var/log/aio-box-xray-access.log", "error": "/var/log/aio-box-xray-error.log" },
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
    
    jq empty /usr/local/etc/xray/config.json >/dev/null 2>&1 || die "Xray JSON 格式非法。"
    /usr/local/bin/xray run -test -config /usr/local/etc/xray/config.json >/dev/null 2>&1 || die "Xray 配置校验失败。"

    if [[ "$INIT_SYS" == "systemd" ]]; then
        cat > /etc/systemd/system/xray.service << SVC_EOF
[Unit]
Description=Xray Service
After=network-online.target nss-lookup.target
Wants=network-online.target
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
    
    setup_geo_cron
    setup_active_defense
    setup_health_monitor
    
    if [[ "$MODE" == *"ALL"* ]]; then
        deploy_official_hy2 "SILENT"
    fi
    write_env "xray" "$MODE"
    view_config "deploy"
}

deploy_singbox() {
    local MODE=$1; clear; echo -e "${BOLD}${GREEN} 部署 Sing-box 核心 [$MODE] ${NC}"
    init_system_environment
    source /etc/ddr/.env 2>/dev/null || true
    release_ports
    clean_nat_rules
    clean_input_rules
    save_firewall_rules
    pre_install_setup "singbox" "$MODE"
    get_architecture
    
    rm -rf /tmp/sing-box-* /tmp/singbox_core.tar.gz /tmp/sing-box /tmp/singbox_ext 2>/dev/null
    fetch_github_release "SagerNet/sing-box" "singbox_core.tar.gz"
    
    mkdir -p /tmp/singbox_ext
    tar -xzf /tmp/singbox_core.tar.gz -C /tmp/singbox_ext || die "Sing-box 压缩包解压失败。"
    
    local SB_PATH=$(find /tmp/singbox_ext -type f -name "sing-box" | head -n 1)
    [[ -n "$SB_PATH" && -f "$SB_PATH" ]] || die "解压后未找到 sing-box 主程序。"
    install -m 755 "$SB_PATH" /usr/local/bin/sing-box || die "安装 sing-box 失败。"
    /usr/local/bin/sing-box version >/dev/null 2>&1 || die "Sing-box 执行校验失败。"
    
    mkdir -p /etc/sing-box
    chmod 700 /etc/sing-box
    
    KEYPAIR=$(/usr/local/bin/sing-box generate reality-keypair)
    PK=$(echo "$KEYPAIR" | grep -i "Private" | awk '{print $NF}')
    PBK=$(echo "$KEYPAIR" | grep -i "Public" | awk '{print $NF}')
    if [[ -z "$PK" ]]; then die "密钥对生成失败"; fi
    UUID=$(generate_robust_uuid)
    SHORT_ID=$(openssl rand -hex 4 | tr -d '\n\r')
    SS_PASS=$(openssl rand -base64 16 | tr -d '\n\r')
    [[ -n "$SS_PASS" ]] || die "SS-2022 密钥生成失败。"
    
    if [[ "$MODE" == *"HY2"* || "$MODE" == *"ALL"* ]]; then
        HY2_PASS=$(rand_alnum 20)
        HY2_OBFS=$(rand_alnum 16)
        openssl ecparam -genkey -name prime256v1 -out /etc/sing-box/hy2.key 2>/dev/null
        local cert_cn="localhost"
        [[ -n "$HY2_DOMAIN" ]] && cert_cn="$HY2_DOMAIN"
        openssl req -new -x509 -days 36500 -key /etc/sing-box/hy2.key -out /etc/sing-box/hy2.crt -subj "/CN=$cert_cn" 2>/dev/null
        chmod 600 /etc/sing-box/hy2.key
        HY2_CERT_SHA256_FP=$(pin_sha256_colon /etc/sing-box/hy2.crt | tr -d ':')
        HY2_CERT_PUBKEY_SHA256_B64=$(openssl x509 -in /etc/sing-box/hy2.crt -noout -pubkey | openssl pkey -pubin -outform der | openssl dgst -sha256 -binary | base64)
    fi

    KA_DELAY=""
    KA_INT=""
    if [[ "$ENABLE_KEEPALIVE" == "true" ]]; then
        KA_DELAY='"tcp_keep_alive": "45s",'
        KA_INT='"tcp_keep_alive_interval": "45s",'
    fi

    JSON_VLESS_VISION=$(cat << EOF
    {
      "type": "vless", "listen": "::", "listen_port": ${VLESS_PORT:-443}, "tcp_fast_open": true,
      ${KA_DELAY} ${KA_INT}
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
      "type": "hysteria2", "listen": "::", "listen_port": ${HY2_BASE_PORT:-443}, "up_mbps": ${HY2_UP:-100}, "down_mbps": ${HY2_DOWN:-1000},
      "obfs": { "type": "salamander", "password": "${HY2_OBFS}" },
      "users": [{"password": "${HY2_PASS}"}],
      "tls": { "enabled": true, "server_name": "${cert_cn}", "certificate_path": "/etc/sing-box/hy2.crt", "key_path": "/etc/sing-box/hy2.key" },
      "masquerade": "${HY2_MASQ_URL}"
    }
EOF
)
    JSON_SS=$(cat << EOF
    {
      "type": "shadowsocks", "listen": "::", "listen_port": ${SS_PORT:-24043}, "tcp_fast_open": true,
      ${KA_DELAY} ${KA_INT}
      "method": "2022-blake3-aes-128-gcm", "password": "${SS_PASS}",
      "network": "tcp",
      "multiplex": { "enabled": true }
    }
EOF
)
    
    INBOUNDS_ARRAY=()
    if [[ "$MODE" == *"VISION"* || "$MODE" == *"ALL"* || "$MODE" == "VLESS_SS" ]]; then
        INBOUNDS_ARRAY+=("$JSON_VLESS_VISION")
    fi
    if [[ "$MODE" == *"HY2"* || "$MODE" == *"ALL"* ]]; then
        INBOUNDS_ARRAY+=("$JSON_HY2")
    fi
    if [[ "$MODE" == *"SS"* || "$MODE" == *"ALL"* || "$MODE" == "VLESS_SS" ]]; then
        INBOUNDS_ARRAY+=("$JSON_SS")
    fi
    INBOUNDS="[$(IFS=,; echo "${INBOUNDS_ARRAY[*]}")]"
    
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
    
    jq empty /etc/sing-box/config.json >/dev/null 2>&1 || die "Sing-box JSON 格式非法。"
    /usr/local/bin/sing-box check -c /etc/sing-box/config.json >/dev/null 2>&1 || die "Sing-box 配置校验失败。"

    if [[ "$INIT_SYS" == "systemd" ]]; then
        SB_PRE_START=""
        SB_POST_STOP=""
        if [[ "$MODE" == *"HY2"* ]] || [[ "$MODE" == *"ALL"* ]]; then
            if [[ "$HY2_HOP" == "true" ]]; then
                SB_PRE_START="ExecStartPre=-/bin/sh -c '$IPT -w -t nat -D PREROUTING -i $INGRESS_IF -p udp --dport ${HY2_RANGE_START}:${HY2_RANGE_END} -m comment --comment \"Aio-box-HY2-HOP\" -j REDIRECT --to-ports $HY2_BASE_PORT 2>/dev/null || true'
ExecStartPre=-/bin/sh -c '$IPT -w -t nat -A PREROUTING -i $INGRESS_IF -p udp --dport ${HY2_RANGE_START}:${HY2_RANGE_END} -m comment --comment \"Aio-box-HY2-HOP\" -j REDIRECT --to-ports $HY2_BASE_PORT 2>/dev/null || true'"
                SB_POST_STOP="ExecStopPost=-/bin/sh -c '$IPT -w -t nat -D PREROUTING -i $INGRESS_IF -p udp --dport ${HY2_RANGE_START}:${HY2_RANGE_END} -m comment --comment \"Aio-box-HY2-HOP\" -j REDIRECT --to-ports $HY2_BASE_PORT 2>/dev/null || true'"
                if has_ipv6 && ipv6_nat_redirect_usable; then
                    SB_PRE_START="$SB_PRE_START
ExecStartPre=-/bin/sh -c '$IPT6 -w -t nat -D PREROUTING -i $INGRESS_IF -p udp --dport ${HY2_RANGE_START}:${HY2_RANGE_END} -m comment --comment \"Aio-box-HY2-HOP\" -j REDIRECT --to-ports $HY2_BASE_PORT 2>/dev/null || true'
ExecStartPre=-/bin/sh -c '$IPT6 -w -t nat -A PREROUTING -i $INGRESS_IF -p udp --dport ${HY2_RANGE_START}:${HY2_RANGE_END} -m comment --comment \"Aio-box-HY2-HOP\" -j REDIRECT --to-ports $HY2_BASE_PORT 2>/dev/null || true'"
                    SB_POST_STOP="$SB_POST_STOP
ExecStopPost=-/bin/sh -c '$IPT6 -w -t nat -D PREROUTING -i $INGRESS_IF -p udp --dport ${HY2_RANGE_START}:${HY2_RANGE_END} -m comment --comment \"Aio-box-HY2-HOP\" -j REDIRECT --to-ports $HY2_BASE_PORT 2>/dev/null || true'"
                fi
            fi
        fi
        cat > /etc/systemd/system/sing-box.service << SVC_EOF
[Unit]
Description=Sing-Box Service
After=network-online.target nss-lookup.target
Wants=network-online.target
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
            if [[ "$HY2_HOP" == "true" ]]; then
                SB_RC_PRE="start_pre() {
  $IPT -w -t nat -D PREROUTING -i $INGRESS_IF -p udp --dport ${HY2_RANGE_START}:${HY2_RANGE_END} -m comment --comment \"Aio-box-HY2-HOP\" -j REDIRECT --to-ports $HY2_BASE_PORT 2>/dev/null || true
  $IPT -w -t nat -A PREROUTING -i $INGRESS_IF -p udp --dport ${HY2_RANGE_START}:${HY2_RANGE_END} -m comment --comment \"Aio-box-HY2-HOP\" -j REDIRECT --to-ports $HY2_BASE_PORT 2>/dev/null || true"
                SB_RC_POST="stop_post() {
  $IPT -w -t nat -D PREROUTING -i $INGRESS_IF -p udp --dport ${HY2_RANGE_START}:${HY2_RANGE_END} -m comment --comment \"Aio-box-HY2-HOP\" -j REDIRECT --to-ports $HY2_BASE_PORT 2>/dev/null || true"
                if has_ipv6 && ipv6_nat_redirect_usable; then
                    SB_RC_PRE="$SB_RC_PRE
  $IPT6 -w -t nat -D PREROUTING -i $INGRESS_IF -p udp --dport ${HY2_RANGE_START}:${HY2_RANGE_END} -m comment --comment \"Aio-box-HY2-HOP\" -j REDIRECT --to-ports $HY2_BASE_PORT 2>/dev/null || true
  $IPT6 -w -t nat -A PREROUTING -i $INGRESS_IF -p udp --dport ${HY2_RANGE_START}:${HY2_RANGE_END} -m comment --comment \"Aio-box-HY2-HOP\" -j REDIRECT --to-ports $HY2_BASE_PORT 2>/dev/null || true"
                    SB_RC_POST="$SB_RC_POST
  $IPT6 -w -t nat -D PREROUTING -i $INGRESS_IF -p udp --dport ${HY2_RANGE_START}:${HY2_RANGE_END} -m comment --comment \"Aio-box-HY2-HOP\" -j REDIRECT --to-ports $HY2_BASE_PORT 2>/dev/null || true"
                fi
                SB_RC_PRE="$SB_RC_PRE
  return 0
}"
                SB_RC_POST="$SB_RC_POST
  return 0
}"
            fi
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
    
    setup_geo_cron
    setup_active_defense
    setup_health_monitor
    
    write_env "singbox" "$MODE"
    view_config "deploy"
}

setup_traffic_monitor() {
    cat > /etc/ddr/traffic_monitor.sh << 'EOF'
#!/bin/bash
PATH=/usr/local/sbin:/usr/local/bin:/sbin:/bin:/usr/sbin:/usr/bin
source /etc/ddr/.env 2>/dev/null || exit 0
[[ -z "$TRAFFIC_LIMIT_GB" ]] && exit 0

INTERFACE=$(ip route get 8.8.8.8 2>/dev/null | awk '{for(i=1;i<=NF;i++) if($i=="dev") print $(i+1)}' | head -n 1)
[[ -z "$INTERFACE" ]] && INTERFACE=$(ip link | awk -F: '$0 !~ "lo|vir|wl|^[^0-9]"{print $2;getline}' | head -n 1 | tr -d ' ')

get_month_total_bytes() {
    local iface="$1"
    local mode="${2:-total}"
    local line
    line=$(vnstat -i "$iface" --oneline b 2>/dev/null) || return 1
    case "$mode" in
        rx)    echo "$line" | awk -F';' '{print $9}' ;;
        tx)    echo "$line" | awk -F';' '{print $10}' ;;
        total) echo "$line" | awk -F';' '{print $11}' ;;
        *) return 1 ;;
    esac
}

bytes_to_gb() {
    awk -v b="$1" 'BEGIN { printf "%.2f", b / 1024 / 1024 / 1024 }'
}

USED_BYTES=$(get_month_total_bytes "$INTERFACE" "${TRAFFIC_LIMIT_MODE:-total}") || exit 0
USED_GB=$(bytes_to_gb "$USED_BYTES")

if (( $(echo "$USED_GB >= $TRAFFIC_LIMIT_GB" | bc -l) )); then
    if command -v systemctl >/dev/null 2>&1; then
        systemctl stop xray sing-box hysteria 2>/dev/null || true
    else
        rc-service xray stop 2>/dev/null || true
        rc-service sing-box stop 2>/dev/null || true
        rc-service hysteria stop 2>/dev/null || true
    fi
    sleep 2
    pgrep -x hysteria >/dev/null 2>&1 && killall -TERM hysteria 2>/dev/null || true
    sleep 2
    pgrep -x hysteria >/dev/null 2>&1 && killall -9 hysteria 2>/dev/null || true
    killall -9 xray sing-box 2>/dev/null || true
fi
EOF
    chmod +x /etc/ddr/traffic_monitor.sh
    local tmp_cron
    tmp_cron=$(mktemp)
    crontab -l 2>/dev/null | grep -vE "^no crontab for|^#" | grep -v '/etc/ddr/traffic_monitor.sh' > "$tmp_cron" || true
    echo "* * * * * /bin/bash /etc/ddr/traffic_monitor.sh >/dev/null 2>&1" >> "$tmp_cron"
    crontab "$tmp_cron" 2>/dev/null
    rm -f "$tmp_cron"
}

disable_traffic_monitor() {
    local tmp_cron
    tmp_cron=$(mktemp)
    crontab -l 2>/dev/null | grep -vE "^no crontab for|^#" | grep -v '/etc/ddr/traffic_monitor.sh' > "$tmp_cron" || true
    crontab "$tmp_cron" 2>/dev/null
    rm -f "$tmp_cron" /etc/ddr/traffic_monitor.sh
}

traffic_management_menu() {
    clear
    echo -e "${CYAN}======================================================================${NC}"
    echo -e "${BOLD}${GREEN} 每月流量管控限制 / Monthly Traffic Management Limit${NC}"
    echo -e "${CYAN}======================================================================${NC}"
    
    local INTERFACE=$(get_active_interface)
    
    echo -e "${YELLOW}[网卡 (Interface) ${INTERFACE} 当前月流量统计 / Current Month Traffic Statistics]${NC}"
    
    echo -e "${CYAN} ► rx (Receive)  : 入站流量 / Inbound (Data flowing INTO the VPS)${NC}"
    echo -e "${CYAN} ► tx (Transmit) : 出站流量 / Outbound (Data flowing FROM the VPS)${NC}"
    echo -e "${CYAN} ► total (Total) : 总吞吐量 / Total (Sum of Inbound and Outbound)${NC}"
    echo -e "${MAGENTA} [提示] AWS/GCP 计费通常仅针对 tx (出站) 流量收费。${NC}"
    echo -e "${BLUE}----------------------------------------------------------------------${NC}"
    
    if command -v vnstat >/dev/null 2>&1; then
        local USED_LINE=$(vnstat -i "$INTERFACE" -m 2>/dev/null | grep -E "^[ ]*$(date +'%Y-%m')")
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
            if valid_positive_int "$limit_gb"; then
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
            
            source /etc/ddr/.env 2>/dev/null
            case "$CORE" in
                xray) service_manager start xray ;;
                singbox) service_manager start sing-box ;;
                hysteria) service_manager start hysteria ;;
            esac
            if [[ "$CORE" == "xray" && "$MODE" == *"ALL"* ]]; then
                service_manager start hysteria
            fi
            
            read -ep "按回车返回 / Press Enter to return..."
            ;;
        *) return 0 ;;
    esac
}

manage_ss_whitelist() {
    clear
    echo -e "${CYAN}======================================================================${NC}"
    echo -e "${BOLD}${GREEN} SS-2022 白名单 IP 管理 / SS-2022 Whitelist Manager${NC}"
    echo -e "${CYAN}======================================================================${NC}"
    source /etc/ddr/.env 2>/dev/null
    if [[ -z "$SS_PORT" ]]; then
        echo -e "${RED}[!] 未检测到已部署的 SS-2022 服务端口，请先安装 SS-2022 节点。${NC}"
        read -ep "按回车返回..."
        return
    fi

    echo -e "${YELLOW}当前 SS-2022 (监听端口: $SS_PORT) 白名单 IP 列表:${NC}"
    $IPT -nL INPUT --line-numbers 2>/dev/null | grep "tcp dpt:$SS_PORT" | grep "ACCEPT" | awk '{print $5}' | grep -v "0.0.0.0/0"
    
    local DROP_RULE=$($IPT -nL INPUT 2>/dev/null | grep "tcp dpt:$SS_PORT" | grep "DROP")
    echo -e "${BLUE}----------------------------------------------------------------------${NC}"
    if [[ -z "$DROP_RULE" ]]; then
        echo -e "${RED}[状态] 当前为全网开放模式 (未开启强制阻断其他 IP)。${NC}"
    else
        echo -e "${GREEN}[状态] 白名单保护模式已开启 (所有非白名单 IP 均会被 DROP)。${NC}"
    fi

    echo -e "${BLUE}----------------------------------------------------------------------${NC}"
    echo -e "${YELLOW}1. 新增白名单 IP${NC}"
    echo -e "${YELLOW}2. 移除白名单 IP${NC}"
    echo -e "${YELLOW}3. 开启白名单模式 (插入 DROP 阻断全网探测)${NC}"
    echo -e "${YELLOW}4. 切换为全网开放 (移除 DROP 阻断)${NC}"
    echo -e "${GREEN}0. 返回主菜单${NC}"
    echo -e "${CYAN}======================================================================${NC}"
    read -ep "请选择操作 [0-4]: " wl_choice

    case $wl_choice in
        1)
            read -ep "请输入要放行的前置机 IP 地址: " add_ip
            if [[ -n "$add_ip" ]]; then
                if [[ "$add_ip" == *:* ]]; then
                    valid_ipv6_cidr "$add_ip" || { echo -e "${RED}[!] IPv6 白名单地址非法: $add_ip${NC}"; read -ep "按回车返回..."; return; }
                    if command -v ip6tables >/dev/null 2>&1; then
                        $IPT6 -w -I INPUT -p tcp --dport "$SS_PORT" -s "$add_ip" -m comment --comment "Aio-box-${SS_PORT}-tcp-WL6" -j ACCEPT >/dev/null 2>&1 || die "IPv6 白名单规则写入失败: $add_ip"
                        save_firewall_rules
                        echo -e "${GREEN}✔ 已成功添加 IP: $add_ip 到白名单。${NC}"
                    else
                        die "系统无 ip6tables，不能添加 IPv6 白名单。"
                    fi
                else
                    valid_ipv4_cidr "$add_ip" || { echo -e "${RED}[!] IPv4 白名单地址非法: $add_ip${NC}"; read -ep "按回车返回..."; return; }
                    if ! $IPT -w -C INPUT -p tcp --dport "$SS_PORT" -s "$add_ip" -j ACCEPT 2>/dev/null; then
                        $IPT -w -I INPUT -p tcp --dport "$SS_PORT" -s "$add_ip" -m comment --comment "Aio-box-${SS_PORT}-tcp-WL" -j ACCEPT >/dev/null 2>&1 || die "IPv4 白名单规则写入失败: $add_ip"
                        save_firewall_rules
                        echo -e "${GREEN}✔ 已成功添加 IP: $add_ip 到白名单。${NC}"
                    else
                        echo -e "${YELLOW}IP: $add_ip 已经在白名单中。${NC}"
                    fi
                fi
            fi
            read -ep "按回车返回..."
            ;;
        2)
            read -ep "请输入要移除的 IP 地址: " del_ip
            if [[ -n "$del_ip" ]]; then
                if [[ "$del_ip" == *:* ]]; then
                    valid_ipv6_cidr "$del_ip" || { echo -e "${RED}[!] IPv6 白名单地址非法: $del_ip${NC}"; read -ep "按回车返回..."; return; }
                    local rule=""
                    local found="0"
                    while $IPT6 -w -S INPUT 2>/dev/null | grep -F "Aio-box-${SS_PORT}-tcp-WL6" | grep -Fq -- "$del_ip"; do
                        rule=$($IPT6 -w -S INPUT 2>/dev/null | grep -F "Aio-box-${SS_PORT}-tcp-WL6" | grep -F -- "$del_ip" | head -n 1 | sed 's/^-A /-D /')
                        [[ -z "$rule" ]] && break
                        $IPT6 -w $rule >/dev/null 2>&1 || die "IPv6 白名单规则删除失败: $del_ip"
                        found="1"
                    done
                    if [[ "$found" == "1" ]]; then
                        save_firewall_rules
                        echo -e "${GREEN}✔ 已成功从白名单移除 IP: $del_ip${NC}"
                    else
                        echo -e "${YELLOW}未在放行列表中找到该 IP。${NC}"
                    fi
                else
                    valid_ipv4_cidr "$del_ip" || { echo -e "${RED}[!] IPv4 白名单地址非法: $del_ip${NC}"; read -ep "按回车返回..."; return; }
                    local rule=""
                    local found="0"
                    while $IPT -w -S INPUT 2>/dev/null | grep -F "Aio-box-${SS_PORT}-tcp-WL" | grep -Fq -- "$del_ip"; do
                        rule=$($IPT -w -S INPUT 2>/dev/null | grep -F "Aio-box-${SS_PORT}-tcp-WL" | grep -F -- "$del_ip" | head -n 1 | sed 's/^-A /-D /')
                        [[ -z "$rule" ]] && break
                        $IPT -w $rule >/dev/null 2>&1 || die "IPv4 白名单规则删除失败: $del_ip"
                        found="1"
                    done
                    if [[ "$found" == "1" ]]; then
                        save_firewall_rules
                        echo -e "${GREEN}✔ 已成功从白名单移除 IP: $del_ip${NC}"
                    else
                        echo -e "${YELLOW}未在放行列表中找到该 IP。${NC}"
                    fi
                fi
            fi
            read -ep "按回车返回..."
            ;;
        3)
            if ! $IPT -w -C INPUT -p tcp --dport "$SS_PORT" -j DROP 2>/dev/null; then
                $IPT -w -A INPUT -p tcp --dport "$SS_PORT" -m comment --comment "Aio-box-${SS_PORT}-tcp-DROP" -j DROP >/dev/null 2>&1 || die "IPv4 SS DROP 规则写入失败。"
                save_firewall_rules
            fi
            if command -v ip6tables >/dev/null 2>&1; then
                if ! $IPT6 -w -C INPUT -p tcp --dport "$SS_PORT" -j DROP 2>/dev/null; then
                    $IPT6 -w -A INPUT -p tcp --dport "$SS_PORT" -m comment --comment "Aio-box-${SS_PORT}-tcp-DROP6" -j DROP >/dev/null 2>&1 || die "IPv6 SS DROP 规则写入失败。"
                fi
            fi
            echo -e "${GREEN}✔ 已开启强制阻断，公网扫描将彻底失效。${NC}"
            read -ep "按回车返回..."
            ;;
        4)
            local rule=""
            while $IPT -w -S INPUT 2>/dev/null | grep -q "Aio-box-${SS_PORT}-tcp-DROP"; do
                rule=$($IPT -w -S INPUT 2>/dev/null | grep "Aio-box-${SS_PORT}-tcp-DROP" | head -n 1 | sed 's/^-A /-D /')
                [[ -z "$rule" ]] && break
                $IPT -w $rule >/dev/null 2>&1 || break
            done
            if command -v ip6tables >/dev/null 2>&1; then
                while $IPT6 -w -S INPUT 2>/dev/null | grep -q "Aio-box-${SS_PORT}-tcp-DROP6"; do
                    rule=$($IPT6 -w -S INPUT 2>/dev/null | grep "Aio-box-${SS_PORT}-tcp-DROP6" | head -n 1 | sed 's/^-A /-D /')
                    [[ -z "$rule" ]] && break
                    $IPT6 -w $rule >/dev/null 2>&1 || break
                done
            fi
            allowPort "$SS_PORT" "tcp"
            save_firewall_rules
            echo -e "${GREEN}✔ 已切换为全网开放模式。${NC}"
            read -ep "按回车返回..."
            ;;
    esac
}

# --- Cleanup ---
do_cleanup() {
    clear; echo -e "${RED}⚠️ 正在执行剥离逻辑... / Executing precision wipe protocol...${NC}"
    init_system_environment
    stop_all_managed_services

    clean_nat_rules
    clean_input_rules
    save_firewall_rules
    
    rm -rf /usr/local/etc/xray \
           /usr/local/share/xray \
           /etc/sing-box \
           /etc/hysteria \
           /usr/local/bin/xray \
           /usr/local/bin/sing-box \
           /usr/local/bin/hysteria
    rm -f /etc/systemd/system/xray.service /etc/systemd/system/sing-box.service /etc/systemd/system/hysteria.service
    rm -f /etc/init.d/xray /etc/init.d/sing-box /etc/init.d/hysteria
    rm -f /etc/sysctl.d/99-aio-box-tune.conf /etc/security/limits.d/aio-box.conf
    sysctl --system >/dev/null 2>&1 || true
    
    local tmp_cron
    tmp_cron=$(mktemp)
    crontab -l 2>/dev/null | grep -vE "^no crontab for|^#" | grep -vE '/etc/ddr/traffic_monitor.sh|/etc/ddr/geo_update.sh|/etc/ddr/socket_probe.sh' > "$tmp_cron" || true
    crontab "$tmp_cron" 2>/dev/null
    rm -f "$tmp_cron"
    
    rm -rf /var/log/aio-box-*.log /etc/fail2ban/jail.d/aio-box.local /etc/fail2ban/filter.d/aio-box.conf /etc/logrotate.d/aio-box 2>/dev/null
    
    if [[ "$INIT_SYS" == "systemd" ]]; then
        systemctl restart fail2ban 2>/dev/null || true
        systemctl daemon-reload 2>/dev/null || true
    elif [[ "$INIT_SYS" == "openrc" ]]; then
        rc-service fail2ban restart 2>/dev/null || true
    fi
    
    if [[ "$1" == "full" ]]; then
        rm -rf /etc/ddr /usr/local/bin/sb
        echo -e "${GREEN}✔ 物理层完全清场完毕！机器重获原生干净状态。 / Nuclear cleanup succeeded!${NC}"
        exit 0
    else
        rm -f /etc/ddr/.env /etc/ddr/.deps*
        rm -f /etc/ddr/traffic_monitor.sh /etc/ddr/geo_update.sh /etc/ddr/socket_probe.sh
        setup_shortcut
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
    echo -e "\033[1;36m[1/5] 执行核心进程锁死检测 / Scanning processes...\033[0m"
    local BAD_PROC=$(ps aux | grep -E 'xray|sing-box|hysteria' | grep -v grep 2>/dev/null)
    if [[ -n "$BAD_PROC" ]]; then
        echo -e "${YELLOW} [!] 发现未受控的进程挂起。执行系统级原子绞杀 / Resolving deadlock...${NC}"
        stop_all_managed_services
        echo -e "${GREEN} ✔ 修复完毕: 系统句柄已强行阻断并释放回内存池 / Resources forcefully reclaimed.${NC}"
    else
        echo -e "${GREEN} ✔ 校验通过: 未发现寻址层争抢冲突 / Process logic healthy.${NC}"
    fi
    echo -e "\n\033[1;36m[2/5] 探查底层 Linux 内核 TCP/IP 过滤链栈 / Analyzing Netfilter topology...\033[0m"
    local NAT_C=$($IPT -t nat -S PREROUTING 2>/dev/null | grep -E "Aio-box-HY2-HOP")
    local INP_C=$($IPT -S INPUT 2>/dev/null | grep -i "Aio-box-")
    local NAT_C6=""
    local INP_C6=""
    if command -v ip6tables >/dev/null 2>&1 && $IPT6 -w -t nat -S PREROUTING >/dev/null 2>&1; then
        NAT_C6=$($IPT6 -t nat -S PREROUTING 2>/dev/null | grep -E "Aio-box-HY2-HOP")
    fi
    if command -v ip6tables >/dev/null 2>&1 && $IPT6 -w -S INPUT >/dev/null 2>&1; then
        INP_C6=$($IPT6 -S INPUT 2>/dev/null | grep -i "Aio-box-")
    fi
    if [[ -n "$NAT_C" || -n "$INP_C" || -n "$NAT_C6" || -n "$INP_C6" ]]; then
        echo -e "${YELLOW} [!] 捕获到废弃的虚假转发脏路由表。执行无损阻断剔除 / Executing targeted firewall reset...${NC}"
        clean_nat_rules
        clean_input_rules
        save_firewall_rules
        echo -e "${GREEN} ✔ 修复完毕: 脏配置链已抹除，且未侵入/破坏其他原生程序运行 / Target chain disinfected.${NC}"
    else
        echo -e "${GREEN} ✔ 校验通过: 防火墙底层逻辑栈纯净无干扰 / Filter stack pristine.${NC}"
    fi
    echo -e "\n\033[1;36m[3/5] 检索系统自持服务管理器索引 / Checking daemon registry indexing...\033[0m"
    
    local tmp_cron
    tmp_cron=$(mktemp)
    crontab -l 2>/dev/null | grep -vE "^no crontab for|^#" | grep -vE '/etc/ddr/traffic_monitor.sh|/etc/ddr/geo_update.sh|/etc/ddr/socket_probe.sh' > "$tmp_cron" || true
    crontab "$tmp_cron" 2>/dev/null
    rm -f "$tmp_cron"
    
    rm -f /etc/ddr/.env /etc/ddr/.deps*
    rm -f /etc/ddr/traffic_monitor.sh /etc/ddr/geo_update.sh /etc/ddr/socket_probe.sh
    rm -rf /var/log/aio-box-*.log 2>/dev/null || true
    rm -f /etc/fail2ban/jail.d/aio-box.local /etc/fail2ban/filter.d/aio-box.conf /etc/logrotate.d/aio-box
    if [[ "$INIT_SYS" == "systemd" ]]; then
        systemctl restart fail2ban 2>/dev/null || true
        systemctl daemon-reload 2>/dev/null || true
    elif [[ "$INIT_SYS" == "openrc" ]]; then
        rc-service fail2ban restart 2>/dev/null || true
    fi

    if [[ -f /etc/systemd/system/xray.service \
       || -f /etc/systemd/system/sing-box.service \
       || -f /etc/systemd/system/hysteria.service \
       || -f /etc/init.d/xray \
       || -f /etc/init.d/sing-box \
       || -f /etc/init.d/hysteria ]]; then
        echo -e "${YELLOW} [!] 检索到失效自启动碎片信息。执行挂载卸载操作 / Unloading daemon fragments...${NC}"
        rm -f /etc/systemd/system/xray.service /etc/systemd/system/sing-box.service /etc/systemd/system/hysteria.service 2>/dev/null
        rm -f /etc/init.d/xray /etc/init.d/sing-box /etc/init.d/hysteria 2>/dev/null
        [[ "$INIT_SYS" == "systemd" ]] && systemctl daemon-reload 2>/dev/null || true
        echo -e "${GREEN} ✔ 修复完毕: 失效索引树已解除并对齐 / Daemon registry flushed.${NC}"
    else
        echo -e "${GREEN} ✔ 校验通过: 服务树状表条目完全干净 / Daemon registry healthy.${NC}"
    fi
    echo -e "\n\033[1;36m[4/5] 校验块文件存储级污染遗存 / Performing disk I/O pollution check...\033[0m"
    local DIR_C=""
    [[ -d /usr/local/etc/xray || -d /etc/sing-box || -d /etc/hysteria || -d /usr/local/share/xray ]] && DIR_C="1"
    if [[ -n "$DIR_C" ]]; then
        echo -e "${YELLOW} [!] 确认存在无效物理配置文件群。执行磁盘擦除程序 / Wiping orphaned configs...${NC}"
        rm -rf /usr/local/etc/xray /usr/local/share/xray /etc/sing-box /etc/hysteria /usr/local/bin/xray /usr/local/bin/sing-box /usr/local/bin/hysteria 2>/dev/null
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

# --- [12] 核心重构: 校验并追杀式注入 1.3.4 功能 / Tune VPS Enhancement ---
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
net.ipv4.tcp_syncookies = 1
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
    if [[ -f /usr/local/etc/xray/config.json ]] && ! grep -q '"tcpKeepAliveIdle": 30' /usr/local/etc/xray/config.json; then
        echo -e "${YELLOW}[*] 正在向 Xray 配置注入 TCP 双向心跳保活参数 (30s)...${NC}"
        cp -f /usr/local/etc/xray/config.json /tmp/xray_config.bak
        if command -v jq >/dev/null 2>&1; then
            if jq '(.inbounds[] | select(.protocol=="vless") | .streamSettings.sockopt) |= {"tcpKeepAliveIdle":30,"tcpKeepAliveInterval":30}' /usr/local/etc/xray/config.json > /tmp/xray_patch.json && [[ -s /tmp/xray_patch.json ]]; then
                mv -f /tmp/xray_patch.json /usr/local/etc/xray/config.json
                jq empty /usr/local/etc/xray/config.json >/dev/null 2>&1 || { mv -f /tmp/xray_config.bak /usr/local/etc/xray/config.json; die "Xray tune 后 JSON 非法，已回滚。"; }
                /usr/local/bin/xray run -test -config /usr/local/etc/xray/config.json >/dev/null 2>&1 || { mv -f /tmp/xray_config.bak /usr/local/etc/xray/config.json; die "Xray tune 后配置校验失败，已回滚。"; }
                service_manager start xray
                echo -e "${GREEN}   ✔ Xray 服务端心跳底层注入完成！${NC}"
            fi
        fi
    fi
    if [[ -f /etc/sing-box/config.json ]] && ! grep -q '"tcp_keep_alive": "30s"' /etc/sing-box/config.json; then
        echo -e "${YELLOW}[*] 正在向 Sing-box 配置注入 TCP 双向心跳保活参数 (30s)...${NC}"
        cp -f /etc/sing-box/config.json /tmp/sb_config.bak
        if command -v jq >/dev/null 2>&1; then
            if jq '(.inbounds[] | select(.type=="vless" or .type=="shadowsocks")) |= . + {"tcp_keep_alive": "30s", "tcp_keep_alive_interval": "30s"}' /etc/sing-box/config.json > /tmp/sb_patch.json && [[ -s /tmp/sb_patch.json ]]; then
                mv -f /tmp/sb_patch.json /etc/sing-box/config.json
                jq empty /etc/sing-box/config.json >/dev/null 2>&1 || { mv -f /tmp/sb_config.bak /etc/sing-box/config.json; die "Sing-box tune 后 JSON 非法，已回滚。"; }
                /usr/local/bin/sing-box check -c /etc/sing-box/config.json >/dev/null 2>&1 || { mv -f /tmp/sb_config.bak /etc/sing-box/config.json; die "Sing-box tune 后配置校验失败，已回滚。"; }
                service_manager start sing-box
                echo -e "${GREEN}   ✔ Sing-box 服务端心跳底层注入完成！${NC}"
            fi
        fi
    fi

    echo -e "${CYAN}\n[*] 正在校验并强制挂载 L4自愈探针(1) / 环形防御(3) / 审计阻断黑洞(4)...${NC}"
    
    if ! crontab -l 2>/dev/null | grep -q '/etc/ddr/socket_probe.sh'; then
        setup_health_monitor
        echo -e "${GREEN}   ✔ L4 内核套接字健康探针校验不通过，已为您重新挂载！${NC}"
    else
        echo -e "${GREEN}   ✔ L4 内核套接字健康探针状态: 已激活${NC}"
    fi

    if [[ ! -f /etc/fail2ban/jail.d/aio-box.local ]] || [[ ! -f /etc/logrotate.d/aio-box ]]; then
        setup_active_defense
        echo -e "${GREEN}   ✔ Fail2Ban 与 Logrotate 环形缓冲防御矩阵已为您重新挂载！${NC}"
    else
        echo -e "${GREEN}   ✔ 环形防御矩阵状态: 已激活${NC}"
    fi

    if [[ -f /usr/local/etc/xray/config.json ]] && ! grep -q "category-ads-all" /usr/local/etc/xray/config.json; then
        cp -f /usr/local/etc/xray/config.json /tmp/xray_config.bak
        if command -v jq >/dev/null 2>&1; then
            if jq '.routing.rules += [{"type": "field", "domain": ["geosite:category-ads-all"], "outboundTag": "block"}] | .log = {"loglevel": "warning", "access": "/var/log/aio-box-xray-access.log", "error": "/var/log/aio-box-xray-error.log"}' /usr/local/etc/xray/config.json > /tmp/xp.json && [[ -s /tmp/xp.json ]]; then
                mv -f /tmp/xp.json /usr/local/etc/xray/config.json
                jq empty /usr/local/etc/xray/config.json >/dev/null 2>&1 || { mv -f /tmp/xray_config.bak /usr/local/etc/xray/config.json; die "Xray 黑名单修补后 JSON 非法，已回滚。"; }
                /usr/local/bin/xray run -test -config /usr/local/etc/xray/config.json >/dev/null 2>&1 || { mv -f /tmp/xray_config.bak /usr/local/etc/xray/config.json; die "Xray 黑名单修补后校验失败，已回滚。"; }
                service_manager start xray
                echo -e "${GREEN}   ✔ Xray 路由拦截黑名单与日志持久化已热重载！${NC}"
            fi
        fi
    fi
    if [[ -f /etc/sing-box/config.json ]] && ! grep -q "aio-box-singbox.log" /etc/sing-box/config.json; then
        cp -f /etc/sing-box/config.json /tmp/sb_config.bak
        if command -v jq >/dev/null 2>&1; then
            if jq '.log = {"level": "warn", "output": "/var/log/aio-box-singbox.log"}' /etc/sing-box/config.json > /tmp/sp.json && [[ -s /tmp/sp.json ]]; then
                mv -f /tmp/sp.json /etc/sing-box/config.json
                jq empty /etc/sing-box/config.json >/dev/null 2>&1 || { mv -f /tmp/sb_config.bak /etc/sing-box/config.json; die "Sing-box 日志修补后 JSON 非法，已回滚。"; }
                /usr/local/bin/sing-box check -c /etc/sing-box/config.json >/dev/null 2>&1 || { mv -f /tmp/sb_config.bak /etc/sing-box/config.json; die "Sing-box 日志修补后校验失败，已回滚。"; }
                service_manager start sing-box
                echo -e "${GREEN}   ✔ Sing-box 日志持久化探针已安全热重载！${NC}"
            fi
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
        1) 
            clear
            echo -e "${YELLOW}[!] 即将远程执行第三方脚本 bench.sh。此操作不属于 Aio-box 本体代码。${NC}"
            read -ep "确认执行？[y/N]: " confirm_remote
            if [[ "$confirm_remote" =~ ^[Yy]$ ]]; then
                echo -e "${GREEN}正在运行 bench.sh... / Running bench.sh...${NC}"
                wget -qO- https://bench.sh | bash
            fi
            read -ep "按回车返回主菜单 / Press Enter to return..."
            ;;
        2) 
            clear
            echo -e "${YELLOW}[!] 即将远程执行第三方脚本 Check.Place。此操作不属于 Aio-box 本体代码。${NC}"
            read -ep "确认执行？[y/N]: " confirm_remote
            if [[ "$confirm_remote" =~ ^[Yy]$ ]]; then
                echo -e "${GREEN}正在运行 Check.Place... / Running Check.Place...${NC}"
                bash <(curl -Ls https://Check.Place) -I
            fi
            read -ep "按回车返回主菜单 / Press Enter to return..."
            ;;
        0|*) return 0 ;;
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

# --- View & Render ---
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
    
    if [[ -z "$LINK_IP" || "$LINK_IP" == "N/A" ]]; then
        echo -e "${YELLOW}[!] 未能自动获取公网 IP，分享链接可能不可用。${NC}"
    fi

    echo -e "${BLUE}======================================================================${NC}\n${BOLD}${CYAN} 全局拓扑网络参数 (${MODE}) / Network Parameters ${NC}\n${BLUE}======================================================================${NC}"
    echo -e "${BOLD}引擎栈 / Engine:${NC} $CORE | ${BOLD}模式 / Mode:${NC} $MODE\n${BLUE}----------------------------------------------------------------------${NC}"
    
    echo -e "${YELLOW}[ 通用分享 URI / General URIs ]${NC}"
    if [[ "$MODE" == *"VISION"* ]] || [[ "$MODE" == *"ALL"* ]] || [[ "$MODE" == "VLESS_SS" ]]; then
        VLESS_URL="vless://$UUID@$F_IP:$VLESS_PORT?encryption=none&flow=xtls-rprx-vision&security=reality&sni=$VLESS_SNI&fp=chrome&pbk=$PUBLIC_KEY&sid=$SHORT_ID&type=tcp#Aio-VLESS-Vision"
        echo -e "${GREEN}${VLESS_URL}${NC}"
        generate_qr "$VLESS_URL"
    fi
    if [[ "$MODE" == *"XHTTP"* ]] || [[ "$MODE" == *"ALL"* ]]; then
        XHTTP_URL="vless://$UUID@$F_IP:$XHTTP_PORT?encryption=none&security=reality&sni=$VLESS_SNI&fp=chrome&pbk=$PUBLIC_KEY&sid=$SHORT_ID&type=xhttp&path=/xhttp&mode=auto#Aio-VLESS-XHTTP"
        echo -e "${GREEN}${XHTTP_URL}${NC}"
        generate_qr "$XHTTP_URL"
    fi
    if [[ "$MODE" == *"HY2"* ]] || [[ "$MODE" == *"ALL"* ]]; then
        if [[ "$CORE" == "singbox" && -n "$HY2_DOMAIN" ]]; then
            echo -e "${YELLOW}[!] Sing-box HY2 当前脚本使用自签证书；域名仅作为 SNI/CN，不自动申请 ACME。客户端仍需 insecure 或证书 pin。${NC}"
        fi
        
        if [[ -n "$HY2_DOMAIN" && "$CORE" != "singbox" ]]; then
            HY2_URL="hysteria2://$HY2_PASS@$HY2_DOMAIN:$HY2_URI_PORTS/?sni=$HY2_DOMAIN&obfs=salamander&obfs-password=$HY2_OBFS#Aio-Hy2-ACME"
            echo -e "${GREEN}${HY2_URL}${NC}"
        else
            local S_IP=$F_IP
            [[ -n "$HY2_DOMAIN" ]] && S_IP=$HY2_DOMAIN
            HY2_URL="hysteria2://$HY2_PASS@$S_IP:$HY2_URI_PORTS/?insecure=1&pinSHA256=$HY2_CERT_SHA256_FP&obfs=salamander&obfs-password=$HY2_OBFS#Aio-Hy2-Self"
            echo -e "${GREEN}${HY2_URL}${NC}"
        fi
        [[ "$HY2_HOP" == "true" ]] && echo -e "${YELLOW}默认端口跳跃间隔为 30s；如客户端支持可手动改，但不建议低于 5s。${NC}"
        generate_qr "$HY2_URL"
    fi
    if [[ "$MODE" == *"SS"* ]] || [[ "$MODE" == *"ALL"* ]] || [[ "$MODE" == "VLESS_SS" ]]; then
        SS_BASE64=$(echo -n "2022-blake3-aes-128-gcm:${SS_PASS}" | base64 -w 0 2>/dev/null || echo -n "2022-blake3-aes-128-gcm:${SS_PASS}" | base64 | tr -d '\n')
        SS_URL="ss://${SS_BASE64}@$F_IP:$SS_PORT#Aio-SS"
        echo -e "${GREEN}${SS_URL}${NC}"
        generate_qr "$SS_URL"
    fi
    
    echo -e "${BLUE}----------------------------------------------------------------------${NC}"
    echo -e "${YELLOW}[ 客户端实现示例 / Client-side Implementation Examples ]${NC}"
    echo -e "${YELLOW}注：SS-2022 仅导出通用 URI；UDP over TCP / multiplex 属于客户端实现策略，需按客户端类型单独配置。${NC}"
    
    echo -e "\n${YELLOW}--- Clash Meta 示例 ---${NC}"
    if [[ "$MODE" == *"VISION"* ]] || [[ "$MODE" == *"ALL"* ]] || [[ "$MODE" == "VLESS_SS" ]]; then
        cat <<EOF
  - name: "Aio-VLESS-Vision"
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
    if [[ "$MODE" == *"XHTTP"* ]] || [[ "$MODE" == *"ALL"* ]]; then
        cat <<EOF
  - name: "Aio-VLESS-XHTTP"
    type: vless
    server: $LINK_IP
    port: $XHTTP_PORT
    uuid: $UUID
    network: xhttp
    tls: true
    udp: true
    xhttp-opts:
      mode: auto
      path: /xhttp
    client-fingerprint: chrome
    servername: $VLESS_SNI
    reality-opts:
      public-key: $PUBLIC_KEY
      short-id: $SHORT_ID
EOF
    fi
    if [[ "$MODE" == *"HY2"* ]] || [[ "$MODE" == *"ALL"* ]]; then
        if [[ -n "$HY2_DOMAIN" && "$CORE" != "singbox" ]]; then
            if [[ "$HY2_HOP" == "true" ]]; then
                cat <<EOF
  - name: "Aio-Hy2-ACME"
    type: hysteria2
    server: $HY2_DOMAIN
    ports: ${HY2_CLASH_PORTS}
    hop-interval: 30
    password: $HY2_PASS
    alpn: [h3]
    sni: $HY2_DOMAIN
    obfs: salamander
    obfs-password: $HY2_OBFS
EOF
            else
                cat <<EOF
  - name: "Aio-Hy2-ACME"
    type: hysteria2
    server: $HY2_DOMAIN
    port: $HY2_BASE_PORT
    password: $HY2_PASS
    alpn: [h3]
    sni: $HY2_DOMAIN
    obfs: salamander
    obfs-password: $HY2_OBFS
EOF
            fi
        else
            local S_IP=$LINK_IP
            [[ -n "$HY2_DOMAIN" ]] && S_IP=$HY2_DOMAIN
            if [[ "$HY2_HOP" == "true" ]]; then
                cat <<EOF
  - name: "Aio-Hy2-Self"
    type: hysteria2
    server: $S_IP
    ports: ${HY2_CLASH_PORTS}
    hop-interval: 30
    password: $HY2_PASS
    alpn: [h3]
    skip-cert-verify: true
    fingerprint: $HY2_CERT_SHA256_FP
    obfs: salamander
    obfs-password: $HY2_OBFS
EOF
            else
                cat <<EOF
  - name: "Aio-Hy2-Self"
    type: hysteria2
    server: $S_IP
    port: $HY2_BASE_PORT
    password: $HY2_PASS
    alpn: [h3]
    skip-cert-verify: true
    fingerprint: $HY2_CERT_SHA256_FP
    obfs: salamander
    obfs-password: $HY2_OBFS
EOF
            fi
        fi
    fi
    if [[ "$MODE" == *"SS"* ]] || [[ "$MODE" == *"ALL"* ]] || [[ "$MODE" == "VLESS_SS" ]]; then
        if [[ "$CORE" == "xray" ]]; then
            cat <<EOF
  - name: "Aio-SS-Xray"
    type: ss
    server: $LINK_IP
    port: $SS_PORT
    cipher: 2022-blake3-aes-128-gcm
    password: $SS_PASS
    udp: true
    udp-over-tcp: true
EOF
        fi
    fi
    
    echo -e "\n${YELLOW}--- Sing-box 示例 ---${NC}"
    if [[ "$MODE" == *"HY2"* ]] || [[ "$MODE" == *"ALL"* ]]; then
        if [[ "$CORE" == "singbox" ]]; then
            local S_IP=$LINK_IP
            [[ -n "$HY2_DOMAIN" ]] && S_IP=$HY2_DOMAIN
            
            if [[ "$HY2_HOP" == "true" ]]; then
                cat <<EOF
    {
      "type": "hysteria2",
      "server": "$S_IP",
      "server_ports": ["$HY2_SB_PORTS"],
      "hop_interval": "30s",
      "password": "$HY2_PASS",
      "tls": {
        "enabled": true,
        "insecure": true,
        "certificate_public_key_sha256": ["$HY2_CERT_PUBKEY_SHA256_B64"]
      },
      "obfs": {
        "type": "salamander",
        "password": "$HY2_OBFS"
      }
    }
EOF
            else
                cat <<EOF
    {
      "type": "hysteria2",
      "server": "$S_IP",
      "server_port": $HY2_BASE_PORT,
      "password": "$HY2_PASS",
      "tls": {
        "enabled": true,
        "insecure": true,
        "certificate_public_key_sha256": ["$HY2_CERT_PUBKEY_SHA256_B64"]
      },
      "obfs": {
        "type": "salamander",
        "password": "$HY2_OBFS"
      }
    }
EOF
            fi
        fi
    fi
    if [[ "$MODE" == *"SS"* ]] || [[ "$MODE" == *"ALL"* ]] || [[ "$MODE" == "VLESS_SS" ]]; then
        if [[ "$CORE" == "singbox" ]]; then
            cat <<EOF
    {
      "type": "shadowsocks",
      "server": "$LINK_IP",
      "server_port": $SS_PORT,
      "method": "2022-blake3-aes-128-gcm",
      "password": "$SS_PASS",
      "multiplex": {
        "enabled": true
      }
    }
EOF
        fi
    fi
    
    if [[ "$MODE" == *"XHTTP"* ]] || [[ "$MODE" == *"ALL"* ]]; then
        echo -e "\n${YELLOW}--- v2rayN / v2rayNG (XHTTP JSON 格式) ---${NC}"
        cat <<EOF
{
  "v": "2", "ps": "Aio-VLESS-XHTTP", "add": "$LINK_IP", "port": "$XHTTP_PORT", "id": "$UUID",
  "net": "xhttp", "type": "none", "path": "/xhttp", "tls": "reality",
  "sni": "$VLESS_SNI", "alpn": "h2", "fp": "chrome", "pbk": "$PUBLIC_KEY", "sid": "$SHORT_ID"
}
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
    echo -e " Xray-core 系列:"
    echo -e " 1. VLESS-Vision-Reality: 最稳健的单 TCP 流长连接特征伪装。"
    echo -e " 2. VLESS-XHTTP-Reality: 最新的流拆分技术，利用 auto 防御高并发环境审计。"
    echo -e " 3. Shadowsocks-2022: 最新标准 AEAD 协议，推荐作为链式后置落地节点。"
    echo -e " 4. Hysteria 2 (原生/Apernet): 原生 UDP 暴力穿透。支持 ACME 真域名与自签证书指纹锁定。"
    echo -e " 5. 全协议四合一 (Xray+Hy2): 物理隔离架构最佳实践 (TCP由Xray接管，UDP由Hy2原生承载)。"
    echo -e " Sing-box 系列 (主打低内存聚合运维):"
    echo -e " 6~10: Sing-box 单一进程管理各协议环境，极低资源消耗。"
    echo -e "${YELLOW}【二】运维与系统强化 / System Enhancement Tools${NC}"
    echo -e " 11. 测速与 IP 审计: 调用 bench.sh 与 Check.Place 检测 VPS 性能与 IP 纯净度。"
    echo -e " 12. VPS一键优化 (BBR Tuning): 注入内核参数，开启 TCP BBR，并修复内核级 TCP KeepAlive。"
    echo -e " 13. 参数显示: 实时生成 URI 分享链接与客户端 YAML / JSON 片段。"
    echo -e " 14. 脚本说明书 / Script Description Document。"
    echo -e " 15. OTA 更新与 Geo 资源: 在线同步 GitHub 获取热更新，及 Loyalsoldier Geo 数据库更替。"
    echo -e " 16. 一键清空: 提供物理级完全清场模式，彻底粉碎防火墙与节点配置。"
    echo -e " 17. 环境自愈: 自动扫描进程死锁、释放 TCP/UDP 占用，恢复系统绝对纯净。"
    echo -e " 18. 流量管控: vnstat 监视并提供月度配额耗尽后服务自动阻断机制。"
    echo -e " 19. SS-2022 白名单管理: 动态新增、删除或阻断 SS-2022 回程的前置机 IP 白名单。"
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
        if bash -n /tmp/aio_update.sh && grep -q "==============================Aio-box===============================" /tmp/aio_update.sh; then
            mv /tmp/aio_update.sh /etc/ddr/aio.sh
            chmod +x /etc/ddr/aio.sh
            echo -e "${GREEN}✔ 校验指纹比对通过！核心代码热更新完毕。 / OTA Engine Execution Complete!${NC}"
            sleep 2
            exec /etc/ddr/aio.sh
        else
            echo -e "${RED}[!] 异常拦截: 更新层发现源码语法错误或指纹校验失败。 / Hash validation error.${NC}"
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
    
    if [[ ! -x /etc/ddr/geo_update.sh ]]; then
        setup_geo_cron
    fi
    
    echo -e "${YELLOW}[*] 正在拉取 Loyalsoldier 增强版 Geo 资源并执行校验... / Fetching Geo Data...${NC}"
    if bash /etc/ddr/geo_update.sh; then
        echo -e "${GREEN}✔ Geo 资源更新与校验成功，已覆盖核心文件并完成热重载！${NC}\n${GREEN}✔ 定时任务已同步下发：每周一夜里 3:00 自动静默执行闭闭环更新。${NC}"
    else
        echo -e "${RED}[!] Geo 资源下载失败或校验未通过，未执行覆盖。${NC}"
    fi
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

# --- [8] Main Loop ---
init_system_environment
setup_shortcut
GLOBAL_PUBLIC_IP=$(get_public_ip)

while true; do
    STATUS_STR=""
    is_service_running xray && STATUS_STR="${GREEN}Xray-Core${NC} "
    is_service_running sing-box && STATUS_STR+="${CYAN}Sing-Box${NC} "
    is_service_running hysteria && STATUS_STR+="${GREEN}Hy2(Native)${NC} "
    [[ -z "$STATUS_STR" ]] && STATUS_STR="${RED}Stack Stopped${NC}"
    
    source /etc/ddr/.env 2>/dev/null && CUR_MODE="[${CORE}-${MODE}]" || CUR_MODE=""
    
    clear; echo -e "${BLUE}======================================================================${NC}\n${BOLD}${YELLOW} ==============================Aio-box===============================${NC}\n${BLUE}======================================================================${NC}"
    echo -e " 网关/Gateway: ${YELLOW}$GLOBAL_PUBLIC_IP${NC} | 核心/Core: $STATUS_STR $CUR_MODE\n${BLUE}----------------------------------------------------------------------${NC}"
    echo -e " ${YELLOW}[ Xray-core 部署/Deployment ]${NC}          ${YELLOW}[ Sing-box 部署/Deployment ]${NC}"
    echo -e " ${GREEN}1.${NC} VLESS-Vision-Reality               ${GREEN}6.${NC} VLESS-Vision-Reality"
    echo -e " ${GREEN}2.${NC} VLESS-XHTTP-Reality                ${GREEN}7.${NC} Shadowsocks-2022"
    echo -e " ${GREEN}3.${NC} Shadowsocks-2022                   ${GREEN}8.${NC} VLESS + SS-2022"
    echo -e " ${GREEN}4.${NC} Hysteria 2 (原生/Apernet)          ${GREEN}9.${NC} Hysteria 2 (Sing-box)"
    echo -e " ${GREEN}5.${NC} 全协议四合一/All (Xray+Hy2)        ${GREEN}10.${NC} 全协议三合一/All (Sing-box)"
    echo -e "${BLUE}----------------------------------------------------------------------${NC}"
    echo -e " ${GREEN}11.${NC} 本机配置与IP测速纯净度 / The purity of local configuration and IP speed test"
    echo -e " ${GREEN}12.${NC} VPS一键优化 / VPS One-click Optimization"
    echo -e " ${GREEN}13.${NC} 全部节点参数显示 / Display of all node parameters"
    echo -e " ${GREEN}14.${NC} 脚本说明书 / Script Description Document"
    echo -e " ${GREEN}15.${NC} 脚本OTA升级与Geo资源更新 / Script OTA & Geo Resource Update"
    echo -e " ${GREEN}16.${NC} 一键全部清空卸载 / One-click to completely clear and uninstall"
    echo -e " ${GREEN}17.${NC} 删除全部节点与环境初始化 / Delete all nodes and perform environment initialization"
    echo -e " ${GREEN}18.${NC} 每月流量管控限制 / Monthly Traffic Management Limit"
    echo -e " ${GREEN}19.${NC} SS-2022 白名单 IP 管理 / SS-2022 Whitelist Manager"
    echo -e " ${GREEN} 0.${NC} 退出脚本 / Exit Script"
    echo -e "${BLUE}======================================================================${NC}"
    read -ep " 请求下发执行代号 / Request input command: " choice
    
    case $choice in
        1) deploy_xray "VISION" ;;
        2) deploy_xray "XHTTP" ;;
        3) deploy_xray "SS" ;;
        4) deploy_official_hy2 "NORMAL" ;;
        5) deploy_xray "ALL" ;;
        6) deploy_singbox "VISION" ;;
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
        19) manage_ss_whitelist ;;
        0) clear; rm -f /var/run/aio_box.lock; exit 0 ;;
        *) sleep 1 ;;
    esac
done
