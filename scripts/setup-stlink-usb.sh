#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

source "$ROOT_DIR/scripts/helpers.sh"

if ! is_wsl; then
    log_info "Native Linux detected; usbipd-win is not required."
    exit 0
fi

POWERSHELL="/mnt/c/Windows/System32/WindowsPowerShell/v1.0/powershell.exe"

if [[ ! -x "$POWERSHELL" ]]; then
    log_warn "Windows PowerShell is not accessible from WSL."
    exit 0
fi

PS_SCRIPT="$ROOT_DIR/scripts/windows/setup-usbipd-stlink.ps1"
USB_IDS_FILE="$ROOT_DIR/config/stlink-usb-ids.txt"

[[ -f "$PS_SCRIPT" ]] ||
    die "usbipd PowerShell script not found."

[[ -f "$USB_IDS_FILE" ]] ||
    die "ST-LINK USB ID configuration not found."

WINDOWS_SCRIPT="$(wslpath -w "$PS_SCRIPT")"
WINDOWS_USB_IDS="$(wslpath -w "$USB_IDS_FILE")"

log_info "Checking Windows ST-LINK/usbipd configuration..."

"$POWERSHELL" \
    -NoProfile \
    -ExecutionPolicy Bypass \
    -File "$WINDOWS_SCRIPT" \
    -UsbIdsFile "$WINDOWS_USB_IDS"

log_ok "Windows ST-LINK USB configuration checked."
