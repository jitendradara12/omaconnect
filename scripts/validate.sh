#!/usr/bin/env bash
set -euo pipefail

repo_dir="$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_dir"

python3 -m unittest -q tests/test_state.py
bash -n scripts/*.sh

validator=""
if command -v omarchy-plugin-validate >/dev/null 2>&1; then
    validator="$(command -v omarchy-plugin-validate)"
elif [ -n "${OMARCHY_PATH:-}" ] && [ -x "${OMARCHY_PATH}/bin/omarchy-plugin-validate" ]; then
    validator="${OMARCHY_PATH}/bin/omarchy-plugin-validate"
fi

if [ -n "$validator" ] && [ -x "$validator" ]; then
    "$validator" .
else
    printf '%s\n' "exact Omarchy validator unavailable; skipped"
fi

qmllint_cmd=""
if [[ -x /usr/lib/qt6/bin/qmllint ]]; then
    qmllint_cmd=/usr/lib/qt6/bin/qmllint
elif command -v qmllint >/dev/null 2>&1; then
    qmllint_cmd="$(command -v qmllint)"
fi

if [[ -n "$qmllint_cmd" ]]; then
    qml_output="$(mktemp)"
    trap 'rm -f "$qml_output"' EXIT
    set +e
    omarchy_shell="${OMARCHY_PATH:-/usr/share/omarchy}/shell"
    
    qml_files=(Service.qml BarWidget.qml KdeConnectController.qml)
    if [ -f Panel.qml ]; then qml_files+=(Panel.qml); fi
    for file in components/*.qml; do
        if [ -f "$file" ]; then qml_files+=("$file"); fi
    done

    "$qmllint_cmd" -I "$omarchy_shell" \
        -I "$omarchy_shell/Ui" \
        -I "$omarchy_shell/Commons" \
        "${qml_files[@]}" >"$qml_output" 2>&1
    status=$?
    set -e
    if [ "$status" -ne 0 ]; then
        printf '%s\n' "qmllint reported actual errors; runtime loader checks are also required"
        printf '%s\n' "$(<"$qml_output")"
        exit "$status"
    elif grep -q 'Warning:' "$qml_output"; then
        printf '%s\n' "qmllint emitted host-import/unqualified-type diagnostics; not claimed warning-free"
        printf '%s\n' "QML loader/runtime verification is the authoritative error check"
        else
        printf '%s\n' "qmllint completed without diagnostics"
    fi
else
    printf '%s\n' "qmllint unavailable; skipped"
fi

printf '%s\n' "validation completed"
