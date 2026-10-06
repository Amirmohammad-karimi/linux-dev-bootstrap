#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT_DIR/scripts/helpers.sh"
source "$ROOT_DIR/config/versions.env"
LOCAL_CONFIG="$ROOT_DIR/config/local.env"
load_local_env "$LOCAL_CONFIG"

install_python_packages() {
    local packages=()
    feature_enabled ENABLE_PYTHON3 yes && packages+=(python3)
    feature_enabled ENABLE_PYTHON_PIP yes && packages+=(python3-pip)
    feature_enabled ENABLE_PYTHON_VENV yes && packages+=(python3-venv)
    feature_enabled ENABLE_PYTHON_DEV yes && packages+=(python3-dev)
    feature_enabled ENABLE_PIPX yes && packages+=(pipx)
    [[ "${#packages[@]}" -eq 0 ]] && { log_info "No Python system packages selected."; return 0; }
    log_info "Installing Python system packages..."
    apt_install "${packages[@]}"
    log_ok "Selected Python system packages are installed."
}

install_uv() {
    export PATH="$HOME/.local/bin:$PATH"
    if command_exists uv; then
        local installed_version
        installed_version="$(uv --version | awk '{print $2}')"
        if [[ "$installed_version" == "$UV_VERSION" ]]; then
            log_ok "uv $UV_VERSION already installed"
            return 0
        fi
        log_info "uv version $installed_version installed; target is $UV_VERSION"
    fi

    log_info "Installing uv $UV_VERSION..."
    ensure_directory "$HOME/.local/bin"
    local installer
    installer="$(mktemp)"
    download_file "https://astral.sh/uv/${UV_VERSION}/install.sh" "$installer"
    env UV_INSTALL_DIR="$HOME/.local/bin" UV_NO_MODIFY_PATH=1 sh "$installer"
    rm -f "$installer"
    log_ok "uv $UV_VERSION installed."
}

verify_python() {
    export PATH="$HOME/.local/bin:$PATH"
    log_info "Python toolchain:"

    if feature_enabled ENABLE_PYTHON3 yes; then
        command_exists python3 && printf '  Python: %s\n' "$(python3 --version)" || log_warn "Python enabled but python3 is unavailable."
    else printf '  Python: disabled\n'; fi

    if feature_enabled ENABLE_PYTHON_PIP yes; then
        if command_exists python3 && python3 -m pip --version >/dev/null 2>&1; then
            printf '  pip:    %s\n' "$(python3 -m pip --version | awk '{print $2}')"
        else log_warn "pip enabled but unavailable."; fi
    else printf '  pip:    disabled\n'; fi

    if feature_enabled ENABLE_PIPX yes; then
        command_exists pipx && printf '  pipx:   %s\n' "$(pipx --version)" || log_warn "pipx enabled but unavailable."
    else printf '  pipx:   disabled\n'; fi

    if feature_enabled ENABLE_UV yes; then
        command_exists uv && printf '  uv:     %s\n' "$(uv --version)" || log_warn "uv enabled but unavailable."
    else printf '  uv:     disabled\n'; fi
}

main() {
    if ! feature_enabled ENABLE_PYTHON_TOOLCHAIN yes; then
        log_feature_disabled "Python toolchain" "ENABLE_PYTHON_TOOLCHAIN"
        return 0
    fi
    install_python_packages
    if feature_enabled ENABLE_UV yes; then install_uv; else log_feature_disabled "uv" "ENABLE_UV"; fi
    verify_python
}
main "$@"
