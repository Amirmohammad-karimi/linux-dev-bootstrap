#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

source "$ROOT_DIR/scripts/helpers.sh"

PACKAGE_FILE="$ROOT_DIR/packages/apt.txt"

install_base_packages() {
    log_info "Installing base system packages..."

    if [[ ! -f "$PACKAGE_FILE" ]]; then
        die "Package list not found: $PACKAGE_FILE"
    fi

    local packages=()
    local package

    while IFS= read -r package || [[ -n "$package" ]]; do

        # Remove leading/trailing whitespace
        package="${package#"${package%%[![:space:]]*}"}"
        package="${package%"${package##*[![:space:]]}"}"

        # Skip empty lines
        [[ -z "$package" ]] && continue

        # Skip comments
        [[ "$package" == \#* ]] && continue

        packages+=("$package")

    done < "$PACKAGE_FILE"

    if [[ "${#packages[@]}" -eq 0 ]]; then
        log_warn "No packages found in $PACKAGE_FILE"
        return 0
    fi

    apt_install "${packages[@]}"

    log_ok "Base system packages are installed."
}

install_base_packages
