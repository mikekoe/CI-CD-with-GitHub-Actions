#!/usr/bin/env bash
# app.sh - DevOps helper tool.
#
# Usage: ./app/app.sh <command> [arguments]
#   system-info               Display system information
#   check-host <host>         Resolve a host and check it
#   check-port <host> <port>  Validate the port and check TCP connectivity
#   help                      Show usage
#
# Exit codes: 0 = success, 1 = a check failed, 2 = invalid input.

PROG="$(basename "$0")"

usage() {
    cat << USAGE_TEXT
Usage: $PROG <command> [arguments]

Commands:
  system-info                 Display system information (OS, kernel, uptime, CPU, memory, disk)
  check-host <host>           Resolve a host name and check it with ping
  check-port <host> <port>    Validate the port (1-65535) and check TCP connectivity
  help                        Show this help

Exit codes:
  0   success
  1   a check failed (host did not resolve, port closed)
  2   invalid input (unknown command, missing or invalid arguments)

Examples:
  $PROG system-info
  $PROG check-host example.com
  $PROG check-port example.com 443
USAGE_TEXT
}

# Print an error and exit 2 (invalid input).
die_usage() {
    echo "Error: $1" >&2
    echo "Run '$PROG help' for usage." >&2
    exit 2
}

section() { printf '\n=== %s ===\n' "$1"; }
row()     { printf '%-18s : %s\n' "$1" "$2"; }

fmt_duration() {   # seconds -> "Xd Yh Zm"
    local s=$1
    printf '%dd %dh %dm' $((s/86400)) $((s%86400/3600)) $((s%3600/60))
}

# --------------------------- validation helpers ---------------------------
valid_host() {
    local h="$1"
    [ -n "$h" ] && [ "${#h}" -le 253 ] || return 1
    [[ "$h" =~ ^[A-Za-z0-9]([A-Za-z0-9.-]*[A-Za-z0-9])?$ ]] && return 0   # hostname / IPv4
    [[ "$h" =~ ^[0-9A-Fa-f:]*:[0-9A-Fa-f:]*$ ]] && return 0               # IPv6
    return 1
}

# Validates a port argument, or exits 2 with a specific message.
require_valid_port() {
    local p="$1"
    if ! [[ "$p" =~ ^[0-9]+$ ]]; then
        die_usage "port must be a number, got '$p'."
    fi
    if [ "${#p}" -gt 5 ] || [ "$((10#$p))" -lt 1 ] || [ "$((10#$p))" -gt 65535 ]; then
        die_usage "port must be between 1 and 65535, got '$p'."
    fi
}

resolve_host() {
    local h="$1" ip=""
    if [[ "$h" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]] || [[ "$h" == *:* ]]; then
        echo "$h"; return 0
    fi
    if command -v getent >/dev/null 2>&1; then
        ip="$(getent ahosts "$h" 2>/dev/null | awk 'NR==1 {print $1}')"
    fi
    if [ -z "$ip" ] && command -v dscacheutil >/dev/null 2>&1; then
        ip="$(dscacheutil -q host -a name "$h" 2>/dev/null | awk '/^(ip_address|ipv6_address):/ {print $2; exit}')"
    fi
    if [ -z "$ip" ] && command -v host >/dev/null 2>&1; then
        ip="$(host "$h" 2>/dev/null | awk '/has (IPv6 )?address/ {print $NF; exit}')"
    fi
    [ -n "$ip" ] && echo "$ip"
}

# ------------------------------ system-info ------------------------------
cmd_system_info() {
    [ $# -eq 0 ] || die_usage "'system-info' takes no arguments."

    local os up="Unavailable" cpu="Unavailable" cores="Unavailable"
    local load="Unavailable" mem_total="Unavailable" mem_used="Unavailable" mem_avail="Unavailable"
    local container="no"
    os="$(uname -s)"

    if [ -r /etc/os-release ]; then
        # shellcheck source=/dev/null
        os="$(. /etc/os-release && echo "${PRETTY_NAME:-${NAME:-$os}}")"
    fi
    if [ -r /proc/uptime ]; then
        up="$(fmt_duration "$(cut -d. -f1 /proc/uptime)")"
    fi
    if [ -r /proc/cpuinfo ]; then
        cpu="$(grep -m1 'model name' /proc/cpuinfo | cut -d: -f2- | sed 's/^ *//')"
        [ -n "$cpu" ] || cpu="Unavailable"
    fi
    cores="$(nproc 2>/dev/null || getconf _NPROCESSORS_ONLN 2>/dev/null || echo Unavailable)"
    if [ -r /proc/loadavg ]; then
        load="$(cut -d' ' -f1-3 /proc/loadavg)"
    fi
    if [ -r /proc/meminfo ]; then
        local total_kb avail_kb
        total_kb="$(awk '/^MemTotal:/ {print $2}' /proc/meminfo)"
        avail_kb="$(awk '/^MemAvailable:/ {print $2}' /proc/meminfo)"
        if [ -n "$total_kb" ] && [ -n "$avail_kb" ]; then
            local used_kb=$((total_kb - avail_kb))
            mem_total="$((total_kb/1024)) MiB"
            mem_used="$((used_kb/1024)) MiB ($((used_kb*100/total_kb))%)"
            mem_avail="$((avail_kb/1024)) MiB"
        fi
    fi
    if [ -f /.dockerenv ] || grep -qaE 'docker|containerd|kubepods' /proc/1/cgroup 2>/dev/null; then
        container="yes"
    fi

    section "System information"
    row "Hostname"          "$(hostname)"
    row "Current user"      "$(id -un 2>/dev/null || whoami)"
    row "Date/time"         "$(date '+%Y-%m-%d %H:%M:%S %Z')"
    row "Operating system"  "$os"
    row "Kernel"            "$(uname -r)"
    row "Architecture"      "$(uname -m)"
    row "Uptime"            "$up"
    row "Load average"      "$load"
    row "Running in Docker" "$container"

    section "CPU"
    row "Model"             "$cpu"
    row "Cores"             "$cores"

    section "Memory"
    row "Total"             "$mem_total"
    row "Used"              "$mem_used"
    row "Available"         "$mem_avail"

    section "Disk (/)"
    local line
    line="$(df -hP / 2>/dev/null | awk 'NR==2 {print $2" "$3" "$4" "$5}')"
    if [ -n "$line" ]; then
        # shellcheck disable=SC2086
        set -- $line
        row "Size"      "$1"
        row "Used"      "$2"
        row "Available" "$3"
        row "Use%"      "$4"
    else
        row "Disk" "Unavailable"
    fi
    return 0
}

# ------------------------------- check-host -------------------------------
# Success (0) means the host name resolves. The ping result is reported for
# information only, because many hosts block ICMP.
cmd_check_host() {
    [ $# -ge 1 ] || die_usage "'check-host' requires a <host> argument."
    [ $# -le 1 ] || die_usage "'check-host' takes exactly one <host> argument."
    local host="$1" addr
    valid_host "$host" || die_usage "'$host' is not a valid hostname or IP address."

    section "Host check: $host"
    addr="$(resolve_host "$host")"
    if [ -z "$addr" ]; then
        row "Resolution" "FAILED"
        row "Result"     "UNRESOLVED"
        return 1
    fi
    row "Host"             "$host"
    row "Resolved address" "$addr"

    if command -v ping >/dev/null 2>&1; then
        local ping_cmd=(ping -c 1 -W 3 "$addr")
        [ "$(uname -s)" = "Darwin" ] && ping_cmd=(ping -c 1 -t 3 "$addr")
        if "${ping_cmd[@]}" >/dev/null 2>&1; then
            row "Ping" "reply received"
        else
            row "Ping" "no reply (host may block ICMP)"
        fi
    else
        row "Ping" "skipped (ping not installed)"
    fi
    row "Result" "RESOLVED"
    return 0
}

# ------------------------------- check-port -------------------------------
cmd_check_port() {
    [ $# -ge 1 ] || die_usage "'check-port' requires <host> and <port> arguments."
    [ $# -ge 2 ] || die_usage "'check-port' requires a <port> argument."
    [ $# -le 2 ] || die_usage "'check-port' takes exactly <host> and <port>."
    local host="$1" port="$2" addr
    valid_host "$host" || die_usage "'$host' is not a valid hostname or IP address."
    require_valid_port "$port"
    port=$((10#$port))

    section "Port check: $host:$port"
    addr="$(resolve_host "$host")"
    if [ -z "$addr" ]; then
        row "Resolution" "FAILED"
        row "Result"     "UNRESOLVED"
        return 1
    fi
    row "Host"             "$host"
    row "Resolved address" "$addr"
    row "Port"             "$port"

    local rc
    if command -v nc >/dev/null 2>&1; then
        nc -z -w 3 "$addr" "$port" >/dev/null 2>&1
        rc=$?
    elif command -v timeout >/dev/null 2>&1; then
        timeout 3 bash -c "exec 3<>/dev/tcp/$addr/$port" >/dev/null 2>&1
        rc=$?
    else
        row "TCP" "cannot test (neither nc nor timeout is installed)"
        return 1
    fi

    if [ "$rc" -eq 0 ]; then
        row "TCP" "open"
        row "Result" "OPEN"
        return 0
    fi
    row "TCP" "closed or unreachable"
    row "Result" "CLOSED"
    return 1
}

# ---------------------------------- main ----------------------------------
main() {
    [ $# -ge 1 ] || { echo "Error: missing command." >&2; usage >&2; exit 2; }
    local cmd="$1"; shift
    case "$cmd" in
        system-info)     cmd_system_info "$@" ;;
        check-host)      cmd_check_host "$@" ;;
        check-port)      cmd_check_port "$@" ;;
        help|-h|--help)  usage ;;
        *)               echo "Error: unknown command '$cmd'." >&2; usage >&2; exit 2 ;;
    esac
}

main "$@"
if [ then
