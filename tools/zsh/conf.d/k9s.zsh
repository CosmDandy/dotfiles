# k9s: switches the Solarized skin to match the terminal background, detected by
# _term_is_light (OSC 11). config.yaml keeps `skin: solarized`, and the wrapper repoints
# the solarized.yaml symlink at the dark or light file.
# Override: K9S_THEME=light|dark
k9s() {
    local theme skindir="${XDG_CONFIG_HOME:-$HOME/.config}/k9s/skins"
    case "$K9S_THEME" in
        light|dark) theme="$K9S_THEME" ;;
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
    ln -sf "solarized-${theme}.yaml" "$skindir/solarized.yaml" 2>/dev/null
    command k9s "$@"
}
