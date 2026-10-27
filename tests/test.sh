#!/usr/bin/env bash
# test.sh - Tests for app/app.sh.
#
# Covers: help, system-info, invalid commands, missing host, a valid host,
# missing port, non-numeric port, out-of-range ports, closed and open ports.
#
# Usage: ./tests/test.sh
# Exit code: 0 if no test failed, 1 otherwise.

cd "$(dirname "${BASH_SOURCE[0]}")/.." || exit 1

APP=(bash app/app.sh)
PASS=0
FAIL=0
SKIP=0
LISTENER_PID=""

pass() { echo "  PASS: $1"; PASS=$((PASS+1)); }
fail() { echo "  FAIL: $1"; FAIL=$((FAIL+1)); }
skip() { echo "  SKIP: $1"; SKIP=$((SKIP+1)); }

cleanup() {
    if [ -n "$LISTENER_PID" ]; then
        kill "$LISTENER_PID" 2>/dev/null
        wait "$LISTENER_PID" 2>/dev/null
    fi
}
trap cleanup EXIT

# check "description" expected_exit "regex or empty" args...
check() {
    local desc="$1" want="$2" pattern="$3"; shift 3
    local out rc
    out="$("${APP[@]}" "$@" 2>&1)"; rc=$?
    if [ "$rc" -ne "$want" ]; then
        fail "$desc (expected exit $want, got $rc)"
    elif [ -n "$pattern" ] && ! grep -qiE "$pattern" <<< "$out"; then
        fail "$desc (output did not match '$pattern')"
    else
        pass "$desc"
    fi
}

echo "Tests for app/app.sh"
echo "===================="

echo
echo "== help =="
check "help shows usage"                      0 "usage"                "help"
check "--help shows usage"                    0 "usage"                "--help"
check "help lists system-info"                0 "system-info"          "help"
check "help lists check-host"                 0 "check-host <host>"    "help"
check "help lists check-port"                 0 "check-port <host> <port>" "help"

echo
echo "== system-info =="
check "system-info shows hostname"            0 "hostname"             "system-info"
check "system-info shows kernel"              0 "kernel"               "system-info"
check "system-info shows memory"               0 "=== Memory"          "system-info"
check "system-info shows disk usage"          0 "=== Disk"            "system-info"
check "system-info rejects extra arguments"   2 "no arguments"         "system-info" "extra"

echo
echo "== invalid commands =="
check "unknown command exits 2"               2 "unknown command"      "not-a-command"
check "no command exits 2"                    2 "missing command"
check "old-style command name exits 2"        2 "unknown command"      "system"

echo
echo "== check-host =="
check "missing host exits 2"                  2 "requires a <host>"    "check-host"
check "too many arguments exits 2"            2 "exactly one"          "check-host" "a" "b"
check "invalid host exits 2"                  2 "not a valid"          "check-host" "bad host!"
check "host starting with '-' exits 2"        2 "not a valid"          "check-host" "-bad"
check "valid host (localhost) succeeds"       0 "resolved"             "check-host" "localhost"
check "valid IP address succeeds"             0 "127.0.0.1"            "check-host" "127.0.0.1"
check "unresolvable host exits 1"             1 "unresolved"           "check-host" "nosuchhost.invalid"

echo
echo "== check-port: input validation =="
check "missing host and port exits 2"         2 "requires <host> and <port>" "check-port"
check "missing port exits 2"                  2 "requires a <port>"    "check-port" "localhost"
check "non-numeric port exits 2"              2 "must be a number"     "check-port" "localhost" "abc"
check "negative port exits 2"                 2 "must be a number"     "check-port" "localhost" "-1"
check "port 0 is out of range (exit 2)"       2 "between 1 and 65535"  "check-port" "localhost" "0"
check "port 65536 is out of range (exit 2)"   2 "between 1 and 65535"  "check-port" "localhost" "65536"
check "port 99999 is out of range (exit 2)"   2 "between 1 and 65535"  "check-port" "localhost" "99999"
check "invalid host exits 2"                  2 "not a valid"          "check-port" "bad host!" "80"
check "too many arguments exits 2"            2 "exactly"              "check-port" "localhost" "80" "extra"

echo
echo "== check-port: connectivity =="
check "closed port exits 1"                   1 "closed"               "check-port" "127.0.0.1" "1"
check "unresolvable host exits 1"             1 "unresolved"           "check-port" "nosuchhost.invalid" "80"

if command -v python3 >/dev/null 2>&1; then
    PORT="$(python3 -c 'import socket; s=socket.socket(); s.bind(("127.0.0.1", 0)); print(s.getsockname()[1]); s.close()')"
    python3 -m http.server "$PORT" --bind 127.0.0.1 >/dev/null 2>&1 &
    LISTENER_PID=$!
    # wait up to ~5 seconds for the listener to accept connections
    for _ in 1 2 3 4 5 6 7 8 9 10; do
        if (exec 3<>"/dev/tcp/127.0.0.1/$PORT") 2>/dev/null; then break; fi
        sleep 0.5
    done
    check "open port exits 0"                 0 "open"                 "check-port" "127.0.0.1" "$PORT"
else
    skip "open port test (python3 is not installed)"
fi

echo
echo "===================="
echo "Passed: $PASS   Failed: $FAIL   Skipped: $SKIP"
[ "$FAIL" -eq 0 ]
