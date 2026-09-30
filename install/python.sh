#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

source "$ROOT_DIR/scripts/helpers.sh"
source "$ROOT_DIR/config/versions.env"

install_python_packages() {
    log_info "Installing Python system packages..."

    apt_install \
        python3 \
        python3-pip \
        python3-venv \
        python3-dev \
        pipx

    log_ok "Python system packages are installed."
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

    curl -LsSf \
        "https://astral.sh/uv/${UV_VERSION}/install.sh" |
        env \
            UV_INSTALL_DIR="$HOME/.local/bin" \
            UV_NO_MODIFY_PATH=1 \
            sh

    log_ok "uv $UV_VERSION installed."
}

verify_python() {
    export PATH="$HOME/.local/bin:$PATH"

    log_info "Python toolchain:"

    printf '  Python: %s\n' "$(python3 --version)"
    printf '  pip:    %s\n' "$(python3 -m pip --version | awk '{print $2}')"
    printf '  pipx:   %s\n' "$(pipx --version)"
    printf '  uv:     %s\n' "$(uv --version)"
}

main() {
    install_python_packages
    install_uv
    verify_python
}

main "$@"
