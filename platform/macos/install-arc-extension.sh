#!/usr/bin/env zsh

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../common.sh"

print_section "Installing Arc Extensions"

extensions=(
    "https://chromewebstore.google.com/detail/adblock-%E2%80%94-block-ads-acros/gighmmpiobklfepjocnamgkkbiglidom"
    "https://chromewebstore.google.com/detail/dark-reader/eimadpbcbfnmbkopoojfekhnkhdbieeh?hl=ru"
    "https://chromewebstore.google.com/detail/bitwarden-%D0%BC%D0%B5%D0%BD%D0%B5%D0%B4%D0%B6%D0%B5%D1%80-%D0%BF%D0%B0%D1%80%D0%BE%D0%BB%D0%B5/nngceckbapebfimnlniiiahkandclblb"
    "https://chromewebstore.google.com/detail/%D0%BF%D0%B0%D1%80%D0%BE%D0%BB%D0%B8-icloud/pejdijmoenmkgeppbflobdenhhabjlaj"
    "https://chromewebstore.google.com/detail/refined-github/hlepfoohegkhhmjieoechaddaejaokhf"
)

echo "Opening extension pages in Arc..."
for ext in "${extensions[@]}"; do
    open -a "Arc" "$ext"
    sleep 1
done

echo ""
echo "Please install each extension manually by clicking 'Add to Chrome'"
read "?Press Enter when all extensions are installed: "
