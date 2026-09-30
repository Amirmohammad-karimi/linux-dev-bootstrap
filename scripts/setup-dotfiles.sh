#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

source "$ROOT_DIR/scripts/helpers.sh"

DOTFILES_DIR="$ROOT_DIR/dotfiles"

SHELL_CONFIG="$HOME/.config/linux-bootstrap/shell.sh"
GIT_CONFIG="$HOME/.config/linux-bootstrap/gitconfig"

remove_exact_line() {
    local line="$1"
    local file="$2"

    [[ -f "$file" ]] || return 0

    local temporary
    temporary="$(mktemp)"

    grep -Fvx -- "$line" "$file" > "$temporary" || true

    cat "$temporary" > "$file"
    rm -f "$temporary"
}

prepare_target() {
    local target="$1"

    if [[ -L "$target" ]]; then
        return 0
    fi

    if [[ -e "$target" ]]; then
        log_warn "Existing unmanaged file found: $target"

        backup_file "$target"
        rm -f "$target"
    fi
}

install_dotfiles() {
    require_command stow

    log_info "Installing managed dotfiles..."

    prepare_target "$SHELL_CONFIG"
    prepare_target "$GIT_CONFIG"

    stow \
        --dir="$DOTFILES_DIR" \
        --target="$HOME" \
        --no-folding \
        --restow \
        common

    log_ok "Managed dotfiles installed."
}

configure_bash() {
    local bashrc="$HOME/.bashrc"

    log_info "Configuring Bash..."

    touch "$bashrc"

    # Remove configuration previously written directly by node.sh.
    remove_exact_line \
        'export NVM_DIR="$HOME/.nvm"' \
        "$bashrc"

    remove_exact_line \
        '[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"' \
        "$bashrc"

    remove_exact_line \
        '[ -s "$NVM_DIR/bash_completion" ] && \. "$NVM_DIR/bash_completion"' \
        "$bashrc"

    # Bash only needs one bootstrap-managed line.
    append_line_if_missing \
        '[ -f "$HOME/.config/linux-bootstrap/shell.sh" ] && . "$HOME/.config/linux-bootstrap/shell.sh"' \
        "$bashrc"

    log_ok "Bash configuration connected to managed dotfiles."
}

configure_git() {
    require_command git

    log_info "Configuring Git..."

    if git config --global --get-all include.path 2>/dev/null |
        grep -Fxq "$GIT_CONFIG"; then

        log_ok "Git bootstrap configuration already included"
        return 0
    fi

    git config --global --add include.path "$GIT_CONFIG"

    log_ok "Git bootstrap configuration included."
}

verify_dotfiles() {
    log_info "Managed configuration:"

    local expected_shell
    local expected_git
    local actual_shell
    local actual_git

    expected_shell="$(readlink -f "$DOTFILES_DIR/common/.config/linux-bootstrap/shell.sh")"
    expected_git="$(readlink -f "$DOTFILES_DIR/common/.config/linux-bootstrap/gitconfig")"

    actual_shell="$(readlink -f "$SHELL_CONFIG" 2>/dev/null || true)"
    actual_git="$(readlink -f "$GIT_CONFIG" 2>/dev/null || true)"

    if [[ "$actual_shell" == "$expected_shell" ]]; then
        printf '  Shell: %s\n' "$SHELL_CONFIG"
    else
        die "Shell configuration is not managed by Stow."
    fi

    if [[ "$actual_git" == "$expected_git" ]]; then
        printf '  Git:   %s\n' "$GIT_CONFIG"
    else
        die "Git configuration is not managed by Stow."
    fi

    log_ok "Managed configuration verified."
}

main() {
    install_dotfiles
    configure_bash
    configure_git
    verify_dotfiles
}

main "$@"
