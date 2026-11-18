#!/usr/bin/env bash

set -u
shopt -s nullglob

CONF=/proc/sys/net/ipv6/conf

die() {
    printf '错误：%s\n' "$*" >&2
    exit 1
}

usage() {
    printf '用法：bash %s [on|off|toggle|status|menu]\n' "$0"
    printf '不带参数打开菜单。修改需要 root，查看状态不需要。\n'
}

detect_os() {
    [[ $(uname -s) == Linux ]] || die '此脚本只支持 Linux。'

    local ID='' VERSION_ID='' PRETTY_NAME=''
    local major

    if [[ -r /etc/os-release ]]; then
        . /etc/os-release
    elif [[ -r /usr/lib/os-release ]]; then
        . /usr/lib/os-release
    else
        die '找不到 os-release，无法识别发行版。'
    fi

    printf '系统：%s（ID=%s，版本=%s）\n' \
        "${PRETTY_NAME:-未知}" "${ID:-未知}" "${VERSION_ID:-未知}"
    printf '内核：%s\n' "$(uname -r)"

    major=${VERSION_ID%%.*}
    case "$ID:$VERSION_ID" in
        debian:11|debian:12|debian:13|\
        ubuntu:20.04|ubuntu:22.04|ubuntu:24.04|ubuntu:26.04)
            return 0
            ;;
    esac

    case "$ID:$major" in
        rhel:[89]|rhel:10|rocky:[89]|rocky:10|\
        almalinux:[89]|almalinux:10|ol:[89]|ol:10|\
        centos:[89]|centos:10)
            return 0
            ;;
    esac

    die '该系统或版本不在支持列表中，未修改任何设置。'
}

# 逐个读取现有网卡，不用 all 的读数判断整机状态。
# 0 = 全部开启，1 = 全部关闭，mixed = 状态混合。
scan_interfaces() {
    local path name value
    local enabled=0 disabled=0

    for path in "$CONF"/*/disable_ipv6; do
        name=${path%/disable_ipv6}
        name=${name##*/}
        case "$name" in all|default) continue ;; esac

        if ! IFS= read -r value < "$path"; then
            printf '无法读取接口 %s 的 IPv6 状态。\n' "$name" >&2
            return 1
        fi

        case "$value" in
            0) enabled=$((enabled + 1)) ;;
            1) disabled=$((disabled + 1)) ;;
            *) return 1 ;;
        esac

        if [[ ${1:-} == detail ]]; then
            if [[ $value == 0 ]]; then
                printf '  %s：开启\n' "$name" >&2
            else
                printf '  %s：关闭\n' "$name" >&2
            fi
        fi
    done

    if (( enabled > 0 && disabled == 0 )); then
        printf '0\n'
    elif (( disabled > 0 && enabled == 0 )); then
        printf '1\n'
    elif (( enabled > 0 && disabled > 0 )); then
        printf 'mixed\n'
    else
        return 1
    fi
}

show_status() {
    local state default

    state=$(scan_interfaces) || die '无法判断当前网卡状态。'
    IFS= read -r default < "$CONF/default/disable_ipv6" ||
        die '无法读取新建网卡的默认设置。'

    case "$state" in
        0)     printf '当前网卡：IPv6 全部开启\n' ;;
        1)     printf '当前网卡：IPv6 全部关闭\n' ;;
        mixed)
            printf '当前网卡：部分开启、部分关闭\n'
            scan_interfaces detail >/dev/null || die '无法读取网卡明细。'
            ;;
    esac

    case "$default" in
        0) printf '新建网卡的内核默认设置：开启 IPv6\n' ;;
        1) printf '新建网卡的内核默认设置：关闭 IPv6\n' ;;
        *) printf '新建网卡的内核默认设置：未知\n' ;;
    esac

    if command -v ip >/dev/null 2>&1; then
        printf '\n当前全局范围的 IPv6 地址（无输出表示没有）：\n'
        ip -6 -brief address show scope global
    fi
}

set_ipv6() {
    local wanted=$1 state default

    (( EUID == 0 )) || die '修改需要 root，请用 sudo bash ipv6-toggle.sh on 或 off。'

    # default 影响随后新建的接口，all 一次应用到当前接口。
    if ! printf '%s\n' "$wanted" > "$CONF/default/disable_ipv6"; then
        die '无法修改默认设置。容器或受限环境可能禁止写入。'
    fi

    if ! printf '%s\n' "$wanted" > "$CONF/all/disable_ipv6"; then
        die '默认设置已写入，但无法修改现有网卡。请运行 status 检查。'
    fi

    state=$(scan_interfaces) || die '已写入设置，但无法核对网卡状态。'
    IFS= read -r default < "$CONF/default/disable_ipv6" ||
        die '已写入设置，但无法核对默认状态。'

    if [[ $state != "$wanted" || $default != "$wanted" ]]; then
        die '写入后状态与预期不一致，请运行 status 检查。'
    fi

    if [[ $wanted == 0 ]]; then
        printf 'IPv6 已临时开启。能否获得公网 IPv6 地址，取决于服务商和网络配置。\n'
    else
        printf 'IPv6 已临时关闭。\n'
    fi
    printf '未修改配置文件，重启后由系统原有配置决定。\n'
}

main() {
    local action=${1:-menu} choice state

    (( $# <= 1 )) || die '只接受一个参数，使用 --help 查看用法。'
    case "$action" in
        -h|--help) usage; return 0 ;;
        on|off|toggle|status|menu) ;;
        *) usage >&2; exit 1 ;;
    esac

    detect_os
    [[ -r "$CONF/all/disable_ipv6" && -r "$CONF/default/disable_ipv6" ]] ||
        die '找不到 IPv6 运行时开关。IPv6 可能已在内核启动时禁用，或当前环境未提供该接口。'

    if [[ $action == menu ]]; then
        [[ -t 0 ]] || die '菜单需要在终端运行，请先下载脚本，或显式传入 on、off、status。'
        printf '\n1. 开启 IPv6\n2. 关闭 IPv6\n3. 查看状态\n0. 退出\n'
        read -r -p '请选择 [0-3]：' choice || return 1
        case "$choice" in
            1) action=on ;;
            2) action=off ;;
            3) action=status ;;
            0) return 0 ;;
            *) die '无效选项。' ;;
        esac
    fi

    case "$action" in
        on) set_ipv6 0 ;;
        off) set_ipv6 1 ;;
        status) show_status ;;
        toggle)
            state=$(scan_interfaces) || die '无法判断当前网卡状态。'
            case "$state" in
                0) set_ipv6 1 ;;
                1) set_ipv6 0 ;;
                mixed) die '网卡状态不一致，请明确指定 on 或 off。' ;;
            esac
            ;;
    esac
}

main "$@"
