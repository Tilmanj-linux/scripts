#!/usr/bin/env bash
# package-diff.sh — track explicit-package drift vs a git-tracked manifest.
#   package-diff.sh           report new/removed since last bless
#   package-diff.sh --bless   set manifest = current state
set +e
M="$HOME/.config/package-manifest.txt"; A="$HOME/.config/package-manifest-aur.txt"
cur(){ pacman -Qe|sort; }; cur_aur(){ pacman -Qm|sort; }
if [ "$1" = "--bless" ]; then cur>"$M"; cur_aur>"$A"; echo "✓ blessed ($(wc -l<"$M") explicit, $(wc -l<"$A") AUR)"; echo "  commit: git -C ~/.config add package-manifest*.txt && git -C ~/.config commit -m 'bless packages'"; exit 0; fi
if [ ! -f "$M" ]; then cur>"$M"; cur_aur>"$A"; echo "✓ baseline created ($(wc -l<"$M") explicit, $(wc -l<"$A") AUR)"; echo "  commit: git -C ~/.config add package-manifest*.txt && git -C ~/.config commit -m 'init manifest'"; exit 0; fi
ADD=$(comm -23 <(cur|cut -d' ' -f1) <(cut -d' ' -f1 "$M")); GONE=$(comm -13 <(cur|cut -d' ' -f1) <(cut -d' ' -f1 "$M"))
echo "── package drift ──"
if [ -z "$ADD" ]&&[ -z "$GONE" ]; then echo "✓ no drift"; else [ -n "$ADD" ]&&{ echo "▌ NEW:"; echo "$ADD"|sed 's/^/  + /'; }; [ -n "$GONE" ]&&{ echo "▌ REMOVED:"; echo "$GONE"|sed 's/^/  - /'; }; echo "  bless if intentional: ~/scripts/package-diff.sh --bless"; fi
