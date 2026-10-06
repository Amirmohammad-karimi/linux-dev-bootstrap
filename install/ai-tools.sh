#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

source "$ROOT_DIR/scripts/helpers.sh"
source "$ROOT_DIR/config/versions.env"
SCRIPT_DIR="$(
    cd "$(dirname "${BASH_SOURCE[0]}")" >/dev/null 2>&1
    pwd
)"

REPO_ROOT="$(
    cd "$SCRIPT_DIR/.." >/dev/null 2>&1
    pwd
)"

ANTIGRAVITY_PATCHER_SCRIPT="$REPO_ROOT/scripts/antigravity-patcher.sh"


# ---------------------------------------------------------------------------
# Local machine configuration
# ---------------------------------------------------------------------------

LOCAL_CONFIG="$ROOT_DIR/config/local.env"

ENABLE_CHATGPT="no"
ENABLE_ANTIGRAVITY_CLI="no"
ENABLE_ANTIGRAVITY_DESKTOP="no"
ENABLE_FREEBUFF_CLI="no"
ENABLE_FREEBUFF_DESKTOP="no"
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
# Antigravity CLI
# ---------------------------------------------------------------------------

antigravity_cli_installed() {
    [[ -x "$HOME/.local/bin/agy" ]]
}


installed_antigravity_cli_version() {
    if ! antigravity_cli_installed; then
        return 1
    fi

    "$HOME/.local/bin/agy" --version 2>/dev/null |
        head -n1
}


install_antigravity_cli() {
    if antigravity_cli_installed; then
        log_ok "Antigravity CLI already installed ($(installed_antigravity_cli_version))"
        return 0
    fi

    log_info "Installing Antigravity CLI..."

    curl -fsSL \
        https://antigravity.google/cli/install.sh |
        bash

    if ! antigravity_cli_installed; then
        die "Antigravity CLI installation verification failed."
    fi

    log_ok "Antigravity CLI installed ($(installed_antigravity_cli_version))"
}

# ---------------------------------------------------------------------------
# Antigravity Desktop
# ---------------------------------------------------------------------------

ANTIGRAVITY_DESKTOP_ROOT="$HOME/.local/opt/antigravity"
ANTIGRAVITY_DESKTOP_CURRENT="$ANTIGRAVITY_DESKTOP_ROOT/current"
ANTIGRAVITY_DOWNLOAD_PAGE="https://www.antigravity.google/download?os=linux"


antigravity_desktop_binary() {
    local candidate

    for candidate in \
        "$ANTIGRAVITY_DESKTOP_CURRENT/antigravity" \
        "$ANTIGRAVITY_DESKTOP_CURRENT/Antigravity"
    do
        if [[ -x "$candidate" ]]; then
            printf '%s\n' "$candidate"
            return 0
        fi
    done

    return 1
}


antigravity_desktop_installed() {
    antigravity_desktop_binary >/dev/null 2>&1
}


installed_antigravity_desktop_version() {
    if ! antigravity_desktop_installed; then
        return 1
    fi

    if [[ -L "$ANTIGRAVITY_DESKTOP_CURRENT" ]]; then
        basename "$(readlink -f "$ANTIGRAVITY_DESKTOP_CURRENT")"
        return 0
    fi

    local binary
    binary="$(antigravity_desktop_binary)"

    "$binary" --version 2>/dev/null |
        head -n1
}


resolve_antigravity_download() {
    local platform

    case "$(uname -m)" in
        x86_64)
            platform="linux-x64"
            ;;

        aarch64|arm64)
            platform="linux-arm"
            ;;

        *)
            die "Unsupported Antigravity architecture: $(uname -m)"
            ;;
    esac

    local page
    page="$(curl -fsSL "$ANTIGRAVITY_DOWNLOAD_PAGE")"

    local url

    url="$(
        printf '%s' "$page" |
        grep -oE \
            "https://storage\.googleapis\.com/antigravity-public/antigravity-hub/[^\"']+/${platform}/Antigravity\.tar\.gz" |
        head -n1
    )"

    if [[ -z "$url" ]]; then
        die "Could not resolve official Antigravity Linux download URL."
    fi

    printf '%s\n' "$url"
}


install_antigravity_desktop() {
    if antigravity_desktop_installed; then
        log_ok "Antigravity desktop already installed ($(installed_antigravity_desktop_version))"
        return 0
    fi

    log_info "Resolving latest official Antigravity desktop release..."

    local url
    url="$(resolve_antigravity_download)"

    local release_id
    release_id="$(
        printf '%s\n' "$url" |
        sed -E 's#^.*/antigravity-hub/([^/]+)/.*$#\1#'
    )"

    local version
    version="${release_id%%-*}"

    log_info "Antigravity desktop version: $version"

    local temp_dir
    temp_dir="$(mktemp -d)"

    local archive
    archive="$temp_dir/Antigravity.tar.gz"

    log_info "Downloading Antigravity desktop..."

    curl \
        --proto '=https' \
        --tlsv1.2 \
        --fail \
        --location \
        --retry 3 \
        "$url" \
        -o "$archive"

    if ! tar -tzf "$archive" >/dev/null 2>&1; then
        rm -rf "$temp_dir"
        die "Downloaded Antigravity archive is invalid."
    fi

    log_ok "Antigravity archive validated."

    local extract_dir
    extract_dir="$temp_dir/extracted"

    mkdir -p "$extract_dir"

    tar -xzf "$archive" \
        -C "$extract_dir"

    local binary
    binary="$(
        find "$extract_dir" \
            -type f \
            \( -name antigravity -o -name Antigravity \) \
            -perm -111 \
            -print \
            -quit
    )"

    if [[ -z "$binary" ]]; then
        log_info "Extracted Antigravity files:"
        find "$extract_dir" -maxdepth 3 -type f | head -50

        rm -rf "$temp_dir"

        die "Antigravity executable was not found in archive."
    fi

    local source_dir
    source_dir="$(dirname "$binary")"

    local version_dir
    version_dir="$ANTIGRAVITY_DESKTOP_ROOT/$version"

    ensure_directory "$ANTIGRAVITY_DESKTOP_ROOT"

    rm -rf "$version_dir"

    mv "$source_dir" "$version_dir"

    ln -sfn \
        "$version_dir" \
        "$ANTIGRAVITY_DESKTOP_CURRENT"

    rm -rf "$temp_dir"

    if ! antigravity_desktop_installed; then
        die "Antigravity desktop installation verification failed."
    fi

    log_ok "Antigravity desktop $version installed."
}

# ---------------------------------------------------------------------------
# Freebuff CLI
# ---------------------------------------------------------------------------

freebuff_cli_installed() {
    command -v freebuff >/dev/null 2>&1
}

installed_freebuff_cli_version() {
    if ! freebuff_cli_installed; then
        return 1
    fi

    local version

    version="$(
        npm list -g freebuff \
            --depth=0 \
            --json \
            2>/dev/null |
        jq -r '.dependencies.freebuff.version // empty'
    )"

    if [[ -n "$version" ]]; then
        printf '%s\n' "$version"
    else
        printf '%s\n' "installed"
    fi
}

install_freebuff_cli() {
    if freebuff_cli_installed; then
        log_ok "Freebuff CLI already installed ($(installed_freebuff_cli_version))"
        return 0
    fi

    command -v npm >/dev/null 2>&1 ||
        die "npm is required to install Freebuff CLI."

    log_info "Installing Freebuff CLI..."

    npm install -g freebuff

    if ! freebuff_cli_installed; then
        die "Freebuff CLI installation verification failed."
    fi

    log_ok "Freebuff CLI installed ($(installed_freebuff_cli_version))"
}


# ---------------------------------------------------------------------------
# Freebuff Desktop
# ---------------------------------------------------------------------------

FREEBUFF_DESKTOP_ROOT="$HOME/.local/opt/freebuff"
FREEBUFF_DESKTOP_APPIMAGE="$FREEBUFF_DESKTOP_ROOT/Freebuff.AppImage"

freebuff_desktop_installed() {
    [[ -x "$FREEBUFF_DESKTOP_APPIMAGE" ]]
}

freebuff_desktop_download_url() {
    case "$(uname -m)" in
        x86_64)
            printf '%s\n' \
                "https://freebuff.com/api/desktop/download/linux"
            ;;

        aarch64|arm64)
            printf '%s\n' \
                "https://freebuff.com/api/desktop/download/linux-arm64"
            ;;

        *)
            die "Unsupported Freebuff architecture: $(uname -m)"
            ;;
    esac
}

install_freebuff_desktop() {

    if ! ldconfig -p 2>/dev/null | grep -q 'libfuse.so.2'; then
        log_info "Installing FUSE 2 compatibility library..."

        apt_install libfuse2t64

        log_ok "FUSE 2 compatibility library installed."
    fi
    
    if freebuff_desktop_installed; then
        log_ok "Freebuff Desktop already installed"
        return 0
    fi

    local url
    url="$(freebuff_desktop_download_url)"

    local temp_dir
    temp_dir="$(mktemp -d)"

    local appimage
    appimage="$temp_dir/Freebuff.AppImage"

    log_info "Downloading Freebuff Desktop..."

    curl \
        --proto '=https' \
        --tlsv1.2 \
        --fail \
        --location \
        --retry 3 \
        "$url" \
        -o "$appimage"

    if [[ ! -s "$appimage" ]]; then
        rm -rf "$temp_dir"
        die "Downloaded Freebuff AppImage is empty."
    fi

    chmod +x "$appimage"

    mkdir -p "$FREEBUFF_DESKTOP_ROOT"

    mv "$appimage" "$FREEBUFF_DESKTOP_APPIMAGE"

    rm -rf "$temp_dir"

    if ! freebuff_desktop_installed; then
        die "Freebuff Desktop installation verification failed."
    fi

    log_ok "Freebuff Desktop installed."
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

    if [[ "$ENABLE_ANTIGRAVITY_CLI" == "yes" ]]; then
        if antigravity_cli_installed; then
            printf '  Antigravity CLI:     %s\n' \
                "$(installed_antigravity_cli_version)"
        else
            printf '  Antigravity CLI:     not installed\n'
        fi
    else
        printf '  Antigravity CLI:     disabled by local.env\n'
    fi


    if [[ "$ENABLE_ANTIGRAVITY_DESKTOP" == "yes" ]]; then
        if antigravity_desktop_installed; then
            printf '  Antigravity desktop: %s\n' \
                "$(installed_antigravity_desktop_version)"
        else
            printf '  Antigravity desktop: not installed\n'
        fi
    else
        printf '  Antigravity desktop: disabled by local.env\n'
    fi

    if [[ "${ENABLE_FREEBUFF_CLI:-no}" == "yes" ]]; then
        if freebuff_cli_installed; then
            echo "  Freebuff CLI:        $(installed_freebuff_cli_version)"
        else
            echo "  Freebuff CLI:        not installed"
        fi
    else
        echo "  Freebuff CLI:        disabled"
    fi

    if [[ "${ENABLE_FREEBUFF_DESKTOP:-no}" == "yes" ]]; then
        if freebuff_desktop_installed; then
            echo "  Freebuff Desktop:    installed"
        else
            echo "  Freebuff Desktop:    not installed"
        fi
    else
        echo "  Freebuff Desktop:    disabled"
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

    case "${ENABLE_ANTIGRAVITY_CLI,,}" in
        yes|true|1)
            ENABLE_ANTIGRAVITY_CLI="yes"
            install_antigravity_cli
            #"$ANTIGRAVITY_PATCHER_SCRIPT" cli
            ;;

        no|false|0|"")
            ENABLE_ANTIGRAVITY_CLI="no"
            log_info "Antigravity CLI disabled by config/local.env"
            ;;

        *)
            die "Invalid ENABLE_ANTIGRAVITY_CLI value: $ENABLE_ANTIGRAVITY_CLI. Use yes or no."
            ;;
    esac


case "${ENABLE_ANTIGRAVITY_DESKTOP,,}" in
    yes|true|1)
        ENABLE_ANTIGRAVITY_DESKTOP="yes"

        install_antigravity_desktop

        ANTIGRAVITY_MANAGER="$HOME/.local/opt/antigravity/current/resources/bin/language_server"

        if command -v fuser >/dev/null 2>&1 &&
           fuser "$ANTIGRAVITY_MANAGER" >/dev/null 2>&1
        then
            log_error "Antigravity is currently running."
            log_error "Close Antigravity Desktop and rerun the AI setup."
            exit 1
        fi

        "$ANTIGRAVITY_PATCHER_SCRIPT" manager
        ;;

    no|false|0|"")
        ENABLE_ANTIGRAVITY_DESKTOP="no"
        log_info "Antigravity desktop disabled by config/local.env"
        ;;

    *)
        die "Invalid ENABLE_ANTIGRAVITY_DESKTOP value: $ENABLE_ANTIGRAVITY_DESKTOP. Use yes or no."
        ;;
esac

    # ---------------------------------------------------------------------------
    # Freebuff CLI
    # ---------------------------------------------------------------------------

    case "${ENABLE_FREEBUFF_CLI,,}" in
        yes|true|1)
            ENABLE_FREEBUFF_CLI="yes"
            install_freebuff_cli
            ;;

        no|false|0|"")
            ENABLE_FREEBUFF_CLI="no"
            log_info "Freebuff CLI disabled by config/local.env"
            ;;

        *)
            die "Invalid ENABLE_FREEBUFF_CLI value: $ENABLE_FREEBUFF_CLI. Use yes or no."
            ;;
    esac


    # ---------------------------------------------------------------------------
    # Freebuff Desktop
    # ---------------------------------------------------------------------------

    case "${ENABLE_FREEBUFF_DESKTOP,,}" in
        yes|true|1)
            ENABLE_FREEBUFF_DESKTOP="yes"
            install_freebuff_desktop
            ;;

        no|false|0|"")
            ENABLE_FREEBUFF_DESKTOP="no"
            log_info "Freebuff Desktop disabled by config/local.env"
            ;;

        *)
            die "Invalid ENABLE_FREEBUFF_DESKTOP value: $ENABLE_FREEBUFF_DESKTOP. Use yes or no."
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
