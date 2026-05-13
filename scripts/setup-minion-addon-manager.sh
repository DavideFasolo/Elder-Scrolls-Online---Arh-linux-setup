#!/usr/bin/env bash
set -euo pipefail

APP_ID="gg.minion.Minion"

PREFIX="${ESO_PREFIX:-$HOME/Games/eso-clean-wine11-prefix}"
DESKTOP_DIR="${ESO_DESKTOP_DIR:-$HOME/.local/share/applications}"
CACHE_DIR="${ESO_CACHE_DIR:-$HOME/.cache/eso-linux}"

msg() { printf '\n== %s ==\n' "$*"; }
fail() { printf 'ERRORE: %s\n' "$*" >&2; exit 1; }

msg "controllo pacchetti Arch/Garuda"

missing_pkgs=()
for p in flatpak desktop-file-utils; do
  pacman -Q "$p" >/dev/null 2>&1 || missing_pkgs+=("$p")
done

if (( ${#missing_pkgs[@]} > 0 )); then
  printf 'Pacchetti mancanti: %s\n' "${missing_pkgs[*]}" >&2
  printf 'Installa con:\n  sudo pacman -S --needed %s\n' "${missing_pkgs[*]}" >&2
  exit 1
fi

command -v flatpak >/dev/null 2>&1 || fail "flatpak non trovato"
command -v update-desktop-database >/dev/null 2>&1 || true

msg "configuro Flathub"

flatpak remote-add --if-not-exists flathub https://flathub.org/repo/flathub.flatpakrepo

msg "installo Minion Flatpak"

flatpak --user install -y flathub "$APP_ID"

msg "concedo accesso alla home a Minion"

flatpak override --user --filesystem=home "$APP_ID"

msg "cerco percorso AddOns ESO"

DOCS_DIR=""

# Caso preferito: prefisso ESO già creato.
if [[ -e "$PREFIX/drive_c/users/steamuser/Documents" ]]; then
  DOCS_DIR="$PREFIX/drive_c/users/steamuser/Documents"
elif [[ -d "$PREFIX/drive_c/users" ]]; then
  while IFS= read -r d; do
    base="$(basename "$d")"
    [[ "$base" == "Public" ]] && continue
    if [[ -e "$d/Documents" ]]; then
      DOCS_DIR="$d/Documents"
      break
    fi
  done < <(find "$PREFIX/drive_c/users" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | sort)
fi

# Fallback: cartella Documenti/Documents nativa.
if [[ -z "$DOCS_DIR" ]]; then
  if command -v xdg-user-dir >/dev/null 2>&1; then
    DOCS_DIR="$(xdg-user-dir DOCUMENTS 2>/dev/null || true)"
  fi

  if [[ -z "$DOCS_DIR" || "$DOCS_DIR" == "$HOME" ]]; then
    if [[ -d "$HOME/Documenti" ]]; then
      DOCS_DIR="$HOME/Documenti"
    else
      DOCS_DIR="$HOME/Documents"
    fi
  fi
fi

LIVE_DIR="$(realpath -m "$DOCS_DIR/Elder Scrolls Online/live")"
ADDONS_DIR="$LIVE_DIR/AddOns"
SAVEDVARS_DIR="$LIVE_DIR/SavedVariables"

mkdir -p "$ADDONS_DIR" "$SAVEDVARS_DIR" "$CACHE_DIR" "$DESKTOP_DIR"

PATH_INFO="$CACHE_DIR/minion-addon-path.txt"

cat > "$PATH_INFO" <<EOF
ESO Minion paths

Cartella live ESO:
$LIVE_DIR

Cartella AddOns:
$ADDONS_DIR

Cartella SavedVariables:
$SAVEDVARS_DIR

Uso consigliato in Minion:
- se Minion chiede la cartella AddOns, usa:
  $ADDONS_DIR

- se Minion chiede la cartella live/game folder, usa:
  $LIVE_DIR
EOF

msg "genero launcher desktop Minion"

cat > "$DESKTOP_DIR/eso-minion.desktop" <<EOF
[Desktop Entry]
Type=Application
Name=ESO Minion
Comment=Gestione addon di Elder Scrolls Online tramite Minion
Exec=flatpak run $APP_ID
Icon=$APP_ID
Terminal=false
Categories=Game;Utility;
StartupNotify=true
EOF

chmod +x "$DESKTOP_DIR/eso-minion.desktop"
update-desktop-database "$DESKTOP_DIR" >/dev/null 2>&1 || true

msg "setup Minion completato"

cat <<EOF
Desktop entry creata:
  ESO Minion

Percorso salvato in:
  $PATH_INFO

Percorso AddOns da usare in Minion:
  $ADDONS_DIR

Nota pratica:
  se Minion sembra bloccato o non lista gli addon al primo avvio,
  chiudilo e riaprilo. Sì, davvero. Informatica gestionale per troll.
EOF
