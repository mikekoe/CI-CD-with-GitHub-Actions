#!/usr/bin/env bash
# grade.sh - Checks the repository against the assignment requirements.
#
# Checks: repository structure, Bash syntax, executable permissions, workflow
# triggers, required jobs, job dependencies, application behaviour, linting,
# Docker build and smoke tests, the test suite and basic git history.
#
# Usage: chmod +x grade.sh app/*.sh scripts/*.sh tests/*.sh   (once)
#        ./grade.sh
# Exit code: 0 if no check failed, 1 otherwise.

cd "$(dirname "${BASH_SOURCE[0]}")" || exit 1

WF=.github/workflows/ci.yml
PASS=0
FAIL=0
SKIP=0

pass() { echo "PASS: $1"; PASS=$((PASS+1)); }
fail() { echo "FAIL: $1"; FAIL=$((FAIL+1)); }
skip() { echo "SKIP: $1"; SKIP=$((SKIP+1)); }

# has "description" "regex" file
has() {
    if [ -f "$3" ] && grep -qiE "$2" "$3"; then pass "$1"; else fail "$1"; fi
}

# expect "description" expected_exit "regex or empty" command...
expect() {
    local desc="$1" want="$2" pattern="$3"; shift 3
    local out rc
    out="$("$@" 2>&1)"; rc=$?
    if [ "$rc" -ne "$want" ]; then
        fail "$desc (expected exit $want, got $rc)"
    elif [ -n "$pattern" ] && ! grep -qiE "$pattern" <<< "$out"; then
        fail "$desc (output did not match '$pattern')"
    else
        pass "$desc"
    fi
}

# job_needs <job> : prints the 'needs:' value of a workflow job (empty if none)
job_needs() {
    awk -v job="$1" '
        $0 ~ "^  " job ":" {f=1; next}
        f && /^  [A-Za-z0-9_-]+:/ {f=0}
        f && /^    needs:/ {sub(/^    needs:[ ]*/, ""); print; exit}
    ' "$WF" 2>/dev/null
}

DOCKER_OK=0
if command -v docker >/dev/null 2>&1 && docker info >/dev/null 2>&1; then DOCKER_OK=1; fi

SCRIPTS=(grade.sh app/app.sh scripts/lint.sh scripts/build.sh tests/test.sh)

echo "================================="
echo "Grader"
echo "================================="

# ---------- Repository structure ----------
echo
echo "-- Repository structure --"
for f in README.md app/app.sh scripts/lint.sh scripts/build.sh tests/test.sh .github/workflows/ci.yml Dockerfile compose.yaml .dockerignore grade.sh; do
    if [ -f "$f" ]; then pass "Required file exists: $f"; else fail "Missing required file: $f"; fi
done
for f in README.md Dockerfile compose.yaml .dockerignore; do
    if [ -s "$f" ]; then pass "Not empty: $f"; else fail "Empty or missing: $f"; fi
done

# ---------- Bash syntax ----------
echo
echo "-- Bash syntax --"
for f in "${SCRIPTS[@]}"; do
    [ -f "$f" ] || continue
    if head -1 "$f" | grep -q '^#!.*bash'; then pass "Has bash shebang: $f"; else fail "No bash shebang: $f"; fi
    if bash -n "$f" 2>/dev/null; then pass "Valid syntax: $f"; else fail "Syntax error: $f"; fi
done

# ---------- Executable permissions ----------
echo
echo "-- Executable permissions (chmod +x grade.sh app/*.sh scripts/*.sh tests/*.sh) --"
for f in "${SCRIPTS[@]}"; do
    if [ -x "$f" ]; then pass "Executable: $f"; else fail "Not executable: $f"; fi
done

# ---------- Workflow ----------
echo
echo "-- GitHub Actions workflow ($WF) --"
has "Runs on push"                        '^  push:'                      "$WF"
has "Runs on pull_request"                '^  pull_request:'              "$WF"
for j in validate test docker; do
    has "Job defined: $j"                 "^  $j:"                        "$WF"
done
if [ -f "$WF" ] && [ -z "$(job_needs validate)" ]; then
    pass "validate has no dependency (runs first)"
else
    fail "validate has no dependency (runs first)"
fi
if job_needs test | grep -q 'validate'; then pass "test needs: validate"; else fail "test needs: validate"; fi
if job_needs docker | grep -q 'test'; then pass "docker needs: test"; else fail "docker needs: test"; fi
has "validate job runs scripts/lint.sh"   'scripts/lint\.sh'              "$WF"
has "test job runs tests/test.sh"         'tests/test\.sh'                "$WF"
has "docker job runs scripts/build.sh"    'scripts/build\.sh'             "$WF"
if command -v python3 >/dev/null 2>&1 && python3 -c 'import yaml' 2>/dev/null; then
    if python3 -c 'import sys, yaml; yaml.safe_load(open(sys.argv[1]))' "$WF" 2>/dev/null; then
        pass "Workflow is valid YAML"
    else
        fail "Workflow is valid YAML"
    fi
else
    skip "YAML validation (python3 with PyYAML not available)"
fi

# ---------- Application behaviour ----------
echo
echo "-- Application behaviour (./app/app.sh) --"
APP=(bash app/app.sh)
expect "help"                                  0 "usage"           "${APP[@]}" help
expect "system-info"                           0 "hostname"        "${APP[@]}" system-info
expect "check-host localhost"                  0 "resolved"        "${APP[@]}" check-host localhost
expect "check-host without host -> exit 2"     2 "requires a <host>" "${APP[@]}" check-host
expect "check-port without port -> exit 2"     2 "requires a <port>" "${APP[@]}" check-port localhost
expect "check-port non-numeric port -> exit 2" 2 "must be a number"  "${APP[@]}" check-port localhost abc
expect "check-port port 65536 -> exit 2"       2 "between 1 and 65535" "${APP[@]}" check-port localhost 65536
expect "invalid command -> exit 2"             2 "unknown command" "${APP[@]}" bogus

# ---------- Linting ----------
echo
echo "-- Linting (scripts/lint.sh) --"
if [ -f scripts/lint.sh ]; then
    if bash scripts/lint.sh >/tmp/grade-lint.log 2>&1; then
        pass "scripts/lint.sh passes"
    else
        fail "scripts/lint.sh reported problems:"
        grep -E 'FAIL|^[^ ]' /tmp/grade-lint.log | sed 's/^/    /' | head -15
    fi
else
    fail "scripts/lint.sh not found"
fi

# ---------- Test suite ----------
echo
echo "-- Test suite (tests/test.sh) --"
if [ -f tests/test.sh ]; then
    n_tests="$(grep -cE '^[[:space:]]*check "' tests/test.sh)"
    if [ "$n_tests" -ge 8 ]; then pass "At least 8 tests defined (found $n_tests)"; else fail "At least 8 tests defined (found $n_tests)"; fi
    if bash tests/test.sh >/tmp/grade-test.log 2>&1; then
        pass "tests/test.sh passes ($(grep -E '^Passed:' /tmp/grade-test.log))"
    else
        fail "tests/test.sh reported failures:"
        grep 'FAIL' /tmp/grade-test.log | sed 's/^/    /'
    fi
else
    fail "tests/test.sh not found"
fi

# ---------- Docker ----------
echo
echo "-- Docker build and smoke tests --"
has "Dockerfile has FROM"                 '^FROM '                        Dockerfile
has "Dockerfile copies app/"              '^COPY +app/?'                  Dockerfile
has "Dockerfile sets permissions (chmod)" 'chmod'                         Dockerfile
has "Dockerfile has ENTRYPOINT and/or CMD" '^(ENTRYPOINT|CMD) '           Dockerfile
if grep -iE '^FROM ' Dockerfile 2>/dev/null | grep -qiE 'alpine|slim|busybox|distroless'; then
    pass "Lightweight base image"
else
    fail "Lightweight base image (alpine, *-slim, busybox, distroless)"
fi
if grep -qiE '^USER +(root|0)( |$)' Dockerfile 2>/dev/null || ! grep -qiE '^USER +' Dockerfile 2>/dev/null; then
    fail "Runs as a non-root user (USER)"
else
    pass "Runs as a non-root user (USER)"
fi
has ".dockerignore excludes .git"         '^\.git'                        .dockerignore
has "compose.yaml defines services"       '^services:'                    compose.yaml
if [ "$DOCKER_OK" -eq 1 ]; then
    if bash scripts/build.sh >/tmp/grade-build.log 2>&1; then
        pass "scripts/build.sh: image builds and smoke tests pass ($(grep -E '^Passed:' /tmp/grade-build.log))"
    else
        fail "scripts/build.sh failed:"
        grep -E 'FAIL|Error' /tmp/grade-build.log | sed 's/^/    /' | head -15
    fi
    if docker compose version >/dev/null 2>&1; then
        expect "docker compose config" 0 "" docker compose config -q
    else
        skip "docker compose is not available"
    fi
else
    skip "Docker is not installed or not running - image build and smoke tests NOT run"
fi

# ---------- README ----------
echo
echo "-- README.md --"
has "Documents docker build"              'docker build -t devops-tool'   README.md
has "Documents docker run"                'docker run --rm devops-tool'   README.md
for c in system-info check-host check-port help; do
    has "Documents command: $c"           "app\.sh $c"                    README.md
done
has "Documents the CI workflow"           'ci\.yml'                       README.md
has "Documents the CI failure demonstration" 'CI failure demonstration'   README.md

# ---------- Git history ----------
echo
echo "-- Git history --"
if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    n="$(git rev-list --count HEAD 2>/dev/null || echo 0)"
    if [ "$n" -ge 3 ]; then pass "At least 3 commits (found $n)"; else fail "At least 3 commits (found $n)"; fi
    if git log --format=%s 2>/dev/null | grep -qiE 'fix|revert'; then
        pass "History contains a fix commit (CI failure demonstration)"
    else
        fail "History contains a fix commit (CI failure demonstration)"
    fi
    badmode=0
    for f in "${SCRIPTS[@]}"; do
        [ "$(git ls-files --stage -- "$f" | cut -d' ' -f1)" = "100755" ] || badmode=1
    done
    if [ "$badmode" -eq 0 ]; then
        pass "Executable bits are committed in git"
    else
        fail "Executable bits are committed in git (git update-index --chmod=+x ...)"
    fi
else
    fail "Not a git repository"
fi

echo
echo "================================="
echo "Passed: $PASS  Failed: $FAIL  Skipped: $SKIP"
if [ "$SKIP" -gt 0 ]; then
    echo "WARNING: $SKIP check(s) were skipped. Start Docker and re-run for a full grade."
fi
echo "================================="

[ "$FAIL" -eq 0 ]
