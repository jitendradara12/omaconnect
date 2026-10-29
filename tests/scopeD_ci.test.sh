#!/usr/bin/env bash
# Run with: bash tests/scopeD_ci.test.sh
#
# Self-test of the test infrastructure (scope D): verifies the harness
# pieces that scripts/validate.sh and CI rely on actually behave —
# syntax checks catch broken scripts, unittest discovery picks up the
# python tests, validate.sh degrades gracefully when optional tools are
# missing, and the python suite never writes into HOME.
#
# Zero dependencies: bash, python3 and coreutils only.
#
# Re-entry guard: scripts/validate.sh stage 2 runs every tests/*.test.sh,
# including this one. When this self-test invokes validate.sh, that nested
# run would invoke this file again — so validate.sh sees SCOPED_CI_NESTED
# in the environment and this guard short-circuits the recursive copy.
if [ -n "${SCOPED_CI_NESTED:-}" ]; then
    printf '%s\n' "scopeD: nested invocation via validate.sh; re-entry guard active, nothing to do"
    exit 0
fi
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$root"

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

# (a) bash -n must reject a syntactically broken script -----------------------
broken="$tmp/broken.sh"
# Deliberately malformed: the test stanza is never closed.
printf 'if true; then echo unclosed\n' >"$broken"
if bash -n "$broken" 2>/dev/null; then
    printf '%s\n' "scopeD FAIL: bash -n accepted a syntactically broken script"
    exit 1
fi
printf '%s\n' "scopeD PASS bash -n rejects broken scripts"

# (b) unittest discovery must find and pass the python suite ------------------
if python3 -m unittest discover -s tests -p 'test_*.py' -q >/"$tmp/unittest.out" 2>&1 \
    && grep -Eq '^Ran [1-9][0-9]* test' "$tmp/unittest.out"; then
    printf '%s\n' "scopeD PASS unittest discovery runs the python suite ($(grep -E -o '^Ran [0-9]+' "$tmp/unittest.out" | grep -E -o '[0-9]+') tests)"
else
    printf '%s\n' "scopeD FAIL unittest discovery did not run the python suite:"
    sed 's/^/  | /' "$tmp/unittest.out"
    exit 1
fi

# (c) validate.sh must skip (not fail) when qmllint is unavailable ------------
# Simulate a host without qmllint by pointing PATH at a temp bin dir of
# symlinks (bash/python3/coreutils plus everything the repo scripts call,
# but no qmllint). PATH stripping alone cannot hide
# /usr/lib/qt6/bin/qmllint — validate.sh keeps that absolute fallback for
# distros that keep Qt tools off PATH — so the QMLLINT override forces the
# "not found" answer; both mechanisms together model a machine where
# qmllint simply is not installed. OMARCHY_PATH is cleared so the optional
# Omarchy plugin validator (whose own PATH dependencies are not the thing
# under test here) is not discovered through the fallback location either.
# OMACONNECT_SKIP_BASH_TESTS keeps sibling bash suites (added by other
# branches) out of this nested run: they build their own PATH sandboxes and
# are not guaranteed to work inside this restricted one. SCOPED_CI_NESTED
# stays as a second guard against this file re-entering itself.
restricted_bin="$tmp/bin"
mkdir -p "$restricted_bin"
for tool in bash sh env python3 nohup awk gdbus busctl dirname basename \
    grep sed cat ls mkdir rm cp mv chmod ln tr head tail wc sort uniq \
    touch mktemp id readlink realpath cut find xargs sleep stat; do
    tool_path="$(command -v "$tool" 2>/dev/null || true)"
    if [ -n "$tool_path" ]; then
        ln -sf "$tool_path" "$restricted_bin/$tool"
    fi
done
validate_out="$tmp/validate.out"
if PATH="$restricted_bin" QMLLINT="$tmp/no-qmllint-here" OMARCHY_PATH="" \
    OMACONNECT_SKIP_BASH_TESTS=1 SCOPED_CI_NESTED=1 bash scripts/validate.sh >"$validate_out" 2>&1; then
    validate_status=0
else
    validate_status=$?
fi
if [ "$validate_status" -ne 0 ]; then
    printf '%s\n' "scopeD FAIL validate.sh exited $validate_status with qmllint unavailable (skip must not fail):"
    sed 's/^/  | /' "$validate_out"
    exit 1
fi
if ! grep -q 'qmllint unavailable; skipped' "$validate_out"; then
    printf '%s\n' "scopeD FAIL validate.sh did not report the qmllint-unavailable skip:"
    sed 's/^/  | /' "$validate_out"
    exit 1
fi
printf '%s\n' "scopeD PASS validate.sh skips gracefully without qmllint (exit 0)"

# (d) hygiene: the python suite must not write into HOME ----------------------
fresh_home="$tmp/home"
mkdir -p "$fresh_home"
if ! HOME="$fresh_home" python3 -m unittest discover -s tests -p 'test_*.py' -q \
    >"$tmp/hygiene.out" 2>&1; then
    printf '%s\n' "scopeD FAIL python suite failed under a fresh HOME:"
    sed 's/^/  | /' "$tmp/hygiene.out"
    exit 1
fi
if [ -n "$(ls -A "$fresh_home")" ]; then
    printf '%s\n' "scopeD FAIL python suite wrote into HOME: $(ls -A "$fresh_home" | tr '\n' ' ')"
    exit 1
fi
printf '%s\n' "scopeD PASS python suite leaves HOME untouched"

printf '%s\n' "scopeD: all tests passed"
