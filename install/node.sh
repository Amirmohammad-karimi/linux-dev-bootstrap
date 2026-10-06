#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT_DIR/scripts/helpers.sh"
source "$ROOT_DIR/config/versions.env"
LOCAL_CONFIG="$ROOT_DIR/config/local.env"
load_local_env "$LOCAL_CONFIG"
NVM_DIR="${NVM_DIR:-$HOME/.nvm}"
export NVM_DIR

load_nvm() {
    if [[ -s "$NVM_DIR/nvm.sh" ]]; then
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
    download_file "https://raw.githubusercontent.com/nvm-sh/nvm/v${NVM_VERSION}/install.sh" "$installer"
    PROFILE=/dev/null NVM_DIR="$NVM_DIR" bash "$installer"
    rm -f "$installer"
    load_nvm || die "Unable to load nvm after installation."
    log_ok "nvm $NVM_VERSION installed."
}

install_node() {
    load_nvm || die "Node.js requires nvm. Set ENABLE_NVM=yes or install nvm manually."
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

verify_node() {
    log_info "Node.js toolchain:"
    if feature_enabled ENABLE_NVM yes; then
        load_nvm && printf '  nvm:  %s\n' "$(nvm --version)" || log_warn "nvm enabled but unavailable."
    else printf '  nvm:  disabled\n'; fi

    if feature_enabled ENABLE_NODEJS yes; then
        load_nvm && nvm use "$NODE_VERSION" >/dev/null 2>&1 || true
        command_exists node && printf '  Node: %s\n' "$(node --version)" || log_warn "Node.js enabled but unavailable."
        command_exists npm && printf '  npm:  %s\n' "$(npm --version)" || log_warn "npm unavailable."
        command_exists npx && printf '  npx:  %s\n' "$(npx --version)" || log_warn "npx unavailable."
    else
        printf '  Node: disabled\n'
        printf '  npm:  disabled with Node.js\n'
        printf '  npx:  disabled with Node.js\n'
    fi
}

main() {
    if ! feature_enabled ENABLE_NODE_TOOLCHAIN yes; then
        log_feature_disabled "Node.js toolchain" "ENABLE_NODE_TOOLCHAIN"
        return 0
    fi
    if feature_enabled ENABLE_NVM yes; then install_nvm; else log_feature_disabled "nvm" "ENABLE_NVM"; fi
    if feature_enabled ENABLE_NODEJS yes; then install_node; else log_feature_disabled "Node.js" "ENABLE_NODEJS"; fi
    log_ok "Node.js shell configuration is managed by linux-bootstrap dotfiles."
    verify_node
}
main "$@"
