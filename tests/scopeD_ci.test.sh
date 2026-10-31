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
if python3 -m unittest discover -s tests -p 'test_*.py' -q >"$tmp/unittest.out" 2>&1 \
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

# Shared runner for the stage-6 verdict tests below: runs validate.sh with the
# restricted PATH sandbox and the QMLLINT override pointed at a fake linter
# (or at a nonexistent path to simulate a host without qmllint), capturing
# the exit status and full output (validate_out / validate_status).
run_validate_with_stub() {
    if PATH="$restricted_bin" QMLLINT="$1" OMARCHY_PATH="" \
        OMARCHY_SHELL_PATH="" \
        OMACONNECT_SKIP_BASH_TESTS=1 SCOPED_CI_NESTED=1 \
        bash scripts/validate.sh >"$validate_out" 2>&1; then
        validate_status=0
    else
        validate_status=$?
    fi
}

run_validate_with_stub "$tmp/no-qmllint-here"
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

# (c2) a "[syntax]" finding must FAIL stage 6 even under a Warning: prefix --
# Qt 6 qmllint reports parse errors as "Warning: ... [syntax]" (exit 255,
# matching the Qt convention of non-zero on warning-only runs); before the
# fix that fell into the warning-only PASS branch.
fake_syntax="$tmp/fake-qmllint-syntax"
cat >"$fake_syntax" <<'STUB'
#!/usr/bin/env bash
printf 'Warning: main.qml:12:5: Expected token \x27:\x27 [syntax]\n'
exit 255
STUB
chmod +x "$fake_syntax"
run_validate_with_stub "$fake_syntax"
if [ "$validate_status" -eq 0 ] || ! grep -q 'FAIL qmllint reported 1 syntax/linter error' "$validate_out"; then
    printf '%s\n' "scopeD FAIL validate.sh passed a Warning-prefixed [syntax] error:"
    sed 's/^/  | /' "$validate_out"
    exit 1
fi
printf '%s\n' "scopeD PASS validate.sh FAILs Warning-prefixed [syntax] errors"

# (c3) a non-zero exit with non-diagnostic output (linter crash / bad CLI
# argument) must FAIL, not fall through to "completed without diagnostics".
# Exit 3 is an arbitrary non-255 failure standing in for a crashed linter.
fake_crash="$tmp/fake-qmllint-crash"
cat >"$fake_crash" <<'STUB'
#!/usr/bin/env bash
printf 'Unrecognized option --bogus\n' >&2
exit 3
STUB
chmod +x "$fake_crash"
run_validate_with_stub "$fake_crash"
if [ "$validate_status" -eq 0 ] || ! grep -q 'FAIL qmllint exited 3:' "$validate_out"; then
    printf '%s\n' "scopeD FAIL validate.sh passed a crashed linter (exit 3, non-diagnostic output):"
    sed 's/^/  | /' "$validate_out"
    exit 1
fi
printf '%s\n' "scopeD PASS validate.sh FAILs crashed/bad-invocation qmllint"

# (c4) plain warning-only output (host-import/unqualified-type diagnostics)
# still PASSES — the [syntax] enforcement must not break the advisory path.
# Exit 255 mirrors distro builds that exit non-zero on warning-only output.
fake_warn="$tmp/fake-qmllint-warn"
cat >"$fake_warn" <<'STUB'
#!/usr/bin/env bash
printf 'Warning: main.qml:40:9: unqualified access\n'
exit 255
STUB
chmod +x "$fake_warn"
run_validate_with_stub "$fake_warn"
if [ "$validate_status" -ne 0 ] || ! grep -q 'PASS qmllint emitted' "$validate_out"; then
    printf '%s\n' "scopeD FAIL validate.sh no longer passes warning-only qmllint output:"
    sed 's/^/  | /' "$validate_out"
    exit 1
fi
printf '%s\n' "scopeD PASS validate.sh still passes warning-only qmllint output"

# (c5) "[syntax]" appearing only as a substring inside an identifier is NOT a
# syntax diagnostic — the tag must be matched as a standalone token, so
# warning-only output containing e.g. Foo[syntax]Helper still PASSES.
fake_substr="$tmp/fake-qmllint-substr"
cat >"$fake_substr" <<'STUB'
#!/usr/bin/env bash
printf 'Warning: main.qml:8:2: unresolved type Foo[syntax]Helper\n'
exit 255
STUB
chmod +x "$fake_substr"
run_validate_with_stub "$fake_substr"
if [ "$validate_status" -ne 0 ] || ! grep -q 'PASS qmllint emitted' "$validate_out"; then
    printf '%s\n' "scopeD FAIL validate.sh treated a substring [syntax] as a syntax error:"
    sed 's/^/  | /' "$validate_out"
    exit 1
fi
printf '%s\n' "scopeD PASS validate.sh ignores [syntax] inside identifiers (token match)"

# (c6) an "Error:" finding fails the stage regardless of the exit code — even
# a zero exit (findings, not exit codes, decide the verdict).
fake_err0="$tmp/fake-qmllint-error0"
cat >"$fake_err0" <<'STUB'
#!/usr/bin/env bash
printf 'Error: main.qml:3:1: expected component name\n'
exit 0
STUB
chmod +x "$fake_err0"
run_validate_with_stub "$fake_err0"
if [ "$validate_status" -eq 0 ] || ! grep -q 'FAIL qmllint reported 1 syntax/linter error' "$validate_out"; then
    printf '%s\n' "scopeD FAIL validate.sh passed an Error: finding reported with exit 0:"
    sed 's/^/  | /' "$validate_out"
    exit 1
fi
printf '%s\n' "scopeD PASS validate.sh FAILs Error: findings even with exit 0"

# (c7) Qt 6.4-era qmllint (the build CI installs) reports parse errors as
# BARE location lines with no Error:/[syntax] marker — and warnings routinely
# coexist in the same run, which used to defuse the crash guard. A bare
# "file:line:col:" finding must FAIL even alongside Warning: lines.
fake_bare="$tmp/fake-qmllint-bare"
cat >"$fake_bare" <<'STUB'
#!/usr/bin/env bash
printf 'Warning: Failed to find the following builtins: jsroot.qmltypes (so will use qrc). Import paths used:\n'
printf '\t/usr/lib/qt6/qml\n'
printf 'main.qml:4:1: Expected token %s\n' "'}'"
exit 255
STUB
chmod +x "$fake_bare"
run_validate_with_stub "$fake_bare"
if [ "$validate_status" -eq 0 ] || ! grep -q 'FAIL qmllint reported 1 syntax/linter error' "$validate_out"; then
    printf '%s\n' "scopeD FAIL validate.sh passed a bare-location syntax error hidden among warnings:"
    sed 's/^/  | /' "$validate_out"
    exit 1
fi
printf '%s\n' "scopeD PASS validate.sh FAILs bare-location errors (Qt 6.4 format)"

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
