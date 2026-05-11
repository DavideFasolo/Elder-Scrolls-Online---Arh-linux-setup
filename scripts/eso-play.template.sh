#!/usr/bin/env bash
set -euo pipefail

# Template. setup-eso.sh genera una versione già compilata coi percorsi reali.
PREFIX="${ESO_PREFIX:-$HOME/Games/eso-clean-wine11-prefix}"
PROTON="${ESO_PROTON_DIR:-$HOME/.local/share/Steam/compatibilitytools.d/GE-Proton10-34}"
LOG="${ESO_CACHE_DIR:-$HOME/.cache/eso-linux}/eso-play.log"

mkdir -p "$(dirname "$LOG")"
ESO64="$(find "$PREFIX/drive_c" -type f -iname 'eso64.exe' 2>/dev/null | head -n 1 || true)"
[[ -n "$ESO64" ]] || { echo "eso64.exe non trovato" >&2; exit 1; }

# ESO: skip pre-game videos
patch_usersettings_skip_videos() {
  local settings
  local candidates=(
    "$HOME/Documenti/Elder Scrolls Online/live/UserSettings.txt"
    "$HOME/Documents/Elder Scrolls Online/live/UserSettings.txt"
    "$PREFIX/drive_c/users/steamuser/Documents/Elder Scrolls Online/live/UserSettings.txt"
    "$PREFIX/drive_c/users/${USER:-steamuser}/Documents/Elder Scrolls Online/live/UserSettings.txt"
  )

  for settings in "${candidates[@]}"; do
    [[ -f "$settings" ]] || continue

    if grep -q '^SET SkipPregameVideos ' "$settings"; then
      sed -i 's/^SET SkipPregameVideos .*/SET SkipPregameVideos "1"/' "$settings"
    else
      printf '\nSET SkipPregameVideos "1"\n' >> "$settings"
    fi
  done
}

patch_usersettings_skip_videos

cd "$(dirname "$ESO64")"

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
  GAMEID="umu-306130" \
  STORE="steam" \
  WINEPREFIX="$PREFIX" \
  PROTONPATH="$PROTON" \
  PROTON_USE_XALIA="0" \
  WINEDEBUG="-all" \
  umu-run "$ESO64" "$@" >> "$LOG" 2>&1
