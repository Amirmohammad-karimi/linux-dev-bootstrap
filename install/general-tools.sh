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
ENABLE_SLACK_CLI="${ENABLE_SLACK_CLI:-no}"

# ---------------------------------------------------------------------------
# Load machine-local configuration
# ---------------------------------------------------------------------------

load_local_env "$LOCAL_ENV"


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

    ensure_apt_dependency ENABLE_CA_CERTIFICATES ca-certificates "Google Chrome" yes
    ensure_apt_dependency ENABLE_CURL curl "Google Chrome" yes
    ensure_apt_dependency ENABLE_GNUPG gnupg "Google Chrome" yes
    require_command curl
    require_command gpg

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
# Slack CLI
# ---------------------------------------------------------------------------

SLACK_CLI_INSTALLER_URL="https://downloads.slack-edge.com/slack-cli/install.sh"

slack_cli_installed() {
    command -v slack >/dev/null 2>&1 &&
        slack --version --skip-update >/dev/null 2>&1
}

installed_slack_cli_version() {
    slack --version --skip-update 2>/dev/null |
        head -n1
}

install_slack_cli() {
    if slack_cli_installed; then
        log_ok "Slack CLI already installed ($(installed_slack_cli_version))"
        return 0
    fi

    if command -v slack >/dev/null 2>&1; then
        die "A command named 'slack' already exists but does not appear to be the Slack developer CLI. The official installer will not overwrite it."
    fi

    log_info "Installing Slack CLI..."

    ensure_apt_dependency ENABLE_CA_CERTIFICATES ca-certificates "Slack CLI" yes
    ensure_apt_dependency ENABLE_CURL curl "Slack CLI" yes
    ensure_apt_dependency ENABLE_GIT git "Slack CLI" yes

    require_command curl
    require_command git

    local installer
    installer="$(mktemp)"

    curl         --proto '=https'         --tlsv1.2         --fail         --silent         --show-error         --location         --retry 3         "$SLACK_CLI_INSTALLER_URL"         -o "$installer"

    bash "$installer"
    rm -f "$installer"

    hash -r

    # The official installer normally configures the command. If the binary
    # was downloaded but the command is not in PATH yet, create the documented
    # user-local symlink. ~/.local/bin is managed by this bootstrap.
    if ! command -v slack >/dev/null 2>&1 &&
       [[ -x "$HOME/.slack/bin/slack" ]]; then
        create_symlink             "$HOME/.slack/bin/slack"             "$HOME/.local/bin/slack"
        hash -r
    fi

    if ! slack_cli_installed; then
        die "Slack CLI installation verification failed."
    fi

    log_ok "Slack CLI installed ($(installed_slack_cli_version))"
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

main() {
    if ! feature_enabled ENABLE_GENERAL_TOOLS yes; then
        log_feature_disabled "General applications" "ENABLE_GENERAL_TOOLS"
        return 0
    fi

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

    case "${ENABLE_SLACK_CLI,,}" in
        yes|true|1)
            ENABLE_SLACK_CLI="yes"
            install_slack_cli
            ;;

        no|false|0|"")
            ENABLE_SLACK_CLI="no"
            log_info "Slack CLI disabled by config/local.env"
            ;;

        *)
            die "Invalid ENABLE_SLACK_CLI value: $ENABLE_SLACK_CLI. Use yes or no."
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

    if [[ "$ENABLE_SLACK_CLI" == "yes" ]]; then
        if slack_cli_installed; then
            echo "  Slack CLI:     $(installed_slack_cli_version)"
        else
            echo "  Slack CLI:     not installed"
        fi
    else
        echo "  Slack CLI:     disabled by config/local.env"
    fi
}

main "$@"
