#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

source "$ROOT_DIR/scripts/helpers.sh"
source "$ROOT_DIR/config/versions.env"

NVM_DIR="${NVM_DIR:-$HOME/.nvm}"
export NVM_DIR

load_nvm() {
    if [[ -s "$NVM_DIR/nvm.sh" ]]; then
        # shellcheck disable=SC1090
        source "$NVM_DIR/nvm.sh"
        return 0
    fi

    return 1
}

install_nvm() {
    if load_nvm; then
        local installed_version
        installed_version="$(nvm --version)"

        if [[ "$installed_version" == "$NVM_VERSION" ]]; then
            log_ok "nvm $NVM_VERSION already installed"
            return 0
        fi

        log_info "nvm $installed_version installed; target is $NVM_VERSION"
    fi

    log_info "Installing nvm $NVM_VERSION..."

    local installer
    installer="$(mktemp)"

    download_file \
        "https://raw.githubusercontent.com/nvm-sh/nvm/v${NVM_VERSION}/install.sh" \
        "$installer"

    PROFILE=/dev/null \
    NVM_DIR="$NVM_DIR" \
    bash "$installer"

    rm -f "$installer"

    load_nvm || die "Unable to load nvm after installation."

    log_ok "nvm $NVM_VERSION installed."
}

install_node() {
    load_nvm || die "nvm is not available."

    local installed_version
    installed_version="$(nvm version "$NODE_VERSION" 2>/dev/null || true)"

    if [[ "$installed_version" == "v$NODE_VERSION" ]]; then
        log_ok "Node.js $NODE_VERSION already installed"
    else
        log_info "Installing Node.js $NODE_VERSION..."
        nvm install "$NODE_VERSION"
        log_ok "Node.js $NODE_VERSION installed."
    fi

    nvm alias default "$NODE_VERSION" >/dev/null
    nvm use "$NODE_VERSION" >/dev/null

    log_ok "Default Node.js version set to $NODE_VERSION"
}

configure_shell() {
    log_ok "Node.js shell configuration is managed by linux-bootstrap dotfiles."
}

verify_node() {
    load_nvm
    nvm use "$NODE_VERSION" >/dev/null

    log_info "Node.js toolchain:"

    printf '  nvm:  %s\n' "$(nvm --version)"
    printf '  Node: %s\n' "$(node --version)"
    printf '  npm:  %s\n' "$(npm --version)"
    printf '  npx:  %s\n' "$(npx --version)"
}

main() {
    install_nvm
    install_node
    configure_shell
    verify_node
}

main "$@"
