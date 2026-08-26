# PATH

export PATH="$HOME/.nix-profile/bin:$PATH"
export PATH="$HOME/.cargo/bin:$PATH"
export PATH="$HOME/.local/bin:$PATH"

# NOTE: declared here rather than appended by install-brew.sh — that wrote through the
# symlink and dirtied the repo.
[[ -x /opt/homebrew/bin/brew ]] && eval "$(/opt/homebrew/bin/brew shellenv)"

# XDG base directories

export XDG_CONFIG_HOME="$HOME/.config"
export XDG_DATA_HOME="$HOME/.local/share"
export XDG_CACHE_HOME="$HOME/.cache"
export XDG_STATE_HOME="$HOME/.local/state"
# NOTE: HISTFILE and .zcompdump are deliberately NOT moved here — that would break the
# existing command history and require migrating files. These declarations only make the
# `${XDG_CACHE_HOME:-…}` expansions elsewhere resolve explicitly instead of by fallback.

export VISUAL='nvim'
export EDITOR='nvim'
export COLORTERM='truecolor'

# Resource limits

# NOTE: macOS hands out a soft limit of 256 fds through launchd, inherited by the whole
# chain launchd → Ghostty → zsh → children. libgit2 inside nix keeps far more open while
# packing nixpkgs and dies with "Too many open files". The ceiling is kern.maxfilesperproc
# (10240); the kernel allows no more.
# NOTE: raised only — Linux containers sometimes start above 10240 and must not be lowered.
_nofile_soft=$(ulimit -Sn 2>/dev/null)
if [ -n "$_nofile_soft" ] && [ "$_nofile_soft" != "unlimited" ] && [ "$_nofile_soft" -lt 10240 ] 2>/dev/null; then
  ulimit -n 10240 2>/dev/null || true
fi
unset _nofile_soft
