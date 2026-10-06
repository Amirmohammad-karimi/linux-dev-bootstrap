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
