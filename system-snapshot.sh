#!/bin/bash
# system-snapshot.sh — Littlebear state collector
#
# Usage:
#   system-snapshot.sh full          Full dump, all modules (startup/exit)
#   system-snapshot.sh pulse         Pruned subset for paste (quick check)
#   system-snapshot.sh <module>      Single module (targeted)
#   system-snapshot.sh               Defaults to 'full'
#
# Modules:
#   meta, gpu, storage, monitors, packages, configs,
#   services, env, mounts, stale, errors, processes
#
# Output:
#   full   → ~/Drive/system-state/snapshot-YYYY-MM-DD.json + latest.json
#   pulse  → stdout (paste into chat)
#   module → stdout

set -euo pipefail

COMMAND="${1:-full}"
if mountpoint -q "$HOME/Drive"; then
    OUT_DIR="$HOME/Drive/system-state"
else
    OUT_DIR="$HOME/.local/state/littlebear-snapshots"
    echo "  ⚠ ~/Drive not mounted — snapshot → local, mount point left clean" >&2
fi
DATE=$(date +%Y-%m-%d_%H%M%S)
OUTFILE="$OUT_DIR/snapshot-$DATE.json"

# ── Collector: runs Python with requested modules ──
collect() {
    local mode="$1"
    local target="${2:-stdout}"

    python3 - "$mode" "$target" << 'PYEOF'
import subprocess, json, os, hashlib, sys, platform
from datetime import datetime

MODE = sys.argv[1]       # full | pulse | <module_name>
TARGET = sys.argv[2]     # filepath | stdout

# ── Helpers ──

def cmd(args, fallback=""):
    try:
        r = subprocess.run(args, capture_output=True, text=True, timeout=10)
        return r.stdout.strip()
    except:
        return fallback

def cmd_json(args, fallback=None):
    try:
        r = subprocess.run(args, capture_output=True, text=True, timeout=10)
        return json.loads(r.stdout)
    except:
        return fallback or []

# ── Modules ──
# Each returns a dict. Add new modules here + register in MODULE_MAP below.

def mod_meta():
    hypr_ver = ""
    for line in cmd(["pacman", "-Q", "hyprland"]).split("\n"):
        parts = line.split()
        if len(parts) >= 2 and parts[0] == "hyprland":
            hypr_ver = parts[1]
    return {
        "timestamp": datetime.now().astimezone().isoformat(),
        "hostname": platform.node(),
        "user": os.environ.get("USER", "unknown"),
        "kernel": platform.release(),
        "compositor": f"hyprland {hypr_ver}",
        "snapshot_version": "2.0",
        "command": MODE,
    }

def mod_gpu():
    nvsmi = cmd(["nvidia-smi",
        "--query-gpu=driver_version,name,memory.total,temperature.gpu,power.draw",
        "--format=csv,noheader,nounits"])
    if not nvsmi:
        return {}
    parts = [p.strip() for p in nvsmi.split(",")]
    return {"driver": parts[0], "name": parts[1], "vram_mb": parts[2],
            "temp_c": parts[3], "power_w": parts[4]}

def mod_storage():
    devices = cmd_json(["lsblk", "-Jpo", "NAME,SIZE,FSTYPE,MOUNTPOINT,MODEL"])
    usage = []
    df_out = cmd(["df", "-BG", "--output=target,size,used,avail,pcent", "/", "/home"])
    if df_out:
        for line in df_out.strip().split("\n")[1:]:
            parts = line.split()
            if len(parts) >= 5:
                usage.append({"mount": parts[0], "size": parts[1],
                              "used": parts[2], "avail": parts[3], "pct": parts[4]})
    return {"devices": devices, "usage": usage}

def mod_monitors():
    """Full monitor data from hyprctl."""
    return cmd_json(["hyprctl", "monitors", "-j"])

def mod_monitors_pruned():
    """Monitors with debug/mode noise stripped."""
    raw = cmd_json(["hyprctl", "monitors", "-j"])
    pruned = []
    drop_keys = {"availableModes", "solitaryBlockedBy", "tearingBlockedBy",
                 "directScanoutBlockedBy", "directScanoutTo", "colorManagementPreset",
                 "sdrBrightness", "sdrSaturation", "sdrMinLuminance", "sdrMaxLuminance",
                 "activelyTearing", "solitary", "currentFormat", "mirrorOf",
                 "physicalWidth", "physicalHeight"}
    for m in raw:
        pruned.append({k: v for k, v in m.items() if k not in drop_keys})
    return pruned

def mod_packages():
    """All explicit packages with source."""
    explicit = cmd(["pacman", "-Qe"]).split("\n")
    foreign = set(cmd(["pacman", "-Qm"]).split("\n"))
    pkgs = []
    for line in explicit:
        if not line.strip():
            continue
        parts = line.split()
        pkgs.append({"name": parts[0],
                     "version": parts[1] if len(parts) > 1 else "",
                     "source": "AUR" if line in foreign else "repo"})
    return pkgs

def mod_packages_summary():
    """Package count + AUR list only."""
    explicit = cmd(["pacman", "-Qe"]).split("\n")
    foreign = [l.split()[0] for l in cmd(["pacman", "-Qm"]).split("\n") if l.strip()]
    return {"total_explicit": len([l for l in explicit if l.strip()]),
            "aur": foreign}

def mod_configs():
    config_paths = [
        "~/.config/hypr/hyprland.lua",
        "~/.config/hypr/core/env.lua",
        "~/.config/hypr/core/monitors.lua",
        "~/.config/hypr/core/workspaces.lua",
        "~/.config/hypr/core/appearance.lua",
        "~/.config/hypr/core/autostart.lua",
        "~/.config/hypr/core/binds.lua",
        "~/.config/hypr/core/rules.lua",
        "~/.config/hypr/core/animations.lua",
        "~/.config/hypr/scripts/close-at-cursor.sh",
        "~/.config/hypr/scripts/wallpaper-cycle.sh",
        "~/.config/nvim/init.lua",
        "~/.config/kitty/kitty.conf",
        "~/.config/gtk-3.0/bookmarks",
        "~/.config/hypr/hyprlock.conf",
        "~/.config/hypr/hypridle.conf",
        "~/.config/waybar/config.jsonc",
        "~/.config/waybar/style.css",
        "~/.config/rofi/config.rasi",
        "~/.config/dunst/dunstrc",
    ]
    configs = []
    for cfg in config_paths:
        path = os.path.expanduser(cfg)
        if os.path.exists(path):
            with open(path, "rb") as f:
                sha = hashlib.sha256(f.read()).hexdigest()[:8]
            configs.append({"path": cfg, "exists": True, "sha256_short": sha,
                            "modified": datetime.fromtimestamp(os.path.getmtime(path)).isoformat(),
                            "size_bytes": os.path.getsize(path)})
        else:
            configs.append({"path": cfg, "exists": False})
    return configs

def mod_configs_hashes():
    """Hash-only view for drift detection."""
    full = mod_configs()
    return [{"path": c["path"],
             "sha256_short": c.get("sha256_short", "—"),
             "exists": c["exists"]}
            for c in full]

def mod_services():
    raw = cmd(["systemctl", "--user", "list-units", "--state=running",
               "--type=service", "--no-legend", "--no-pager"])
    return [line.split()[0] for line in raw.split("\n") if line.strip()]

def mod_env():
    """Capture key environment variables that affect GPU/display behavior."""
    keys = [
        "LIBVA_DRIVER_NAME", "__GLX_VENDOR_LIBRARY_NAME",
        "XCURSOR_THEME", "XCURSOR_SIZE",
        "ELECTRON_OZONE_PLATFORM_HINT",
        "XDG_SESSION_TYPE", "XDG_CURRENT_DESKTOP",
        "WAYLAND_DISPLAY", "DISPLAY",
        "GBM_BACKEND", "WLR_NO_HARDWARE_CURSORS",
        "MOZ_ENABLE_WAYLAND",
    ]
    return {k: os.environ.get(k, "(unset)") for k in keys}

def mod_mounts():
    """Check key mount points."""
    checks = [
        ("~/Drive", os.path.expanduser("~/Drive")),
        ("/mnt/games", "/mnt/games"),
    ]
    results = []
    for label, path in checks:
        is_mount = os.path.ismount(path)
        exists = os.path.exists(path)
        results.append({"path": label, "exists": exists, "mounted": is_mount})
    return results

def mod_stale():
    known_stale = [
        "~/.config/hypr/core/hyprland.lua",
        "~/.config/hypr/hyprland.conf.bak",
    ]
    results = []
    for f in known_stale:
        path = os.path.expanduser(f)
        exists = os.path.exists(path)
        results.append({"path": f, "exists": exists,
                        "action": "DELETE" if exists else "clean"})
    return results

def mod_errors():
    return cmd(["hyprctl", "configerrors"])

def mod_processes():
    """Check if expected autostart processes are running."""
    expected = ["waybar", "hypridle", "dunst", "awww-daemon"]
    results = {}
    for proc in expected:
        r = cmd(["pgrep", "-x", proc])
        results[proc] = {"running": bool(r), "pid": r if r else None}
    return results

def mod_input_devices():
    """Input devices from hyprctl."""
    return cmd_json(["hyprctl", "devices", "-j"])

# ── Module registry ──

MODULE_MAP = {
    "meta":       mod_meta,
    "gpu":        mod_gpu,
    "storage":    mod_storage,
    "monitors":   mod_monitors,
    "packages":   mod_packages,
    "configs":    mod_configs,
    "services":   mod_services,
    "env":        mod_env,
    "mounts":     mod_mounts,
    "stale":      mod_stale,
    "errors":     mod_errors,
    "processes":  mod_processes,
    "input_devices": mod_input_devices,
}

# ── Composition ──

FULL_MODULES = [
    ("meta",       mod_meta),
    ("gpu",        mod_gpu),
    ("storage",    mod_storage),
    ("monitors",   mod_monitors),
    ("packages",   mod_packages),
    ("configs",    mod_configs),
    ("services",   mod_services),
    ("env",        mod_env),
    ("mounts",     mod_mounts),
    ("stale",      mod_stale),
    ("config_errors", mod_errors),
    ("processes",  mod_processes),
    ("input_devices", mod_input_devices),
]

# [UNDER CONSTRUCTION] Pulse composition — curated + pruned
PULSE_MODULES = [
    ("meta",           mod_meta),
    ("gpu",            mod_gpu),
    ("monitors",       mod_monitors_pruned),
    ("packages",       mod_packages_summary),
    ("configs",        mod_configs_hashes),
    ("mounts",         mod_mounts),
    ("config_errors",  mod_errors),
    ("processes",      mod_processes),
]

def build_snapshot(module_list):
    snapshot = {}
    for key, func in module_list:
        try:
            snapshot[key] = func()
        except Exception as e:
            snapshot[key] = {"error": str(e)}
    return snapshot

# ── Dispatch ──

if MODE == "full":
    snapshot = build_snapshot(FULL_MODULES)
elif MODE == "pulse":
    snapshot = build_snapshot(PULSE_MODULES)
elif MODE in MODULE_MAP:
    snapshot = {MODE: MODULE_MAP[MODE]()}
else:
    print(f"Unknown command: {MODE}", file=sys.stderr)
    print(f"Available: full, pulse, {', '.join(MODULE_MAP.keys())}", file=sys.stderr)
    sys.exit(1)

# ── Output ──

output = json.dumps(snapshot, indent=2)

if TARGET != "stdout":
    os.makedirs(os.path.dirname(TARGET), exist_ok=True)
    with open(TARGET, "w") as f:
        f.write(output)
else:
    print(output)

# ── Summary (stderr so it doesn't pollute JSON on stdout) ──

meta = snapshot.get("meta", {})
pkgs = snapshot.get("packages", {})
cfgs = snapshot.get("configs", [])
stale_list = snapshot.get("stale", [])
svcs = snapshot.get("services", [])
errs = snapshot.get("config_errors", "")
procs = snapshot.get("processes", {})

lines = [f"  Mode: {MODE}"]

if isinstance(pkgs, list):
    lines.append(f"  Packages (explicit): {len(pkgs)}")
elif isinstance(pkgs, dict) and "total_explicit" in pkgs:
    lines.append(f"  Packages (explicit): {pkgs['total_explicit']}, AUR: {len(pkgs.get('aur', []))}")

if isinstance(cfgs, list):
    found = len([c for c in cfgs if c.get("exists")])
    missing = len([c for c in cfgs if not c.get("exists")])
    lines.append(f"  Configs: {found} found, {missing} missing")

if isinstance(stale_list, list):
    dirty = len([s for s in stale_list if s.get("exists")])
    lines.append(f"  Stale files: {dirty} need cleanup")

if "services" in snapshot and isinstance(svcs, list):
    lines.append(f"  User services: {len(svcs)} running")

if isinstance(procs, dict):
    down = [k for k, v in procs.items() if not v.get("running")]
    if down:
        lines.append(f"  ⚠ Not running: {', '.join(down)}")
    else:
        lines.append(f"  Autostart processes: all up")

if errs and isinstance(errs, str) and "no errors" not in errs.lower() and errs.strip():
    lines.append(f"  ⚠ Config errors detected!")
else:
    lines.append(f"  Config: clean")

print("\n".join(lines), file=sys.stderr)

PYEOF
}

# ── Main ──

case "$COMMAND" in
   full)
        echo "Collecting system state for Littlebear..." >&2
        mkdir -p "$OUT_DIR"
        collect "full" "$OUTFILE"
        cp -f "$OUTFILE" "$OUT_DIR/latest.json"

        # Auto-commit dotfiles if anything changed
        if git -C "$HOME/.config" diff --quiet 2>/dev/null && \
           git -C "$HOME/.config" diff --cached --quiet 2>/dev/null; then
            echo "  Dotfiles: no changes" >&2
        else
            git -C "$HOME/.config" add -A 2>/dev/null
            git -C "$HOME/.config" commit -m "auto: snapshot $(date +%Y-%m-%d_%H:%M)" 2>/dev/null >&2
            echo "  Dotfiles: committed" >&2
        fi

        echo "" >&2
        echo "Snapshot saved: $OUTFILE" >&2
        echo "Latest: $OUT_DIR/latest.json" >&2
        ;;
    pulse)
        echo "Pulse check..." >&2
        collect "pulse" "stdout"
        ;;
    *)
        # Targeted module — validate name inside Python
        collect "$COMMAND" "stdout"
        ;;
esac
