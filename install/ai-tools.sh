#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

source "$ROOT_DIR/scripts/helpers.sh"
source "$ROOT_DIR/config/versions.env"


# ---------------------------------------------------------------------------
# Local machine configuration
# ---------------------------------------------------------------------------

LOCAL_CONFIG="$ROOT_DIR/config/local.env"

ENABLE_CHATGPT="no"
ENABLE_OLLAMA="no"
OLLAMA_MODEL=""

if [[ -f "$LOCAL_CONFIG" ]]; then
    # shellcheck source=/dev/null
    source "$LOCAL_CONFIG"
fi


# ---------------------------------------------------------------------------
# OpenCode
# ---------------------------------------------------------------------------

installed_opencode_version() {
    local opencode_bin=""

    if command_exists opencode; then
        opencode_bin="$(command -v opencode)"
    elif [[ -x "$HOME/.opencode/bin/opencode" ]]; then
        opencode_bin="$HOME/.opencode/bin/opencode"
    else
        return 1
    fi

    "$opencode_bin" --version 2>/dev/null |
        grep -Eo '[0-9]+\.[0-9]+\.[0-9]+' |
        head -n1
}


install_opencode() {
    local installed=""

    installed="$(installed_opencode_version || true)"

    if [[ "$installed" == "$OPENCODE_VERSION" ]]; then
        log_ok "OpenCode $OPENCODE_VERSION already installed"
        return 0
    fi

    if [[ -n "$installed" ]]; then
        log_info "Updating OpenCode $installed -> $OPENCODE_VERSION"
    else
        log_info "Installing OpenCode $OPENCODE_VERSION..."
    fi

    local installer
    installer="$(mktemp)"

    curl -fsSL \
        https://opencode.ai/v2/install \
        -o "$installer"

    bash "$installer" \
        --version "$OPENCODE_VERSION" \
        --no-modify-path

    rm -f "$installer"

    export PATH="$HOME/.opencode/bin:$PATH"

    installed="$(installed_opencode_version || true)"

    if [[ "$installed" != "$OPENCODE_VERSION" ]]; then
        die "OpenCode installation verification failed. Expected $OPENCODE_VERSION, got ${installed:-not found}."
    fi

    log_ok "OpenCode $installed installed."
}


# ---------------------------------------------------------------------------
# ChatGPT desktop app
# ---------------------------------------------------------------------------

chatgpt_installed() {
    dpkg-query \
        -W \
        -f='${Status}' \
        chatgpt \
        2>/dev/null |
        grep -q 'install ok installed'
}


installed_chatgpt_version() {
    if ! chatgpt_installed; then
        return 1
    fi

    dpkg-query \
        -W \
        -f='${Version}' \
        chatgpt \
        2>/dev/null
}


chatgpt_download_url() {
    case "$(uname -m)" in
        x86_64)
            printf '%s\n' \
                'https://persistent.oaistatic.com/codex-app-prod/linux/deb/latest/chatgpt_amd64.deb'
            ;;

        aarch64|arm64)
            printf '%s\n' \
                'https://persistent.oaistatic.com/codex-app-prod/linux/deb/latest/chatgpt_arm64.deb'
            ;;

        *)
            return 1
            ;;
    esac
}


install_chatgpt() {
    if chatgpt_installed; then
        log_ok "ChatGPT already installed ($(installed_chatgpt_version))"
        return 0
    fi

    local url
    url="$(chatgpt_download_url || true)"

    if [[ -z "$url" ]]; then
        log_warn "ChatGPT Linux package unavailable for architecture: $(uname -m)"
        return 0
    fi

    log_info "Installing ChatGPT desktop app..."

    local temp_deb
    temp_deb="$(mktemp --suffix=.deb)"

    curl \
        --proto '=https' \
        --tlsv1.2 \
        -fL \
        "$url" \
        -o "$temp_deb"

    ensure_sudo

    sudo apt-get install -y "$temp_deb"

    rm -f "$temp_deb"

    if ! chatgpt_installed; then
        die "ChatGPT installation verification failed."
    fi

    log_ok "ChatGPT installed ($(installed_chatgpt_version))"
}


verify_chatgpt() {
    if ! chatgpt_installed; then
        return 0
    fi

    printf '  ChatGPT:  %s' "$(installed_chatgpt_version)"

    if is_wsl; then
        if [[ -n "${DISPLAY:-}" || -n "${WAYLAND_DISPLAY:-}" ]]; then
            printf ' (WSLg available)\n'
        else
            printf ' (no GUI display detected)\n'
        fi
    else
        printf '\n'
    fi
}


# ---------------------------------------------------------------------------
# Ollama helpers
# ---------------------------------------------------------------------------

installed_ollama_version() {
    if ! command_exists ollama; then
        return 1
    fi

    ollama --version 2>/dev/null |
        grep -Eo '[0-9]+\.[0-9]+\.[0-9]+' |
        head -n1
}


systemd_available() {
    command_exists systemctl &&
        [[ "$(ps -p 1 -o comm= 2>/dev/null | xargs)" == "systemd" ]]
}


ollama_api_running() {
    curl -fsS \
        http://127.0.0.1:11434/api/tags \
        >/dev/null 2>&1
}


ollama_models_present() {
    local -a model_dirs=()

    if [[ -n "${OLLAMA_MODELS:-}" ]]; then
        model_dirs+=("$OLLAMA_MODELS")
    fi

    model_dirs+=(
        "$HOME/.ollama/models"
        "/usr/share/ollama/.ollama/models"
    )

    local dir

    for dir in "${model_dirs[@]}"; do
        [[ -d "$dir/manifests" ]] || continue

        if find "$dir/manifests" \
            -type f \
            -print \
            -quit \
            2>/dev/null |
            grep -q .; then

            return 0
        fi
    done

    return 1
}


ensure_ollama_requirements() {
    if command_exists zstd; then
        return 0
    fi

    log_info "Installing required Ollama dependency: zstd"
    apt_install zstd
}


# ---------------------------------------------------------------------------
# Ollama installation
# ---------------------------------------------------------------------------

install_ollama() {
    local installed=""

    installed="$(installed_ollama_version || true)"

    if [[ "$installed" == "$OLLAMA_VERSION" ]]; then
        log_ok "Ollama $OLLAMA_VERSION already installed"
        return 0
    fi

    ensure_ollama_requirements

    if [[ -n "$installed" ]]; then
        log_info "Updating Ollama $installed -> $OLLAMA_VERSION"
    else
        log_info "Installing Ollama $OLLAMA_VERSION..."
    fi

    local installer
    installer="$(mktemp)"

    curl -fsSL \
        https://ollama.com/install.sh \
        -o "$installer"

    ensure_sudo

    OLLAMA_VERSION="$OLLAMA_VERSION" \
        sh "$installer"

    rm -f "$installer"

    installed="$(installed_ollama_version || true)"

    if [[ "$installed" != "$OLLAMA_VERSION" ]]; then
        die "Ollama installation verification failed. Expected $OLLAMA_VERSION, got ${installed:-not found}."
    fi

    log_ok "Ollama $installed installed."
}


# ---------------------------------------------------------------------------
# Ollama runtime
# ---------------------------------------------------------------------------

TEMP_OLLAMA_PID=""

start_ollama() {
    if ollama_api_running; then
        log_ok "Ollama API already running"
        return 0
    fi

    if systemd_available; then
        log_info "Starting Ollama service..."

        ensure_sudo
        sudo systemctl start ollama

        return 0
    fi

    log_info "Starting Ollama user process..."

    ensure_directory "$HOME/.cache/linux-bootstrap"

    nohup ollama serve \
        >"$HOME/.cache/linux-bootstrap/ollama.log" \
        2>&1 &

    TEMP_OLLAMA_PID="$!"
}


stop_ollama_if_unused() {
    if systemd_available; then
        ensure_sudo

        sudo systemctl stop ollama >/dev/null 2>&1 || true
        sudo systemctl disable ollama >/dev/null 2>&1 || true

        log_ok "Ollama installed but inactive because no local models exist."
        return 0
    fi

    if [[ -n "$TEMP_OLLAMA_PID" ]]; then
        kill "$TEMP_OLLAMA_PID" >/dev/null 2>&1 || true
        TEMP_OLLAMA_PID=""
    fi

    log_ok "Ollama installed but inactive because no local models exist."
}


enable_ollama_service() {
    if ! systemd_available; then
        return 0
    fi

    ensure_sudo
    sudo systemctl enable ollama >/dev/null 2>&1 || true
}


wait_for_ollama() {
    log_info "Waiting for Ollama API..."

    local attempt

    for ((attempt=1; attempt<=30; attempt++)); do
        if ollama_api_running; then
            log_ok "Ollama API available at http://127.0.0.1:11434"
            return 0
        fi

        sleep 1
    done

    die "Ollama API did not become available."
}


# ---------------------------------------------------------------------------
# Ollama model handling
# ---------------------------------------------------------------------------

ollama_model_installed() {
    local model="$1"

    ollama_api_running || return 1

    ollama list 2>/dev/null |
        awk 'NR > 1 {print $1}' |
        grep -Fxq "$model"
}


ensure_ollama_model() {
    local model="$1"

    [[ -n "$model" ]] || return 0

    start_ollama
    wait_for_ollama

    if ollama_model_installed "$model"; then
        log_ok "Ollama model already installed: $model"
        return 0
    fi

    log_info "Downloading Ollama model: $model"

    ollama pull "$model"

    if ! ollama_model_installed "$model"; then
        die "Ollama model installation failed: $model"
    fi

    log_ok "Ollama model installed: $model"
}


configure_ollama_runtime() {
    if [[ -n "$OLLAMA_MODEL" ]]; then
        ensure_ollama_model "$OLLAMA_MODEL"
        enable_ollama_service

        log_ok "Ollama runtime enabled because a local model is configured."
        return 0
    fi

    if ollama_models_present; then
        log_info "Existing local Ollama models detected."

        start_ollama
        wait_for_ollama
        enable_ollama_service

        log_ok "Ollama runtime enabled."
        return 0
    fi

    stop_ollama_if_unused
}


# ---------------------------------------------------------------------------
# Optional GPU information
# ---------------------------------------------------------------------------

verify_gpu() {
    if ! command_exists nvidia-smi; then
        log_info "nvidia-smi unavailable; skipping NVIDIA GPU detection."
        return 0
    fi

    local gpu=""

    gpu="$(
        nvidia-smi \
            --query-gpu=name \
            --format=csv,noheader \
            2>/dev/null |
        head -n1 || true
    )"

    if [[ -n "$gpu" ]]; then
        log_ok "NVIDIA GPU visible to Linux/WSL:"
        printf '  %s\n' "$gpu"
    else
        log_info "No NVIDIA GPU reported by nvidia-smi."
    fi
}


# ---------------------------------------------------------------------------
# Final verification
# ---------------------------------------------------------------------------

verify_ai_tools() {
    local opencode_version=""
    local ollama_version=""
    local ollama_state="disabled"

    opencode_version="$(installed_opencode_version || true)"

    log_info "AI development environment:"

    printf '  OpenCode: %s\n' "${opencode_version:-not found}"

    if [[ "$ENABLE_CHATGPT" == "yes" ]]; then
        if chatgpt_installed; then
            verify_chatgpt
        else
            printf '  ChatGPT:  not installed\n'
        fi
    else
        printf '  ChatGPT:  disabled by config/local.env\n'
    fi

    if [[ "$ENABLE_OLLAMA" == "yes" ]]; then
        ollama_version="$(installed_ollama_version || true)"

        if ollama_api_running; then
            ollama_state="running"
        elif ollama_models_present; then
            ollama_state="models found, runtime unavailable"
        elif [[ -n "$ollama_version" ]]; then
            ollama_state="installed, inactive (no models)"
        else
            ollama_state="not installed"
        fi

        printf '  Ollama:   %s\n' "${ollama_version:-not found}"
        printf '  Runtime:  %s\n' "$ollama_state"

        if [[ -n "$OLLAMA_MODEL" ]]; then
            printf '  Model:    %s\n' "$OLLAMA_MODEL"
        fi
    else
        printf '  Ollama:   disabled by config/local.env\n'
    fi
}


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

main() {
    install_opencode

    case "${ENABLE_CHATGPT,,}" in
        yes|true|1)
            ENABLE_CHATGPT="yes"
            install_chatgpt
            ;;

        no|false|0|"")
            ENABLE_CHATGPT="no"
            log_info "ChatGPT disabled by config/local.env"
            ;;

        *)
            die "Invalid ENABLE_CHATGPT value: $ENABLE_CHATGPT. Use yes or no."
            ;;
    esac

    case "${ENABLE_OLLAMA,,}" in
        yes|true|1)
            ENABLE_OLLAMA="yes"

            install_ollama
            configure_ollama_runtime
            verify_gpu
            ;;

        no|false|0|"")
            ENABLE_OLLAMA="no"
            log_info "Ollama disabled by config/local.env"
            ;;

        *)
            die "Invalid ENABLE_OLLAMA value: $ENABLE_OLLAMA. Use yes or no."
            ;;
    esac

    verify_ai_tools
}

main "$@"
