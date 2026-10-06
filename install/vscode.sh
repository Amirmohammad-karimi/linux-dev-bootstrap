#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

source "$ROOT_DIR/scripts/helpers.sh"

EXTENSION_FILE="$ROOT_DIR/packages/vscode-extensions.txt"

INSTALLED_EXTENSIONS=""

check_vscode() {
    if ! command_exists code; then
        die "Managed VS Code wrapper is missing from PATH: $HOME/.local/bin/code"
    fi

    local version

    if ! version="$(code --version 2>/dev/null | head -n1)"; then
        die "Windows VS Code is not installed or cannot be reached from WSL."
    fi

    [[ -n "$version" ]] ||
        die "Windows VS Code did not report a version."

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
    check_vscode
    install_extensions
    verify_vscode
}

main "$@"
