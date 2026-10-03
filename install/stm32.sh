#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

source "$ROOT_DIR/scripts/helpers.sh"

STM32_EXTENSION="stmicroelectronics.stm32-vscode-extension"
STM32_CORE_EXTENSION="stmicroelectronics.stm32cube-ide-core"

BUNDLE_FILE="$ROOT_DIR/packages/stm32-bundles.txt"

export CUBE_BUNDLE_PATH="${CUBE_BUNDLE_PATH:-$HOME/.local/share/stm32cube/bundles}"
export CMSIS_PACK_ROOT="${CMSIS_PACK_ROOT:-$HOME/.local/share/stm32cube/packs}"

CUBE_BIN=""

install_stm32_extension() {
    require_command code

    local extensions
    extensions="$(code --list-extensions 2>/dev/null || true)"

    if grep -Fxi "$STM32_EXTENSION" <<< "$extensions" >/dev/null; then
        log_ok "STM32Cube VS Code extension pack already installed"
        return 0
    fi

    log_info "Installing STM32Cube VS Code extension pack..."

    code --install-extension "$STM32_EXTENSION"

    log_ok "STM32Cube VS Code extension pack installed."
}

find_cube_cli() {
    if command_exists cube; then
        CUBE_BIN="$(command -v cube)"
        log_ok "cube CLI found: $CUBE_BIN"
        return 0
    fi

    CUBE_BIN="$(
        find "$HOME/.vscode-server/extensions" \
            -path '*/stmicroelectronics.stm32cube-ide-core-*/*' \
            -type f \
            -name cube \
            -perm -111 \
            -print \
            -quit \
            2>/dev/null
    )"

    if [[ -z "$CUBE_BIN" ]]; then
        die "cube CLI was not found in the WSL VS Code Server extensions."
    fi

    log_ok "cube CLI found: $CUBE_BIN"
}

prepare_directories() {
    ensure_directory "$CUBE_BUNDLE_PATH"
    ensure_directory "$CMSIS_PACK_ROOT"

    log_ok "STM32Cube directories ready"
}

bundle_installed() {
    local specification="$1"

    local name="${specification%@*}"
    local version="${specification#*@}"

    [[ -d "$CUBE_BUNDLE_PATH/$name/$version" ]]
}

install_bundles() {
    [[ -f "$BUNDLE_FILE" ]] ||
        die "STM32 bundle manifest not found: $BUNDLE_FILE"

    log_info "Checking STM32Cube bundles..."

    local install_help
    local yes_args=()

    install_help="$(
        "$CUBE_BIN" bundle install --help 2>&1 || true
    )"

    if grep -F -- '--yes' <<< "$install_help" >/dev/null; then
        yes_args=(--yes)
    fi

    local bundle

    while IFS= read -r bundle || [[ -n "$bundle" ]]; do

        bundle="${bundle#"${bundle%%[![:space:]]*}"}"
        bundle="${bundle%"${bundle##*[![:space:]]}"}"

        [[ -z "$bundle" ]] && continue
        [[ "$bundle" == \#* ]] && continue

        if bundle_installed "$bundle"; then
            log_ok "$bundle already installed"
            continue
        fi

        log_info "Installing STM32 bundle: $bundle"

        "$CUBE_BIN" bundle install "$bundle" "${yes_args[@]}"

        if bundle_installed "$bundle"; then
            log_ok "Installed: $bundle"
        else
            die "Bundle installation did not produce expected directory: $bundle"
        fi

    done < "$BUNDLE_FILE"
}

install_usb_dependencies() {
    log_info "Installing STM32 USB dependencies..."

    apt_install \
        libusb-1.0-0 \
        libusb-1.0-0-dev \
        udev \
        usbutils

    log_ok "STM32 USB dependencies installed."
}

install_udev_rules() {
    local spec
    local version
    local bundle_dir
    local deb
    local package_name

    spec="$(
        grep -E '^stlink-udev-rules@' "$BUNDLE_FILE" |
        head -n1 || true
    )"

    if [[ -z "$spec" ]]; then
        log_warn "ST-LINK udev-rules bundle is not configured."
        return 0
    fi

    version="${spec#*@}"
    bundle_dir="$CUBE_BUNDLE_PATH/stlink-udev-rules/$version"

    deb="$(
        find "$bundle_dir/bin" \
            -maxdepth 1 \
            -type f \
            -name 'st-stlink-udev-rules-*-linux-all.deb' \
            -print \
            -quit
    )"

    if [[ -z "$deb" || ! -f "$deb" ]]; then
        die "ST-LINK udev-rules .deb package not found."
    fi

    package_name="$(dpkg-deb -f "$deb" Package)"

    if dpkg-query -W -f='${Status}' "$package_name" 2>/dev/null |
        grep -q 'install ok installed'; then

        log_ok "ST-LINK udev rules already installed ($package_name)"
    else
        log_info "Installing ST-LINK udev rules..."

        ensure_sudo

    local temp_deb

    temp_deb="/tmp/$(basename "$deb")"

    cp "$deb" "$temp_deb"
    chmod 0644 "$temp_deb"

    sudo apt-get install -y "$temp_deb"

    rm -f "$temp_deb"

        log_ok "ST-LINK udev rules installed."
    fi

    if command_exists udevadm; then
        sudo udevadm control --reload-rules
        sudo udevadm trigger
    fi
}        

verify_stm32() {
    log_info "STM32 environment:"

    printf '  Bundle path: %s\n' "$CUBE_BUNDLE_PATH"
    printf '  CMSIS packs: %s\n' "$CMSIS_PACK_ROOT"
    printf '  cube CLI:    %s\n' "$CUBE_BIN"

    local gcc_spec
    local gcc_version
    local gcc

    gcc_spec="$(
        grep -E '^gnu-tools-for-stm32@' "$BUNDLE_FILE" |
        head -n1
    )"

    gcc_version="${gcc_spec#*@}"

    gcc="$CUBE_BUNDLE_PATH/gnu-tools-for-stm32/$gcc_version/bin/arm-none-eabi-gcc"

    if [[ -x "$gcc" ]]; then
        printf '  GCC:         %s\n' \
            "$("$gcc" --version | head -n1)"
    else
        log_warn "arm-none-eabi-gcc executable was not found."
    fi

    local count
    count="$(
        grep -Ev '^[[:space:]]*(#|$)' "$BUNDLE_FILE" |
        wc -l
    )"

    printf '  Bundles:     %s configured\n' "$count"
}

verify_stlink() {
    local usb_ids_file="$ROOT_DIR/config/stlink-usb-ids.txt"

    if [[ ! -f "$usb_ids_file" ]]; then
        log_warn "ST-LINK USB ID configuration not found."
        return 0
    fi

    if ! command_exists lsusb; then
        log_warn "lsusb is unavailable."
        return 0
    fi

    local attempt
    local max_attempts=10
    local id
    local found=0

    for ((attempt=1; attempt<=max_attempts; attempt++)); do

        found=0

        while IFS= read -r id || [[ -n "$id" ]]; do
            id="${id%%#*}"
            id="$(printf '%s' "$id" | xargs)"

            [[ -z "$id" ]] && continue

            local line
            line="$(lsusb -d "$id" 2>/dev/null | head -n1 || true)"

            [[ -z "$line" ]] && continue

            found=1

            local device
            device="$(
                awk '{
                    gsub(":","",$4)
                    print "/dev/bus/usb/"$2"/"$4
                }' <<< "$line"
            )"

            log_ok "ST-LINK $id detected"
            printf '  Device:      %s\n' "$device"

            if [[ -e "$device" ]]; then
                printf '  Permissions: %s\n' \
                    "$(stat -c '%A %U %G' "$device")"

                if [[ -r "$device" && -w "$device" ]]; then
                    log_ok "Current user has read/write access."
                else
                    log_warn "Current user lacks read/write access."
                fi
            fi

        done < "$usb_ids_file"

        [[ "$found" -eq 1 ]] && return 0

        if [[ "$attempt" -lt "$max_attempts" ]]; then
            sleep 1
        fi
    done

    log_warn "No configured ST-LINK programmer is visible inside Linux."
}

main() {
    install_stm32_extension
    find_cube_cli
    prepare_directories

    install_bundles
    install_usb_dependencies
    install_udev_rules

    if is_wsl; then
        "$ROOT_DIR/scripts/setup-stlink-usb.sh"
    fi    
    
    verify_stlink
    verify_stm32
}

main "$@"
