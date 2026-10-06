#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

source "$ROOT_DIR/scripts/helpers.sh"
source "$ROOT_DIR/config/versions.env"
source "$ROOT_DIR/config/cubemx.env"

LOCAL_CONFIG="$ROOT_DIR/config/local.env"
load_local_env "$LOCAL_CONFIG"

CUBEMX_ROOT="$HOME/.local/opt/stm32cubemx"
CUBEMX_CURRENT="$CUBEMX_ROOT/current"

# Default location used by STM32CubeMX interactive installer.
CUBEMX_DEFAULT_INSTALL_DIR="$HOME/STM32CubeMX"

# Filled by detect_cubemx_install().
CUBEMX_INSTALL_DIR=""

CACHE_DIR="$HOME/.cache/linux-bootstrap"
AUTO_INSTALL_XML="$ROOT_DIR/config/cubemx-auto-install.xml"


detect_cubemx_install() {
    local dir

    for dir in \
        "$CUBEMX_ROOT/$CUBEMX_VERSION" \
        "$CUBEMX_DEFAULT_INSTALL_DIR" \
        "$CUBEMX_CURRENT"
    do
        if [[ -x "$dir/STM32CubeMX" ]]; then
            CUBEMX_INSTALL_DIR="$(cd "$dir" && pwd -P)"
            return 0
        fi
    done

    local executable

    executable="$(
        find "$HOME" \
            -maxdepth 4 \
            -type f \
            -name STM32CubeMX \
            -perm -111 \
            -print \
            -quit 2>/dev/null
    )"

    if [[ -n "$executable" ]]; then
        CUBEMX_INSTALL_DIR="$(dirname "$executable")"
        return 0
    fi

    return 1
}


cubemx_installed() {
    detect_cubemx_install
}


windows_download_dir() {
    if ! is_wsl; then
        return 1
    fi

    local powershell
    powershell="/mnt/c/Windows/System32/WindowsPowerShell/v1.0/powershell.exe"

    [[ -x "$powershell" ]] || return 1

    local windows_profile

    windows_profile="$(
        "$powershell" \
            -NoProfile \
            -Command '[Console]::OutputEncoding=[System.Text.Encoding]::UTF8; Write-Output $env:USERPROFILE' \
            2>/dev/null |
        tr -d '\r' |
        tail -n1
    )"

    [[ -n "$windows_profile" ]] || return 1

    local linux_profile
    linux_profile="$(wslpath -u "$windows_profile")"

    printf '%s/Downloads\n' "$linux_profile"
}


find_installer_zip() {
    local version_dash
    version_dash="${CUBEMX_VERSION//./-}"

    local -a search_dirs=(
        "$CACHE_DIR"
        "$HOME/Downloads"
    )

    local win_downloads

    win_downloads="$(windows_download_dir || true)"

    if [[ -n "$win_downloads" ]]; then
        search_dirs+=("$win_downloads")
    fi

    find "${search_dirs[@]}" \
        -maxdepth 1 \
        -type f \
        \( \
            -iname "en.stm32cubemx-lin-v${version_dash}.zip" \
            -o \
            -iname "SetupSTM32CubeMX-${CUBEMX_VERSION}-Lin-x86_64.zip" \
            -o \
            -iname "*stm32cubemx*lin*${version_dash}*.zip" \
            -o \
            -iname "*stm32cubemx*lin*${CUBEMX_VERSION}*.zip" \
        \) \
        -print \
        -quit \
        2>/dev/null
}


validate_zip() {
    local zip="$1"

    if unzip -tq "$zip" >/dev/null 2>&1; then
        log_ok "CubeMX archive passed ZIP integrity check."
        return 0
    fi

    log_error "CubeMX archive is invalid or incomplete:"
    printf '  %s\n' "$zip"

    return 1
}


open_official_download_page() {
    log_info "Opening official STM32CubeMX download page..."

    if is_wsl; then
        local powershell
        powershell="/mnt/c/Windows/System32/WindowsPowerShell/v1.0/powershell.exe"

        if [[ ! -x "$powershell" ]]; then
            die "Windows PowerShell is unavailable."
        fi

        "$powershell" \
            -NoProfile \
            -Command "Start-Process '$CUBEMX_OFFICIAL_PAGE'"

        log_ok "ST download page opened in Windows browser."
        return 0
    fi

    if command_exists xdg-open; then
        xdg-open "$CUBEMX_OFFICIAL_PAGE" >/dev/null 2>&1 &
        log_ok "ST download page opened."
        return 0
    fi

    die "Unable to open browser automatically."
}


wait_for_official_download() {
    local zip

    log_info "Waiting for STM32CubeMX Linux $CUBEMX_VERSION download..."
    log_info "Login/accept the ST download in your browser."
    log_info "The bootstrap will continue automatically when the ZIP finishes downloading."
    log_info "Press Ctrl+C if you want to cancel."

    while true; do

        zip="$(find_installer_zip || true)"

        if [[ -n "$zip" ]]; then

            if validate_zip "$zip"; then
                printf '%s\n' "$zip"
                return 0
            fi

        fi

        sleep 2
    done
}

CUBEMX_ZIP=""

obtain_installer_zip() {
    local zip

    zip="$(find_installer_zip || true)"

    if [[ -n "$zip" ]]; then
        log_ok "Existing STM32CubeMX installer found:"
        printf '  %s\n' "$zip"

        validate_zip "$zip"

        CUBEMX_ZIP="$zip"
        return 0
    fi

    if [[ "$CUBEMX_DOWNLOAD_SOURCE" != "official" ]]; then
        die "Unsupported CubeMX download source: $CUBEMX_DOWNLOAD_SOURCE"
    fi

    open_official_download_page

    log_info "Waiting for STM32CubeMX Linux $CUBEMX_VERSION download..."
    log_info "Complete the download in your Windows browser."
    log_info "The bootstrap will continue automatically when it finishes."
    log_info "Press Ctrl+C to cancel."

    while true; do
        zip="$(find_installer_zip || true)"

        if [[ -n "$zip" ]]; then
            if validate_zip "$zip"; then
                CUBEMX_ZIP="$zip"
                return 0
            fi
        fi

        sleep 2
    done
}

install_cubemx() {
    if detect_cubemx_install; then
        log_ok "STM32CubeMX $CUBEMX_VERSION already installed"
        printf '  %s\n' "$CUBEMX_INSTALL_DIR"
        return 0
    fi

    obtain_installer_zip

    local zip="$CUBEMX_ZIP"

    [[ -n "$zip" && -f "$zip" ]] ||
        die "STM32CubeMX installer archive was not obtained."

    log_ok "STM32CubeMX installer ready:"
    printf '  %s\n' "$zip"

    local temp_dir
    temp_dir="$(mktemp -d)"

    log_info "Extracting STM32CubeMX installer..."

    ensure_apt_dependency ENABLE_UNZIP unzip "STM32CubeMX" yes
    require_command unzip
    unzip -q "$zip" -d "$temp_dir"

    local installer_version
    installer_version="${CUBEMX_VERSION%.*}_${CUBEMX_VERSION##*.}"

    local setup
    setup="$(
        find "$temp_dir" \
            -type f \
            -name "SetupSTM32CubeMX-${installer_version}" \
            -print \
            -quit
    )"

    if [[ -z "$setup" ]]; then
        rm -rf "$temp_dir"
        die "STM32CubeMX setup executable was not found in archive."
    fi

    log_ok "STM32CubeMX setup executable found:"
    printf '  %s\n' "$setup"
    
    chmod +x "$setup"

    ensure_directory "$CUBEMX_ROOT"

    if [[ -f "$AUTO_INSTALL_XML" ]]; then

        log_info "Using CubeMX automatic installation configuration..."

        "$setup" "$AUTO_INSTALL_XML"

    else

        echo
        log_warn "CubeMX automatic installation configuration does not exist yet."
        log_info "Starting interactive STM32CubeMX installer."
        echo

        log_info "Install STM32CubeMX into:"
        printf '  %s\n' "$CUBEMX_INSTALL_DIR"

        echo
        log_info "If the installer offers automatic-install script generation,"
        log_info "save it as:"
        printf '  %s\n' "$AUTO_INSTALL_XML"
        echo

        "$setup"
    fi

    rm -rf "$temp_dir"

    if ! detect_cubemx_install; then
        die "STM32CubeMX installation finished, but the executable could not be located."
    fi

    log_ok "STM32CubeMX $CUBEMX_VERSION installed:"
    printf '  %s\n' "$CUBEMX_INSTALL_DIR"
}


configure_cubemx() {
    if ! detect_cubemx_install; then
        die "STM32CubeMX installation could not be located."
    fi

    ensure_directory "$CUBEMX_ROOT"

    ln -sfn \
        "$CUBEMX_INSTALL_DIR" \
        "$CUBEMX_CURRENT"

    log_ok "STM32CubeMX current installation linked:"
    printf '  %s -> %s\n' \
        "$CUBEMX_CURRENT" \
        "$CUBEMX_INSTALL_DIR"
}


verify_cubemx() {
    local executable
    executable="$CUBEMX_CURRENT/STM32CubeMX"

    if [[ ! -x "$executable" ]]; then
        die "STM32CubeMX executable not found."
    fi

    log_info "STM32CubeMX environment:"

    printf '  Version: %s\n' "$CUBEMX_VERSION"
    printf '  Install: %s\n' "$CUBEMX_INSTALL_DIR"
    printf '  Current: %s\n' "$CUBEMX_CURRENT"
    printf '  Binary:  %s\n' "$executable"

    if is_wsl; then
        if [[ -n "${DISPLAY:-}" || -n "${WAYLAND_DISPLAY:-}" ]]; then
            printf '  GUI:     WSLg available\n'
        else
            printf '  GUI:     no display detected\n'
        fi
    fi
}


main() {
    if ! feature_enabled ENABLE_STM32CUBEMX yes; then
        log_feature_disabled "STM32CubeMX" "ENABLE_STM32CUBEMX"
        return 0
    fi
    install_cubemx
    configure_cubemx
    verify_cubemx
}

main "$@"
