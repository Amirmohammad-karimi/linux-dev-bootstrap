#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT_DIR/scripts/helpers.sh"
LOCAL_CONFIG="$ROOT_DIR/config/local.env"
load_local_env "$LOCAL_CONFIG"
TARGET_USER="${SUDO_USER:-$USER}"

docker_server_available() { command_exists docker && docker info >/dev/null 2>&1; }
docker_engine_installed() { package_installed docker-ce; }
docker_desktop_detected() {
    docker_server_available || return 1
    docker info --format '{{.OperatingSystem}}' 2>/dev/null | grep -qi "docker desktop"
}

remove_conflicting_packages() {
    local conflicting=(docker.io docker-compose docker-compose-v2 docker-doc docker-buildx podman-docker containerd runc)
    local installed=()
    local package
    for package in "${conflicting[@]}"; do package_installed "$package" && installed+=("$package"); done
    [[ "${#installed[@]}" -eq 0 ]] && return 0
    log_info "Removing conflicting Docker packages: ${installed[*]}"
    ensure_sudo
    sudo apt-get remove -y "${installed[@]}"
    log_ok "Conflicting Docker packages removed."
}

configure_docker_repository() {
    log_info "Configuring official Docker APT repository..."
    ensure_apt_dependency ENABLE_CA_CERTIFICATES ca-certificates "Docker repository setup" yes
    ensure_apt_dependency ENABLE_CURL curl "Docker repository setup" yes
    require_command curl
    ensure_sudo
    sudo install -m 0755 -d /etc/apt/keyrings
    if [[ ! -f /etc/apt/keyrings/docker.asc ]]; then
        curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo tee /etc/apt/keyrings/docker.asc >/dev/null
        sudo chmod a+r /etc/apt/keyrings/docker.asc
        log_ok "Docker signing key installed."
    else log_ok "Docker signing key already installed."; fi
    local codename arch
    codename="$(source /etc/os-release; printf '%s' "${UBUNTU_CODENAME:-$VERSION_CODENAME}")"
    arch="$(dpkg --print-architecture)"
    sudo tee /etc/apt/sources.list.d/docker.sources >/dev/null <<EOF_REPO
Types: deb
URIs: https://download.docker.com/linux/ubuntu
Suites: $codename
Components: stable
Architectures: $arch
Signed-By: /etc/apt/keyrings/docker.asc
EOF_REPO
    APT_UPDATED=0
    apt_update
    log_ok "Docker APT repository configured."
}

install_docker_packages() {
    if docker_desktop_detected; then log_ok "Docker Desktop WSL integration already working"; return 0; fi

    if feature_enabled ENABLE_DOCKER_ENGINE yes; then
        feature_enabled ENABLE_DOCKER_CLI yes || die "ENABLE_DOCKER_ENGINE=yes requires ENABLE_DOCKER_CLI=yes"
        feature_enabled ENABLE_CONTAINERD yes || die "ENABLE_DOCKER_ENGINE=yes requires ENABLE_CONTAINERD=yes"
    fi

    if is_wsl && command_exists docker && ! docker_engine_installed && ! docker_server_available && feature_enabled ENABLE_DOCKER_ENGINE yes; then
        die "Docker CLI exists but no local Docker Engine is detected and the daemon is unavailable. Docker Desktop may be stopped or WSL integration may be disabled. Refusing to install a second Engine automatically."
    fi

    local packages=()
    feature_enabled ENABLE_DOCKER_ENGINE yes && packages+=(docker-ce)
    feature_enabled ENABLE_DOCKER_CLI yes && packages+=(docker-ce-cli)
    feature_enabled ENABLE_CONTAINERD yes && packages+=(containerd.io)
    feature_enabled ENABLE_DOCKER_BUILDX yes && packages+=(docker-buildx-plugin)
    feature_enabled ENABLE_DOCKER_COMPOSE yes && packages+=(docker-compose-plugin)
    [[ "${#packages[@]}" -eq 0 ]] && { log_info "No Docker packages selected."; return 0; }

    remove_conflicting_packages
    configure_docker_repository
    log_info "Installing selected Docker packages..."
    apt_install "${packages[@]}"
    log_ok "Selected Docker packages installed."
}

start_docker() {
    docker_server_available && return 0
    if ! feature_enabled ENABLE_DOCKER_ENGINE yes; then
        log_info "Docker Engine service not managed because ENABLE_DOCKER_ENGINE=no"
        return 0
    fi
    docker_engine_installed || die "Docker Engine enabled but docker-ce is not installed."
    ensure_sudo
    if sudo docker info >/dev/null 2>&1; then log_ok "Docker daemon already running"; return 0; fi
    log_info "Starting Docker..."
    if command_exists systemctl && [[ "$(ps -p 1 -o comm=)" == "systemd" ]]; then
        sudo systemctl enable --now docker
    else
        sudo service docker start
    fi
    sudo docker info >/dev/null 2>&1 || die "Docker daemon failed to start."
    log_ok "Docker daemon started."
}

configure_docker_user() {
    if ! feature_enabled ENABLE_DOCKER_NONROOT yes; then
        log_feature_disabled "Non-root Docker access" "ENABLE_DOCKER_NONROOT"
        return 0
    fi
    docker_desktop_detected && return 0
    docker_engine_installed || return 0
    if ! getent group docker >/dev/null 2>&1; then log_warn "Docker group does not exist."; return 0; fi
    if id -nG "$TARGET_USER" | tr ' ' '\n' | grep -qx docker; then
        if docker_server_available; then log_ok "$TARGET_USER already belongs to docker group"
        else log_warn "Docker group membership is configured but is not active in this shell."; log_warn "Open a new shell or run: newgrp docker"; fi
        return 0
    fi
    ensure_sudo
    sudo usermod -aG docker "$TARGET_USER"
    log_ok "Added $TARGET_USER to docker group"
    log_warn "Open a new shell before using Docker without sudo."
}

verify_docker() {
    log_info "Docker toolchain:"
    if feature_enabled ENABLE_DOCKER_CLI yes; then
        command_exists docker && printf '  Docker:  %s\n' "$(docker --version)" || log_warn "Docker CLI enabled but unavailable."
    else printf '  Docker:  disabled\n'; fi

    if feature_enabled ENABLE_DOCKER_COMPOSE yes; then
        command_exists docker && docker compose version >/dev/null 2>&1 && printf '  Compose: %s\n' "$(docker compose version)" || log_warn "Docker Compose enabled but unavailable."
    else printf '  Compose: disabled\n'; fi

    if feature_enabled ENABLE_DOCKER_BUILDX yes; then
        command_exists docker && docker buildx version >/dev/null 2>&1 && printf '  Buildx:  %s\n' "$(docker buildx version | head -n1)" || log_warn "Docker Buildx enabled but unavailable."
    else printf '  Buildx:  disabled\n'; fi

    if docker_server_available; then printf '  Server:  running\n'
    elif docker_engine_installed && sudo docker info >/dev/null 2>&1; then printf '  Server:  running (sudo required until new login)\n'
    elif feature_enabled ENABLE_DOCKER_ENGINE yes; then die "Docker server verification failed."
    else printf '  Server:  not managed\n'; fi
}

main() {
    if ! feature_enabled ENABLE_DOCKER yes; then log_feature_disabled "Docker" "ENABLE_DOCKER"; return 0; fi
    install_docker_packages
    start_docker
    configure_docker_user
    verify_docker
}
main "$@"
