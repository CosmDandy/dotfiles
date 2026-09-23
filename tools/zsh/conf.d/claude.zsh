# Claude Code — launch aliases and memory helpers. Identical on the mac and in containers.

# NOTE: the autocompact threshold IS in the env block of settings.json, but that is not
# enough: from there variables are handed to CHILD processes (Bash tools, hooks), while
# Claude Code itself reads the threshold from its own process.env — i.e. only what was in
# the environment at launch. A session started by the daemon inherits it; `claude` run by
# hand from a shell does not and falls back to "window − 13000" (~987K instead of 650K on
# a 1M window). Measured in one container: the daemon session compacted 4 times by 258K,
# the shell session reached 819K with no autocompact at all.
export CLAUDE_AUTOCOMPACT_PCT_OVERRIDE=65

# Inside tmux Claude Code caps its own palette at 256 colours — the check is literally
# `if (TMUX && level > 2) level = 2`, with this variable as the documented way out. The
# cap is not harmless: 24-bit theme colours get rounded to the nearest xterm cube entry,
# and those are not Solarized. The message plate #164450 came out as a washed blue and
# the body text #93a1a1 as 38;5;103 — #8787af, visibly violet. Verified by reading the
# bytes tmux writes to the pty: with the variable set they are 38;2;... again.
# tmux itself is innocent — a printf of a 24-bit sequence passes through it untouched.
# NOTE: the shell, not the env block of settings.json. Claude Code reads this from its
# OWN process.env at startup, and settings.json env only reaches child processes — the
# same reason CLAUDE_AUTOCOMPACT_PCT_OVERRIDE lives here.
export CLAUDE_CODE_TMUX_TRUECOLOR=1

# The everyday one.
# NOTE: the auto-mode classifier is off — an audit of five containers showed it caused 100%
# of the interruptions in background sessions, while interactively 135 of 136 prompts were
# approved unchanged. The barrier is the deny rules plus pretooluse-guard.sh, which was
# written for exactly this mode and applies in full here.
# The flag duplicates defaultMode from settings.json on purpose: it does not depend on the
# client honouring bypass from the file.
alias cl='claude --permission-mode bypassPermissions'
# Back to semantic checks when needed for one run: swapped remotes or endpoints, deleting
# somebody's stateful resources, pushing secrets, boundaries stated in words.
alias cla='claude --permission-mode auto'
# Sandboxed research: writes only into the working directory, network by allowlist, ~/.ssh
# and tokens closed. Strict — there is no fallback outward.
alias cls='claude --settings ~/.dotfiles/tools/claude/settings.sandbox.json --permission-mode auto'

claude-memory-init() {
    local dotfiles_dir="${HOME}/.dotfiles"
    [[ ! -d "$dotfiles_dir" ]] && dotfiles_dir="${HOME}/dotfiles"
    "${dotfiles_dir}/tools/claude/custom/setup.sh" "${1:-$(basename "$PWD")}" "$PWD"
}

claude-memory-push() {
    local dotfiles_dir="${HOME}/.dotfiles"
    [[ ! -d "$dotfiles_dir" ]] && dotfiles_dir="${HOME}/dotfiles"
    local submodule_dir="${dotfiles_dir}/tools/claude/custom"

    local project="$1"
    if [[ -z "$project" ]]; then
        local encoded_path
        encoded_path="$(pwd | sed 's|[/.]|-|g')"
        local memory_link="$HOME/.claude/projects/${encoded_path}/memory"
        if [[ -L "$memory_link" ]]; then
            project="$(basename "$(dirname "$(readlink "$memory_link")")")"
        else
            project="$(basename "$PWD" | sed 's/^\.//')"
        fi
    fi

    local memory_path="knowledge/${project}/memory"

    if [[ ! -d "${submodule_dir}/${memory_path}" ]]; then
        echo "Memory not found: ${memory_path}" >&2
        return 1
    fi

    git -C "$submodule_dir" add "knowledge/${project}"
    git -C "$submodule_dir" diff --cached --quiet && {
        echo "No changes for ${project}"
        return 0
    }
    git -C "$submodule_dir" commit -m "docs(${project}): update knowledge"
    git -C "$submodule_dir" push
}

# Repoints ~/.claude/themes/solarized.json at the dark or light file. settings.json keeps
# `"theme": "custom:solarized"`, so the slug never changes — only what the file holds.
# Solarized both sides: base02/base2 for the message plate, the same pair nvim uses for
# CursorLine and fzf for bg+, so a session reads as part of the same desktop.
# NOTE: copied, not symlinked. Claude watches the themes directory and rereads what
# changed; a repointed symlink leaves the target file's mtime untouched, and whether the
# watcher notices then depends on how it resolves links. A copy always looks changed.
# NOTE: this is what makes the switch live — a running session repaints itself, which is
# why `term-theme` calls it too. Nothing else here can do that: with a custom theme Claude
# stops polling the terminal for the background on its own.
_claude_theme_apply() {
    emulate -L zsh
    local theme="$1"
    if [[ -z "$theme" ]]; then
        _term_is_light
        case $? in
            0) theme=light ;;
            1) theme=dark ;;
            *)
                if [[ "$OSTYPE" == darwin* ]] && ! defaults read -g AppleInterfaceStyle &>/dev/null; then
                    theme=light
                else
                    theme=dark
                fi ;;
        esac
    fi
    local dir="$HOME/.claude/themes"
    local src="${DOTFILES_DIR:-$HOME/.dotfiles}/tools/claude/themes/solarized-${theme}.json"
    [[ -r "$src" ]] || return 1
    mkdir -p "$dir" 2>/dev/null || return 1
    # Idempotent: an unchanged file is left alone, so starting a shell does not make every
    # running session reload its theme for nothing.
    cmp -s "$src" "$dir/solarized.json" 2>/dev/null || cp -f "$src" "$dir/solarized.json"
}

# The wrapper picks the theme at launch, where asking the terminal is free — the same
# moment k9s and lazygit ask. Override with CLAUDE_THEME=light|dark.
claude() {
    _claude_theme_apply "$CLAUDE_THEME"
    command claude "$@"
}
