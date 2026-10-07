#!/usr/bin/env bash

# Shared helper functions for linux-bootstrap.

# ---------------------------------------------------------------------------
# Logging
# ---------------------------------------------------------------------------

log_info() {
    printf '[INFO] %s\n' "$*"
}

log_ok() {
    printf '[OK]   %s\n' "$*"
}

log_warn() {
    printf '[WARN] %s\n' "$*" >&2
}

log_error() {
    printf '[ERROR] %s\n' "$*" >&2
}

die() {
    log_error "$*"
    exit 1
}

# ---------------------------------------------------------------------------
# Command checks
# ---------------------------------------------------------------------------

command_exists() {
    command -v "$1" >/dev/null 2>&1
}

require_command() {
    local command_name="$1"

    if ! command_exists "$command_name"; then
        die "Required command not found: $command_name"
    fi
}

# ---------------------------------------------------------------------------
# Machine-local configuration / feature flags
# ---------------------------------------------------------------------------

load_local_env() {
    local file="$1"

    if [[ -f "$file" ]]; then
        # shellcheck source=/dev/null
        source "$file"
    fi
}

load_proxy_environment() {
    local file="$1"

    [[ -f "$file" ]] || return 0

    local PROXY_ENABLED="no"
    local HTTP_PROXY_URL=""
    local HTTPS_PROXY_URL=""
    local NO_PROXY=""

    # shellcheck source=/dev/null
    source "$file"

    if ! feature_enabled PROXY_ENABLED no; then
        return 0
    fi

    [[ -n "$HTTP_PROXY_URL" ]] ||
        die "PROXY_ENABLED=yes requires HTTP_PROXY_URL in $file"

    [[ -n "$HTTPS_PROXY_URL" ]] ||
        HTTPS_PROXY_URL="$HTTP_PROXY_URL"

    export HTTP_PROXY="$HTTP_PROXY_URL"
    export HTTPS_PROXY="$HTTPS_PROXY_URL"
    export http_proxy="$HTTP_PROXY_URL"
    export https_proxy="$HTTPS_PROXY_URL"

    if [[ -n "$NO_PROXY" ]]; then
        export NO_PROXY
        export no_proxy="$NO_PROXY"
    fi

    log_ok "Proxy environment enabled for bootstrap downloads."
}

feature_enabled() {
    local variable="$1"
    local default="${2:-no}"
    local value

    if declare -p "$variable" >/dev/null 2>&1; then
        value="${!variable}"
    else
        value="$default"
    fi

    case "${value,,}" in
        yes|true|1|on) return 0 ;;
        no|false|0|off|"") return 1 ;;
        *) die "Invalid value for $variable: $value. Use yes or no." ;;
    esac
}

log_feature_disabled() {
    local name="$1"
    local variable="${2:-}"

    if [[ -n "$variable" ]]; then
        log_info "$name disabled ($variable=no)"
    else
        log_info "$name disabled by config/local.env"
    fi
}

ensure_apt_dependency() {
    local variable="$1"
    local package="$2"
    local consumer="$3"
    local default="${4:-yes}"

    if package_installed "$package"; then
        return 0
    fi

    if feature_enabled "$variable" "$default"; then
        apt_install "$package"
        return 0
    fi

    die "$consumer requires package '$package'. Set $variable=yes or install the package manually."
}

# ---------------------------------------------------------------------------
# System detection
# ---------------------------------------------------------------------------

is_linux() {
    [[ "$(uname -s)" == "Linux" ]]
}

is_wsl() {
    if [[ -n "${WSL_DISTRO_NAME:-}" ]]; then
        return 0
    fi

    grep -qiE '(microsoft|wsl)' /proc/version 2>/dev/null
}

ubuntu_version() {
    if [[ -r /etc/os-release ]]; then
        (
            source /etc/os-release
            printf '%s\n' "${VERSION_ID:-unknown}"
        )
    else
        printf 'unknown\n'
    fi
}

architecture() {
    uname -m
}

# ---------------------------------------------------------------------------
# sudo
# ---------------------------------------------------------------------------

SUDO_KEEPALIVE_PID=""

start_sudo_session() {
    if [[ "$EUID" -eq 0 ]]; then
        return 0
    fi

    if ! command_exists sudo; then
        die "sudo is required but is not installed."
    fi

    log_info "Authenticating sudo for bootstrap..."

    sudo -v ||
        die "sudo authentication failed."

    # Refresh the sudo timestamp while the bootstrap is running so later
    # install scripts do not repeatedly prompt for the user's password.
    (
        while true; do
            sleep 60
            sudo -n -v >/dev/null 2>&1 || exit
        done
    ) &

    SUDO_KEEPALIVE_PID="$!"

    log_ok "sudo session active."
}

stop_sudo_session() {
    if [[ -n "${SUDO_KEEPALIVE_PID:-}" ]]; then
        kill "$SUDO_KEEPALIVE_PID" >/dev/null 2>&1 || true
        wait "$SUDO_KEEPALIVE_PID" 2>/dev/null || true
        SUDO_KEEPALIVE_PID=""
    fi
}

ensure_sudo() {
    if [[ "$EUID" -eq 0 ]]; then
        return 0
    fi

    if ! command_exists sudo; then
        die "sudo is required but is not installed."
    fi

    sudo -v
}

# ---------------------------------------------------------------------------
# APT
# ---------------------------------------------------------------------------

APT_UPDATED=0

apt_update() {
    if [[ "$APT_UPDATED" -eq 1 ]]; then
        return 0
    fi

    ensure_sudo

    log_info "Updating APT package index..."

    sudo apt-get \
        -o APT::Update::Error-Mode=any \
        -o Acquire::Retries=3 \
        update

    APT_UPDATED=1

    log_ok "APT package index updated."
}

package_installed() {
    dpkg-query -W -f='${Status}' "$1" 2>/dev/null |
        grep -q "install ok installed"
}

apt_install() {
    local packages=()
    local package

    for package in "$@"; do
        if package_installed "$package"; then
            log_ok "$package already installed"
        else
            packages+=("$package")
        fi
    done

    if [[ "${#packages[@]}" -eq 0 ]]; then
        return 0
    fi

    apt_update

    log_info "Installing: ${packages[*]}"

    ensure_sudo
    sudo DEBIAN_FRONTEND=noninteractive apt-get install -y "${packages[@]}"

    log_ok "Installed: ${packages[*]}"
}

# ---------------------------------------------------------------------------
# Files and directories
# ---------------------------------------------------------------------------

ensure_directory() {
    local directory="$1"

    if [[ ! -d "$directory" ]]; then
        mkdir -p "$directory"
        log_ok "Created directory: $directory"
    fi
}

backup_file() {
    local file="$1"

    if [[ ! -e "$file" ]]; then
        return 0
    fi

    local backup="${file}.backup.$(date +%Y%m%d-%H%M%S)"

    cp -a "$file" "$backup"

    log_ok "Backup created: $backup"
}

append_line_if_missing() {
    local line="$1"
    local file="$2"

    ensure_directory "$(dirname "$file")"

    touch "$file"

    if grep -Fqx "$line" "$file"; then
        log_ok "Configuration already present in $file"
    else
        printf '%s\n' "$line" >> "$file"
        log_ok "Added configuration to $file"
    fi
}

# ---------------------------------------------------------------------------
# Downloads
# ---------------------------------------------------------------------------

download_file() {
    local url="$1"
    local destination="$2"

    ensure_directory "$(dirname "$destination")"

    if command_exists curl; then
        log_info "Downloading: $url"
        curl --fail --location --retry 3 \
            --output "$destination" "$url"

    elif command_exists wget; then
        log_info "Downloading: $url"
        wget --tries=3 \
            --output-document="$destination" "$url"

    else
        die "Neither curl nor wget is installed."
    fi

    log_ok "Downloaded: $destination"
}

# ---------------------------------------------------------------------------
# Symbolic links
# ---------------------------------------------------------------------------

create_symlink() {
    local source="$1"
    local destination="$2"

    ensure_directory "$(dirname "$destination")"

    if [[ -L "$destination" ]]; then
        local current_target
        current_target="$(readlink "$destination")"

        if [[ "$current_target" == "$source" ]]; then
            log_ok "Symlink already correct: $destination"
            return 0
        fi

        rm "$destination"
    elif [[ -e "$destination" ]]; then
        backup_file "$destination"
        rm -rf "$destination"
    fi

    ln -s "$source" "$destination"

    log_ok "Created symlink: $destination -> $source"
}

# ---------------------------------------------------------------------------
# Bootstrap utilities
# ---------------------------------------------------------------------------

print_system_info() {
    log_info "System information"
    printf '  OS:           %s\n' "$(uname -s)"
    printf '  Architecture: %s\n' "$(architecture)"
    printf '  Ubuntu:       %s\n' "$(ubuntu_version)"

    if is_wsl; then
        printf '  Environment:  WSL\n'
    else
        printf '  Environment:  Native Linux\n'
    fi
}
