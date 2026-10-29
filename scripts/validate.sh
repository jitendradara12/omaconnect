#!/usr/bin/env bash
# Ordered validation pipeline for the omaconnect plugin.
#
# Every stage reports its own PASS / FAIL / SKIP line and the script exits
# non-zero if any enforced stage failed. Enforced stages: python unit tests,
# bash tests, shell syntax, qmllint errors. Advisory stages (shellcheck
# findings, the Omarchy plugin validator, qmllint warnings) never fail the
# run.
#
# Tests are discovered by convention, not by a hardcoded list:
#   - tests/test_*.py   via `python3 -m unittest discover`
#   - tests/*.test.sh   each executed with bash
# so tests added by any branch are picked up automatically. Bash tests that
# themselves invoke validate.sh must guard re-entry (see
# tests/scopeD_ci.test.sh for the pattern).
set -euo pipefail

repo_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_dir"

total_stages=6
failed_stages=()

# --- [1/6] python unit tests (tests/test_*.py) ------------------------------
printf '%s\n' "[1/${total_stages}] python unit tests: python3 -m unittest discover -s tests -p 'test_*.py'"
if python3 -m unittest discover -s tests -p 'test_*.py' -q; then
    printf '%s\n' "[1/${total_stages}] PASS python unit tests"
else
    printf '%s\n' "[1/${total_stages}] FAIL python unit tests"
    failed_stages+=(1)
fi

# --- [2/6] bash tests (tests/*.test.sh) --------------------------------------
printf '%s\n' "[2/${total_stages}] bash tests: tests/*.test.sh"
if [ -n "${OMACONNECT_SKIP_BASH_TESTS:-}" ]; then
    # Escape hatch for nested/sandboxed invocations: bash suites build their
    # own PATH sandboxes and must not run inside another test's restricted
    # environment. Each suite still runs at the top level.
    printf '%s\n' "[2/${total_stages}] SKIP bash tests (OMACONNECT_SKIP_BASH_TESTS set)"
else
bash_any=0
bash_failed=0
for t in tests/*.test.sh; do
    [ -e "$t" ] || continue
    bash_any=1
    printf '%s\n' "---- running $t"
    if ! bash "$t"; then
        bash_failed=1
    fi
done
if [ "$bash_any" -eq 0 ]; then
    printf '%s\n' "[2/${total_stages}] SKIP no tests/*.test.sh found"
elif [ "$bash_failed" -eq 0 ]; then
    printf '%s\n' "[2/${total_stages}] PASS bash tests"
else
    printf '%s\n' "[2/${total_stages}] FAIL bash tests"
    failed_stages+=(2)
fi
fi

# --- [3/6] shell syntax (scripts/*.sh) ---------------------------------------
printf '%s\n' "[3/${total_stages}] shell syntax: bash -n scripts/*.sh"
syntax_failed=0
for s in scripts/*.sh; do
    [ -e "$s" ] || continue
    if ! bash -n "$s"; then
        syntax_failed=1
    fi
done
if [ "$syntax_failed" -eq 0 ]; then
    printf '%s\n' "[3/${total_stages}] PASS shell syntax"
else
    printf '%s\n' "[3/${total_stages}] FAIL shell syntax"
    failed_stages+=(3)
fi

# --- [4/6] shellcheck (advisory; skipped when not installed) -----------------
printf '%s\n' "[4/${total_stages}] shellcheck scripts/*.sh"
if command -v shellcheck >/dev/null 2>&1; then
    if shellcheck scripts/*.sh; then
        printf '%s\n' "[4/${total_stages}] PASS shellcheck"
    else
        # Findings are advisory for now: scripts are shared across
        # contributors, so we warn instead of failing the pipeline.
        printf '%s\n' "[4/${total_stages}] WARN shellcheck reported findings (advisory; not enforced)"
    fi
else
    printf '%s\n' "[4/${total_stages}] SKIP shellcheck unavailable; install shellcheck for lint coverage"
fi

# --- [5/6] omarchy plugin validator (optional) -------------------------------
printf '%s\n' "[5/${total_stages}] omarchy plugin validator"
validator=""
if command -v omarchy-plugin-validate >/dev/null 2>&1; then
    validator="$(command -v omarchy-plugin-validate)"
elif [ -n "${OMARCHY_PATH:-}" ] && [ -x "${OMARCHY_PATH}/bin/omarchy-plugin-validate" ]; then
    validator="${OMARCHY_PATH}/bin/omarchy-plugin-validate"
fi

if [ -n "$validator" ] && [ -x "$validator" ]; then
    if "$validator" .; then
        printf '%s\n' "[5/${total_stages}] PASS omarchy plugin validator"
    else
        printf '%s\n' "[5/${total_stages}] FAIL omarchy plugin validator"
        failed_stages+=(5)
    fi
else
    printf '%s\n' "[5/${total_stages}] SKIP exact Omarchy validator unavailable; skipped"
fi

# --- [6/6] qmllint (errors enforced, warnings informational) -----------------
printf '%s\n' "[6/${total_stages}] qmllint"
# Resolution order: an explicit QMLLINT override (lets callers force a
# specific binary, or force the skip by pointing it at a missing file — used
# by the self-tests to simulate a host without qmllint), then PATH (a
# stripped PATH therefore disables this stage), then the standard Qt6
# location for distros (Debian/Ubuntu qt6-declarative-dev-tools) that keep
# it off PATH.
qmllint_cmd=""
if [ -n "${QMLLINT:-}" ]; then
    if [ -x "$QMLLINT" ]; then
        qmllint_cmd="$QMLLINT"
    fi
elif command -v qmllint >/dev/null 2>&1; then
    qmllint_cmd="$(command -v qmllint)"
elif [ -x /usr/lib/qt6/bin/qmllint ]; then
    qmllint_cmd=/usr/lib/qt6/bin/qmllint
fi

# Import paths for the Omarchy shell (qs.Ui / qs.Commons / Quickshell types).
# OMARCHY_SHELL_PATH lets CI point at a checkout of omacom/omarchy without
# claiming OMARCHY_PATH (which would also arm the plugin-validator stage).
omarchy_shell="${OMARCHY_SHELL_PATH:-${OMARCHY_PATH:-/usr/share/omarchy}/shell}"

if [ -n "$qmllint_cmd" ]; then
    printf '%s\n' "[6/${total_stages}] running $qmllint_cmd"
    qml_output="$(mktemp)"
    trap 'rm -f "$qml_output"' EXIT
    set +e
    if [ ! -d "$omarchy_shell" ]; then
        printf '%s\n' "note: $omarchy_shell not found; linting without Omarchy imports may add warnings"
    fi

    qml_files=()
    for file in ./*.qml components/*.qml bridge/*.qml; do
        [ -f "$file" ] && qml_files+=("$file")
    done

    "$qmllint_cmd" -I "$omarchy_shell" \
        -I "$omarchy_shell/Ui" \
        -I "$omarchy_shell/Commons" \
        "${qml_files[@]}" >"$qml_output" 2>&1
    status=$?
    set -e
    # Verdict comes from the findings, not the exit code: some distro builds
    # of qmllint (Debian/Ubuntu Qt 6.4) exit non-zero when only warnings were
    # reported, while others exit 0 for the same output. A line starting with
    # "Error:" is a real syntax/type failure and always fails the stage;
    # warning-only output passes (informational, never claimed warning-free).
    # One guard on the exit code: non-zero with NO diagnostics means the
    # linter itself failed (crash, bad invocation) — that must never pass.
    if [ "$status" -ne 0 ] && [ ! -s "$qml_output" ]; then
        printf '%s\n' "[6/${total_stages}] FAIL qmllint exited $status with no output (linter failure?)"
        failed_stages+=(6)
    elif grep -q '^Error:' "$qml_output"; then
        error_count="$(grep -c '^Error:' "$qml_output" || true)"
        printf '%s\n' "[6/${total_stages}] FAIL qmllint reported $error_count error(s); runtime loader checks are also required"
        sed -n '1,40p' "$qml_output" >&2 || true
        failed_stages+=(6)
    elif grep -q 'Warning:' "$qml_output"; then
        printf '%s\n' "[6/${total_stages}] PASS qmllint emitted host-import/unqualified-type diagnostics; not claimed warning-free"
        printf '%s\n' "QML loader/runtime verification is the authoritative error check"
    else
        printf '%s\n' "[6/${total_stages}] PASS qmllint completed without diagnostics"
    fi
else
    printf '%s\n' "[6/${total_stages}] SKIP qmllint unavailable; skipped"
fi

# --- summary -----------------------------------------------------------------
if [ "${#failed_stages[@]}" -gt 0 ]; then
    printf '%s\n' "validation FAILED (stage(s): ${failed_stages[*]})"
    exit 1
fi
printf '%s\n' "validation completed"
