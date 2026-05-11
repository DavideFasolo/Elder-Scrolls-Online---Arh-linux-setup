#!/usr/bin/env bash
set -euo pipefail

FORCE=0
if [[ "${1:-}" == "--force" ]]; then
  FORCE=1
elif [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  cat <<'EOF'
Usage: ./setup-eso.sh [--force]

Environment variables:
  ESO_PREFIX       Wine prefix path. Default: $HOME/Games/eso-clean-wine11-prefix
  ESO_SCRIPT_DIR   Generated script dir. Default: $HOME/scripts/games
  ESO_DESKTOP_DIR  Desktop entry dir. Default: $HOME/.local/share/applications
  ESO_PROTON_DIR   GE-Proton path. Autodetected if empty.
EOF
  exit 0
fi

PREFIX="${ESO_PREFIX:-$HOME/Games/eso-clean-wine11-prefix}"
SCRIPT_DIR="${ESO_SCRIPT_DIR:-$HOME/scripts/games}"
DESKTOP_DIR="${ESO_DESKTOP_DIR:-$HOME/.local/share/applications}"
CACHE_DIR="${ESO_CACHE_DIR:-$HOME/.cache/eso-linux}"
DOWNLOAD_DIR="$CACHE_DIR/downloads"
LAUNCHER_URL="${ESO_LAUNCHER_URL:-https://elderscrolls-a.akamaihd.net/products/CNL_Launcher/Launcher_6.2.44.m250723.zip}"
LAUNCHER_SHA256="${ESO_LAUNCHER_SHA256:-20b200414e5a2d81601ba1c6a0cdf7b70b800f218ca891a24d92bc164b01e4dc}"
ZIP="$DOWNLOAD_DIR/$(basename "$LAUNCHER_URL")"
ZENIMAX_DIR="$PREFIX/drive_c/Program Files (x86)/Zenimax Online"
LAUNCHER_DIR="$ZENIMAX_DIR/Launcher"

msg() { printf '\n== %s ==\n' "$*"; }
fail() { printf 'ERRORE: %s\n' "$*" >&2; exit 1; }

need_cmds=(pacman wine wineboot wineserver winetricks umu-run curl unzip rsync sha256sum find grep sed awk)
missing_cmds=()
for c in "${need_cmds[@]}"; do
  command -v "$c" >/dev/null 2>&1 || missing_cmds+=("$c")
done

if (( ${#missing_cmds[@]} > 0 )); then
  printf 'Comandi mancanti: %s\n' "${missing_cmds[*]}" >&2
  cat >&2 <<'EOF'
Installa prima i pacchetti base:
  sudo pacman -S --needed wine winetricks umu-launcher curl unzip rsync desktop-file-utils
EOF
  exit 1
fi

msg "controllo pacchetti pacman principali"
missing_pkgs=()
for p in wine winetricks umu-launcher curl unzip rsync desktop-file-utils; do
  pacman -Q "$p" >/dev/null 2>&1 || missing_pkgs+=("$p")
done
if (( ${#missing_pkgs[@]} > 0 )); then
  printf 'Pacchetti mancanti: %s\n' "${missing_pkgs[*]}"
  printf 'Installa con:\n  sudo pacman -S --needed %s\n' "${missing_pkgs[*]}"
  exit 1
fi

PROTON="${ESO_PROTON_DIR:-}"
if [[ -z "$PROTON" ]]; then
  PROTON="$(find "$HOME/.local/share/Steam/compatibilitytools.d" -maxdepth 1 -mindepth 1 -type d -name 'GE-Proton*' 2>/dev/null | sort -V | tail -n 1 || true)"
fi
[[ -n "$PROTON" && -d "$PROTON" ]] || fail "GE-Proton non trovato. Installa GE-Proton in ~/.local/share/Steam/compatibilitytools.d oppure esporta ESO_PROTON_DIR=/percorso/GE-Proton..."
[[ -x "$PROTON/files/bin/wineserver" ]] || fail "Percorso GE-Proton non valido: manca $PROTON/files/bin/wineserver"

msg "riepilogo"
cat <<EOF
Wine:        $(wine --version)
UMU:         $(umu-run --version 2>/dev/null | head -n 1 || true)
Prefix:      $PREFIX
Proton:      $PROTON
Script dir:  $SCRIPT_DIR
Desktop dir: $DESKTOP_DIR
Launcher:    $LAUNCHER_URL
EOF

if [[ -d "$PREFIX" ]]; then
  if (( FORCE == 1 )); then
    msg "rimuovo prefisso esistente (--force)"
    rm -rf "$PREFIX"
  else
    fail "Il prefisso esiste già: $PREFIX. Usa --force per ricrearlo da zero."
  fi
fi

mkdir -p "$DOWNLOAD_DIR" "$SCRIPT_DIR" "$DESKTOP_DIR" "$CACHE_DIR"

msg "scarico launcher ufficiale"
if [[ ! -f "$ZIP" ]]; then
  curl -L --fail --retry 3 --retry-delay 2 -o "$ZIP" "$LAUNCHER_URL"
else
  echo "Uso download già presente: $ZIP"
fi

msg "verifico sha256 launcher"
echo "$LAUNCHER_SHA256  $ZIP" | sha256sum -c -

msg "inizializzo prefisso Wine pulito"
mkdir -p "$PREFIX"
WINEDLLOVERRIDES="mscoree=d" WINEPREFIX="$PREFIX" WINEARCH=win64 wineboot -u >/dev/null 2>&1 || true
sleep 2

msg "installo launcher nel prefisso"
mkdir -p "$ZENIMAX_DIR"
unzip -q "$ZIP" -d "$ZENIMAX_DIR"
[[ -f "$LAUNCHER_DIR/Bethesda.net_Launcher.exe" ]] || fail "Launcher non estratto correttamente in $LAUNCHER_DIR"

msg "scrivo launcher.settings"
cat > "$LAUNCHER_DIR/launcher.settings" <<'JSON'
{"appScale1080":1,"language":"en-us","removeDirect3LauncherFiles":false,"downloadDirect6Metafiles":false,"renameOldGameDirectories":false,"detectDirect3GameInstallDIrectories":false,"cleanupObsoleteFiles":false,"enableTTS":false,"ttsLanguageFilterEnabled":true,"fontSize":0,"zosLastError_Live_Prod":"","zosLastError_PTS_Prod":"","lastSelectedGame":"The Elder Scrolls Online"}
JSON

msg "installo runtime Wine nel prefisso"
WINEDLLOVERRIDES="mscoree=d" WINEPREFIX="$PREFIX" winetricks -q vcrun2022 d3dcompiler_47 dxvk

msg "genero script launcher/update"
cat > "$SCRIPT_DIR/eso-launcher-update.sh" <<EOF
#!/usr/bin/env bash
set -euo pipefail

PREFIX="$PREFIX"
LAUNCHER="\$PREFIX/drive_c/Program Files (x86)/Zenimax Online/Launcher"
EXE="\$LAUNCHER/Bethesda.net_Launcher.exe"
LOG="$CACHE_DIR/eso-launcher-update.log"

mkdir -p "\$(dirname "\$LOG")"

if [[ ! -f "\$EXE" ]]; then
  echo "Launcher non trovato: \$EXE" >&2
  exit 1
fi

pkill -f 'eso64.exe|Bethesda.net_Launcher.exe|launcher_helper.exe|GameConsultant.exe|winedbg' 2>/dev/null || true
WINEPREFIX="\$PREFIX" wineserver -k >/dev/null 2>&1 || true
sleep 1

cd "\$LAUNCHER"

exec env -i \\
  HOME="\$HOME" \\
  USER="\${USER:-user}" \\
  LOGNAME="\${LOGNAME:-\${USER:-user}}" \\
  PATH="/usr/local/bin:/usr/bin:/bin" \\
  LANG="\${LANG:-it_IT.UTF-8}" \\
  DISPLAY="\${DISPLAY:-:0}" \\
  WAYLAND_DISPLAY="\${WAYLAND_DISPLAY:-}" \\
  XDG_RUNTIME_DIR="\${XDG_RUNTIME_DIR:-}" \\
  XDG_CURRENT_DESKTOP="\${XDG_CURRENT_DESKTOP:-Hyprland}" \\
  XDG_SESSION_TYPE="\${XDG_SESSION_TYPE:-wayland}" \\
  DBUS_SESSION_BUS_ADDRESS="\${DBUS_SESSION_BUS_ADDRESS:-}" \\
  WINEPREFIX="\$PREFIX" \\
  WINEDLLOVERRIDES="mscoree=d" \\
  WINEDEBUG="-all" \\
  wine "\$EXE" >> "\$LOG" 2>&1
EOF
chmod +x "$SCRIPT_DIR/eso-launcher-update.sh"

msg "genero script gioco"
cat > "$SCRIPT_DIR/eso-play.sh" <<EOF
#!/usr/bin/env bash
set -euo pipefail

PREFIX="$PREFIX"
PROTON="$PROTON"
LOG="$CACHE_DIR/eso-play.log"

mkdir -p "\$(dirname "\$LOG")"

ESO64="\$(find "\$PREFIX/drive_c" -type f -iname 'eso64.exe' 2>/dev/null | head -n 1 || true)"

if [[ -z "\${ESO64:-}" ]]; then
  echo "eso64.exe non trovato dentro: \$PREFIX/drive_c" >&2
  echo "Avvia prima: $SCRIPT_DIR/eso-launcher-update.sh" >&2
  exit 1
fi

if [[ ! -d "\$PROTON" ]]; then
  echo "GE-Proton non trovato: \$PROTON" >&2
  exit 1
fi

pkill -f 'Bethesda.net_Launcher.exe|launcher_helper.exe|GameConsultant.exe|winedbg' 2>/dev/null || true
WINEPREFIX="\$PREFIX" "\$PROTON/files/bin/wineserver" -k >/dev/null 2>&1 || true
sleep 1


# ESO: skip pre-game videos
patch_usersettings_skip_videos() {
  local settings
  local candidates=(
    "\$HOME/Documenti/Elder Scrolls Online/live/UserSettings.txt"
    "\$HOME/Documents/Elder Scrolls Online/live/UserSettings.txt"
    "\$PREFIX/drive_c/users/steamuser/Documents/Elder Scrolls Online/live/UserSettings.txt"
    "\$PREFIX/drive_c/users/\${USER:-steamuser}/Documents/Elder Scrolls Online/live/UserSettings.txt"
  )

  for settings in "\${candidates[@]}"; do
    [[ -f "\$settings" ]] || continue

    if grep -q '^SET SkipPregameVideos ' "\$settings"; then
      sed -i 's/^SET SkipPregameVideos .*/SET SkipPregameVideos "1"/' "\$settings"
    else
      printf '\nSET SkipPregameVideos "1"\n' >> "\$settings"
    fi
  done
}

patch_usersettings_skip_videos

cd "\$(dirname "\$ESO64")"

exec env -i \\
  HOME="\$HOME" \\
  USER="\${USER:-user}" \\
  LOGNAME="\${LOGNAME:-\${USER:-user}}" \\
  PATH="/usr/local/bin:/usr/bin:/bin" \\
  LANG="\${LANG:-it_IT.UTF-8}" \\
  DISPLAY="\${DISPLAY:-:0}" \\
  WAYLAND_DISPLAY="\${WAYLAND_DISPLAY:-}" \\
  XDG_RUNTIME_DIR="\${XDG_RUNTIME_DIR:-}" \\
  XDG_CURRENT_DESKTOP="\${XDG_CURRENT_DESKTOP:-Hyprland}" \\
  XDG_SESSION_TYPE="\${XDG_SESSION_TYPE:-wayland}" \\
  DBUS_SESSION_BUS_ADDRESS="\${DBUS_SESSION_BUS_ADDRESS:-}" \\
  GAMEID="umu-306130" \\
  STORE="steam" \\
  WINEPREFIX="\$PREFIX" \\
  PROTONPATH="\$PROTON" \\
  PROTON_USE_XALIA="0" \\
  WINEDEBUG="-all" \\
  umu-run "\$ESO64" "\$@" >> "\$LOG" 2>&1
EOF
chmod +x "$SCRIPT_DIR/eso-play.sh"

msg "genero symlink comodi se possibile"
ln -sf "$SCRIPT_DIR/eso-launcher-update.sh" "$SCRIPT_DIR/eso-launcher-update"
ln -sf "$SCRIPT_DIR/eso-play.sh" "$SCRIPT_DIR/eso-play"

msg "genero file .desktop"
cat > "$DESKTOP_DIR/eso-launcher.desktop" <<EOF
[Desktop Entry]
Type=Application
Name=ESO Launcher
Comment=Aggiorna The Elder Scrolls Online tramite launcher Wine
Exec=$SCRIPT_DIR/eso-launcher-update.sh
Icon=applications-games
Terminal=false
Categories=Game;
StartupNotify=true
EOF

cat > "$DESKTOP_DIR/eso-game.desktop" <<EOF
[Desktop Entry]
Type=Application
Name=ESO Game
Comment=Avvia The Elder Scrolls Online tramite GE-Proton
Exec=$SCRIPT_DIR/eso-play.sh
Icon=applications-games
Terminal=false
Categories=Game;
StartupNotify=true
EOF
chmod +x "$DESKTOP_DIR/eso-launcher.desktop" "$DESKTOP_DIR/eso-game.desktop"
update-desktop-database "$DESKTOP_DIR" >/dev/null 2>&1 || true

msg "setup completato"
cat <<EOF
Prossimi passi:

1. Avvia launcher/update:
   $SCRIPT_DIR/eso-launcher-update.sh

2. Premi Install, attendi download/installazione.

3. Quando il launcher mostra PLAY, chiudilo. Non premere PLAY dal launcher.

4. Avvia il gioco:
   $SCRIPT_DIR/eso-play.sh

Desktop entries:
   ESO Launcher
   ESO Game
EOF
