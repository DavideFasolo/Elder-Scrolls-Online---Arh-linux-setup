#!/usr/bin/env bash
set -euo pipefail

# Template. setup-eso.sh genera una versione già compilata coi percorsi reali.
PREFIX="${ESO_PREFIX:-$HOME/Games/eso-clean-wine11-prefix}"
LAUNCHER="$PREFIX/drive_c/Program Files (x86)/Zenimax Online/Launcher"
EXE="$LAUNCHER/Bethesda.net_Launcher.exe"
LOG="${ESO_CACHE_DIR:-$HOME/.cache/eso-linux}/eso-launcher-update.log"

mkdir -p "$(dirname "$LOG")"
cd "$LAUNCHER"

exec env -i \
  HOME="$HOME" \
  USER="${USER:-user}" \
  LOGNAME="${LOGNAME:-${USER:-user}}" \
  PATH="/usr/local/bin:/usr/bin:/bin" \
  LANG="${LANG:-it_IT.UTF-8}" \
  DISPLAY="${DISPLAY:-:0}" \
  WAYLAND_DISPLAY="${WAYLAND_DISPLAY:-}" \
  XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-}" \
  XDG_CURRENT_DESKTOP="${XDG_CURRENT_DESKTOP:-Hyprland}" \
  XDG_SESSION_TYPE="${XDG_SESSION_TYPE:-wayland}" \
  DBUS_SESSION_BUS_ADDRESS="${DBUS_SESSION_BUS_ADDRESS:-}" \
  WINEPREFIX="$PREFIX" \
  WINEDLLOVERRIDES="mscoree=d" \
  WINEDEBUG="-all" \
  wine "$EXE" >> "$LOG" 2>&1
