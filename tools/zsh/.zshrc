# Terminal compatibility

# NOTE: the verdict is cached per TERM value, not hardcoded. `infocmp` is a
# process spawn on every shell — 3-7 ms — for an answer that changes only when
# the terminfo database does. An allowlist would have been wrong here: the value
# most likely to be MISSING is xterm-ghostty inside a container, which is the
# exact case this check exists for, so it must still be asked once per machine.
# Both outcomes are remembered; a container without the entry pays the spawn
# once, not on every shell.
() {
    local dir=${XDG_CACHE_HOME:-$HOME/.cache}/zsh
    local ok=$dir/term-ok-$TERM bad=$dir/term-bad-$TERM
    [[ -f $ok ]] && return
    [[ -f $bad ]] && { export TERM='xterm-256color'; return }
    mkdir -p $dir 2> /dev/null
    if infocmp "$TERM" &> /dev/null; then
        : > $ok 2> /dev/null
    else
        : > $bad 2> /dev/null
        export TERM='xterm-256color'
    fi
}

# Deferred startup
#
# Everything that is not needed to draw the FIRST prompt runs after it is on
# screen. The mechanism is a pipe watched by zle: `zle -F` calls its handler
# only when the line editor is idle, which by definition is after the prompt has
# been drawn. A precmd hook cannot do this — precmd runs BEFORE the prompt, so
# work moved there delays exactly what it was meant to speed up.
typeset -ga _deferred
defer() { _deferred+=("${(j: :)@}") }
_defer_run() {
    emulate -L zsh
    zle -F $1 2>/dev/null          # unregister first: this must never run twice
    # NOTE: the braces matter. A bare `exec ... 2>/dev/null` applies the
    # redirection to the SHELL itself, permanently — every later error in the
    # interactive session goes to /dev/null. The group keeps it to this line.
    { exec {1}>&- } 2>/dev/null
    local cmd
    for cmd in $_deferred; do
        eval $cmd
    done
    _deferred=()
    # NOTE: the prompt on screen was drawn before any of this existed. Ask zle
    # to draw it again, or a prompt that depends on what just loaded stays stale
    # until the next command.
    zle reset-prompt 2>/dev/null
}
_defer_arm() {
    emulate -L zsh
    (( $#_deferred )) || return 0
    # Escape hatch, and the way the deferral is A/B tested: run the queue right
    # here and the shell behaves as it did before any of this existed.
    if [[ -n $ZSH_NO_DEFER ]]; then
        local cmd
        for cmd in $_deferred; do eval $cmd; done
        _deferred=()
        return 0
    fi
    local fd
    exec {fd}< <(:)                # readable immediately, so zle fires at once
    zle -F $fd _defer_run
}

# NOTE: defined FIRST, before anything can queue work. `defer _compinit_run`
# sits two hundred lines above where this block used to live, and zsh reported
# exactly that: "command not found: defer".

# External environment

# NOTE: never hardcode this — the repo is ~/.dotfiles on macOS and ~/dotfiles on
# Linux, and the `(N)` globs below skip missing paths without a word.
export DOTFILES_DIR="${HOME}/.dotfiles"
[[ ! -d "$DOTFILES_DIR" ]] && export DOTFILES_DIR="${HOME}/dotfiles"

# NOTE: whitelist, not `set -a` — that exported every token in .env into every
# child process. Anything not listed here stays a shell variable, so a new .env
# entry does not leak by default.
# NOTE: two possible homes. On the mac the file is the repo's own .env; in a
# container it is delivered by `dp secrets` as a 0600 file, because the devpod
# --workspace-env-file route wrote the same values into /etc/envfile.json with
# mode 644, where every process in the container could read them.
() {
    local f
    for f in "$HOME/.config/dp/work.env" "$DOTFILES_DIR/.env"; do
        [[ -r $f ]] && { typeset -g _DP_ENV_FILE=$f; return }
    done
}
if [[ -n $_DP_ENV_FILE ]]; then
    source "$_DP_ENV_FILE"
    () {
        local -a keep=(JIRA_URL JIRA_USERNAME JIRA_API_TOKEN TIMING_MCP_URL GITLAB_TOKEN)
        local -a found=()
        local line v
        # Parsed by hand rather than with sed: BSD and GNU differ in BRE.
        while IFS= read -r line || [[ -n $line ]]; do
            [[ $line =~ '^[[:space:]]*(export[[:space:]]+)?([A-Za-z_][A-Za-z0-9_]*)=' ]] \
                && found+=("$match[2]")
        done < "$_DP_ENV_FILE"
        for v in $found; do
            (( ${keep[(Ie)$v]} )) || typeset +x "$v" 2> /dev/null
        done
        for v in $keep; do
            [[ -n ${(P)v} ]] && export "$v"
        done
    }
fi

# Linux containers have no Keychain, so they authenticate with a long-lived
# OAuth token written at workspace creation. The file never exists on the mac.
if [[ -r "$HOME/.config/claude/token" ]]; then
    export CLAUDE_CODE_OAUTH_TOKEN="$(<"$HOME/.config/claude/token")"
fi

if [[ -r "$HOME/.atuin/bin/env" ]]; then
    source "$HOME/.atuin/bin/env"
fi

# SSH agent forwarding across a tmux reattach

# NOTE: mkdir before ln — in a container ~/.ssh may not exist at all now that
# github's keys are baked into /etc/ssh/ssh_known_hosts and nothing creates the
# directory.
if [[ -n "$SSH_AUTH_SOCK" && "$SSH_AUTH_SOCK" != "$HOME/.ssh/ssh_auth_sock" ]]; then
    mkdir -p -m 700 "$HOME/.ssh"
    ln -sf "$SSH_AUTH_SOCK" "$HOME/.ssh/ssh_auth_sock"
fi
# NOTE: export only when the socket is alive; unconditionally it pointed at last
# session's dead symlink and ssh reported a connection error instead of "no
# agent".
[[ -S "$HOME/.ssh/ssh_auth_sock" ]] && export SSH_AUTH_SOCK="$HOME/.ssh/ssh_auth_sock"

# zsh options

set -o vi
KEYTIMEOUT=1 # default 40 = 0.4s of lag on every Esc

# Cursor shape as the mode indicator: block for normal, bar for insert.
_cursor_shape() { case $KEYMAP in vicmd) print -n '\e[2 q';; *) print -n '\e[6 q';; esac }
zle -N zle-keymap-select _cursor_shape
zle -N zle-line-init     _cursor_shape

HISTFILE=~/.zsh_history
HISTSIZE=100000
SAVEHIST=100000

setopt EXTENDED_HISTORY     # timestamps cannot be reconstructed afterwards
setopt HIST_IGNORE_SPACE
setopt HIST_IGNORE_DUPS
setopt HIST_IGNORE_ALL_DUPS
setopt HIST_SAVE_NO_DUPS
setopt HIST_FIND_NO_DUPS
setopt HIST_VERIFY          # show !! and !$ in the line instead of running them
setopt SHARE_HISTORY
# NOTE: set here because we now skip the system /etc/zshrc, which used to set it.
# With SHARE_HISTORY every shell rewrites the file constantly; fcntl locking is
# what keeps a dozen of them from corrupting each other's entries, and the
# lock-file fallback is the weaker option.
setopt HIST_FCNTL_LOCK

# Completion system

# NOTE: dedupe before touching fpath. nix-darwin's /etc/zshenv re-runs
# set-environment for every zsh process, so fpath arrives with 62 entries for 25
# unique directories and compinit walks every duplicate.
typeset -U path fpath

# Cache only — no hand-written completions are kept in the repo any more.
fpath=("${XDG_CACHE_HOME:-$HOME/.cache}/zsh/completions" $fpath)

# NOTE: nobody else adds these. On Linux there is no nix-darwin, so without this
# line nix-package completions were missing entirely; zinit adds its own
# directory 150 lines below, i.e. after compinit.
() {
    local d
    for d in "$HOME/.nix-profile/share/zsh/site-functions" \
             "$HOME/.nix-profile/share/zsh/vendor-completions" \
             "${XDG_DATA_HOME:-$HOME/.local/share}/zinit/completions"; do
        [[ -d $d ]] && fpath=("$d" $fpath)
    done
}

# Generate CLI completions into the cache when missing.
# NOTE: count files before and after — with -C compinit reads the dump instead
# of fpath and would not see a freshly created _tool for up to a day.
typeset -g _comp_fresh=0
() {
    local cdir="${XDG_CACHE_HOME:-$HOME/.cache}/zsh/completions"
    mkdir -p "$cdir"
    local -a before=("$cdir"/_*(N))
    local tool
    for tool in kubectl helm talosctl k9s devpod docker; do
        (($+commands[$tool])) && [[ ! -f "$cdir/_$tool" ]] && "$tool" completion zsh > "$cdir/_$tool" 2> /dev/null
    done
    # cobra CLIs need -s
    for tool in gh glab; do
        (($+commands[$tool])) && [[ ! -f "$cdir/_$tool" ]] && "$tool" completion -s zsh > "$cdir/_$tool" 2> /dev/null
    done
    # atuin has its own syntax
    (($+commands[atuin])) && [[ ! -f "$cdir/_atuin" ]] && atuin gen-completions --shell zsh > "$cdir/_atuin" 2> /dev/null
    # clap style
    for tool in uv uvx; do
        (($+commands[$tool])) && [[ ! -f "$cdir/_$tool" ]] && "$tool" --generate-shell-completion zsh > "$cdir/_$tool" 2> /dev/null
    done
    local -a after=("$cdir"/_*(N))
    (( $#after != $#before )) && _comp_fresh=1
}

autoload -Uz compinit
# NOTE: deferred, and FIRST in the queue. Everything else that touches
# completions — the zinit completions plugin, bashcompinit, terraform,
# argcomplete — is queued behind it, because they add to fpath or wrap
# `complete`, and both only mean anything once compinit has run.
# Cost of deferring: Tab does nothing for the few ms between the prompt
# appearing and this running.
# NOTE: the anonymous function is not cosmetic — `(#q...)` needs EXTENDED_GLOB,
# which zinit only enables three hundred lines below. Without it the cache
# branch was unreachable and every start paid a full compinit: 1.45s against
# 0.13s.
_compinit_run() {
    setopt local_options extended_glob
    # NOTE: our OWN dump file. Debian's /etc/zsh/zshrc runs a global compinit
    # before ~/.zshrc and rewrites the shared ~/.zcompdump on every start, so
    # the age check never fired and `rm ~/.zcompdump` changed nothing.
    local dump="${ZDOTDIR:-$HOME}/.zcompdump-${ZSH_VERSION}"
    # NOTE: the glob is assigned to an array on purpose. Inside [[ ]] it expands
    # before the expression is parsed, and with zero matches `-n` is left
    # without an operand — the condition is then false ALWAYS, including when
    # the left side of || is true.
    local -a stale=($dump(#qN.mh+24))
    if [[ ! -f $dump ]] || (( $#stale )) || (( _comp_fresh )); then
        compinit -d "$dump"     # missing / older than a day / a new file appeared
    else
        compinit -C -d "$dump"
    fi
}
defer _compinit_run
unset _comp_fresh

# Navigation

alias ..='cd ..'
alias ...='cd ../..'
alias ....='cd ../../..'
alias .....='cd ../../../..'
alias sz='source ~/.zshrc'

alias v='nvim'
alias b='btop'

alias c='clear'
alias e='exit'

alias ls='eza'
alias la='eza -laghm --all --icons --git --color=always'
alias lt='eza --tree --level=2 --icons'

alias grep='grep --color=auto'
alias diff='diff --color=auto'
alias less='less -R'
# NOTE: the alias covers only a hand-typed less; git, man and kubectl start
# their own pager and need the same flags through the variable.
export LESS='-R -F -X -i'
export LESSHISTFILE=/dev/null

# df and du are deliberately not aliased: hiding flags misleads when
# machine-readable output is needed.

alias psa='source .venv/bin/activate'

# git / GitHub / GitLab

alias gc='git clone'
alias gs='git status'
alias gp='git pull'
# NOTE: reset --hard discards uncommitted work — that is the point of the alias
# ("force from the cloud"), but check git status first.
alias dfu='(cd "$DOTFILES_DIR" && git fetch origin && git reset --hard @{u}) && echo "✓ Dotfiles updated" || echo "✗ Failed to update dotfiles"'

alias gha='gh run list'
alias ghaw='gh run watch'
alias ghav='gh run view'
alias ghar='gh run rerun'
alias gharf='gh run rerun --failed'

alias ghrv='gh repo view --web'

# Docker

alias dc='docker compose'
alias lzd='lazydocker'

# DevPod

# NOTE: `devpod ssh` tunnels the caller's SSH_AUTH_SOCK itself and never reads
# the `Host *.devpod` IdentityAgent, so without this wrapper the full main agent
# goes into the container.
devpod() {
    local sock="$HOME/.local/state/ssh-agents/devpod.sock"
    if [[ -S "$sock" ]]; then
        SSH_AUTH_SOCK="$sock" command devpod "$@"
    else
        # NOTE: warn instead of falling through silently — a dead launchd agent
        # once cost a whole `devpod up`, reported only as a bare git exit 128.
        if [[ "$OSTYPE" == darwin* ]]; then
            local label="org.nixos.ssh-devpod-agent"
            print -u2 "devpod: dedicated agent socket is down, container gets the main agent instead"
            print -u2 "  restart: launchctl bootout gui/\$UID/$label; launchctl bootstrap gui/\$UID ~/Library/LaunchAgents/$label.plist"
        fi
        command devpod "$@"
    fi
}

# Kubernetes

alias k='kubectl'
alias kgp='kubectl get pods'
alias kgs='kubectl get svc'
alias kl='kubectl logs -f'
alias kctx='kubectl config use-context'
alias kns='kubectl config set-context --current --namespace'

# tmux

alias t='tmux'
alias ta='tmux attach'
alias tl='tmux list-sessions'
alias tks='tmux kill-server'

tw() {
    local count="${1:-3}"
    local name="${2:-$(basename "$PWD")}"
    name="${name#.}"
    name="${name//./-}"
    tmux new-session -d -s "$name" -c "$PWD"
    for i in $(seq 2 "$count"); do
        tmux new-window -t "${name}:" -c "$PWD"
    done
    tmux select-window -t "${name}:1"
    if [[ -n "$TMUX" ]]; then
        tmux switch-client -t "$name"
    else
        tmux attach -t "$name"
    fi
}

t3() { tw 3 "$1"; }
t6() { tw 6 "$1"; }

tn() {
    local name="${1:-$(basename "$PWD")}"
    name="${name#.}"
    name="${name//./-}"
    tmux new-session -d -s "$name" -c "$PWD"
    tmux new-window -t "${name}:" -c "$PWD"
    tmux new-window -t "${name}:" -c "$PWD"
    local lock_count
    lock_count=$(find ~/.claude/ide -maxdepth 1 -name '*.lock' 2> /dev/null | wc -l)
    tmux send-keys -t "${name}:1" 'nvim' C-m
    tmux send-keys -t "${name}:2" "while [ \$(find ~/.claude/ide -maxdepth 1 -name '*.lock' 2>/dev/null | wc -l) -le $lock_count ]; do sleep 0.3; done && cl" C-m
    tmux select-window -t "${name}:1"
    if [[ -n "$TMUX" ]]; then
        tmux switch-client -t "$name"
        tmux refresh-client -S
    else
        tmux attach -t "$name"
    fi
}

# Plugin manager

ZINIT_HOME="${XDG_DATA_HOME:-${HOME}/.local/share}/zinit/zinit.git"

if [[ ! -d $ZINIT_HOME ]]; then
    mkdir -p "$(dirname $ZINIT_HOME)"
    git clone https://github.com/zdharma-continuum/zinit.git "$ZINIT_HOME"
fi

export ZSH_AUTOSUGGEST_HIGHLIGHT_STYLE="fg=#586e75" # solarized base01

# NOTE: zinit itself is deferred, not just its plugins. The plugins already had
# `wait lucid`, so they loaded after the first prompt — but sourcing the manager
# that schedules them cost 33 ms BEFORE it. Now nothing of this touches the
# first prompt; `wait lucid` still applies once zinit is up.
_zinit_load() {
    if [[ ! -d $ZINIT_HOME ]]; then
        mkdir -p "$(dirname $ZINIT_HOME)"
        git clone https://github.com/zdharma-continuum/zinit.git "$ZINIT_HOME"
    fi
    source "${ZINIT_HOME}/zinit.zsh"

    # NOTE: no `wait lucid` any more. Turbo defers a plugin until the next
    # precmd — which made sense when zinit was sourced at file scope, but this
    # whole function already runs after the first prompt. Kept together the two
    # delays stack: the plugins then waited for the next precmd, i.e. until
    # after the first command was run, and a fresh shell had no autosuggestions
    # at all until you typed something. Reported as "new session does not
    # suggest, old one does".
    zinit light zsh-users/zsh-completions
    zinit light zsh-users/zsh-autosuggestions
    zinit light zdharma-continuum/fast-syntax-highlighting
    zinit light hlissner/zsh-autopair

    # autosuggestions hooks itself on precmd; we are past the first one, so it
    # needs the explicit start it used to get from the `atload` ice.
    (( $+functions[_zsh_autosuggest_start] )) && _zsh_autosuggest_start
}
defer _zinit_load

# conf.d modules

# NOTE: one pass, and private/ must follow it. Alias substitution inside a
# function body happens when the function is PARSED, so the dpl/dpf aliases from
# conf.d/devpod.zsh have to exist before private/zsh/work-stack.sh is sourced.
# Function-to-function calls do not care about order. Platform files decide for
# themselves whether to load.
for f in "$DOTFILES_DIR/tools/zsh/conf.d/"*.zsh(N); do source "$f"; done

for f in "$DOTFILES_DIR/private/zsh/"*.sh(N); do source "$f"; done

autoload -Uz _zinit
((${+_comps})) && _comps[zinit]=_zinit

# External tool integrations

# Each of these tools prints a shell script and we eval it. Printing it costs a
# process spawn per shell — measured 17 ms for starship, 42 for atuin, 26 for
# direnv — and a terminal tab that opens once an hour never gets those cheap.
# So the script is generated once into the cache and sourced from there, and
# regenerated only when the binary itself is newer.
# NOTE: safe to cache — nothing in the output is baked at generation time. The
# two lines that looked per-run (atuin's ATUIN_SESSION, starship's
# STARSHIP_SESSION_KEY) are code that runs when the script is SOURCED, so every
# shell still gets its own value.
_init_cached() {
    emulate -L zsh
    # NOTE: and then turn LOCAL_OPTIONS back off before sourcing. `emulate -L`
    # implies it, so every `setopt` the sourced script runs would be undone the
    # moment this function returns — starship sets PROMPT_SUBST, and without it
    # the prompt printed its own `$(starship prompt …)` as literal text.
    unsetopt local_options
    local tool=$1; shift
    (( $+commands[$tool] )) || return 0
    local file="${XDG_CACHE_HOME:-$HOME/.cache}/zsh/init-${tool}.zsh"
    if [[ ! -s $file || ${commands[$tool]} -nt $file ]]; then
        mkdir -p "${file:h}"
        "$@" > "$file.new" 2>/dev/null && mv -f "$file.new" "$file" || {
            rm -f "$file.new"
            eval "$("$@")"      # cache unusable: fall back to the old way
            return 0
        }
    fi
    source "$file"
}

_init_cached starship starship init zsh

# fzf is configured here but NOT wired into zle — see the note further down.
# Its only callers are the pickers in conf.d, which pipe their own rows in.
if (($+commands[fzf])); then
    # NOTE: DEFAULT_COMMAND only matters when fzf is started with no input on
    # stdin. The CTRL_T and ALT_C variants went with the widgets that used them.
    (($+commands[fd])) && export FZF_DEFAULT_COMMAND='fd --type f --hidden --follow --exclude .git'
    # --color=base16 keeps the parts nobody tunes (info, spinner, prompt) on the
    # terminal palette. The keys that carry the theme are set in hex by the
    # wrapper below, and deliberately NOT by index: in Solarized the ANSI 0-15
    # map is IDENTICAL in light and dark, so an index cannot express "lighter in
    # the light theme". Worse, ghostty's iTerm2 preset puts #bbb5a2 at index 7,
    # far darker than Solarized's own base2 — the selection bar came out a grey
    # slab. The hex values below are the ones nvim already uses, so a picker and
    # an editor buffer highlight the current line identically.
    # NOTE: --gutter=' ' erases the column of '▌' fzf draws down the left edge
    # (its default gutter character) in the same tone as the text.
    # NOTE: minimal plus ONE border, not the `full` preset — full frames every
    # section separately (input, header, list), which is six rows of chrome
    # around three rows of content. --style must stay ahead of --border and
    # --info here: a preset resets them, so it would undo both.
    # NOTE: horizontal, i.e. no side rails, because with them fzf draws every
    # section rule one column PAST the right inner padding — measured at 1 left
    # against 0 right, the same for --header-border, --list-border=top and
    # --input-border=bottom, and --padding only shifts the pair. Without the
    # side rails there is no right edge to be short of, and the gap between the
    # frame and the text goes with it.
    # NOTE: `~` makes the height a ceiling instead of a constant — the window
    # grows with the list. The ceiling is in ROWS, not per cent: 40% of a tall
    # terminal is a wall of empty frame, and the useful size of a picker does
    # not depend on how big the window happens to be.
    # NOTE: --header-border=bottom is the one rule inside the frame — without it
    # the header runs straight into the first item.
    # NOTE: kept as the base so the theme can be re-applied on top of it
    # without stacking; _fzf_theme_apply rebuilds FZF_DEFAULT_OPTS from here.
    typeset -g _FZF_BASE_OPTS='--height=~15 --layout=reverse --style=minimal --border=horizontal --header-border=bottom --color=base16,gutter:-1 --gutter=" " --info=inline-right --prompt="❯ " --pointer="▸" --marker="✓"'
    # NOTE: guard on -t 0, not `-o zle` — `fzf --zsh` has no guard of its own
    # and floods stderr in headless runs, while -i enables the zle option even
    # without a terminal.
    # NOTE: no `eval "$(fzf --zsh)"`. Those widgets — Ctrl-T, Ctrl-R, Alt-C —
    # went unused: history is atuin's and the pickers here feed fzf their own
    # input. It cost a process spawn per shell plus six bindkey lines whose only
    # job was to undo the bindings fzf had just made, and the ordering rule
    # "fzf strictly before atuin" existed for the same reason. All of it goes.

    # Which theme to paint the pickers in. 0 = dark, 1 = light.
    #
    # NOTE: asked of the OS or of an env var — NEVER of the terminal at startup.
    # The OSC 11 query below has to put the tty in raw mode and read it, and
    # anything typed before that read is swallowed. Measured with A/B runs:
    # characters typed 150 ms after a tmux window opened reached the prompt with
    # the probe disabled and vanished with it enabled. A shell must not touch
    # the terminal before its first prompt, however cheap the query looks.
    _term_bg_is_dark() {
        emulate -L zsh
        # An explicit answer wins: this is how a container learns the theme,
        # since it has no system setting to read.
        [[ -n $DP_TERM_BG ]] && { [[ $DP_TERM_BG == dark ]]; return }
        # NOTE: cached, because `defaults read` is not the 9 ms it measures as in
        # isolation — inside a real startup a trace put it at 31 ms, a third of
        # the whole pre-prompt path, for a value that changes twice a day. The
        # file is read in microseconds; one shell every five minutes pays the
        # process, and `term-theme` forces a refresh when the flip must be seen
        # at once.
        local cache=${XDG_CACHE_HOME:-$HOME/.cache}/zsh/term-bg
        local -a fresh=($cache(Nms-300))
        if (( $#fresh )); then
            [[ $(<$cache) == dark ]]
            return
        fi
        [[ $OSTYPE == darwin* ]] && {
            local bg=light
            [[ $(defaults read -g AppleInterfaceStyle 2>/dev/null) == Dark ]] && bg=dark
            mkdir -p ${cache:h} 2>/dev/null
            print -r -- $bg > $cache 2>/dev/null
            [[ $bg == dark ]]
            return
        }
        return 0    # container, nobody said otherwise: dark
    }

    # Ask the TERMINAL itself. This is the only thing that works where the OS
    # cannot answer — a container over ssh, where ghostty still replies through
    # tmux and the ssh channel (verified from inside a devcontainer).
    # NOTE: deliberately NOT called at startup; see the note above. Run it from
    # a prompt, where eating the input queue costs nothing because it is empty.
    _term_bg_probe() {
        emulate -L zsh
        local old reply
        # NOTE: the guard is opening /dev/tty, not `[[ -r /dev/tty ]]` — the
        # device node exists and is world-readable even for a process with no
        # controlling terminal, so only the open tells the truth. This is what
        # keeps headless runs from touching the terminal at all.
        # NOTE: the braces catch the SHELL's own complaint, not stty's. With no
        # controlling terminal the `< /dev/tty` redirection is what fails, and
        # zsh prints "device not configured" itself — a plain `2>/dev/null` on
        # the command silences the wrong process.
        { old=$(stty -g < /dev/tty) } 2>/dev/null || return 2
        {
            stty raw -echo < /dev/tty
            print -n '\e]11;?\e\\' > /dev/tty
            # NOTE: -d '\' stops at the ST terminator. Reading until the timeout
            # instead costs the whole 200 ms on every picker; this is ~8 ms.
            IFS= read -r -s -t 0.2 -d '\' reply < /dev/tty
            # NOTE: a late answer is worse than no answer — it is still queued
            # on the tty and the NEXT program reads it as typed input. Seen for
            # real: `11;rgb:fdfd/f6f6/e3e3` appeared in an fzf query line, since
            # tmux hands the reply to a pane that is not the active one only
            # when it gets around to it. So wait once more, and if it is still
            # not a colour, swallow whatever is queued before letting go of the
            # terminal.
            [[ $reply == *rgb:* ]] || IFS= read -r -s -t 0.3 -d '\' reply < /dev/tty
            if [[ $reply != *rgb:* ]]; then
                local junk
                while IFS= read -r -s -t 0.02 -k 1 junk < /dev/tty; do :; done
            fi
        } always {
            # a terminal left in raw mode is a dead shell — restore it even if
            # the read is interrupted
            stty "$old" < /dev/tty
        }
        [[ $reply == *rgb:* ]] || return 2
        local -a ch
        ch=(${(s:/:)${reply#*rgb:}})
        (( $#ch == 3 )) || return 2
        # rgb:RRRR/GGGG/BBBB — 16 bits per channel, the high byte decides
        local hex=${ch[1]:0:2}${ch[2]:0:2}${ch[3]:0:2}
        # NOTE: plain globs. `##` here would need EXTENDED_GLOB, which
        # `emulate -L zsh` does not set, and the pattern would quietly match
        # nothing at all.
        [[ $hex == ?????? && $hex != *[^0-9a-fA-F]* ]] || return 2
        local -i r=16#${hex:0:2} g=16#${hex:2:2} b=16#${hex:4:2}
        (( (r * 299 + g * 587 + b * 114) / 1000 < 128 ))
    }

    # Applied once at startup and again whenever `term-theme` is run. Per-fzf
    # -launch was the first design and it cost two defects: a late answer landed
    # in the next program's input, and holding the tty inside a pipeline stopped
    # whatever else was in it (`_dp_rows | fzf` died with "you have suspended
    # jobs"). Startup looked like the safe moment — it is not, it is the moment
    # typeahead exists. Hence: no terminal at startup at all.
    _fzf_theme_apply() {
        local theme rc
        _term_bg_is_dark; rc=$?
        if (( rc == 1 )); then
            # base2 over base3, the pair nvim uses for CursorLine in light mode
            # (colorscheme.lua: hl.CursorLine). The text keeps the normal
            # foreground exactly as it does there — the bar alone marks the
            # line, the pointer says which one. Matches in sol_blue, the theme's
            # own accent.
            theme='--color=border:#93a1a1,bg+:#eee8d5,fg+:#657b83,hl:#268bd2,hl+:#268bd2'
        else
            # dark: base02 over base03, the same pair on the other side, and the
            # values the indices resolved to before — this side already looked
            # right and is left alone.
            theme='--color=border:#335e69,bg+:#073642,fg+:#fdf6e3,hl+:#2aa198'
        fi
        # NOTE: rebuilt from the base, not appended to. `term-theme` calls this
        # again, and appending would stack a second --color onto the first.
        export FZF_DEFAULT_OPTS="$_FZF_BASE_OPTS $theme"
    }
    _fzf_theme_apply

    # Re-detect and repaint without restarting the shell. With no argument it
    # asks the terminal (the only source a container has); `term-theme light`
    # and `term-theme dark` set it outright.
    term-theme() {
        emulate -L zsh
        case $1 in
            light|dark) export DP_TERM_BG=$1 ;;
            '')  _term_bg_probe && export DP_TERM_BG=dark || export DP_TERM_BG=light ;;
            *)   print -u2 "term-theme: light | dark | (пусто — спросить терминал)"; return 1 ;;
        esac
        # NOTE: the cache is updated too, or every shell started in the next
        # five minutes would still read the old answer off disk.
        local cache=${XDG_CACHE_HOME:-$HOME/.cache}/zsh/term-bg
        mkdir -p ${cache:h} 2>/dev/null
        print -r -- $DP_TERM_BG > $cache 2>/dev/null
        _fzf_theme_apply
        print -r -- "theme: $DP_TERM_BG"
    }
fi

# NOTE: atuin is the heaviest of the three even from cache — it defines the
# widgets and spawns `atuin uuid` for the session id. Ctrl-R is unusable for the
# few milliseconds between the prompt appearing and this running.
# NOTE: the bindkey corrections MUST live in the same deferred unit, after the
# init. They exist to undo bindings atuin makes, so running them at file scope
# now — before atuin loads — would leave atuin's own bindings in place, which is
# how '?' turned into a blocking AI request and vi navigation lost k and /.
_atuin_setup() {
    _init_cached atuin atuin init zsh
    # '?' back to a plain character on an empty prompt
    bindkey -r '?' 2> /dev/null
    bindkey -M viins '?' self-insert 2> /dev/null
    # vicmd: stock widget names verified with `bindkey -M vicmd`
    # (up-line-or-history, not vi-up-line-or-history)
    bindkey -M vicmd 'k' up-line-or-history 2> /dev/null
    bindkey -M vicmd '/' vi-history-search-backward 2> /dev/null
    # Defined in conf.d/atuin.zsh, which is sourced long before this runs. It
    # lives there because containers run an older copy of THIS file, baked into
    # the image, while conf.d is read from the clone and arrives with a pull.
    _atuin_inline_height
}
defer _atuin_setup

# NOTE: deferred too. The hook fires on the NEXT prompt, so a directory with an
# .envrc entered in the very first prompt activates one prompt later.
defer _init_cached direnv direnv hook zsh

# bash-style completions. NOTE: deferred behind _compinit_run — `bashcompinit`
# and every `complete -C` below are meaningless until compinit has set the
# completion system up, and compinit no longer runs at file scope.
_bashcomp_init() {
    autoload -U +X bashcompinit && bashcompinit
    # dynamic path so it survives a nix update
    (($+commands[terraform])) && complete -o nospace -C "$(command -v terraform)" terraform

    # ansible via argcomplete, cached so python is not spawned on every start
    if (($+commands[register-python-argcomplete])); then
        local af="${XDG_CACHE_HOME:-$HOME/.cache}/zsh/completions/ansible-argcomplete.zsh"
        if [[ ! -f "$af" ]]; then
            local acmd
            for acmd in ansible ansible-playbook ansible-vault ansible-galaxy ansible-config ansible-doc ansible-inventory; do
                (($+commands[$acmd])) && register-python-argcomplete "$acmd"
            done > "$af" 2> /dev/null
        fi
        [[ -s "$af" ]] && source "$af"
    fi
}
defer _bashcomp_init

# Everything queued with `defer` runs from here, once the first prompt is on
# screen. Last line of the file on purpose: whatever is queued after this point
# would never be armed.
_defer_arm
