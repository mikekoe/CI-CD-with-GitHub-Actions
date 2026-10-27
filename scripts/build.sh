#!/usr/bin/env bash
# build.sh - Build the Docker image and run smoke tests against it.
#
# Usage: ./scripts/build.sh
# Exit code: 0 if the build and all smoke tests pass, 1 otherwise.

cd "$(dirname "${BASH_SOURCE[0]}")/.." || exit 1

IMAGE="devops-tool"
PASS=0
FAIL=0

pass() { echo "  PASS: $1"; PASS=$((PASS+1)); }
fail() { echo "  FAIL: $1"; FAIL=$((FAIL+1)); }

# smoke "description" expected_exit "regex or empty" docker-args...
smoke() {
    local desc="$1" want="$2" pattern="$3"; shift 3
    local out rc
    out="$(docker run --rm "$@" 2>&1)"; rc=$?
    if [ "$rc" -ne "$want" ]; then
        fail "$desc (expected exit $want, got $rc)"
    elif [ -n "$pattern" ] && ! grep -qiE "$pattern" <<< "$out"; then
        fail "$desc (output did not match '$pattern')"
    else
        pass "$desc"
    fi
}

if ! command -v docker >/dev/null 2>&1; then
    echo "Error: docker is not installed." >&2
    exit 1
fi
if ! docker info >/dev/null 2>&1; then
    echo "Error: the Docker daemon is not running. Start Docker and try again." >&2
    exit 1
fi

echo "== Build =="
if docker build -t "$IMAGE" .; then
    pass "docker build -t $IMAGE ."
else
    fail "docker build -t $IMAGE ."
    echo
    echo "Build failed; skipping smoke tests."
    exit 1
fi

echo
echo "== Smoke tests =="
smoke "help"                              0 "usage"           "$IMAGE" help
smoke "default command shows help"        0 "usage"           "$IMAGE"
smoke "system-info"                       0 "hostname"        "$IMAGE" system-info
smoke "system-info runs inside Docker"    0 "running in docker +: yes" "$IMAGE" system-info
smoke "invalid command exits 2"           2 "unknown command" "$IMAGE" not-a-command
smoke "check-host without host exits 2"   2 "requires a <host>" "$IMAGE" check-host
smoke "check-port without port exits 2"   2 "requires a <port>" "$IMAGE" check-port localhost
smoke "check-port rejects bad port"       2 "between 1 and 65535" "$IMAGE" check-port localhost 99999
smoke "check-host localhost"              0 "resolved"        "$IMAGE" check-host localhost
smoke "runs as a non-root user"           0 "^devops$"        --entrypoint id "$IMAGE" -un
smoke "works with a read-only filesystem" 0 "usage"           --read-only "$IMAGE" help

echo
echo "Passed: $PASS   Failed: $FAIL"
[ "$FAIL" -eq 0 ]
