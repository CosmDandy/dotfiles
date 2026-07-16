# =============================================================================
# PATH CONFIGURATION
# =============================================================================

export PATH="$HOME/.nix-profile/bin:$PATH"
export PATH="$HOME/.cargo/bin:$PATH"
export PATH="$HOME/.local/bin:$PATH"

# brew в PATH логин-шелла (раньше install-brew.sh дописывал эту строку в
# ~/.zprofile императивно — сквозь симлинк это пачкало репо)
[[ -x /opt/homebrew/bin/brew ]] && eval "$(/opt/homebrew/bin/brew shellenv)"

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
export COLORTERM='truecolor'

# =============================================================================
# RESOURCE LIMITS
# =============================================================================

# macOS отдаёт через launchd soft-лимит в 256 fd, и его наследует вся цепочка
# launchd → Ghostty → zsh → дочерние процессы. libgit2 внутри nix (fetch flake-
# инпутов в ~/.cache/nix/tarball-cache-v2) на паковке nixpkgs держит открытыми
# сильно больше и падает с "Too many open files". Потолок — kern.maxfilesperproc
# (10240 на macOS); выше ядро не даст. Только повышаем: в Linux-контейнерах soft
# бывает уже больше 10240, понижать его нельзя.
_nofile_soft=$(ulimit -Sn 2>/dev/null)
if [ -n "$_nofile_soft" ] && [ "$_nofile_soft" != "unlimited" ] && [ "$_nofile_soft" -lt 10240 ] 2>/dev/null; then
  ulimit -n 10240 2>/dev/null || true
fi
unset _nofile_soft

