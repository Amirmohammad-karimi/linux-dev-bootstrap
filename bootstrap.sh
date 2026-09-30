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
    log_ok "Bootstrap framework loaded successfully."
    log_info "Install modules will be connected in the next steps."
}

main "$@"
