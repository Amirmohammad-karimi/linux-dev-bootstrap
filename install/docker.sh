#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

source "$ROOT_DIR/scripts/helpers.sh"

TARGET_USER="${SUDO_USER:-$USER}"

docker_server_available() {
    command_exists docker && docker info >/dev/null 2>&1
}

docker_engine_installed() {
    package_installed docker-ce
}

docker_desktop_detected() {
    if ! docker_server_available; then
        return 1
    fi

    docker info --format '{{.OperatingSystem}}' 2>/dev/null |
        grep -qi "docker desktop"
}

remove_conflicting_packages() {
    local conflicting=(
        docker.io
        docker-compose
        docker-compose-v2
        docker-doc
        docker-buildx
        podman-docker
        containerd
        runc
    )

    local installed=()
    local package

    for package in "${conflicting[@]}"; do
        if package_installed "$package"; then
            installed+=("$package")
        fi
    done

    if [[ "${#installed[@]}" -eq 0 ]]; then
        return 0
    fi

    log_info "Removing conflicting Docker packages: ${installed[*]}"

    ensure_sudo
    sudo apt-get remove -y "${installed[@]}"

    log_ok "Conflicting Docker packages removed."
}

configure_docker_repository() {
    log_info "Configuring official Docker APT repository..."

    apt_install ca-certificates curl

    ensure_sudo

    sudo install -m 0755 -d /etc/apt/keyrings

    if [[ ! -f /etc/apt/keyrings/docker.asc ]]; then
        curl -fsSL https://download.docker.com/linux/ubuntu/gpg |
            sudo tee /etc/apt/keyrings/docker.asc >/dev/null

        sudo chmod a+r /etc/apt/keyrings/docker.asc

        log_ok "Docker signing key installed."
    else
        log_ok "Docker signing key already installed."
    fi

    local codename
    local arch

    codename="$(
        source /etc/os-release
        printf '%s' "${UBUNTU_CODENAME:-$VERSION_CODENAME}"
    )"

    arch="$(dpkg --print-architecture)"

    sudo tee /etc/apt/sources.list.d/docker.sources >/dev/null <<EOF_REPO
Types: deb
URIs: https://download.docker.com/linux/ubuntu
Suites: $codename
Components: stable
Architectures: $arch
Signed-By: /etc/apt/keyrings/docker.asc
EOF_REPO

    # Repository may have changed, so force an APT refresh.
    APT_UPDATED=0
    apt_update

    log_ok "Docker APT repository configured."
}

install_docker_engine() {
    if docker_server_available; then
        if docker_desktop_detected; then
            log_ok "Docker Desktop WSL integration already working"
        else
            log_ok "Docker Engine already working"
        fi

        return 0
    fi

    if docker_engine_installed; then
        log_ok "Docker Engine already installed"
        return 0
    fi

    if is_wsl && command_exists docker; then
        die "Docker CLI exists but no local docker-ce installation is detected and the daemon is unavailable. Docker Desktop may be stopped or WSL integration may be disabled. Refusing to install a second Docker Engine automatically."
    fi

    remove_conflicting_packages
    configure_docker_repository

    log_info "Installing Docker Engine..."

    apt_install \
        docker-ce \
        docker-ce-cli \
        containerd.io \
        docker-buildx-plugin \
        docker-compose-plugin

    log_ok "Docker Engine packages installed."
}

start_docker() {
    if docker_server_available; then
        return 0
    fi

    ensure_sudo

    # The daemon may already be running while the current shell still lacks
    # the newly granted docker-group membership.
    if docker_engine_installed &&
       sudo docker info >/dev/null 2>&1; then
        log_ok "Docker daemon already running"
        return 0
    fi

    log_info "Starting Docker..."

    if command_exists systemctl &&
       [[ "$(ps -p 1 -o comm=)" == "systemd" ]]; then

        sudo systemctl enable --now docker
    else
        sudo service docker start
    fi

    if ! sudo docker info >/dev/null 2>&1; then
        die "Docker daemon failed to start."
    fi

    log_ok "Docker daemon started."
}

configure_docker_user() {
    if docker_desktop_detected; then
        return 0
    fi

    if ! getent group docker >/dev/null 2>&1; then
        log_warn "Docker group does not exist."
        return 0
    fi

    if id -nG "$TARGET_USER" | tr ' ' '\n' | grep -qx docker; then
        if docker_server_available; then
            log_ok "$TARGET_USER already belongs to docker group"
        else
            log_warn "Docker group membership is configured but is not active in this shell."
            log_warn "Open a new shell or run: newgrp docker"
        fi
        return 0
    fi

    ensure_sudo

    sudo usermod -aG docker "$TARGET_USER"

    log_ok "Added $TARGET_USER to docker group"
    log_warn "Open a new shell before using Docker without sudo."
}

verify_docker() {
    log_info "Docker toolchain:"

    printf '  Docker:  %s\n' "$(docker --version)"
    printf '  Compose: %s\n' "$(docker compose version)"
    printf '  Buildx:  %s\n' "$(docker buildx version | head -n1)"

    if docker_server_available; then
        printf '  Server:  running\n'
    elif sudo docker info >/dev/null 2>&1; then
        printf '  Server:  running (sudo required until new login)\n'
    else
        die "Docker server verification failed."
    fi
}

main() {
    install_docker_engine
    start_docker
    configure_docker_user
    verify_docker
}

main "$@"
