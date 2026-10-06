#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

source "$ROOT_DIR/scripts/helpers.sh"

LOCAL_CONFIG="$ROOT_DIR/config/local.env"
load_local_env "$LOCAL_CONFIG"

PROFILE="${1:-full}"

main() {
    echo
    echo "========================================"
    echo " Linux Bootstrap"
    echo "========================================"
    echo

    if ! is_linux; then
        die "This bootstrap currently supports Linux only."
    fi

    if feature_enabled ENABLE_SUDO_KEEPALIVE yes; then
        start_sudo_session
        trap stop_sudo_session EXIT
    else
        log_feature_disabled "sudo keepalive" "ENABLE_SUDO_KEEPALIVE"
    fi

    print_system_info

    echo
    log_info "Selected profile: $PROFILE"

    case "$PROFILE" in
        minimal|development|embedded|ai|full)
            ;;
        *)
            die "Unknown profile: $PROFILE"
            ;;
    esac

    echo
    log_info "Running base installation..."

    "$ROOT_DIR/install/base.sh"

    echo
    if feature_enabled ENABLE_MANAGED_DOTFILES yes; then
        log_info "Installing managed dotfiles..."
        "$ROOT_DIR/scripts/setup-dotfiles.sh"
    else
        log_feature_disabled "Managed dotfiles" "ENABLE_MANAGED_DOTFILES"
    fi

    # Make user-local launchers available to this bootstrap process.
    export PATH="$HOME/.local/bin:$PATH"
    hash -r

    echo
    log_info "Running Python installation..."

    "$ROOT_DIR/install/python.sh"

    case "$PROFILE" in
	development|embedded|ai|full)
	    echo
	    log_info "Running Node.js installation..."
            "$ROOT_DIR/install/node.sh"

	    echo 
            log_info "Running Docker installation..."
	    "$ROOT_DIR/install/docker.sh"
            
	    echo 
	    log_info "Running general applications setup..."
	    "$ROOT_DIR/install/general-tools.sh"
	    ;;
    esac

    case "$PROFILE" in 
        development|embedded|full)
            echo
            log_info "Running VS Code configuration..."
            "$ROOT_DIR/install/vscode.sh"
            ;;
    esac

    case "$PROFILE" in
    embedded|full)
        echo
        log_info "Running STM32 environment setup..."
        "$ROOT_DIR/install/stm32.sh"
    
        echo 
        log_info "Running STM32CubeMX setup..."
        "$ROOT_DIR/install/cubemx.sh"
        ;;
    esac 

    case "$PROFILE" in 
    ai|full)
        echo 
        log_info "Running AI development tools setup..."
	"$ROOT_DIR/install/ai-tools.sh"
	;;
    esac

    echo
    log_ok "Bootstrap completed successfully."
}

main "$@"
