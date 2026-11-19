#!/usr/bin/env bash

set -u
shopt -s nullglob

CONF=/proc/sys/net/ipv6/conf

# 只在终端里显示颜色，避免日志里出现转义字符。
red='' green='' yellow='' cyan='' reset=''
if [[ -t 1 && ${TERM:-dumb} != dumb && -z ${NO_COLOR:-} ]]; then
    red=$'\033[31m'
    green=$'\033[32m'
    yellow=$'\033[33m'
    cyan=$'\033[36m'
    reset=$'\033[0m'
fi

say() {
    printf '%s%s%s\n' "$1" "$2" "$reset"
}

die() {
    printf '错误：%s\n' "$*" >&2
    exit 1
}

usage() {
    printf '用法：bash %s [on|off|toggle|status|menu]\n' "$0"
    printf '不带参数打开菜单；查看状态无需 root，开启或关闭需要 root。\n'
}

detect_os() {
    [[ $(uname -s) == Linux ]] || die '此脚本只支持 Linux。'

    local ID='' VERSION_ID='' PRETTY_NAME='' major
    if [[ -r /etc/os-release ]]; then
        . /etc/os-release
    elif [[ -r /usr/lib/os-release ]]; then
        . /usr/lib/os-release
    else
        die '找不到 os-release，无法识别系统。'
    fi

    say "$cyan" '========== IPv6 临时开关 =========='
    printf '系统：%s（版本 %s）\n' "${PRETTY_NAME:-${ID:-未知}}" "${VERSION_ID:-未知}"
    printf '内核：%s\n\n' "$(uname -r)"

    case "$ID:$VERSION_ID" in
        debian:11|debian:12|debian:13|\
        ubuntu:20.04|ubuntu:22.04|ubuntu:24.04|ubuntu:26.04)
            return 0 ;;
    esac

    major=${VERSION_ID%%.*}
    case "$ID:$major" in
        rhel:[89]|rhel:10|rocky:[89]|rocky:10|\
        almalinux:[89]|almalinux:10|ol:[89]|ol:10|\
        centos:[89]|centos:10)
            return 0 ;;
    esac

    die '该系统或版本不在支持列表中，未修改任何设置。'
}

# 逐个读取现有网卡，不用 all 的读数判断整机状态。
scan_interfaces() {
    local path name value enabled=0 disabled=0

    for path in "$CONF"/*/disable_ipv6; do
        name=${path%/disable_ipv6}
        name=${name##*/}
        case "$name" in all|default) continue ;; esac

        IFS= read -r value < "$path" || return 1
        case "$value" in
            0) enabled=$((enabled + 1)) ;;
            1) disabled=$((disabled + 1)) ;;
            *) return 1 ;;
        esac
    done

    if (( enabled > 0 && disabled > 0 )); then
        printf 'mixed\n'
    elif (( enabled > 0 )); then
        printf 'on\n'
    elif (( disabled > 0 )); then
        printf 'off\n'
    else
        return 1
    fi
}

show_status() {
    local state=$1 addresses index iface family address rest

    addresses=$(ip -6 -o addr show scope global) ||
        die '无法查询 IPv6 地址。'

    case "$state" in
        on)    say "$green"  'IPv6 开关：已开启' ;;
        off)   say "$red"    'IPv6 开关：已关闭' ;;
        mixed) say "$yellow" 'IPv6 开关：部分网卡开启、部分关闭' ;;
    esac

    if [[ -n $addresses ]]; then
        say "$green" '全局 IPv6 地址：有'
        while read -r index iface family address rest; do
            [[ $family == inet6 ]] && printf '  %s  %s\n' "$iface" "$address"
        done <<< "$addresses"
    else
        say "$red" '全局 IPv6 地址：没有'
        if [[ $state != off ]]; then
            say "$yellow" 'IPv6 功能已开启，但没有全局地址。若刚从关闭恢复，原有地址可能需要由系统网络服务重新配置。'
        fi
    fi
}

set_ipv6() {
    local value=$1 expected state default

    (( EUID == 0 )) || die '修改需要 root，请用 sudo bash ipv6-toggle.sh 运行。'

    if [[ $value == 0 ]]; then
        expected=on
    else
        expected=off
    fi

    # default 用于之后新建的网卡，all 用于当前网卡。
    printf '%s\n' "$value" > "$CONF/default/disable_ipv6" ||
        die '无法修改新建网卡的默认设置，容器或受限 VPS 可能禁止写入。'
    printf '%s\n' "$value" > "$CONF/all/disable_ipv6" ||
        die '默认设置已改，但无法修改当前网卡。请运行 status 检查。'

    state=$(scan_interfaces) || die '已写入，但无法核对当前网卡状态。'
    IFS= read -r default < "$CONF/default/disable_ipv6" ||
        die '已写入，但无法核对新建网卡的默认设置。'
    [[ $state == "$expected" && $default == "$value" ]] ||
        die '写入后状态与预期不符，请运行 status 检查。'

    printf '\n'
    show_status "$state"
    printf '\n未修改配置文件，也未重启网络服务。重启后以系统原有配置为准。\n'
}

show_menu() {
    local state=$1 choice first

    show_status "$state"
    printf '\n'
    case "$state" in
        on)
            first=off
            say "$red" '1. 临时关闭 IPv6'
            ;;
        off)
            first=on
            say "$green" '1. 临时开启 IPv6'
            ;;
        mixed)
            first=on
            say "$green" '1. 临时开启所有网卡的 IPv6'
            say "$red"   '2. 临时关闭所有网卡的 IPv6'
            ;;
    esac
    printf '0. 退出\n'

    read -r -p '请选择：' choice || return 1
    case "$choice" in
        0) return 0 ;;
        1)
            if [[ $first == on ]]; then
                set_ipv6 0
            else
                set_ipv6 1
            fi
            ;;
        2)
            [[ $state == mixed ]] || die '无效选项。'
            set_ipv6 1
            ;;
        *) die '无效选项。' ;;
    esac
}

main() {
    local action=${1:-menu} state

    (( $# <= 1 )) || die '只接受一个参数，使用 --help 查看用法。'
    case "$action" in
        -h|--help) usage; return 0 ;;
        on|off|toggle|status|menu) ;;
        *) usage >&2; exit 1 ;;
    esac

    detect_os
    [[ -r "$CONF/all/disable_ipv6" && -r "$CONF/default/disable_ipv6" ]] ||
        die '找不到 IPv6 运行时开关。IPv6 可能已在内核启动时禁用，或当前环境未提供该接口。'
    command -v ip >/dev/null 2>&1 ||
        die '找不到 ip 命令，请先安装 iproute2。'
    state=$(scan_interfaces) || die '无法读取当前网卡的 IPv6 状态。'

    case "$action" in
        menu)
            [[ -t 0 ]] || die '菜单需要在终端运行，请先下载脚本，或显式传入 on、off、status。'
            show_menu "$state"
            ;;
        status) show_status "$state" ;;
        on)     set_ipv6 0 ;;
        off)    set_ipv6 1 ;;
        toggle)
            case "$state" in
                on)    set_ipv6 1 ;;
                off)   set_ipv6 0 ;;
                mixed) die '网卡状态不一致，请明确指定 on 或 off。' ;;
            esac
            ;;
    esac
}

main "$@"
