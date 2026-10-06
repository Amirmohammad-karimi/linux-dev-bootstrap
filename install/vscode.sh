#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT_DIR/scripts/helpers.sh"
LOCAL_CONFIG="$ROOT_DIR/config/local.env"
EXTENSION_FILE="$ROOT_DIR/packages/vscode-extensions.txt"
load_local_env "$LOCAL_CONFIG"
INSTALLED_EXTENSIONS=""

check_vscode() {
    command_exists code || die "Managed VS Code wrapper is missing from PATH: $HOME/.local/bin/code"
    local version
    version="$(code --version 2>/dev/null | head -n1)" || die "Windows VS Code is not installed or cannot be reached from WSL."
    [[ -n "$version" ]] || die "Windows VS Code did not report a version."
    log_ok "VS Code detected: $version"
}
refresh_extension_cache() { INSTALLED_EXTENSIONS="$(code --list-extensions 2>/dev/null || true)"; }
extension_installed() { local extension="$1"; grep -Fxi "$extension" <<< "$INSTALLED_EXTENSIONS" >/dev/null; }

install_extensions() {
    if ! feature_enabled ENABLE_VSCODE_EXTENSIONS yes; then log_feature_disabled "VS Code extensions" "ENABLE_VSCODE_EXTENSIONS"; return 0; fi
    [[ -f "$EXTENSION_FILE" ]] || die "Extension list not found: $EXTENSION_FILE"
    log_info "Checking VS Code extensions..."
    refresh_extension_cache
    local feature extension
    while IFS='|' read -r feature extension || [[ -n "${feature:-}${extension:-}" ]]; do
        feature="${feature#"${feature%%[![:space:]]*}"}"; feature="${feature%"${feature##*[![:space:]]}"}"
        extension="${extension#"${extension%%[![:space:]]*}"}"; extension="${extension%"${extension##*[![:space:]]}"}"
        [[ -z "$feature" || "$feature" == \#* ]] && continue
        [[ -n "$extension" ]] || die "Invalid VS Code extension manifest entry for $feature"
        if ! feature_enabled "$feature" yes; then log_feature_disabled "$extension" "$feature"; continue; fi
        if extension_installed "$extension"; then log_ok "$extension already installed"
        else
            log_info "Installing: $extension"
            code --install-extension "$extension"
            log_ok "Installed: $extension"
            INSTALLED_EXTENSIONS+=$'\n'"$extension"
        fi
    done < "$EXTENSION_FILE"
}

verify_vscode() {
    refresh_extension_cache
    log_info "VS Code environment:"
    printf '  VS Code: %s\n' "$(code --version | head -n1)"
    printf '  WSL extensions: %s\n' "$(grep -cve '^[[:space:]]*$' <<< "$INSTALLED_EXTENSIONS")"
}
main() {
    if ! feature_enabled ENABLE_VSCODE yes; then log_feature_disabled "VS Code configuration" "ENABLE_VSCODE"; return 0; fi
    check_vscode
    install_extensions
    verify_vscode
}
main "$@"
