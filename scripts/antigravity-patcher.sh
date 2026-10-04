#!/usr/bin/env bash
set -euo pipefail

TARGET="${1:-}"

if [[ -z "$TARGET" ]]; then
    echo "Usage: $0 <manager|cli|ide>"
    exit 1
fi

REPO_URL="https://github.com/QNIX-Dev/eligibility-antigravity-patcher.git"
PATCHER_DIR="$HOME/workspace/eligibility-antigravity-patcher"
MANAGER_PATH="$HOME/.local/opt/antigravity/current/resources/bin/language_server"
CLI_PATH="$HOME/.local/bin/agy"
IDE_PATH="$HOME/.local/opt/antigravity/current/resources/app.asar"
ANTIGRAVITY_ROOT="$HOME/.local/opt/antigravity"
ANTIGRAVITY_CURRENT="$ANTIGRAVITY_ROOT/current"
ANTIGRAVITY_BINARY="$ANTIGRAVITY_CURRENT/antigravity"

log_info() {
    echo "[INFO]  $*"
}

log_ok() {
    echo "[OK]    $*"
}

log_error() {
    echo "[ERROR] $*" >&2
}

die() {
    log_error "$*"
    exit 1
}

# ---------------------------------------------------------------------------
# 1. Verify Antigravity CLI
# ---------------------------------------------------------------------------

if ! command -v agy >/dev/null 2>&1; then
    die "Antigravity CLI is not installed."
fi

cli_version="$(agy --version 2>/dev/null || true)"
cli_version="${cli_version%%$'\n'*}"

if [[ -n "$cli_version" ]]; then
    log_ok "Antigravity CLI detected: $cli_version"
else
    log_ok "Antigravity CLI detected."
fi

# ---------------------------------------------------------------------------
# 2. Verify Antigravity Desktop
#
# Do NOT execute `antigravity --version`.
# It is an Electron GUI application.
# ---------------------------------------------------------------------------

if [[ -x "$ANTIGRAVITY_BINARY" ]]; then

    desktop_version="installed"

    if [[ -L "$ANTIGRAVITY_CURRENT" ]]; then
        resolved_dir="$(readlink -f "$ANTIGRAVITY_CURRENT")"

        if [[ -n "$resolved_dir" ]]; then
            desktop_version="$(basename "$resolved_dir")"
        fi
    fi

    log_ok "Antigravity Desktop detected: $desktop_version"

elif command -v antigravity >/dev/null 2>&1; then

    log_ok "Antigravity Desktop launcher detected: $(command -v antigravity)"

else
    die "Antigravity Desktop is not installed."
fi

# ---------------------------------------------------------------------------
# 3. Check required tools
# ---------------------------------------------------------------------------

command -v git >/dev/null 2>&1 ||
    die "git is not installed."

command -v python3 >/dev/null 2>&1 ||
    die "python3 is not installed."

if ! python3 -m venv --help >/dev/null 2>&1; then
    die "Python venv support is missing. Install python3-venv first."
fi

# ---------------------------------------------------------------------------
# 4. Clone/update patcher repository
# ---------------------------------------------------------------------------

if [[ -d "$PATCHER_DIR/.git" ]]; then

    log_ok "Patcher repository already exists."

    log_info "Updating patcher repository..."

    if git -C "$PATCHER_DIR" pull --ff-only; then
        log_ok "Patcher repository updated."
    else
        die "Could not update patcher repository."
    fi

elif [[ -e "$PATCHER_DIR" ]]; then

    die "Path exists but is not a Git repository: $PATCHER_DIR"

else

    log_info "Cloning patcher repository..."

    mkdir -p "$(dirname "$PATCHER_DIR")"

    git clone "$REPO_URL" "$PATCHER_DIR"

    log_ok "Patcher repository cloned."
fi

# ---------------------------------------------------------------------------
# 5. Enter repository
# ---------------------------------------------------------------------------

cd "$PATCHER_DIR"

log_ok "Working directory: $PATCHER_DIR"

# ---------------------------------------------------------------------------
# 6. Create Python virtual environment
# ---------------------------------------------------------------------------

if [[ ! -x ".venv/bin/python" ]]; then

    log_info "Creating Python virtual environment..."

    python3 -m venv .venv

    log_ok "Virtual environment created."

else
    log_ok "Python virtual environment already exists."
fi

PYTHON="$PATCHER_DIR/.venv/bin/python"

# ---------------------------------------------------------------------------
# 7. Install Python requirements
# ---------------------------------------------------------------------------

if [[ ! -f "requirements.txt" ]]; then
    die "requirements.txt not found."
fi

log_info "Installing Python requirements..."

"$PYTHON" -m pip install \
    --disable-pip-version-check \
    --quiet \
    -r requirements.txt

log_ok "Python requirements installed."

# ---------------------------------------------------------------------------
# 8. Verify manager.py
# ---------------------------------------------------------------------------

if [[ ! -f "manager.py" ]]; then
    die "manager.py not found."
fi

log_ok "Patcher manager found: $PATCHER_DIR/manager.py"

# ---------------------------------------------------------------------------
# 9. Ready
# ---------------------------------------------------------------------------

echo
log_ok "Patcher environment is ready."

# ---------------------------------------------------------------------------
# 10. Target selection
# ---------------------------------------------------------------------------

case "$TARGET" in

    manager)
        log_info "Selected target: Antigravity Manager"

        if [[ ! -f "$MANAGER_PATH" ]]; then
            die "Manager not found: $MANAGER_PATH"
        fi

        "$PYTHON" $PATCHER_DIR/manager.py --path-manager $MANAGER_PATH patch manager
        ;;

    cli)
        log_info "Selected target: Antigravity CLI"

        if [[ ! -x "$CLI_PATH" ]]; then
            die "CLI not found: $CLI_PATH"
        fi

        "$PYTHON" $PATCHER_DIR/manager.py --path-cli $CLI_PATH patch cli
        ;;

    ide)
        log_info "Selected target: Antigravity IDE"

        if [[ ! -f "$IDE_PATH" ]]; then
            die "IDE resource not found: $IDE_PATH"
        fi

        echo "IDE path:"
        echo "  $IDE_PATH"

        "$PYTHON" $PATCHER_DIR/manager.py --path-ide $IDE_PATH patch ide
        ;;

    *)
        die "Invalid target '$TARGET'. Use: manager, cli, or ide"
        ;;

esac

exit 0

