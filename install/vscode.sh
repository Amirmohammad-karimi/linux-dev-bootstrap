#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

source "$ROOT_DIR/scripts/helpers.sh"

EXTENSION_FILE="$ROOT_DIR/packages/vscode-extensions.txt"

INSTALLED_EXTENSIONS=""

check_vscode() {
    if ! command_exists code; then
        log_warn "VS Code CLI is not available."
        log_warn "Windows VS Code must be accessible from WSL."
        return 1
    fi

    local version
    version="$(code --version | head -n1)"

    log_ok "VS Code detected: $version"
}

refresh_extension_cache() {
    INSTALLED_EXTENSIONS="$(code --list-extensions 2>/dev/null || true)"
}

extension_installed() {
    local extension="$1"

    grep -Fxi "$extension" <<< "$INSTALLED_EXTENSIONS" >/dev/null
}

install_extensions() {
    [[ -f "$EXTENSION_FILE" ]] ||
        die "Extension list not found: $EXTENSION_FILE"

    log_info "Checking VS Code extensions..."

    refresh_extension_cache

    local extension

    while IFS= read -r extension || [[ -n "$extension" ]]; do

        extension="${extension#"${extension%%[![:space:]]*}"}"
        extension="${extension%"${extension##*[![:space:]]}"}"

        [[ -z "$extension" ]] && continue
        [[ "$extension" == \#* ]] && continue

        if extension_installed "$extension"; then
            log_ok "$extension already installed"
        else
            log_info "Installing: $extension"

            code --install-extension "$extension"

            log_ok "Installed: $extension"

            # Update cache after installation.
            INSTALLED_EXTENSIONS+=$'\n'"$extension"
        fi

    done < "$EXTENSION_FILE"
}

verify_vscode() {
    refresh_extension_cache

    log_info "VS Code environment:"

    printf '  VS Code: %s\n' "$(code --version | head -n1)"
    printf '  WSL extensions: %s\n' \
        "$(grep -cve '^[[:space:]]*$' <<< "$INSTALLED_EXTENSIONS")"
}

main() {
    if ! check_vscode; then
        return 0
    fi

    install_extensions
    verify_vscode
}

main "$@"
