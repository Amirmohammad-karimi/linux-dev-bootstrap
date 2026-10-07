#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

source "$ROOT_DIR/scripts/helpers.sh"

PROXY_CONFIG="$ROOT_DIR/config/proxy.env"
APT_PROXY_FILE="/etc/apt/apt.conf.d/95linux-bootstrap-proxy"

PROXY_ENABLED="no"
HTTP_PROXY_URL=""
HTTPS_PROXY_URL=""

if [[ -f "$PROXY_CONFIG" ]]; then
    # shellcheck source=/dev/null
    source "$PROXY_CONFIG"
fi

remove_apt_proxy() {
    [[ -f "$APT_PROXY_FILE" ]] || return 0

    ensure_sudo
    sudo rm -f "$APT_PROXY_FILE"

    log_ok "Removed bootstrap-managed APT proxy configuration."
}

configure_apt_proxy() {
    if ! feature_enabled PROXY_ENABLED no; then
        remove_apt_proxy
        log_info "Proxy disabled."
        return 0
    fi

    [[ -n "$HTTP_PROXY_URL" ]] ||
        die "PROXY_ENABLED=yes requires HTTP_PROXY_URL in config/proxy.env"

    [[ -n "$HTTPS_PROXY_URL" ]] ||
        HTTPS_PROXY_URL="$HTTP_PROXY_URL"

    local desired
    desired="$(cat <<EOF
Acquire::http::Proxy "$HTTP_PROXY_URL";
Acquire::https::Proxy "$HTTPS_PROXY_URL";
EOF
)"

    if [[ -f "$APT_PROXY_FILE" ]] &&
       [[ "$(cat "$APT_PROXY_FILE" 2>/dev/null || true)" == "$desired" ]]; then
        log_ok "APT proxy already configured."
        return 0
    fi

    ensure_sudo

    printf '%s\n' "$desired" |
        sudo tee "$APT_PROXY_FILE" >/dev/null

    log_ok "APT proxy configured."
}

configure_apt_proxy
