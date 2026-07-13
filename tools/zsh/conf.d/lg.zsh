# lazygit: авто-переключение цвета выделения под фон терминала.
# Базовый config.yml + оверлей theme-{light,dark}.yml (только selectedLineBgColor) через
# --use-config-file. Фон определяет _term_is_light (OSC 11). Override: LG_THEME=light|dark
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
