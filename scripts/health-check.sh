#!/usr/bin/env bash

set -u

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

source "$ROOT_DIR/scripts/helpers.sh"

LOCAL_CONFIG="$ROOT_DIR/config/local.env"

ENABLE_CHATGPT="no"
ENABLE_OLLAMA="no"
OLLAMA_MODEL=""

if [[ -f "$LOCAL_CONFIG" ]]; then
    # shellcheck source=/dev/null
    source "$LOCAL_CONFIG"
fi

ERRORS=0
WARNINGS=0

pass() {
    printf '[OK]   %s\n' "$1"
}

warn() {
    printf '[WARN] %s\n' "$1"
    WARNINGS=$((WARNINGS + 1))
}

fail() {
    printf '[FAIL] %s\n' "$1"
    ERRORS=$((ERRORS + 1))
}

check_command() {
    local command="$1"
    local name="${2:-$1}"

    if command -v "$command" >/dev/null 2>&1; then
        pass "$name: $(command -v "$command")"
    else
        fail "$name not found"
    fi
}

echo
echo "========================================"
echo "Linux Bootstrap Health Check"
echo "========================================"
echo

print_system_info

echo
echo "[INFO] Core tools"

check_command git
check_command curl
check_command python3
check_command pipx
check_command uv
check_command node
check_command npm
check_command docker
check_command code "VS Code"
check_command opencode "OpenCode"

echo
echo "[INFO] Docker"

if command -v docker >/dev/null 2>&1; then
    if docker info >/dev/null 2>&1; then
        pass "Docker daemon is running"
    else
        warn "Docker CLI exists but daemon is unavailable"
    fi
fi

echo
echo "[INFO] STM32"

check_command cube "STM32 cube CLI"

GCC="$HOME/.local/share/stm32cube/bundles/gnu-tools-for-stm32/14.3.1+st.2/bin/arm-none-eabi-gcc"

if [[ -x "$GCC" ]]; then
    pass "GNU Arm GCC: $("$GCC" --version | head -n1)"
else
    warn "GNU Arm GCC bundle not found"
fi

if command -v stm32cubemx >/dev/null 2>&1; then
    pass "STM32CubeMX launcher available"
else
    warn "STM32CubeMX launcher not found"
fi

if command -v lsusb >/dev/null 2>&1; then
    if lsusb | grep -qiE '0483:374[0-9a-f]|0483:375[0-9a-f]'; then
        pass "ST-LINK visible in Linux"
    else
        warn "No ST-LINK currently visible"
    fi
fi

echo
echo "[INFO] AI tools"

if command -v opencode >/dev/null 2>&1; then
    pass "OpenCode: $(opencode --version 2>/dev/null)"
else
    fail "OpenCode not found"
fi

case "${ENABLE_CHATGPT,,}" in
    yes|true|1)
        if dpkg-query -W -f='${Status}' chatgpt 2>/dev/null |
            grep -q 'install ok installed'; then

            pass "ChatGPT: $(dpkg-query -W -f='${Version}' chatgpt)"
        else
            fail "ChatGPT enabled in local.env but not installed"
        fi
        ;;

    *)
        if dpkg-query -W -f='${Status}' chatgpt 2>/dev/null |
            grep -q 'install ok installed'; then
            pass "ChatGPT installed (not required by local.env)"
        else
            pass "ChatGPT disabled by local.env"
        fi
        ;;
esac

case "${ENABLE_OLLAMA,,}" in
    yes|true|1)
        if command -v ollama >/dev/null 2>&1; then
            pass "Ollama installed: $(ollama --version 2>/dev/null | head -n1)"

            if curl -fsS \
                http://127.0.0.1:11434/api/tags \
                >/dev/null 2>&1; then

                pass "Ollama API running"
            else
                warn "Ollama enabled but API is inactive"
            fi
        else
            fail "Ollama enabled in local.env but not installed"
        fi
        ;;

    *)
        if command -v ollama >/dev/null 2>&1; then
            pass "Ollama installed but disabled by local.env"
        else
            pass "Ollama disabled by local.env"
        fi
        ;;
esac

echo
echo "[INFO] Managed configuration"

for file in \
    "$HOME/.config/linux-bootstrap/shell.sh" \
    "$HOME/.config/linux-bootstrap/gitconfig" \
    "$HOME/.config/opencode/opencode.jsonc"
do
    if [[ -e "$file" ]]; then
        pass "$file"
    else
        fail "$file missing"
    fi
done

echo
echo "========================================"

if [[ "$ERRORS" -eq 0 ]]; then
    echo "[OK] Health check passed"
else
    echo "[FAIL] Health check found $ERRORS error(s)"
fi

if [[ "$WARNINGS" -gt 0 ]]; then
    echo "[WARN] $WARNINGS warning(s)"
fi

echo "========================================"

exit "$ERRORS"
