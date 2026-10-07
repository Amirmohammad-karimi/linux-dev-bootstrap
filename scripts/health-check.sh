#!/usr/bin/env bash
set -u
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT_DIR/scripts/helpers.sh"
LOCAL_CONFIG="$ROOT_DIR/config/local.env"
load_local_env "$LOCAL_CONFIG"
ERRORS=0
WARNINGS=0
pass(){ printf '[OK]   %s\n' "$1"; }
warn(){ printf '[WARN] %s\n' "$1"; WARNINGS=$((WARNINGS+1)); }
fail(){ printf '[FAIL] %s\n' "$1"; ERRORS=$((ERRORS+1)); }
check_command(){ local command="$1"; local name="${2:-$1}"; command -v "$command" >/dev/null 2>&1 && pass "$name: $(command -v "$command")" || fail "$name not found"; }
check_enabled_command(){
    local feature="$1"
    local default="$2"
    local command="$3"
    local name="${4:-$3}"

    if feature_enabled "$feature" "$default"; then
        check_command "$command" "$name"
    else
        pass "$name disabled ($feature=no)"
    fi
}

stm32_bundle_enabled() {
    local manifest="$ROOT_DIR/packages/stm32-bundles.txt"
    local feature
    local bundle

    [[ -f "$manifest" ]] || return 1

    while IFS='|' read -r feature bundle || [[ -n "${feature:-}${bundle:-}" ]]; do
        feature="${feature#"${feature%%[![:space:]]*}"}"
        [[ -z "$feature" || "$feature" == \#* ]] && continue

        if feature_enabled "$feature" yes; then
            return 0
        fi
    done < "$manifest"

    return 1
}

stm32_gcc_path() {
    local manifest="$ROOT_DIR/packages/stm32-bundles.txt"
    local spec

    spec="$(
        awk -F'|' '
            $1 == "ENABLE_STM32_GCC" {
                gsub(/^[[:space:]]+|[[:space:]]+$/, "", $2)
                print $2
                exit
            }
        ' "$manifest"
    )"

    [[ -n "$spec" ]] || return 1

    local version="${spec#*@}"
    printf '%s\n' "$HOME/.local/share/stm32cube/bundles/gnu-tools-for-stm32/$version/bin/arm-none-eabi-gcc"
}

echo; echo "========================================"; echo "Linux Bootstrap Health Check"; echo "========================================"; echo
print_system_info
echo; echo "[INFO] Base / development tools"
check_enabled_command ENABLE_GIT yes git Git
check_enabled_command ENABLE_CURL yes curl curl
if feature_enabled ENABLE_PYTHON_TOOLCHAIN yes; then
    check_enabled_command ENABLE_PYTHON3 yes python3 Python
    check_enabled_command ENABLE_PIPX yes pipx pipx
    check_enabled_command ENABLE_UV yes uv uv
else pass "Python toolchain disabled"; fi
if feature_enabled ENABLE_NODE_TOOLCHAIN yes; then
    check_enabled_command ENABLE_NODEJS yes node Node.js
    feature_enabled ENABLE_NODEJS yes && check_command npm npm
else pass "Node.js toolchain disabled"; fi
if feature_enabled ENABLE_VSCODE yes; then
    check_command code "VS Code"
else
    pass "VS Code configuration disabled"
fi

echo; echo "[INFO] Docker"
if feature_enabled ENABLE_DOCKER yes; then
    feature_enabled ENABLE_DOCKER_CLI yes && check_command docker Docker
    if command -v docker >/dev/null 2>&1; then
        if docker info >/dev/null 2>&1; then pass "Docker daemon is running"
        elif package_installed docker-ce && sudo -n docker info >/dev/null 2>&1; then pass "Docker daemon is running (current shell lacks Docker group access)"
        elif feature_enabled ENABLE_DOCKER_ENGINE yes; then warn "Docker Engine enabled but daemon is unavailable"; fi
    fi
else pass "Docker disabled"; fi

echo; echo "[INFO] STM32"
if feature_enabled ENABLE_STM32 yes; then
    if stm32_bundle_enabled; then
        check_command cube "STM32 cube CLI"
    else
        pass "STM32 cube CLI not required (all bundles disabled)"
    fi

    if feature_enabled ENABLE_STM32_GCC yes; then
        GCC="$(stm32_gcc_path || true)"

        if [[ -n "$GCC" && -x "$GCC" ]]; then
            pass "GNU Arm GCC: $("$GCC" --version | head -n1)"
        else
            warn "GNU Arm GCC enabled but bundle not found"
        fi
    else
        pass "GNU Arm GCC disabled"
    fi

    if feature_enabled ENABLE_STM32CUBEMX yes; then
        if command -v stm32cubemx >/dev/null 2>&1; then
            pass "STM32CubeMX launcher available"
        else
            warn "STM32CubeMX enabled but launcher not found"
        fi
    else
        pass "STM32CubeMX disabled"
    fi

    if feature_enabled ENABLE_USBUTILS yes && command -v lsusb >/dev/null 2>&1; then
        if lsusb | grep -qiE '0483:374[0-9a-f]|0483:375[0-9a-f]'; then
            pass "ST-LINK visible in Linux"
        else
            warn "No ST-LINK currently visible"
        fi
    fi
else
    pass "STM32 development environment disabled"
fi

echo; echo "[INFO] AI tools"
if feature_enabled ENABLE_AI_TOOLS yes; then
    if feature_enabled ENABLE_OPENCODE yes; then command -v opencode >/dev/null 2>&1 && pass "OpenCode: $(opencode --version 2>/dev/null)" || fail "OpenCode enabled but not found"; else pass "OpenCode disabled"; fi
    if feature_enabled ENABLE_CHATGPT no; then package_installed chatgpt && pass "ChatGPT: $(dpkg-query -W -f='${Version}' chatgpt)" || fail "ChatGPT enabled but not installed"; else pass "ChatGPT disabled"; fi
    if feature_enabled ENABLE_ANTIGRAVITY_CLI no; then [[ -x "$HOME/.local/bin/agy" ]] && pass "Antigravity CLI available" || fail "Antigravity CLI enabled but not found"; else pass "Antigravity CLI disabled"; fi
    if feature_enabled ENABLE_ANTIGRAVITY_DESKTOP no; then [[ -x "$HOME/.local/opt/antigravity/current/antigravity" || -x "$HOME/.local/opt/antigravity/current/Antigravity" ]] && pass "Antigravity Desktop available" || fail "Antigravity Desktop enabled but not found"; else pass "Antigravity Desktop disabled"; fi
    if feature_enabled ENABLE_FREEBUFF_CLI no; then check_command freebuff "Freebuff CLI"; else pass "Freebuff CLI disabled"; fi
    if feature_enabled ENABLE_FREEBUFF_DESKTOP no; then [[ -x "$HOME/.local/opt/freebuff/Freebuff.AppImage" ]] && pass "Freebuff Desktop available" || fail "Freebuff Desktop enabled but not found"; else pass "Freebuff Desktop disabled"; fi
    if feature_enabled ENABLE_ZCODE no; then [[ -x "$HOME/.local/opt/zcode/ZCode.AppImage" ]] && pass "ZCode Desktop available" || fail "ZCode enabled but not found"; else pass "ZCode disabled"; fi
    if feature_enabled ENABLE_OLLAMA no; then
        if command -v ollama >/dev/null 2>&1; then
            pass "Ollama installed: $(ollama --version 2>/dev/null | head -n1)"
            command -v curl >/dev/null 2>&1 && curl -fsS http://127.0.0.1:11434/api/tags >/dev/null 2>&1 && pass "Ollama API running" || warn "Ollama enabled but API is inactive"
        else fail "Ollama enabled but not installed"; fi
    else pass "Ollama disabled"; fi
else pass "AI tools disabled"; fi

echo; echo "[INFO] Managed configuration"
if feature_enabled ENABLE_MANAGED_DOTFILES yes; then
    for file in "$HOME/.config/linux-bootstrap/shell.sh" "$HOME/.config/linux-bootstrap/gitconfig" "$HOME/.config/opencode/opencode.jsonc"; do
        [[ -e "$file" ]] && pass "$file" || fail "$file missing"
    done
else pass "Managed dotfiles disabled"; fi

echo; echo "========================================"
[[ "$ERRORS" -eq 0 ]] && echo "[OK] Health check passed" || echo "[FAIL] Health check found $ERRORS error(s)"
[[ "$WARNINGS" -gt 0 ]] && echo "[WARN] $WARNINGS warning(s)"
echo "========================================"
exit "$ERRORS"
