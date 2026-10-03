# Managed by linux-bootstrap.
# Do not put secrets in this file.

# User-installed command line tools
case ":$PATH:" in
    *":$HOME/.local/bin:"*) ;;
    *) export PATH="$HOME/.local/bin:$PATH" ;;
esac

# NVM / Node.js
export NVM_DIR="$HOME/.nvm"

if [ -s "$NVM_DIR/nvm.sh" ]; then
    . "$NVM_DIR/nvm.sh"
fi

if [ -s "$NVM_DIR/bash_completion" ]; then
    . "$NVM_DIR/bash_completion"
fi

# STM32Cube
export CUBE_BUNDLE_PATH="$HOME/.local/share/stm32cube/bundles"
export CMSIS_PACK_ROOT="$HOME/.local/share/stm32cube/packs"

# STM32CubeMX
export STM32CubeMX_PATH="$HOME/.local/opt/stm32cubemx/current"
