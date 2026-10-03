#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

source "$ROOT_DIR/scripts/helpers.sh"

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
    log_info "Installing managed dotfiles..."
    "$ROOT_DIR/scripts/setup-dotfiles.sh"	

    echo
    log_ok "Bootstrap completed successfully."
}

main "$@"
