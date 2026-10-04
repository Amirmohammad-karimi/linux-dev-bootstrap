#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(
    cd "$(dirname "${BASH_SOURCE[0]}")" >/dev/null 2>&1
    pwd
)"

REPO_ROOT="$(
    cd "$SCRIPT_DIR/.." >/dev/null 2>&1
    pwd
)"

# shellcheck source=../scripts/helpers.sh
source "$REPO_ROOT/scripts/helpers.sh"

LOCAL_ENV="$REPO_ROOT/config/local.env"

# ---------------------------------------------------------------------------
# Defaults
# ---------------------------------------------------------------------------

ENABLE_GOOGLE_CHROME="${ENABLE_GOOGLE_CHROME:-no}"

# ---------------------------------------------------------------------------
# Load machine-local configuration
# ---------------------------------------------------------------------------

if [[ -f "$LOCAL_ENV" ]]; then
    # shellcheck disable=SC1090
    source "$LOCAL_ENV"
fi


# ---------------------------------------------------------------------------
# Google Chrome
# ---------------------------------------------------------------------------

GOOGLE_CHROME_KEYRING="/etc/apt/keyrings/google-chrome.gpg"
GOOGLE_CHROME_SOURCE="/etc/apt/sources.list.d/google-chrome.list"

google_chrome_installed() {
    command -v google-chrome-stable >/dev/null 2>&1 ||
    command -v google-chrome >/dev/null 2>&1
}

installed_google_chrome_version() {
    if command -v google-chrome-stable >/dev/null 2>&1; then
        google-chrome-stable --version
    elif command -v google-chrome >/dev/null 2>&1; then
        google-chrome --version
    fi
}

install_google_chrome() {
    if google_chrome_installed; then
        log_ok "Google Chrome already installed ($(installed_google_chrome_version))"
        return 0
    fi

    log_info "Installing Google Chrome..."

    apt_install \
        ca-certificates \
        curl \
        gnupg

    sudo install \
        -m 0755 \
        -d /etc/apt/keyrings

    local temp_key
    temp_key="$(mktemp)"

    curl -fsSL \
        https://dl.google.com/linux/linux_signing_key.pub \
        -o "$temp_key"

    gpg \
        --dearmor \
        --yes \
        --output "$temp_key.gpg" \
        "$temp_key"

    sudo install \
        -m 0644 \
        "$temp_key.gpg" \
        "$GOOGLE_CHROME_KEYRING"

    rm -f \
        "$temp_key" \
        "$temp_key.gpg"

    echo \
        "deb [arch=amd64 signed-by=$GOOGLE_CHROME_KEYRING] https://dl.google.com/linux/chrome/deb/ stable main" |
        sudo tee "$GOOGLE_CHROME_SOURCE" >/dev/null

    apt_update

    apt_install google-chrome-stable

    if ! google_chrome_installed; then
        die "Google Chrome installation verification failed."
    fi

    log_ok "Google Chrome installed ($(installed_google_chrome_version))"
}


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

main() {

    case "${ENABLE_GOOGLE_CHROME,,}" in
        yes|true|1)
            ENABLE_GOOGLE_CHROME="yes"
            install_google_chrome
            ;;

        no|false|0|"")
            ENABLE_GOOGLE_CHROME="no"
            log_info "Google Chrome disabled by config/local.env"
            ;;

        *)
            die "Invalid ENABLE_GOOGLE_CHROME value: $ENABLE_GOOGLE_CHROME. Use yes or no."
            ;;
    esac

    echo
    log_info "General applications:"

    if [[ "$ENABLE_GOOGLE_CHROME" == "yes" ]]; then
        if google_chrome_installed; then
            echo "  Google Chrome: $(installed_google_chrome_version)"
        else
            echo "  Google Chrome: not installed"
        fi
    else
        echo "  Google Chrome: disabled by config/local.env"
    fi
}

main "$@"
