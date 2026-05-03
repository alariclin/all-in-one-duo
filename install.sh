#!/usr/bin/env bash
# ==============================Aio-box===============================
set -o pipefail
export DEBIAN_FRONTEND=noninteractive
export LANG=${LANG:-en_US.UTF-8}

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;36m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
NC='\033[0m'
BOLD='\033[1m'

DEPS_MARKER='/etc/ddr/.deps.v20260504'
SCRIPT_URL='https://raw.githubusercontent.com/alariclin/aio-box/main/install.sh'
AIO_DIR='/etc/ddr'
AIO_ENV='/etc/ddr/.env'
LOCK_FILE='/var/run/aio_box.lock'

msg() { echo -e "$*"; }
die() { echo -e "${RED}[!] $*${NC}" >&2; exit 1; }
pause_return() { read -r -ep "按回车返回 / Press Enter to return..." _ || true; }

need_interactive_tty() {
    if [[ ! -t 0 ]]; then
        if [[ -r /dev/tty ]]; then
            exec < /dev/tty
        else
            die '当前环境无可交互 TTY，无法运行交互式菜单。'
        fi
    fi
}
valid_port() {
    [[ "${1:-}" =~ ^[0-9]+$ ]] && (( 10#$1 >= 1 && 10#$1 <= 65535 ))
}

valid_port_range() {
    local input="${1:-}" start end
    if [[ "$input" =~ ^([0-9]+):([0-9]+)$ ]]; then
        start="${BASH_REMATCH[1]}"; end="${BASH_REMATCH[2]}"
    elif [[ "$input" =~ ^([0-9]+)-([0-9]+)$ ]]; then
        start="${BASH_REMATCH[1]}"; end="${BASH_REMATCH[2]}"
    else
        return 1
    fi
    valid_port "$start" && valid_port "$end" && (( 10#$start <= 10#$end ))
}

valid_positive_int() {
    [[ "${1:-}" =~ ^[1-9][0-9]*$ ]]
}

valid_domain() {
    local domain="${1:-}"
    [[ ${#domain} -le 253 ]] || return 1
    [[ "$domain" =~ ^([A-Za-z0-9]([A-Za-z0-9-]{0,61}[A-Za-z0-9])?\.)+[A-Za-z]{2,63}$ ]]
}

valid_sni() { valid_domain "$1"; }

valid_url_https() {
    local url="${1:-}" rest host port
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
}

valid_ipv4_cidr() {
    local input="${1:-}" addr mask n
    addr="${input%/*}"
    mask=''
    [[ "$input" == */* ]] && mask="${input#*/}"
    if [[ -n "$mask" ]]; then
        [[ "$mask" =~ ^[0-9]+$ ]] || return 1
        (( 10#$mask >= 0 && 10#$mask <= 32 )) || return 1
    fi
    [[ "$addr" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]] || return 1
    local IFS=.
    local -a octets
    read -r -a octets <<< "$addr"
    for n in "${octets[@]}"; do
        [[ "$n" =~ ^[0-9]+$ ]] || return 1
        (( 10#$n >= 0 && 10#$n <= 255 )) || return 1
    done
}

valid_ipv6_cidr() {
    local input="${1:-}" addr mask
    addr="${input%/*}"
    mask=''
    [[ "$input" == */* ]] && mask="${input#*/}"
    if [[ -n "$mask" ]]; then
        [[ "$mask" =~ ^[0-9]+$ ]] || return 1
        (( 10#$mask >= 0 && 10#$mask <= 128 )) || return 1
    fi
    [[ "$addr" == *:* ]] || return 1
    [[ "$addr" =~ ^[0-9A-Fa-f:.]+$ ]] || return 1
    [[ "$addr" != *':::'* ]] || return 1
    if command -v python3 >/dev/null 2>&1; then
        python3 - "$input" <<'PY' >/dev/null 2>&1
import ipaddress, sys
ipaddress.ip_network(sys.argv[1], strict=False)
PY
        return $?
    fi
    return 0
}

shell_quote() { printf '%q' "${1:-}"; }
json_escape() { jq -Rn --arg v "${1:-}" '$v'; }

rand_alnum() {
    local len="$1" out=''
    while [[ ${#out} -lt "$len" ]]; do
        out+="$(openssl rand -base64 48 | tr -dc 'a-zA-Z0-9')"
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
        u=$(tr -dc 'a-f0-9' < /dev/urandom | fold -w 32 | head -n 1)
        [[ ${#u} -eq 32 ]] || die 'UUID 随机源读取失败。'
        echo "${u:0:8}-${u:8:4}-4${u:13:3}-8${u:17:3}-${u:20:12}"
    fi
}

pin_sha256_colon() {
    openssl x509 -noout -fingerprint -sha256 -in "$1" | cut -d= -f2
}

get_public_ip() {
    local ip api
    for api in 'https://api.ipify.org' 'https://ifconfig.me/ip' 'https://icanhazip.com'; do
        ip=$(curl -s4m5 "$api" 2>/dev/null | tr -d '[:space:]')
        if valid_ipv4_cidr "$ip"; then
            printf '%s\n' "$ip"
            return 0
        fi
    done
    ip=$(curl -s6m5 'https://api64.ipify.org' 2>/dev/null | tr -d '[:space:]')
    if valid_ipv6_cidr "$ip"; then
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
    local domain="$1" pub_ip="$2" resolved continue_domain
    resolved=$(getent ahosts "$domain" 2>/dev/null | awk '{print $1}' | sort -u)
    [[ -z "$resolved" ]] && die "域名无法解析: $domain"
    if [[ "$pub_ip" != 'N/A' ]] && ! grep -Fxq "$pub_ip" <<< "$resolved"; then
        msg "${YELLOW}[!] 域名已解析，但未发现解析到当前公网 IP: $pub_ip${NC}"
        msg "${YELLOW}解析结果:${NC}\n$resolved"
        read -r -ep '仍然继续？[y/N]: ' continue_domain
        [[ "$continue_domain" =~ ^[Yy]$ ]] || die '已取消部署。'
    fi
}

init_system_environment() {
    release=''
    installType=''
    removeType=''
    if [[ -f /etc/os-release ]]; then
        . /etc/os-release
        case "${ID:-}" in
            debian) release='debian'; installType='apt-get -y install'; removeType='apt-get -y autoremove' ;;
            ubuntu) release='ubuntu'; installType='apt-get -y install'; removeType='apt-get -y autoremove' ;;
            alpine) release='alpine'; installType='apk add'; removeType='apk del' ;;
            centos|rhel|rocky|almalinux|fedora) release='centos'; installType='yum -y install'; removeType='yum -y remove' ;;
        esac
    fi
    if [[ -z "$release" ]]; then
        if [[ -f /etc/redhat-release ]] || grep -qiE 'centos|red hat|rocky|almalinux|fedora' /proc/version 2>/dev/null; then
            release='centos'; installType='yum -y install'; removeType='yum -y remove'
        elif grep -qi 'Alpine' /etc/issue /proc/version 2>/dev/null; then
            release='alpine'; installType='apk add'; removeType='apk del'
        elif grep -qi 'debian' /etc/issue /proc/version 2>/dev/null; then
            release='debian'; installType='apt-get -y install'; removeType='apt-get -y autoremove'
        elif grep -qi 'ubuntu' /etc/issue /proc/version 2>/dev/null; then
            release='ubuntu'; installType='apt-get -y install'; removeType='apt-get -y autoremove'
        fi
    fi
    [[ -z "$release" ]] && die '本脚本不支持当前异构系统。'
    if [[ "$release" == 'centos' ]] && command -v dnf >/dev/null 2>&1; then
        installType='dnf -y install'
        removeType='dnf -y remove'
    fi

    if command -v systemctl >/dev/null 2>&1; then
        INIT_SYS='systemd'
    elif command -v rc-service >/dev/null 2>&1; then
        INIT_SYS='openrc'
    else
        die '无法检测到受支持的守护进程初始化系统 (Systemd/OpenRC)。'
    fi

    if [[ ! -f "$DEPS_MARKER" ]]; then
        msg "${YELLOW}[*] 正在同步系统依赖环境 (OS: ${release}, Init: ${INIT_SYS})...${NC}"
        case "$release" in
            debian|ubuntu) apt-get update -y -q >/dev/null 2>&1 ;;
            centos) if command -v dnf >/dev/null 2>&1; then dnf makecache -y -q >/dev/null 2>&1 || true; else yum makecache -y -q >/dev/null 2>&1 || true; fi; ${installType} epel-release >/dev/null 2>&1 || true ;;
            alpine) apk update -q >/dev/null 2>&1 ;;
        esac
        local deps=()
        case "$release" in
            debian|ubuntu)
                deps=(wget curl jq openssl bc unzip vnstat iptables tar psmisc lsof qrencode ca-certificates iproute2 coreutils cron uuid-runtime iptables-persistent netfilter-persistent fail2ban python3)
                command -v ufw >/dev/null 2>&1 && ufw disable >/dev/null 2>&1 || true
                ;;
            centos)
                deps=(wget curl jq openssl bc unzip vnstat iptables tar psmisc lsof qrencode ca-certificates coreutils cronie util-linux bind-utils iproute fail2ban iptables-services epel-release python3)
                ;;
            alpine)
                deps=(bash wget curl jq openssl bc unzip vnstat iptables tar psmisc lsof qrencode ca-certificates iproute2 coreutils util-linux bind-tools procps fail2ban iptables-openrc python3)
                ;;
        esac
        ${installType} "${deps[@]}" >/dev/null 2>&1 || die '基础依赖包安装失败。'
        mkdir -p "$AIO_DIR" && touch "$DEPS_MARKER"
    fi

    ensure_commands

    start_unit_if_exists() {
        local unit="$1"
        systemctl list-unit-files "$unit.service" >/dev/null 2>&1 || return 0
        systemctl enable --now "$unit" >/dev/null 2>&1 || true
    }

    if [[ "$INIT_SYS" == 'systemd' ]]; then
        case "$release" in
            debian|ubuntu) start_unit_if_exists cron ;;
            centos) start_unit_if_exists crond ;;
        esac
        start_unit_if_exists vnstat
        if [[ "$release" == 'centos' ]]; then
            systemctl disable --now firewalld 2>/dev/null || true
            systemctl enable --now iptables ip6tables 2>/dev/null || true
        fi
    else
        rc-update add crond default 2>/dev/null || true
        rc-update add vnstatd default 2>/dev/null || true
        rc-service crond start 2>/dev/null || true
        rc-service vnstatd start 2>/dev/null || true
    fi

    IPT=$(command -v iptables || echo '/sbin/iptables')
    IPT6=$(command -v ip6tables || echo '/sbin/ip6tables')
}

ensure_commands() {
    local missing_pkgs=()
    need_cmd_pkg() {
        local cmd="$1" deb="$2" rpm="$3" apk="$4"
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
    need_cmd_pkg flock util-linux util-linux util-linux
    need_cmd_pkg python3 python3 python3 python3
    if (( ${#missing_pkgs[@]} > 0 )); then
        local unique_pkgs
        unique_pkgs=$(printf '%s\n' "${missing_pkgs[@]}" | awk 'NF && !seen[$0]++')
        msg "${YELLOW}[*] 检测到缺失依赖包，正在补装...${NC}"
        # shellcheck disable=SC2086
        ${installType} $unique_pkgs >/dev/null 2>&1 || die '依赖补装失败。'
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
    $IPT6 -w -t nat -L PREROUTING >/dev/null 2>&1 || return 1
}

get_architecture() {
    local ARCH
    ARCH=$(uname -m)
    case "$ARCH" in
        x86_64|amd64) XRAY_ARCH='64'; SB_ARCH='amd64'; HY2_ARCH='amd64' ;;
        aarch64|arm64|armv8*) XRAY_ARCH='arm64-v8a'; SB_ARCH='arm64'; HY2_ARCH='arm64' ;;
        *) die "无法识别的底层 CPU 架构: $ARCH" ;;
    esac
}

service_manager() {
    local action=$1; shift
    local srv pid
    for srv in "$@"; do
        if [[ "$INIT_SYS" == 'systemd' ]]; then
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
                        journalctl -u "$srv" --no-pager -n 80 2>/dev/null || true
                        die "服务 $srv 拉起失败。"
                    fi
                    ;;
            esac
        else
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
                        die "服务 $srv 拉起失败。"
                    fi
                    ;;
            esac
        fi
    done
}

stop_all_managed_services() {
    service_manager stop xray sing-box hysteria >/dev/null 2>&1 || true
    if [[ "$INIT_SYS" == 'systemd' ]]; then
        local srv pid
        for srv in xray sing-box hysteria; do
            pid=$(systemctl show -p MainPID --value "$srv" 2>/dev/null || true)
            [[ "$pid" =~ ^[0-9]+$ && "$pid" -gt 1 ]] && kill -TERM "$pid" 2>/dev/null || true
        done
    fi
}

is_service_running() {
    local srv=$1
    if [[ "$INIT_SYS" == 'systemd' ]]; then
        systemctl is-active --quiet "$srv"
    else
        rc-service "$srv" status >/dev/null 2>&1
    fi
}

save_firewall_rules() {
    command -v netfilter-persistent >/dev/null 2>&1 && netfilter-persistent save >/dev/null 2>&1 || true
    command -v rc-service >/dev/null 2>&1 && rc-service iptables save >/dev/null 2>&1 || true
    if [[ -d /etc/sysconfig ]]; then
        command -v iptables-save >/dev/null 2>&1 && iptables-save > /etc/sysconfig/iptables 2>/dev/null || true
        command -v ip6tables-save >/dev/null 2>&1 && ip6tables-save > /etc/sysconfig/ip6tables 2>/dev/null || true
    fi
}

allowPort() {
    local port=$1 type=${2:-tcp}
    if ! $IPT -w -C INPUT -p "$type" --dport "$port" -j ACCEPT 2>/dev/null; then
        $IPT -w -I INPUT -p "$type" --dport "$port" -m comment --comment "Aio-box-${port}-${type}" -j ACCEPT >/dev/null 2>&1 || die "IPv4 防火墙放行失败: ${port}/${type}"
    fi
    if has_ipv6 && command -v ip6tables >/dev/null 2>&1 && $IPT6 -w -S INPUT >/dev/null 2>&1; then
        if ! $IPT6 -w -C INPUT -p "$type" --dport "$port" -j ACCEPT 2>/dev/null; then
            $IPT6 -w -I INPUT -p "$type" --dport "$port" -m comment --comment "Aio-box-${port}-${type}" -j ACCEPT >/dev/null 2>&1 || die "IPv6 防火墙放行失败: ${port}/${type}"
        fi
    fi
}

clean_nat_rules() {
    local rule
    while $IPT -w -t nat -S PREROUTING 2>/dev/null | grep -q 'Aio-box-HY2-HOP'; do
        rule=$($IPT -w -t nat -S PREROUTING 2>/dev/null | grep 'Aio-box-HY2-HOP' | head -n 1 | sed 's/^-A /-D /')
        [[ -z "$rule" ]] && break
        # shellcheck disable=SC2086
        $IPT -w -t nat $rule 2>/dev/null || break
    done
    if command -v ip6tables >/dev/null 2>&1 && $IPT6 -w -t nat -S PREROUTING >/dev/null 2>&1; then
        while $IPT6 -w -t nat -S PREROUTING 2>/dev/null | grep -q 'Aio-box-HY2-HOP'; do
            rule=$($IPT6 -w -t nat -S PREROUTING 2>/dev/null | grep 'Aio-box-HY2-HOP' | head -n 1 | sed 's/^-A /-D /')
            [[ -z "$rule" ]] && break
            # shellcheck disable=SC2086
            $IPT6 -w -t nat $rule 2>/dev/null || break
        done
    fi
}

clean_input_rules() {
    local rule
    while $IPT -w -S INPUT 2>/dev/null | grep -q 'Aio-box-'; do
        rule=$($IPT -w -S INPUT 2>/dev/null | grep 'Aio-box-' | head -n 1 | sed 's/^-A /-D /')
        [[ -z "$rule" ]] && break
        # shellcheck disable=SC2086
        $IPT -w $rule 2>/dev/null || break
    done
    if command -v ip6tables >/dev/null 2>&1 && $IPT6 -w -S INPUT >/dev/null 2>&1; then
        while $IPT6 -w -S INPUT 2>/dev/null | grep -q 'Aio-box-'; do
            rule=$($IPT6 -w -S INPUT 2>/dev/null | grep 'Aio-box-' | head -n 1 | sed 's/^-A /-D /')
            [[ -z "$rule" ]] && break
            # shellcheck disable=SC2086
            $IPT6 -w $rule 2>/dev/null || break
        done
    fi
}

add_port_pair() {
    local arr_name="$1" proto="$2" port="$3"
    [[ -n "$port" && "$port" =~ ^[0-9]+$ ]] || return 0
    printf -v "$arr_name" '%s%s/%s\n' "${!arr_name}" "$proto" "$port"
}

selected_port_pairs() {
    local pairs=''
    add_port_pair pairs tcp "${VLESS_PORT:-}"
    add_port_pair pairs tcp "${XHTTP_PORT:-}"
    add_port_pair pairs tcp "${SS_PORT:-}"
    add_port_pair pairs udp "${HY2_BASE_PORT:-}"
    printf '%s' "$pairs"
}

check_selected_ports_free() {
    msg "${YELLOW}[*] 正在检查新选择端口是否被非 Aio-box 进程占用...${NC}"
    local pairs pair proto p holder dup
    pairs=$(selected_port_pairs | awk 'NF')
    dup=$(printf '%s\n' "$pairs" | awk 'NF{seen[$0]++} END{for(k in seen) if(seen[k]>1) print k}' | head -n 1)
    [[ -n "$dup" ]] && die "端口冲突：当前配置中存在重复监听组合 ($dup)。"

    if [[ "${HY2_HOP:-}" == 'true' && -n "${HY2_RANGE_START:-}" && -n "${HY2_RANGE_END:-}" ]]; then
        for pair in $pairs; do
            proto=${pair%/*}; p=${pair#*/}
            if [[ "$proto" == 'udp' ]] && (( p >= HY2_RANGE_START && p <= HY2_RANGE_END )); then
                die "端口冲突：HY2 基础 UDP 端口 ($p) 不能落在跳跃区间 (${HY2_RANGE_START}-${HY2_RANGE_END}) 内。"
            fi
        done
    fi

    for pair in $pairs; do
        proto=${pair%/*}; p=${pair#*/}
        holder=$(ss -H -n -l -p -A "$proto" 2>/dev/null | grep -E "[:.]${p}\b" | grep -vE 'xray|sing-box|hysteria' || true)
        [[ -z "$holder" ]] && continue
        msg "${RED}[!] 新选择端口 ${p}/${proto} 已被非 Aio-box 进程占用：${NC}"
        echo "$holder"
        die "请先手动释放端口 ${p}/${proto}。"
    done

    if [[ "${HY2_HOP:-}" == 'true' && -n "${HY2_RANGE_START:-}" && -n "${HY2_RANGE_END:-}" ]]; then
        holder=$(ss -H -n -l -p -A udp 2>/dev/null | while read -r line; do
            p=$(awk '{print $4}' <<< "$line" | sed -nE 's/.*[:.]([0-9]+)$/\1/p')
            [[ "$p" =~ ^[0-9]+$ ]] || continue
            if (( p >= HY2_RANGE_START && p <= HY2_RANGE_END )); then
                echo "$line"
            fi
        done | grep -vE 'xray|sing-box|hysteria' || true)
        if [[ -n "$holder" ]]; then
            msg "${RED}[!] HY2 UDP 跳跃区间 ${HY2_RANGE_START}-${HY2_RANGE_END} 已被非 Aio-box 进程占用：${NC}"
            echo "$holder"
            die '请先手动释放 HY2 UDP 跳跃区间内的占用端口。'
        fi
    fi
}

release_ports() {
    msg "${YELLOW}[*] 正在停止 Aio-box 托管服务并检查端口占用...${NC}"
    stop_all_managed_services
    sleep 1
    local pairs pair proto p holder
    pairs=$(selected_port_pairs | awk 'NF' | sort -u)
    for pair in $pairs; do
        proto=${pair%/*}; p=${pair#*/}
        holder=$(ss -H -n -l -p -A "$proto" 2>/dev/null | grep -E "[:.]${p}\b" | grep -vE 'xray|sing-box|hysteria' || true)
        [[ -z "$holder" ]] && continue
        msg "${RED}[!] 端口 ${p}/${proto} 已被非 Aio-box 进程占用：${NC}"
        echo "$holder"
        die "请先手动释放端口 ${p}/${proto}。脚本不会自动 kill 非托管进程。"
    done
}

setup_shortcut() {
    mkdir -p "$AIO_DIR"
    if [[ "${1:-}" == 'update' ]]; then
        curl -fLs --connect-timeout 10 "$SCRIPT_URL" -o /tmp/aio.sh.tmp || die '快捷入口脚本下载失败。'
        bash -n /tmp/aio.sh.tmp || die '更新脚本语法校验失败。'
        grep -q '==============================Aio-box===============================' /tmp/aio.sh.tmp || die '更新脚本文本指纹不匹配。'
        mv -f /tmp/aio.sh.tmp "$AIO_DIR/aio.sh"
    elif [[ -f "$0" && -r "$0" && "$0" != 'bash' && "$0" != '-bash' ]]; then
        cp -f "$0" "$AIO_DIR/aio.sh"
    elif [[ ! -f "$AIO_DIR/aio.sh" ]]; then
        curl -fLs --connect-timeout 10 "$SCRIPT_URL" -o /tmp/aio.sh.tmp || die '无法从远端创建持久化入口。'
        bash -n /tmp/aio.sh.tmp || die '持久化脚本语法校验失败。'
        grep -q '==============================Aio-box===============================' /tmp/aio.sh.tmp || die '持久化脚本文本指纹不匹配。'
        mv -f /tmp/aio.sh.tmp "$AIO_DIR/aio.sh"
    fi
    chmod +x "$AIO_DIR/aio.sh"
    cat > /usr/local/bin/sb <<'EOS'
#!/usr/bin/env bash
if [[ $EUID -eq 0 ]]; then
    exec bash /etc/ddr/aio.sh "$@"
elif command -v sudo >/dev/null 2>&1; then
    exec sudo bash /etc/ddr/aio.sh "$@"
else
    echo 'Root privileges required. Please run: su -'
    exit 1
fi
EOS
    chmod +x /usr/local/bin/sb
}

validate_downloaded_asset() {
    local f="/tmp/$1"
    [[ -s "$f" ]] || die "下载资产为空: $1"
    case "$1" in
        xray_core.zip) unzip -tqq "$f" >/dev/null 2>&1 || die 'Xray 压缩包校验失败。' ;;
        singbox_core.tar.gz) tar -tzf "$f" >/dev/null 2>&1 || die 'Sing-box 压缩包校验失败。' ;;
        hysteria_core) [[ "$(head -c 4 "$f" | od -An -tx1 | tr -d ' \n')" == '7f454c46' ]] || die 'Hysteria 下载结果不是 ELF 可执行文件。' ;;
        *) die "未定义的下载校验规则: $1" ;;
    esac
}

github_api_get() {
    local url="$1"
    curl -fLsS --connect-timeout 10 -m 60 \
        -H 'Accept: application/vnd.github+json' \
        -H 'X-GitHub-Api-Version: 2022-11-28' \
        "$url"
}

verify_github_asset_digest() {
    local file="$1" digest="${2:-}" expected actual
    [[ -n "$digest" && "$digest" != 'null' ]] || return 0
    [[ "$digest" == sha256:* ]] || return 0
    expected="${digest#sha256:}"
    [[ "$expected" =~ ^[A-Fa-f0-9]{64}$ ]] || die 'GitHub Release digest 格式异常。'
    actual=$(sha256sum "$file" | awk '{print $1}')
    [[ "${actual,,}" == "${expected,,}" ]] || die 'GitHub Release digest 校验失败。'
}

valid_github_download_url() {
    local repo="$1" url="$2"
    [[ "$url" == "https://github.com/${repo}/releases/download/"* ]]
}

fetch_github_release() {
    local repo=$1 output_file=$2 api_url asset_re release_json asset_json download_url digest mirror tmp_file
    api_url="https://api.github.com/repos/${repo}/releases/latest"
    case "${repo}:${output_file}" in
        XTLS/Xray-core:xray_core.zip) asset_re="^Xray-linux-${XRAY_ARCH//+/\\+}\\.zip$" ;;
        SagerNet/sing-box:singbox_core.tar.gz) asset_re="^sing-box-.*-linux-${SB_ARCH}\\.tar\\.gz$" ;;
        apernet/hysteria:hysteria_core) asset_re="^hysteria-linux-${HY2_ARCH}$" ;;
        *) die "未定义的资产匹配规则: ${repo}:${output_file}" ;;
    esac
    msg "${YELLOW} -> 正在从 GitHub 抓取最新架构版本 [${repo}]...${NC}"

    release_json=$(github_api_get "$api_url" 2>/dev/null) || release_json=''
    if [[ -z "$release_json" ]]; then
        release_json=$(curl -fLsS --connect-timeout 10 -m 60 "https://ghp.ci/$api_url" 2>/dev/null) || release_json=''
    fi
    [[ -n "$release_json" ]] || die 'GitHub Release API 请求失败。'

    asset_json=$(jq -c --arg re "$asset_re" '.assets[]? | select(.name | test($re)) | {url:.browser_download_url,digest:(.digest // "")}' <<< "$release_json" | head -n 1)
    [[ -n "$asset_json" && "$asset_json" != 'null' ]] || die '未能解析核心资产下载地址。'
    download_url=$(jq -r '.url' <<< "$asset_json")
    digest=$(jq -r '.digest // ""' <<< "$asset_json")
    valid_github_download_url "$repo" "$download_url" || die 'GitHub Release 下载地址域名/仓库不匹配。'

    tmp_file="/tmp/${output_file}.download.$$"
    rm -f "$tmp_file" "/tmp/${output_file}"
    for mirror in '' 'https://ghp.ci/' 'https://mirror.ghproxy.com/'; do
        if curl -fLsS --connect-timeout 10 -m 180 "${mirror}${download_url}" -o "$tmp_file"; then
            mv -f "$tmp_file" "/tmp/${output_file}"
            validate_downloaded_asset "$output_file"
            verify_github_asset_digest "/tmp/${output_file}" "$digest"
            msg "${GREEN}   核心资产提取成功。${NC}"
            return 0
        fi
        rm -f "$tmp_file"
    done
    die '所有通道均无法下载核心资产。请检查网络。'
}

fetch_geo_data() {
    local file_name="$1" official_url="$2" out="/tmp/${file_name}" size
    rm -f "$out"
    if curl -fLs --connect-timeout 10 -m 90 "$official_url" -o "$out"; then
        size=$(wc -c < "$out" 2>/dev/null | tr -d ' ')
        [[ -n "$size" && "$size" -gt 500000 ]] && return 0
    fi
    rm -f "$out"
    die "Geo 数据文件 ${file_name} 下载或校验失败。"
}

reset_protocol_vars() {
    unset UUID VLESS_SNI VLESS_PORT XHTTP_PORT HY2_BASE_PORT HY2_DOMAIN HY2_UP HY2_DOWN HY2_MASQ_URL
    unset SS_PORT SS_WHITELIST_IP PUBLIC_KEY PBK SHORT_ID HY2_PASS HY2_OBFS SS_PASS
    unset HY2_CERT_SHA256_FP HY2_CERT_PUBKEY_SHA256_B64 HY2_HOP HY2_HOP_IMPL HY2_MONITOR_PORT
    unset HY2_URI_PORTS HY2_CLASH_PORTS HY2_SB_PORTS HY2_RANGE_START HY2_RANGE_END ENABLE_KEEPALIVE
}

write_env() {
    local env_core="$1" env_mode="$2" old_traffic_limit_gb='' old_traffic_limit_mode=''
    if [[ -f "$AIO_ENV" ]]; then
        old_traffic_limit_gb=$(grep '^TRAFFIC_LIMIT_GB=' "$AIO_ENV" | tail -n 1 | cut -d= -f2- | tr -d '"')
        old_traffic_limit_mode=$(grep '^TRAFFIC_LIMIT_MODE=' "$AIO_ENV" | tail -n 1 | cut -d= -f2- | tr -d '"')
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
        printf 'HY2_MASQ_URL=%s\n' "$(shell_quote "${HY2_MASQ_URL:-}")"
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
    } > "$AIO_ENV"
    chmod 600 "$AIO_ENV"
}

setup_active_defense() {
    msg "${YELLOW}[*] 正在挂载环形缓冲日志与 Fail2Ban 主动防御矩阵...${NC}"
    touch /var/log/aio-box-xray-access.log /var/log/aio-box-xray-error.log /var/log/aio-box-singbox.log 2>/dev/null || true
    chmod 644 /var/log/aio-box-*.log 2>/dev/null || true
    cat > /etc/logrotate.d/aio-box <<'EOF_LOGROTATE'
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
EOF_LOGROTATE
    if command -v fail2ban-client >/dev/null 2>&1; then
        mkdir -p /etc/fail2ban/filter.d /etc/fail2ban/jail.d
        cat > /etc/fail2ban/filter.d/aio-box.conf <<'EOF_F2B_FILTER'
[Definition]
failregex = ^.*(?:rejected|invalid request|bad request|authentication failed).* from <HOST>[: ].*$
            ^.*<HOST>.*(?:rejected|invalid|unauthorized|forbidden).*$
ignoreregex =
EOF_F2B_FILTER
        cat > /etc/fail2ban/jail.d/aio-box.local <<'EOF_F2B_JAIL'
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
EOF_F2B_JAIL
        if [[ "$INIT_SYS" == 'systemd' ]]; then
            systemctl restart fail2ban 2>/dev/null || true
        else
            rc-service fail2ban restart 2>/dev/null || true
        fi
    fi
}

setup_health_monitor() {
    msg "${YELLOW}[*] 正在注入 L4 套接字自愈探针...${NC}"
    mkdir -p "$AIO_DIR"
    cat > "$AIO_DIR/socket_probe.sh" <<'EOF_PROBE'
#!/usr/bin/env bash
PATH=/usr/local/sbin:/usr/local/bin:/sbin:/bin:/usr/sbin:/usr/bin
source /etc/ddr/.env 2>/dev/null || exit 0
[[ -z "${CORE:-}" ]] && exit 0

IPT=$(command -v iptables || echo '/sbin/iptables')
IPT6=$(command -v ip6tables || echo '/sbin/ip6tables')

has_ipv6() {
    ip -6 addr show scope global 2>/dev/null | grep -q inet6 && return 0
    ip -6 route show default 2>/dev/null | grep -q '^default' && return 0
    return 1
}

ipv6_nat_redirect_usable() {
    command -v ip6tables >/dev/null 2>&1 || return 1
    $IPT6 -w -t nat -L PREROUTING >/dev/null 2>&1 || return 1
}

get_month_total_bytes() {
    local iface="$1" mode="${2:-total}" line
    line=$(vnstat -i "$iface" --oneline b 2>/dev/null) || return 1
    case "$mode" in
        rx) echo "$line" | awk -F';' '{print $9}' ;;
        tx) echo "$line" | awk -F';' '{print $10}' ;;
        total) echo "$line" | awk -F';' '{print $11}' ;;
        *) return 1 ;;
    esac
}

bytes_to_gb() { awk -v b="$1" 'BEGIN { printf "%.2f", b / 1024 / 1024 / 1024 }'; }

if [[ -n "${TRAFFIC_LIMIT_GB:-}" ]]; then
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
    local srv="$1"
    [[ "$srv" == 'singbox' ]] && srv='sing-box'
    [[ "$srv" == 'xray-core' ]] && srv='xray'
    if command -v systemctl >/dev/null 2>&1; then
        systemctl restart "$srv" >/dev/null 2>&1 || true
    else
        rc-service "$srv" restart >/dev/null 2>&1 || true
    fi
}

HY2_SRV="$CORE"
[[ "$CORE" == 'singbox' ]] && HY2_SRV='sing-box'
[[ "$CORE" == 'xray' && "$MODE" == *'ALL'* ]] && HY2_SRV='hysteria'

if [[ "${HY2_HOP:-}" == 'true' && "${HY2_HOP_IMPL:-}" == 'manual' && -n "${HY2_RANGE_START:-}" && -n "${HY2_RANGE_END:-}" ]]; then
    if ! $IPT -w -t nat -S PREROUTING 2>/dev/null | grep -q 'Aio-box-HY2-HOP'; then
        check_restart "$HY2_SRV"
        exit 0
    fi
    if has_ipv6 && ipv6_nat_redirect_usable; then
        if ! $IPT6 -w -t nat -S PREROUTING 2>/dev/null | grep -q 'Aio-box-HY2-HOP'; then
            check_restart "$HY2_SRV"
            exit 0
        fi
    fi
fi

if [[ -n "${VLESS_PORT:-}" ]] && ! ss -H -nlt 2>/dev/null | awk '{print $4}' | grep -Eq "[:.]${VLESS_PORT}$"; then
    check_restart "$CORE"; exit 0
fi
if [[ -n "${XHTTP_PORT:-}" ]] && ! ss -H -nlt 2>/dev/null | awk '{print $4}' | grep -Eq "[:.]${XHTTP_PORT}$"; then
    check_restart "$CORE"; exit 0
fi
if [[ -n "${HY2_MONITOR_PORT:-}" ]] && ! ss -H -nlu 2>/dev/null | awk '{print $4}' | grep -Eq "[:.]${HY2_MONITOR_PORT}$"; then
    check_restart "$HY2_SRV"; exit 0
fi
if [[ -n "${SS_PORT:-}" ]] && ! ss -H -nlt 2>/dev/null | awk '{print $4}' | grep -Eq "[:.]${SS_PORT}$"; then
    check_restart "$CORE"; exit 0
fi
EOF_PROBE
    chmod +x "$AIO_DIR/socket_probe.sh"
    local tmp_cron
    tmp_cron=$(mktemp)
    crontab -l 2>/dev/null | grep -vE '^no crontab for|^#' | grep -v '/etc/ddr/socket_probe.sh' > "$tmp_cron" || true
    echo '* * * * * /bin/bash /etc/ddr/socket_probe.sh >/dev/null 2>&1' >> "$tmp_cron"
    crontab "$tmp_cron" 2>/dev/null || true
    rm -f "$tmp_cron"
}

setup_geo_cron() {
    mkdir -p "$AIO_DIR"
    cat > "$AIO_DIR/geo_update.sh" <<'EOF_GEO'
#!/usr/bin/env bash
PATH=/usr/local/sbin:/usr/local/bin:/sbin:/bin:/usr/sbin:/usr/bin
GEOIP_URL='https://github.com/Loyalsoldier/v2ray-rules-dat/releases/latest/download/geoip.dat'
GEOSITE_URL='https://github.com/Loyalsoldier/v2ray-rules-dat/releases/latest/download/geosite.dat'
fetch_one() {
    local url="$1" out="$2" size
    rm -f "$out"
    if curl -fLs --connect-timeout 10 -m 90 "$url" -o "$out"; then
        size=$(wc -c < "$out" 2>/dev/null | tr -d ' ')
        [[ -n "$size" && "$size" -gt 500000 ]] && return 0
    fi
    return 1
}

targets=0
[[ -d '/usr/local/share/xray' ]] && targets=$((targets + 1))
[[ -d '/etc/sing-box' ]] && targets=$((targets + 1))
(( targets == 0 )) && exit 0

tmpdir=$(mktemp -d /tmp/aio-geo.XXXXXX) || exit 1
trap 'rm -rf "$tmpdir"' EXIT
fetch_one "$GEOIP_URL" "$tmpdir/geoip.dat" || exit 1
fetch_one "$GEOSITE_URL" "$tmpdir/geosite.dat" || exit 1

if [[ -d '/usr/local/share/xray' ]]; then
    install -m 644 "$tmpdir/geoip.dat" /usr/local/share/xray/geoip.dat
    install -m 644 "$tmpdir/geosite.dat" /usr/local/share/xray/geosite.dat
    if command -v systemctl >/dev/null 2>&1; then systemctl restart xray 2>/dev/null || true; else rc-service xray restart 2>/dev/null || true; fi
fi
if [[ -d '/etc/sing-box' ]]; then
    install -m 644 "$tmpdir/geoip.dat" /etc/sing-box/geoip.dat
    install -m 644 "$tmpdir/geosite.dat" /etc/sing-box/geosite.dat
    if command -v systemctl >/dev/null 2>&1; then systemctl restart sing-box 2>/dev/null || true; else rc-service sing-box restart 2>/dev/null || true; fi
fi
EOF_GEO
    chmod +x "$AIO_DIR/geo_update.sh"
    local tmp_cron
    tmp_cron=$(mktemp)
    crontab -l 2>/dev/null | grep -vE '^no crontab for|^#' | grep -v '/etc/ddr/geo_update.sh' > "$tmp_cron" || true
    echo '0 3 * * 1 /bin/bash /etc/ddr/geo_update.sh >/dev/null 2>&1' >> "$tmp_cron"
    crontab "$tmp_cron" 2>/dev/null || true
    rm -f "$tmp_cron"
}

pre_install_setup() {
    local CORE_IN=$1 MODE_IN=$2
    reset_protocol_vars
    local AUTO_SNI='www.samsung.com'
    local DEF_V_PORT=443 DEF_X_PORT=8443 DEF_H_PORT=443 DEF_S_PORT=24043
    local INPUT_V_SNI INPUT_V_PORT INPUT_X_PORT INPUT_H_PORT INPUT_H_DOMAIN INPUT_H_HOP INPUT_H_DOWN INPUT_H_UP INPUT_H_MASQ INPUT_S_PORT INPUT_SS_WL INPUT_KA ip

    if [[ "$CORE_IN" == 'xray' && "$MODE_IN" == *'ALL'* ]]; then
        DEF_V_PORT=8443
        DEF_X_PORT=9443
    fi
    if [[ "$CORE_IN" == 'singbox' && "$MODE_IN" == *'ALL'* ]]; then
        DEF_V_PORT=8443
    fi

    INGRESS_IF=$(get_active_interface)
    [[ -z "$INGRESS_IF" ]] && die '无法识别公网入接口。'

    msg "\n${CYAN}======================================================================${NC}"
    msg "${BOLD}参数构造向导 [Engine: $CORE_IN | Mode: $MODE_IN]${NC}"
    msg "${BLUE}----------------------------------------------------------------------${NC}"

    if [[ "$MODE_IN" == *'VISION'* || "$MODE_IN" == *'XHTTP'* || "$MODE_IN" == *'ALL'* || "$MODE_IN" == 'VLESS_SS' ]]; then
        read -r -ep "   [REALITY] 请输入伪装 SNI (回车默认: $AUTO_SNI): " INPUT_V_SNI
        VLESS_SNI=${INPUT_V_SNI:-$AUTO_SNI}
        valid_sni "$VLESS_SNI" || die "SNI 格式非法: $VLESS_SNI"
    fi
    if [[ "$MODE_IN" == *'VISION'* || "$MODE_IN" == *'ALL'* || "$MODE_IN" == 'VLESS_SS' ]]; then
        read -r -ep "   [VLESS-Vision] 请输入监听端口 (回车默认: $DEF_V_PORT): " INPUT_V_PORT
        VLESS_PORT=${INPUT_V_PORT:-$DEF_V_PORT}
        valid_port "$VLESS_PORT" || die "端口非法: $VLESS_PORT"
    fi
    if [[ "$MODE_IN" == *'XHTTP'* || "$MODE_IN" == *'ALL'* ]]; then
        read -r -ep "   [VLESS-XHTTP] 请输入监听端口 (回车默认: $DEF_X_PORT): " INPUT_X_PORT
        XHTTP_PORT=${INPUT_X_PORT:-$DEF_X_PORT}
        valid_port "$XHTTP_PORT" || die "端口非法: $XHTTP_PORT"
    fi
    if [[ "$MODE_IN" == *'HY2'* || "$MODE_IN" == *'ALL'* ]]; then
        read -r -ep "   [HY2] 请输入主监听端口 (回车默认: $DEF_H_PORT): " INPUT_H_PORT
        HY2_BASE_PORT=${INPUT_H_PORT:-$DEF_H_PORT}
        valid_port "$HY2_BASE_PORT" || die "端口非法: $HY2_BASE_PORT"

        read -r -ep '   [HY2] 是否拥有已解析到本机的域名？(留空使用自签证书): ' INPUT_H_DOMAIN
        HY2_DOMAIN="$INPUT_H_DOMAIN"
        if [[ -n "$HY2_DOMAIN" ]]; then
            valid_domain "$HY2_DOMAIN" || die "域名格式非法: $HY2_DOMAIN"
            [[ "${GLOBAL_PUBLIC_IP:-N/A}" != 'N/A' ]] && verify_domain_points_to_self "$HY2_DOMAIN" "$GLOBAL_PUBLIC_IP"
        fi

        read -r -ep '   [HY2] 是否开启端口跳跃 (中国移动等单端口被限速环境建议开启)? [y/N]: ' INPUT_H_HOP
        if [[ "$INPUT_H_HOP" =~ ^[Yy]$ ]]; then
            HY2_HOP='true'
            HY2_RANGE_START=20000
            HY2_RANGE_END=25000
            if [[ "$CORE_IN" == 'hysteria' || ( "$CORE_IN" == 'xray' && "$MODE_IN" == *'ALL'* ) ]]; then
                HY2_HOP_IMPL='official'
                HY2_URI_PORTS="${HY2_RANGE_START}-${HY2_RANGE_END}"
                HY2_MONITOR_PORT="$HY2_RANGE_START"
            else
                HY2_HOP_IMPL='manual'
                HY2_URI_PORTS="${HY2_BASE_PORT},${HY2_RANGE_START}-${HY2_RANGE_END}"
                HY2_MONITOR_PORT="$HY2_BASE_PORT"
            fi
            HY2_CLASH_PORTS="${HY2_RANGE_START}-${HY2_RANGE_END}"
            HY2_SB_PORTS="${HY2_RANGE_START}:${HY2_RANGE_END}"
        else
            HY2_HOP='false'
            HY2_HOP_IMPL='none'
            HY2_URI_PORTS="$HY2_BASE_PORT"
            HY2_CLASH_PORTS=''
            HY2_SB_PORTS=''
            HY2_MONITOR_PORT="$HY2_BASE_PORT"
        fi

        read -r -ep '   [HY2] 下行速率(Mbps) (回车默认: 1000): ' INPUT_H_DOWN
        HY2_DOWN=${INPUT_H_DOWN:-1000}
        valid_positive_int "$HY2_DOWN" || die "速率非法: $HY2_DOWN"
        read -r -ep '   [HY2] 上行速率(Mbps) (回车默认: 100): ' INPUT_H_UP
        HY2_UP=${INPUT_H_UP:-100}
        valid_positive_int "$HY2_UP" || die "速率非法: $HY2_UP"

        read -r -ep '   [HY2] 请输入 HTTP/3 伪装站点 URL (回车默认使用 VLESS SNI 或 https://www.samsung.com/): ' INPUT_H_MASQ
        HY2_MASQ_URL=${INPUT_H_MASQ:-"https://${VLESS_SNI:-www.samsung.com}/"}
        valid_url_https "$HY2_MASQ_URL" || die "HY2 伪装 URL 非法: $HY2_MASQ_URL"
    fi
    if [[ "$MODE_IN" == *'SS'* || "$MODE_IN" == *'ALL'* || "$MODE_IN" == 'VLESS_SS' ]]; then
        read -r -ep "   [SS-2022] 请输入回程监听端口(仅TCP) (回车默认: $DEF_S_PORT): " INPUT_S_PORT
        SS_PORT=${INPUT_S_PORT:-$DEF_S_PORT}
        valid_port "$SS_PORT" || die "端口非法: $SS_PORT"
        read -r -ep '   [SS-2022] 请输入前置机白名单 IP/CIDR (留空全网开放, 多个用空格分隔): ' INPUT_SS_WL
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

    read -r -ep '   [全局] 是否开启 TCP KeepAlive (45s) 防治 NAT 空闲断连? [y/N]: ' INPUT_KA
    [[ "$INPUT_KA" =~ ^[Yy]$ ]] && ENABLE_KEEPALIVE='true' || ENABLE_KEEPALIVE='false'
    msg "${CYAN}======================================================================${NC}\n"

    check_selected_ports_free

    [[ "$MODE_IN" == *'VISION'* || "$MODE_IN" == *'ALL'* || "$MODE_IN" == 'VLESS_SS' ]] && allowPort "$VLESS_PORT" tcp
    [[ "$MODE_IN" == *'XHTTP'* || "$MODE_IN" == *'ALL'* ]] && allowPort "$XHTTP_PORT" tcp
    if [[ "$MODE_IN" == *'HY2'* || "$MODE_IN" == *'ALL'* ]]; then
        if [[ -n "$HY2_DOMAIN" && ( "$CORE_IN" == 'hysteria' || "$MODE_IN" == *'ALL'* ) ]]; then
            allowPort 80 tcp
        fi
        if [[ "$HY2_HOP" == 'true' ]]; then
            allowPort "${HY2_RANGE_START}:${HY2_RANGE_END}" udp
            [[ "$HY2_HOP_IMPL" == 'manual' ]] && allowPort "$HY2_BASE_PORT" udp
        else
            allowPort "$HY2_BASE_PORT" udp
        fi
    fi
    if [[ "$MODE_IN" == *'SS'* || "$MODE_IN" == *'ALL'* || "$MODE_IN" == 'VLESS_SS' ]]; then
        if [[ -n "${SS_WHITELIST_IP:-}" ]]; then
            for ip in $SS_WHITELIST_IP; do
                if [[ "$ip" == *:* ]]; then
                    if has_ipv6 && command -v ip6tables >/dev/null 2>&1 && $IPT6 -w -S INPUT >/dev/null 2>&1; then
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
                $IPT -w -A INPUT -p tcp --dport "$SS_PORT" -m comment --comment "Aio-box-${SS_PORT}-tcp-DROP" -j DROP >/dev/null 2>&1 || die 'IPv4 SS DROP 规则写入失败。'
            fi
            if has_ipv6 && command -v ip6tables >/dev/null 2>&1 && $IPT6 -w -S INPUT >/dev/null 2>&1; then
                if ! $IPT6 -w -C INPUT -p tcp --dport "$SS_PORT" -j DROP 2>/dev/null; then
                    $IPT6 -w -A INPUT -p tcp --dport "$SS_PORT" -m comment --comment "Aio-box-${SS_PORT}-tcp-DROP6" -j DROP >/dev/null 2>&1 || die 'IPv6 SS DROP 规则写入失败。'
                fi
            fi
        else
            allowPort "$SS_PORT" tcp
        fi
    fi
    save_firewall_rules
}

json_sockopt_xray() {
    if [[ "${ENABLE_KEEPALIVE:-}" == 'true' ]]; then
        jq -n '{tcpKeepAliveIdle:45,tcpKeepAliveInterval:45}'
    else
        jq -n 'null'
    fi
}

build_xray_config() {
    local mode="$1" sockopt_json inbounds_json out tmp_out
    sockopt_json=$(json_sockopt_xray)
    inbounds_json=$(jq -n \
        --arg mode "$mode" \
        --arg uuid "$UUID" \
        --arg sni "$VLESS_SNI" \
        --arg pk "$PK" \
        --arg sid "$SHORT_ID" \
        --argjson vport "${VLESS_PORT:-443}" \
        --argjson xport "${XHTTP_PORT:-8443}" \
        --argjson ssport "${SS_PORT:-24043}" \
        --arg ss_pass "$SS_PASS" \
        --argjson sock "$sockopt_json" '
        def maybe_sock: if $sock == null then {} else {sockopt:$sock} end;
        def vision:
          {
            listen:"::", port:$vport, protocol:"vless",
            settings:{clients:[{id:$uuid, flow:"xtls-rprx-vision"}], decryption:"none"},
            streamSettings:({network:"tcp", security:"reality", realitySettings:{target:($sni + ":443"), serverNames:[$sni], privateKey:$pk, shortIds:[$sid]}} + maybe_sock),
            sniffing:{enabled:true, destOverride:["http","tls","quic"]}
          };
        def xhttp:
          {
            listen:"::", port:$xport, protocol:"vless",
            settings:{clients:[{id:$uuid}], decryption:"none"},
            streamSettings:({network:"xhttp", security:"reality", xhttpSettings:{mode:"auto", path:"/xhttp"}, realitySettings:{target:($sni + ":443"), serverNames:[$sni], privateKey:$pk, shortIds:[$sid]}} + maybe_sock),
            sniffing:{enabled:true, destOverride:["http","tls","quic"]}
          };
        def ss:
          ({listen:"::", port:$ssport, protocol:"shadowsocks", settings:{method:"2022-blake3-aes-128-gcm", password:$ss_pass, network:"tcp"}}
           + (if $sock == null then {} else {streamSettings:{sockopt:$sock}} end));
        []
        | if ($mode|contains("VISION")) or ($mode|contains("ALL")) or $mode == "VLESS_SS" then . + [vision] else . end
        | if ($mode|contains("XHTTP")) or ($mode|contains("ALL")) then . + [xhttp] else . end
        | if ($mode|contains("SS")) or ($mode|contains("ALL")) or $mode == "VLESS_SS" then . + [ss] else . end
    ')
    out="${XRAY_CONFIG_PATH:-/usr/local/etc/xray/config.json}"
    tmp_out="${out}.tmp.$$"
    mkdir -p "$(dirname "$out")"
    jq -n --argjson inbounds "$inbounds_json" '{
        log:{loglevel:"warning", access:"/var/log/aio-box-xray-access.log", error:"/var/log/aio-box-xray-error.log"},
        routing:{domainStrategy:"IPIfNonMatch", rules:[
            {type:"field", protocol:["bittorrent"], outboundTag:"block"},
            {type:"field", domain:["geosite:category-ads-all"], outboundTag:"block"}
        ]},
        inbounds:$inbounds,
        outbounds:[{protocol:"freedom", tag:"direct"}, {protocol:"blackhole", tag:"block"}]
    }' > "$tmp_out" || { rm -f "$tmp_out"; die 'Xray JSON 生成失败。'; }
    mv -f "$tmp_out" "$out"
}

build_singbox_config() {
    local mode="$1" inbounds_json ka_obj cert_cn='localhost' out tmp_out
    [[ -n "${HY2_DOMAIN:-}" ]] && cert_cn="$HY2_DOMAIN"
    if [[ "${ENABLE_KEEPALIVE:-}" == 'true' ]]; then
        ka_obj='{"tcp_keep_alive":"45s","tcp_keep_alive_interval":"45s"}'
    else
        ka_obj='{}'
    fi
    inbounds_json=$(jq -n \
        --arg mode "$mode" \
        --arg uuid "$UUID" \
        --arg sni "$VLESS_SNI" \
        --arg pk "$PK" \
        --arg sid "$SHORT_ID" \
        --argjson vport "${VLESS_PORT:-443}" \
        --argjson hy2port "${HY2_BASE_PORT:-443}" \
        --argjson ssport "${SS_PORT:-24043}" \
        --argjson hy2up "${HY2_UP:-100}" \
        --argjson hy2down "${HY2_DOWN:-1000}" \
        --arg hy2pass "${HY2_PASS:-}" \
        --arg hy2obfs "${HY2_OBFS:-}" \
        --arg cert_cn "$cert_cn" \
        --arg masq "${HY2_MASQ_URL:-https://www.samsung.com/}" \
        --arg ss_pass "${SS_PASS:-}" \
        --argjson ka "$ka_obj" '
        def vision:
          ({
            type:"vless", listen:"::", listen_port:$vport, tcp_fast_open:true,
            users:[{uuid:$uuid, flow:"xtls-rprx-vision"}],
            tls:{enabled:true, server_name:$sni, reality:{enabled:true, handshake:{server:$sni, server_port:443}, private_key:$pk, short_id:[$sid]}}
          } + $ka);
        def hy2:
          {
            type:"hysteria2", listen:"::", listen_port:$hy2port, up_mbps:$hy2up, down_mbps:$hy2down,
            obfs:{type:"salamander", password:$hy2obfs},
            users:[{password:$hy2pass}],
            tls:{enabled:true, server_name:$cert_cn, certificate_path:"/etc/sing-box/hy2.crt", key_path:"/etc/sing-box/hy2.key"},
            masquerade:$masq
          };
        def ss:
          ({
            type:"shadowsocks", listen:"::", listen_port:$ssport, tcp_fast_open:true,
            method:"2022-blake3-aes-128-gcm", password:$ss_pass, network:"tcp"
          } + $ka);
        []
        | if ($mode|contains("VISION")) or ($mode|contains("ALL")) or $mode == "VLESS_SS" then . + [vision] else . end
        | if ($mode|contains("HY2")) or ($mode|contains("ALL")) then . + [hy2] else . end
        | if ($mode|contains("SS")) or ($mode|contains("ALL")) or $mode == "VLESS_SS" then . + [ss] else . end
    ')
    out="${SINGBOX_CONFIG_PATH:-/etc/sing-box/config.json}"
    tmp_out="${out}.tmp.$$"
    mkdir -p "$(dirname "$out")"
    jq -n --argjson inbounds "$inbounds_json" '{
        log:{level:"warn", output:"/var/log/aio-box-singbox.log"},
        route:{rules:[{protocol:"bittorrent", outbound:"block"}], auto_detect_interface:true},
        inbounds:$inbounds,
        outbounds:[{type:"direct", tag:"direct"}, {type:"block", tag:"block"}]
    }' > "$tmp_out" || { rm -f "$tmp_out"; die 'Sing-box JSON 生成失败。'; }
    mv -f "$tmp_out" "$out"
}

deploy_official_hy2() {
    local IS_SILENT=${1:-NORMAL} TLS_CONFIG HY2_LISTEN cert_cn
    if [[ "$IS_SILENT" != 'SILENT' ]]; then
        clear; msg "${BOLD}${GREEN}部署官方 Hysteria 2${NC}"
        init_system_environment
        source "$AIO_ENV" 2>/dev/null || true
        release_ports
        clean_nat_rules
        clean_input_rules
        save_firewall_rules
        pre_install_setup hysteria HY2
        get_architecture
    fi

    fetch_github_release apernet/hysteria hysteria_core
    install -m 755 /tmp/hysteria_core /usr/local/bin/hysteria || die '安装 hysteria 失败。'
    /usr/local/bin/hysteria version >/dev/null 2>&1 || die 'Hysteria 执行校验失败。'

    HY2_PASS=$(rand_alnum 20)
    HY2_OBFS=$(rand_alnum 16)
    mkdir -p /etc/hysteria

    if [[ -n "${HY2_DOMAIN:-}" ]]; then
        TLS_CONFIG="acme:
  domains:
    - ${HY2_DOMAIN}
  email: admin@${HY2_DOMAIN}
  type: http
  http:
    altPort: 80"
        HY2_CERT_SHA256_FP=''
        HY2_CERT_PUBKEY_SHA256_B64=''
    else
        openssl ecparam -genkey -name prime256v1 -out /etc/hysteria/server.key 2>/dev/null
        openssl req -new -x509 -days 36500 -key /etc/hysteria/server.key -out /etc/hysteria/server.crt -subj '/CN=localhost' 2>/dev/null
        chmod 600 /etc/hysteria/server.key
        HY2_CERT_SHA256_FP=$(pin_sha256_colon /etc/hysteria/server.crt | tr -d ':')
        HY2_CERT_PUBKEY_SHA256_B64=$(openssl x509 -in /etc/hysteria/server.crt -noout -pubkey | openssl pkey -pubin -outform der | openssl dgst -sha256 -binary | base64 | tr -d '\n')
        TLS_CONFIG="tls:
  cert: /etc/hysteria/server.crt
  key: /etc/hysteria/server.key"
    fi

    if [[ "${HY2_HOP:-}" == 'true' ]]; then
        HY2_LISTEN=":${HY2_RANGE_START}-${HY2_RANGE_END}"
    else
        HY2_LISTEN=":${HY2_BASE_PORT}"
    fi

    cat > /etc/hysteria/config.yaml <<EOF_HY2
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
EOF_HY2
    chmod 600 /etc/hysteria/config.yaml

    if [[ "$INIT_SYS" == 'systemd' ]]; then
        cat > /etc/systemd/system/hysteria.service <<'EOF_SVC'
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
EOF_SVC
    else
        mkdir -p /etc/conf.d
        echo 'rc_ulimit="-n 1048576"' > /etc/conf.d/hysteria
        cat > /etc/init.d/hysteria <<'EOF_SVC'
#!/sbin/openrc-run
description="Hysteria 2 Service"
command="/usr/local/bin/hysteria"
command_args="server -c /etc/hysteria/config.yaml"
command_background="yes"
pidfile="/run/hysteria.pid"
depend() { need net; }
EOF_SVC
        chmod +x /etc/init.d/hysteria
    fi
    service_manager start hysteria
    setup_geo_cron
    setup_health_monitor
    if [[ "$IS_SILENT" != 'SILENT' ]]; then
        write_env hysteria HY2
        view_config deploy
    fi
}

deploy_xray() {
    local MODE_IN=$1 KEYPAIR PK_LOCAL
    clear; msg "${BOLD}${GREEN}部署 Xray-core [$MODE_IN]${NC}"
    init_system_environment
    source "$AIO_ENV" 2>/dev/null || true
    release_ports
    clean_nat_rules
    clean_input_rules
    save_firewall_rules
    pre_install_setup xray "$MODE_IN"
    get_architecture

    rm -rf /tmp/xray_ext /tmp/xray_core.zip 2>/dev/null
    fetch_github_release XTLS/Xray-core xray_core.zip
    unzip -qo /tmp/xray_core.zip -d /tmp/xray_ext || die 'Xray 压缩包解压失败。'
    [[ -f /tmp/xray_ext/xray ]] || die '解压后未找到 xray 主程序。'
    install -m 755 /tmp/xray_ext/xray /usr/local/bin/xray || die '安装 xray 失败。'
    /usr/local/bin/xray version >/dev/null 2>&1 || die 'Xray 执行校验失败。'
    mkdir -p /usr/local/share/xray /usr/local/etc/xray

    fetch_geo_data geoip.dat 'https://github.com/Loyalsoldier/v2ray-rules-dat/releases/latest/download/geoip.dat'
    fetch_geo_data geosite.dat 'https://github.com/Loyalsoldier/v2ray-rules-dat/releases/latest/download/geosite.dat'
    install -m 644 /tmp/geoip.dat /usr/local/share/xray/geoip.dat
    install -m 644 /tmp/geosite.dat /usr/local/share/xray/geosite.dat

    KEYPAIR=$(/usr/local/bin/xray x25519)
    PK=$(awk '/Private/{print $NF}' <<< "$KEYPAIR")
    PBK=$(awk '/Public/{print $NF}' <<< "$KEYPAIR")
    [[ -n "$PK" && -n "$PBK" ]] || die 'Xray REALITY 密钥生成失败。'
    UUID=$(generate_robust_uuid)
    SHORT_ID=$(openssl rand -hex 4 | tr -d '\n\r')
    SS_PASS=$(openssl rand -base64 16 | tr -d '\n\r')
    [[ -n "$SS_PASS" ]] || die 'SS-2022 密钥生成失败。'

    build_xray_config "$MODE_IN"
    chmod 600 /usr/local/etc/xray/config.json
    jq empty /usr/local/etc/xray/config.json >/dev/null 2>&1 || die 'Xray JSON 格式非法。'
    /usr/local/bin/xray run -test -config /usr/local/etc/xray/config.json >/dev/null 2>&1 || die 'Xray 配置校验失败。'

    if [[ "$INIT_SYS" == 'systemd' ]]; then
        cat > /etc/systemd/system/xray.service <<'EOF_SVC'
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
EOF_SVC
    else
        mkdir -p /etc/conf.d
        echo 'rc_ulimit="-n 1048576"' > /etc/conf.d/xray
        echo 'XRAY_LOCATION_ASSET="/usr/local/share/xray"' >> /etc/conf.d/xray
        cat > /etc/init.d/xray <<'EOF_SVC'
#!/sbin/openrc-run
description="Xray Service"
command="/usr/local/bin/xray"
command_args="run -config /usr/local/etc/xray/config.json"
command_background="yes"
pidfile="/run/xray.pid"
depend() { need net; }
EOF_SVC
        chmod +x /etc/init.d/xray
    fi
    service_manager start xray
    setup_geo_cron
    setup_active_defense
    setup_health_monitor

    if [[ "$MODE_IN" == *'ALL'* ]]; then
        deploy_official_hy2 SILENT
    fi
    write_env xray "$MODE_IN"
    view_config deploy
}

deploy_singbox() {
    local MODE_IN=$1 KEYPAIR SB_PATH cert_cn='localhost' SB_PRE_START='' SB_POST_STOP='' SB_RC_PRE='' SB_RC_POST=''
    clear; msg "${BOLD}${GREEN}部署 Sing-box 核心 [$MODE_IN]${NC}"
    init_system_environment
    source "$AIO_ENV" 2>/dev/null || true
    release_ports
    clean_nat_rules
    clean_input_rules
    save_firewall_rules
    pre_install_setup singbox "$MODE_IN"
    get_architecture

    rm -rf /tmp/sing-box-* /tmp/singbox_core.tar.gz /tmp/sing-box /tmp/singbox_ext 2>/dev/null
    fetch_github_release SagerNet/sing-box singbox_core.tar.gz
    mkdir -p /tmp/singbox_ext
    tar -xzf /tmp/singbox_core.tar.gz -C /tmp/singbox_ext || die 'Sing-box 压缩包解压失败。'
    SB_PATH=$(find /tmp/singbox_ext -type f -name 'sing-box' | head -n 1)
    [[ -n "$SB_PATH" && -f "$SB_PATH" ]] || die '解压后未找到 sing-box 主程序。'
    install -m 755 "$SB_PATH" /usr/local/bin/sing-box || die '安装 sing-box 失败。'
    /usr/local/bin/sing-box version >/dev/null 2>&1 || die 'Sing-box 执行校验失败。'

    mkdir -p /etc/sing-box
    chmod 700 /etc/sing-box
    KEYPAIR=$(/usr/local/bin/sing-box generate reality-keypair)
    PK=$(awk '/Private/{print $NF}' <<< "$KEYPAIR")
    PBK=$(awk '/Public/{print $NF}' <<< "$KEYPAIR")
    [[ -n "$PK" && -n "$PBK" ]] || die 'Sing-box REALITY 密钥生成失败。'
    UUID=$(generate_robust_uuid)
    SHORT_ID=$(openssl rand -hex 4 | tr -d '\n\r')
    SS_PASS=$(openssl rand -base64 16 | tr -d '\n\r')
    [[ -n "$SS_PASS" ]] || die 'SS-2022 密钥生成失败。'

    if [[ "$MODE_IN" == *'HY2'* || "$MODE_IN" == *'ALL'* ]]; then
        HY2_PASS=$(rand_alnum 20)
        HY2_OBFS=$(rand_alnum 16)
        [[ -n "${HY2_DOMAIN:-}" ]] && cert_cn="$HY2_DOMAIN"
        openssl ecparam -genkey -name prime256v1 -out /etc/sing-box/hy2.key 2>/dev/null
        openssl req -new -x509 -days 36500 -key /etc/sing-box/hy2.key -out /etc/sing-box/hy2.crt -subj "/CN=$cert_cn" 2>/dev/null
        chmod 600 /etc/sing-box/hy2.key
        HY2_CERT_SHA256_FP=$(pin_sha256_colon /etc/sing-box/hy2.crt | tr -d ':')
        HY2_CERT_PUBKEY_SHA256_B64=$(openssl x509 -in /etc/sing-box/hy2.crt -noout -pubkey | openssl pkey -pubin -outform der | openssl dgst -sha256 -binary | base64 | tr -d '\n')
    fi

    build_singbox_config "$MODE_IN"
    chmod 600 /etc/sing-box/config.json
    jq empty /etc/sing-box/config.json >/dev/null 2>&1 || die 'Sing-box JSON 格式非法。'
    /usr/local/bin/sing-box check -c /etc/sing-box/config.json >/dev/null 2>&1 || die 'Sing-box 配置校验失败。'

    if [[ "$MODE_IN" == *'HY2'* || "$MODE_IN" == *'ALL'* ]] && [[ "${HY2_HOP:-}" == 'true' ]]; then
        SB_PRE_START="ExecStartPre=-/bin/sh -c '$IPT -w -t nat -D PREROUTING -i $INGRESS_IF -p udp --dport ${HY2_RANGE_START}:${HY2_RANGE_END} -m comment --comment \"Aio-box-HY2-HOP\" -j REDIRECT --to-ports $HY2_BASE_PORT 2>/dev/null || true'
ExecStartPre=-/bin/sh -c '$IPT -w -t nat -A PREROUTING -i $INGRESS_IF -p udp --dport ${HY2_RANGE_START}:${HY2_RANGE_END} -m comment --comment \"Aio-box-HY2-HOP\" -j REDIRECT --to-ports $HY2_BASE_PORT 2>/dev/null || true'"
        SB_POST_STOP="ExecStopPost=-/bin/sh -c '$IPT -w -t nat -D PREROUTING -i $INGRESS_IF -p udp --dport ${HY2_RANGE_START}:${HY2_RANGE_END} -m comment --comment \"Aio-box-HY2-HOP\" -j REDIRECT --to-ports $HY2_BASE_PORT 2>/dev/null || true'"
        SB_RC_PRE="start_pre() {
  $IPT -w -t nat -D PREROUTING -i $INGRESS_IF -p udp --dport ${HY2_RANGE_START}:${HY2_RANGE_END} -m comment --comment \"Aio-box-HY2-HOP\" -j REDIRECT --to-ports $HY2_BASE_PORT 2>/dev/null || true
  $IPT -w -t nat -A PREROUTING -i $INGRESS_IF -p udp --dport ${HY2_RANGE_START}:${HY2_RANGE_END} -m comment --comment \"Aio-box-HY2-HOP\" -j REDIRECT --to-ports $HY2_BASE_PORT 2>/dev/null || true"
        SB_RC_POST="stop_post() {
  $IPT -w -t nat -D PREROUTING -i $INGRESS_IF -p udp --dport ${HY2_RANGE_START}:${HY2_RANGE_END} -m comment --comment \"Aio-box-HY2-HOP\" -j REDIRECT --to-ports $HY2_BASE_PORT 2>/dev/null || true"
        if has_ipv6 && ipv6_nat_redirect_usable; then
            SB_PRE_START+="
ExecStartPre=-/bin/sh -c '$IPT6 -w -t nat -D PREROUTING -i $INGRESS_IF -p udp --dport ${HY2_RANGE_START}:${HY2_RANGE_END} -m comment --comment \"Aio-box-HY2-HOP\" -j REDIRECT --to-ports $HY2_BASE_PORT 2>/dev/null || true'
ExecStartPre=-/bin/sh -c '$IPT6 -w -t nat -A PREROUTING -i $INGRESS_IF -p udp --dport ${HY2_RANGE_START}:${HY2_RANGE_END} -m comment --comment \"Aio-box-HY2-HOP\" -j REDIRECT --to-ports $HY2_BASE_PORT 2>/dev/null || true'"
            SB_POST_STOP+="
ExecStopPost=-/bin/sh -c '$IPT6 -w -t nat -D PREROUTING -i $INGRESS_IF -p udp --dport ${HY2_RANGE_START}:${HY2_RANGE_END} -m comment --comment \"Aio-box-HY2-HOP\" -j REDIRECT --to-ports $HY2_BASE_PORT 2>/dev/null || true'"
            SB_RC_PRE+="
  $IPT6 -w -t nat -D PREROUTING -i $INGRESS_IF -p udp --dport ${HY2_RANGE_START}:${HY2_RANGE_END} -m comment --comment \"Aio-box-HY2-HOP\" -j REDIRECT --to-ports $HY2_BASE_PORT 2>/dev/null || true
  $IPT6 -w -t nat -A PREROUTING -i $INGRESS_IF -p udp --dport ${HY2_RANGE_START}:${HY2_RANGE_END} -m comment --comment \"Aio-box-HY2-HOP\" -j REDIRECT --to-ports $HY2_BASE_PORT 2>/dev/null || true"
            SB_RC_POST+="
  $IPT6 -w -t nat -D PREROUTING -i $INGRESS_IF -p udp --dport ${HY2_RANGE_START}:${HY2_RANGE_END} -m comment --comment \"Aio-box-HY2-HOP\" -j REDIRECT --to-ports $HY2_BASE_PORT 2>/dev/null || true"
        fi
        SB_RC_PRE+="
  return 0
}"
        SB_RC_POST+="
  return 0
}"
    fi

    if [[ "$INIT_SYS" == 'systemd' ]]; then
        cat > /etc/systemd/system/sing-box.service <<EOF_SVC
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
EOF_SVC
    else
        mkdir -p /etc/conf.d
        echo 'rc_ulimit="-n 1048576"' > /etc/conf.d/sing-box
        cat > /etc/init.d/sing-box <<EOF_SVC
#!/sbin/openrc-run
description="Sing-Box Service"
command="/usr/local/bin/sing-box"
command_args="run -c /etc/sing-box/config.json"
command_background="yes"
pidfile="/run/sing-box.pid"
depend() { need net; }
$SB_RC_PRE
$SB_RC_POST
EOF_SVC
        chmod +x /etc/init.d/sing-box
    fi
    service_manager start sing-box
    setup_geo_cron
    setup_active_defense
    setup_health_monitor
    write_env singbox "$MODE_IN"
    view_config deploy
}

get_month_total_bytes() {
    local iface="$1" mode="${2:-total}" line
    line=$(vnstat -i "$iface" --oneline b 2>/dev/null) || return 1
    case "$mode" in
        rx) echo "$line" | awk -F';' '{print $9}' ;;
        tx) echo "$line" | awk -F';' '{print $10}' ;;
        total) echo "$line" | awk -F';' '{print $11}' ;;
        *) return 1 ;;
    esac
}

bytes_to_gb() { awk -v b="$1" 'BEGIN { printf "%.2f", b / 1024 / 1024 / 1024 }'; }

setup_traffic_monitor() {
    mkdir -p "$AIO_DIR"
    cat > "$AIO_DIR/traffic_monitor.sh" <<'EOF_TRAFFIC'
#!/usr/bin/env bash
PATH=/usr/local/sbin:/usr/local/bin:/sbin:/bin:/usr/sbin:/usr/bin
source /etc/ddr/.env 2>/dev/null || exit 0
[[ -z "${TRAFFIC_LIMIT_GB:-}" ]] && exit 0
INTERFACE=$(ip route get 8.8.8.8 2>/dev/null | awk '{for(i=1;i<=NF;i++) if($i=="dev"){print $(i+1); exit}}')
[[ -z "$INTERFACE" ]] && INTERFACE=$(ip -o route show to default 2>/dev/null | awk '{print $5; exit}')
[[ -z "$INTERFACE" ]] && INTERFACE=$(ip link | awk -F: '$0 !~ "lo|vir|wl|^[^0-9]"{print $2;getline}' | head -n 1 | tr -d ' ')
get_month_total_bytes() {
    local iface="$1" mode="${2:-total}" line
    line=$(vnstat -i "$iface" --oneline b 2>/dev/null) || return 1
    case "$mode" in
        rx) echo "$line" | awk -F';' '{print $9}' ;;
        tx) echo "$line" | awk -F';' '{print $10}' ;;
        total) echo "$line" | awk -F';' '{print $11}' ;;
        *) return 1 ;;
    esac
}
bytes_to_gb() { awk -v b="$1" 'BEGIN { printf "%.2f", b / 1024 / 1024 / 1024 }'; }
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
    killall -TERM hysteria xray sing-box 2>/dev/null || true
    sleep 2
    killall -9 hysteria xray sing-box 2>/dev/null || true
fi
EOF_TRAFFIC
    chmod +x "$AIO_DIR/traffic_monitor.sh"
    local tmp_cron
    tmp_cron=$(mktemp)
    crontab -l 2>/dev/null | grep -vE '^no crontab for|^#' | grep -v '/etc/ddr/traffic_monitor.sh' > "$tmp_cron" || true
    echo '* * * * * /bin/bash /etc/ddr/traffic_monitor.sh >/dev/null 2>&1' >> "$tmp_cron"
    crontab "$tmp_cron" 2>/dev/null || true
    rm -f "$tmp_cron"
}

disable_traffic_monitor() {
    local tmp_cron
    tmp_cron=$(mktemp)
    crontab -l 2>/dev/null | grep -vE '^no crontab for|^#' | grep -v '/etc/ddr/traffic_monitor.sh' > "$tmp_cron" || true
    crontab "$tmp_cron" 2>/dev/null || true
    rm -f "$tmp_cron" "$AIO_DIR/traffic_monitor.sh"
}

traffic_management_menu() {
    clear
    local INTERFACE USED_BYTES USED_GB limit_gb mode_choice
    INTERFACE=$(get_active_interface)
    msg "${CYAN}======================================================================${NC}"
    msg "${BOLD}${GREEN}每月流量管控限制 / Monthly Traffic Management Limit${NC}"
    msg "${CYAN}======================================================================${NC}"
    msg "${YELLOW}[网卡 ${INTERFACE} 当前月流量统计]${NC}"
    if command -v vnstat >/dev/null 2>&1; then
        vnstat -i "$INTERFACE" -m 2>/dev/null | head -n 8 | grep -v '^$' || msg "${YELLOW}暂无本月统计数据，vnstat 正在收集中。${NC}"
    fi
    source "$AIO_ENV" 2>/dev/null || true
    if [[ -n "${TRAFFIC_LIMIT_GB:-}" ]]; then
        msg "当前设定: ${GREEN}${TRAFFIC_LIMIT_GB} GB${NC} | 模式: ${TRAFFIC_LIMIT_MODE:-total}"
    else
        msg "当前设定: ${RED}未开启${NC}"
    fi
    msg "${CYAN}======================================================================${NC}"
    msg "${YELLOW}1. 设定/修改每月流量上限${NC}"
    msg "${YELLOW}2. 解除流量限制${NC}"
    msg "${GREEN}0. 返回主菜单${NC}"
    read -r -ep '请选择 [0-2]: ' tr_choice
    case "$tr_choice" in
        1)
            read -r -ep '请输入每月流量上限(GB)，纯数字: ' limit_gb
            valid_positive_int "$limit_gb" || { msg "${RED}[!] 输入无效。${NC}"; pause_return; return; }
            read -r -ep '计量模式 total/rx/tx (回车默认 total): ' mode_choice
            mode_choice=${mode_choice:-total}
            [[ "$mode_choice" =~ ^(total|rx|tx)$ ]] || { msg "${RED}[!] 计量模式无效。${NC}"; pause_return; return; }
            touch "$AIO_ENV"
            sed -i '/^TRAFFIC_LIMIT_GB=/d;/^TRAFFIC_LIMIT_MODE=/d' "$AIO_ENV" 2>/dev/null || true
            printf 'TRAFFIC_LIMIT_GB=%q\nTRAFFIC_LIMIT_MODE=%q\n' "$limit_gb" "$mode_choice" >> "$AIO_ENV"
            chmod 600 "$AIO_ENV"
            setup_traffic_monitor
            msg "${GREEN}流量限制已设定为 ${limit_gb} GB，模式 ${mode_choice}。${NC}"
            pause_return
            ;;
        2)
            [[ -f "$AIO_ENV" ]] && sed -i '/^TRAFFIC_LIMIT_GB=/d;/^TRAFFIC_LIMIT_MODE=/d' "$AIO_ENV" 2>/dev/null || true
            disable_traffic_monitor
            source "$AIO_ENV" 2>/dev/null || true
            case "${CORE:-}" in
                xray) service_manager start xray ;;
                singbox) service_manager start sing-box ;;
                hysteria) service_manager start hysteria ;;
            esac
            [[ "${CORE:-}" == 'xray' && "${MODE:-}" == *'ALL'* ]] && service_manager start hysteria
            msg "${GREEN}流量限制已解除。${NC}"
            pause_return
            ;;
        *) return 0 ;;
    esac
}

manage_ss_whitelist() {
    clear
    source "$AIO_ENV" 2>/dev/null || true
    [[ -z "${SS_PORT:-}" ]] && { msg "${RED}[!] 未检测到已部署的 SS-2022 服务端口。${NC}"; pause_return; return; }
    msg "${CYAN}======================================================================${NC}"
    msg "${BOLD}${GREEN}SS-2022 白名单 IP 管理${NC}"
    msg "${CYAN}======================================================================${NC}"
    msg "${YELLOW}当前 SS-2022 监听端口: $SS_PORT${NC}"
    msg "IPv4 白名单:"
    $IPT -nL INPUT --line-numbers 2>/dev/null | grep "tcp dpt:$SS_PORT" | grep 'ACCEPT' | awk '{print $5}' | grep -v '0.0.0.0/0' || true
    if command -v ip6tables >/dev/null 2>&1 && $IPT6 -nL INPUT >/dev/null 2>&1; then
        msg "IPv6 白名单:"
        $IPT6 -nL INPUT --line-numbers 2>/dev/null | grep "tcp dpt:$SS_PORT" | grep 'ACCEPT' | awk '{print $5}' | grep -v '::/0' || true
    fi
    msg "${BLUE}----------------------------------------------------------------------${NC}"
    msg "${YELLOW}1. 新增白名单 IP${NC}"
    msg "${YELLOW}2. 移除白名单 IP${NC}"
    msg "${YELLOW}3. 开启白名单模式 (插入 DROP)${NC}"
    msg "${YELLOW}4. 切换为全网开放 (移除 DROP)${NC}"
    msg "${GREEN}0. 返回主菜单${NC}"
    read -r -ep '请选择操作 [0-4]: ' wl_choice
    local add_ip del_ip rule found
    case "$wl_choice" in
        1)
            read -r -ep '请输入要放行的前置机 IP/CIDR: ' add_ip
            [[ -z "$add_ip" ]] && return
            if [[ "$add_ip" == *:* ]]; then
                valid_ipv6_cidr "$add_ip" || { msg "${RED}[!] IPv6 白名单地址非法: $add_ip${NC}"; pause_return; return; }
                has_ipv6 && command -v ip6tables >/dev/null 2>&1 && $IPT6 -w -I INPUT -p tcp --dport "$SS_PORT" -s "$add_ip" -m comment --comment "Aio-box-${SS_PORT}-tcp-WL6" -j ACCEPT >/dev/null 2>&1 || die "IPv6 白名单规则写入失败: $add_ip"
            else
                valid_ipv4_cidr "$add_ip" || { msg "${RED}[!] IPv4 白名单地址非法: $add_ip${NC}"; pause_return; return; }
                $IPT -w -I INPUT -p tcp --dport "$SS_PORT" -s "$add_ip" -m comment --comment "Aio-box-${SS_PORT}-tcp-WL" -j ACCEPT >/dev/null 2>&1 || die "IPv4 白名单规则写入失败: $add_ip"
            fi
            save_firewall_rules
            msg "${GREEN}已添加白名单: $add_ip${NC}"
            pause_return
            ;;
        2)
            read -r -ep '请输入要移除的 IP/CIDR: ' del_ip
            [[ -z "$del_ip" ]] && return
            if [[ "$del_ip" == *:* ]]; then
                valid_ipv6_cidr "$del_ip" || { msg "${RED}[!] IPv6 白名单地址非法: $del_ip${NC}"; pause_return; return; }
                found=0
                while $IPT6 -w -S INPUT 2>/dev/null | grep -F "Aio-box-${SS_PORT}-tcp-WL6" | grep -Fq -- "$del_ip"; do
                    rule=$($IPT6 -w -S INPUT 2>/dev/null | grep -F "Aio-box-${SS_PORT}-tcp-WL6" | grep -F -- "$del_ip" | head -n 1 | sed 's/^-A /-D /')
                    [[ -z "$rule" ]] && break
                    # shellcheck disable=SC2086
                    $IPT6 -w $rule >/dev/null 2>&1 || die "IPv6 白名单规则删除失败: $del_ip"
                    found=1
                done
            else
                valid_ipv4_cidr "$del_ip" || { msg "${RED}[!] IPv4 白名单地址非法: $del_ip${NC}"; pause_return; return; }
                found=0
                while $IPT -w -S INPUT 2>/dev/null | grep -F "Aio-box-${SS_PORT}-tcp-WL" | grep -Fq -- "$del_ip"; do
                    rule=$($IPT -w -S INPUT 2>/dev/null | grep -F "Aio-box-${SS_PORT}-tcp-WL" | grep -F -- "$del_ip" | head -n 1 | sed 's/^-A /-D /')
                    [[ -z "$rule" ]] && break
                    # shellcheck disable=SC2086
                    $IPT -w $rule >/dev/null 2>&1 || die "IPv4 白名单规则删除失败: $del_ip"
                    found=1
                done
            fi
            save_firewall_rules
            [[ "$found" == 1 ]] && msg "${GREEN}已移除白名单: $del_ip${NC}" || msg "${YELLOW}未找到该白名单规则。${NC}"
            pause_return
            ;;
        3)
            if ! $IPT -w -C INPUT -p tcp --dport "$SS_PORT" -j DROP 2>/dev/null; then
                $IPT -w -A INPUT -p tcp --dport "$SS_PORT" -m comment --comment "Aio-box-${SS_PORT}-tcp-DROP" -j DROP >/dev/null 2>&1 || die 'IPv4 SS DROP 规则写入失败。'
            fi
            if has_ipv6 && command -v ip6tables >/dev/null 2>&1 && $IPT6 -w -S INPUT >/dev/null 2>&1; then
                if ! $IPT6 -w -C INPUT -p tcp --dport "$SS_PORT" -j DROP 2>/dev/null; then
                    $IPT6 -w -A INPUT -p tcp --dport "$SS_PORT" -m comment --comment "Aio-box-${SS_PORT}-tcp-DROP6" -j DROP >/dev/null 2>&1 || die 'IPv6 SS DROP 规则写入失败。'
                fi
            fi
            save_firewall_rules
            msg "${GREEN}已开启白名单保护模式。${NC}"
            pause_return
            ;;
        4)
            while $IPT -w -S INPUT 2>/dev/null | grep -q "Aio-box-${SS_PORT}-tcp-DROP"; do
                rule=$($IPT -w -S INPUT 2>/dev/null | grep "Aio-box-${SS_PORT}-tcp-DROP" | head -n 1 | sed 's/^-A /-D /')
                [[ -z "$rule" ]] && break
                # shellcheck disable=SC2086
                $IPT -w $rule >/dev/null 2>&1 || break
            done
            if command -v ip6tables >/dev/null 2>&1 && $IPT6 -w -S INPUT >/dev/null 2>&1; then
                while $IPT6 -w -S INPUT 2>/dev/null | grep -q "Aio-box-${SS_PORT}-tcp-DROP6"; do
                    rule=$($IPT6 -w -S INPUT 2>/dev/null | grep "Aio-box-${SS_PORT}-tcp-DROP6" | head -n 1 | sed 's/^-A /-D /')
                    [[ -z "$rule" ]] && break
                    # shellcheck disable=SC2086
                    $IPT6 -w $rule >/dev/null 2>&1 || break
                done
            fi
            allowPort "$SS_PORT" tcp
            save_firewall_rules
            msg "${GREEN}已切换为全网开放模式。${NC}"
            pause_return
            ;;
        *) return 0 ;;
    esac
}

do_cleanup() {
    clear; msg "${RED}正在执行清理逻辑...${NC}"
    init_system_environment
    stop_all_managed_services
    clean_nat_rules
    clean_input_rules
    save_firewall_rules
    killall -TERM xray sing-box hysteria 2>/dev/null || true
    sleep 1
    killall -9 xray sing-box hysteria 2>/dev/null || true
    rm -rf /usr/local/etc/xray /usr/local/share/xray /etc/sing-box /etc/hysteria /usr/local/bin/xray /usr/local/bin/sing-box /usr/local/bin/hysteria
    rm -f /etc/systemd/system/xray.service /etc/systemd/system/sing-box.service /etc/systemd/system/hysteria.service
    rm -f /etc/init.d/xray /etc/init.d/sing-box /etc/init.d/hysteria
    rm -f /etc/sysctl.d/99-aio-box-tune.conf /etc/security/limits.d/aio-box.conf
    sysctl --system >/dev/null 2>&1 || true
    local tmp_cron
    tmp_cron=$(mktemp)
    crontab -l 2>/dev/null | grep -vE '^no crontab for|^#' | grep -vE '/etc/ddr/traffic_monitor.sh|/etc/ddr/geo_update.sh|/etc/ddr/socket_probe.sh' > "$tmp_cron" || true
    crontab "$tmp_cron" 2>/dev/null || true
    rm -f "$tmp_cron"
    rm -f /var/log/aio-box-*.log /etc/fail2ban/jail.d/aio-box.local /etc/fail2ban/filter.d/aio-box.conf /etc/logrotate.d/aio-box 2>/dev/null || true
    if [[ "$INIT_SYS" == 'systemd' ]]; then
        systemctl restart fail2ban 2>/dev/null || true
        systemctl daemon-reload 2>/dev/null || true
    else
        rc-service fail2ban restart 2>/dev/null || true
    fi
    if [[ "${1:-}" == 'full' ]]; then
        rm -rf "$AIO_DIR" /usr/local/bin/sb
        msg "${GREEN}完全清理完成。${NC}"
        exit 0
    else
        rm -f "$AIO_ENV" "$AIO_DIR"/.deps* "$AIO_DIR/traffic_monitor.sh" "$AIO_DIR/geo_update.sh" "$AIO_DIR/socket_probe.sh"
        setup_shortcut
        msg "${GREEN}代理系统已销毁，保留 sb 入口。${NC}"
        pause_return
    fi
}

check_virgin_state() {
    clear
    init_system_environment
    msg "${YELLOW}删除全部节点与环境初始化 / Delete all nodes and perform environment initialization${NC}"
    read -r -ep '确定执行环境深度自愈吗？(输入 y 确认): ' confirm_virgin
    [[ "$confirm_virgin" =~ ^[Yy]$ ]] || { msg "${GREEN}操作已取消。${NC}"; pause_return; return; }
    stop_all_managed_services
    killall -TERM xray sing-box hysteria 2>/dev/null || true
    sleep 1
    killall -9 xray sing-box hysteria 2>/dev/null || true
    clean_nat_rules
    clean_input_rules
    save_firewall_rules
    local tmp_cron
    tmp_cron=$(mktemp)
    crontab -l 2>/dev/null | grep -vE '^no crontab for|^#' | grep -vE '/etc/ddr/traffic_monitor.sh|/etc/ddr/geo_update.sh|/etc/ddr/socket_probe.sh' > "$tmp_cron" || true
    crontab "$tmp_cron" 2>/dev/null || true
    rm -f "$tmp_cron"
    rm -f "$AIO_ENV" "$AIO_DIR"/.deps* "$AIO_DIR/traffic_monitor.sh" "$AIO_DIR/geo_update.sh" "$AIO_DIR/socket_probe.sh"
    rm -rf /usr/local/etc/xray /usr/local/share/xray /etc/sing-box /etc/hysteria /usr/local/bin/xray /usr/local/bin/sing-box /usr/local/bin/hysteria
    rm -f /etc/systemd/system/xray.service /etc/systemd/system/sing-box.service /etc/systemd/system/hysteria.service /etc/init.d/xray /etc/init.d/sing-box /etc/init.d/hysteria
    rm -f /var/log/aio-box-*.log /etc/fail2ban/jail.d/aio-box.local /etc/fail2ban/filter.d/aio-box.conf /etc/logrotate.d/aio-box 2>/dev/null || true
    [[ "$INIT_SYS" == 'systemd' ]] && systemctl daemon-reload 2>/dev/null || true
    msg "${GREEN}环境初始化完成。${NC}"
    pause_return
}

tune_vps() {
    clear; msg "${CYAN}正在开启底层系统优化 (TCP-BBR & I/O Limit Control)...${NC}"
    cat > /etc/security/limits.d/aio-box.conf <<'EOF_LIMITS'
* soft nofile 1048576
* hard nofile 1048576
* soft nproc 1048576
* hard nproc 1048576
root soft nofile 1048576
root hard nofile 1048576
EOF_LIMITS
    modprobe tcp_bbr 2>/dev/null || true
    cat > /etc/sysctl.d/99-aio-box-tune.conf <<'EOF_SYSCTL'
fs.file-max = 1048576
fs.inotify.max_user_instances = 8192
net.ipv4.ip_forward = 1
net.ipv4.tcp_syncookies = 1
net.ipv4.tcp_fin_timeout = 30
net.ipv4.tcp_keepalive_time = 30
net.ipv4.tcp_max_syn_backlog = 8192
net.ipv4.tcp_max_tw_buckets = 5000
net.ipv4.tcp_fastopen = 3
net.ipv4.tcp_mtu_probing = 1
net.ipv4.tcp_notsent_lowat = 16384
net.core.netdev_max_backlog = 250000
net.core.somaxconn = 32768
net.core.default_qdisc = fq
net.ipv4.tcp_congestion_control = bbr
EOF_SYSCTL
    if command -v sysctl >/dev/null 2>&1; then
        if [[ "${release:-}" == 'alpine' ]]; then
            for conf in /etc/sysctl.d/*.conf /etc/sysctl.conf; do [[ -f "$conf" ]] && sysctl -p "$conf" >/dev/null 2>&1 || true; done
        else
            sysctl --system >/dev/null 2>&1 || true
        fi
    fi
    if [[ -f /usr/local/etc/xray/config.json ]] && command -v jq >/dev/null 2>&1; then
        cp -f /usr/local/etc/xray/config.json /tmp/xray_config.bak
        jq '(.inbounds[] | select(.protocol=="vless") | .streamSettings.sockopt) |= {"tcpKeepAliveIdle":30,"tcpKeepAliveInterval":30}' /usr/local/etc/xray/config.json > /tmp/xray_patch.json && mv -f /tmp/xray_patch.json /usr/local/etc/xray/config.json
        jq empty /usr/local/etc/xray/config.json >/dev/null 2>&1 || { mv -f /tmp/xray_config.bak /usr/local/etc/xray/config.json; die 'Xray tune 后 JSON 非法，已回滚。'; }
        /usr/local/bin/xray run -test -config /usr/local/etc/xray/config.json >/dev/null 2>&1 || { mv -f /tmp/xray_config.bak /usr/local/etc/xray/config.json; die 'Xray tune 后配置校验失败，已回滚。'; }
        service_manager start xray
    fi
    if [[ -f /etc/sing-box/config.json ]] && command -v jq >/dev/null 2>&1; then
        cp -f /etc/sing-box/config.json /tmp/sb_config.bak
        jq '(.inbounds[] | select(.type=="vless" or .type=="shadowsocks")) |= . + {"tcp_keep_alive":"30s","tcp_keep_alive_interval":"30s"}' /etc/sing-box/config.json > /tmp/sb_patch.json && mv -f /tmp/sb_patch.json /etc/sing-box/config.json
        jq empty /etc/sing-box/config.json >/dev/null 2>&1 || { mv -f /tmp/sb_config.bak /etc/sing-box/config.json; die 'Sing-box tune 后 JSON 非法，已回滚。'; }
        /usr/local/bin/sing-box check -c /etc/sing-box/config.json >/dev/null 2>&1 || { mv -f /tmp/sb_config.bak /etc/sing-box/config.json; die 'Sing-box tune 后配置校验失败，已回滚。'; }
        service_manager start sing-box
    fi
    setup_health_monitor
    setup_active_defense
    msg "${GREEN}系统优化完成。${NC}"
    pause_return
}

vps_benchmark_menu() {
    clear
    msg "${CYAN}======================================================================${NC}"
    msg "${BOLD}${GREEN}本机配置与 IP 测速纯净度 / Benchmark & IP Check${NC}"
    msg "${CYAN}======================================================================${NC}"
    msg "${YELLOW}1. 本机配置和测速 (bench.sh)${NC}"
    msg "${YELLOW}2. IP纯净度和测速 (Check.Place)${NC}"
    msg "${GREEN}0. 返回主菜单${NC}"
    read -r -ep '请选择 [0-2]: ' bench_choice
    local confirm_remote
    case "$bench_choice" in
        1)
            read -r -ep '即将远程执行第三方脚本 bench.sh，确认执行？[y/N]: ' confirm_remote
            [[ "$confirm_remote" =~ ^[Yy]$ ]] && wget -qO- https://bench.sh | bash
            pause_return
            ;;
        2)
            read -r -ep '即将远程执行第三方脚本 Check.Place，确认执行？[y/N]: ' confirm_remote
            [[ "$confirm_remote" =~ ^[Yy]$ ]] && bash <(curl -Ls https://Check.Place) -I
            pause_return
            ;;
        *) return 0 ;;
    esac
}

clean_uninstall_menu() {
    clear
    msg "${CYAN}======================================================================${NC}"
    msg "${BOLD}${RED}深度卸载系统 / Deep Unloading System${NC}"
    msg "${CYAN}======================================================================${NC}"
    msg "${YELLOW}1. 完全物理清场 (销毁节点、配置、防火墙映射与 sb 入口)${NC}"
    msg "${YELLOW}2. 保留脚本与清场 (销毁节点配置，保留控制台与 sb 入口)${NC}"
    msg "${GREEN}0. 取消并返回${NC}"
    read -r -ep '请输入执行代码 [0-2]: ' un_choice
    case "$un_choice" in
        1) do_cleanup full ;;
        2) do_cleanup keep ;;
        *) return 0 ;;
    esac
}

generate_qr() {
    local url=$1
    if command -v qrencode >/dev/null 2>&1; then
        msg "\n${CYAN}================ 扫码导入 / Scan QR Code =================${NC}"
        printf '%s' "$url" | qrencode -s 1 -m 2 -t UTF8
        msg "${CYAN}==========================================================${NC}\n"
    fi
}

view_config() {
    local CALLER=${1:-manual}
    clear
    [[ ! -f "$AIO_ENV" ]] && { msg "${RED}未检测到持久化配置变量。${NC}"; sleep 2; return 0; }
    source "$AIO_ENV"
    local F_IP="$LINK_IP" S_IP SS_BASE64 VLESS_URL XHTTP_URL HY2_URL SS_URL
    [[ "$LINK_IP" =~ : ]] && F_IP="[$LINK_IP]"
    [[ -z "$LINK_IP" || "$LINK_IP" == 'N/A' ]] && msg "${YELLOW}[!] 未能自动获取公网 IP，分享链接可能不可用。${NC}"
    msg "${BLUE}======================================================================${NC}"
    msg "${BOLD}${CYAN}全局拓扑网络参数 (${MODE}) / Network Parameters${NC}"
    msg "${BLUE}======================================================================${NC}"
    msg "${BOLD}引擎栈:${NC} $CORE | ${BOLD}模式:${NC} $MODE"
    msg "${BLUE}----------------------------------------------------------------------${NC}"
    msg "${YELLOW}[ 通用分享 URI / General URIs ]${NC}"
    if [[ "$MODE" == *'VISION'* || "$MODE" == *'ALL'* || "$MODE" == 'VLESS_SS' ]]; then
        VLESS_URL="vless://$UUID@$F_IP:$VLESS_PORT?encryption=none&flow=xtls-rprx-vision&security=reality&sni=$VLESS_SNI&fp=chrome&pbk=$PUBLIC_KEY&sid=$SHORT_ID&type=tcp#Aio-VLESS-Vision"
        msg "${GREEN}${VLESS_URL}${NC}"
        generate_qr "$VLESS_URL"
    fi
    if [[ "$MODE" == *'XHTTP'* || "$MODE" == *'ALL'* ]]; then
        XHTTP_URL="vless://$UUID@$F_IP:$XHTTP_PORT?encryption=none&security=reality&sni=$VLESS_SNI&fp=chrome&pbk=$PUBLIC_KEY&sid=$SHORT_ID&type=xhttp&path=%2Fxhttp&mode=auto#Aio-VLESS-XHTTP"
        msg "${GREEN}${XHTTP_URL}${NC}"
        generate_qr "$XHTTP_URL"
    fi
    if [[ "$MODE" == *'HY2'* || "$MODE" == *'ALL'* ]]; then
        if [[ -n "${HY2_DOMAIN:-}" && "$CORE" != 'singbox' ]]; then
            HY2_URL="hysteria2://$HY2_PASS@$HY2_DOMAIN:$HY2_URI_PORTS/?sni=$HY2_DOMAIN&obfs=salamander&obfs-password=$HY2_OBFS#Aio-Hy2-ACME"
        else
            S_IP="$F_IP"
            [[ -n "${HY2_DOMAIN:-}" ]] && S_IP="$HY2_DOMAIN"
            HY2_URL="hysteria2://$HY2_PASS@$S_IP:$HY2_URI_PORTS/?insecure=1&pinSHA256=$HY2_CERT_SHA256_FP&obfs=salamander&obfs-password=$HY2_OBFS#Aio-Hy2-Self"
        fi
        msg "${GREEN}${HY2_URL}${NC}"
        [[ "${HY2_HOP:-}" == 'true' ]] && msg "${YELLOW}端口跳跃默认间隔 30s；不建议低于 5s。${NC}"
        generate_qr "$HY2_URL"
    fi
    if [[ "$MODE" == *'SS'* || "$MODE" == *'ALL'* || "$MODE" == 'VLESS_SS' ]]; then
        SS_BASE64=$(printf '%s' "2022-blake3-aes-128-gcm:${SS_PASS}" | base64 -w 0 2>/dev/null || printf '%s' "2022-blake3-aes-128-gcm:${SS_PASS}" | base64 | tr -d '\n')
        SS_URL="ss://${SS_BASE64}@$F_IP:$SS_PORT#Aio-SS"
        msg "${GREEN}${SS_URL}${NC}"
        generate_qr "$SS_URL"
    fi

    msg "${BLUE}----------------------------------------------------------------------${NC}"
    msg "${YELLOW}[ Clash Meta 示例 ]${NC}"
    if [[ "$MODE" == *'VISION'* || "$MODE" == *'ALL'* || "$MODE" == 'VLESS_SS' ]]; then
        cat <<EOF_CM
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
EOF_CM
    fi
    if [[ "$MODE" == *'XHTTP'* || "$MODE" == *'ALL'* ]]; then
        cat <<EOF_CM
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
EOF_CM
    fi
    if [[ "$MODE" == *'HY2'* || "$MODE" == *'ALL'* ]]; then
        S_IP="$LINK_IP"
        [[ -n "${HY2_DOMAIN:-}" ]] && S_IP="$HY2_DOMAIN"
        if [[ -n "${HY2_DOMAIN:-}" && "$CORE" != 'singbox' ]]; then
            if [[ "${HY2_HOP:-}" == 'true' ]]; then
                cat <<EOF_CM
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
EOF_CM
            else
                cat <<EOF_CM
  - name: "Aio-Hy2-ACME"
    type: hysteria2
    server: $HY2_DOMAIN
    port: $HY2_BASE_PORT
    password: $HY2_PASS
    alpn: [h3]
    sni: $HY2_DOMAIN
    obfs: salamander
    obfs-password: $HY2_OBFS
EOF_CM
            fi
        else
            if [[ "${HY2_HOP:-}" == 'true' ]]; then
                cat <<EOF_CM
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
EOF_CM
            else
                cat <<EOF_CM
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
EOF_CM
            fi
        fi
    fi
    if [[ "$MODE" == *'SS'* || "$MODE" == *'ALL'* || "$MODE" == 'VLESS_SS' ]]; then
        cat <<EOF_CM
  - name: "Aio-SS"
    type: ss
    server: $LINK_IP
    port: $SS_PORT
    cipher: 2022-blake3-aes-128-gcm
    password: $SS_PASS
    udp: true
EOF_CM
    fi

    msg "\n${YELLOW}--- Sing-box 出站示例 ---${NC}"
    if [[ "$MODE" == *'HY2'* || "$MODE" == *'ALL'* ]]; then
        S_IP="$LINK_IP"
        [[ -n "${HY2_DOMAIN:-}" ]] && S_IP="$HY2_DOMAIN"
        if [[ "${HY2_HOP:-}" == 'true' ]]; then
            cat <<EOF_SB
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
EOF_SB
        else
            cat <<EOF_SB
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
EOF_SB
        fi
    fi
    if [[ "$MODE" == *'SS'* || "$MODE" == *'ALL'* || "$MODE" == 'VLESS_SS' ]]; then
        cat <<EOF_SB
    {
      "type": "shadowsocks",
      "server": "$LINK_IP",
      "server_port": $SS_PORT,
      "method": "2022-blake3-aes-128-gcm",
      "password": "$SS_PASS"
    }
EOF_SB
    fi
    if [[ "$MODE" == *'XHTTP'* || "$MODE" == *'ALL'* ]]; then
        msg "\n${YELLOW}--- v2rayN / v2rayNG XHTTP JSON ---${NC}"
        cat <<EOF_V2N
{
  "v": "2",
  "ps": "Aio-VLESS-XHTTP",
  "add": "$LINK_IP",
  "port": "$XHTTP_PORT",
  "id": "$UUID",
  "net": "xhttp",
  "type": "none",
  "path": "/xhttp",
  "tls": "reality",
  "sni": "$VLESS_SNI",
  "fp": "chrome",
  "pbk": "$PUBLIC_KEY",
  "sid": "$SHORT_ID"
}
EOF_V2N
    fi
    msg "${BLUE}----------------------------------------------------------------------${NC}"
    [[ "$CALLER" == 'deploy' ]] && msg "${GREEN}服务池部署完成。${NC}"
    pause_return
}

show_usage() {
    clear
    msg "${CYAN}======================================================================${NC}"
    msg "${BOLD}${GREEN}Aio-box 脚本全功能说明书${NC}"
    msg "${CYAN}======================================================================${NC}"
    cat <<'EOF_USAGE'
1  Xray VLESS-Vision-Reality
2  Xray VLESS-XHTTP-Reality
3  Xray Shadowsocks-2022
4  官方 Hysteria 2
5  Xray + 官方 Hysteria 2 全协议
6  Sing-box VLESS-Vision-Reality
7  Sing-box Shadowsocks-2022
8  Sing-box VLESS + SS-2022
9  Sing-box Hysteria 2
10 Sing-box 全协议
11 本机配置与 IP 测速
12 VPS 一键优化
13 全部节点参数显示
14 脚本说明书
15 脚本 OTA 升级与 Geo 资源更新
16 一键全部清空卸载
17 删除全部节点与环境初始化
18 每月流量管控限制
19 SS-2022 白名单 IP 管理
EOF_USAGE
    msg "${CYAN}======================================================================${NC}"
    pause_return
}

update_script() {
    clear
    local OTA_URL='https://raw.githubusercontent.com/alariclin/aio-box/main/install.sh'
    msg "${YELLOW}[*] 正在同步远端源码...${NC}"
    if curl -fLs --connect-timeout 10 "$OTA_URL" -o /tmp/aio_update.sh; then
        if bash -n /tmp/aio_update.sh && grep -q '==============================Aio-box===============================' /tmp/aio_update.sh; then
            mv /tmp/aio_update.sh "$AIO_DIR/aio.sh"
            chmod +x "$AIO_DIR/aio.sh"
            msg "${GREEN}核心代码热更新完毕。${NC}"
            sleep 2
            exec "$AIO_DIR/aio.sh"
        else
            msg "${RED}[!] 更新脚本语法错误或指纹校验失败。${NC}"
        fi
    else
        msg "${RED}[!] 无法抵达更新服务器。${NC}"
    fi
    pause_return
}

force_update_geo() {
    clear
    [[ -x "$AIO_DIR/geo_update.sh" ]] || setup_geo_cron
    msg "${YELLOW}[*] 正在拉取 Loyalsoldier Geo 资源并执行校验...${NC}"
    if bash "$AIO_DIR/geo_update.sh"; then
        msg "${GREEN}Geo 资源更新与校验成功。${NC}"
    else
        msg "${RED}[!] Geo 资源下载失败或校验未通过。${NC}"
    fi
    pause_return
}

ota_and_geo_menu() {
    clear
    msg "${CYAN}======================================================================${NC}"
    msg "${BOLD}${GREEN}脚本 OTA 升级与 Geo 资源更新${NC}"
    msg "${CYAN}======================================================================${NC}"
    msg "${YELLOW}1. 升级 Aio-box 核心脚本${NC}"
    msg "${YELLOW}2. 立即拉取并更新 Loyalsoldier Geo 资源${NC}"
    msg "${GREEN}0. 返回主菜单${NC}"
    read -r -ep '请选择 [0-2]: ' ota_choice
    case "$ota_choice" in
        1) update_script ;;
        2) force_update_geo ;;
        *) return 0 ;;
    esac
}


enter_runtime() {
    if [[ $EUID -ne 0 ]]; then
        if [[ -f "$0" && -r "$0" && "$0" != 'bash' && "$0" != '-bash' ]] && command -v sudo >/dev/null 2>&1; then
            exec sudo bash "$0" "$@"
        fi
        die '非 root 管道/标准输入执行无法自动提权；请使用: curl -fsSL <URL> | sudo bash'
    fi
    need_interactive_tty
    mkdir -p /var/run "$AIO_DIR"
    exec 9>"$LOCK_FILE"
    if command -v flock >/dev/null 2>&1; then
        flock -n 9 || die '检测到另一个 Aio-box 实例正在运行。'
    fi
}

show_cli_help() {
    cat <<'EOF_HELP'
Aio-box
Usage:
  bash aio.sh              启动交互菜单
  bash aio.sh --self-test  运行无副作用静态自测
  bash aio.sh --help       显示命令行帮助
EOF_HELP
}

run_self_tests() {
    local tmp failures=0
    tmp=$(mktemp -d /tmp/aio-selftest.XXXXXX) || exit 1
    trap 'rm -rf "$tmp"' RETURN
    assert_ok() { "$@" >/dev/null 2>&1 || { echo "FAIL: $*"; failures=$((failures + 1)); }; }
    assert_bad() { "$@" >/dev/null 2>&1 && { echo "FAIL expected bad: $*"; failures=$((failures + 1)); } || true; }

    assert_ok valid_port 1
    assert_ok valid_port 65535
    assert_bad valid_port 0
    assert_bad valid_port 65536
    assert_bad valid_port 08x
    assert_ok valid_port_range 20000:25000
    assert_ok valid_port_range 20000-25000
    assert_bad valid_port_range 25000:20000
    assert_ok valid_domain example.com
    assert_bad valid_domain -bad.example.com
    assert_ok valid_url_https https://example.com/path
    assert_ok valid_url_https https://example.com:443/path
    assert_bad valid_url_https http://example.com/
    assert_bad valid_url_https 'https://bad example.com/'
    assert_ok valid_ipv4_cidr 192.0.2.1/24
    assert_bad valid_ipv4_cidr 999.0.2.1/24
    assert_ok valid_ipv6_cidr 2001:db8::1/64
    assert_bad valid_ipv6_cidr 2001:::1/64

    UUID=00000000-0000-4000-8000-000000000000
    VLESS_SNI=www.example.com
    VLESS_PORT=8443
    XHTTP_PORT=9443
    SS_PORT=24043
    HY2_BASE_PORT=443
    HY2_UP=100
    HY2_DOWN=1000
    HY2_PASS=testpass
    HY2_OBFS=testobfs
    HY2_MASQ_URL=https://www.example.com/
    PK=privatekey
    PBK=publickey
    SHORT_ID=abcd1234
    SS_PASS=testsspass
    ENABLE_KEEPALIVE=true

    mkdir -p "$tmp/xray" "$tmp/sing-box"
    XRAY_CONFIG_PATH="$tmp/xray/config.json" build_xray_config ALL
    jq empty "$tmp/xray/config.json" >/dev/null 2>&1 || { echo 'FAIL: build_xray_config JSON'; failures=$((failures + 1)); }
    SINGBOX_CONFIG_PATH="$tmp/sing-box/config.json" build_singbox_config ALL
    jq empty "$tmp/sing-box/config.json" >/dev/null 2>&1 || { echo 'FAIL: build_singbox_config JSON'; failures=$((failures + 1)); }

    if (( failures > 0 )); then
        echo "SELF_TEST_FAILED=$failures"
        return 1
    fi
    echo 'SELF_TEST_OK'
}

main() {
    case "${1:-}" in
        --help|-h) show_cli_help; exit 0 ;;
        --self-test) run_self_tests; exit $? ;;
        '') enter_runtime "$@"; main_loop "$@" ;;
        *) enter_runtime "$@"; main_loop "$@" ;;
    esac
}

main_loop() {
    init_system_environment
    setup_shortcut
    GLOBAL_PUBLIC_IP=$(get_public_ip)
    while true; do
        local STATUS_STR='' CUR_MODE='' choice
        is_service_running xray && STATUS_STR+="${GREEN}Xray-Core${NC} "
        is_service_running sing-box && STATUS_STR+="${CYAN}Sing-Box${NC} "
        is_service_running hysteria && STATUS_STR+="${GREEN}Hy2(Native)${NC} "
        [[ -z "$STATUS_STR" ]] && STATUS_STR="${RED}Stack Stopped${NC}"
        source "$AIO_ENV" 2>/dev/null && CUR_MODE="[${CORE}-${MODE}]" || CUR_MODE=''
        clear
        msg "${BLUE}======================================================================${NC}"
        msg "${BOLD}${YELLOW}==============================Aio-box===============================${NC}"
        msg "${BLUE}======================================================================${NC}"
        msg "网关/Gateway: ${YELLOW}$GLOBAL_PUBLIC_IP${NC} | 核心/Core: $STATUS_STR $CUR_MODE"
        msg "${BLUE}----------------------------------------------------------------------${NC}"
        msg "${YELLOW}[ Xray-core 部署 ]${NC}                    ${YELLOW}[ Sing-box 部署 ]${NC}"
        msg "${GREEN}1.${NC} VLESS-Vision-Reality               ${GREEN}6.${NC} VLESS-Vision-Reality"
        msg "${GREEN}2.${NC} VLESS-XHTTP-Reality                ${GREEN}7.${NC} Shadowsocks-2022"
        msg "${GREEN}3.${NC} Shadowsocks-2022                   ${GREEN}8.${NC} VLESS + SS-2022"
        msg "${GREEN}4.${NC} Hysteria 2 (官方/Apernet)          ${GREEN}9.${NC} Hysteria 2 (Sing-box)"
        msg "${GREEN}5.${NC} 全协议四合一 (Xray+Hy2)            ${GREEN}10.${NC} 全协议三合一 (Sing-box)"
        msg "${BLUE}----------------------------------------------------------------------${NC}"
        msg "${GREEN}11.${NC} 本机配置与 IP 测速纯净度"
        msg "${GREEN}12.${NC} VPS 一键优化"
        msg "${GREEN}13.${NC} 全部节点参数显示"
        msg "${GREEN}14.${NC} 脚本说明书"
        msg "${GREEN}15.${NC} 脚本 OTA 升级与 Geo 资源更新"
        msg "${GREEN}16.${NC} 一键全部清空卸载"
        msg "${GREEN}17.${NC} 删除全部节点与环境初始化"
        msg "${GREEN}18.${NC} 每月流量管控限制"
        msg "${GREEN}19.${NC} SS-2022 白名单 IP 管理"
        msg "${GREEN}0.${NC} 退出脚本"
        msg "${BLUE}======================================================================${NC}"
        read -r -ep '请求下发执行代号 / Request input command: ' choice
        case "$choice" in
            1) deploy_xray VISION ;;
            2) deploy_xray XHTTP ;;
            3) deploy_xray SS ;;
            4) deploy_official_hy2 NORMAL ;;
            5) deploy_xray ALL ;;
            6) deploy_singbox VISION ;;
            7) deploy_singbox SS ;;
            8) deploy_singbox VLESS_SS ;;
            9) deploy_singbox HY2 ;;
            10) deploy_singbox ALL ;;
            11) vps_benchmark_menu ;;
            12) tune_vps ;;
            13) view_config manual ;;
            14) show_usage ;;
            15) ota_and_geo_menu ;;
            16) clean_uninstall_menu ;;
            17) check_virgin_state ;;
            18) traffic_management_menu ;;
            19) manage_ss_whitelist ;;
            0) clear; rm -f "$LOCK_FILE"; exit 0 ;;
            *) sleep 1 ;;
        esac
    done
}

main "$@"
