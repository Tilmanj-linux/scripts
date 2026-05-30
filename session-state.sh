#!/bin/bash
# session-state.sh — Quick state dump for pasting into a 30.01 Claude session
#
# Run:    ~/scripts/session-state.sh
# Usage:  Copy output, paste at session start
#
# This is the lightweight complement to system-snapshot.sh.
# Snapshot = full JSON to Google Drive (for Claude to read via tools).
# This = terminal output for quick paste when you just want to sync.

echo "=== LITTLEBEAR SESSION STATE $(date +%Y-%m-%d_%H%M%S) ==="
echo ""

# Kernel + compositor
echo "--- System ---"
echo "Kernel: $(uname -r)"
hyprctl version 2>/dev/null | head -1 || echo "Hyprland: not running"
nvidia-smi --query-gpu=driver_version,name --format=csv,noheader 2>/dev/null | \
    awk -F', ' '{print "GPU: " $2 " (driver " $1 ")"}'
echo ""

# Package changes since last snapshot
echo "--- Recent Package Activity ---"
# Last 20 install/upgrade/remove events from pacman log
grep -E '(installed|upgraded|removed)' /var/log/pacman.log 2>/dev/null | tail -20
echo ""

# Config file modification times (just the recent ones)
echo "--- Recently Modified Configs ---"
find ~/.config/hypr ~/.config/kitty ~/.config/waybar ~/.config/rofi ~/.config/dunst \
    -name "*.lua" -o -name "*.conf" -o -name "*.css" -o -name "*.jsonc" -o -name "*.rasi" -o -name "dunstrc" \
    2>/dev/null | xargs ls -lt 2>/dev/null | head -10
echo ""

# Monitors
echo "--- Monitors ---"
hyprctl monitors -j 2>/dev/null | python3 -c "
import sys, json
try:
    for m in json.load(sys.stdin):
        xform = {0:'normal',1:'90CW',2:'180',3:'270CW'}.get(m.get('transform',0), '?')
        print(f\"  {m['name']}: {m['width']}x{m['height']}@{m.get('refreshRate',0):.0f}Hz pos({m['x']},{m['y']}) {xform}\")
except: print('  (could not parse)')
" 2>/dev/null
echo ""

# Disk
echo "--- Storage ---"
df -h / /home /mnt/games 2>/dev/null | tail -n +2 | awk '{print "  " $6 ": " $3 "/" $2 " (" $5 " used)"}'
echo ""

# Config errors
echo "--- Config Errors ---"
hyprctl configerrors 2>/dev/null || echo "  (hyprctl not available)"
echo ""

# Stale file check
echo "--- Stale File Check ---"
for f in ~/.config/hypr/core/hyprland.lua ~/.config/hypr/hyprland.conf.bak; do
    if [ -f "$f" ]; then
        echo "  ⚠ EXISTS (delete): $f"
    fi
done
echo "  (clean if no warnings above)"
echo ""
echo "=== END STATE ==="
