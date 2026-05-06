#!/usr/bin/env bash
# ==============================A-Box===============================
# SNI profile: built-in deduplicated maximum REALITY target candidate library; no legacy remote SNI script dependency.
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
SCRIPT_URL='https://raw.githubusercontent.com/alariclin/a-box/main/install.sh'
ABOX_DIR='/etc/ddr'
ABOX_ENV='/etc/ddr/.env'
LOCK_FILE='/var/run/A-Box.lock'
LANG_FILE='/etc/ddr/.lang'
PUBLIC_IP_CACHE='/etc/ddr/.public_ip.cache'
PUBLIC_IP_CACHE_TTL=600
ABOX_LANG='zh'

msg() { echo -e "$*"; }
die() { echo -e "${RED}[!] $*${NC}" >&2; exit 1; }

normalize_lang() {
    case "${1:-}" in
        en|en_US|en-US|english|English) printf 'en' ;;
        zh|zh_CN|zh-CN|cn|CN|中文|'') printf 'zh' ;;
        *) printf 'zh' ;;
    esac
}

tr_msg() {
    local key="$1"
    case "${ABOX_LANG:-zh}:$key" in
        zh:press_return) echo '按回车返回...' ;;
        en:press_return) echo 'Press Enter to return...' ;;
        zh:select_prompt) echo '请选择 / Select' ;;
        en:select_prompt) echo 'Select' ;;
        zh:main_command) echo '请求下发执行代号: ' ;;
        en:main_command) echo 'Input command: ' ;;
        zh:lang_title) echo '语言设置 / Language' ;;
        en:lang_title) echo 'Language Settings / 语言设置' ;;
        zh:lang_saved) echo '语言已保存。' ;;
        en:lang_saved) echo 'Language saved.' ;;
        zh:yes_no_default_no) echo '[Y/N]' ;;
        en:yes_no_default_no) echo '[Y/N]' ;;
        zh:yes_no_default_yes) echo '[Y/N]' ;;
        en:yes_no_default_yes) echo '[Y/N]' ;;
        zh:reality_sni_prompt) echo '   %s 请输入伪装 SNI (端口 %s，回车默认: %s): ' ;;
        en:reality_sni_prompt) echo '   %s Enter camouflage SNI (port %s, default: %s): ' ;;
        zh:bad_sni) echo 'SNI 格式非法: %s' ;;
        en:bad_sni) echo 'Invalid SNI format: %s' ;;
        zh:apple_non443_warn) echo '检测到非 443 端口使用 Apple/iCloud 类 SNI：%s。Xray-core 对 apple/icloud target 与非443端口有风险警告，此组合可能提高 IP 封禁概率。' ;;
        en:apple_non443_warn) echo 'Apple/iCloud-like SNI on non-443 port detected: %s. Xray-core warns about apple/icloud targets and non-443 listening ports; this combination may increase IP blocking risk.' ;;
        zh:continue_or_reset) echo '继续使用此 SNI？输入 y 继续，其他任意键重新输入 %s: ' ;;
        en:continue_or_reset) echo 'Continue with this SNI? Type y to continue, anything else to re-enter %s: ' ;;
        zh:port_prompt) echo '   %s 请输入监听端口 (回车默认: %s): ' ;;
        en:port_prompt) echo '   %s Enter listen port (default: %s): ' ;;
        zh:ss_port_prompt) echo '   %s 请输入回程监听端口(TCP/UDP) (回车默认: %s): ' ;;
        en:ss_port_prompt) echo '   %s Enter relay listen port (TCP/UDP, default: %s): ' ;;
        zh:bad_port) echo '端口非法: %s' ;;
        en:bad_port) echo 'Invalid port: %s' ;;
        zh:toolbox_title) echo '综合工具箱 / Toolbox' ;;
        en:toolbox_title) echo 'Toolbox / 综合工具箱' ;;
        zh:confirm_remote) echo '即将远程执行第三方脚本：%s。确认执行？[Y/N]: ' ;;
        en:confirm_remote) echo 'About to run third-party remote script: %s. Continue? [Y/N]: ' ;;
        zh:confirm_local_sni_full) echo '即将运行本地内置全量 SNI 优选库（不执行远程脚本）。确认执行？[Y/N]: ' ;;
        en:confirm_local_sni_full) echo 'About to run the local built-in full SNI preference library (no remote script execution). Continue? [Y/N]: ' ;;
        zh:confirm_local_sni_mini) echo '即将运行本地内置微型主机 SNI 优选库（候选库与全量相同，不执行远程脚本）。确认执行？[Y/N]: ' ;;
        en:confirm_local_sni_mini) echo 'About to run the local built-in mini-host SNI preference library (same candidate library as full, no remote script execution). Continue? [Y/N]: ' ;;
        zh:swap_exists) echo '检测到 /swapfile 已存在，跳过创建。' ;;
        en:swap_exists) echo '/swapfile already exists; creation skipped.' ;;
        zh:swap_done) echo 'Swap 处理完成。' ;;
        en:swap_done) echo 'Swap operation completed.' ;;
        *) echo "$key" ;;
    esac
}

tprintf() { local key="$1"; shift; printf "$(tr_msg "$key")" "$@"; }

proto_label() {
    printf '%b[%s]%b' "${BOLD}${CYAN}" "$1" "${NC}"
}

pause_return() { read -r -ep "$(tr_msg press_return)" _ || true; }

is_yes() { [[ "${1:-}" =~ ^[Yy]$ ]]; }

confirm_yes_no() {
    local prompt="$1" answer
    read -r -ep "$prompt" answer
    is_yes "$answer"
}

detect_lang() {
    if [[ -n "${ABOX_LANG_OVERRIDE:-}" ]]; then
        ABOX_LANG=$(normalize_lang "$ABOX_LANG_OVERRIDE")
    elif [[ -n "${ABOX_LANG:-}" && "${ABOX_LANG:-}" != 'zh' ]]; then
        ABOX_LANG=$(normalize_lang "$ABOX_LANG")
    elif [[ -r "$LANG_FILE" ]]; then
        ABOX_LANG=$(normalize_lang "$(tr -d '[:space:]' < "$LANG_FILE" 2>/dev/null)")
    else
        ABOX_LANG='zh'
    fi
}

save_lang() {
    mkdir -p "$ABOX_DIR"
    printf '%s\n' "${ABOX_LANG:-zh}" > "$LANG_FILE"
    chmod 600 "$LANG_FILE" 2>/dev/null || true
}

initial_language_select() {
    [[ -f "$LANG_FILE" || -n "${ABOX_LANG_OVERRIDE:-}" ]] && return 0
    local c
    echo 'Language / 语言'
    echo '1. 中文'
    echo '2. English'
    read -r -ep 'Select [1-2, default 1]: ' c || true
    case "$c" in 2) ABOX_LANG='en' ;; *) ABOX_LANG='zh' ;; esac
    save_lang
}

language_menu() {
    clear
    msg "${CYAN}======================================================================${NC}"
    msg "${BOLD}${GREEN}$(tr_msg lang_title)${NC}"
    msg "${CYAN}======================================================================${NC}"
    msg "${YELLOW}1. 中文${NC}"
    msg "${YELLOW}2. English${NC}"
    msg "${GREEN}0. 返回 / Back${NC}"
    local c
    read -r -ep 'Select [0-2]: ' c
    case "$c" in
        1) ABOX_LANG='zh'; save_lang; msg "${GREEN}$(tr_msg lang_saved)${NC}"; pause_return ;;
        2) ABOX_LANG='en'; save_lang; msg "${GREEN}$(tr_msg lang_saved)${NC}"; pause_return ;;
        *) return 0 ;;
    esac
}

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

is_apple_like_sni() {
    local sni="${1,,}"
    [[ "$sni" == 'apple.com' || "$sni" == *.apple.com || "$sni" == 'icloud.com' || "$sni" == *.icloud.com ]]
}

default_sni_for_port() {
    local port="${1:-443}"
    # Avoid Apple/iCloud as a default target. Xray-core emits warnings for apple/icloud
    # targets and for non-443 listeners; use toolbox SNI radar results for production.
    printf 'www.microsoft.com'
}

prompt_reality_sni() {
    local label="$1" port="$2" default_sni input answer prompt
    default_sni=$(default_sni_for_port "$port")
    while true; do
        printf -v prompt "$(tr_msg reality_sni_prompt)" "$label" "$port" "$default_sni"
        read -r -ep "$prompt" input
        input=${input:-$default_sni}
        if ! valid_sni "$input"; then
            echo -e "${RED}[!] $(printf "$(tr_msg bad_sni)" "$input")${NC}" >&2
            continue
        fi
        if [[ "$port" != '443' ]] && is_apple_like_sni "$input"; then
            echo -e "${YELLOW}[!] $(printf "$(tr_msg apple_non443_warn)" "$input")${NC}" >&2
            printf -v prompt "$(tr_msg continue_or_reset)" "$label"
            read -r -ep "$prompt" answer
            is_yes "$answer" && { printf '%s\n' "$input"; return 0; }
            continue
        fi
        printf '%s\n' "$input"
        return 0
    done
}

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

normalize_https_url_input() {
    local input="${1:-}" rest
    input="$(printf '%s' "$input" | tr -d '\r' | sed -E 's/^[[:space:]]+//; s/[[:space:]]+$//')"
    [[ -n "$input" ]] || return 1
    if [[ "$input" != http://* && "$input" != https://* ]]; then
        input="https://${input}"
    fi
    if [[ "$input" == https://* ]]; then
        rest="${input#https://}"
        [[ "$rest" != */* ]] && input="${input}/"
    fi
    printf '%s\n' "$input"
}

prompt_https_url() {
    local prompt="$1" default_url="$2" input normalized
    while true; do
        read -r -ep "$prompt" input
        input="${input:-$default_url}"
        normalized="$(normalize_https_url_input "$input" 2>/dev/null || true)"
        if [[ -n "$normalized" ]] && valid_url_https "$normalized"; then
            printf '%s\n' "$normalized"
            return 0
        fi
        echo -e "${RED}[!] HY2 伪装 URL 非法 / Invalid HY2 masquerade URL: ${input}${NC}" >&2
        echo -e "${YELLOW}    正确示例 / Example: https://www.microsoft.com/${NC}" >&2
    done
}

prompt_port_input() {
    local label="$1" default_port="$2" input prompt
    while true; do
        printf -v prompt "$(tr_msg port_prompt)" "$label" "$default_port"
        read -r -ep "$prompt" input
        input="${input:-$default_port}"
        if valid_port "$input"; then
            printf '%s\n' "$input"
            return 0
        fi
        echo -e "${RED}[!] $(printf "$(tr_msg bad_port)" "$input")${NC}" >&2
    done
}

prompt_ss_port_input() {
    local label="$1" default_port="$2" input prompt
    while true; do
        printf -v prompt "$(tr_msg ss_port_prompt)" "$label" "$default_port"
        read -r -ep "$prompt" input
        input="${input:-$default_port}"
        if valid_port "$input"; then
            printf '%s\n' "$input"
            return 0
        fi
        echo -e "${RED}[!] $(printf "$(tr_msg bad_port)" "$input")${NC}" >&2
    done
}

prompt_positive_int_input() {
    local prompt="$1" default_value="$2" input
    while true; do
        read -r -ep "$prompt" input
        input="${input:-$default_value}"
        if valid_positive_int "$input"; then
            printf '%s\n' "$input"
            return 0
        fi
        echo -e "${RED}[!] 请输入正整数 / Enter a positive integer: ${input}${NC}" >&2
    done
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

get_public_ip_fresh() {
    local ip api
    for api in 'https://api.ipify.org' 'https://ifconfig.me/ip' 'https://icanhazip.com'; do
        ip=$(curl -fsS4 --connect-timeout 1 -m 2 "$api" 2>/dev/null | tr -d '[:space:]')
        if valid_ipv4_cidr "$ip"; then
            printf '%s\n' "$ip"
            return 0
        fi
    done
    ip=$(curl -fsS6 --connect-timeout 1 -m 2 'https://api64.ipify.org' 2>/dev/null | tr -d '[:space:]')
    if valid_ipv6_cidr "$ip"; then
        printf '%s\n' "$ip"
        return 0
    fi
    printf 'N/A\n'
    return 1
}

cache_public_ip() {
    local ip="$1"
    [[ -n "$ip" && "$ip" != 'N/A' ]] || return 0
    mkdir -p "$ABOX_DIR" 2>/dev/null || true
    printf '%s\n' "$ip" > "$PUBLIC_IP_CACHE" 2>/dev/null || true
    chmod 600 "$PUBLIC_IP_CACHE" 2>/dev/null || true
}

read_cached_public_ip() {
    local ip now mtime age
    [[ -r "$PUBLIC_IP_CACHE" ]] || return 1
    ip=$(head -n 1 "$PUBLIC_IP_CACHE" 2>/dev/null | tr -d '[:space:]')
    if ! valid_ipv4_cidr "$ip" && ! valid_ipv6_cidr "$ip"; then
        return 1
    fi
    now=$(date +%s)
    mtime=$(stat -c %Y "$PUBLIC_IP_CACHE" 2>/dev/null || echo 0)
    age=$(( now - mtime ))
    (( age >= 0 && age <= PUBLIC_IP_CACHE_TTL )) || return 1
    printf '%s\n' "$ip"
}

get_public_ip() {
    local ip
    ip=$(read_cached_public_ip 2>/dev/null || true)
    if [[ -n "$ip" ]]; then
        printf '%s\n' "$ip"
        return 0
    fi
    ip=$(get_public_ip_fresh || true)
    if [[ -n "$ip" && "$ip" != 'N/A' ]]; then
        cache_public_ip "$ip"
        printf '%s\n' "$ip"
        return 0
    fi
    if [[ -r "$PUBLIC_IP_CACHE" ]]; then
        ip=$(head -n 1 "$PUBLIC_IP_CACHE" 2>/dev/null | tr -d '[:space:]')
        if valid_ipv4_cidr "$ip" || valid_ipv6_cidr "$ip"; then
            printf '%s\n' "$ip"
            return 0
        fi
    fi
    printf 'N/A\n'
}

refresh_public_ip() {
    local ip
    ip=$(get_public_ip_fresh || true)
    if [[ -n "$ip" && "$ip" != 'N/A' ]]; then
        cache_public_ip "$ip"
        printf '%s\n' "$ip"
        return 0
    fi
    get_public_ip
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
        read -r -ep '仍然继续？[Y/N]: ' continue_domain
        is_yes "$continue_domain" || die '已取消部署。'
    fi
}

init_system_environment() {
    release=''
    installType=''
    removeType=''
    deps_initialized=0
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
        mkdir -p "$ABOX_DIR" && touch "$DEPS_MARKER"
        deps_initialized=1
    fi

    ensure_commands

    start_unit_if_exists() {
        local unit="$1"
        systemctl list-unit-files "$unit.service" >/dev/null 2>&1 || return 0
        systemctl enable --now "$unit" >/dev/null 2>&1 || true
    }

    if [[ "$deps_initialized" == '1' ]]; then
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


build_status_str() {
    local status_str='' statuses status
    if [[ "${INIT_SYS:-}" == 'systemd' ]] && command -v systemctl >/dev/null 2>&1; then
        mapfile -t statuses < <(systemctl is-active xray sing-box hysteria 2>/dev/null || true)
        [[ "${statuses[0]:-}" == 'active' ]] && status_str+="${GREEN}Xray-Core${NC} "
        [[ "${statuses[1]:-}" == 'active' ]] && status_str+="${CYAN}Sing-Box${NC} "
        [[ "${statuses[2]:-}" == 'active' ]] && status_str+="${GREEN}Hy2(Native)${NC} "
    elif [[ "${INIT_SYS:-}" == 'openrc' ]]; then
        rc-service xray status >/dev/null 2>&1 && status_str+="${GREEN}Xray-Core${NC} "
        rc-service sing-box status >/dev/null 2>&1 && status_str+="${CYAN}Sing-Box${NC} "
        rc-service hysteria status >/dev/null 2>&1 && status_str+="${GREEN}Hy2(Native)${NC} "
    fi
    [[ -z "$status_str" ]] && status_str="${RED}Stack Stopped${NC}"
    printf '%b' "$status_str"
}

managed_services_active() {
    is_service_running xray || is_service_running sing-box || is_service_running hysteria
}

confirm_deployment_replacement() {
    local next_core="$1" next_mode="$2" answer current="none"
    [[ -n "${CORE:-}" || -n "${MODE:-}" ]] && current="${CORE:-unknown}-${MODE:-unknown}"
    if [[ "$current" == 'none' ]] && ! managed_services_active; then
        return 0
    fi
    msg "${YELLOW}[!] A-Box will stop managed services before deploying a new stack.${NC}"
    if [[ "${ABOX_LANG:-zh}" == 'en' ]]; then
        msg "Current config: ${current} | New deployment: ${next_core}-${next_mode}"
        msg "This stops/disables xray, sing-box and hysteria managed by A-Box, clears A-Box firewall rules, and overwrites /etc/ddr/.env. Existing binaries/config directories are not fully removed unless using menu 16."
        read -r -ep 'Continue deployment? [Y/N]: ' answer
    else
        msg "当前配置: ${current} | 新部署: ${next_core}-${next_mode}"
        msg '脚本会先停止/禁用 A-Box 托管的 xray、sing-box、hysteria，清理 A-Box 防火墙规则，并覆盖 /etc/ddr/.env。旧核心二进制和配置目录不会被完全删除；彻底删除请用菜单 16。'
        read -r -ep '继续部署？[Y/N]: ' answer
    fi
    is_yes "$answer" || die '已取消部署 / Deployment canceled.'
}

show_status_report() {
    local init='unknown' xray_state='unknown' sing_state='unknown' hy2_state='unknown' shortcut_state='missing'
    [[ -f "$ABOX_ENV" ]] && source "$ABOX_ENV" 2>/dev/null || true
    if command -v systemctl >/dev/null 2>&1; then
        init='systemd'
        xray_state=$(systemctl is-active xray 2>/dev/null || true)
        sing_state=$(systemctl is-active sing-box 2>/dev/null || true)
        hy2_state=$(systemctl is-active hysteria 2>/dev/null || true)
    elif command -v rc-service >/dev/null 2>&1; then
        init='openrc'
        rc-service xray status >/dev/null 2>&1 && xray_state='active' || xray_state='inactive'
        rc-service sing-box status >/dev/null 2>&1 && sing_state='active' || sing_state='inactive'
        rc-service hysteria status >/dev/null 2>&1 && hy2_state='active' || hy2_state='inactive'
    fi
    [[ -x /usr/local/bin/sb ]] && shortcut_state='executable'
    cat <<EOF_STATUS
A-Box status
Init: ${init}
Config: CORE=${CORE:-} MODE=${MODE:-}
Services: xray=${xray_state} sing-box=${sing_state} hysteria=${hy2_state}
Shortcut: /usr/local/bin/sb=${shortcut_state}
Config file: ${ABOX_ENV}
EOF_STATUS
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
        $IPT -w -I INPUT -p "$type" --dport "$port" -m comment --comment "A-Box-${port}-${type}" -j ACCEPT >/dev/null 2>&1 || die "IPv4 防火墙放行失败: ${port}/${type}"
    fi
    if has_ipv6 && command -v ip6tables >/dev/null 2>&1 && $IPT6 -w -S INPUT >/dev/null 2>&1; then
        if ! $IPT6 -w -C INPUT -p "$type" --dport "$port" -j ACCEPT 2>/dev/null; then
            $IPT6 -w -I INPUT -p "$type" --dport "$port" -m comment --comment "A-Box-${port}-${type}" -j ACCEPT >/dev/null 2>&1 || die "IPv6 防火墙放行失败: ${port}/${type}"
        fi
    fi
}

clean_nat_rules() {
    local rule
    while $IPT -w -t nat -S PREROUTING 2>/dev/null | grep -q 'A-Box-HY2-HOP'; do
        rule=$($IPT -w -t nat -S PREROUTING 2>/dev/null | grep 'A-Box-HY2-HOP' | head -n 1 | sed 's/^-A /-D /')
        [[ -z "$rule" ]] && break
        # shellcheck disable=SC2086
        $IPT -w -t nat $rule 2>/dev/null || break
    done
    if command -v ip6tables >/dev/null 2>&1 && $IPT6 -w -t nat -S PREROUTING >/dev/null 2>&1; then
        while $IPT6 -w -t nat -S PREROUTING 2>/dev/null | grep -q 'A-Box-HY2-HOP'; do
            rule=$($IPT6 -w -t nat -S PREROUTING 2>/dev/null | grep 'A-Box-HY2-HOP' | head -n 1 | sed 's/^-A /-D /')
            [[ -z "$rule" ]] && break
            # shellcheck disable=SC2086
            $IPT6 -w -t nat $rule 2>/dev/null || break
        done
    fi
}

clean_input_rules() {
    local rule
    while $IPT -w -S INPUT 2>/dev/null | grep -q 'A-Box-'; do
        rule=$($IPT -w -S INPUT 2>/dev/null | grep 'A-Box-' | head -n 1 | sed 's/^-A /-D /')
        [[ -z "$rule" ]] && break
        # shellcheck disable=SC2086
        $IPT -w $rule 2>/dev/null || break
    done
    if command -v ip6tables >/dev/null 2>&1 && $IPT6 -w -S INPUT >/dev/null 2>&1; then
        while $IPT6 -w -S INPUT 2>/dev/null | grep -q 'A-Box-'; do
            rule=$($IPT6 -w -S INPUT 2>/dev/null | grep 'A-Box-' | head -n 1 | sed 's/^-A /-D /')
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
    add_port_pair pairs udp "${SS_PORT:-}"
    add_port_pair pairs udp "${HY2_BASE_PORT:-}"
    printf '%s' "$pairs"
}

check_selected_ports_free() {
    msg "${YELLOW}[*] 正在检查新选择端口是否被非 A-Box 进程占用...${NC}"
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
        msg "${RED}[!] 新选择端口 ${p}/${proto} 已被非 A-Box 进程占用：${NC}"
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
            msg "${RED}[!] HY2 UDP 跳跃区间 ${HY2_RANGE_START}-${HY2_RANGE_END} 已被非 A-Box 进程占用：${NC}"
            echo "$holder"
            die '请先手动释放 HY2 UDP 跳跃区间内的占用端口。'
        fi
    fi
}

release_ports() {
    msg "${YELLOW}[*] 正在停止 A-Box 托管服务并检查端口占用...${NC}"
    stop_all_managed_services
    sleep 1
    local pairs pair proto p holder
    pairs=$(selected_port_pairs | awk 'NF' | sort -u)
    for pair in $pairs; do
        proto=${pair%/*}; p=${pair#*/}
        holder=$(ss -H -n -l -p -A "$proto" 2>/dev/null | grep -E "[:.]${p}\b" | grep -vE 'xray|sing-box|hysteria' || true)
        [[ -z "$holder" ]] && continue
        msg "${RED}[!] 端口 ${p}/${proto} 已被非 A-Box 进程占用：${NC}"
        echo "$holder"
        die "请先手动释放端口 ${p}/${proto}。脚本不会自动 kill 非托管进程。"
    done
}

write_if_changed() {
    local target="$1" tmp="$2"
    if [[ -f "$target" ]] && cmp -s "$tmp" "$target"; then
        rm -f "$tmp"
    else
        mv -f "$tmp" "$target"
    fi
}

setup_shortcut() {
    mkdir -p "$ABOX_DIR"
    local script_tmp=''
    if [[ "${1:-}" == 'update' ]]; then
        script_tmp=$(mktemp /tmp/A-Box-script.XXXXXX.sh) || die '快捷入口临时脚本创建失败。'
        curl -fLs --connect-timeout 10 "$SCRIPT_URL" -o "$script_tmp" || { rm -f "$script_tmp"; die '快捷入口脚本下载失败。'; }
        bash -n "$script_tmp" || { rm -f "$script_tmp"; die '更新脚本语法校验失败。'; }
        grep -q '==============================A-Box===============================' "$script_tmp" || { rm -f "$script_tmp"; die '更新脚本文本指纹不匹配。'; }
        write_if_changed "$ABOX_DIR/A-Box.sh" "$script_tmp"
    elif [[ -f "$0" && -r "$0" && "$0" != 'bash' && "$0" != '-bash' ]]; then
        if [[ ! -f "$ABOX_DIR/A-Box.sh" ]] || ! cmp -s "$0" "$ABOX_DIR/A-Box.sh"; then
            cp -f "$0" "$ABOX_DIR/A-Box.sh"
        fi
    elif [[ ! -f "$ABOX_DIR/A-Box.sh" ]]; then
        script_tmp=$(mktemp /tmp/A-Box-script.XXXXXX.sh) || die '持久化入口临时脚本创建失败。'
        curl -fLs --connect-timeout 10 "$SCRIPT_URL" -o "$script_tmp" || { rm -f "$script_tmp"; die '无法从远端创建持久化入口。'; }
        bash -n "$script_tmp" || { rm -f "$script_tmp"; die '持久化脚本语法校验失败。'; }
        grep -q '==============================A-Box===============================' "$script_tmp" || { rm -f "$script_tmp"; die '持久化脚本文本指纹不匹配。'; }
        write_if_changed "$ABOX_DIR/A-Box.sh" "$script_tmp"
    fi
    chmod +x "$ABOX_DIR/A-Box.sh"

    local shortcut_tmp
    shortcut_tmp=$(mktemp /tmp/A-Box-sb.XXXXXX) || die '快捷入口临时文件创建失败。'
    cat > "$shortcut_tmp" <<'EOS'
#!/usr/bin/env bash
if [[ $EUID -eq 0 ]]; then
    exec bash /etc/ddr/A-Box.sh "$@"
elif command -v sudo >/dev/null 2>&1; then
    exec sudo bash /etc/ddr/A-Box.sh "$@"
else
    echo 'Root privileges required. Please run: su -'
    exit 1
fi
EOS
    chmod 755 "$shortcut_tmp"
    if [[ ! -f /usr/local/bin/sb ]] || ! cmp -s "$shortcut_tmp" /usr/local/bin/sb; then
        install -m 755 "$shortcut_tmp" /usr/local/bin/sb || die '快捷入口写入失败。'
        rm -f "$shortcut_tmp"
    else
        rm -f "$shortcut_tmp"
        chmod 755 /usr/local/bin/sb 2>/dev/null || true
    fi
}
validate_downloaded_asset() {
    local asset_name="$1" f="${2:-/tmp/$1}"
    [[ -s "$f" ]] || die "下载资产为空: $asset_name"
    case "$asset_name" in
        xray_core.zip) unzip -tqq "$f" >/dev/null 2>&1 || die 'Xray 压缩包校验失败。' ;;
        singbox_core.tar.gz) tar -tzf "$f" >/dev/null 2>&1 || die 'Sing-box 压缩包校验失败。' ;;
        hysteria_core) [[ "$(head -c 4 "$f" | od -An -tx1 | tr -d ' \n')" == '7f454c46' ]] || die 'Hysteria 下载结果不是 ELF 可执行文件。' ;;
        *) die "未定义的下载校验规则: $asset_name" ;;
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
    local repo=$1 output_file=$2 dest_file="${3:-}" api_url asset_re release_json asset_json download_url digest mirror tmp_file tmp_dir
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

    if [[ -z "$dest_file" ]]; then
        tmp_dir=$(mktemp -d /tmp/A-Box-asset.XXXXXX) || die '核心资产临时目录创建失败。'
        dest_file="$tmp_dir/$output_file"
    else
        mkdir -p "$(dirname "$dest_file")"
        rm -f -- "$dest_file"
    fi

    for mirror in '' 'https://ghp.ci/' 'https://mirror.ghproxy.com/'; do
        tmp_file=$(mktemp "${dest_file}.download.XXXXXX") || die '核心资产临时文件创建失败。'
        if curl -fLsS --connect-timeout 10 -m 180 "${mirror}${download_url}" -o "$tmp_file"; then
            mv -f "$tmp_file" "$dest_file"
            validate_downloaded_asset "$output_file" "$dest_file"
            verify_github_asset_digest "$dest_file" "$digest"
            FETCHED_ASSET_PATH="$dest_file"
            msg "${GREEN}   核心资产提取成功。${NC}"
            return 0
        fi
        rm -f "$tmp_file"
    done
    die '所有通道均无法下载核心资产。请检查网络。'
}

fetch_geo_data() {
    local file_name official_url out tmp_out size
    file_name="${1:-}"
    official_url="${2:-}"
    out="${3:-}"
    [[ -n "$file_name" && -n "$official_url" ]] || die 'Geo 数据下载参数缺失。'
    [[ "$file_name" =~ ^[A-Za-z0-9._-]+$ ]] || die "Geo 数据文件名非法: $file_name"
    [[ -n "$out" ]] || out="$(mktemp "/tmp/${file_name}.XXXXXX")"
    mkdir -p "$(dirname "$out")"
    tmp_out=$(mktemp "${out}.download.XXXXXX") || die 'Geo 数据临时文件创建失败。'
    if curl -fLs --connect-timeout 10 -m 90 "$official_url" -o "$tmp_out"; then
        size=$(wc -c < "$tmp_out" 2>/dev/null | tr -d ' ')
        if [[ -n "$size" && "$size" -gt 500000 ]]; then
            mv -f "$tmp_out" "$out"
            FETCHED_GEO_PATH="$out"
            return 0
        fi
    fi
    rm -f -- "$tmp_out" "$out"
    die "Geo 数据文件 ${file_name} 下载或校验失败。"
}

reset_protocol_vars() {
    unset UUID VLESS_SNI VISION_SNI XHTTP_SNI VLESS_PORT XHTTP_PORT HY2_BASE_PORT HY2_DOMAIN HY2_UP HY2_DOWN HY2_MASQ_URL
    unset SS_PORT SS_WHITELIST_IP PUBLIC_KEY PBK SHORT_ID HY2_PASS HY2_OBFS SS_PASS
    unset HY2_CERT_SHA256_FP HY2_CERT_PUBKEY_SHA256_B64 HY2_HOP HY2_HOP_IMPL HY2_MONITOR_PORT
    unset HY2_ACME_TYPE HY2_ACME_DNS_PROVIDER HY2_ACME_DNS_CF_API_TOKEN
    unset HY2_URI_PORTS HY2_CLASH_PORTS HY2_SB_PORTS HY2_RANGE_START HY2_RANGE_END ENABLE_KEEPALIVE
}

write_env() {
    local env_core="$1" env_mode="$2" old_traffic_limit_gb='' old_traffic_limit_mode=''
    if [[ -f "$ABOX_ENV" ]]; then
        old_traffic_limit_gb=$(grep '^TRAFFIC_LIMIT_GB=' "$ABOX_ENV" | tail -n 1 | cut -d= -f2- | tr -d '"')
        old_traffic_limit_mode=$(grep '^TRAFFIC_LIMIT_MODE=' "$ABOX_ENV" | tail -n 1 | cut -d= -f2- | tr -d '"')
    fi
    umask 077
    {
        printf 'CORE=%s\n' "$(shell_quote "$env_core")"
        printf 'MODE=%s\n' "$(shell_quote "$env_mode")"
        printf 'UUID=%s\n' "$(shell_quote "${UUID:-}")"
        printf 'VLESS_SNI=%s\n' "$(shell_quote "${VLESS_SNI:-}")"
        printf 'VISION_SNI=%s\n' "$(shell_quote "${VISION_SNI:-}")"
        printf 'XHTTP_SNI=%s\n' "$(shell_quote "${XHTTP_SNI:-}")"
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
        printf 'HY2_ACME_TYPE=%s\n' "$(shell_quote "${HY2_ACME_TYPE:-http}")"
        printf 'HY2_ACME_DNS_PROVIDER=%s\n' "$(shell_quote "${HY2_ACME_DNS_PROVIDER:-}")"
        printf 'HY2_ACME_DNS_CF_API_TOKEN=%s\n' "$(shell_quote "${HY2_ACME_DNS_CF_API_TOKEN:-}")"
        printf 'HY2_URI_PORTS=%s\n' "$(shell_quote "${HY2_URI_PORTS:-}")"
        printf 'HY2_CLASH_PORTS=%s\n' "$(shell_quote "${HY2_CLASH_PORTS:-}")"
        printf 'HY2_SB_PORTS=%s\n' "$(shell_quote "${HY2_SB_PORTS:-}")"
        printf 'HY2_RANGE_START=%s\n' "$(shell_quote "${HY2_RANGE_START:-}")"
        printf 'HY2_RANGE_END=%s\n' "$(shell_quote "${HY2_RANGE_END:-}")"
        printf 'INGRESS_IF=%s\n' "$(shell_quote "${INGRESS_IF:-}")"
        printf 'ENABLE_KEEPALIVE=%s\n' "$(shell_quote "${ENABLE_KEEPALIVE:-}")"
        [[ -n "$old_traffic_limit_gb" ]] && printf 'TRAFFIC_LIMIT_GB=%s\n' "$(shell_quote "$old_traffic_limit_gb")"
        [[ -n "$old_traffic_limit_mode" ]] && printf 'TRAFFIC_LIMIT_MODE=%s\n' "$(shell_quote "$old_traffic_limit_mode")"
    } > "$ABOX_ENV"
    chmod 600 "$ABOX_ENV"
}

setup_active_defense() {
    msg "${YELLOW}[*] 正在挂载环形缓冲日志与 Fail2Ban 主动防御矩阵...${NC}"
    touch /var/log/A-Box-xray-access.log /var/log/A-Box-xray-error.log /var/log/A-Box-singbox.log /var/log/A-Box-hysteria.log 2>/dev/null || true
    chmod 644 /var/log/A-Box-*.log 2>/dev/null || true
    cat > /etc/logrotate.d/A-Box <<'EOF_LOGROTATE'
/var/log/A-Box-*.log {
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
        cat > /etc/fail2ban/filter.d/A-Box.conf <<'EOF_F2B_FILTER'
[Definition]
failregex = ^.*(?:rejected|invalid request|bad request|authentication failed).* from <HOST>[: ].*$
            ^.*<HOST>.*(?:rejected|invalid|unauthorized|forbidden).*$
ignoreregex =
EOF_F2B_FILTER
        local f2b_ports=''
        [[ -n "${VLESS_PORT:-}" ]] && f2b_ports+="${VLESS_PORT},"
        [[ -n "${XHTTP_PORT:-}" ]] && f2b_ports+="${XHTTP_PORT},"
        [[ -n "${HY2_BASE_PORT:-}" ]] && f2b_ports+="${HY2_BASE_PORT},"
        if [[ "${HY2_HOP:-}" == 'true' && -n "${HY2_RANGE_START:-}" && -n "${HY2_RANGE_END:-}" ]]; then
            f2b_ports+="${HY2_RANGE_START}:${HY2_RANGE_END},"
        fi
        [[ -n "${SS_PORT:-}" ]] && f2b_ports+="${SS_PORT},"
        f2b_ports="${f2b_ports%,}"
        [[ -z "$f2b_ports" ]] && f2b_ports='1-65535'
        cat > /etc/fail2ban/jail.d/A-Box.local <<EOF_F2B_JAIL
[A-Box]
enabled = true
ignoreip = 127.0.0.1/8 ::1
port = ${f2b_ports}
filter = A-Box
logpath = /var/log/A-Box-xray-error.log
          /var/log/A-Box-singbox.log
          /var/log/A-Box-hysteria.log
maxretry = 8
findtime = 120
bantime = 3600
action = iptables-multiport[name=A-Box, port="${f2b_ports}", protocol=tcp]
         iptables-multiport[name=A-Box-udp, port="${f2b_ports}", protocol=udp]
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
    mkdir -p "$ABOX_DIR"
    cat > "$ABOX_DIR/socket_probe.sh" <<'EOF_PROBE'
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
    if ! $IPT -w -t nat -S PREROUTING 2>/dev/null | grep -q 'A-Box-HY2-HOP'; then
        check_restart "$HY2_SRV"
        exit 0
    fi
    if has_ipv6 && ipv6_nat_redirect_usable; then
        if ! $IPT6 -w -t nat -S PREROUTING 2>/dev/null | grep -q 'A-Box-HY2-HOP'; then
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
    chmod +x "$ABOX_DIR/socket_probe.sh"
    local tmp_cron
    tmp_cron=$(mktemp)
    crontab -l 2>/dev/null | grep -vE '^no crontab for|^#' | grep -v '/etc/ddr/socket_probe.sh' > "$tmp_cron" || true
    echo '* * * * * /bin/bash /etc/ddr/socket_probe.sh >/dev/null 2>&1' >> "$tmp_cron"
    crontab "$tmp_cron" 2>/dev/null || true
    rm -f "$tmp_cron"
}

setup_geo_cron() {
    mkdir -p "$ABOX_DIR"
    cat > "$ABOX_DIR/geo_update.sh" <<'EOF_GEO'
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

[[ -d '/usr/local/share/xray' ]] || exit 0

tmpdir=$(mktemp -d /tmp/A-Box-geo.XXXXXX) || exit 1
trap 'rm -rf "$tmpdir"' EXIT
fetch_one "$GEOIP_URL" "$tmpdir/geoip.dat" || exit 1
fetch_one "$GEOSITE_URL" "$tmpdir/geosite.dat" || exit 1

install -m 644 "$tmpdir/geoip.dat" /usr/local/share/xray/geoip.dat
install -m 644 "$tmpdir/geosite.dat" /usr/local/share/xray/geosite.dat
if command -v systemctl >/dev/null 2>&1; then systemctl restart xray 2>/dev/null || true; else rc-service xray restart 2>/dev/null || true; fi
# sing-box GeoIP/Geosite are intentionally not updated here. New sing-box releases removed
# legacy geoip/geosite support; use rule-set based configs when route databases are needed.
EOF_GEO
    chmod +x "$ABOX_DIR/geo_update.sh"
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
    local DEF_V_PORT=443 DEF_X_PORT=8443 DEF_H_PORT=443 DEF_S_PORT=2053
    local INPUT_V_PORT INPUT_X_PORT INPUT_H_PORT INPUT_H_DOMAIN INPUT_H_HOP INPUT_H_DOWN INPUT_H_UP INPUT_H_MASQ INPUT_S_PORT INPUT_SS_WL INPUT_KA ip prompt
    local HAS_VISION=false HAS_XHTTP=false HAS_HY2=false HAS_SS=false
    local L_VISION L_XHTTP L_HY2 L_SS L_GLOBAL
    L_VISION=$(proto_label 'VLESS-Vision')
    L_XHTTP=$(proto_label 'VLESS-XHTTP')
    L_HY2=$(proto_label 'HY2')
    L_SS=$(proto_label 'SS-2022')
    if [[ "${ABOX_LANG:-zh}" == 'en' ]]; then L_GLOBAL=$(proto_label 'Global'); else L_GLOBAL=$(proto_label '全局'); fi
    [[ "$MODE_IN" == *'VISION'* || "$MODE_IN" == *'ALL'* || "$MODE_IN" == 'VLESS_SS' ]] && HAS_VISION=true
    [[ "$CORE_IN" == 'xray' && ( "$MODE_IN" == *'XHTTP'* || "$MODE_IN" == *'ALL'* ) ]] && HAS_XHTTP=true
    [[ "$MODE_IN" == *'HY2'* || "$MODE_IN" == *'ALL'* ]] && HAS_HY2=true
    [[ "$MODE_IN" == *'SS'* || "$MODE_IN" == *'ALL'* || "$MODE_IN" == 'VLESS_SS' ]] && HAS_SS=true

    # Xray ALL: Vision TCP 443 + XHTTP TCP 8443 + HY2 UDP 443 + SS-2022 TCP/UDP 2053.
    # Sing-box ALL: Vision TCP 443 + HY2 UDP 443 + SS-2022 TCP/UDP 2053. XHTTP is intentionally excluded.

    INGRESS_IF=$(get_active_interface)
    [[ -z "$INGRESS_IF" ]] && die '无法识别公网入接口。'
    GLOBAL_PUBLIC_IP=$(refresh_public_ip)

    msg "\n${CYAN}======================================================================${NC}"
    if [[ "${ABOX_LANG:-zh}" == 'en' ]]; then
        msg "${BOLD}Parameter Wizard [Engine: $CORE_IN | Mode: $MODE_IN]${NC}"
    else
        msg "${BOLD}参数构造向导 [Engine: $CORE_IN | Mode: $MODE_IN]${NC}"
    fi
    msg "${BLUE}----------------------------------------------------------------------${NC}"

    if [[ "$HAS_VISION" == 'true' ]]; then
        VLESS_PORT=$(prompt_port_input "$L_VISION" "$DEF_V_PORT")
        VISION_SNI=$(prompt_reality_sni "$L_VISION" "$VLESS_PORT")
    fi
    if [[ "$HAS_XHTTP" == 'true' ]]; then
        XHTTP_PORT=$(prompt_port_input "$L_XHTTP" "$DEF_X_PORT")
        XHTTP_SNI=$(prompt_reality_sni "$L_XHTTP" "$XHTTP_PORT")
    fi
    VLESS_SNI=${VISION_SNI:-${XHTTP_SNI:-www.microsoft.com}}

    if [[ "$HAS_HY2" == 'true' ]]; then
        HY2_BASE_PORT=$(prompt_port_input "$L_HY2" "$DEF_H_PORT")

        if [[ "${ABOX_LANG:-zh}" == 'en' ]]; then
            read -r -ep "   ${L_HY2} Do you have a domain already resolved to this server? (empty = self-signed certificate): " INPUT_H_DOMAIN
        else
            read -r -ep "   ${L_HY2} 是否拥有已解析到本机的域名？(留空使用默认自签证书): " INPUT_H_DOMAIN
        fi
        HY2_DOMAIN="$INPUT_H_DOMAIN"
        if [[ -n "$HY2_DOMAIN" ]]; then
            valid_domain "$HY2_DOMAIN" || die "域名格式非法 / Invalid domain: $HY2_DOMAIN"
            [[ "${GLOBAL_PUBLIC_IP:-N/A}" != 'N/A' ]] && verify_domain_points_to_self "$HY2_DOMAIN" "$GLOBAL_PUBLIC_IP"
            HY2_ACME_TYPE='http'
            HY2_ACME_DNS_PROVIDER=''
            HY2_ACME_DNS_CF_API_TOKEN=''
            if [[ "$CORE_IN" == 'hysteria' || "$MODE_IN" == *'ALL'* ]]; then
                if [[ -n "${ABOX_HY2_ACME_DNS_PROVIDER:-${ABOX_ACME_DNS_PROVIDER:-}}" ]]; then
                    HY2_ACME_TYPE='dns'
                    HY2_ACME_DNS_PROVIDER="${ABOX_HY2_ACME_DNS_PROVIDER:-${ABOX_ACME_DNS_PROVIDER:-}}"
                    HY2_ACME_DNS_CF_API_TOKEN="${ABOX_HY2_ACME_DNS_CF_API_TOKEN:-${ABOX_ACME_DNS_CF_API_TOKEN:-}}"
                else
                    local INPUT_ACME_DNS INPUT_CF_TOKEN
                    if [[ "${ABOX_LANG:-zh}" == 'en' ]]; then
                        read -r -ep "   ${L_HY2} Use Cloudflare DNS-01 ACME instead of HTTP-01? [Y/N]: " INPUT_ACME_DNS
                    else
                        read -r -ep "   ${L_HY2} 是否使用 Cloudflare DNS-01 申请证书以避免占用 80 端口？[Y/N]: " INPUT_ACME_DNS
                    fi
                    if is_yes "$INPUT_ACME_DNS"; then
                        HY2_ACME_TYPE='dns'
                        HY2_ACME_DNS_PROVIDER='cloudflare'
                        read -r -sep "   ${L_HY2} Cloudflare API Token: " INPUT_CF_TOKEN; echo
                        HY2_ACME_DNS_CF_API_TOKEN="$INPUT_CF_TOKEN"
                    fi
                fi
                if [[ "${HY2_ACME_TYPE:-http}" == 'dns' ]]; then
                    [[ "${HY2_ACME_DNS_PROVIDER:-}" == 'cloudflare' ]] || die '当前仅内置支持 Cloudflare DNS-01 ACME。'
                    [[ -n "${HY2_ACME_DNS_CF_API_TOKEN:-}" ]] || die 'Cloudflare DNS-01 ACME 需要 API Token。'
                fi
            fi
        fi

        if [[ "${ABOX_LANG:-zh}" == 'en' ]]; then
            read -r -ep "   ${L_HY2} Enable port hopping? [Y/N]: " INPUT_H_HOP
        else
            read -r -ep "   ${L_HY2} 是否开启端口跳跃 (单端口被限速环境建议开启)? [Y/N]: " INPUT_H_HOP
        fi
        if is_yes "$INPUT_H_HOP"; then
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

        if [[ "${ABOX_LANG:-zh}" == 'en' ]]; then
            HY2_DOWN=$(prompt_positive_int_input "   ${L_HY2} Downlink Mbps (default: 1000): " 1000)
        else
            HY2_DOWN=$(prompt_positive_int_input "   ${L_HY2} 下行速率(Mbps) (回车默认: 1000): " 1000)
        fi
        if [[ "${ABOX_LANG:-zh}" == 'en' ]]; then
            HY2_UP=$(prompt_positive_int_input "   ${L_HY2} Uplink Mbps (default: 100): " 100)
        else
            HY2_UP=$(prompt_positive_int_input "   ${L_HY2} 上行速率(Mbps) (回车默认: 100): " 100)
        fi

        local masq_default="https://${VISION_SNI:-${XHTTP_SNI:-www.samsung.com}}/"
        if [[ "${ABOX_LANG:-zh}" == 'en' ]]; then
            HY2_MASQ_URL=$(prompt_https_url "   ${L_HY2} Enter HTTP/3 masquerade URL (default: $masq_default): " "$masq_default")
        else
            HY2_MASQ_URL=$(prompt_https_url "   ${L_HY2} 请输入 HTTP/3 伪装站点 URL (回车默认: $masq_default): " "$masq_default")
        fi
    fi
    if [[ "$HAS_SS" == 'true' ]]; then
        SS_PORT=$(prompt_ss_port_input "$L_SS" "$DEF_S_PORT")
        if [[ "${ABOX_LANG:-zh}" == 'en' ]]; then
            read -r -ep "   ${L_SS} Enter frontend whitelist IP/CIDR (empty = open to all, space-separated): " INPUT_SS_WL
        else
            read -r -ep "   ${L_SS} 请输入前置机白名单 IP/CIDR (留空全网开放, 多个用空格分隔): " INPUT_SS_WL
        fi
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

    if [[ "${ABOX_LANG:-zh}" == 'en' ]]; then
        read -r -ep "   ${L_GLOBAL} Enable TCP KeepAlive 45s to prevent NAT idle disconnect? [Y/N]: " INPUT_KA
    else
        read -r -ep "   ${L_GLOBAL} 是否开启 TCP KeepAlive (45s) 防治 NAT 空闲断连? [Y/N]: " INPUT_KA
    fi
    is_yes "$INPUT_KA" && ENABLE_KEEPALIVE='true' || ENABLE_KEEPALIVE='false'
    msg "${CYAN}======================================================================${NC}\n"

    check_selected_ports_free
    if [[ "$HAS_HY2" == 'true' && -n "${HY2_DOMAIN:-}" && "${HY2_ACME_TYPE:-http}" == 'http' && ( "$CORE_IN" == 'hysteria' || "$MODE_IN" == *'ALL'* ) ]]; then
        holder=$(ss -H -n -l -p -A tcp 2>/dev/null | grep -E '[:.]80\b' | grep -vE 'xray|sing-box|hysteria' || true)
        if [[ -n "$holder" ]]; then
            msg "${RED}[!] ACME HTTP-01 需要 80/tcp，但该端口已被非 A-Box 进程占用：${NC}"
            echo "$holder"
            die '请先释放 80/tcp，或改用 Cloudflare DNS-01 ACME 后再部署 HY2 域名证书。'
        fi
    fi

    [[ "$HAS_VISION" == 'true' ]] && allowPort "$VLESS_PORT" tcp
    [[ "$HAS_XHTTP" == 'true' ]] && allowPort "$XHTTP_PORT" tcp
    if [[ "$HAS_HY2" == 'true' ]]; then
        if [[ -n "$HY2_DOMAIN" && "${HY2_ACME_TYPE:-http}" == 'http' && ( "$CORE_IN" == 'hysteria' || "$MODE_IN" == *'ALL'* ) ]]; then
            allowPort 80 tcp
        fi
        if [[ "$HY2_HOP" == 'true' ]]; then
            allowPort "${HY2_RANGE_START}:${HY2_RANGE_END}" udp
            [[ "$HY2_HOP_IMPL" == 'manual' ]] && allowPort "$HY2_BASE_PORT" udp
        else
            allowPort "$HY2_BASE_PORT" udp
        fi
    fi
    if [[ "$HAS_SS" == 'true' ]]; then
        if [[ -n "${SS_WHITELIST_IP:-}" ]]; then
            for ip in $SS_WHITELIST_IP; do
                for proto in tcp udp; do
                    if [[ "$ip" == *:* ]]; then
                        if has_ipv6 && command -v ip6tables >/dev/null 2>&1 && $IPT6 -w -S INPUT >/dev/null 2>&1; then
                            if ! $IPT6 -w -C INPUT -p "$proto" --dport "$SS_PORT" -s "$ip" -j ACCEPT 2>/dev/null; then
                                $IPT6 -w -I INPUT -p "$proto" --dport "$SS_PORT" -s "$ip" -m comment --comment "A-Box-${SS_PORT}-${proto}-WL6" -j ACCEPT >/dev/null 2>&1 || die "IPv6 白名单规则写入失败: $ip/$proto"
                            fi
                        fi
                    else
                        if ! $IPT -w -C INPUT -p "$proto" --dport "$SS_PORT" -s "$ip" -j ACCEPT 2>/dev/null; then
                            $IPT -w -I INPUT -p "$proto" --dport "$SS_PORT" -s "$ip" -m comment --comment "A-Box-${SS_PORT}-${proto}-WL" -j ACCEPT >/dev/null 2>&1 || die "IPv4 白名单规则写入失败: $ip/$proto"
                        fi
                    fi
                done
            done
            for proto in tcp udp; do
                if ! $IPT -w -C INPUT -p "$proto" --dport "$SS_PORT" -j DROP 2>/dev/null; then
                    $IPT -w -A INPUT -p "$proto" --dport "$SS_PORT" -m comment --comment "A-Box-${SS_PORT}-${proto}-DROP" -j DROP >/dev/null 2>&1 || die "IPv4 SS DROP 规则写入失败: $proto"
                fi
                if has_ipv6 && command -v ip6tables >/dev/null 2>&1 && $IPT6 -w -S INPUT >/dev/null 2>&1; then
                    if ! $IPT6 -w -C INPUT -p "$proto" --dport "$SS_PORT" -j DROP 2>/dev/null; then
                        $IPT6 -w -A INPUT -p "$proto" --dport "$SS_PORT" -m comment --comment "A-Box-${SS_PORT}-${proto}-DROP6" -j DROP >/dev/null 2>&1 || die "IPv6 SS DROP 规则写入失败: $proto"
                    fi
                fi
            done
        else
            allowPort "$SS_PORT" tcp
            allowPort "$SS_PORT" udp
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
        --arg v_sni "${VISION_SNI:-${VLESS_SNI:-www.apple.com}}" \
        --arg x_sni "${XHTTP_SNI:-${VLESS_SNI:-www.microsoft.com}}" \
        --arg pk "$PK" \
        --arg sid "$SHORT_ID" \
        --argjson vport "${VLESS_PORT:-443}" \
        --argjson xport "${XHTTP_PORT:-8443}" \
        --argjson ssport "${SS_PORT:-2053}" \
        --arg ss_pass "$SS_PASS" \
        --argjson sock "$sockopt_json" '
        def maybe_sock: if $sock == null then {} else {sockopt:$sock} end;
        def vision:
          {
            listen:"::", port:$vport, protocol:"vless",
            settings:{clients:[{id:$uuid, flow:"xtls-rprx-vision"}], decryption:"none"},
            streamSettings:({network:"tcp", security:"reality", realitySettings:{target:($v_sni + ":443"), serverNames:[$v_sni], privateKey:$pk, shortIds:[$sid]}} + maybe_sock),
            sniffing:{enabled:true, destOverride:["http","tls","quic"]}
          };
        def xhttp:
          {
            listen:"::", port:$xport, protocol:"vless",
            settings:{clients:[{id:$uuid}], decryption:"none"},
            streamSettings:({network:"xhttp", security:"reality", xhttpSettings:{mode:"auto", path:"/xhttp"}, realitySettings:{target:($x_sni + ":443"), serverNames:[$x_sni], privateKey:$pk, shortIds:[$sid]}} + maybe_sock),
            sniffing:{enabled:true, destOverride:["http","tls","quic"]}
          };
        def ss:
          ({listen:"::", port:$ssport, protocol:"shadowsocks", settings:{method:"2022-blake3-aes-128-gcm", password:$ss_pass, network:"tcp,udp"}}
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
        log:{loglevel:"warning", access:"/var/log/A-Box-xray-access.log", error:"/var/log/A-Box-xray-error.log"},
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
        --arg v_sni "${VISION_SNI:-${VLESS_SNI:-www.apple.com}}" \
        --arg x_sni "${XHTTP_SNI:-${VLESS_SNI:-www.microsoft.com}}" \
        --arg pk "$PK" \
        --arg sid "$SHORT_ID" \
        --argjson vport "${VLESS_PORT:-443}" \
        --argjson hy2port "${HY2_BASE_PORT:-443}" \
        --argjson ssport "${SS_PORT:-2053}" \
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
            tls:{enabled:true, server_name:$v_sni, reality:{enabled:true, handshake:{server:$v_sni, server_port:443}, private_key:$pk, short_id:[$sid]}}
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
            method:"2022-blake3-aes-128-gcm", password:$ss_pass
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
        log:{level:"warn", output:"/var/log/A-Box-singbox.log"},
        route:{rules:[{protocol:"bittorrent", action:"route", outbound:"block"}], auto_detect_interface:true},
        inbounds:$inbounds,
        outbounds:[{type:"direct", tag:"direct"}, {type:"block", tag:"block"}]
    }' > "$tmp_out" || { rm -f "$tmp_out"; die 'Sing-box JSON 生成失败。'; }
    mv -f "$tmp_out" "$out"
}

deploy_official_hy2() {
    local IS_SILENT=${1:-NORMAL} TLS_CONFIG HY2_LISTEN cert_cn HY2_CAPS='CAP_NET_BIND_SERVICE' hy2_tmp hy2_bin
    if [[ "$IS_SILENT" != 'SILENT' ]]; then
        clear; msg "${BOLD}${GREEN}部署官方 Hysteria 2${NC}"
        init_system_environment
        source "$ABOX_ENV" 2>/dev/null || true
        confirm_deployment_replacement hysteria HY2
        release_ports
        clean_nat_rules
        clean_input_rules
        save_firewall_rules
        pre_install_setup hysteria HY2
        get_architecture
    fi

    hy2_tmp=$(mktemp -d /tmp/A-Box-hysteria.XXXXXX) || die 'Hysteria 临时目录创建失败。'
    hy2_bin="$hy2_tmp/hysteria_core"
    fetch_github_release apernet/hysteria hysteria_core "$hy2_bin"
    install -m 755 "$hy2_bin" /usr/local/bin/hysteria || die '安装 hysteria 失败。'
    rm -rf "$hy2_tmp"
    /usr/local/bin/hysteria version >/dev/null 2>&1 || die 'Hysteria 执行校验失败。'

    HY2_PASS=$(rand_alnum 20)
    HY2_OBFS=$(rand_alnum 16)
    mkdir -p /etc/hysteria

    if [[ -n "${HY2_DOMAIN:-}" ]]; then
        if [[ "${HY2_ACME_TYPE:-http}" == 'dns' ]]; then
            [[ "${HY2_ACME_DNS_PROVIDER:-}" == 'cloudflare' ]] || die '当前仅内置支持 Cloudflare DNS-01 ACME。'
            [[ -n "${HY2_ACME_DNS_CF_API_TOKEN:-}" ]] || die 'Cloudflare DNS-01 ACME 需要 API Token。'
            TLS_CONFIG="acme:
  domains:
    - ${HY2_DOMAIN}
  email: admin@${HY2_DOMAIN}
  type: dns
  dns:
    name: cloudflare
    config:
      cloudflare_api_token: ${HY2_ACME_DNS_CF_API_TOKEN}"
        else
            TLS_CONFIG="acme:
  domains:
    - ${HY2_DOMAIN}
  email: admin@${HY2_DOMAIN}
  type: http
  http:
    altPort: 80"
        fi
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
        HY2_CAPS='CAP_NET_ADMIN CAP_NET_BIND_SERVICE'
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
        cat > /etc/systemd/system/hysteria.service <<EOF_SVC
[Unit]
Description=Hysteria 2 Service
After=network-online.target
Wants=network-online.target

[Service]
CapabilityBoundingSet=${HY2_CAPS}
AmbientCapabilities=${HY2_CAPS}
ExecStart=/bin/sh -c 'exec /usr/local/bin/hysteria server -c /etc/hysteria/config.yaml >>/var/log/A-Box-hysteria.log 2>&1'
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
command_args="server -c /etc/hysteria/config.yaml >>/var/log/A-Box-hysteria.log 2>&1"
command_background="yes"
pidfile="/run/hysteria.pid"
depend() { need net; }
EOF_SVC
        chmod +x /etc/init.d/hysteria
    fi
    service_manager start hysteria
    setup_geo_cron
    setup_active_defense
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
    source "$ABOX_ENV" 2>/dev/null || true
    confirm_deployment_replacement xray "$MODE_IN"
    release_ports
    clean_nat_rules
    clean_input_rules
    save_firewall_rules
    pre_install_setup xray "$MODE_IN"
    get_architecture

    local xray_tmp xray_zip xray_ext geo_tmp
    xray_tmp=$(mktemp -d /tmp/A-Box-xray.XXXXXX) || die 'Xray 临时目录创建失败。'
    xray_zip="$xray_tmp/xray_core.zip"
    xray_ext="$xray_tmp/xray_ext"
    mkdir -p "$xray_ext"
    fetch_github_release XTLS/Xray-core xray_core.zip "$xray_zip"
    unzip -qo "$xray_zip" -d "$xray_ext" || die 'Xray 压缩包解压失败。'
    [[ -f "$xray_ext/xray" ]] || die '解压后未找到 xray 主程序。'
    install -m 755 "$xray_ext/xray" /usr/local/bin/xray || die '安装 xray 失败。'
    /usr/local/bin/xray version >/dev/null 2>&1 || die 'Xray 执行校验失败。'
    mkdir -p /usr/local/share/xray /usr/local/etc/xray

    geo_tmp="$xray_tmp/geo"
    mkdir -p "$geo_tmp"
    fetch_geo_data geoip.dat 'https://github.com/Loyalsoldier/v2ray-rules-dat/releases/latest/download/geoip.dat' "$geo_tmp/geoip.dat"
    fetch_geo_data geosite.dat 'https://github.com/Loyalsoldier/v2ray-rules-dat/releases/latest/download/geosite.dat' "$geo_tmp/geosite.dat"
    install -m 644 "$geo_tmp/geoip.dat" /usr/local/share/xray/geoip.dat
    install -m 644 "$geo_tmp/geosite.dat" /usr/local/share/xray/geosite.dat
    rm -rf "$xray_tmp"

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
CapabilityBoundingSet=CAP_NET_BIND_SERVICE
AmbientCapabilities=CAP_NET_BIND_SERVICE
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
    local MODE_IN=$1 KEYPAIR SB_PATH cert_cn='localhost' SB_PRE_START='' SB_POST_STOP='' SB_RC_PRE='' SB_RC_POST='' SB_CAPS='CAP_NET_BIND_SERVICE'
    clear; msg "${BOLD}${GREEN}部署 Sing-box 核心 [$MODE_IN]${NC}"
    init_system_environment
    source "$ABOX_ENV" 2>/dev/null || true
    confirm_deployment_replacement singbox "$MODE_IN"
    release_ports
    clean_nat_rules
    clean_input_rules
    save_firewall_rules
    pre_install_setup singbox "$MODE_IN"
    get_architecture

    local sb_tmp sb_tar sb_ext
    sb_tmp=$(mktemp -d /tmp/A-Box-singbox.XXXXXX) || die 'Sing-box 临时目录创建失败。'
    sb_tar="$sb_tmp/singbox_core.tar.gz"
    sb_ext="$sb_tmp/extract"
    mkdir -p "$sb_ext"
    fetch_github_release SagerNet/sing-box singbox_core.tar.gz "$sb_tar"
    tar -xzf "$sb_tar" -C "$sb_ext" || die 'Sing-box 压缩包解压失败。'
    SB_PATH=$(find "$sb_ext" -type f -name 'sing-box' | head -n 1)
    [[ -n "$SB_PATH" && -f "$SB_PATH" ]] || die '解压后未找到 sing-box 主程序。'
    install -m 755 "$SB_PATH" /usr/local/bin/sing-box || die '安装 sing-box 失败。'
    rm -rf "$sb_tmp"
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
        SB_CAPS='CAP_NET_ADMIN CAP_NET_BIND_SERVICE'
        SB_PRE_START="ExecStartPre=-/bin/sh -c '$IPT -w -t nat -D PREROUTING -i $INGRESS_IF -p udp --dport ${HY2_RANGE_START}:${HY2_RANGE_END} -m comment --comment \"A-Box-HY2-HOP\" -j REDIRECT --to-ports $HY2_BASE_PORT 2>/dev/null || true'
ExecStartPre=-/bin/sh -c '$IPT -w -t nat -A PREROUTING -i $INGRESS_IF -p udp --dport ${HY2_RANGE_START}:${HY2_RANGE_END} -m comment --comment \"A-Box-HY2-HOP\" -j REDIRECT --to-ports $HY2_BASE_PORT 2>/dev/null || true'"
        SB_POST_STOP="ExecStopPost=-/bin/sh -c '$IPT -w -t nat -D PREROUTING -i $INGRESS_IF -p udp --dport ${HY2_RANGE_START}:${HY2_RANGE_END} -m comment --comment \"A-Box-HY2-HOP\" -j REDIRECT --to-ports $HY2_BASE_PORT 2>/dev/null || true'"
        SB_RC_PRE="start_pre() {
  $IPT -w -t nat -D PREROUTING -i $INGRESS_IF -p udp --dport ${HY2_RANGE_START}:${HY2_RANGE_END} -m comment --comment \"A-Box-HY2-HOP\" -j REDIRECT --to-ports $HY2_BASE_PORT 2>/dev/null || true
  $IPT -w -t nat -A PREROUTING -i $INGRESS_IF -p udp --dport ${HY2_RANGE_START}:${HY2_RANGE_END} -m comment --comment \"A-Box-HY2-HOP\" -j REDIRECT --to-ports $HY2_BASE_PORT 2>/dev/null || true"
        SB_RC_POST="stop_post() {
  $IPT -w -t nat -D PREROUTING -i $INGRESS_IF -p udp --dport ${HY2_RANGE_START}:${HY2_RANGE_END} -m comment --comment \"A-Box-HY2-HOP\" -j REDIRECT --to-ports $HY2_BASE_PORT 2>/dev/null || true"
        if has_ipv6 && ipv6_nat_redirect_usable; then
            SB_PRE_START+="
ExecStartPre=-/bin/sh -c '$IPT6 -w -t nat -D PREROUTING -i $INGRESS_IF -p udp --dport ${HY2_RANGE_START}:${HY2_RANGE_END} -m comment --comment \"A-Box-HY2-HOP\" -j REDIRECT --to-ports $HY2_BASE_PORT 2>/dev/null || true'
ExecStartPre=-/bin/sh -c '$IPT6 -w -t nat -A PREROUTING -i $INGRESS_IF -p udp --dport ${HY2_RANGE_START}:${HY2_RANGE_END} -m comment --comment \"A-Box-HY2-HOP\" -j REDIRECT --to-ports $HY2_BASE_PORT 2>/dev/null || true'"
            SB_POST_STOP+="
ExecStopPost=-/bin/sh -c '$IPT6 -w -t nat -D PREROUTING -i $INGRESS_IF -p udp --dport ${HY2_RANGE_START}:${HY2_RANGE_END} -m comment --comment \"A-Box-HY2-HOP\" -j REDIRECT --to-ports $HY2_BASE_PORT 2>/dev/null || true'"
            SB_RC_PRE+="
  $IPT6 -w -t nat -D PREROUTING -i $INGRESS_IF -p udp --dport ${HY2_RANGE_START}:${HY2_RANGE_END} -m comment --comment \"A-Box-HY2-HOP\" -j REDIRECT --to-ports $HY2_BASE_PORT 2>/dev/null || true
  $IPT6 -w -t nat -A PREROUTING -i $INGRESS_IF -p udp --dport ${HY2_RANGE_START}:${HY2_RANGE_END} -m comment --comment \"A-Box-HY2-HOP\" -j REDIRECT --to-ports $HY2_BASE_PORT 2>/dev/null || true"
            SB_RC_POST+="
  $IPT6 -w -t nat -D PREROUTING -i $INGRESS_IF -p udp --dport ${HY2_RANGE_START}:${HY2_RANGE_END} -m comment --comment \"A-Box-HY2-HOP\" -j REDIRECT --to-ports $HY2_BASE_PORT 2>/dev/null || true"
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
CapabilityBoundingSet=$SB_CAPS
AmbientCapabilities=$SB_CAPS
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
    mkdir -p "$ABOX_DIR"
    cat > "$ABOX_DIR/traffic_monitor.sh" <<'EOF_TRAFFIC'
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
    chmod +x "$ABOX_DIR/traffic_monitor.sh"
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
    rm -f "$tmp_cron" "$ABOX_DIR/traffic_monitor.sh"
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
    source "$ABOX_ENV" 2>/dev/null || true
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
            touch "$ABOX_ENV"
            sed -i '/^TRAFFIC_LIMIT_GB=/d;/^TRAFFIC_LIMIT_MODE=/d' "$ABOX_ENV" 2>/dev/null || true
            printf 'TRAFFIC_LIMIT_GB=%q\nTRAFFIC_LIMIT_MODE=%q\n' "$limit_gb" "$mode_choice" >> "$ABOX_ENV"
            chmod 600 "$ABOX_ENV"
            setup_traffic_monitor
            msg "${GREEN}流量限制已设定为 ${limit_gb} GB，模式 ${mode_choice}。${NC}"
            pause_return
            ;;
        2)
            [[ -f "$ABOX_ENV" ]] && sed -i '/^TRAFFIC_LIMIT_GB=/d;/^TRAFFIC_LIMIT_MODE=/d' "$ABOX_ENV" 2>/dev/null || true
            disable_traffic_monitor
            source "$ABOX_ENV" 2>/dev/null || true
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
    source "$ABOX_ENV" 2>/dev/null || true
    [[ -z "${SS_PORT:-}" ]] && { msg "${RED}[!] 未检测到已部署的 SS-2022 服务端口。${NC}"; pause_return; return; }
    msg "${CYAN}======================================================================${NC}"
    msg "${BOLD}${GREEN}SS-2022 白名单 IP 管理 / SS-2022 Whitelist Manager${NC}"
    msg "${CYAN}======================================================================${NC}"
    msg "${YELLOW}当前 SS-2022 监听端口: $SS_PORT/TCP+UDP${NC}"
    msg "IPv4 白名单:"
    $IPT -nL INPUT --line-numbers 2>/dev/null | grep -E "(tcp|udp) dpt:$SS_PORT" | grep 'ACCEPT' | awk '{print $5}' | grep -v '0.0.0.0/0' | sort -u || true
    if command -v ip6tables >/dev/null 2>&1 && $IPT6 -nL INPUT >/dev/null 2>&1; then
        msg "IPv6 白名单:"
        $IPT6 -nL INPUT --line-numbers 2>/dev/null | grep -E "(tcp|udp) dpt:$SS_PORT" | grep 'ACCEPT' | awk '{print $5}' | grep -v '::/0' | sort -u || true
    fi
    msg "${BLUE}----------------------------------------------------------------------${NC}"
    msg "${YELLOW}1. 新增白名单 IP/CIDR (TCP+UDP)${NC}"
    msg "${YELLOW}2. 移除白名单 IP/CIDR (TCP+UDP)${NC}"
    msg "${YELLOW}3. 开启白名单模式 (TCP+UDP DROP)${NC}"
    msg "${YELLOW}4. 切换为全网开放 (移除 DROP 并放行 TCP+UDP)${NC}"
    msg "${GREEN}0. 返回主菜单${NC}"
    read -r -ep '请选择操作 [0-4]: ' wl_choice
    local add_ip del_ip rule found proto
    case "$wl_choice" in
        1)
            read -r -ep '请输入要放行的前置机 IP/CIDR: ' add_ip
            [[ -z "$add_ip" ]] && return
            if [[ "$add_ip" == *:* ]]; then
                valid_ipv6_cidr "$add_ip" || { msg "${RED}[!] IPv6 白名单地址非法: $add_ip${NC}"; pause_return; return; }
                has_ipv6 && command -v ip6tables >/dev/null 2>&1 && $IPT6 -w -S INPUT >/dev/null 2>&1 || die '系统无可用 IPv6 防火墙。'
                for proto in tcp udp; do
                    $IPT6 -w -I INPUT -p "$proto" --dport "$SS_PORT" -s "$add_ip" -m comment --comment "A-Box-${SS_PORT}-${proto}-WL6" -j ACCEPT >/dev/null 2>&1 || die "IPv6 白名单规则写入失败: $add_ip/$proto"
                done
            else
                valid_ipv4_cidr "$add_ip" || { msg "${RED}[!] IPv4 白名单地址非法: $add_ip${NC}"; pause_return; return; }
                for proto in tcp udp; do
                    $IPT -w -I INPUT -p "$proto" --dport "$SS_PORT" -s "$add_ip" -m comment --comment "A-Box-${SS_PORT}-${proto}-WL" -j ACCEPT >/dev/null 2>&1 || die "IPv4 白名单规则写入失败: $add_ip/$proto"
                done
            fi
            save_firewall_rules
            msg "${GREEN}已添加白名单: $add_ip (TCP+UDP)${NC}"
            pause_return
            ;;
        2)
            read -r -ep '请输入要移除的 IP/CIDR: ' del_ip
            [[ -z "$del_ip" ]] && return
            found=0
            if [[ "$del_ip" == *:* ]]; then
                valid_ipv6_cidr "$del_ip" || { msg "${RED}[!] IPv6 白名单地址非法: $del_ip${NC}"; pause_return; return; }
                for proto in tcp udp; do
                    while $IPT6 -w -S INPUT 2>/dev/null | grep -F "A-Box-${SS_PORT}-${proto}-WL6" | grep -Fq -- "$del_ip"; do
                        rule=$($IPT6 -w -S INPUT 2>/dev/null | grep -F "A-Box-${SS_PORT}-${proto}-WL6" | grep -F -- "$del_ip" | head -n 1 | sed 's/^-A /-D /')
                        [[ -z "$rule" ]] && break
                        # shellcheck disable=SC2086
                        $IPT6 -w $rule >/dev/null 2>&1 || die "IPv6 白名单规则删除失败: $del_ip/$proto"
                        found=1
                    done
                done
            else
                valid_ipv4_cidr "$del_ip" || { msg "${RED}[!] IPv4 白名单地址非法: $del_ip${NC}"; pause_return; return; }
                for proto in tcp udp; do
                    while $IPT -w -S INPUT 2>/dev/null | grep -F "A-Box-${SS_PORT}-${proto}-WL" | grep -Fq -- "$del_ip"; do
                        rule=$($IPT -w -S INPUT 2>/dev/null | grep -F "A-Box-${SS_PORT}-${proto}-WL" | grep -F -- "$del_ip" | head -n 1 | sed 's/^-A /-D /')
                        [[ -z "$rule" ]] && break
                        # shellcheck disable=SC2086
                        $IPT -w $rule >/dev/null 2>&1 || die "IPv4 白名单规则删除失败: $del_ip/$proto"
                        found=1
                    done
                done
            fi
            save_firewall_rules
            [[ "$found" == 1 ]] && msg "${GREEN}已移除白名单: $del_ip${NC}" || msg "${YELLOW}未找到该白名单规则。${NC}"
            pause_return
            ;;
        3)
            for proto in tcp udp; do
                if ! $IPT -w -C INPUT -p "$proto" --dport "$SS_PORT" -j DROP 2>/dev/null; then
                    $IPT -w -A INPUT -p "$proto" --dport "$SS_PORT" -m comment --comment "A-Box-${SS_PORT}-${proto}-DROP" -j DROP >/dev/null 2>&1 || die "IPv4 SS DROP 规则写入失败: $proto"
                fi
                if has_ipv6 && command -v ip6tables >/dev/null 2>&1 && $IPT6 -w -S INPUT >/dev/null 2>&1; then
                    if ! $IPT6 -w -C INPUT -p "$proto" --dport "$SS_PORT" -j DROP 2>/dev/null; then
                        $IPT6 -w -A INPUT -p "$proto" --dport "$SS_PORT" -m comment --comment "A-Box-${SS_PORT}-${proto}-DROP6" -j DROP >/dev/null 2>&1 || die "IPv6 SS DROP 规则写入失败: $proto"
                    fi
                fi
            done
            save_firewall_rules
            msg "${GREEN}已开启白名单保护模式 (TCP+UDP)。${NC}"
            pause_return
            ;;
        4)
            for proto in tcp udp; do
                while $IPT -w -S INPUT 2>/dev/null | grep -q "A-Box-${SS_PORT}-${proto}-DROP"; do
                    rule=$($IPT -w -S INPUT 2>/dev/null | grep "A-Box-${SS_PORT}-${proto}-DROP" | head -n 1 | sed 's/^-A /-D /')
                    [[ -z "$rule" ]] && break
                    # shellcheck disable=SC2086
                    $IPT -w $rule >/dev/null 2>&1 || break
                done
                if command -v ip6tables >/dev/null 2>&1 && $IPT6 -w -S INPUT >/dev/null 2>&1; then
                    while $IPT6 -w -S INPUT 2>/dev/null | grep -q "A-Box-${SS_PORT}-${proto}-DROP6"; do
                        rule=$($IPT6 -w -S INPUT 2>/dev/null | grep "A-Box-${SS_PORT}-${proto}-DROP6" | head -n 1 | sed 's/^-A /-D /')
                        [[ -z "$rule" ]] && break
                        # shellcheck disable=SC2086
                        $IPT6 -w $rule >/dev/null 2>&1 || break
                    done
                fi
                allowPort "$SS_PORT" "$proto"
            done
            save_firewall_rules
            msg "${GREEN}已切换为全网开放模式 (TCP+UDP)。${NC}"
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
    rm -f /etc/sysctl.d/99-A-Box-tune.conf /etc/security/limits.d/A-Box.conf
    sysctl --system >/dev/null 2>&1 || true
    local tmp_cron
    tmp_cron=$(mktemp)
    crontab -l 2>/dev/null | grep -vE '^no crontab for|^#' | grep -vE '/etc/ddr/traffic_monitor.sh|/etc/ddr/geo_update.sh|/etc/ddr/socket_probe.sh' > "$tmp_cron" || true
    crontab "$tmp_cron" 2>/dev/null || true
    rm -f "$tmp_cron"
    rm -f /var/log/A-Box-*.log /etc/fail2ban/jail.d/A-Box.local /etc/fail2ban/filter.d/A-Box.conf /etc/logrotate.d/A-Box 2>/dev/null || true
    if [[ "$INIT_SYS" == 'systemd' ]]; then
        systemctl restart fail2ban 2>/dev/null || true
        systemctl daemon-reload 2>/dev/null || true
    else
        rc-service fail2ban restart 2>/dev/null || true
    fi
    if [[ "${1:-}" == 'full' ]]; then
        rm -rf "$ABOX_DIR" /usr/local/bin/sb
        msg "${GREEN}完全清理完成。${NC}"
        exit 0
    else
        rm -f "$ABOX_ENV" "$ABOX_DIR"/.deps* "$ABOX_DIR/traffic_monitor.sh" "$ABOX_DIR/geo_update.sh" "$ABOX_DIR/socket_probe.sh"
        setup_shortcut
        msg "${GREEN}代理系统已销毁，保留 sb 入口。${NC}"
        pause_return
    fi
}

check_virgin_state() {
    clear
    init_system_environment
    msg "${YELLOW}删除全部节点与环境初始化 / Delete all nodes and perform environment initialization${NC}"
    read -r -ep '确定执行环境深度自愈吗？[Y/N]: ' confirm_virgin
    is_yes "$confirm_virgin" || { msg "${GREEN}操作已取消。${NC}"; pause_return; return; }
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
    rm -f "$ABOX_ENV" "$ABOX_DIR"/.deps* "$ABOX_DIR/traffic_monitor.sh" "$ABOX_DIR/geo_update.sh" "$ABOX_DIR/socket_probe.sh"
    rm -rf /usr/local/etc/xray /usr/local/share/xray /etc/sing-box /etc/hysteria /usr/local/bin/xray /usr/local/bin/sing-box /usr/local/bin/hysteria
    rm -f /etc/systemd/system/xray.service /etc/systemd/system/sing-box.service /etc/systemd/system/hysteria.service /etc/init.d/xray /etc/init.d/sing-box /etc/init.d/hysteria
    rm -f /var/log/A-Box-*.log /etc/fail2ban/jail.d/A-Box.local /etc/fail2ban/filter.d/A-Box.conf /etc/logrotate.d/A-Box 2>/dev/null || true
    [[ "$INIT_SYS" == 'systemd' ]] && systemctl daemon-reload 2>/dev/null || true
    msg "${GREEN}环境初始化完成。${NC}"
    pause_return
}

tune_vps() {
    clear; msg "${CYAN}正在开启底层系统优化 (TCP-BBR & I/O Limit Control)...${NC}"
    cat > /etc/security/limits.d/A-Box.conf <<'EOF_LIMITS'
* soft nofile 1048576
* hard nofile 1048576
* soft nproc 1048576
* hard nproc 1048576
root soft nofile 1048576
root hard nofile 1048576
EOF_LIMITS
    modprobe tcp_bbr 2>/dev/null || true
    cat > /etc/sysctl.d/99-A-Box-tune.conf <<'EOF_SYSCTL'
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
        local xray_bak xray_patch
        xray_bak=$(mktemp /tmp/A-Box-xray-config.XXXXXX) || die 'Xray tune 临时备份创建失败。'
        xray_patch=$(mktemp /tmp/A-Box-xray-patch.XXXXXX) || die 'Xray tune 临时补丁创建失败。'
        cp -f /usr/local/etc/xray/config.json "$xray_bak"
        jq '(.inbounds[] | select(.protocol=="vless") | .streamSettings.sockopt) |= {"tcpKeepAliveIdle":30,"tcpKeepAliveInterval":30}' /usr/local/etc/xray/config.json > "$xray_patch" && mv -f "$xray_patch" /usr/local/etc/xray/config.json
        jq empty /usr/local/etc/xray/config.json >/dev/null 2>&1 || { mv -f "$xray_bak" /usr/local/etc/xray/config.json; rm -f "$xray_patch"; die 'Xray tune 后 JSON 非法，已回滚。'; }
        /usr/local/bin/xray run -test -config /usr/local/etc/xray/config.json >/dev/null 2>&1 || { mv -f "$xray_bak" /usr/local/etc/xray/config.json; rm -f "$xray_patch"; die 'Xray tune 后配置校验失败，已回滚。'; }
        rm -f "$xray_bak" "$xray_patch"
        service_manager start xray
    fi
    if [[ -f /etc/sing-box/config.json ]] && command -v jq >/dev/null 2>&1; then
        local sb_bak sb_patch
        sb_bak=$(mktemp /tmp/A-Box-sb-config.XXXXXX) || die 'Sing-box tune 临时备份创建失败。'
        sb_patch=$(mktemp /tmp/A-Box-sb-patch.XXXXXX) || die 'Sing-box tune 临时补丁创建失败。'
        cp -f /etc/sing-box/config.json "$sb_bak"
        jq '(.inbounds[] | select(.type=="vless" or .type=="shadowsocks")) |= . + {"tcp_keep_alive":"30s","tcp_keep_alive_interval":"30s"}' /etc/sing-box/config.json > "$sb_patch" && mv -f "$sb_patch" /etc/sing-box/config.json
        jq empty /etc/sing-box/config.json >/dev/null 2>&1 || { mv -f "$sb_bak" /etc/sing-box/config.json; rm -f "$sb_patch"; die 'Sing-box tune 后 JSON 非法，已回滚。'; }
        /usr/local/bin/sing-box check -c /etc/sing-box/config.json >/dev/null 2>&1 || { mv -f "$sb_bak" /etc/sing-box/config.json; rm -f "$sb_patch"; die 'Sing-box tune 后配置校验失败，已回滚。'; }
        rm -f "$sb_bak" "$sb_patch"
        service_manager start sing-box
    fi
    setup_health_monitor
    setup_active_defense
    msg "${GREEN}系统优化完成。${NC}"
    pause_return
}


run_remote_bash_script() {
    local label="$1" url="$2" tmp sha
    shift 2 || true
    tmp=$(mktemp /tmp/A-Box-remote.XXXXXX.sh) || die '远程脚本临时文件创建失败。'
    if ! curl -fLsS --connect-timeout 10 -m 120 "$url" -o "$tmp"; then
        rm -f "$tmp"
        die "远程脚本下载失败: $label"
    fi
    chmod 600 "$tmp"
    sha=$(sha256sum "$tmp" | awk '{print $1}')
    msg "${YELLOW}[*] Remote script: ${label}${NC}"
    msg "${YELLOW}[*] Source: ${url}${NC}"
    msg "${YELLOW}[*] SHA256: ${sha}${NC}"
    bash -n "$tmp" || { rm -f "$tmp"; die "远程脚本语法校验失败: $label"; }
    bash "$tmp" "$@"
    local rc=$?
    rm -f "$tmp"
    return "$rc"
}



write_sni_candidate_library() {
    local profile="${1:-full}" out="$2" raw generated tmp remote_tmp max_count variant_count
    [[ -n "$out" ]] || die 'SNI candidate output path missing.'
    raw=$(mktemp /tmp/A-Box-sni-lib.XXXXXX) || die 'SNI library temporary file creation failed.'
    generated=$(mktemp /tmp/A-Box-sni-lib-generated.XXXXXX) || { rm -f "$raw"; die 'SNI generated library temporary file creation failed.'; }
    tmp=$(mktemp /tmp/A-Box-sni-lib-filtered.XXXXXX) || { rm -f "$raw" "$generated"; die 'SNI library filtered temporary file creation failed.'; }

    cat > "$raw" <<'EOF_SNI_CANDIDATES'
www.confluent.io
www.apache.org
learn.microsoft.com
www.cloudflare.com
developers.cloudflare.com
docs.github.com
www.fastly.com
www.akamai.com
www.nginx.com
nginx.org
www.postgresql.org
www.mongodb.com
www.python.org
www.rust-lang.org
go.dev
pkg.go.dev
www.kernel.org
www.debian.org
www.ubuntu.com
www.mozilla.org
developer.mozilla.org
www.ietf.org
www.rfc-editor.org
www.openssl.org
curl.se
www.linuxfoundation.org
www.cncf.io
www.w3.org
www.nist.gov
www.cisa.gov
www.google.com
www.gstatic.com
ssl.gstatic.com
fonts.gstatic.com
fonts.googleapis.com
ajax.googleapis.com
apis.google.com
www.googleapis.com
storage.googleapis.com
storage.cloud.google.com
cloud.google.com
docs.cloud.google.com
console.cloud.google.com
cloud.googleusercontent.com
www.googleusercontent.com
lh3.googleusercontent.com
lh4.googleusercontent.com
lh5.googleusercontent.com
lh6.googleusercontent.com
developers.google.com
firebase.google.com
android.googleapis.com
android.clients.google.com
chromium.googlesource.com
android.googlesource.com
google.github.io
www.microsoft.com
www.bing.com
www.office.com
www.linkedin.com
www.github.com
github.com
raw.githubusercontent.com
www.youtube.com
www.amazon.com
aws.amazon.com
docs.aws.amazon.com
www.oracle.com
www.ibm.com
www.redhat.com
www.docker.com
docs.docker.com
hub.docker.com
www.kubernetes.io
kubernetes.io
helm.sh
prometheus.io
grafana.com
www.elastic.co
www.mysql.com
www.sqlite.org
www.redis.io
redis.io
www.envoyproxy.io
envoyproxy.io
istio.io
www.terraform.io
www.hashicorp.com
www.vaultproject.io
www.consul.io
www.nomadproject.io
www.ansible.com
www.jenkins.io
www.gitlab.com
docs.gitlab.com
about.gitlab.com
www.bitbucket.org
www.atlassian.com
www.jetbrains.com
docs.python.org
pypi.org
www.npmjs.com
nodejs.org
www.typescriptlang.org
crates.io
golang.org
www.java.com
openjdk.org
www.eclipse.org
www.scala-lang.org
kotlinlang.org
swift.org
llvm.org
clang.llvm.org
cmake.org
www.gnu.org
gcc.gnu.org
releases.ubuntu.com
www.fedoraproject.org
getfedora.org
www.centos.org
www.rockylinux.org
almalinux.org
archlinux.org
www.alpinelinux.org
www.freebsd.org
www.openbsd.org
www.netbsd.org
www.chromium.org
www.wireshark.org
www.iana.org
www.icann.org
www.arin.net
www.ripe.net
www.apnic.net
www.lacnic.net
www.afrinic.net
www.cloudflarestatus.com
status.aws.amazon.com
status.cloud.google.com
status.azure.com
www.datadoghq.com
www.newrelic.com
www.splunk.com
www.sentry.io
sentry.io
www.pagerduty.com
www.postman.com
www.insomnia.rest
www.openapis.org
swagger.io
www.json.org
json-schema.org
yaml.org
www.markdownguide.org
www.opencontainers.org
www.openstack.org
www.rancher.com
www.suse.com
www.canonical.com
www.salesforce.com
www.tableau.com
www.snowflake.com
www.databricks.com
www.vercel.com
vercel.com
nextjs.org
www.netlify.com
pages.cloudflare.com
www.heroku.com
www.digitalocean.com
docs.digitalocean.com
www.linode.com
www.vultr.com
www.ovhcloud.com
www.hetzner.com
www.scaleway.com
www.backblaze.com
www.wasabi.com
www.box.com
www.dropbox.com
www.slack.com
api.slack.com
www.zoom.us
support.zoom.us
www.notion.so
www.figma.com
www.canva.com
www.adobe.com
www.spotify.com
www.shopify.com
www.paypal.com
www.stripe.com
stripe.com
docs.stripe.com
www.squareup.com
squareup.com
www.twilio.com
www.sendgrid.com
www.mailgun.com
www.mailchimp.com
www.okta.com
developer.okta.com
www.auth0.com
auth0.com
www.digicert.com
www.letsencrypt.org
letsencrypt.org
www.sectigo.com
www.globalsign.com
www.quovadisglobal.com
www.hardenize.com
www.ssllabs.com
www.openai.com
platform.openai.com
chatgpt.com
www.anthropic.com
www.cohere.com
www.mistral.ai
www.perplexity.ai
huggingface.co
www.kaggle.com
www.tensorflow.org
pytorch.org
onnx.ai
opencv.org
www.r-project.org
posit.co
jupyter.org
www.mathworks.com
www.wolfram.com
www.overleaf.com
www.arxiv.org
arxiv.org
www.nature.com
www.science.org
www.cell.com
www.springer.com
link.springer.com
www.wiley.com
onlinelibrary.wiley.com
www.cambridge.org
www.oxfordlearnersdictionaries.com
www.britannica.com
www.nationalgeographic.com
www.nasa.gov
www.noaa.gov
www.usgs.gov
www.energy.gov
www.cdc.gov
www.nih.gov
www.who.int
www.worldbank.org
www.imf.org
www.oecd.org
www.un.org
www.wto.org
www.iso.org
www.itu.int
www.ieee.org
spectrum.ieee.org
www.acm.org
dl.acm.org
www.usenix.org
www.eff.org
www.torproject.org
www.wikipedia.org
www.wikimedia.org
commons.wikimedia.org
meta.wikimedia.org
www.wikidata.org
www.archive.org
archive.org
www.openstreetmap.org
www.stackoverflow.com
stackoverflow.com
serverfault.com
superuser.com
askubuntu.com
math.stackexchange.com
unix.stackexchange.com
security.stackexchange.com
www.reddit.com
www.quora.com
medium.com
dev.to
www.freecodecamp.org
www.codecademy.com
www.coursera.org
www.edx.org
www.udacity.com
www.khanacademy.org
www.duolingo.com
www.udemy.com
www.pluralsight.com
www.oreilly.com
www.infoq.com
www.dzone.com
www.baeldung.com
www.howtogeek.com
www.tomshardware.com
www.anandtech.com
www.phoronix.com
www.servethehome.com
www.lwn.net
lwn.net
news.ycombinator.com
www.ycombinator.com
www.producthunt.com
www.crunchbase.com
www.forbes.com
www.bloomberg.com
www.reuters.com
www.apnews.com
www.bbc.com
www.cnn.com
www.npr.org
www.ft.com
www.wsj.com
www.nytimes.com
www.theguardian.com
www.economist.com
www.cnbc.com
www.marketwatch.com
www.nasdaq.com
www.spglobal.com
www.morningstar.com
www.investing.com
www.tradingview.com
www.coindesk.com
www.cointelegraph.com
www.kraken.com
www.coinbase.com
www.binance.com
www.okx.com
www.bitstamp.net
www.gemini.com
www.chainalysis.com
www.blockchain.com
etherscan.io
www.blockchair.com
www.githubstatus.com
registry.npmjs.org
rubygems.org
packagist.org
repo.maven.apache.org
search.maven.org
plugins.gradle.org
repo1.maven.org
nuget.org
www.nuget.org
static.rust-lang.org
commondatastorage.googleapis.com
cdn.jsdelivr.net
www.jsdelivr.com
unpkg.com
cdnjs.cloudflare.com
assets-global.website-files.com
www.squarespace.com
www.wix.com
www.webflow.com
www.cloudflareinsights.com
www.google-analytics.com
tagmanager.google.com
www.googletagmanager.com
static.xx.fbcdn.net
www.instagram.com
www.whatsapp.com
web.whatsapp.com
www.snapchat.com
www.pinterest.com
www.tumblr.com
static.licdn.com
trailhead.salesforce.com
www.sap.com
www.servicenow.com
www.workday.com
www.vmware.com
www.broadcom.com
www.intel.com
www.amd.com
www.nvidia.com
developer.nvidia.com
www.arm.com
www.qualcomm.com
www.tsmc.com
www.samsung.com
www.lg.com
www.sony.com
www.panasonic.com
www.lenovo.com
www.dell.com
www.hp.com
www.asus.com
www.acer.com
www.logitech.com
www.corsair.com
www.razer.com
www.lumen.com
www.cisco.com
www.juniper.net
www.arista.com
www.fortinet.com
www.paloaltonetworks.com
www.openssh.com
www.libssh.org
www.wireguard.com
www.strongswan.org
www.openvpn.net
www.tailscale.com
www.zerotier.com
www.netmaker.io
www.ngrok.com
www.cloudflarewarp.com
one.one.one.one
www.quic.cloud
quic.cloud
www.litespeedtech.com
www.openresty.org
openresty.org
www.haproxy.org
www.varnish-software.com
www.varnish-cache.org
www.memcached.org
www.rabbitmq.com
www.kafka.apache.org
kafka.apache.org
pulsar.apache.org
flink.apache.org
spark.apache.org
hadoop.apache.org
beam.apache.org
airflow.apache.org
superset.apache.org
httpd.apache.org
caddyserver.com
www.caddyserver.com
traefik.io
www.traefik.io
linkerd.io
www.linkerd.io
www.openpolicyagent.org
www.sigstore.dev
www.slsa.dev
www.chainguard.dev
www.snyk.io
snyk.io
www.sonarsource.com
sonarcloud.io
www.semgrep.dev
semgrep.dev
www.trivy.dev
trivy.dev
aquasecurity.github.io
www.aquasec.com
www.lacework.com
www.tenable.com
www.qualys.com
www.rapid7.com
www.mandiant.com
www.crowdstrike.com
www.sentinelone.com
www.sophos.com
www.bitdefender.com
www.eset.com
www.malwarebytes.com
www.kaspersky.com
www.trendmicro.com
www.mcafee.com
umbrella.cisco.com
www.cloudflare.tv
www.apple.com
www.icloud.com
www.nike.com
www.adidas.com
www.underarmour.com
www.puma.com
www.reebok.com
www.thenorthface.com
www.patagonia.com
www.uniqlo.com
www.zara.com
www.hm.com
www.ikea.com
www.walmart.com
www.target.com
www.costco.com
www.bestbuy.com
www.homedepot.com
www.lowes.com
www.etsy.com
www.ebay.com
www.twitch.tv
www.netflix.com
www.hulu.com
www.disneyplus.com
www.max.com
www.paramountplus.com
www.peacocktv.com
www.primevideo.com
www.imdb.com
www.rottentomatoes.com
www.metacritic.com
www.soundcloud.com
www.bandcamp.com
www.deezer.com
music.apple.com
youtu.be
www.youtube-nocookie.com
www.vimeo.com
vimeo.com
player.vimeo.com
www.cloudflare-ipfs.com
ipfs.io
www.protocol.ai
protocol.ai
www.internetcomputer.org
www.dfinity.org
www.solana.com
ethereum.org
bitcoin.org
www.linux.org
www.linux.com
www.fsfe.org
www.opensource.org
opensource.org
www.creativecommons.org
creativecommons.org
www.owasp.org
owasp.org
cheatsheetseries.owasp.org
www.first.org
www.mitre.org
cve.mitre.org
attack.mitre.org
www.cve.org
www.cert.org
www.sei.cmu.edu
www.cmu.edu
www.stanford.edu
www.mit.edu
www.harvard.edu
www.berkeley.edu
www.princeton.edu
www.yale.edu
www.ox.ac.uk
www.cam.ac.uk
www.ethz.ch
www.epfl.ch
www.u-tokyo.ac.jp
www.kyoto-u.ac.jp
www.nus.edu.sg
www.ntu.edu.sg
www.hku.hk
www.cuhk.edu.hk
www.cityu.edu.hk
www.polyu.edu.hk
www.unimelb.edu.au
www.sydney.edu.au
www.unsw.edu.au
www.monash.edu
www.auckland.ac.nz
www.otago.ac.nz
www.wgtn.ac.nz
www.rmit.edu.au
www.qut.edu.au
www.uq.edu.au
www.adelaide.edu.au
www.anu.edu.au
www.uwa.edu.au
www.azure.com
azure.microsoft.com
portal.azure.com
docs.microsoft.com
visualstudio.microsoft.com
code.visualstudio.com
marketplace.visualstudio.com
devblogs.microsoft.com
techcommunity.microsoft.com
www.microsoft365.com
www.skype.com
www.xbox.com
www.msn.com
www.live.com
login.live.com
account.microsoft.com
www.onedrive.com
onedrive.live.com
www.outlook.com
outlook.live.com
www.office365.com
www.windows.com
www.surface.com
engineering.linkedin.com
business.linkedin.com
learning.linkedin.com
www.github.blog
github.blog
resources.github.com
education.github.com
skills.github.com
cli.github.com
desktop.github.com
gist.github.com
objects.githubusercontent.com
avatars.githubusercontent.com
user-images.githubusercontent.com
www.git-scm.com
git-scm.com
training.linuxfoundation.org
events.linuxfoundation.org
landscape.cncf.io
k8s.io
www.containerd.io
containerd.io
www.dockerhub.com
dockerhub.com
registry-1.docker.io
www.mobyproject.org
mobyproject.org
www.podman.io
podman.io
buildpacks.io
www.buildpacks.io
www.openshift.com
access.redhat.com
developers.redhat.com
catalog.redhat.com
quay.io
www.quay.io
docs.ansible.com
ubuntu.com
help.ubuntu.com
wiki.ubuntu.com
packages.ubuntu.com
launchpad.net
debian.org
packages.debian.org
wiki.debian.org
security-tracker.debian.org
cdn.kernel.org
git.kernel.org
mirrors.edge.kernel.org
wiki.archlinux.org
aur.archlinux.org
alpinelinux.org
pkgs.alpinelinux.org
www.gentoo.org
gentoo.org
wiki.gentoo.org
docs.freebsd.org
forums.freebsd.org
man.openbsd.org
www.dragonflybsd.org
fedoraproject.org
docs.fedoraproject.org
bodhi.fedoraproject.org
pagure.io
src.fedoraproject.org
centos.org
rockylinux.org
wiki.rockylinux.org
wiki.almalinux.org
suse.com
www.opensuse.org
opensuse.org
build.opensuse.org
canonical.com
multipass.run
microk8s.io
maas.io
juju.is
cloudflare.com
blog.cloudflare.com
radar.cloudflare.com
dash.cloudflare.com
community.cloudflare.com
support.cloudflare.com
workers.cloudflare.com
fastly.com
docs.fastly.com
developer.fastly.com
status.fastly.com
akamai.com
techdocs.akamai.com
linode.com
digitalocean.com
status.digitalocean.com
vultr.com
docs.vultr.com
status.vultr.com
ovhcloud.com
help.ovhcloud.com
hetzner.com
docs.hetzner.com
status.hetzner.com
scaleway.com
backblaze.com
wasabi.com
www.cloudflare.net
www.rackspace.com
rackspace.com
oracle.com
docs.oracle.com
apex.oracle.com
cloud.oracle.com
ibm.com
cloud.ibm.com
developer.ibm.com
console.aws.amazon.com
health.aws.amazon.com
aws.amazon.com.cn
www.amazon.science
dl.google.com
opensource.google
research.google
ai.google
blog.google
workspace.google.com
www.googlecloudcommunity.com
tensorflow.org
keras.io
jax.readthedocs.io
pytorch-lightning.readthedocs.io
cdn-lfs.huggingface.co
datasets-server.huggingface.co
www.modelscope.cn
scikit-learn.org
numpy.org
scipy.org
pandas.pydata.org
matplotlib.org
seaborn.pydata.org
jupyterlab.readthedocs.io
cran.r-project.org
mathworks.com
wolfram.com
overleaf.com
export.arxiv.org
nature.com
science.org
cell.com
cambridge.org
academic.oup.com
nasa.gov
nvlpubs.nist.gov
csrc.nist.gov
archive-it.org
web.archive.org
reddit.com
old.reddit.com
quora.com
towardsdatascience.com
hashnode.com
freecodecamp.org
codecademy.com
coursera.org
edx.org
udacity.com
khanacademy.org
duolingo.com
udemy.com
pluralsight.com
learning.oreilly.com
infoq.com
baeldung.com
crunchbase.com
tradingview.com
chainalysis.com
blockchain.com
www.litecoin.org
polygon.technology
www.polygon.technology
mongodb.com
postgresql.org
mysql.com
sqlite.org
rabbitmq.com
docs.confluent.io
maven.apache.org
eclipse.org
jetbrains.com
plugins.jetbrains.com
python.org
files.pythonhosted.org
npmjs.com
rust-lang.org
static.crates.io
doc.rust-lang.org
proxy.golang.org
sum.golang.org
jdk.java.net
scala-lang.org
openssl.org
wireshark.org
iana.org
icann.org
datadoghq.com
newrelic.com
splunk.com
pagerduty.com
postman.com
insomnia.rest
rancher.com
salesforce.com
tableau.com
snowflake.com
databricks.com
netlify.com
heroku.com
box.com
dropbox.com
slack.com
zoom.us
notion.so
figma.com
canva.com
adobe.com
helpx.adobe.com
spotify.com
shopify.com
paypal.com
developer.paypal.com
status.stripe.com
twilio.com
status.twilio.com
sendgrid.com
mailgun.com
mailchimp.com
okta.com
digicert.com
sectigo.com
globalsign.com
hardenize.com
openai.com
help.openai.com
status.openai.com
anthropic.com
console.anthropic.com
cohere.com
mistral.ai
perplexity.ai
litespeedtech.com
firebaseapp.com
hosting.google.com
maps.google.com
maps.gstatic.com
translate.google.com
admin.google.com
support.google.com
policies.google.com
safety.google
privacy.google
about.google
gemini.google
deepmind.google
labs.google
health.google
quantumai.google
android.com
www.android.com
developer.android.com
source.android.com
security.googleblog.com
chromium.org
chrome.google.com
developer.chrome.com
web.dev
material.io
m3.material.io
fonts.google.com
flutter.dev
www.flutter.dev
docs.flutter.dev
api.flutter.dev
dart.dev
www.dart.dev
api.dart.dev
pub.dev
angular.dev
angular.io
www.angular.io
material.angular.io
blog.angular.dev
www.go.dev
k8s.gcr.io
gcr.io
marketplace.gcr.io
cdn.amazon.com
d1.awsstatic.com
d0.awsstatic.com
d2908q01vomqb2.cloudfront.net
autoscaling.amazonaws.com
cloudfront.amazonaws.com
s3.amazonaws.com
developer.microsoft.com
support.microsoft.com
static2.sharepointonline.com
res.cdn.office.net
edgeservices.bing.com
challenges.cloudflare.com
community.fastly.com
www.fastlystatus.com
developer.akamai.com
blogs.akamai.com
blogs.oracle.com
cloud.digitalocean.com
community.digitalocean.com
docs.linode.com
my.vultr.com
docs.ovh.com
developers.scaleway.com
console.scaleway.com
console.hetzner.cloud
alibabacloud.com
www.alibabacloud.com
help.aliyun.com
docs.alibabacloud.com
cloud.tencent.com
intl.cloud.tencent.com
www.tencentcloud.com
docs.tencentcloud.com
redhat.com
docs.redhat.com
vmware.com
docs.vmware.com
developer.vmware.com
blogs.vmware.com
githubstatus.com
gist.githubusercontent.com
codeload.github.com
github.githubassets.com
pages.github.com
gitlab.com
status.gitlab.com
packages.gitlab.com
bitbucket.org
support.atlassian.com
developer.atlassian.com
community.atlassian.com
packaging.python.org
docs.npmjs.com
jsdelivr.com
data.jsdelivr.com
app.unpkg.com
cdnjs.com
ajax.cloudflare.com
docs.rs
www.llvm.org
releases.llvm.org
kernel.org
docs.kernel.org
linuxfoundation.org
docs.kubernetes.io
blog.kubernetes.io
registry.k8s.io
cncf.io
glossary.cncf.io
grafana.github.io
opentelemetry.io
apache.org
downloads.apache.org
archive.apache.org
projects.apache.org
infra.apache.org
nginx.com
docs.nginx.com
haproxy.org
haproxy.com
www.haproxy.com
docs.haproxy.org
docs.postgresql.org
wiki.postgresql.org
dev.mysql.com
mariadb.org
mariadb.com
docs.mariadb.com
docs.mongodb.com
developer.mongodb.com
developers.mongodb.com
learn.mongodb.com
redis.com
docs.redis.com
elastic.co
docs.elastic.co
artifacts.elastic.co
opensearch.org
docs.opensearch.org
jenkins.io
plugins.jenkins.io
updates.jenkins.io
docker.com
download.docker.com
production.cloudflare.docker.com
buildah.io
hashicorp.com
developer.hashicorp.com
releases.hashicorp.com
registry.terraform.io
cdn.terraform.io
app.terraform.io
terraform.io
ansible.com
galaxy.ansible.com
blog.jetbrains.com
download.jetbrains.com
resources.jetbrains.com
stackoverflow.blog
blog.stackoverflow.com
stackexchange.com
api.stackexchange.com
developer.stackexchange.com
developers.stackexchange.com
mozilla.org
support.mozilla.org
community.mozilla.org
blog.mozilla.org
addons.mozilla.org
w3.org
validator.w3.org
www.w3schools.com
ietf.org
datatracker.ietf.org
rfc-editor.org
publicsuffix.org
community.letsencrypt.org
acme-v02.api.letsencrypt.org
docs.openssl.org
everything.curl.dev
developers.openai.com
community.openai.com
cdn.openai.com
docs.anthropic.com
assets.anthropic.com
www.huggingface.co
download.pytorch.org
tensorflow.google.cn
anaconda.com
www.anaconda.com
docs.anaconda.com
repo.anaconda.com
conda-forge.org
docs.jupyter.org
kaggle.com
static.arxiv.org
ieee.org
standards.ieee.org
computer.org
acm.org
static-content.springer.com
springer.com
sciencedirect.com
www.sciencedirect.com
elsevier.com
www.elsevier.com
mit.edu
news.mit.edu
api.mit.edu
web.mit.edu
ocw.mit.edu
stanford.edu
assets.stanford.edu
cdn.stanford.edu
engineering.stanford.edu
berkeley.edu
news.berkeley.edu
eecs.berkeley.edu
harvard.edu
hbs.edu
www.hbs.edu
princeton.edu
yale.edu
columbia.edu
www.columbia.edu
cmu.edu
cs.cmu.edu
caltech.edu
www.caltech.edu
ethz.ch
epfl.ch
ox.ac.uk
cam.ac.uk
imperial.ac.uk
www.imperial.ac.uk
utoronto.ca
www.utoronto.ca
uwaterloo.ca
www.uwaterloo.ca
nus.edu.sg
ntu.edu.sg
wikipedia.org
wikimedia.org
api.wikimedia.org
doc.wikimedia.org
developer.wikimedia.org
developers.wikimedia.org
upload.wikimedia.org
blog.archive.org
eff.org
torproject.org
confluent.io
developer.confluent.io
assets.confluent.io
cdn.confluent.io
help.okta.com
cdn.okta.com
support.stripe.com
js.stripe.com
adyen.com
www.adyen.com
docs.adyen.com
checkoutshopper-live.adyen.com
www.paypalobjects.com
shopify.dev
cdn.shopify.com
cdn.shopifycdn.net
developer.salesforce.com
help.salesforce.com
a.slack-edge.com
slack-imgs.com
marketplace.zoom.us
st1.zoom.us
developers.notion.com
images.ctfassets.net
help.figma.com
static.figma.com
static.canva.com
assets.vercel.com
docs.netlify.com
answers.netlify.com
devcenter.heroku.com
dashboard.heroku.com
docs.sentry.io
blog.sentry.io
cloudinary.com
res.cloudinary.com
demo.cloudinary.com
contentful.com
www.contentful.com
graphql.contentful.com
sanity.io
www.sanity.io
docs.sanity.io
cdn.sanity.io
algolia.com
www.algolia.com
docs.algolia.com
support.algolia.com
segment.com
cdn.segment.com
docs.snowflake.com
community.snowflake.com
atlassian.com
docs.snyk.io
sonarsource.com
docs.sonarsource.com
docs.newrelic.com
developer.newrelic.com
cloudsmith.com
help.cloudsmith.io
jfrog.com
jcenter.bintray.com
cloudfront.net
d2c8v52ll5s99u.cloudfront.net
akamaihd.net
edgesuite.net
akamai.net
fastly.net
global.ssl.fastly.net
fastly.jsdelivr.net
cloudflare.net
cloudflare-dns.com
jsdelivr.net
gcore.jsdelivr.net
testingcf.jsdelivr.net
esm.sh
cdn.esm.sh
skypack.dev
cdn.skypack.dev
pkg.cloudflare.com
packages.cloud.google.com
packages.microsoft.com
deb.debian.org
security.debian.org
cdn-fastly.deb.debian.org
archive.ubuntu.com
security.ubuntu.com
central.sonatype.com
oss.sonatype.org
registry.yarnpkg.com
auth.docker.io
cdn.quay.io
ghcr.io
pkg-containers.githubusercontent.com
rubygems.global.ssl.fastly.net
conda.anaconda.org
support.apple.com
developer.apple.com
m.media-amazon.com
images-na.ssl-images-amazon.com
developer.adobe.com
media.licdn.com
cfl.dropboxstatic.com
dl.dropboxusercontent.com
community.spotify.com
open.spotify.com
help.netflix.com
assets.nflxext.com
static.nike.com
assets.adidas.com
docs.nvidia.com
developer.arm.com
developer.cisco.com
www.hpe.com
support.hp.com
support.lenovo.com
developer.samsung.com
doc.confluent.io
developers.confluent.io
blog.confluent.io
static.confluent.io
support.confluent.io
help.confluent.io
community.confluent.io
learn.confluent.io
status.confluent.io
download.confluent.io
downloads.confluent.io
packages.confluent.io
registry.confluent.io
api.confluent.io
docs.hashicorp.com
doc.hashicorp.com
developers.hashicorp.com
blog.hashicorp.com
assets.hashicorp.com
cdn.hashicorp.com
static.hashicorp.com
support.hashicorp.com
help.hashicorp.com
community.hashicorp.com
learn.hashicorp.com
status.hashicorp.com
download.hashicorp.com
downloads.hashicorp.com
packages.hashicorp.com
registry.hashicorp.com
api.hashicorp.com
doc.mongodb.com
blog.mongodb.com
assets.mongodb.com
cdn.mongodb.com
static.mongodb.com
support.mongodb.com
help.mongodb.com
community.mongodb.com
status.mongodb.com
download.mongodb.com
downloads.mongodb.com
packages.mongodb.com
registry.mongodb.com
api.mongodb.com
doc.docker.com
developer.docker.com
developers.docker.com
blog.docker.com
assets.docker.com
cdn.docker.com
static.docker.com
support.docker.com
help.docker.com
community.docker.com
learn.docker.com
status.docker.com
downloads.docker.com
packages.docker.com
registry.docker.com
api.docker.com
doc.kubernetes.io
developer.kubernetes.io
developers.kubernetes.io
assets.kubernetes.io
cdn.kubernetes.io
static.kubernetes.io
support.kubernetes.io
help.kubernetes.io
community.kubernetes.io
learn.kubernetes.io
status.kubernetes.io
download.kubernetes.io
downloads.kubernetes.io
packages.kubernetes.io
registry.kubernetes.io
api.kubernetes.io
docs.cloudflare.com
doc.cloudflare.com
developer.cloudflare.com
assets.cloudflare.com
cdn.cloudflare.com
static.cloudflare.com
help.cloudflare.com
learn.cloudflare.com
status.cloudflare.com
download.cloudflare.com
downloads.cloudflare.com
packages.cloudflare.com
registry.cloudflare.com
api.cloudflare.com
doc.fastly.com
developers.fastly.com
blog.fastly.com
assets.fastly.com
cdn.fastly.com
static.fastly.com
support.fastly.com
help.fastly.com
learn.fastly.com
download.fastly.com
downloads.fastly.com
packages.fastly.com
registry.fastly.com
api.fastly.com
docs.openai.com
doc.openai.com
developer.openai.com
blog.openai.com
assets.openai.com
static.openai.com
support.openai.com
learn.openai.com
download.openai.com
downloads.openai.com
packages.openai.com
registry.openai.com
api.openai.com
doc.anthropic.com
developer.anthropic.com
developers.anthropic.com
blog.anthropic.com
cdn.anthropic.com
static.anthropic.com
support.anthropic.com
help.anthropic.com
community.anthropic.com
learn.anthropic.com
status.anthropic.com
download.anthropic.com
downloads.anthropic.com
packages.anthropic.com
registry.anthropic.com
api.anthropic.com
docs.huggingface.co
doc.huggingface.co
developer.huggingface.co
developers.huggingface.co
blog.huggingface.co
assets.huggingface.co
cdn.huggingface.co
static.huggingface.co
support.huggingface.co
help.huggingface.co
community.huggingface.co
learn.huggingface.co
status.huggingface.co
download.huggingface.co
downloads.huggingface.co
packages.huggingface.co
registry.huggingface.co
api.huggingface.co
docs.jetbrains.com
doc.jetbrains.com
developer.jetbrains.com
developers.jetbrains.com
assets.jetbrains.com
cdn.jetbrains.com
static.jetbrains.com
support.jetbrains.com
help.jetbrains.com
community.jetbrains.com
learn.jetbrains.com
status.jetbrains.com
downloads.jetbrains.com
packages.jetbrains.com
registry.jetbrains.com
api.jetbrains.com
doc.elastic.co
developer.elastic.co
developers.elastic.co
blog.elastic.co
assets.elastic.co
cdn.elastic.co
static.elastic.co
support.elastic.co
help.elastic.co
community.elastic.co
learn.elastic.co
status.elastic.co
download.elastic.co
downloads.elastic.co
packages.elastic.co
registry.elastic.co
api.elastic.co
docs.redis.io
doc.redis.io
developer.redis.io
developers.redis.io
blog.redis.io
assets.redis.io
cdn.redis.io
static.redis.io
support.redis.io
help.redis.io
community.redis.io
learn.redis.io
status.redis.io
download.redis.io
downloads.redis.io
packages.redis.io
registry.redis.io
api.redis.io
www.grafana.com
docs.grafana.com
doc.grafana.com
developer.grafana.com
developers.grafana.com
blog.grafana.com
assets.grafana.com
cdn.grafana.com
static.grafana.com
support.grafana.com
help.grafana.com
community.grafana.com
learn.grafana.com
status.grafana.com
download.grafana.com
downloads.grafana.com
packages.grafana.com
registry.grafana.com
api.grafana.com
www.prometheus.io
docs.prometheus.io
doc.prometheus.io
developer.prometheus.io
developers.prometheus.io
blog.prometheus.io
assets.prometheus.io
cdn.prometheus.io
static.prometheus.io
support.prometheus.io
help.prometheus.io
community.prometheus.io
learn.prometheus.io
status.prometheus.io
download.prometheus.io
downloads.prometheus.io
packages.prometheus.io
registry.prometheus.io
api.prometheus.io
doc.postgresql.org
developer.postgresql.org
developers.postgresql.org
blog.postgresql.org
assets.postgresql.org
cdn.postgresql.org
static.postgresql.org
support.postgresql.org
help.postgresql.org
community.postgresql.org
learn.postgresql.org
status.postgresql.org
download.postgresql.org
downloads.postgresql.org
packages.postgresql.org
registry.postgresql.org
api.postgresql.org
doc.python.org
developer.python.org
developers.python.org
blog.python.org
assets.python.org
cdn.python.org
static.python.org
support.python.org
help.python.org
community.python.org
learn.python.org
status.python.org
download.python.org
downloads.python.org
packages.python.org
registry.python.org
api.python.org
www.nodejs.org
docs.nodejs.org
doc.nodejs.org
developer.nodejs.org
developers.nodejs.org
blog.nodejs.org
assets.nodejs.org
cdn.nodejs.org
static.nodejs.org
support.nodejs.org
help.nodejs.org
community.nodejs.org
learn.nodejs.org
status.nodejs.org
download.nodejs.org
downloads.nodejs.org
packages.nodejs.org
registry.nodejs.org
api.nodejs.org
docs.rust-lang.org
developer.rust-lang.org
developers.rust-lang.org
blog.rust-lang.org
assets.rust-lang.org
cdn.rust-lang.org
support.rust-lang.org
help.rust-lang.org
community.rust-lang.org
learn.rust-lang.org
status.rust-lang.org
download.rust-lang.org
downloads.rust-lang.org
packages.rust-lang.org
registry.rust-lang.org
api.rust-lang.org
docs.go.dev
doc.go.dev
developer.go.dev
developers.go.dev
blog.go.dev
assets.go.dev
cdn.go.dev
static.go.dev
support.go.dev
help.go.dev
community.go.dev
learn.go.dev
status.go.dev
download.go.dev
downloads.go.dev
packages.go.dev
registry.go.dev
api.go.dev
docs.mozilla.org
doc.mozilla.org
developers.mozilla.org
assets.mozilla.org
cdn.mozilla.org
static.mozilla.org
help.mozilla.org
learn.mozilla.org
status.mozilla.org
download.mozilla.org
downloads.mozilla.org
packages.mozilla.org
registry.mozilla.org
api.mozilla.org
docs.wikimedia.org
blog.wikimedia.org
assets.wikimedia.org
cdn.wikimedia.org
static.wikimedia.org
support.wikimedia.org
help.wikimedia.org
community.wikimedia.org
learn.wikimedia.org
status.wikimedia.org
download.wikimedia.org
downloads.wikimedia.org
packages.wikimedia.org
registry.wikimedia.org
docs.apache.org
doc.apache.org
developer.apache.org
developers.apache.org
blog.apache.org
assets.apache.org
cdn.apache.org
static.apache.org
support.apache.org
help.apache.org
community.apache.org
learn.apache.org
status.apache.org
download.apache.org
packages.apache.org
registry.apache.org
api.apache.org
docs.stanford.edu
doc.stanford.edu
developer.stanford.edu
developers.stanford.edu
blog.stanford.edu
static.stanford.edu
support.stanford.edu
help.stanford.edu
community.stanford.edu
learn.stanford.edu
status.stanford.edu
download.stanford.edu
downloads.stanford.edu
packages.stanford.edu
registry.stanford.edu
api.stanford.edu
docs.mit.edu
doc.mit.edu
developer.mit.edu
developers.mit.edu
blog.mit.edu
assets.mit.edu
cdn.mit.edu
static.mit.edu
support.mit.edu
help.mit.edu
community.mit.edu
learn.mit.edu
status.mit.edu
download.mit.edu
downloads.mit.edu
packages.mit.edu
registry.mit.edu
doc.stripe.com
developer.stripe.com
developers.stripe.com
blog.stripe.com
assets.stripe.com
cdn.stripe.com
static.stripe.com
help.stripe.com
community.stripe.com
learn.stripe.com
download.stripe.com
downloads.stripe.com
packages.stripe.com
registry.stripe.com
api.stripe.com
docs.okta.com
doc.okta.com
developers.okta.com
blog.okta.com
assets.okta.com
static.okta.com
support.okta.com
community.okta.com
learn.okta.com
status.okta.com
download.okta.com
downloads.okta.com
packages.okta.com
registry.okta.com
api.okta.com
docs.atlassian.com
doc.atlassian.com
developers.atlassian.com
blog.atlassian.com
assets.atlassian.com
cdn.atlassian.com
static.atlassian.com
help.atlassian.com
learn.atlassian.com
status.atlassian.com
download.atlassian.com
downloads.atlassian.com
packages.atlassian.com
registry.atlassian.com
api.atlassian.com
docs.shopify.com
doc.shopify.com
developer.shopify.com
developers.shopify.com
blog.shopify.com
assets.shopify.com
static.shopify.com
support.shopify.com
help.shopify.com
community.shopify.com
learn.shopify.com
status.shopify.com
download.shopify.com
downloads.shopify.com
packages.shopify.com
registry.shopify.com
api.shopify.com
docs.salesforce.com
doc.salesforce.com
developers.salesforce.com
blog.salesforce.com
assets.salesforce.com
cdn.salesforce.com
static.salesforce.com
support.salesforce.com
community.salesforce.com
learn.salesforce.com
status.salesforce.com
download.salesforce.com
downloads.salesforce.com
packages.salesforce.com
registry.salesforce.com
api.salesforce.com
docs.vercel.com
doc.vercel.com
developer.vercel.com
developers.vercel.com
blog.vercel.com
cdn.vercel.com
static.vercel.com
support.vercel.com
help.vercel.com
community.vercel.com
learn.vercel.com
status.vercel.com
download.vercel.com
downloads.vercel.com
packages.vercel.com
registry.vercel.com
api.vercel.com
doc.netlify.com
developer.netlify.com
developers.netlify.com
blog.netlify.com
assets.netlify.com
cdn.netlify.com
static.netlify.com
support.netlify.com
help.netlify.com
community.netlify.com
learn.netlify.com
status.netlify.com
download.netlify.com
downloads.netlify.com
packages.netlify.com
registry.netlify.com
api.netlify.com
doc.digitalocean.com
developer.digitalocean.com
developers.digitalocean.com
blog.digitalocean.com
assets.digitalocean.com
cdn.digitalocean.com
static.digitalocean.com
support.digitalocean.com
help.digitalocean.com
learn.digitalocean.com
download.digitalocean.com
downloads.digitalocean.com
packages.digitalocean.com
registry.digitalocean.com
api.digitalocean.com
docs.scaleway.com
doc.scaleway.com
developer.scaleway.com
blog.scaleway.com
assets.scaleway.com
cdn.scaleway.com
static.scaleway.com
support.scaleway.com
help.scaleway.com
community.scaleway.com
learn.scaleway.com
status.scaleway.com
download.scaleway.com
downloads.scaleway.com
packages.scaleway.com
registry.scaleway.com
api.scaleway.com
doc.vultr.com
developer.vultr.com
developers.vultr.com
blog.vultr.com
assets.vultr.com
cdn.vultr.com
static.vultr.com
support.vultr.com
help.vultr.com
community.vultr.com
learn.vultr.com
download.vultr.com
downloads.vultr.com
packages.vultr.com
registry.vultr.com
api.vultr.com
doc.hetzner.com
developer.hetzner.com
developers.hetzner.com
blog.hetzner.com
assets.hetzner.com
cdn.hetzner.com
static.hetzner.com
support.hetzner.com
help.hetzner.com
community.hetzner.com
learn.hetzner.com
download.hetzner.com
downloads.hetzner.com
packages.hetzner.com
registry.hetzner.com
api.hetzner.com
doc.oracle.com
developer.oracle.com
developers.oracle.com
blog.oracle.com
assets.oracle.com
cdn.oracle.com
static.oracle.com
support.oracle.com
help.oracle.com
community.oracle.com
learn.oracle.com
status.oracle.com
download.oracle.com
downloads.oracle.com
packages.oracle.com
registry.oracle.com
api.oracle.com
docs.ibm.com
doc.ibm.com
developers.ibm.com
blog.ibm.com
assets.ibm.com
cdn.ibm.com
static.ibm.com
support.ibm.com
help.ibm.com
community.ibm.com
learn.ibm.com
status.ibm.com
download.ibm.com
downloads.ibm.com
packages.ibm.com
registry.ibm.com
api.ibm.com
doc.redhat.com
developer.redhat.com
blog.redhat.com
assets.redhat.com
cdn.redhat.com
static.redhat.com
support.redhat.com
help.redhat.com
community.redhat.com
learn.redhat.com
status.redhat.com
download.redhat.com
downloads.redhat.com
packages.redhat.com
registry.redhat.com
api.redhat.com
doc.vmware.com
developers.vmware.com
blog.vmware.com
assets.vmware.com
cdn.vmware.com
static.vmware.com
support.vmware.com
help.vmware.com
community.vmware.com
learn.vmware.com
status.vmware.com
download.vmware.com
downloads.vmware.com
packages.vmware.com
registry.vmware.com
api.vmware.com
docs.google.com
doc.google.com
developer.google.com
blog.google.com
assets.google.com
cdn.google.com
static.google.com
help.google.com
community.google.com
learn.google.com
status.google.com
download.google.com
downloads.google.com
packages.google.com
registry.google.com
api.google.com
docs.gstatic.com
doc.gstatic.com
developer.gstatic.com
developers.gstatic.com
blog.gstatic.com
assets.gstatic.com
cdn.gstatic.com
static.gstatic.com
support.gstatic.com
help.gstatic.com
community.gstatic.com
learn.gstatic.com
status.gstatic.com
download.gstatic.com
downloads.gstatic.com
packages.gstatic.com
registry.gstatic.com
api.gstatic.com
docs.googleapis.com
doc.googleapis.com
developer.googleapis.com
developers.googleapis.com
blog.googleapis.com
assets.googleapis.com
cdn.googleapis.com
static.googleapis.com
support.googleapis.com
help.googleapis.com
community.googleapis.com
learn.googleapis.com
status.googleapis.com
download.googleapis.com
downloads.googleapis.com
packages.googleapis.com
registry.googleapis.com
api.googleapis.com
docs.googleusercontent.com
doc.googleusercontent.com
developer.googleusercontent.com
developers.googleusercontent.com
blog.googleusercontent.com
assets.googleusercontent.com
cdn.googleusercontent.com
static.googleusercontent.com
support.googleusercontent.com
help.googleusercontent.com
community.googleusercontent.com
learn.googleusercontent.com
status.googleusercontent.com
download.googleusercontent.com
downloads.googleusercontent.com
packages.googleusercontent.com
registry.googleusercontent.com
api.googleusercontent.com
docs.android.com
doc.android.com
developers.android.com
blog.android.com
assets.android.com
cdn.android.com
static.android.com
support.android.com
help.android.com
community.android.com
learn.android.com
status.android.com
download.android.com
downloads.android.com
packages.android.com
registry.android.com
api.android.com
doc.flutter.dev
developer.flutter.dev
developers.flutter.dev
blog.flutter.dev
assets.flutter.dev
cdn.flutter.dev
static.flutter.dev
support.flutter.dev
help.flutter.dev
community.flutter.dev
learn.flutter.dev
status.flutter.dev
download.flutter.dev
downloads.flutter.dev
packages.flutter.dev
registry.flutter.dev
docs.dart.dev
doc.dart.dev
developer.dart.dev
developers.dart.dev
blog.dart.dev
assets.dart.dev
cdn.dart.dev
static.dart.dev
support.dart.dev
help.dart.dev
community.dart.dev
learn.dart.dev
status.dart.dev
download.dart.dev
downloads.dart.dev
packages.dart.dev
registry.dart.dev
www.angular.dev
docs.angular.dev
doc.angular.dev
developer.angular.dev
developers.angular.dev
assets.angular.dev
cdn.angular.dev
static.angular.dev
support.angular.dev
help.angular.dev
community.angular.dev
learn.angular.dev
status.angular.dev
download.angular.dev
downloads.angular.dev
packages.angular.dev
registry.angular.dev
api.angular.dev
www.firebase.google.com
docs.firebase.google.com
doc.firebase.google.com
developer.firebase.google.com
developers.firebase.google.com
blog.firebase.google.com
assets.firebase.google.com
cdn.firebase.google.com
static.firebase.google.com
support.firebase.google.com
help.firebase.google.com
community.firebase.google.com
learn.firebase.google.com
status.firebase.google.com
download.firebase.google.com
downloads.firebase.google.com
packages.firebase.google.com
registry.firebase.google.com
api.firebase.google.com
doc.github.com
developer.github.com
developers.github.com
blog.github.com
assets.github.com
cdn.github.com
static.github.com
support.github.com
help.github.com
community.github.com
learn.github.com
status.github.com
download.github.com
downloads.github.com
packages.github.com
registry.github.com
api.github.com
doc.gitlab.com
developer.gitlab.com
developers.gitlab.com
blog.gitlab.com
assets.gitlab.com
cdn.gitlab.com
static.gitlab.com
support.gitlab.com
help.gitlab.com
community.gitlab.com
learn.gitlab.com
download.gitlab.com
downloads.gitlab.com
registry.gitlab.com
api.gitlab.com
docs.stackoverflow.com
doc.stackoverflow.com
developer.stackoverflow.com
developers.stackoverflow.com
assets.stackoverflow.com
cdn.stackoverflow.com
static.stackoverflow.com
support.stackoverflow.com
help.stackoverflow.com
community.stackoverflow.com
learn.stackoverflow.com
status.stackoverflow.com
download.stackoverflow.com
downloads.stackoverflow.com
packages.stackoverflow.com
registry.stackoverflow.com
api.stackoverflow.com
www.stackexchange.com
docs.stackexchange.com
doc.stackexchange.com
blog.stackexchange.com
assets.stackexchange.com
cdn.stackexchange.com
static.stackexchange.com
support.stackexchange.com
help.stackexchange.com
community.stackexchange.com
learn.stackexchange.com
status.stackexchange.com
download.stackexchange.com
downloads.stackexchange.com
packages.stackexchange.com
registry.stackexchange.com
docs.terraform.io
doc.terraform.io
developer.terraform.io
developers.terraform.io
blog.terraform.io
assets.terraform.io
static.terraform.io
support.terraform.io
help.terraform.io
community.terraform.io
learn.terraform.io
status.terraform.io
download.terraform.io
downloads.terraform.io
packages.terraform.io
api.terraform.io
doc.sentry.io
developer.sentry.io
developers.sentry.io
assets.sentry.io
cdn.sentry.io
static.sentry.io
support.sentry.io
help.sentry.io
community.sentry.io
learn.sentry.io
status.sentry.io
download.sentry.io
downloads.sentry.io
packages.sentry.io
registry.sentry.io
api.sentry.io
doc.snowflake.com
developer.snowflake.com
developers.snowflake.com
blog.snowflake.com
assets.snowflake.com
cdn.snowflake.com
static.snowflake.com
support.snowflake.com
help.snowflake.com
learn.snowflake.com
status.snowflake.com
download.snowflake.com
downloads.snowflake.com
packages.snowflake.com
registry.snowflake.com
api.snowflake.com
docs.contentful.com
doc.contentful.com
developer.contentful.com
developers.contentful.com
blog.contentful.com
assets.contentful.com
cdn.contentful.com
static.contentful.com
support.contentful.com
help.contentful.com
community.contentful.com
learn.contentful.com
status.contentful.com
download.contentful.com
downloads.contentful.com
packages.contentful.com
registry.contentful.com
api.contentful.com
www.cloudinary.com
docs.cloudinary.com
doc.cloudinary.com
developer.cloudinary.com
developers.cloudinary.com
blog.cloudinary.com
assets.cloudinary.com
cdn.cloudinary.com
static.cloudinary.com
support.cloudinary.com
help.cloudinary.com
community.cloudinary.com
learn.cloudinary.com
status.cloudinary.com
download.cloudinary.com
downloads.cloudinary.com
packages.cloudinary.com
registry.cloudinary.com
api.cloudinary.com
doc.sanity.io
developer.sanity.io
developers.sanity.io
blog.sanity.io
assets.sanity.io
static.sanity.io
support.sanity.io
help.sanity.io
community.sanity.io
learn.sanity.io
status.sanity.io
download.sanity.io
downloads.sanity.io
packages.sanity.io
registry.sanity.io
api.sanity.io
doc.algolia.com
developer.algolia.com
developers.algolia.com
blog.algolia.com
assets.algolia.com
cdn.algolia.com
static.algolia.com
help.algolia.com
community.algolia.com
learn.algolia.com
status.algolia.com
download.algolia.com
downloads.algolia.com
packages.algolia.com
registry.algolia.com
api.algolia.com
doc.newrelic.com
developers.newrelic.com
blog.newrelic.com
assets.newrelic.com
cdn.newrelic.com
static.newrelic.com
support.newrelic.com
help.newrelic.com
community.newrelic.com
learn.newrelic.com
status.newrelic.com
download.newrelic.com
downloads.newrelic.com
packages.newrelic.com
registry.newrelic.com
api.newrelic.com
doc.sonarsource.com
developer.sonarsource.com
developers.sonarsource.com
blog.sonarsource.com
assets.sonarsource.com
cdn.sonarsource.com
static.sonarsource.com
support.sonarsource.com
help.sonarsource.com
community.sonarsource.com
learn.sonarsource.com
status.sonarsource.com
download.sonarsource.com
downloads.sonarsource.com
packages.sonarsource.com
registry.sonarsource.com
api.sonarsource.com
doc.snyk.io
developer.snyk.io
developers.snyk.io
blog.snyk.io
assets.snyk.io
cdn.snyk.io
static.snyk.io
support.snyk.io
help.snyk.io
community.snyk.io
learn.snyk.io
status.snyk.io
download.snyk.io
downloads.snyk.io
packages.snyk.io
registry.snyk.io
api.snyk.io
readthedocs.org
readthedocs.io
docs.readthedocs.io
media.readthedocs.org
sphinx-doc.org
www.sphinx-doc.org
mkdocs.org
www.mkdocs.org
vuejs.org
vitejs.dev
rollupjs.org
webpack.js.org
babeljs.io
react.dev
remix.run
docs.astro.build
astro.build
svelte.dev
docs.svelte.dev
nuxt.com
tailwindcss.com
getbootstrap.com
jquery.com
api.jquery.com
lodash.com
momentjs.com
date-fns.org
nghttp2.org
quicwg.org
httpwg.org
opencollective.com
static.opencollective.com
licensebuttons.net
firebasestorage.googleapis.com
fcm.googleapis.com
googleapis.com
googleusercontent.com
play-lh.googleusercontent.com
s3.eu-west-1.amazonaws.com
s3.us-east-1.amazonaws.com
s3.us-west-2.amazonaws.com
adservice.google.com
cache.pack.google.com
chromewebstore.google.com
clients1.google.com
clients2.google.com
clients3.google.com
clients4.google.com
clients5.google.com
clients6.google.com
google.com
play.google.com
www.google.ca
www.google.ch
www.google.co.in
www.google.co.jp
www.google.co.kr
www.google.co.nz
www.google.co.uk
www.google.com.au
www.google.com.br
www.google.com.hk
www.google.com.mx
www.google.com.sg
www.google.com.tw
www.google.de
www.google.es
www.google.fr
www.google.ie
www.google.it
www.google.nl
www.google.se
gstatic.com
edgedl.me.gvt1.com
redirector.gvt1.com
api-inference.huggingface.co
asia.gcr.io
chainguard.dev
cisa.gov
cve.org
eu.gcr.io
first.org
freebsd.org
memcached.org
mitre.org
nist.gov
openbsd.org
openpolicyagent.org
sigstore.dev
slsa.dev
us.gcr.io
www.swift.org
repo.confluent.io
pkg.confluent.io
files.confluent.io
raw.confluent.io
resources.confluent.io
training.confluent.io
security.confluent.io
repo.apache.org
pkg.apache.org
files.apache.org
raw.apache.org
resources.apache.org
training.apache.org
security.apache.org
microsoft.com
doc.microsoft.com
developers.microsoft.com
api.microsoft.com
status.microsoft.com
blog.microsoft.com
cdn.microsoft.com
static.microsoft.com
assets.microsoft.com
download.microsoft.com
downloads.microsoft.com
registry.microsoft.com
repo.microsoft.com
pkg.microsoft.com
files.microsoft.com
raw.microsoft.com
resources.microsoft.com
community.microsoft.com
help.microsoft.com
training.microsoft.com
security.microsoft.com
repo.github.com
pkg.github.com
files.github.com
raw.github.com
training.github.com
security.github.com
repo.cloudflare.com
files.cloudflare.com
raw.cloudflare.com
resources.cloudflare.com
training.cloudflare.com
security.cloudflare.com
repo.fastly.com
pkg.fastly.com
files.fastly.com
raw.fastly.com
resources.fastly.com
training.fastly.com
security.fastly.com
docs.akamai.com
doc.akamai.com
developers.akamai.com
api.akamai.com
status.akamai.com
support.akamai.com
blog.akamai.com
cdn.akamai.com
static.akamai.com
assets.akamai.com
download.akamai.com
downloads.akamai.com
registry.akamai.com
repo.akamai.com
packages.akamai.com
pkg.akamai.com
files.akamai.com
raw.akamai.com
resources.akamai.com
community.akamai.com
help.akamai.com
learn.akamai.com
training.akamai.com
security.akamai.com
repo.google.com
pkg.google.com
files.google.com
raw.google.com
resources.google.com
training.google.com
security.google.com
repo.oracle.com
pkg.oracle.com
files.oracle.com
raw.oracle.com
resources.oracle.com
training.oracle.com
security.oracle.com
repo.ibm.com
pkg.ibm.com
files.ibm.com
raw.ibm.com
resources.ibm.com
training.ibm.com
security.ibm.com
repo.redhat.com
pkg.redhat.com
files.redhat.com
raw.redhat.com
resources.redhat.com
training.redhat.com
security.redhat.com
repo.docker.com
pkg.docker.com
files.docker.com
raw.docker.com
resources.docker.com
training.docker.com
security.docker.com
repo.kubernetes.io
pkg.kubernetes.io
files.kubernetes.io
raw.kubernetes.io
resources.kubernetes.io
training.kubernetes.io
security.kubernetes.io
repo.elastic.co
pkg.elastic.co
files.elastic.co
raw.elastic.co
resources.elastic.co
training.elastic.co
security.elastic.co
repo.mongodb.com
pkg.mongodb.com
files.mongodb.com
raw.mongodb.com
resources.mongodb.com
training.mongodb.com
security.mongodb.com
repo.postgresql.org
pkg.postgresql.org
files.postgresql.org
raw.postgresql.org
resources.postgresql.org
training.postgresql.org
security.postgresql.org
docs.mysql.com
doc.mysql.com
developer.mysql.com
developers.mysql.com
api.mysql.com
status.mysql.com
support.mysql.com
blog.mysql.com
cdn.mysql.com
static.mysql.com
assets.mysql.com
download.mysql.com
downloads.mysql.com
registry.mysql.com
repo.mysql.com
packages.mysql.com
pkg.mysql.com
files.mysql.com
raw.mysql.com
resources.mysql.com
community.mysql.com
help.mysql.com
learn.mysql.com
training.mysql.com
security.mysql.com
docs.sqlite.org
doc.sqlite.org
developer.sqlite.org
developers.sqlite.org
api.sqlite.org
status.sqlite.org
support.sqlite.org
blog.sqlite.org
cdn.sqlite.org
static.sqlite.org
assets.sqlite.org
download.sqlite.org
downloads.sqlite.org
registry.sqlite.org
repo.sqlite.org
packages.sqlite.org
pkg.sqlite.org
files.sqlite.org
raw.sqlite.org
resources.sqlite.org
community.sqlite.org
help.sqlite.org
learn.sqlite.org
training.sqlite.org
security.sqlite.org
repo.redis.io
pkg.redis.io
files.redis.io
raw.redis.io
resources.redis.io
training.redis.io
security.redis.io
doc.nginx.com
developer.nginx.com
developers.nginx.com
api.nginx.com
status.nginx.com
support.nginx.com
blog.nginx.com
cdn.nginx.com
static.nginx.com
assets.nginx.com
download.nginx.com
downloads.nginx.com
registry.nginx.com
repo.nginx.com
packages.nginx.com
pkg.nginx.com
files.nginx.com
raw.nginx.com
resources.nginx.com
community.nginx.com
help.nginx.com
learn.nginx.com
training.nginx.com
security.nginx.com
www.nginx.org
docs.nginx.org
doc.nginx.org
developer.nginx.org
developers.nginx.org
api.nginx.org
status.nginx.org
support.nginx.org
blog.nginx.org
cdn.nginx.org
static.nginx.org
assets.nginx.org
download.nginx.org
downloads.nginx.org
registry.nginx.org
repo.nginx.org
packages.nginx.org
pkg.nginx.org
files.nginx.org
raw.nginx.org
resources.nginx.org
community.nginx.org
help.nginx.org
learn.nginx.org
training.nginx.org
security.nginx.org
repo.terraform.io
pkg.terraform.io
files.terraform.io
raw.terraform.io
resources.terraform.io
training.terraform.io
security.terraform.io
repo.hashicorp.com
pkg.hashicorp.com
files.hashicorp.com
raw.hashicorp.com
resources.hashicorp.com
training.hashicorp.com
security.hashicorp.com
repo.jetbrains.com
pkg.jetbrains.com
files.jetbrains.com
raw.jetbrains.com
training.jetbrains.com
security.jetbrains.com
repo.python.org
pkg.python.org
files.python.org
raw.python.org
resources.python.org
training.python.org
security.python.org
doc.npmjs.com
developer.npmjs.com
developers.npmjs.com
api.npmjs.com
status.npmjs.com
support.npmjs.com
blog.npmjs.com
cdn.npmjs.com
static.npmjs.com
assets.npmjs.com
download.npmjs.com
downloads.npmjs.com
registry.npmjs.com
repo.npmjs.com
packages.npmjs.com
pkg.npmjs.com
files.npmjs.com
raw.npmjs.com
resources.npmjs.com
community.npmjs.com
help.npmjs.com
learn.npmjs.com
training.npmjs.com
security.npmjs.com
repo.nodejs.org
pkg.nodejs.org
files.nodejs.org
raw.nodejs.org
resources.nodejs.org
training.nodejs.org
security.nodejs.org
typescriptlang.org
docs.typescriptlang.org
doc.typescriptlang.org
developer.typescriptlang.org
developers.typescriptlang.org
api.typescriptlang.org
status.typescriptlang.org
support.typescriptlang.org
blog.typescriptlang.org
cdn.typescriptlang.org
static.typescriptlang.org
assets.typescriptlang.org
download.typescriptlang.org
downloads.typescriptlang.org
registry.typescriptlang.org
repo.typescriptlang.org
packages.typescriptlang.org
pkg.typescriptlang.org
files.typescriptlang.org
raw.typescriptlang.org
resources.typescriptlang.org
community.typescriptlang.org
help.typescriptlang.org
learn.typescriptlang.org
training.typescriptlang.org
security.typescriptlang.org
repo.rust-lang.org
pkg.rust-lang.org
files.rust-lang.org
raw.rust-lang.org
resources.rust-lang.org
training.rust-lang.org
security.rust-lang.org
www.golang.org
docs.golang.org
doc.golang.org
developer.golang.org
developers.golang.org
api.golang.org
status.golang.org
support.golang.org
blog.golang.org
cdn.golang.org
static.golang.org
assets.golang.org
download.golang.org
downloads.golang.org
registry.golang.org
repo.golang.org
packages.golang.org
pkg.golang.org
files.golang.org
raw.golang.org
resources.golang.org
community.golang.org
help.golang.org
learn.golang.org
training.golang.org
security.golang.org
repo.go.dev
files.go.dev
raw.go.dev
resources.go.dev
training.go.dev
security.go.dev
docs.eclipse.org
doc.eclipse.org
developer.eclipse.org
developers.eclipse.org
api.eclipse.org
status.eclipse.org
support.eclipse.org
blog.eclipse.org
cdn.eclipse.org
static.eclipse.org
assets.eclipse.org
download.eclipse.org
downloads.eclipse.org
registry.eclipse.org
repo.eclipse.org
packages.eclipse.org
pkg.eclipse.org
files.eclipse.org
raw.eclipse.org
resources.eclipse.org
community.eclipse.org
help.eclipse.org
learn.eclipse.org
training.eclipse.org
security.eclipse.org
gnu.org
docs.gnu.org
doc.gnu.org
developer.gnu.org
developers.gnu.org
api.gnu.org
status.gnu.org
support.gnu.org
blog.gnu.org
cdn.gnu.org
static.gnu.org
assets.gnu.org
download.gnu.org
downloads.gnu.org
registry.gnu.org
repo.gnu.org
packages.gnu.org
pkg.gnu.org
files.gnu.org
raw.gnu.org
resources.gnu.org
community.gnu.org
help.gnu.org
learn.gnu.org
training.gnu.org
security.gnu.org
doc.kernel.org
developer.kernel.org
developers.kernel.org
api.kernel.org
status.kernel.org
support.kernel.org
blog.kernel.org
static.kernel.org
assets.kernel.org
download.kernel.org
downloads.kernel.org
registry.kernel.org
repo.kernel.org
packages.kernel.org
pkg.kernel.org
files.kernel.org
raw.kernel.org
resources.kernel.org
community.kernel.org
help.kernel.org
learn.kernel.org
training.kernel.org
security.kernel.org
docs.debian.org
doc.debian.org
developer.debian.org
developers.debian.org
api.debian.org
status.debian.org
support.debian.org
blog.debian.org
cdn.debian.org
static.debian.org
assets.debian.org
download.debian.org
downloads.debian.org
registry.debian.org
repo.debian.org
pkg.debian.org
files.debian.org
raw.debian.org
resources.debian.org
community.debian.org
help.debian.org
learn.debian.org
training.debian.org
docs.ubuntu.com
doc.ubuntu.com
developer.ubuntu.com
developers.ubuntu.com
api.ubuntu.com
status.ubuntu.com
support.ubuntu.com
blog.ubuntu.com
cdn.ubuntu.com
static.ubuntu.com
assets.ubuntu.com
download.ubuntu.com
downloads.ubuntu.com
registry.ubuntu.com
repo.ubuntu.com
pkg.ubuntu.com
files.ubuntu.com
raw.ubuntu.com
resources.ubuntu.com
community.ubuntu.com
learn.ubuntu.com
training.ubuntu.com
doc.freebsd.org
developer.freebsd.org
developers.freebsd.org
api.freebsd.org
status.freebsd.org
support.freebsd.org
blog.freebsd.org
cdn.freebsd.org
static.freebsd.org
assets.freebsd.org
download.freebsd.org
downloads.freebsd.org
registry.freebsd.org
repo.freebsd.org
packages.freebsd.org
pkg.freebsd.org
files.freebsd.org
raw.freebsd.org
resources.freebsd.org
community.freebsd.org
help.freebsd.org
learn.freebsd.org
training.freebsd.org
security.freebsd.org
docs.openbsd.org
doc.openbsd.org
developer.openbsd.org
developers.openbsd.org
api.openbsd.org
status.openbsd.org
support.openbsd.org
blog.openbsd.org
cdn.openbsd.org
static.openbsd.org
assets.openbsd.org
download.openbsd.org
downloads.openbsd.org
registry.openbsd.org
repo.openbsd.org
packages.openbsd.org
pkg.openbsd.org
files.openbsd.org
raw.openbsd.org
resources.openbsd.org
community.openbsd.org
help.openbsd.org
learn.openbsd.org
training.openbsd.org
security.openbsd.org
netbsd.org
docs.netbsd.org
doc.netbsd.org
developer.netbsd.org
developers.netbsd.org
api.netbsd.org
status.netbsd.org
support.netbsd.org
blog.netbsd.org
cdn.netbsd.org
static.netbsd.org
assets.netbsd.org
download.netbsd.org
downloads.netbsd.org
registry.netbsd.org
repo.netbsd.org
packages.netbsd.org
pkg.netbsd.org
files.netbsd.org
raw.netbsd.org
resources.netbsd.org
community.netbsd.org
help.netbsd.org
learn.netbsd.org
training.netbsd.org
security.netbsd.org
repo.mozilla.org
pkg.mozilla.org
files.mozilla.org
raw.mozilla.org
resources.mozilla.org
training.mozilla.org
security.mozilla.org
docs.w3.org
doc.w3.org
developer.w3.org
developers.w3.org
api.w3.org
status.w3.org
support.w3.org
blog.w3.org
cdn.w3.org
static.w3.org
assets.w3.org
download.w3.org
downloads.w3.org
registry.w3.org
repo.w3.org
packages.w3.org
pkg.w3.org
files.w3.org
raw.w3.org
resources.w3.org
community.w3.org
help.w3.org
learn.w3.org
training.w3.org
security.w3.org
docs.ietf.org
doc.ietf.org
developer.ietf.org
developers.ietf.org
api.ietf.org
status.ietf.org
support.ietf.org
blog.ietf.org
cdn.ietf.org
static.ietf.org
assets.ietf.org
download.ietf.org
downloads.ietf.org
registry.ietf.org
repo.ietf.org
packages.ietf.org
pkg.ietf.org
files.ietf.org
raw.ietf.org
resources.ietf.org
community.ietf.org
help.ietf.org
learn.ietf.org
training.ietf.org
security.ietf.org
docs.rfc-editor.org
doc.rfc-editor.org
developer.rfc-editor.org
developers.rfc-editor.org
api.rfc-editor.org
status.rfc-editor.org
support.rfc-editor.org
blog.rfc-editor.org
cdn.rfc-editor.org
static.rfc-editor.org
assets.rfc-editor.org
download.rfc-editor.org
downloads.rfc-editor.org
registry.rfc-editor.org
repo.rfc-editor.org
packages.rfc-editor.org
pkg.rfc-editor.org
files.rfc-editor.org
raw.rfc-editor.org
resources.rfc-editor.org
community.rfc-editor.org
help.rfc-editor.org
learn.rfc-editor.org
training.rfc-editor.org
security.rfc-editor.org
doc.openssl.org
developer.openssl.org
developers.openssl.org
api.openssl.org
status.openssl.org
support.openssl.org
blog.openssl.org
cdn.openssl.org
static.openssl.org
assets.openssl.org
download.openssl.org
downloads.openssl.org
registry.openssl.org
repo.openssl.org
packages.openssl.org
pkg.openssl.org
files.openssl.org
raw.openssl.org
resources.openssl.org
community.openssl.org
help.openssl.org
learn.openssl.org
training.openssl.org
security.openssl.org
www.curl.se
docs.curl.se
doc.curl.se
developer.curl.se
developers.curl.se
api.curl.se
status.curl.se
support.curl.se
blog.curl.se
cdn.curl.se
static.curl.se
assets.curl.se
download.curl.se
downloads.curl.se
registry.curl.se
repo.curl.se
packages.curl.se
pkg.curl.se
files.curl.se
raw.curl.se
resources.curl.se
community.curl.se
help.curl.se
learn.curl.se
training.curl.se
security.curl.se
docs.linuxfoundation.org
doc.linuxfoundation.org
developer.linuxfoundation.org
developers.linuxfoundation.org
api.linuxfoundation.org
status.linuxfoundation.org
support.linuxfoundation.org
blog.linuxfoundation.org
cdn.linuxfoundation.org
static.linuxfoundation.org
assets.linuxfoundation.org
download.linuxfoundation.org
downloads.linuxfoundation.org
registry.linuxfoundation.org
repo.linuxfoundation.org
packages.linuxfoundation.org
pkg.linuxfoundation.org
files.linuxfoundation.org
raw.linuxfoundation.org
resources.linuxfoundation.org
community.linuxfoundation.org
help.linuxfoundation.org
learn.linuxfoundation.org
security.linuxfoundation.org
docs.cncf.io
doc.cncf.io
developer.cncf.io
developers.cncf.io
api.cncf.io
status.cncf.io
support.cncf.io
blog.cncf.io
cdn.cncf.io
static.cncf.io
assets.cncf.io
download.cncf.io
downloads.cncf.io
registry.cncf.io
repo.cncf.io
packages.cncf.io
pkg.cncf.io
files.cncf.io
raw.cncf.io
resources.cncf.io
community.cncf.io
help.cncf.io
learn.cncf.io
training.cncf.io
security.cncf.io
repo.digitalocean.com
pkg.digitalocean.com
files.digitalocean.com
raw.digitalocean.com
resources.digitalocean.com
training.digitalocean.com
security.digitalocean.com
doc.linode.com
developer.linode.com
developers.linode.com
api.linode.com
status.linode.com
support.linode.com
blog.linode.com
cdn.linode.com
static.linode.com
assets.linode.com
download.linode.com
downloads.linode.com
registry.linode.com
repo.linode.com
packages.linode.com
pkg.linode.com
files.linode.com
raw.linode.com
resources.linode.com
community.linode.com
help.linode.com
learn.linode.com
training.linode.com
security.linode.com
repo.vultr.com
pkg.vultr.com
files.vultr.com
raw.vultr.com
resources.vultr.com
training.vultr.com
security.vultr.com
docs.ovhcloud.com
doc.ovhcloud.com
developer.ovhcloud.com
developers.ovhcloud.com
api.ovhcloud.com
status.ovhcloud.com
support.ovhcloud.com
blog.ovhcloud.com
cdn.ovhcloud.com
static.ovhcloud.com
assets.ovhcloud.com
download.ovhcloud.com
downloads.ovhcloud.com
registry.ovhcloud.com
repo.ovhcloud.com
packages.ovhcloud.com
pkg.ovhcloud.com
files.ovhcloud.com
raw.ovhcloud.com
resources.ovhcloud.com
community.ovhcloud.com
learn.ovhcloud.com
training.ovhcloud.com
security.ovhcloud.com
repo.hetzner.com
pkg.hetzner.com
files.hetzner.com
raw.hetzner.com
resources.hetzner.com
training.hetzner.com
security.hetzner.com
repo.scaleway.com
pkg.scaleway.com
files.scaleway.com
raw.scaleway.com
resources.scaleway.com
training.scaleway.com
security.scaleway.com
repo.openai.com
pkg.openai.com
files.openai.com
raw.openai.com
resources.openai.com
training.openai.com
security.openai.com
repo.anthropic.com
pkg.anthropic.com
files.anthropic.com
raw.anthropic.com
resources.anthropic.com
training.anthropic.com
security.anthropic.com
repo.huggingface.co
pkg.huggingface.co
files.huggingface.co
raw.huggingface.co
resources.huggingface.co
training.huggingface.co
security.huggingface.co
docs.tensorflow.org
doc.tensorflow.org
developer.tensorflow.org
developers.tensorflow.org
api.tensorflow.org
status.tensorflow.org
support.tensorflow.org
blog.tensorflow.org
cdn.tensorflow.org
static.tensorflow.org
assets.tensorflow.org
download.tensorflow.org
downloads.tensorflow.org
registry.tensorflow.org
repo.tensorflow.org
packages.tensorflow.org
pkg.tensorflow.org
files.tensorflow.org
raw.tensorflow.org
resources.tensorflow.org
community.tensorflow.org
help.tensorflow.org
learn.tensorflow.org
training.tensorflow.org
security.tensorflow.org
www.pytorch.org
docs.pytorch.org
doc.pytorch.org
developer.pytorch.org
developers.pytorch.org
api.pytorch.org
status.pytorch.org
support.pytorch.org
blog.pytorch.org
cdn.pytorch.org
static.pytorch.org
assets.pytorch.org
downloads.pytorch.org
registry.pytorch.org
repo.pytorch.org
packages.pytorch.org
pkg.pytorch.org
files.pytorch.org
raw.pytorch.org
resources.pytorch.org
community.pytorch.org
help.pytorch.org
learn.pytorch.org
training.pytorch.org
security.pytorch.org
docs.cambridge.org
doc.cambridge.org
developer.cambridge.org
developers.cambridge.org
api.cambridge.org
status.cambridge.org
support.cambridge.org
blog.cambridge.org
cdn.cambridge.org
static.cambridge.org
assets.cambridge.org
download.cambridge.org
downloads.cambridge.org
registry.cambridge.org
repo.cambridge.org
packages.cambridge.org
pkg.cambridge.org
files.cambridge.org
raw.cambridge.org
resources.cambridge.org
community.cambridge.org
help.cambridge.org
learn.cambridge.org
training.cambridge.org
security.cambridge.org
docs.nasa.gov
doc.nasa.gov
developer.nasa.gov
developers.nasa.gov
api.nasa.gov
status.nasa.gov
support.nasa.gov
blog.nasa.gov
cdn.nasa.gov
static.nasa.gov
assets.nasa.gov
download.nasa.gov
downloads.nasa.gov
registry.nasa.gov
repo.nasa.gov
packages.nasa.gov
pkg.nasa.gov
files.nasa.gov
raw.nasa.gov
resources.nasa.gov
community.nasa.gov
help.nasa.gov
learn.nasa.gov
training.nasa.gov
security.nasa.gov
docs.nist.gov
doc.nist.gov
developer.nist.gov
developers.nist.gov
api.nist.gov
status.nist.gov
support.nist.gov
blog.nist.gov
cdn.nist.gov
static.nist.gov
assets.nist.gov
download.nist.gov
downloads.nist.gov
registry.nist.gov
repo.nist.gov
packages.nist.gov
pkg.nist.gov
files.nist.gov
raw.nist.gov
resources.nist.gov
community.nist.gov
help.nist.gov
learn.nist.gov
training.nist.gov
security.nist.gov
docs.cisa.gov
doc.cisa.gov
developer.cisa.gov
developers.cisa.gov
api.cisa.gov
status.cisa.gov
support.cisa.gov
blog.cisa.gov
cdn.cisa.gov
static.cisa.gov
assets.cisa.gov
download.cisa.gov
downloads.cisa.gov
registry.cisa.gov
repo.cisa.gov
packages.cisa.gov
pkg.cisa.gov
files.cisa.gov
raw.cisa.gov
resources.cisa.gov
community.cisa.gov
help.cisa.gov
learn.cisa.gov
training.cisa.gov
security.cisa.gov
docs.wikipedia.org
doc.wikipedia.org
developer.wikipedia.org
developers.wikipedia.org
api.wikipedia.org
status.wikipedia.org
support.wikipedia.org
blog.wikipedia.org
cdn.wikipedia.org
static.wikipedia.org
assets.wikipedia.org
download.wikipedia.org
downloads.wikipedia.org
registry.wikipedia.org
repo.wikipedia.org
packages.wikipedia.org
pkg.wikipedia.org
files.wikipedia.org
raw.wikipedia.org
resources.wikipedia.org
community.wikipedia.org
help.wikipedia.org
learn.wikipedia.org
training.wikipedia.org
security.wikipedia.org
repo.wikimedia.org
pkg.wikimedia.org
files.wikimedia.org
raw.wikimedia.org
resources.wikimedia.org
training.wikimedia.org
security.wikimedia.org
docs.archive.org
doc.archive.org
developer.archive.org
developers.archive.org
api.archive.org
status.archive.org
support.archive.org
cdn.archive.org
static.archive.org
assets.archive.org
download.archive.org
downloads.archive.org
registry.archive.org
repo.archive.org
packages.archive.org
pkg.archive.org
files.archive.org
raw.archive.org
resources.archive.org
community.archive.org
help.archive.org
learn.archive.org
training.archive.org
security.archive.org
repo.stackoverflow.com
pkg.stackoverflow.com
files.stackoverflow.com
raw.stackoverflow.com
resources.stackoverflow.com
training.stackoverflow.com
security.stackoverflow.com
repo.stackexchange.com
pkg.stackexchange.com
files.stackexchange.com
raw.stackexchange.com
resources.stackexchange.com
training.stackexchange.com
npmjs.org
www.npmjs.org
docs.npmjs.org
doc.npmjs.org
developer.npmjs.org
developers.npmjs.org
api.npmjs.org
status.npmjs.org
support.npmjs.org
blog.npmjs.org
cdn.npmjs.org
static.npmjs.org
assets.npmjs.org
download.npmjs.org
downloads.npmjs.org
repo.npmjs.org
packages.npmjs.org
pkg.npmjs.org
files.npmjs.org
raw.npmjs.org
resources.npmjs.org
community.npmjs.org
help.npmjs.org
learn.npmjs.org
training.npmjs.org
security.npmjs.org
github.io
www.github.io
docs.github.io
doc.github.io
developer.github.io
developers.github.io
api.github.io
status.github.io
support.github.io
blog.github.io
cdn.github.io
static.github.io
assets.github.io
download.github.io
downloads.github.io
registry.github.io
repo.github.io
packages.github.io
pkg.github.io
files.github.io
raw.github.io
resources.github.io
community.github.io
help.github.io
learn.github.io
training.github.io
security.github.io
cloudflare.tv
docs.cloudflare.tv
doc.cloudflare.tv
developer.cloudflare.tv
developers.cloudflare.tv
api.cloudflare.tv
status.cloudflare.tv
support.cloudflare.tv
blog.cloudflare.tv
cdn.cloudflare.tv
static.cloudflare.tv
assets.cloudflare.tv
download.cloudflare.tv
downloads.cloudflare.tv
registry.cloudflare.tv
repo.cloudflare.tv
packages.cloudflare.tv
pkg.cloudflare.tv
files.cloudflare.tv
raw.cloudflare.tv
resources.cloudflare.tv
community.cloudflare.tv
help.cloudflare.tv
learn.cloudflare.tv
training.cloudflare.tv
security.cloudflare.tv
repo.stanford.edu
pkg.stanford.edu
files.stanford.edu
raw.stanford.edu
resources.stanford.edu
training.stanford.edu
security.stanford.edu
repo.mit.edu
pkg.mit.edu
files.mit.edu
raw.mit.edu
resources.mit.edu
training.mit.edu
security.mit.edu
docs.berkeley.edu
doc.berkeley.edu
developer.berkeley.edu
developers.berkeley.edu
api.berkeley.edu
status.berkeley.edu
support.berkeley.edu
blog.berkeley.edu
cdn.berkeley.edu
static.berkeley.edu
assets.berkeley.edu
download.berkeley.edu
downloads.berkeley.edu
registry.berkeley.edu
repo.berkeley.edu
packages.berkeley.edu
pkg.berkeley.edu
files.berkeley.edu
raw.berkeley.edu
resources.berkeley.edu
community.berkeley.edu
help.berkeley.edu
learn.berkeley.edu
training.berkeley.edu
security.berkeley.edu
docs.ethz.ch
doc.ethz.ch
developer.ethz.ch
developers.ethz.ch
api.ethz.ch
status.ethz.ch
support.ethz.ch
blog.ethz.ch
cdn.ethz.ch
static.ethz.ch
assets.ethz.ch
download.ethz.ch
downloads.ethz.ch
registry.ethz.ch
repo.ethz.ch
packages.ethz.ch
pkg.ethz.ch
files.ethz.ch
raw.ethz.ch
resources.ethz.ch
community.ethz.ch
help.ethz.ch
learn.ethz.ch
training.ethz.ch
security.ethz.ch
docs.epfl.ch
doc.epfl.ch
developer.epfl.ch
developers.epfl.ch
api.epfl.ch
status.epfl.ch
support.epfl.ch
blog.epfl.ch
cdn.epfl.ch
static.epfl.ch
assets.epfl.ch
download.epfl.ch
downloads.epfl.ch
registry.epfl.ch
repo.epfl.ch
packages.epfl.ch
pkg.epfl.ch
files.epfl.ch
raw.epfl.ch
resources.epfl.ch
community.epfl.ch
help.epfl.ch
learn.epfl.ch
training.epfl.ch
security.epfl.ch
monash.edu
docs.monash.edu
doc.monash.edu
developer.monash.edu
developers.monash.edu
api.monash.edu
status.monash.edu
support.monash.edu
blog.monash.edu
cdn.monash.edu
static.monash.edu
assets.monash.edu
download.monash.edu
downloads.monash.edu
registry.monash.edu
repo.monash.edu
packages.monash.edu
pkg.monash.edu
files.monash.edu
raw.monash.edu
resources.monash.edu
community.monash.edu
help.monash.edu
learn.monash.edu
training.monash.edu
security.monash.edu
docs.github.blog
doc.github.blog
developer.github.blog
developers.github.blog
api.github.blog
status.github.blog
support.github.blog
blog.github.blog
cdn.github.blog
static.github.blog
assets.github.blog
download.github.blog
downloads.github.blog
registry.github.blog
repo.github.blog
packages.github.blog
pkg.github.blog
files.github.blog
raw.github.blog
resources.github.blog
community.github.blog
help.github.blog
learn.github.blog
training.github.blog
security.github.blog
docker.io
www.docker.io
docs.docker.io
doc.docker.io
developer.docker.io
developers.docker.io
api.docker.io
status.docker.io
support.docker.io
blog.docker.io
cdn.docker.io
static.docker.io
assets.docker.io
download.docker.io
downloads.docker.io
registry.docker.io
repo.docker.io
packages.docker.io
pkg.docker.io
files.docker.io
raw.docker.io
resources.docker.io
community.docker.io
help.docker.io
learn.docker.io
training.docker.io
security.docker.io
docs.cloudflare.net
doc.cloudflare.net
developer.cloudflare.net
developers.cloudflare.net
api.cloudflare.net
status.cloudflare.net
support.cloudflare.net
blog.cloudflare.net
cdn.cloudflare.net
static.cloudflare.net
assets.cloudflare.net
download.cloudflare.net
downloads.cloudflare.net
registry.cloudflare.net
repo.cloudflare.net
packages.cloudflare.net
pkg.cloudflare.net
files.cloudflare.net
raw.cloudflare.net
resources.cloudflare.net
community.cloudflare.net
help.cloudflare.net
learn.cloudflare.net
training.cloudflare.net
security.cloudflare.net
www.cloudfront.net
docs.cloudfront.net
doc.cloudfront.net
developer.cloudfront.net
developers.cloudfront.net
api.cloudfront.net
status.cloudfront.net
support.cloudfront.net
blog.cloudfront.net
cdn.cloudfront.net
static.cloudfront.net
assets.cloudfront.net
download.cloudfront.net
downloads.cloudfront.net
registry.cloudfront.net
repo.cloudfront.net
packages.cloudfront.net
pkg.cloudfront.net
files.cloudfront.net
raw.cloudfront.net
resources.cloudfront.net
community.cloudfront.net
help.cloudfront.net
learn.cloudfront.net
training.cloudfront.net
security.cloudfront.net
amazonaws.com
www.amazonaws.com
docs.amazonaws.com
doc.amazonaws.com
developer.amazonaws.com
developers.amazonaws.com
api.amazonaws.com
status.amazonaws.com
support.amazonaws.com
blog.amazonaws.com
cdn.amazonaws.com
static.amazonaws.com
assets.amazonaws.com
download.amazonaws.com
downloads.amazonaws.com
registry.amazonaws.com
repo.amazonaws.com
packages.amazonaws.com
pkg.amazonaws.com
files.amazonaws.com
raw.amazonaws.com
resources.amazonaws.com
community.amazonaws.com
help.amazonaws.com
learn.amazonaws.com
training.amazonaws.com
security.amazonaws.com
hetzner.cloud
www.hetzner.cloud
docs.hetzner.cloud
doc.hetzner.cloud
developer.hetzner.cloud
developers.hetzner.cloud
api.hetzner.cloud
status.hetzner.cloud
support.hetzner.cloud
blog.hetzner.cloud
cdn.hetzner.cloud
static.hetzner.cloud
assets.hetzner.cloud
download.hetzner.cloud
downloads.hetzner.cloud
registry.hetzner.cloud
repo.hetzner.cloud
packages.hetzner.cloud
pkg.hetzner.cloud
files.hetzner.cloud
raw.hetzner.cloud
resources.hetzner.cloud
community.hetzner.cloud
help.hetzner.cloud
learn.hetzner.cloud
training.hetzner.cloud
security.hetzner.cloud
www.redis.com
doc.redis.com
developer.redis.com
developers.redis.com
api.redis.com
status.redis.com
support.redis.com
blog.redis.com
cdn.redis.com
static.redis.com
assets.redis.com
download.redis.com
downloads.redis.com
registry.redis.com
repo.redis.com
packages.redis.com
pkg.redis.com
files.redis.com
raw.redis.com
resources.redis.com
community.redis.com
help.redis.com
learn.redis.com
training.redis.com
security.redis.com
www.stackoverflow.blog
docs.stackoverflow.blog
doc.stackoverflow.blog
developer.stackoverflow.blog
developers.stackoverflow.blog
api.stackoverflow.blog
status.stackoverflow.blog
support.stackoverflow.blog
blog.stackoverflow.blog
cdn.stackoverflow.blog
static.stackoverflow.blog
assets.stackoverflow.blog
download.stackoverflow.blog
downloads.stackoverflow.blog
registry.stackoverflow.blog
repo.stackoverflow.blog
packages.stackoverflow.blog
pkg.stackoverflow.blog
files.stackoverflow.blog
raw.stackoverflow.blog
resources.stackoverflow.blog
community.stackoverflow.blog
help.stackoverflow.blog
learn.stackoverflow.blog
training.stackoverflow.blog
security.stackoverflow.blog
curl.dev
www.curl.dev
docs.curl.dev
doc.curl.dev
developer.curl.dev
developers.curl.dev
api.curl.dev
status.curl.dev
support.curl.dev
blog.curl.dev
cdn.curl.dev
static.curl.dev
assets.curl.dev
download.curl.dev
downloads.curl.dev
registry.curl.dev
repo.curl.dev
packages.curl.dev
pkg.curl.dev
files.curl.dev
raw.curl.dev
resources.curl.dev
community.curl.dev
help.curl.dev
learn.curl.dev
training.curl.dev
security.curl.dev
google.cn
www.google.cn
docs.google.cn
doc.google.cn
developer.google.cn
developers.google.cn
api.google.cn
status.google.cn
support.google.cn
blog.google.cn
cdn.google.cn
static.google.cn
assets.google.cn
download.google.cn
downloads.google.cn
registry.google.cn
repo.google.cn
packages.google.cn
pkg.google.cn
files.google.cn
raw.google.cn
resources.google.cn
community.google.cn
help.google.cn
learn.google.cn
training.google.cn
security.google.cn
www.akamai.net
docs.akamai.net
doc.akamai.net
developer.akamai.net
developers.akamai.net
api.akamai.net
status.akamai.net
support.akamai.net
blog.akamai.net
cdn.akamai.net
static.akamai.net
assets.akamai.net
download.akamai.net
downloads.akamai.net
registry.akamai.net
repo.akamai.net
packages.akamai.net
pkg.akamai.net
files.akamai.net
raw.akamai.net
resources.akamai.net
community.akamai.net
help.akamai.net
learn.akamai.net
training.akamai.net
security.akamai.net
www.fastly.net
docs.fastly.net
doc.fastly.net
developer.fastly.net
developers.fastly.net
api.fastly.net
status.fastly.net
support.fastly.net
blog.fastly.net
cdn.fastly.net
static.fastly.net
assets.fastly.net
download.fastly.net
downloads.fastly.net
registry.fastly.net
repo.fastly.net
packages.fastly.net
pkg.fastly.net
files.fastly.net
raw.fastly.net
resources.fastly.net
community.fastly.net
help.fastly.net
learn.fastly.net
training.fastly.net
security.fastly.net
google.ca
docs.google.ca
doc.google.ca
developer.google.ca
developers.google.ca
api.google.ca
status.google.ca
support.google.ca
blog.google.ca
cdn.google.ca
static.google.ca
assets.google.ca
download.google.ca
downloads.google.ca
registry.google.ca
repo.google.ca
packages.google.ca
pkg.google.ca
files.google.ca
raw.google.ca
resources.google.ca
community.google.ca
help.google.ca
learn.google.ca
training.google.ca
security.google.ca
google.ch
docs.google.ch
doc.google.ch
developer.google.ch
developers.google.ch
api.google.ch
status.google.ch
support.google.ch
blog.google.ch
cdn.google.ch
static.google.ch
assets.google.ch
download.google.ch
downloads.google.ch
registry.google.ch
repo.google.ch
packages.google.ch
pkg.google.ch
files.google.ch
raw.google.ch
resources.google.ch
community.google.ch
help.google.ch
learn.google.ch
training.google.ch
security.google.ch
google.de
docs.google.de
doc.google.de
developer.google.de
developers.google.de
api.google.de
status.google.de
support.google.de
blog.google.de
cdn.google.de
static.google.de
assets.google.de
download.google.de
downloads.google.de
registry.google.de
repo.google.de
packages.google.de
pkg.google.de
files.google.de
raw.google.de
resources.google.de
community.google.de
help.google.de
learn.google.de
training.google.de
security.google.de
google.es
docs.google.es
doc.google.es
developer.google.es
developers.google.es
api.google.es
status.google.es
support.google.es
blog.google.es
cdn.google.es
static.google.es
assets.google.es
download.google.es
downloads.google.es
registry.google.es
repo.google.es
packages.google.es
pkg.google.es
files.google.es
raw.google.es
resources.google.es
community.google.es
help.google.es
learn.google.es
training.google.es
security.google.es
google.fr
docs.google.fr
doc.google.fr
developer.google.fr
developers.google.fr
api.google.fr
status.google.fr
support.google.fr
blog.google.fr
cdn.google.fr
static.google.fr
assets.google.fr
download.google.fr
downloads.google.fr
registry.google.fr
repo.google.fr
packages.google.fr
pkg.google.fr
files.google.fr
raw.google.fr
resources.google.fr
community.google.fr
help.google.fr
learn.google.fr
training.google.fr
security.google.fr
google.ie
docs.google.ie
doc.google.ie
developer.google.ie
developers.google.ie
api.google.ie
status.google.ie
support.google.ie
blog.google.ie
cdn.google.ie
static.google.ie
assets.google.ie
download.google.ie
downloads.google.ie
registry.google.ie
repo.google.ie
packages.google.ie
pkg.google.ie
files.google.ie
raw.google.ie
resources.google.ie
community.google.ie
help.google.ie
learn.google.ie
training.google.ie
security.google.ie
google.it
docs.google.it
doc.google.it
developer.google.it
developers.google.it
api.google.it
status.google.it
support.google.it
blog.google.it
cdn.google.it
static.google.it
assets.google.it
download.google.it
downloads.google.it
registry.google.it
repo.google.it
packages.google.it
pkg.google.it
files.google.it
raw.google.it
resources.google.it
community.google.it
help.google.it
learn.google.it
training.google.it
security.google.it
google.nl
docs.google.nl
doc.google.nl
developer.google.nl
developers.google.nl
api.google.nl
status.google.nl
support.google.nl
blog.google.nl
cdn.google.nl
static.google.nl
assets.google.nl
download.google.nl
downloads.google.nl
registry.google.nl
repo.google.nl
packages.google.nl
pkg.google.nl
files.google.nl
raw.google.nl
resources.google.nl
community.google.nl
help.google.nl
learn.google.nl
training.google.nl
security.google.nl
google.se
docs.google.se
doc.google.se
developer.google.se
developers.google.se
api.google.se
status.google.se
support.google.se
blog.google.se
cdn.google.se
static.google.se
assets.google.se
download.google.se
downloads.google.se
registry.google.se
repo.google.se
packages.google.se
pkg.google.se
files.google.se
raw.google.se
resources.google.se
community.google.se
help.google.se
learn.google.se
training.google.se
security.google.se
EOF_SNI_CANDIDATES

    cat >> "$raw" <<'EOF_SNI_PRIORITY'
EOF_SNI_PRIORITY

    # Generate conservative subdomain variants for strong apexes. Invalid/nonexistent hosts are filtered by TLS probing.
    awk 'NF && $0 !~ /^#/ {print tolower($0)}' "$raw" | \
        sed -E 's#^https?://##; s#/.*$##; s/:443$//; s/[[:space:]]//g' | \
        grep -E '^([a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?\.)+[a-z]{2,63}$' | \
        awk '!seen[$0]++' > "$generated"

    awk -F. 'NF>=2 {
        base=$(NF-1); apex=base "." $NF
        if (base ~ /^(github|cloudflare|microsoft|google|apache|mozilla|docker|kubernetes|linuxfoundation|cncf|python|rust-lang|golang|go|oracle|ibm|redhat|ubuntu|debian|nginx|postgresql|mongodb|elastic|hashicorp|terraform|confluent|fastly|akamai|digitalocean|linode|vultr|hetzner|ovhcloud|scaleway|openai|anthropic|huggingface|pytorch|tensorflow|ietf|w3|rfc-editor|openssl|curl|gnu|kernel|freebsd|openbsd|netbsd|eclipse|jetbrains|npmjs|nodejs|typescriptlang|redis|sqlite|mysql|wikimedia|wikipedia|archive|stackoverflow|stackexchange|nasa|nist|cisa|stanford|mit|berkeley|cambridge|ox|ethz|epfl|unimelb|sydney|unsw|monash|auckland|cloudfront|amazonaws)$/) print apex
    }' "$generated" | awk '!seen[$0]++' | while IFS= read -r apex; do
        for p in www docs doc developer developers api status support blog cdn static assets download downloads registry repo packages pkg files raw resources community help learn training security; do
            printf '%s.%s\n' "$p" "$apex"
        done
        printf '%s\n' "$apex"
    done >> "$generated"

    awk 'NF && $0 !~ /^#/ {print tolower($0)}' "$generated" | \
        sed -E 's#^https?://##; s#/.*$##; s/:443$//; s/[[:space:]]//g' | \
        grep -E '^([a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?\.)+[a-z]{2,63}$' | \
        grep -Ev '(^|\.)(doubleclick|googlesyndication|googleadservices|facebook|tiktok|tracking|track|ads|analytics|telemetry)\.' | \
        awk '!seen[$0]++' > "$tmp"

    if [[ "$profile" == 'mini' ]]; then
        # Mini mode uses the same full candidate library as full mode to preserve the probability of finding the best SNI.
        # It only lowers runtime pressure through reduced concurrency and verification limits.
        max_count="${ABOX_SNI_MINI_MAX:-0}"
    else
        max_count="${ABOX_SNI_FULL_MAX:-0}"
    fi
    if [[ "$max_count" =~ ^[0-9]+$ && "$max_count" -gt 0 ]]; then
        awk -v n="$max_count" 'NR<=n {print}' "$tmp" > "$out"
    else
        cp -f "$tmp" "$out"
    fi
    rm -f "$raw" "$generated" "$tmp"
}

sni_domain_penalty() {
    local domain="${1,,}" penalty=0
    case "$domain" in
        *.apple.com|*.icloud.com|www.apple.com|www.icloud.com) penalty=$((penalty + 1500)) ;;
        www.nike.com|www.adidas.com|www.amazon.com|www.google.com|www.microsoft.com|www.bing.com|www.youtube.com|www.netflix.com) penalty=$((penalty + 300)) ;;
        *.facebook.com|*.tiktok.com|*.doubleclick.net|*.googlesyndication.com|*.googleadservices.com) penalty=$((penalty + 2000)) ;;
    esac
    case "$domain" in
        docs.*|developer.*|developers.*|*.apache.org|*.mozilla.org|*.linuxfoundation.org|*.cncf.io|*.ietf.org|*.rfc-editor.org|*.w3.org|*.kernel.org|*.debian.org|*.ubuntu.com|*.cloudflare.com|*.fastly.com|*.confluent.io) penalty=$((penalty - 120)) ;;
    esac
    printf '%s\n' "$penalty"
}

asn_lookup_ip() {
    local ip="${1:-}" cache_dir="${2:-/tmp/A-Box-asn-cache}" cache_file body asn country org
    [[ -n "$ip" && "$ip" != 'N/A' ]] || { printf 'asn=unknown\tcountry=unknown\torg=unknown'; return 0; }
    mkdir -p "$cache_dir" 2>/dev/null || true
    cache_file="$cache_dir/$(printf '%s' "$ip" | tr -c 'A-Za-z0-9_.:-' '_')"
    if [[ -s "$cache_file" ]]; then
        cat "$cache_file"
        return 0
    fi
    body=$(curl -fsS --connect-timeout 2 -m 4 "https://ipinfo.io/${ip}/json" 2>/dev/null || true)
    if [[ -n "$body" ]] && command -v jq >/dev/null 2>&1; then
        org=$(jq -r '.org // "unknown"' <<< "$body" 2>/dev/null | tr '\t\n\r' '   ' | sed -E 's/[[:space:]]+/ /g; s/^ //; s/ $//')
        country=$(jq -r '.country // "unknown"' <<< "$body" 2>/dev/null | tr '\t\n\r' '   ' | sed -E 's/[[:space:]]+/ /g; s/^ //; s/ $//')
        asn=$(sed -nE 's/^(AS[0-9]+).*/\1/p' <<< "$org")
    fi
    [[ -n "$asn" ]] || asn='unknown'
    [[ -n "$country" ]] || country='unknown'
    [[ -n "$org" ]] || org='unknown'
    printf 'asn=%s\tcountry=%s\torg=%s' "$asn" "$country" "$org" | tee "$cache_file" 2>/dev/null || true
}

sni_org_cdn_penalty() {
    local domain="${1,,}" org="${2,,}" penalty=0
    case "$org $domain" in
        *cloudflare*|*akamai*|*fastly*|*cloudfront*|*google*|*microsoft*|*amazon*|*aws*|*edgecast*|*verizon*|*stackpath*|*bunny*|*cdn77*) penalty=$((penalty + 250)) ;;
    esac
    case "$domain" in
        *.cloudflare.com|*.fastly.com|*.akamai.com|*.apache.org|*.confluent.io|*.mozilla.org|*.kernel.org|*.debian.org|*.ubuntu.com) penalty=$((penalty - 80)) ;;
    esac
    printf '%s\n' "$penalty"
}

sni_probe_domain() {
    local domain="$1" raw="$2" timeout_s="${3:-6}" metrics code t_connect t_app t_start t_total http_version remote_ip penalty score tls_args=()
    [[ "$domain" =~ ^([a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?\.)+[a-z]{2,63}$ ]] || return 0
    if curl --help all 2>/dev/null | grep -q -- '--tlsv1.3'; then
        tls_args=(--tlsv1.3)
    fi
    metrics=$(curl -sSIL "${tls_args[@]}" --connect-timeout "$timeout_s" --max-time "$((timeout_s + 4))" \
        -o /dev/null \
        -w '%{http_code}\t%{time_connect}\t%{time_appconnect}\t%{time_starttransfer}\t%{time_total}\t%{http_version}\t%{remote_ip}' \
        "https://${domain}/" 2>/dev/null) || return 0
    IFS=$'\t' read -r code t_connect t_app t_start t_total http_version remote_ip <<< "$metrics"
    [[ "$t_app" =~ ^[0-9.]+$ ]] || return 0
    awk -v v="$t_app" 'BEGIN{exit !(v>0)}' || return 0
    penalty=$(sni_domain_penalty "$domain")
    [[ "$http_version" == '2' || "$http_version" == '3' ]] || penalty=$((penalty + 350))
    [[ "$code" =~ ^(2|3|4)[0-9][0-9]$ ]] || penalty=$((penalty + 120))
    score=$(awk -v app="$t_app" -v start="$t_start" -v total="$t_total" -v p="$penalty" 'BEGIN{v=int(app*1000 + start*220 + total*60 + p); if(v<0)v=0; printf "%08d", v}')
    printf '%s\t%s\tapp=%ss\tttfb=%ss\ttotal=%ss\thttp=%s\tcode=%s\tip=%s\n' "$score" "$domain" "$t_app" "$t_start" "$t_total" "$http_version" "$code" "$remote_ip" >> "$raw"
}

sni_openssl_check() {
    local domain="$1" timeout_s="${2:-5}" out cert sanext rest alpn='none' tls13=0 san=0
    command -v openssl >/dev/null 2>&1 || { printf 'tls13=unknown\talpn=unknown\tsan=unknown'; return 0; }
    out=$(printf '' | timeout "$timeout_s" openssl s_client -connect "${domain}:443" -servername "$domain" -alpn 'h2,http/1.1' -tls1_3 -showcerts 2>/dev/null) || out=''
    if [[ -n "$out" ]]; then
        grep -qiE 'Protocol *: *TLSv1\.3|New, TLSv1\.3' <<< "$out" && tls13=1
        alpn=$(awk -F': ' '/ALPN protocol/{print $2; exit}' <<< "$out")
        [[ -n "$alpn" ]] || alpn='none'
        cert=$(awk 'BEGIN{p=0}/-----BEGIN CERTIFICATE-----/{p=1} p{print} /-----END CERTIFICATE-----/{exit}' <<< "$out")
        if [[ -n "$cert" ]]; then
            sanext=$(printf '%s\n' "$cert" | openssl x509 -noout -ext subjectAltName 2>/dev/null | tr '\n' ' ' || true)
            if grep -qi "DNS:${domain}\b" <<< "$sanext"; then
                san=1
            else
                rest="${domain#*.}"
                grep -qi "DNS:\*\.${rest}\b" <<< "$sanext" && san=1
            fi
        fi
    fi
    printf 'tls13=%s\talpn=%s\tsan=%s' "$tls13" "$alpn" "$san"
}

sni_verify_raw_report() {
    local raw_sorted="$1" verified="$2" verify_limit="${3:-240}" timeout_s="${4:-5}" line score domain c3 c4 c5 c6 c7 c8 check tls13 alpn san add adj n=0
    local asn_cache vps_ip vps_meta vps_asn vps_country target_ip target_meta target_asn target_country target_org asn_match same_country cdn_penalty progress_every=20
    : > "$verified"
    asn_cache=$(mktemp -d /tmp/A-Box-asn-cache.XXXXXX) || asn_cache='/tmp'
    vps_ip=$(get_public_ip 2>/dev/null || true)
    vps_meta=$(asn_lookup_ip "$vps_ip" "$asn_cache")
    vps_asn=$(awk -F'\t|=' '{for(i=1;i<=NF;i++) if($i=="asn"){print $(i+1); exit}}' <<< "$vps_meta")
    vps_country=$(awk -F'\t|=' '{for(i=1;i<=NF;i++) if($i=="country"){print $(i+1); exit}}' <<< "$vps_meta")
    [[ -n "$vps_asn" ]] || vps_asn='unknown'
    [[ -n "$vps_country" ]] || vps_country='unknown'
    msg "${YELLOW}[*] Stage 2: OpenSSL verification + ASN/topology scoring. VPS ${vps_ip:-N/A} ${vps_asn}/${vps_country}${NC}"
    while IFS=$'\t' read -r score domain c3 c4 c5 c6 c7 c8; do
        n=$((n + 1))
        (( n > verify_limit )) && break
        if (( n == 1 || n % progress_every == 0 )); then
            printf '\r[*] Stage 2 progress: %d/%d verified' "$n" "$verify_limit" >&2
        fi
        check=$(sni_openssl_check "$domain" "$timeout_s")
        tls13=$(awk -F'\t|=' '{for(i=1;i<=NF;i++) if($i=="tls13"){print $(i+1); exit}}' <<< "$check")
        alpn=$(awk -F'\t|=' '{for(i=1;i<=NF;i++) if($i=="alpn"){print $(i+1); exit}}' <<< "$check")
        san=$(awk -F'\t|=' '{for(i=1;i<=NF;i++) if($i=="san"){print $(i+1); exit}}' <<< "$check")
        target_ip="${c8#ip=}"
        target_meta=$(asn_lookup_ip "$target_ip" "$asn_cache")
        target_asn=$(awk -F'\t|=' '{for(i=1;i<=NF;i++) if($i=="asn"){print $(i+1); exit}}' <<< "$target_meta")
        target_country=$(awk -F'\t|=' '{for(i=1;i<=NF;i++) if($i=="country"){print $(i+1); exit}}' <<< "$target_meta")
        target_org=$(awk -F'\t|=' '{for(i=1;i<=NF;i++) if($i=="org"){print $(i+1); exit}}' <<< "$target_meta")
        [[ -n "$target_asn" ]] || target_asn='unknown'
        [[ -n "$target_country" ]] || target_country='unknown'
        [[ -n "$target_org" ]] || target_org='unknown'
        asn_match=0
        same_country=0
        [[ "$vps_asn" != 'unknown' && "$target_asn" == "$vps_asn" ]] && asn_match=1
        [[ "$vps_country" != 'unknown' && "$target_country" == "$vps_country" ]] && same_country=1
        add=0
        [[ "$tls13" == '1' ]] || add=$((add + 6000))
        [[ "$san" == '1' ]] || add=$((add + 6000))
        [[ "$alpn" == 'h2' ]] || add=$((add + 700))
        cdn_penalty=$(sni_org_cdn_penalty "$domain" "$target_org")
        add=$((add + cdn_penalty))
        [[ "$same_country" == '1' ]] && add=$((add - 250))
        [[ "$asn_match" == '1' ]] && add=$((add - 1200))
        adj=$(awk -v s="$score" -v a="$add" 'BEGIN{v=int(s)+int(a); if(v<0)v=0; printf "%08d", v}')
        printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\tasn=%s\tcountry=%s\tasnmatch=%s\tsamecountry=%s\torg=%s\n' \
            "$adj" "$domain" "$c3" "$c4" "$c5" "$c6" "$c7" "$c8" "$check" "$target_asn" "$target_country" "$asn_match" "$same_country" "$target_org" >> "$verified"
    done < "$raw_sorted"
    printf '\r[*] Stage 2 progress: %d/%d verified\n' "$(( n > verify_limit ? verify_limit : n ))" "$verify_limit" >&2
    sort -n "$verified" -o "$verified"
    rm -rf "$asn_cache" 2>/dev/null || true
}

run_builtin_sni_radar() {
    local profile="${1:-full}" title="${2:-Local SNI preference}" workdir candidates raw raw_sorted report total concurrency timeout_s running=0 domain topn verify_limit processed=0 valid_count=0 batch_start progress_every
    workdir=$(mktemp -d /tmp/A-Box-sni-radar.XXXXXX) || die 'SNI radar temporary directory creation failed.'
    candidates="$workdir/candidates.txt"
    raw="$workdir/results.raw.tsv"
    raw_sorted="$workdir/results.raw.sorted.tsv"
    report="$workdir/results.tsv"
    write_sni_candidate_library "$profile" "$candidates"
    total=$(wc -l < "$candidates" | tr -d ' ')
    if [[ "$profile" == 'mini' ]]; then
        # Mini mode uses the same candidate library as full mode. It reduces concurrency and verification depth only.
        concurrency="${ABOX_SNI_MINI_CONCURRENCY:-8}"
        timeout_s="${ABOX_SNI_MINI_TIMEOUT:-5}"
        topn=25
        verify_limit="${ABOX_SNI_MINI_VERIFY:-180}"
    else
        concurrency="${ABOX_SNI_FULL_CONCURRENCY:-36}"
        timeout_s="${ABOX_SNI_FULL_TIMEOUT:-6}"
        topn=35
        verify_limit="${ABOX_SNI_FULL_VERIFY:-420}"
    fi
    progress_every=$(( concurrency * 2 ))
    (( progress_every < 20 )) && progress_every=20
    msg "${CYAN}======================================================================${NC}"
    msg "${BOLD}${GREEN}${title}${NC}"
    msg "${CYAN}======================================================================${NC}"
    msg "${YELLOW}[*] Candidate library: ${total} domains | profile=${profile} | concurrency=${concurrency}${NC}"
    msg "${YELLOW}[*] Stage 1: HTTPS/TLSv1.3 curl metrics. Stage 2: OpenSSL TLS1.3 + ALPN + SAN + ASN/topology scoring.${NC}"
    msg "${YELLOW}[*] Fully internal SNI library; no legacy remote SNI scripts or gist extraction are used.${NC}"
    msg "${YELLOW}[*] Progress is printed after each batch; large libraries can take several minutes on low-end VPS.${NC}"
    : > "$raw"
    while IFS= read -r domain; do
        sni_probe_domain "$domain" "$raw" "$timeout_s" &
        running=$((running + 1))
        processed=$((processed + 1))
        if (( running >= concurrency )); then
            wait
            running=0
            valid_count=$(wc -l < "$raw" 2>/dev/null | tr -d ' ')
            printf '\r[*] Stage 1 progress: %d/%d tested | valid=%s' "$processed" "$total" "${valid_count:-0}" >&2
        elif (( processed % progress_every == 0 )); then
            valid_count=$(wc -l < "$raw" 2>/dev/null | tr -d ' ')
            printf '\r[*] Stage 1 progress: %d/%d queued | valid=%s' "$processed" "$total" "${valid_count:-0}" >&2
        fi
    done < "$candidates"
    wait
    valid_count=$(wc -l < "$raw" 2>/dev/null | tr -d ' ')
    printf '\r[*] Stage 1 progress: %d/%d tested | valid=%s\n' "$processed" "$total" "${valid_count:-0}" >&2
    if [[ ! -s "$raw" ]]; then
        rm -rf "$workdir"
        die 'SNI radar produced no valid HTTPS/TLS results. Check DNS, routing, firewall, curl/OpenSSL support.'
    fi
    sort -n "$raw" > "$raw_sorted"
    sni_verify_raw_report "$raw_sorted" "$report" "$verify_limit" "$timeout_s"
    if [[ ! -s "$report" ]]; then
        cp -f "$raw_sorted" "$report"
    fi
    mkdir -p "$ABOX_DIR" 2>/dev/null || true
    cp -f "$report" "$ABOX_DIR/A-Box-sni-${profile}.tsv" 2>/dev/null || true
    msg "${BLUE}----------------------------------------------------------------------${NC}"
    msg "${YELLOW}[ Top SNI Candidates / 优选 SNI 候选 ]${NC}"
    awk -F'\t' -v n="$topn" 'NR<=n {printf "%2d. %-42s %s %s %s %s %s %s %s %s %s\n", NR, $2, $3, $4, $5, $6, $7, $9, $10, $11, $12}' "$report"
    msg "${BLUE}----------------------------------------------------------------------${NC}"
    msg "${GREEN}Saved: ${ABOX_DIR}/A-Box-sni-${profile}.tsv${NC}"
    msg "${YELLOW}Use only domains with tls13=1 and san=1. Prefer asnmatch=1/samecountry=1 when available; avoid blindly using fixed Apple/Nike templates.${NC}"
    rm -rf "$workdir"
}

run_local_sni_benchmark() {
    if confirm_yes_no "$(tr_msg confirm_local_sni_full)"; then
        run_builtin_sni_radar 'full' 'Local SNI preference / 本地 SNI 优选'
    fi
    pause_return
}

run_local_sni_mini_benchmark() {
    if confirm_yes_no "$(tr_msg confirm_local_sni_mini)"; then
        run_builtin_sni_radar 'mini' 'Mini host local SNI preference / 微型主机本地 SNI 优选'
    fi
    pause_return
}



run_warp_manager() {
    if confirm_yes_no "$(printf "$(tr_msg confirm_remote)" 'fscarmen/warp Cloudflare WARP menu')"; then
        run_remote_bash_script 'fscarmen/warp Cloudflare WARP menu' 'https://gitlab.com/fscarmen/warp/-/raw/main/menu.sh'
    fi
    pause_return
}

setup_swap_2g() {
    clear
    msg "${CYAN}======================================================================${NC}"
    msg "${BOLD}${GREEN}Swap 虚拟内存一键划拨 / Allocate 2G Swap${NC}"
    msg "${CYAN}======================================================================${NC}"
    if [[ -f /swapfile ]]; then
        msg "${YELLOW}$(tr_msg swap_exists)${NC}"
    else
        fallocate -l 2G /swapfile || dd if=/dev/zero of=/swapfile bs=1M count=2048 status=progress
        chmod 600 /swapfile
        mkswap /swapfile
    fi
    swapon /swapfile 2>/dev/null || true
    if ! grep -qE '^/swapfile[[:space:]]+none[[:space:]]+swap[[:space:]]+sw[[:space:]]+0[[:space:]]+0' /etc/fstab 2>/dev/null; then
        echo '/swapfile none swap sw 0 0' >> /etc/fstab
    fi
    swapon --show || true
    msg "${GREEN}$(tr_msg swap_done)${NC}"
    pause_return
}

vps_benchmark_menu() {
    clear
    msg "${CYAN}======================================================================${NC}"
    msg "${BOLD}${GREEN}$(tr_msg toolbox_title)${NC}"
    msg "${CYAN}======================================================================${NC}"
    if [[ "${ABOX_LANG:-zh}" == 'en' ]]; then
        msg "${YELLOW}1. System benchmark and download speed${NC}"
        msg "${YELLOW}2. IP quality, streaming unlock and route test${NC}"
        msg "${YELLOW}3. Local SNI preference${NC}"
        msg "${YELLOW}4. Mini host local SNI preference${NC}"
        msg "${YELLOW}5. Cloudflare WARP manager (egress IP masking / streaming unlock)${NC}"
        msg "${YELLOW}6. Allocate 2G Swap (prevent OOM crashes)${NC}"
        msg "${GREEN}0. Back${NC}"
    else
        msg "${YELLOW}1. 本机配置和下载测速${NC}"
        msg "${YELLOW}2. IP纯净度、流媒体解锁与回程测试${NC}"
        msg "${YELLOW}3. 本地 SNI 优选${NC}"
        msg "${YELLOW}4. 微型主机本地 SNI 优选${NC}"
        msg "${YELLOW}5. Cloudflare WARP 一键接管 (出站 IP 伪装/流媒体解锁)${NC}"
        msg "${YELLOW}6. Swap 虚拟内存一键划拨 2G (防 OOM 宕机)${NC}"
        msg "${GREEN}0. 返回主菜单${NC}"
    fi
    local bench_choice
    read -r -ep 'Select [0-6]: ' bench_choice
    case "$bench_choice" in
        1)
            confirm_yes_no "$(printf "$(tr_msg confirm_remote)" 'System benchmark and download speed')" && run_remote_bash_script 'System benchmark and download speed' 'https://bench.sh'
            pause_return
            ;;
        2)
            confirm_yes_no "$(printf "$(tr_msg confirm_remote)" 'IP quality, streaming unlock and route test')" && run_remote_bash_script 'IP quality, streaming unlock and route test' 'https://Check.Place' -I
            pause_return
            ;;
        3) run_local_sni_benchmark ;;
        4) run_local_sni_mini_benchmark ;;
        5) run_warp_manager ;;
        6) setup_swap_2g ;;
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


urlencode() {
    local raw="${1:-}"
    jq -rn --arg v "$raw" '$v|@uri'
}

build_ss2022_uri() {
    local host="$1" port="$2" pass="$3"
    # SIP002/SIP022: AEAD-2022 userinfo must not be Base64URL encoded;
    # method and password are percent-encoded as RFC3986 userinfo.
    printf 'ss://%s:%s@%s:%s#A-Box-SS\n' \
        "$(urlencode '2022-blake3-aes-128-gcm')" \
        "$(urlencode "$pass")" \
        "$host" "$port"
}

singbox_hy2_tls_json() {
    if [[ -n "${HY2_DOMAIN:-}" && "${CORE:-}" != 'singbox' ]]; then
        cat <<EOF_TLS
      "tls": {
        "enabled": true,
        "server_name": "${HY2_DOMAIN}"
      }
EOF_TLS
    else
        cat <<EOF_TLS
      "tls": {
        "enabled": true,
        "insecure": true,
        "certificate_public_key_sha256": ["${HY2_CERT_PUBKEY_SHA256_B64:-}"]
      }
EOF_TLS
    fi
}

write_clash_yaml() {
    local out="${CLASH_YAML_PATH:-$ABOX_DIR/A-Box-clash.yaml}" S_IP="$LINK_IP" hy2_name="A-Box-Hy2-Self"
    [[ -n "${HY2_DOMAIN:-}" ]] && S_IP="$HY2_DOMAIN"
    [[ -n "${HY2_DOMAIN:-}" && "${CORE:-}" != 'singbox' ]] && hy2_name='A-Box-Hy2-ACME'
    mkdir -p "$ABOX_DIR"
    {
        cat <<EOF_CLASH
mixed-port: 7890
allow-lan: false
mode: rule
log-level: info
ipv6: true

dns:
  enable: true
  listen: 0.0.0.0:1053
  enhanced-mode: fake-ip
  fake-ip-range: 198.18.0.1/16
  nameserver:
    - https://dns.google/dns-query
    - https://cloudflare-dns.com/dns-query
  fallback:
    - tls://8.8.4.4
    - tls://1.1.1.1

proxies:
EOF_CLASH
        if [[ "$MODE" == *'VISION'* || "$MODE" == *'ALL'* || "$MODE" == 'VLESS_SS' ]]; then
            cat <<EOF_CLASH
  - name: "A-Box-VLESS-Vision"
    type: vless
    server: "$LINK_IP"
    port: $VLESS_PORT
    uuid: "$UUID"
    udp: true
    tls: true
    servername: "$VISION_SNI"
    client-fingerprint: chrome
    encryption: ""
    network: tcp
    flow: xtls-rprx-vision
    packet-encoding: xudp
    reality-opts:
      public-key: "$PUBLIC_KEY"
      short-id: "$SHORT_ID"
    smux:
      enabled: false
EOF_CLASH
        fi
        if [[ "$CORE" == 'xray' && ( "$MODE" == *'XHTTP'* || "$MODE" == *'ALL'* ) ]]; then
            cat <<EOF_CLASH
  - name: "A-Box-VLESS-XHTTP"
    type: vless
    server: "$LINK_IP"
    port: $XHTTP_PORT
    uuid: "$UUID"
    udp: true
    tls: true
    servername: "$XHTTP_SNI"
    client-fingerprint: chrome
    encryption: ""
    network: xhttp
    alpn:
      - h2
    reality-opts:
      public-key: "$PUBLIC_KEY"
      short-id: "$SHORT_ID"
    xhttp-opts:
      path: /xhttp
      host: "$XHTTP_SNI"
      mode: stream-one
    smux:
      enabled: false
EOF_CLASH
        fi
        if [[ "$MODE" == *'HY2'* || "$MODE" == *'ALL'* ]]; then
            if [[ -n "${HY2_DOMAIN:-}" && "$CORE" != 'singbox' ]]; then
                if [[ "${HY2_HOP:-}" == 'true' ]]; then
                    cat <<EOF_CLASH
  - name: "$hy2_name"
    type: hysteria2
    server: "$HY2_DOMAIN"
    ports: ${HY2_CLASH_PORTS}
    hop-interval: 30
    password: "$HY2_PASS"
    alpn:
      - h3
    sni: "$HY2_DOMAIN"
    obfs: salamander
    obfs-password: "$HY2_OBFS"
EOF_CLASH
                else
                    cat <<EOF_CLASH
  - name: "$hy2_name"
    type: hysteria2
    server: "$HY2_DOMAIN"
    port: $HY2_BASE_PORT
    password: "$HY2_PASS"
    alpn:
      - h3
    sni: "$HY2_DOMAIN"
    obfs: salamander
    obfs-password: "$HY2_OBFS"
EOF_CLASH
                fi
            else
                if [[ "${HY2_HOP:-}" == 'true' ]]; then
                    cat <<EOF_CLASH
  - name: "$hy2_name"
    type: hysteria2
    server: "$S_IP"
    ports: ${HY2_CLASH_PORTS}
    hop-interval: 30
    password: "$HY2_PASS"
    alpn:
      - h3
    skip-cert-verify: true
    fingerprint: "$HY2_CERT_SHA256_FP"
    obfs: salamander
    obfs-password: "$HY2_OBFS"
EOF_CLASH
                else
                    cat <<EOF_CLASH
  - name: "$hy2_name"
    type: hysteria2
    server: "$S_IP"
    port: $HY2_BASE_PORT
    password: "$HY2_PASS"
    alpn:
      - h3
    skip-cert-verify: true
    fingerprint: "$HY2_CERT_SHA256_FP"
    obfs: salamander
    obfs-password: "$HY2_OBFS"
EOF_CLASH
                fi
            fi
        fi
        if [[ "$MODE" == *'SS'* || "$MODE" == *'ALL'* || "$MODE" == 'VLESS_SS' ]]; then
            cat <<EOF_CLASH
  - name: "A-Box-SS"
    type: ss
    server: "$LINK_IP"
    port: $SS_PORT
    cipher: 2022-blake3-aes-128-gcm
    password: "$SS_PASS"
    udp: true
    smux:
      enabled: false
EOF_CLASH
        fi
        cat <<EOF_CLASH

proxy-groups:
  - name: PROXY
    type: select
    proxies:
EOF_CLASH
        [[ "$MODE" == *'VISION'* || "$MODE" == *'ALL'* || "$MODE" == 'VLESS_SS' ]] && echo '      - A-Box-VLESS-Vision'
        [[ "$CORE" == 'xray' && ( "$MODE" == *'XHTTP'* || "$MODE" == *'ALL'* ) ]] && echo '      - A-Box-VLESS-XHTTP'
        [[ "$MODE" == *'HY2'* || "$MODE" == *'ALL'* ]] && echo "      - $hy2_name"
        [[ "$MODE" == *'SS'* || "$MODE" == *'ALL'* || "$MODE" == 'VLESS_SS' ]] && echo '      - A-Box-SS'
        cat <<EOF_CLASH
      - DIRECT

rules:
  - MATCH,PROXY
EOF_CLASH
    } > "$out"
    chmod 600 "$out"
    printf '%s\n' "$out"
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
    [[ ! -f "$ABOX_ENV" ]] && { msg "${RED}未检测到持久化配置变量。${NC}"; sleep 2; return 0; }
    source "$ABOX_ENV"
    VISION_SNI=${VISION_SNI:-${VLESS_SNI:-}}
    XHTTP_SNI=${XHTTP_SNI:-${VLESS_SNI:-}}
    local F_IP="$LINK_IP" S_IP VLESS_URL XHTTP_URL HY2_URL SS_URL CLASH_FILE CLASH_SUB_URL CLASH_SCHEME
    local VISION_SNI_E XHTTP_SNI_E PUBLIC_KEY_E SHORT_ID_E HY2_PASS_E HY2_OBFS_E HY2_DOMAIN_E HY2_PIN_E
    [[ "$LINK_IP" =~ : ]] && F_IP="[$LINK_IP]"
    [[ -z "$LINK_IP" || "$LINK_IP" == 'N/A' ]] && msg "${YELLOW}[!] 未能自动获取公网 IP，分享链接可能不可用。${NC}"
    VISION_SNI_E=$(urlencode "$VISION_SNI")
    XHTTP_SNI_E=$(urlencode "$XHTTP_SNI")
    PUBLIC_KEY_E=$(urlencode "$PUBLIC_KEY")
    SHORT_ID_E=$(urlencode "$SHORT_ID")
    HY2_PASS_E=$(urlencode "$HY2_PASS")
    HY2_OBFS_E=$(urlencode "$HY2_OBFS")
    HY2_DOMAIN_E=$(urlencode "$HY2_DOMAIN")
    HY2_PIN_E=$(urlencode "$HY2_CERT_SHA256_FP")
    msg "${BLUE}======================================================================${NC}"
    msg "${BOLD}${CYAN}全局拓扑网络参数 (${MODE}) / Network Parameters${NC}"
    msg "${BLUE}======================================================================${NC}"
    msg "${BOLD}引擎栈:${NC} $CORE | ${BOLD}模式:${NC} $MODE"
    msg "${BLUE}----------------------------------------------------------------------${NC}"
    msg "${YELLOW}[ Shadowrocket / v2rayNG / NekoBox 单节点 URI ]${NC}"
    if [[ "$MODE" == *'VISION'* || "$MODE" == *'ALL'* || "$MODE" == 'VLESS_SS' ]]; then
        VLESS_URL="vless://$UUID@$F_IP:$VLESS_PORT?encryption=none&flow=xtls-rprx-vision&security=reality&sni=$VISION_SNI_E&fp=chrome&pbk=$PUBLIC_KEY_E&sid=$SHORT_ID_E&type=tcp#A-Box-VLESS-Vision"
        msg "${GREEN}${VLESS_URL}${NC}"
        generate_qr "$VLESS_URL"
    fi
    if [[ "$CORE" == 'xray' && ( "$MODE" == *'XHTTP'* || "$MODE" == *'ALL'* ) ]]; then
        XHTTP_URL="vless://$UUID@$F_IP:$XHTTP_PORT?encryption=none&security=reality&sni=$XHTTP_SNI_E&fp=chrome&pbk=$PUBLIC_KEY_E&sid=$SHORT_ID_E&type=xhttp&host=$XHTTP_SNI_E&path=%2Fxhttp&mode=stream-one#A-Box-VLESS-XHTTP"
        msg "${GREEN}${XHTTP_URL}${NC}"
        generate_qr "$XHTTP_URL"
    fi
    if [[ "$MODE" == *'HY2'* || "$MODE" == *'ALL'* ]]; then
        if [[ -n "${HY2_DOMAIN:-}" && "$CORE" != 'singbox' ]]; then
            HY2_URL="hysteria2://$HY2_PASS_E@$HY2_DOMAIN:$HY2_URI_PORTS/?sni=$HY2_DOMAIN_E&obfs=salamander&obfs-password=$HY2_OBFS_E#A-Box-Hy2-ACME"
        else
            S_IP="$F_IP"
            [[ -n "${HY2_DOMAIN:-}" ]] && S_IP="$HY2_DOMAIN"
            HY2_URL="hysteria2://$HY2_PASS_E@$S_IP:$HY2_URI_PORTS/?insecure=1&pinSHA256=$HY2_PIN_E&obfs=salamander&obfs-password=$HY2_OBFS_E#A-Box-Hy2-Self"
        fi
        msg "${GREEN}${HY2_URL}${NC}"
        [[ "${HY2_HOP:-}" == 'true' ]] && msg "${YELLOW}端口跳跃默认间隔 30s；不建议低于 5s。${NC}"
        generate_qr "$HY2_URL"
    fi
    if [[ "$MODE" == *'SS'* || "$MODE" == *'ALL'* || "$MODE" == 'VLESS_SS' ]]; then
        SS_URL=$(build_ss2022_uri "$F_IP" "$SS_PORT" "$SS_PASS")
        msg "${GREEN}${SS_URL}${NC}"
        generate_qr "$SS_URL"
    fi

    CLASH_FILE=$(write_clash_yaml)
    CLASH_SUB_URL="${ABOX_CLASH_SUB_URL:-${CLASH_SUB_URL:-}}"
    msg "${BLUE}----------------------------------------------------------------------${NC}"
    msg "${YELLOW}[ Clash / Mihomo 完整配置 ]${NC}"
    msg "${GREEN}Local YAML: ${CLASH_FILE}${NC}"
    msg "${YELLOW}Clash/Mihomo 类客户端请导入完整 YAML 或远程订阅 URL；不要扫描上方单条 vless:// / hysteria2:// / ss://。${NC}"
    if [[ -n "$CLASH_SUB_URL" ]]; then
        CLASH_SCHEME="clash://install-config?url=$(urlencode "$CLASH_SUB_URL")"
        msg "${GREEN}Subscription URL: ${CLASH_SUB_URL}${NC}"
        generate_qr "$CLASH_SUB_URL"
        msg "${GREEN}Clash Verge Rev URL Scheme: ${CLASH_SCHEME}${NC}"
        generate_qr "$CLASH_SCHEME"
    else
        msg "${YELLOW}未设置 ABOX_CLASH_SUB_URL。若需要 Clash 扫码导入，请把 ${CLASH_FILE} 发布到 HTTPS 后执行：${NC}"
        msg "${CYAN}ABOX_CLASH_SUB_URL='https://example.com/A-Box-clash.yaml' sb${NC}"
    fi

    msg "${BLUE}----------------------------------------------------------------------${NC}"
    msg "${YELLOW}[ Clash / Mihomo YAML 预览 ]${NC}"
    sed -n '1,220p' "$CLASH_FILE" 2>/dev/null || true

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
$(singbox_hy2_tls_json),
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
$(singbox_hy2_tls_json),
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
    if [[ "$CORE" == 'xray' && ( "$MODE" == *'XHTTP'* || "$MODE" == *'ALL'* ) ]]; then
        msg "\n${YELLOW}--- v2rayN / v2rayNG XHTTP JSON ---${NC}"
        cat <<EOF_V2N
{
  "v": "2",
  "ps": "A-Box-VLESS-XHTTP",
  "add": "$LINK_IP",
  "port": "$XHTTP_PORT",
  "id": "$UUID",
  "net": "xhttp",
  "type": "none",
  "path": "/xhttp",
  "mode": "stream-one",
  "tls": "reality",
  "sni": "$XHTTP_SNI",
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
    msg "${BOLD}${GREEN}A-Box 脚本全功能说明书 / Full Manual${NC}"
    msg "${CYAN}======================================================================${NC}"
    if [[ "${ABOX_LANG:-zh}" == 'en' ]]; then
        cat <<'EOF_USAGE'
[Deployment]
1  Xray VLESS-Vision-Reality
   TCP REALITY + Vision. Best default for long-term stealth. Port 443 defaults to www.apple.com; non-443 defaults to www.microsoft.com.
2  Xray VLESS-XHTTP-Reality
   XHTTP over REALITY. Best high-throughput desktop path with Mihomo v1.19.24+. Recommended: stream-one + h2 + smux disabled. Non-443 SNI should be selected by local SNI preference and manually verified for TLS1.3/H2/SAN; avoid Apple/iCloud on non-443.
3  Xray Shadowsocks-2022
   SS-2022 relay/landing inbound. Default port 2053 TCP/UDP. Best used behind frontend proxies with whitelist.
4  Native Hysteria 2
   UDP/QUIC/H3 acceleration. Use ACME domain cert when available; otherwise self-signed cert with pinSHA256.
5  Xray + Native Hysteria 2 All-in-one
   Vision TCP 443 + XHTTP TCP 8443 + HY2 UDP 443 + SS-2022 TCP/UDP 2053. Balanced speed/fallback deployment.
6  Sing-box VLESS-Vision-Reality
   Low-memory single-core Vision deployment.
7  Sing-box Shadowsocks-2022
   Low-memory SS-2022 relay deployment, default 2053 TCP/UDP.
8  Sing-box VLESS + SS-2022
   Vision main path plus SS-2022 relay path in one sing-box process.
9  Sing-box Hysteria 2
   HY2 in sing-box, best for UDP/QUIC mobile paths.
10 Sing-box All-in-one
   Sing-box Vision + HY2 + SS-2022. No XHTTP by design.

[Operations]
11 Toolbox
   System benchmark/download speed; IP quality/streaming unlock/route test; built-in full SNI preference library; built-in mini-host SNI preference library; Cloudflare WARP manager; 2G Swap allocation.
12 VPS One-click Optimization
   BBR/FQ, file descriptor limits, KeepAlive injection, health probe, logrotate/fail2ban defense.
13 Display Node Parameters
   Print URIs, QR codes, Clash/Mihomo YAML, sing-box outbounds, v2rayN/v2rayNG XHTTP JSON.
14 Manual
   This page.
15 OTA, Geo and Core-only Upgrade
   Update A-Box script, Xray Loyalsoldier geoip/geosite data, or upgrade installed proxy core binaries without resetting node parameters.
16 Full/Partial Uninstall
   Remove proxy stack, firewall rules, services and optional sb shortcut.
17 Environment Reset
   Kill orphan processes, clean stale firewall rules, remove broken configs and services.
18 Monthly Traffic Limit
   vnStat-based monthly traffic cap; stop services after reaching quota.
19 SS-2022 Whitelist Manager
   Add/remove frontend IP/CIDR and enforce DROP for non-whitelisted sources.
20 Language
   Switch Chinese/English UI and save to /etc/ddr/.lang.
EOF_USAGE
    else
        cat <<'EOF_USAGE'
【部署类】
1  Xray VLESS-Vision-Reality
   TCP REALITY + Vision。长期隐蔽主力。443/TCP 为主力端口；SNI 应使用工具箱本地优选结果并人工确认 TLS1.3/H2/SAN。Apple/iCloud 仅作 443 备用，不建议非443使用。
2  Xray VLESS-XHTTP-Reality
   XHTTP over REALITY。桌面高速优先，需 Mihomo v1.19.24+。推荐 stream-one + h2 + 关闭 smux。非443默认 www.microsoft.com。
3  Xray Shadowsocks-2022
   SS-2022 回程/落地入站。默认 2053 TCP/UDP。最适合公共前置/机场前置后接入，并建议白名单。
4  官方 Hysteria 2
   UDP/QUIC/H3 加速。优先自有域名 ACME 证书；无域名使用自签证书 + pinSHA256。
5  Xray + 官方 Hysteria 2 全协议四合一
   Vision TCP 443 + XHTTP TCP 8443 + HY2 UDP 443 + SS-2022 TCP/UDP 2053。兼顾隐蔽、速度、移动网络与链式回程。
6  Sing-box VLESS-Vision-Reality
   低内存单进程 Vision 部署。
7  Sing-box Shadowsocks-2022
   低内存 SS-2022 回程部署，默认 2053 TCP/UDP。
8  Sing-box VLESS + SS-2022
   Vision 主力 + SS-2022 回程双协议。
9  Sing-box Hysteria 2
   Sing-box 承载 HY2，适合 UDP/QUIC 移动链路。
10 Sing-box 全协议三合一
   Sing-box Vision + HY2 + SS-2022。按设计不包含 XHTTP。

【运维类】
11 综合工具箱
   本机配置/下载测速；IP纯净度/流媒体解锁/回程测试；内置全量SNI优选库；内置微型主机SNI优选库；Cloudflare WARP接管；2G Swap划拨。
12 VPS 一键优化
   BBR/FQ、文件句柄、KeepAlive、健康探针、logrotate/fail2ban防御。
13 全部节点参数显示
   输出 URI、二维码、Clash/Mihomo YAML、sing-box出站、v2rayN/v2rayNG XHTTP JSON。
14 脚本说明书
   当前页面。
15 脚本 OTA、Xray Geo 与核心无损升级
   更新 A-Box 主脚本、Xray Loyalsoldier geoip/geosite 数据，或仅升级当前已安装协议核心且不重置节点参数。
16 一键全部清空卸载
   删除代理栈、服务、防火墙规则，可选择是否保留 sb 快捷入口。
17 删除全部节点与环境初始化
   杀残留进程、清理陈旧规则、删除破损配置和服务。
18 每月流量管控限制
   基于 vnStat 设置月流量阈值，达到后自动停止服务。
19 SS-2022 白名单 IP 管理
   添加/删除前置机 IP/CIDR，对非白名单来源执行 DROP。
20 语言设置
   中英文切换，持久化保存至 /etc/ddr/.lang。
EOF_USAGE
    fi
    msg "${CYAN}======================================================================${NC}"
    pause_return
}

update_script() {
    clear
    local OTA_URL='https://raw.githubusercontent.com/alariclin/a-box/main/install.sh' tmp_update sha
    tmp_update=$(mktemp /tmp/A-Box-update.XXXXXX.sh) || die '更新脚本临时文件创建失败。'
    msg "${YELLOW}[*] 正在同步远端源码...${NC}"
    if curl -fLs --connect-timeout 10 "$OTA_URL" -o "$tmp_update"; then
        sha=$(sha256sum "$tmp_update" | awk '{print $1}')
        msg "${YELLOW}[*] OTA SHA256: ${sha}${NC}"
        if bash -n "$tmp_update" && grep -q '==============================A-Box===============================' "$tmp_update"; then
            install -m 755 "$tmp_update" "$ABOX_DIR/A-Box.sh"
            rm -f "$tmp_update"
            msg "${GREEN}核心代码热更新完毕。${NC}"
            sleep 2
            exec "$ABOX_DIR/A-Box.sh"
        else
            rm -f "$tmp_update"
            msg "${RED}[!] 更新脚本语法错误或指纹校验失败。${NC}"
        fi
    else
        rm -f "$tmp_update"
        msg "${RED}[!] 无法抵达更新服务器。${NC}"
    fi
    pause_return
}

force_update_geo() {
    clear
    [[ -x "$ABOX_DIR/geo_update.sh" ]] || setup_geo_cron
    msg "${YELLOW}[*] 正在拉取 Loyalsoldier Geo 资源并执行校验...${NC}"
    if bash "$ABOX_DIR/geo_update.sh"; then
        msg "${GREEN}Xray Geo 资源更新与校验成功。${NC}"
    else
        msg "${RED}[!] Xray Geo 资源下载失败或校验未通过。${NC}"
    fi
    pause_return
}


service_unit_exists() {
    local srv="$1"
    if [[ "${INIT_SYS:-}" == 'systemd' ]]; then
        systemctl list-unit-files "${srv}.service" >/dev/null 2>&1 && return 0
        [[ -f "/etc/systemd/system/${srv}.service" || -f "/lib/systemd/system/${srv}.service" || -f "/usr/lib/systemd/system/${srv}.service" ]] && return 0
    else
        [[ -x "/etc/init.d/${srv}" ]] && return 0
    fi
    return 1
}

restart_service_soft() {
    local srv="$1"
    if [[ "${INIT_SYS:-}" == 'systemd' ]]; then
        systemctl daemon-reload >/dev/null 2>&1 || true
        systemctl restart "$srv" >/dev/null 2>&1 || return 1
        sleep 2
        systemctl is-active --quiet "$srv"
    else
        rc-service "$srv" restart >/dev/null 2>&1 || return 1
        sleep 2
        rc-service "$srv" status >/dev/null 2>&1
    fi
}

restore_binary_backup() {
    local bin="$1" backup="$2"
    [[ -n "$backup" && -f "$backup" ]] || return 1
    install -m 755 "$backup" "$bin"
}

upgrade_xray_core_only() {
    local was_active=0 backup='' tmp xray_zip xray_ext old_ver new_ver
    msg "${YELLOW}[*] Upgrading Xray-core binary only; node parameters will be preserved...${NC}"
    get_architecture
    is_service_running xray && was_active=1 || true
    [[ -x /usr/local/bin/xray ]] && old_ver=$(/usr/local/bin/xray version 2>/dev/null | head -n 1 || true)
    tmp=$(mktemp -d /tmp/A-Box-core-xray.XXXXXX) || die 'Xray core upgrade temp directory failed.'
    xray_zip="$tmp/xray_core.zip"
    xray_ext="$tmp/xray_ext"
    mkdir -p "$xray_ext"
    fetch_github_release XTLS/Xray-core xray_core.zip "$xray_zip"
    unzip -qo "$xray_zip" -d "$xray_ext" || { rm -rf "$tmp"; die 'Xray core archive extraction failed.'; }
    [[ -f "$xray_ext/xray" ]] || { rm -rf "$tmp"; die 'Xray binary not found after extraction.'; }
    [[ -x /usr/local/bin/xray ]] && { backup="$tmp/xray.backup"; cp -a /usr/local/bin/xray "$backup"; }
    install -m 755 "$xray_ext/xray" /usr/local/bin/xray || { rm -rf "$tmp"; die 'Xray binary install failed.'; }
    new_ver=$(/usr/local/bin/xray version 2>/dev/null | head -n 1 || true)
    if [[ -f /usr/local/etc/xray/config.json ]]; then
        if ! /usr/local/bin/xray run -test -config /usr/local/etc/xray/config.json >/dev/null 2>&1; then
            msg "${RED}[!] New Xray failed current config test. Rolling back binary...${NC}"
            restore_binary_backup /usr/local/bin/xray "$backup" >/dev/null 2>&1 || true
            rm -rf "$tmp"
            die 'Xray core upgrade rolled back because current config is incompatible.'
        fi
    fi
    if [[ "$was_active" == '1' ]]; then
        if ! restart_service_soft xray; then
            msg "${RED}[!] New Xray failed to restart. Rolling back binary...${NC}"
            restore_binary_backup /usr/local/bin/xray "$backup" >/dev/null 2>&1 || true
            restart_service_soft xray >/dev/null 2>&1 || true
            rm -rf "$tmp"
            die 'Xray core upgrade rolled back because service restart failed.'
        fi
    fi
    msg "${GREEN}[OK] Xray-core upgraded.${NC} ${old_ver:-unknown} -> ${new_ver:-unknown}"
    rm -rf "$tmp"
}

upgrade_singbox_core_only() {
    local was_active=0 backup='' tmp sb_tar sb_ext sb_path old_ver new_ver
    msg "${YELLOW}[*] Upgrading sing-box binary only; node parameters will be preserved...${NC}"
    get_architecture
    is_service_running sing-box && was_active=1 || true
    [[ -x /usr/local/bin/sing-box ]] && old_ver=$(/usr/local/bin/sing-box version 2>/dev/null | head -n 1 || true)
    tmp=$(mktemp -d /tmp/A-Box-core-singbox.XXXXXX) || die 'sing-box core upgrade temp directory failed.'
    sb_tar="$tmp/singbox_core.tar.gz"
    sb_ext="$tmp/extract"
    mkdir -p "$sb_ext"
    fetch_github_release SagerNet/sing-box singbox_core.tar.gz "$sb_tar"
    tar -xzf "$sb_tar" -C "$sb_ext" || { rm -rf "$tmp"; die 'sing-box archive extraction failed.'; }
    sb_path=$(find "$sb_ext" -type f -name 'sing-box' | head -n 1)
    [[ -n "$sb_path" && -f "$sb_path" ]] || { rm -rf "$tmp"; die 'sing-box binary not found after extraction.'; }
    [[ -x /usr/local/bin/sing-box ]] && { backup="$tmp/sing-box.backup"; cp -a /usr/local/bin/sing-box "$backup"; }
    install -m 755 "$sb_path" /usr/local/bin/sing-box || { rm -rf "$tmp"; die 'sing-box binary install failed.'; }
    new_ver=$(/usr/local/bin/sing-box version 2>/dev/null | head -n 1 || true)
    if [[ -f /etc/sing-box/config.json ]]; then
        if ! /usr/local/bin/sing-box check -c /etc/sing-box/config.json >/dev/null 2>&1; then
            msg "${RED}[!] New sing-box failed current config check. Rolling back binary...${NC}"
            restore_binary_backup /usr/local/bin/sing-box "$backup" >/dev/null 2>&1 || true
            rm -rf "$tmp"
            die 'sing-box core upgrade rolled back because current config is incompatible.'
        fi
    fi
    if [[ "$was_active" == '1' ]]; then
        if ! restart_service_soft sing-box; then
            msg "${RED}[!] New sing-box failed to restart. Rolling back binary...${NC}"
            restore_binary_backup /usr/local/bin/sing-box "$backup" >/dev/null 2>&1 || true
            restart_service_soft sing-box >/dev/null 2>&1 || true
            rm -rf "$tmp"
            die 'sing-box core upgrade rolled back because service restart failed.'
        fi
    fi
    msg "${GREEN}[OK] sing-box upgraded.${NC} ${old_ver:-unknown} -> ${new_ver:-unknown}"
    rm -rf "$tmp"
}

upgrade_hysteria_core_only() {
    local was_active=0 backup='' tmp hy2_bin old_ver new_ver
    msg "${YELLOW}[*] Upgrading Hysteria 2 binary only; node parameters will be preserved...${NC}"
    get_architecture
    is_service_running hysteria && was_active=1 || true
    [[ -x /usr/local/bin/hysteria ]] && old_ver=$(/usr/local/bin/hysteria version 2>/dev/null | head -n 1 || true)
    tmp=$(mktemp -d /tmp/A-Box-core-hysteria.XXXXXX) || die 'Hysteria core upgrade temp directory failed.'
    hy2_bin="$tmp/hysteria_core"
    fetch_github_release apernet/hysteria hysteria_core "$hy2_bin"
    [[ -x /usr/local/bin/hysteria ]] && { backup="$tmp/hysteria.backup"; cp -a /usr/local/bin/hysteria "$backup"; }
    install -m 755 "$hy2_bin" /usr/local/bin/hysteria || { rm -rf "$tmp"; die 'Hysteria binary install failed.'; }
    /usr/local/bin/hysteria version >/dev/null 2>&1 || {
        msg "${RED}[!] New Hysteria binary failed execution check. Rolling back binary...${NC}"
        restore_binary_backup /usr/local/bin/hysteria "$backup" >/dev/null 2>&1 || true
        rm -rf "$tmp"
        die 'Hysteria core upgrade rolled back because binary check failed.'
    }
    new_ver=$(/usr/local/bin/hysteria version 2>/dev/null | head -n 1 || true)
    if [[ "$was_active" == '1' ]]; then
        if ! restart_service_soft hysteria; then
            msg "${RED}[!] New Hysteria failed to restart. Rolling back binary...${NC}"
            restore_binary_backup /usr/local/bin/hysteria "$backup" >/dev/null 2>&1 || true
            restart_service_soft hysteria >/dev/null 2>&1 || true
            rm -rf "$tmp"
            die 'Hysteria core upgrade rolled back because service restart failed.'
        fi
    fi
    msg "${GREEN}[OK] Hysteria upgraded.${NC} ${old_ver:-unknown} -> ${new_ver:-unknown}"
    rm -rf "$tmp"
}

upgrade_current_cores_only() {
    clear
    init_system_environment
    source "$ABOX_ENV" 2>/dev/null || true
    local targets=() answer t
    if [[ -x /usr/local/bin/xray || -f /usr/local/etc/xray/config.json || "${CORE:-}" == 'xray' ]] || service_unit_exists xray; then
        targets+=(xray)
    fi
    if [[ -x /usr/local/bin/sing-box || -f /etc/sing-box/config.json || "${CORE:-}" == 'singbox' ]] || service_unit_exists sing-box; then
        targets+=(singbox)
    fi
    if [[ -x /usr/local/bin/hysteria || -f /etc/hysteria/config.yaml || "${CORE:-}" == 'hysteria' || ( "${CORE:-}" == 'xray' && "${MODE:-}" == *'ALL'* ) ]] || service_unit_exists hysteria; then
        targets+=(hysteria)
    fi
    if (( ${#targets[@]} == 0 )); then
        msg "${YELLOW}[!] No installed A-Box core binaries/configs detected.${NC}"
        pause_return
        return 0
    fi
    msg "${CYAN}======================================================================${NC}"
    msg "${BOLD}${GREEN}Upgrade current installed proxy cores only / 仅升级当前已安装协议核心${NC}"
    msg "${CYAN}======================================================================${NC}"
    msg "Detected cores: ${targets[*]}"
    msg "This preserves /etc/ddr/.env, UUID, Reality keys, ports, passwords and all node parameters."
    msg "It downloads GitHub latest release assets, validates the current config where supported, restarts only active services, and rolls back the binary if validation/restart fails."
    read -r -ep 'Continue core-only upgrade? [Y/N]: ' answer
    is_yes "$answer" || { msg "${YELLOW}Canceled.${NC}"; pause_return; return 0; }
    for t in "${targets[@]}"; do
        case "$t" in
            xray) upgrade_xray_core_only ;;
            singbox) upgrade_singbox_core_only ;;
            hysteria) upgrade_hysteria_core_only ;;
        esac
    done
    msg "${GREEN}All detected core-only upgrades completed. Node parameters were preserved.${NC}"
    pause_return
}

ota_and_geo_menu() {
    clear
    msg "${CYAN}======================================================================${NC}"
    if [[ "${ABOX_LANG:-zh}" == 'en' ]]; then
        msg "${BOLD}${GREEN}OTA, Geo and Core-only Upgrade${NC}"
        msg "${CYAN}======================================================================${NC}"
        msg "${YELLOW}1. Upgrade A-Box script${NC}"
        msg "${YELLOW}2. Update Xray Loyalsoldier Geo resources now${NC}"
        msg "${YELLOW}3. Upgrade current installed proxy cores only; preserve node parameters${NC}"
        msg "${GREEN}0. Back${NC}"
        read -r -ep 'Select [0-3]: ' ota_choice
    else
        msg "${BOLD}${GREEN}脚本 OTA、Xray Geo 与核心无损升级${NC}"
        msg "${CYAN}======================================================================${NC}"
        msg "${YELLOW}1. 升级 A-Box 核心脚本${NC}"
        msg "${YELLOW}2. 立即拉取并更新 Xray Loyalsoldier Geo 资源${NC}"
        msg "${YELLOW}3. 仅升级当前已安装协议核心，不重置节点参数${NC}"
        msg "${GREEN}0. 返回主菜单${NC}"
        read -r -ep '请选择 [0-3]: ' ota_choice
    fi
    case "$ota_choice" in
        1) update_script ;;
        2) force_update_geo ;;
        3) upgrade_current_cores_only ;;
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
    mkdir -p /var/run "$ABOX_DIR"
    detect_lang
    initial_language_select
    exec 9>"$LOCK_FILE"
    if command -v flock >/dev/null 2>&1; then
        flock -n 9 || die '检测到另一个 A-Box 实例正在运行。'
    fi
}

show_cli_help() {
    cat <<'EOF_HELP'
A-Box
Usage:
  bash A-Box.sh                    启动交互菜单 / Start interactive menu
  bash A-Box.sh --lang zh          设置中文并启动 / Use Chinese UI
  bash A-Box.sh --lang en          Use English UI / 设置英文并启动
  bash A-Box.sh --self-test        运行无副作用静态自测 / Run static self-test
  bash A-Box.sh --status           显示当前配置和服务状态 / Show current status
  bash A-Box.sh --help             显示命令行帮助 / Show help
EOF_HELP
}

run_self_tests() {
    local tmp failures=0
    tmp=$(mktemp -d /tmp/A-Box-selftest.XXXXXX) || exit 1
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
    [[ "$(normalize_https_url_input www.microsoft.com)" == 'https://www.microsoft.com/' ]] || { echo 'FAIL: normalize HTTPS URL'; failures=$((failures + 1)); }
    [[ "$(normalize_https_url_input https://www.microsoft.com)" == 'https://www.microsoft.com/' ]] || { echo 'FAIL: normalize HTTPS URL trailing slash'; failures=$((failures + 1)); }
    [[ "$(build_ss2022_uri 203.0.113.10 2053 'abc+/=')" == 'ss://2022-blake3-aes-128-gcm:abc%2B%2F%3D@203.0.113.10:2053#A-Box-SS' ]] || { echo 'FAIL: SS-2022 SIP002/SIP022 URI percent encoding'; failures=$((failures + 1)); }

    ABOX_SNI_FULL_MAX=0 write_sni_candidate_library full "$tmp/sni-full.txt"
    sni_count=$(wc -l < "$tmp/sni-full.txt" | tr -d ' ')
    [[ "$sni_count" =~ ^[0-9]+$ && "$sni_count" -ge 2500 ]] || { echo "FAIL: SNI library size < 2500 ($sni_count)"; failures=$((failures + 1)); }
    grep -qx 'www.confluent.io' "$tmp/sni-full.txt" || { echo 'FAIL: SNI library missing www.confluent.io'; failures=$((failures + 1)); }
    grep -qx 'www.apache.org' "$tmp/sni-full.txt" || { echo 'FAIL: SNI library missing www.apache.org'; failures=$((failures + 1)); }
    ABOX_SNI_MINI_MAX=0 write_sni_candidate_library mini "$tmp/sni-mini.txt"
    mini_count=$(wc -l < "$tmp/sni-mini.txt" | tr -d ' ')
    [[ "$mini_count" =~ ^[0-9]+$ && "$mini_count" -eq "$sni_count" ]] || { echo "FAIL: SNI mini library does not match full library ($mini_count vs $sni_count)"; failures=$((failures + 1)); }
    declare -f asn_lookup_ip >/dev/null || { echo 'FAIL: ASN lookup function missing'; failures=$((failures + 1)); }
    declare -f sni_org_cdn_penalty >/dev/null || { echo 'FAIL: ASN/CDN scoring function missing'; failures=$((failures + 1)); }
    [[ "$(tr_msg confirm_local_sni_full)" != *'远程执行第三方脚本'* ]] || { echo 'FAIL: local SNI prompt still says remote third-party'; failures=$((failures + 1)); }
    assert_ok valid_ipv4_cidr 192.0.2.1/24
    assert_bad valid_ipv4_cidr 999.0.2.1/24
    assert_ok valid_ipv6_cidr 2001:db8::1/64
    assert_bad valid_ipv6_cidr 2001:::1/64

    UUID=00000000-0000-4000-8000-000000000000
    VLESS_SNI=www.example.com
    VISION_SNI=www.apple.com
    XHTTP_SNI=www.microsoft.com
    VLESS_PORT=8443
    XHTTP_PORT=9443
    SS_PORT=2053
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
    jq -e '.inbounds[] | select(.protocol=="shadowsocks" and .port==2053 and .settings.network=="tcp,udp")' "$tmp/xray/config.json" >/dev/null 2>&1 || { echo 'FAIL: Xray SS-2022 2053 tcp,udp'; failures=$((failures + 1)); }
    jq -e '.inbounds[] | select(.protocol=="vless" and .port==8443 and .streamSettings.realitySettings.serverNames[0]=="www.apple.com")' "$tmp/xray/config.json" >/dev/null 2>&1 || { echo 'FAIL: Xray Vision SNI split'; failures=$((failures + 1)); }
    jq -e '.inbounds[] | select(.protocol=="vless" and .port==9443 and .streamSettings.realitySettings.serverNames[0]=="www.microsoft.com")' "$tmp/xray/config.json" >/dev/null 2>&1 || { echo 'FAIL: Xray XHTTP SNI split'; failures=$((failures + 1)); }
    SINGBOX_CONFIG_PATH="$tmp/sing-box/config.json" build_singbox_config ALL
    jq empty "$tmp/sing-box/config.json" >/dev/null 2>&1 || { echo 'FAIL: build_singbox_config JSON'; failures=$((failures + 1)); }
    jq -e '.inbounds[] | select(.type=="shadowsocks" and .listen_port==2053 and (.network|not))' "$tmp/sing-box/config.json" >/dev/null 2>&1 || { echo 'FAIL: Sing-box SS-2022 2053 default network'; failures=$((failures + 1)); }
    jq -e 'all(.inbounds[]; .type != "xhttp")' "$tmp/sing-box/config.json" >/dev/null 2>&1 || { echo 'FAIL: Sing-box ALL must not include XHTTP'; failures=$((failures + 1)); }
    jq -e '.route.rules[] | select(.protocol=="bittorrent" and .action=="route" and .outbound=="block")' "$tmp/sing-box/config.json" >/dev/null 2>&1 || { echo 'FAIL: Sing-box route action'; failures=$((failures + 1)); }
    ABOX_DIR="$tmp" ABOX_ENV="$tmp/.env" CORE=xray MODE=ALL PUBLIC_KEY=publickey LINK_IP=203.0.113.10 HY2_DOMAIN= HY2_HOP=false HY2_CERT_SHA256_FP=abcdef HY2_CERT_PUBKEY_SHA256_B64=abcdef CLASH_YAML_PATH="$tmp/A-Box-clash.yaml" write_clash_yaml >/dev/null
    grep -q '^proxy-groups:' "$tmp/A-Box-clash.yaml" || { echo 'FAIL: Clash YAML proxy-groups'; failures=$((failures + 1)); }
    grep -q '^dns:' "$tmp/A-Box-clash.yaml" || { echo 'FAIL: Clash YAML dns'; failures=$((failures + 1)); }
    grep -q 'host: "www.microsoft.com"' "$tmp/A-Box-clash.yaml" || { echo 'FAIL: Clash XHTTP host'; failures=$((failures + 1)); }
    CORE=xray HY2_DOMAIN=hy2.example.com HY2_CERT_PUBKEY_SHA256_B64= singbox_hy2_tls_json | grep -q '"server_name": "hy2.example.com"' || { echo 'FAIL: Sing-box HY2 ACME TLS sample'; failures=$((failures + 1)); }
    CORE=singbox HY2_DOMAIN=hy2.example.com HY2_CERT_PUBKEY_SHA256_B64=abcdef singbox_hy2_tls_json | grep -q 'certificate_public_key_sha256' || { echo 'FAIL: Sing-box HY2 self-signed TLS sample'; failures=$((failures + 1)); }

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
        --status) show_status_report; exit 0 ;;
        --lang)
            ABOX_LANG_OVERRIDE="${2:-zh}"
            enter_runtime "$@"
            ABOX_LANG=$(normalize_lang "$ABOX_LANG_OVERRIDE")
            save_lang
            main_loop "$@"
            ;;
        --lang=*)
            ABOX_LANG_OVERRIDE="${1#--lang=}"
            enter_runtime "$@"
            ABOX_LANG=$(normalize_lang "$ABOX_LANG_OVERRIDE")
            save_lang
            main_loop "$@"
            ;;
        '') enter_runtime "$@"; main_loop "$@" ;;
        *) enter_runtime "$@"; main_loop "$@" ;;
    esac
}

main_loop() {
    detect_lang
    init_system_environment
    setup_shortcut
    GLOBAL_PUBLIC_IP=$(get_public_ip)
    while true; do
        local STATUS_STR='' CUR_MODE='' choice
        STATUS_STR=$(build_status_str)
        source "$ABOX_ENV" 2>/dev/null && CUR_MODE="[${CORE}-${MODE}]" || CUR_MODE=''
        clear
        msg "${BLUE}======================================================================${NC}"
        msg "${BOLD}${YELLOW}==============================A-Box===============================${NC}"
        msg "${BLUE}======================================================================${NC}"
        if [[ "${ABOX_LANG:-zh}" == 'en' ]]; then
            msg "Gateway: ${YELLOW}$GLOBAL_PUBLIC_IP${NC} | Core: $STATUS_STR $CUR_MODE"
            msg "${BLUE}----------------------------------------------------------------------${NC}"
            msg "${YELLOW}[ Xray-core Deployment ]${NC}              ${YELLOW}[ Sing-box Deployment ]${NC}"
            msg "${GREEN}1.${NC} VLESS-Vision-Reality               ${GREEN}6.${NC} VLESS-Vision-Reality"
            msg "${GREEN}2.${NC} VLESS-XHTTP-Reality                ${GREEN}7.${NC} Shadowsocks-2022"
            msg "${GREEN}3.${NC} Shadowsocks-2022                   ${GREEN}8.${NC} VLESS + SS-2022"
            msg "${GREEN}4.${NC} Hysteria 2 (Native/Apernet)        ${GREEN}9.${NC} Hysteria 2 (Sing-box)"
            msg "${GREEN}5.${NC} All-in-one (Xray+Hy2)             ${GREEN}10.${NC} All-in-one (Sing-box)"
            msg "${BLUE}----------------------------------------------------------------------${NC}"
            msg "${GREEN}11.${NC} Toolbox"
            msg "${GREEN}12.${NC} VPS One-click Optimization"
            msg "${GREEN}13.${NC} Display All Node Parameters"
            msg "${GREEN}14.${NC} Manual"
            msg "${GREEN}15.${NC} OTA, Geo & Core Upgrade"
            msg "${GREEN}16.${NC} Clean Uninstall"
            msg "${GREEN}17.${NC} Delete Nodes & Reinitialize Environment"
            msg "${GREEN}18.${NC} Monthly Traffic Limit"
            msg "${GREEN}19.${NC} SS-2022 Whitelist Manager"
            msg "${GREEN}20.${NC} Language"
            msg "${GREEN} 0.${NC} Exit"
            msg "${BLUE}======================================================================${NC}"
            read -r -ep "$(tr_msg main_command)" choice
        else
            msg "网关/Gateway: ${YELLOW}$GLOBAL_PUBLIC_IP${NC} | 核心/Core: $STATUS_STR $CUR_MODE"
            msg "${BLUE}----------------------------------------------------------------------${NC}"
            msg "${YELLOW}[ Xray-core 部署 ]${NC}                    ${YELLOW}[ Sing-box 部署 ]${NC}"
            msg "${GREEN}1.${NC} VLESS-Vision-Reality               ${GREEN}6.${NC} VLESS-Vision-Reality"
            msg "${GREEN}2.${NC} VLESS-XHTTP-Reality                ${GREEN}7.${NC} Shadowsocks-2022"
            msg "${GREEN}3.${NC} Shadowsocks-2022                   ${GREEN}8.${NC} VLESS + SS-2022"
            msg "${GREEN}4.${NC} Hysteria 2 (官方/Apernet)          ${GREEN}9.${NC} Hysteria 2 (Sing-box)"
            msg "${GREEN}5.${NC} 全协议四合一 (Xray+Hy2)           ${GREEN}10.${NC} 全协议三合一 (Sing-box)"
            msg "${BLUE}----------------------------------------------------------------------${NC}"
            msg "${GREEN}11.${NC} 综合工具箱"
            msg "${GREEN}12.${NC} VPS 一键优化"
            msg "${GREEN}13.${NC} 全部节点参数显示"
            msg "${GREEN}14.${NC} 脚本说明书"
            msg "${GREEN}15.${NC} 脚本 OTA、Xray Geo 与核心无损升级"
            msg "${GREEN}16.${NC} 一键全部清空卸载"
            msg "${GREEN}17.${NC} 删除全部节点与环境初始化"
            msg "${GREEN}18.${NC} 每月流量管控限制"
            msg "${GREEN}19.${NC} SS-2022 白名单 IP 管理"
            msg "${GREEN}20.${NC} 语言设置 / Language"
            msg "${GREEN} 0.${NC} 退出脚本"
            msg "${BLUE}======================================================================${NC}"
            read -r -ep "$(tr_msg main_command)" choice
        fi
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
            20) language_menu ;;
            0) clear; rm -f "$LOCK_FILE"; exit 0 ;;
            *) sleep 1 ;;
        esac
    done
}

main "$@"
