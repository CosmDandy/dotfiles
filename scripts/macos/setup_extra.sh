SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"

print_section "Installing apps"
links=(
    "https://appstorrent.ru/3019-screen-studio.html"
    "https://appstorrent.ru/672-cleanshot-x.html"
    "https://appstorrent.ru/1938-istatistica-pro.html"
    "https://appstorrent.ru/1789-network-radar.html"
    "https://appstorrent.ru/162-transmit.html"
    "https://appstorrent.ru/42-things-3.html"
    "https://appstorrent.ru/423-kaleidoscope.html"
    "https://appstorrent.ru/3647-superwhisper.html"
    "https://appstorrent.ru/48-final-cut-pro.html"
    "https://appstorrent.ru/87-capture-one.html"
)

for link in "${links[@]}"; do
    print_section "Opening: $link"
    open "$link"
    sleep 1
done
