# =============================================================================
# PATH CONFIGURATION
# =============================================================================

export PATH="$HOME/.nix-profile/bin:$PATH"
export PATH="$HOME/.cargo/bin:$PATH"
export PATH="$HOME/.local/bin:$PATH"

# =============================================================================
# XDG BASE DIRECTORY SPECIFICATION
# =============================================================================

export XDG_CONFIG_HOME="$HOME/.config"
# export XDG_DATA_HOME="$HOME/.local/share"
# export XDG_CACHE_HOME="$HOME/.cache"
# export XDG_STATE_HOME="$HOME/.local/state"

# =============================================================================
# CORE ENVIRONMENT VARIABLES
# =============================================================================

export VISUAL='nvim'
export EDITOR='nvim'
if ! infocmp "$TERM" &>/dev/null 2>&1; then
  export TERM='xterm-256color'
fi
export COLORTERM='truecolor'

