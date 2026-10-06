#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT_DIR/scripts/helpers.sh"
LOCAL_CONFIG="$ROOT_DIR/config/local.env"
PACKAGE_FILE="$ROOT_DIR/packages/apt.txt"
load_local_env "$LOCAL_CONFIG"

install_base_packages() {
    if ! feature_enabled ENABLE_BASE_PACKAGES yes; then
        log_feature_disabled "Base system packages" "ENABLE_BASE_PACKAGES"
        return 0
    fi

    log_info "Installing base system packages..."
    [[ -f "$PACKAGE_FILE" ]] || die "Package list not found: $PACKAGE_FILE"

    local packages=()
    local feature package

    while IFS='|' read -r feature package || [[ -n "${feature:-}${package:-}" ]]; do
        feature="${feature#"${feature%%[![:space:]]*}"}"
        feature="${feature%"${feature##*[![:space:]]}"}"
        package="${package#"${package%%[![:space:]]*}"}"
        package="${package%"${package##*[![:space:]]}"}"
        [[ -z "$feature" || "$feature" == \#* ]] && continue
        [[ -n "$package" ]] || die "Invalid package manifest entry for $feature"

        if feature_enabled "$feature" yes; then
            packages+=("$package")
        else
            log_feature_disabled "$package" "$feature"
        fi
    done < "$PACKAGE_FILE"

    if [[ "${#packages[@]}" -eq 0 ]]; then
        log_info "No base packages selected."
        return 0
    fi

    apt_install "${packages[@]}"
    log_ok "Base system packages are installed."
}
install_base_packages
