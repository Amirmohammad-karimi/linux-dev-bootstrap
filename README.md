# Linux Dev Bootstrap

Reproducible Linux/WSL development workstation bootstrap for embedded development, STM32, Docker, VS Code, Python, Node.js, and AI development tools.

The goal of this repository is to turn a fresh Ubuntu/WSL installation into a ready-to-use development environment with a single command.

```bash
./bootstrap.sh
```

The scripts are designed to be **idempotent**: running the bootstrap multiple times should detect existing tools and configuration instead of reinstalling everything unnecessarily.

---

## Supported Environment

Primary tested environment:

- Ubuntu 24.04 LTS
- WSL2 on Windows 11
- x86_64
- WSLg for Linux GUI applications

Native Ubuntu Linux should work for most components, although some WSL-specific functionality such as `usbipd` integration is only applicable to WSL.

---

## What It Installs

### Base System

Common development utilities:

- Git
- curl
- wget
- jq
- unzip / zip
- tar / xz
- build-essential
- GNU Stow
- htop
- tree
- rsync
- OpenSSH client
- common development libraries

---

### Python Development

Installs and configures:

- Python 3
- pip
- venv
- Python development headers
- pipx
- uv

Example tested versions:

```text
Python 3.12.3
pip 24.0
pipx 1.4.3
uv 0.12.21
```

Python packages are not installed globally with `sudo pip`. Virtual environments, `pipx`, and `uv` are preferred.

---

### Node.js Development

Node.js is installed through `nvm`.

Current tested setup:

```text
nvm 0.40.8
Node.js 24.21.0
npm 11.19.0
npx 11.19.0
```

The default Node.js version is configured automatically.

---

### Docker

Installs and configures Docker Engine with:

- Docker Engine
- Docker CLI
- Docker Compose
- Docker Buildx
- non-root Docker access

Example tested setup:

```text
Docker 29.8.1
Docker Compose v5.5.1
Buildx v0.37.1
```

The bootstrap adds the current user to the `docker` group when required.

---

### VS Code for WSL

The bootstrap uses the Windows VS Code installation through WSL instead of installing a second Linux VS Code package.

Managed extensions include:

- Python
- Debugpy
- Pylance
- Python Environments
- CMake Tools
- C/C++ development tools
- ChatGPT
- Serial Monitor
- Memory Inspector
- STM32 VS Code extensions

Example:

```text
VS Code 1.140.0
WSL extensions: 22
```

---

## STM32 Development Environment

The bootstrap creates a reproducible STM32 development environment using STM32Cube VS Code bundles.

Configured bundles currently include:

```text
cmake@4.3.1+st.1
gnu-tools-for-stm32@14.3.1+st.2
ninja@1.13.2+st.1
programmer@2.23.0
st-arm-clangd@21.1.0+st.2
stlink-gdbserver@7.14.0+st.2
stlink-udev-rules@1.0.3-3+st.3
```

The bundle location is:

```text
~/.local/share/stm32cube/bundles
```

CMSIS packs are stored under:

```text
~/.local/share/stm32cube/packs
```

The bootstrap also provides a managed `cube` launcher:

```bash
cube
```

---

## ST-LINK / USBIPD

For WSL, the bootstrap can configure ST-LINK USB forwarding from Windows using `usbipd-win`.

Supported ST-LINK USB IDs are stored in:

```text
config/stlink-usb-ids.txt
```

Current configured IDs include:

```text
0483:3744
0483:3748
0483:374b
0483:3752
0483:374d
0483:374e
0483:374f
0483:3753
```

The bootstrap dynamically detects the Windows USB BUSID and attaches the device to WSL.

Example successful detection:

```text
ST-LINK 0483:3748 detected
Permissions: root plugdev
Current user has read/write access
```

---

## STM32CubeMX

STM32CubeMX is managed separately from the STM32 development bundles.

Current tested version:

```text
STM32CubeMX 6.18.1
```

Installation:

```text
~/STM32CubeMX
```

Stable bootstrap-managed path:

```text
~/.local/opt/stm32cubemx/current
```

Launcher:

```bash
stm32cubemx
```

A detached launcher is also available:

```bash
stm32cubemx-silent
```

Some STM32CubeMX installation steps may still require interaction with ST's official installer.

---

## AI Development Tools

Step 11 configures the AI development environment.

Currently supported tools include:

| Tool | Type | Optional |
|---|---|---:|
| OpenCode | CLI / coding agent | No |
| ChatGPT | Desktop | Yes |
| Antigravity | CLI | Yes |
| Antigravity | Desktop | Yes |
| Freebuff | CLI | Yes |
| Freebuff | Desktop | Yes |
| ZCode | Desktop / coding agent | Yes |
| Ollama | Local model runtime | Yes |

Example current environment:

```text
OpenCode:             2.0.20
ChatGPT:              26.928.21956
Antigravity CLI:      1.1.0
Antigravity Desktop:  2.19.1
Freebuff CLI:         0.2.13
Freebuff Desktop:     installed
ZCode:                optional
Ollama:               optional
```

### OpenCode

Installed using the official OpenCode installer.

Managed configuration:

```text
~/.config/opencode/opencode.jsonc
```

Authentication and API secrets should remain outside Git.

---

### ChatGPT Desktop

ChatGPT Linux Desktop can be enabled per machine.

A detached launcher is provided:

```bash
chatgpt-silent
```

This launches the GUI without keeping the terminal attached.

---

### Antigravity CLI

Antigravity CLI is installed using the official installer.

Command:

```bash
agy
```

---

### Antigravity Desktop

The current Linux desktop archive is downloaded and installed under:

```text
~/.local/opt/antigravity/<version>
```

The stable path is:

```text
~/.local/opt/antigravity/current
```

The normal launcher is:

```bash
antigravity
```

A detached launcher is available:

```bash
antigravity-silent
```

On some WSLg systems, Electron GPU acceleration may cause rendering artifacts. The silent launcher can apply the required rendering workaround.

The bootstrap can also prepare an optional third-party Antigravity helper environment. Review the upstream project and its behavior before enabling or using third-party modifications.

---

### Freebuff CLI

Freebuff CLI is installed through npm.

```bash
freebuff
```

The installed version is detected from the npm package metadata instead of invoking `freebuff --version`, because the Freebuff executable may launch the application rather than simply print a version.

---

### Freebuff Desktop

Freebuff Desktop is installed as an AppImage.

Installation location:

```text
~/.local/opt/freebuff/Freebuff.AppImage
```

Launch normally:

```bash
freebuff-desktop
```

Launch detached:

```bash
freebuff-desktop-silent
```

Ubuntu 24.04 requires the FUSE 2 compatibility library for the AppImage:

```text
libfuse2t64
```

The bootstrap installs it automatically when needed.

---

### ZCode

ZCode is available as an optional Linux desktop coding agent.

The bootstrap resolves the current official Linux AppImage from ZCode's install page and installs it at:

```text
~/.local/opt/zcode/ZCode.AppImage
```

Enable it per machine with:

```bash
ENABLE_ZCODE="yes"
ENABLE_ZCODE_FUSE_COMPAT="yes"
```

Launch normally with:

```bash
zcode
```

or detached from the terminal:

```bash
zcode-silent
```

Both managed ZCode launchers force software rendering with `LIBGL_ALWAYS_SOFTWARE=1` and pass Electron's `--disable-gpu` flag. This avoids GPU acceleration and is intended to make ZCode more reliable under WSLg or systems with problematic graphics drivers.

The Linux AppImage may require FUSE compatibility support. On Ubuntu 24.04 the bootstrap can install `libfuse2t64` when necessary.

ZCode does not automatically inherit `HTTP_PROXY` when its proxy field is blank. On proxy-restricted networks, configure the proxy inside **Settings → General** and restart ZCode.

---

### Ollama

Ollama is optional and controlled by machine-local configuration.

If disabled:

```text
Ollama: disabled by config/local.env
```

If enabled, the bootstrap can install Ollama and optionally configure a local model.

Example:

```bash
ENABLE_OLLAMA="yes"
OLLAMA_MODEL="qwen2.5-coder:7b-8k"
```

If Ollama is not required on a machine, it is left untouched.

---

## Repository Structure

```text
linux-dev-bootstrap/
├── bootstrap.sh
│
├── install/
│   ├── base.sh
│   ├── python.sh
│   ├── node.sh
│   ├── docker.sh
│   ├── vscode.sh
│   ├── stm32.sh
│   ├── cubemx.sh
│   └── ai-tools.sh
│
├── packages/
│   ├── apt.txt
│   ├── pipx.txt
│   ├── npm.txt
│   ├── vscode-extensions.txt
│   └── stm32-bundles.txt
│
├── dotfiles/
│   └── common/
│       ├── .config/
│       │   ├── linux-bootstrap/
│       │   └── opencode/
│       └── .local/
│           └── bin/
│
├── config/
│   ├── versions.env
│   ├── cubemx.env
│   ├── local.env.example
│   ├── stlink-usb-ids.txt
│   └── wsl.conf
│
├── profiles/
│
└── scripts/
    ├── helpers.sh
    ├── setup-dotfiles.sh
    ├── setup-stlink-usb.sh
    ├── health-check.sh
    └── windows/
        └── setup-usbipd-stlink.ps1
```

`config/local.env` is intentionally excluded from Git because it contains machine-specific configuration.

Optional proxy configuration is also machine-local. Copy:

```bash
cp config/proxy.env.example config/proxy.env
```

and enable it when the workstation needs a proxy:

```bash
PROXY_ENABLED="yes"
HTTP_PROXY_URL="http://127.0.0.1:10808"
HTTPS_PROXY_URL="http://127.0.0.1:10808"
NO_PROXY="localhost,127.0.0.1"
```

The bootstrap exports the proxy variables for its download commands and writes a bootstrap-managed APT proxy file so `sudo apt` uses the same proxy.

---

# Quick Start

## 1. Install WSL

From an Administrator PowerShell terminal:

```powershell
wsl --install -d Ubuntu-24.04
```

Restart Windows if requested.

---

## 2. Clone the Repository

Inside Ubuntu/WSL:

```bash
mkdir -p ~/workspace/automation
cd ~/workspace/automation

git clone https://github.com/YOUR_USERNAME/linux-dev-bootstrap.git
cd linux-dev-bootstrap
```

---

## 3. Create Machine-Local Configuration

Copy the example:

```bash
cp config/local.env.example config/local.env
```

Edit it:

```bash
nano config/local.env
```

Example:

```bash
ENABLE_CHATGPT="yes"

ENABLE_ANTIGRAVITY_CLI="yes"
ENABLE_ANTIGRAVITY_DESKTOP="yes"

ENABLE_FREEBUFF_CLI="yes"
ENABLE_FREEBUFF_DESKTOP="yes"

ENABLE_OLLAMA="no"
OLLAMA_MODEL=""
```

Different machines can therefore use the same repository while enabling different applications.

### Per-component feature switches

`config/local.env.example` is the source of truth for installation switches.
Every `ENABLE_*` option is documented with an explicit `"yes"` or `"no"` value. Older boolean aliases such as `true`/`false` remain accepted for compatibility.

Switches cover individual base APT packages, Python components, nvm/Node.js,
Docker components, Chrome, VS Code extensions, STM32 bundles and USB
dependencies, STM32CubeMX, and the supported AI applications.

A value of `"no"` means the bootstrap does not explicitly install or manage
that component. It does not uninstall software already present, and an APT
package may still be pulled when it is an unavoidable dependency of another
enabled package.

Existing `config/local.env` files remain compatible: options that are absent
use the bootstrap defaults.

---

## 4. Run the Bootstrap

For the default/full setup:

```bash
./bootstrap.sh
```

Or explicitly:

```bash
./bootstrap.sh full
```

Available profiles are:

```text
minimal
development
embedded
ai
full
```

---

## 5. Reload the Shell

After the first installation:

```bash
exec bash
```

or close and reopen the WSL terminal.

---

## 6. Verify the Environment

Run:

```bash
./scripts/health-check.sh
```

The health check validates the major components without modifying the system.

A disconnected ST-LINK may appear as a warning rather than an error.

---

## Profiles

### `minimal`

Installs the common Linux base environment.

### `development`

Adds:

- Python
- Node.js
- Docker
- VS Code configuration

### `embedded`

Adds the STM32 development environment:

- STM32Cube bundles
- ARM GCC
- CMake
- Ninja
- STM32CubeProgrammer
- ST-LINK GDB server
- USB rules
- STM32CubeMX
- WSL USB forwarding support

### `ai`

Installs/configures the selected AI development tools.

### `full`

Runs the complete workstation setup.

---

## Managed Dotfiles

Configuration is stored in this repository and installed using GNU Stow.

Managed configuration includes:

```text
~/.config/linux-bootstrap/shell.sh
~/.config/linux-bootstrap/gitconfig
~/.config/opencode/opencode.jsonc
~/.local/bin/*
```

The `.bashrc` only needs a small bootstrap-managed source line:

```bash
[ -f "$HOME/.config/linux-bootstrap/shell.sh" ] &&
    . "$HOME/.config/linux-bootstrap/shell.sh"
```

This keeps shell configuration reproducible without replacing the user's entire `.bashrc`.

---

## GUI Launchers

GUI applications can be launched normally or detached from the terminal.

Examples:

```bash
chatgpt-silent
antigravity-silent
freebuff-desktop-silent
zcode-silent
stm32cubemx-silent
```

The silent launchers:

- detach the application from the terminal
- redirect stdout/stderr
- prevent GUI logs from filling the terminal
- allow the terminal to be closed without normally terminating the GUI

CLI tools such as Git, Docker, OpenCode, `agy`, Node.js, and STM32 command-line utilities intentionally do not use silent wrappers.

---

## Idempotency

The scripts are designed to be rerunnable.

For example:

```bash
./bootstrap.sh
```

may produce output such as:

```text
[OK] Python already installed
[OK] Docker Engine already working
[OK] STM32 bundle already installed
[OK] Antigravity desktop already installed
[OK] Freebuff Desktop already installed
```

Existing installations are reused whenever possible.

This makes the same repository suitable for:

- setting up a new PC
- rebuilding a WSL distribution
- keeping multiple workstations consistent
- recovering a development environment after reinstalling Windows/Linux

---

## Reproducibility Philosophy

This repository intentionally stores:

```text
scripts
configuration
package manifests
version definitions
dotfiles
installation logic
```

It does **not** normally store:

```text
SDK archives
toolchain binaries
AppImages
large installers
AI models
credentials
API keys
authentication sessions
machine-specific secrets
```

Large or proprietary components are downloaded from their official sources during setup.

---

## Secrets

Do not commit credentials or API keys.

Machine-specific configuration belongs in:

```text
config/local.env
```

and that file should remain ignored by Git.

Authentication files for tools such as OpenCode should also remain outside the repository.

For example:

```text
~/.local/share/opencode/auth.json
```

should not be committed.

---

## Windows / WSL Notes

The intended setup uses Windows 11 with WSL2.

Windows PATH inheritance may be disabled, and only selected Windows tools are exposed to WSL through managed wrappers.

ST-LINK devices are forwarded from Windows to WSL with `usbipd-win`.

WSLg is used for Linux GUI applications including:

- STM32CubeMX
- ChatGPT
- Antigravity
- Freebuff
- ZCode

---

## Health Check

Run:

```bash
./scripts/health-check.sh
```

Typical checks include:

```text
Python
pipx
uv
Node.js
npm
Docker
Docker Compose
Docker Buildx
VS Code
STM32Cube CLI
GNU ARM toolchain
STM32CubeMX
ST-LINK
OpenCode
ChatGPT
Antigravity
Freebuff
ZCode
Ollama
managed dotfiles
WSL / WSLg
```

---

## Updating the Environment

Pull repository changes:

```bash
git pull
```

Then rerun:

```bash
./bootstrap.sh
```

Because the scripts are idempotent, only missing or changed components should require action.

---

## Development Workflow

The environment is intentionally separated into three layers:

```text
linux-dev-bootstrap
        ↓
configures the workstation

development container repositories
        ↓
configure project-specific development environments

project repositories
        ↓
contain application / firmware source code
```

This avoids mixing workstation provisioning with project-specific code.

---

## Example Full Installation

```bash
git clone https://github.com/YOUR_USERNAME/linux-dev-bootstrap.git
cd linux-dev-bootstrap

cp config/local.env.example config/local.env
nano config/local.env

./bootstrap.sh full

exec bash

./scripts/health-check.sh
```

After that, the workstation should be ready for general development, embedded STM32 development, Docker workflows, and the enabled AI development tools.

---

## Tested Setup

Example successfully tested environment:

```text
OS:                Ubuntu 24.04 LTS
Environment:       WSL2
Architecture:      x86_64

Python:            3.12.3
uv:                0.12.21

Node.js:           24.21.0
npm:               11.19.0

Docker:            29.8.1
Docker Compose:    5.5.1
Buildx:            0.37.1

VS Code:           1.140.0

STM32 GCC:         14.3.1
STM32CubeMX:       6.18.1

OpenCode:          2.0.20
Antigravity CLI:   1.1.0
Antigravity:       2.19.1
Freebuff CLI:      0.2.13
```

Versions will evolve as the bootstrap is updated.

---

## Project Goal

The goal is simple:

> Clone one repository, run one bootstrap command, and reproduce the development workstation.

Instead of manually remembering how every tool was installed, the installation process itself becomes version-controlled infrastructure.