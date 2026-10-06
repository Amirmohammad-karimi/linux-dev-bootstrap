#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT_DIR/scripts/helpers.sh"
LOCAL_CONFIG="$ROOT_DIR/config/local.env"
load_local_env "$LOCAL_CONFIG"
STM32_EXTENSION="stmicroelectronics.stm32-vscode-extension"
BUNDLE_FILE="$ROOT_DIR/packages/stm32-bundles.txt"
export CUBE_BUNDLE_PATH="${CUBE_BUNDLE_PATH:-$HOME/.local/share/stm32cube/bundles}"
export CMSIS_PACK_ROOT="${CMSIS_PACK_ROOT:-$HOME/.local/share/stm32cube/packs}"
CUBE_BIN=""

install_stm32_extension() {
    if ! feature_enabled ENABLE_STM32_VSCODE_EXTENSION yes; then log_feature_disabled "STM32Cube VS Code extension pack" "ENABLE_STM32_VSCODE_EXTENSION"; return 0; fi
    require_command code
    local extensions
    extensions="$(code --list-extensions 2>/dev/null || true)"
    if grep -Fxi "$STM32_EXTENSION" <<< "$extensions" >/dev/null; then log_ok "STM32Cube VS Code extension pack already installed"; return 0; fi
    log_info "Installing STM32Cube VS Code extension pack..."
    code --install-extension "$STM32_EXTENSION"
    log_ok "STM32Cube VS Code extension pack installed."
}

find_cube_cli() {
    if command_exists cube; then CUBE_BIN="$(command -v cube)"; log_ok "cube CLI found: $CUBE_BIN"; return 0; fi
    CUBE_BIN="$(find "$HOME/.vscode-server/extensions" -path '*/stmicroelectronics.stm32cube-ide-core-*/*' -type f -name cube -perm -111 -print -quit 2>/dev/null)"
    [[ -n "$CUBE_BIN" ]] || die "cube CLI was not found. Enable ENABLE_STM32_VSCODE_EXTENSION or install the STM32Cube VS Code extension manually."
    log_ok "cube CLI found: $CUBE_BIN"
}
prepare_directories() { ensure_directory "$CUBE_BUNDLE_PATH"; ensure_directory "$CMSIS_PACK_ROOT"; log_ok "STM32Cube directories ready"; }
bundle_installed() { local specification="$1"; local name="${specification%@*}"; local version="${specification#*@}"; [[ -d "$CUBE_BUNDLE_PATH/$name/$version" ]]; }

install_bundles() {
    [[ -f "$BUNDLE_FILE" ]] || die "STM32 bundle manifest not found: $BUNDLE_FILE"
    local enabled_bundles=()
    local feature bundle
    while IFS='|' read -r feature bundle || [[ -n "${feature:-}${bundle:-}" ]]; do
        feature="${feature#"${feature%%[![:space:]]*}"}"; feature="${feature%"${feature##*[![:space:]]}"}"
        bundle="${bundle#"${bundle%%[![:space:]]*}"}"; bundle="${bundle%"${bundle##*[![:space:]]}"}"
        [[ -z "$feature" || "$feature" == \#* ]] && continue
        [[ -n "$bundle" ]] || die "Invalid STM32 bundle manifest entry for $feature"
        if feature_enabled "$feature" yes; then enabled_bundles+=("$bundle"); else log_feature_disabled "$bundle" "$feature"; fi
    done < "$BUNDLE_FILE"
    [[ "${#enabled_bundles[@]}" -eq 0 ]] && { log_info "No STM32 bundles selected."; return 0; }
    log_info "Checking STM32Cube bundles..."
    local install_help
    local yes_args=()
    install_help="$("$CUBE_BIN" bundle install --help 2>&1 || true)"
    grep -F -- '--yes' <<< "$install_help" >/dev/null && yes_args=(--yes)
    for bundle in "${enabled_bundles[@]}"; do
        if bundle_installed "$bundle"; then log_ok "$bundle already installed"; continue; fi
        log_info "Installing STM32 bundle: $bundle"
        "$CUBE_BIN" bundle install "$bundle" "${yes_args[@]}"
        bundle_installed "$bundle" || die "Bundle installation did not produce expected directory: $bundle"
        log_ok "Installed: $bundle"
    done
}

install_usb_dependencies() {
    local packages=()
    feature_enabled ENABLE_LIBUSB yes && packages+=(libusb-1.0-0)
    feature_enabled ENABLE_LIBUSB_DEV yes && packages+=(libusb-1.0-0-dev)
    feature_enabled ENABLE_UDEV yes && packages+=(udev)
    feature_enabled ENABLE_USBUTILS yes && packages+=(usbutils)
    [[ "${#packages[@]}" -eq 0 ]] && { log_info "No STM32 USB dependency packages selected."; return 0; }
    log_info "Installing STM32 USB dependencies..."
    apt_install "${packages[@]}"
    log_ok "Selected STM32 USB dependencies installed."
}

stlink_udev_bundle_spec() {
    awk -F'|' '$1 == "ENABLE_STLINK_UDEV_RULES" { gsub(/^[[:space:]]+|[[:space:]]+$/, "", $2); print $2; exit }' "$BUNDLE_FILE"
}

install_udev_rules() {
    if ! feature_enabled ENABLE_STLINK_UDEV_RULES yes; then log_feature_disabled "ST-LINK udev rules" "ENABLE_STLINK_UDEV_RULES"; return 0; fi
    ensure_apt_dependency ENABLE_UDEV udev "ST-LINK udev rules" yes
    local spec version bundle_dir deb package_name
    spec="$(stlink_udev_bundle_spec)"
    [[ -n "$spec" ]] || die "ST-LINK udev-rules bundle is not configured."
    version="${spec#*@}"
    bundle_dir="$CUBE_BUNDLE_PATH/stlink-udev-rules/$version"
    deb="$(find "$bundle_dir/bin" -maxdepth 1 -type f -name 'st-stlink-udev-rules-*-linux-all.deb' -print -quit 2>/dev/null)"
    [[ -n "$deb" && -f "$deb" ]] || die "ST-LINK udev-rules .deb package not found."
    package_name="$(dpkg-deb -f "$deb" Package)"
    if package_installed "$package_name"; then log_ok "ST-LINK udev rules already installed ($package_name)"
    else
        log_info "Installing ST-LINK udev rules..."
        ensure_sudo
        local temp_deb
        temp_deb="/tmp/$(basename "$deb")"
        cp "$deb" "$temp_deb"; chmod 0644 "$temp_deb"; sudo apt-get install -y "$temp_deb"; rm -f "$temp_deb"
        log_ok "ST-LINK udev rules installed."
    fi
    if command_exists udevadm; then sudo udevadm control --reload-rules; sudo udevadm trigger; fi
}

verify_stm32() {
    log_info "STM32 environment:"
    printf '  Bundle path: %s\n' "$CUBE_BUNDLE_PATH"
    printf '  CMSIS packs: %s\n' "$CMSIS_PACK_ROOT"
    printf '  cube CLI:    %s\n' "$CUBE_BIN"
    if feature_enabled ENABLE_STM32_GCC yes; then
        local gcc_spec gcc_version gcc
        gcc_spec="$(awk -F'|' '$1 == "ENABLE_STM32_GCC" { gsub(/^[[:space:]]+|[[:space:]]+$/, "", $2); print $2; exit }' "$BUNDLE_FILE")"
        gcc_version="${gcc_spec#*@}"
        gcc="$CUBE_BUNDLE_PATH/gnu-tools-for-stm32/$gcc_version/bin/arm-none-eabi-gcc"
        [[ -x "$gcc" ]] && printf '  GCC:         %s\n' "$("$gcc" --version | head -n1)" || log_warn "arm-none-eabi-gcc enabled but executable was not found."
    else printf '  GCC:         disabled\n'; fi
    local enabled_count=0
    local feature bundle
    while IFS='|' read -r feature bundle || [[ -n "${feature:-}${bundle:-}" ]]; do
        feature="${feature#"${feature%%[![:space:]]*}"}"
        [[ -z "$feature" || "$feature" == \#* ]] && continue
        feature_enabled "$feature" yes && enabled_count=$((enabled_count + 1))
    done < "$BUNDLE_FILE"
    printf '  Bundles:     %s enabled\n' "$enabled_count"
}

verify_stlink() {
    local usb_ids_file="$ROOT_DIR/config/stlink-usb-ids.txt"
    [[ -f "$usb_ids_file" ]] || { log_warn "ST-LINK USB ID configuration not found."; return 0; }
    command_exists lsusb || { log_info "lsusb unavailable; skipping ST-LINK visibility check."; return 0; }
    local attempt max_attempts=10 id found=0
    for ((attempt=1; attempt<=max_attempts; attempt++)); do
        found=0
        while IFS= read -r id || [[ -n "$id" ]]; do
            id="${id%%#*}"; id="$(printf '%s' "$id" | xargs)"; [[ -z "$id" ]] && continue
            local line
            line="$(lsusb -d "$id" 2>/dev/null | head -n1 || true)"; [[ -z "$line" ]] && continue
            found=1
            local device
            device="$(awk '{gsub(":","",$4); print "/dev/bus/usb/"$2"/"$4}' <<< "$line")"
            log_ok "ST-LINK $id detected"; printf '  Device:      %s\n' "$device"
            if [[ -e "$device" ]]; then
                printf '  Permissions: %s\n' "$(stat -c '%A %U %G' "$device")"
                [[ -r "$device" && -w "$device" ]] && log_ok "Current user has read/write access." || log_warn "Current user lacks read/write access."
            fi
        done < "$usb_ids_file"
        [[ "$found" -eq 1 ]] && return 0
        [[ "$attempt" -lt "$max_attempts" ]] && sleep 1
    done
    log_warn "No configured ST-LINK programmer is visible inside Linux."
}

main() {
    if ! feature_enabled ENABLE_STM32 yes; then log_feature_disabled "STM32 development environment" "ENABLE_STM32"; return 0; fi
    install_stm32_extension
    find_cube_cli
    prepare_directories
    install_bundles
    install_usb_dependencies
    install_udev_rules
    if is_wsl && feature_enabled ENABLE_STLINK_USBIPD yes; then "$ROOT_DIR/scripts/setup-stlink-usb.sh"
    elif is_wsl; then log_feature_disabled "ST-LINK usbipd forwarding" "ENABLE_STLINK_USBIPD"; fi
    verify_stlink
    verify_stm32
}
main "$@"
