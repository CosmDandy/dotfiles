# lazygit: switches the selection colour to match the terminal background. The base
# config.yml plus a theme-{light,dark}.yml overlay through --use-config-file; the
# background is detected by _term_is_light (OSC 11). Override with LG_THEME=light|dark.
lg() {
    local theme cfg="${XDG_CONFIG_HOME:-$HOME/.config}/lazygit"
    case "$LG_THEME" in
        light|dark) theme="$LG_THEME" ;;
        *)
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
            esac ;;
    esac
    command lazygit --use-config-file="$cfg/config.yml,$cfg/theme-$theme.yml" "$@"
}
