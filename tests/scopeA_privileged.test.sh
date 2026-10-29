#!/usr/bin/env bash
# Scope A security tests: privileged actions fail closed + argv-only spawning.
#
# Self-contained: needs only bash, python3 and coreutils (od/tr/mktemp/ln/chmod).
# Run from anywhere:  bash tests/scopeA_privileged.test.sh
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
FW="$ROOT/scripts/setup_firewall.sh"
DEP="$ROOT/scripts/install_dependencies.sh"
LAUNCH="$ROOT/scripts/launch_in_terminal.sh"
QML="$ROOT/KdeConnectController.qml"

N=0
FAILS=0
ok() { N=$((N + 1)); printf 'ok %d - %s\n' "$N" "$1"; }
bad() { N=$((N + 1)); FAILS=$((FAILS + 1)); printf 'not ok %d - %s\n' "$N" "$1"; }

assert() { # desc condition...
  local desc="$1"; shift
  if "$@"; then ok "$desc"; else bad "$desc"; fi
}
assert_rc_nonzero() { local desc="$1" rc="$2"; if [[ "$rc" -ne 0 ]]; then ok "$desc"; else bad "$desc (exit was 0, expected non-zero)"; fi; }
assert_rc_eq() { local desc="$1" rc="$2" want="$3"; if [[ "$rc" -eq "$want" ]]; then ok "$desc"; else bad "$desc (exit was $rc, expected $want)"; fi; }
assert_eq() { local desc="$1" got="$2" want="$3"; if [[ "$got" == "$want" ]]; then ok "$desc"; else bad "$desc (got '$got', want '$want')"; fi; }
assert_file_empty() {
  local desc="$1" file="$2"
  if [[ ! -s "$file" ]]; then ok "$desc"; else bad "$desc (file not empty: $(tr '\n' ';' < "$file"))"; fi
}
assert_contains() { local desc="$1" file="$2" needle="$3"; if grep -Fq -- "$needle" "$file"; then ok "$desc"; else bad "$desc (missing '$needle' in $file)"; fi; }
assert_line() { local desc="$1" file="$2" line="$3"; if grep -Fxq -- "$line" "$file"; then ok "$desc"; else bad "$desc (missing exact line '$line' in $file)"; fi; }
assert_not_contains() { local desc="$1" file="$2" needle="$3"; if grep -Fq -- "$needle" "$file"; then bad "$desc (found forbidden '$needle' in $file)"; else ok "$desc"; fi; }

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

# ---------------------------------------------------------------------------
# Sandbox: curated PATH with only what the scripts need, plus fakes.
# /usr/bin contains the real omarchy launcher, ufw and pacman on Omarchy, so
# the scripts under test must never see the ambient PATH.
# ---------------------------------------------------------------------------
COREBIN="$WORK/corebin"
mkdir -p "$COREBIN"
for c in bash cat grep sleep python3; do
  src="$(command -v "$c" 2>/dev/null || true)"
  if [[ ! -x "$src" ]]; then src="/usr/bin/$c"; fi
  if [[ ! -x "$src" ]]; then echo "FATAL: cannot locate required command: $c" >&2; exit 1; fi
  ln -s "$src" "$COREBIN/$c"
done
BASH_BIN="$COREBIN/bash"
PY_BIN="$COREBIN/python3"

make_fake_sudo() { # dir — logs "$*" (quotes stripped, like real sudo argv) and execs
  local dir="$1"; mkdir -p "$dir"
  cat > "$dir/sudo" <<'EOS'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "${SUDO_LOG:?SUDO_LOG not set}"
exec "$@"
EOS
  chmod +x "$dir/sudo"
}
make_stub() { # dir name
  local dir="$1" name="$2"; mkdir -p "$dir"
  printf '#!/usr/bin/env bash\nexit 0\n' > "$dir/$name"
  chmod +x "$dir/$name"
}

FAKE_UFW="$WORK/fake-ufw-bin";   make_fake_sudo "$FAKE_UFW"; make_stub "$FAKE_UFW" ufw
FAKE_FWD="$WORK/fake-fwd-bin";   make_fake_sudo "$FAKE_FWD"; make_stub "$FAKE_FWD" firewall-cmd
FAKE_DEP="$WORK/fake-dep-bin";   make_fake_sudo "$FAKE_DEP"; make_stub "$FAKE_DEP" pacman

# ---------------------------------------------------------------------------
# pty runner: spawn a command under a real pty, wait for a marker string in
# the output, send bytes, then collect exit code + full output.
# PTY_RC gets the child exit code; PTY_OUT holds the raw pty output.
# CHILD_PATH (if set) becomes the child's PATH, so the parent test keeps its
# own working PATH.
# ---------------------------------------------------------------------------
PTY_OUT="$WORK/pty.out"
to_hex() { printf '%s' "$1" | od -A n -t x1 | tr -d ' \n'; }
HEX_PROMPT="$(to_hex 'Press Enter')"
HEX_LF="0a"
HEX_EOT="04"

pty_run() { # waitfor_hex send_hex cmd...
  local waitfor="$1" send="$2"; shift 2
  local summary
  summary="$(python3 - "$waitfor" "$send" "$PTY_OUT" "$@" <<'PYEOF' || true
import os, pty, select, sys, time

waitfor = bytes.fromhex(sys.argv[1]) if sys.argv[1] else b""
send = bytes.fromhex(sys.argv[2]) if sys.argv[2] else b""
outpath = sys.argv[3]
argv = sys.argv[4:]

pid, fd = pty.fork()
if pid == 0:
    if os.environ.get("CHILD_PATH"):
        os.environ["PATH"] = os.environ["CHILD_PATH"]
    try:
        os.execvp(argv[0], argv)
    finally:
        os._exit(127)

out = bytearray()
sent = False
status = None
deadline = time.time() + 60
while time.time() < deadline:
    if not sent and (not waitfor or waitfor in out):
        try:
            os.write(fd, send)
        except OSError:
            pass
        sent = True
    r, _, _ = select.select([fd], [], [], 0.2)
    if not r:
        try:
            wpid, st = os.waitpid(pid, os.WNOHANG)
        except OSError:
            break
        if wpid:
            status = st
        continue
    try:
        chunk = os.read(fd, 65536)
    except OSError:
        break
    if not chunk:
        break
    out += chunk

if status is None:
    while True:
        r, _, _ = select.select([fd], [], [], 0)
        if not r:
            break
        try:
            chunk = os.read(fd, 65536)
        except OSError:
            break
        if not chunk:
            break
        out += chunk
    while True:
        try:
            _, status = os.waitpid(pid, 0)
            break
        except OSError:
            status = 0
            break

with open(outpath, "wb") as f:
    f.write(bytes(out))
print("EXIT:%d" % os.waitstatus_to_exitcode(status))
PYEOF
)"
  if [[ "$summary" == EXIT:* ]]; then PTY_RC="${summary#EXIT:}"; else PTY_RC="no-exit"; fi
}

# ===========================================================================
echo "# (a) fail-closed: no TTY and EOF must abort before any sudo"
# ---------------------------------------------------------------------------
log="$WORK/sudo-a.log"; : > "$log"
out="$WORK/fw-ufw-notty.out"; err="$WORK/fw-ufw-notty.err"
rc=0
PATH="$FAKE_UFW:$COREBIN" SUDO_LOG="$log" "$BASH_BIN" "$FW" </dev/null >"$out" 2>"$err" || rc=$?
assert_rc_nonzero "setup_firewall.sh (ufw) exits non-zero without a TTY" "$rc"
assert_file_empty "setup_firewall.sh (ufw) never reached sudo without a TTY" "$log"
assert_contains "setup_firewall.sh (ufw) explains the TTY refusal on stderr" "$err" \
  "Refusing to apply firewall rules without an interactive terminal (stdin is not a TTY)."
# banners stay byte-identical
assert_contains "ufw banner keeps tcp allow line" "$out" "sudo ufw allow 1714:1764/tcp comment 'KDE Connect'"
assert_contains "ufw banner keeps udp allow line" "$out" "sudo ufw allow 1714:1764/udp comment 'KDE Connect'"
assert_contains "ufw banner keeps reload line" "$out" "sudo ufw reload"
# the prompt only prints once a TTY is confirmed; its text is a source contract
assert_contains "ufw branch keeps apply prompt text" "$FW" "Press Enter to apply UFW rules, or Ctrl+C to cancel: "

log="$WORK/sudo-b.log"; : > "$log"
out="$WORK/fw-fwd-notty.out"; err="$WORK/fw-fwd-notty.err"
rc=0
PATH="$FAKE_FWD:$COREBIN" SUDO_LOG="$log" "$BASH_BIN" "$FW" </dev/null >"$out" 2>"$err" || rc=$?
assert_rc_nonzero "setup_firewall.sh (firewalld) exits non-zero without a TTY" "$rc"
assert_file_empty "setup_firewall.sh (firewalld) never reached sudo without a TTY" "$log"
assert_contains "firewalld banner keeps command preview" "$out" "sudo firewall-cmd --permanent --add-service=kdeconnect"
assert_contains "firewalld banner keeps reload preview" "$out" "sudo firewall-cmd --reload"
assert_contains "firewalld branch keeps apply prompt text" "$FW" "Press Enter to apply firewalld rules, or Ctrl+C to cancel: "

log="$WORK/sudo-c.log"; : > "$log"
out="$WORK/dep-notty.out"; err="$WORK/dep-notty.err"
rc=0
PATH="$FAKE_DEP:$COREBIN" SUDO_LOG="$log" "$BASH_BIN" "$DEP" </dev/null >"$out" 2>"$err" || rc=$?
assert_rc_nonzero "install_dependencies.sh exits non-zero without a TTY" "$rc"
assert_file_empty "install_dependencies.sh never reached sudo without a TTY" "$log"
assert_contains "install_dependencies.sh explains the TTY refusal on stderr" "$err" \
  "Refusing to install dependencies without an interactive terminal (stdin is not a TTY)."
assert_contains "install banner keeps exact-command line" "$out" "Exact command that will be executed:"
assert_contains "install banner keeps pacman preview" "$out" "sudo pacman -S --needed kdeconnect glib2 dbus"

# ===========================================================================
echo "# (b) e2e under a real pty: Enter applies, EOF aborts"
# ---------------------------------------------------------------------------
log="$WORK/sudo-d.log"; : > "$log"
CHILD_PATH="$FAKE_UFW:$COREBIN" SUDO_LOG="$log" pty_run "$HEX_PROMPT" "$HEX_LF" "$BASH_BIN" "$FW"
assert_rc_eq "setup_firewall.sh (ufw) exits 0 after Enter on a pty" "$PTY_RC" 0
assert_line "sudo log has exact tcp allow argv" "$log" "ufw allow 1714:1764/tcp comment KDE Connect"
assert_line "sudo log has exact udp allow argv" "$log" "ufw allow 1714:1764/udp comment KDE Connect"
assert_line "sudo log has exact reload argv" "$log" "ufw reload"
assert_contains "pty output shows applying banner" "$PTY_OUT" "Applying UFW firewall rules with root privileges..."
assert_contains "pty output shows success" "$PTY_OUT" "Firewall rules applied successfully."
no_surprises=true
while IFS= read -r line; do
  case "$line" in
    "ufw status"|"ufw allow 1714:1764/tcp comment KDE Connect"|"ufw allow 1714:1764/udp comment KDE Connect"|"ufw reload") ;;
    *) no_surprises=false; bad "unexpected sudo log line (metacharacter risk?): $line" ;;
  esac
done < "$log"
assert "every ufw sudo log line is an exact whitelisted argv" test "$no_surprises" = true

log="$WORK/sudo-e.log"; : > "$log"
CHILD_PATH="$FAKE_UFW:$COREBIN" SUDO_LOG="$log" pty_run "$HEX_PROMPT" "$HEX_EOT" "$BASH_BIN" "$FW"
assert_rc_nonzero "setup_firewall.sh (ufw) aborts on EOF (Ctrl+D)" "$PTY_RC"
assert_file_empty "no sudo call after EOF abort" "$log"
assert_contains "EOF abort prints Cancelled." "$PTY_OUT" "Cancelled."

log="$WORK/sudo-f.log"; : > "$log"
CHILD_PATH="$FAKE_FWD:$COREBIN" SUDO_LOG="$log" pty_run "$HEX_PROMPT" "$HEX_LF" "$BASH_BIN" "$FW"
assert_rc_eq "setup_firewall.sh (firewalld) exits 0 after Enter on a pty" "$PTY_RC" 0
assert_line "sudo log has exact firewalld add argv" "$log" "firewall-cmd --permanent --add-service=kdeconnect"
assert_line "sudo log has exact firewalld reload argv" "$log" "firewall-cmd --reload"

log="$WORK/sudo-g.log"; : > "$log"
CHILD_PATH="$FAKE_DEP:$COREBIN" SUDO_LOG="$log" pty_run "$HEX_PROMPT" "$HEX_LF" "$BASH_BIN" "$DEP"
assert_rc_eq "install_dependencies.sh exits 0 after Enter on a pty" "$PTY_RC" 0
assert_line "sudo log has exact pacman argv" "$log" "pacman -S --needed kdeconnect glib2 dbus"
assert_contains "pty output shows pacman banner" "$PTY_OUT" "Running pacman with root privileges..."

# ===========================================================================
echo "# (c) launch_in_terminal.sh quoting round-trip"
# ---------------------------------------------------------------------------
LT_BIN="$WORK/fake-lt-bin"
mkdir -p "$LT_BIN"
cat > "$LT_BIN/omarchy-launch-floating-terminal-with-presentation" <<'EOS'
#!/usr/bin/env bash
printf '%s\t%s\n' "$#" "$1" >> "${LAUNCHER_LOG:?LAUNCHER_LOG not set}"
exit 0
EOS
chmod +x "$LT_BIN/omarchy-launch-floating-terminal-with-presentation"

target="$WORK/ta rget wi'th \$dollar and spaces.sh"
printf '#!/usr/bin/env bash\nprintf "%%s" "$0" > %q\n' "$WORK/marker" > "$target"

llog="$WORK/launcher.log"; : > "$llog"
PATH="$LT_BIN:$COREBIN" LAUNCHER_LOG="$llog" "$BASH_BIN" "$LAUNCH" "$target"
assert "omarchy launcher invoked exactly once" test "$(wc -l < "$llog")" -eq 1
logged="$(cat "$llog")"
argc="${logged%%$'\t'*}"
arg="${logged#*$'\t'}"
assert_eq "omarchy launcher receives a single argument" "$argc" 1
assert_eq "single argument is 'bash ' + printf-%q-quoted path" "$arg" "bash $(printf '%q' "$target")"
assert "logged command re-parses without expanding \$dollar" test "$arg" != "bash $target"
rm -f "$WORK/marker"
bash -c "$arg"
assert "round-trip executes the exact original path (marker exists)" test -f "$WORK/marker"
assert_eq "marker records the exact original path" "$(cat "$WORK/marker")" "$target"

# xdg-terminal-exec fallback: pure argv, no quoting at all
XDG_BIN="$WORK/fake-xdg-bin"
mkdir -p "$XDG_BIN"
cat > "$XDG_BIN/xdg-terminal-exec" <<'EOS'
#!/usr/bin/env bash
printf '%s\t%s\n' "$#" "$*" >> "${LAUNCHER_LOG:?LAUNCHER_LOG not set}"
exit 0
EOS
chmod +x "$XDG_BIN/xdg-terminal-exec"

llog="$WORK/xdg.log"; : > "$llog"
PATH="$XDG_BIN:$COREBIN" LAUNCHER_LOG="$llog" "$BASH_BIN" "$LAUNCH" "$target"
logged="$(cat "$llog")"
argc="${logged%%$'\t'*}"
arg="${logged#*$'\t'}"
assert_eq "xdg-terminal-exec receives two argv elements" "$argc" 2
assert_eq "xdg-terminal-exec argv is raw 'bash <path>'" "$arg" "bash $target"

# no launcher available -> 127
rc=0
PATH="$COREBIN" "$BASH_BIN" "$LAUNCH" "$target" >"$WORK/nolt.out" 2>"$WORK/nolt.err" || rc=$?
assert_rc_eq "missing launcher exits 127" "$rc" 127
assert_contains "missing launcher explains on stderr" "$WORK/nolt.err" "No terminal launcher found"

# empty target -> usage error, never spawns anything
rc=0
PATH="$LT_BIN:$COREBIN" LAUNCHER_LOG="$llog" "$BASH_BIN" "$LAUNCH" "" >"$WORK/empty.out" 2>"$WORK/empty.err" || rc=$?
assert_rc_nonzero "empty target rejected" "$rc"
assert_contains "empty target prints usage" "$WORK/empty.err" "Usage: launch_in_terminal.sh <script-path>"

# ===========================================================================
echo "# (d) source contracts"
# ---------------------------------------------------------------------------
assert_contains "controller routes firewall through launch_in_terminal.sh" "$QML" "launch_in_terminal.sh"
assert_contains "configureFirewall spawns launcher argv-style" "$QML" \
  '["bash", scriptPath("scripts/launch_in_terminal.sh"), getFirewallScriptPath()]'
assert_contains "installDependencies spawns launcher argv-style" "$QML" \
  '["bash", scriptPath("scripts/launch_in_terminal.sh"), getInstallScriptPath()]'
assert_not_contains "old shell-string spawner pattern is gone" "$QML" "bash '\" + script + \"'\""
assert "tailscale sh -c constant spawner untouched" grep -Fq '["sh", "-c", "command -v tailscale' "$QML"
assert "validDeviceId helper exists" grep -Fq 'function validDeviceId(id)' "$QML"
assert "respondToPairingRequest guarded by validDeviceId" grep -Fq 'if (!validDeviceId(id)) return false' "$QML"
assert_contains "firewall script is fail-closed on TTY" "$FW" '[[ ! -t 0 ]]'
assert_contains "install script is fail-closed on TTY" "$DEP" '[[ ! -t 0 ]]'
assert_contains "EOF aborts firewall confirmation" "$FW" 'if ! read -r _; then'
assert_contains "EOF aborts install confirmation" "$DEP" 'if ! read -r _; then'

# validDeviceId regex semantics (executed, mirrored from the QML source)
"$PY_BIN" - "$QML" <<'PYEOF' && ok "validDeviceId regex accepts real ids, rejects hostile ones" || bad "validDeviceId regex semantics wrong"
import re, sys
src = open(sys.argv[1]).read()
m = re.search(r'function validDeviceId\(id\) \{\s*return\s+(\S[^\n]*?)\.test\(String\(id \|\| ""\)\)', src)
assert m, "validDeviceId body not found"
literal = m.group(1).strip()
assert literal.startswith("/") and literal.endswith("/"), "not a regex literal: " + literal
pattern = literal[1:-1]
assert pattern.startswith("^") and pattern.endswith("$"), "regex not anchored: " + pattern
rx = re.compile(pattern[1:-1])  # anchors become fullmatch
valid = ["0123456789abcdef0123456789abcdef", "device_1-x", "A", "abcDEF012_-9"]
invalid = ["", "../../etc/passwd", "foo bar", "a;b", "$(cmd)", "a/b", "id'", 'x"y', "a`b", "a\nb"]
for v in valid:
    assert rx.fullmatch(v), "should accept: %r" % v
for v in invalid:
    assert not rx.fullmatch(v), "should reject: %r" % v
sys.exit(0)
PYEOF

# ---------------------------------------------------------------------------
echo ""
if [[ "$FAILS" -eq 0 ]]; then
  echo "scopeA: all tests passed"
else
  echo "scopeA: $FAILS test(s) FAILED" >&2
  exit 1
fi
