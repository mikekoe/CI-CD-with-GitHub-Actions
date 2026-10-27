#!/usr/bin/env bash
# lint.sh - Static checks for the repository.
#
#   1. Required files exist.
#   2. `bash -n` passes for every Bash script.
#   3. ShellCheck (extra check): runs if installed, otherwise skipped.
#
# Usage: ./scripts/lint.sh
# Exit code: 0 if everything passes, 1 otherwise.

cd "$(dirname "${BASH_SOURCE[0]}")/.." || exit 1

REQUIRED_FILES=(
    README.md
    app/app.sh
    scripts/lint.sh
    scripts/build.sh
    tests/test.sh
    .github/workflows/ci.yml
    Dockerfile
    compose.yaml
    .dockerignore
    grade.sh
)
BASH_SCRIPTS=(app/app.sh scripts/lint.sh scripts/build.sh tests/test.sh grade.sh)

FAILED=0
ok()   { echo "  ok    $1"; }
bad()  { echo "  FAIL  $1"; FAILED=1; }
skip() { echo "  skip  $1"; }

echo "== Required files =="
for f in "${REQUIRED_FILES[@]}"; do
    if [ -f "$f" ]; then ok "$f"; else bad "missing: $f"; fi
done

echo
echo "== Bash syntax (bash -n) =="
for f in "${BASH_SCRIPTS[@]}"; do
    [ -f "$f" ] || continue
    if err="$(bash -n "$f" 2>&1)"; then
        ok "$f"
    else
        bad "$f"
        while IFS= read -r line; do echo "        $line"; done <<< "$err"
    fi
done

echo
echo "== ShellCheck (extra) =="
if command -v shellcheck >/dev/null 2>&1; then
    existing=()
    for f in "${BASH_SCRIPTS[@]}"; do [ -f "$f" ] && existing+=("$f"); done
    if shellcheck -x "${existing[@]}"; then
        ok "shellcheck: no findings"
    else
        bad "shellcheck reported findings"
    fi
else
    skip "shellcheck is not installed"
fi

echo
if [ "$FAILED" -eq 0 ]; then
    echo "Lint passed."
else
    echo "Lint FAILED."
fi
exit "$FAILED"
