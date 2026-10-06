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

backup_dotfile_conflicts() {
    local source_root="$DOTFILES_DIR/common"
    local backup_root="$HOME/.local/state/linux-dev-bootstrap/dotfiles-backup"

    while IFS= read -r -d '' source; do
        local relative="${source#$source_root/}"
        local target="$HOME/$relative"

        [[ -e "$target" || -L "$target" ]] || continue

        # Keep a symlink that already points at the managed source.
        if [[ -L "$target" ]]; then
            local expected_target
            local actual_target

            expected_target="$(readlink -f "$source" 2>/dev/null || true)"
            actual_target="$(readlink -f "$target" 2>/dev/null || true)"

            if [[ -n "$expected_target" && "$actual_target" == "$expected_target" ]]; then
                continue
            fi
        fi

        local backup="$backup_root/$relative"

        if [[ -e "$backup" || -L "$backup" ]]; then
            backup="${backup}.$(date +%Y%m%d-%H%M%S)"
        fi

        log_warn "Existing unmanaged target found: $target"

        mkdir -p "$(dirname "$backup")"
        mv "$target" "$backup"

        log_ok "Backup created: $backup"
    done < <(
        find "$source_root" \(
            -type f -o -type l
        \) -print0
    )
}

install_dotfiles() {
    require_command stow

    log_info "Installing managed dotfiles..."

    backup_dotfile_conflicts

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
