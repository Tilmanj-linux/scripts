#!/usr/bin/env bash
# #59 — one-shot network health check. Auto-detects gateway + rclone remote.
source ~/scripts/lib/colors.sh 2>/dev/null || { C_OK=""; C_ERR=""; C_WARN=""; C_DIM=""; C_RESET=""; C_BOLD=""; }
ok(){   echo -e "${C_OK}✓${C_RESET} $1"; }
bad(){  echo -e "${C_ERR}✗${C_RESET} $1"; }
warn(){ echo -e "${C_WARN}!${C_RESET} $1"; }

echo -e "${C_BOLD}── net-check ──${C_RESET}"

dev=$(nmcli -t -f DEVICE,STATE device status | awk -F: '$2=="connected"{print $1; exit}')
[ -n "$dev" ] && ok "interface up: $dev" || bad "no connected interface"

gw=$(ip route | awk '/^default/{print $3; exit}')
if [ -n "$gw" ] && ping -c1 -W2 "$gw" >/dev/null 2>&1; then ok "gateway reachable: $gw"
else bad "gateway unreachable (${gw:-none})"; fi

ping -c1 -W2 1.1.1.1 >/dev/null 2>&1 && ok "internet (1.1.1.1)" || bad "no internet"
ping -c1 -W2 cloudflare.com >/dev/null 2>&1 && ok "DNS resolving" || warn "DNS not resolving"

remote=$(rclone listremotes 2>/dev/null | head -1)
if [ -z "$remote" ]; then warn "no rclone remote configured"
elif rclone lsd "$remote" --max-depth 1 --timeout 8s --low-level-retries 1 >/dev/null 2>&1; then ok "rclone remote ok: $remote"
else bad "rclone remote unreachable: $remote"; fi

mountpoint -q ~/Drive && ok "~/Drive mounted" || warn "~/Drive not mounted"
