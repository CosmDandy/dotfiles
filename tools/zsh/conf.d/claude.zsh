# Claude Code — launch aliases and memory helpers. Identical on the mac and in containers.

# NOTE: the autocompact threshold IS in the env block of settings.json, but that is not
# enough: from there variables are handed to CHILD processes (Bash tools, hooks), while
# Claude Code itself reads the threshold from its own process.env — i.e. only what was in
# the environment at launch. A session started by the daemon inherits it; `claude` run by
# hand from a shell does not and falls back to "window − 13000" (~987K instead of 650K on
# a 1M window). Measured in one container: the daemon session compacted 4 times by 258K,
# the shell session reached 819K with no autocompact at all.
export CLAUDE_AUTOCOMPACT_PCT_OVERRIDE=65

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
