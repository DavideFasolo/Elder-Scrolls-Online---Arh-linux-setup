#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="${ESO_SCRIPT_DIR:-$HOME/scripts/games}"
CACHE_DIR="${ESO_CACHE_DIR:-$HOME/.cache/eso-linux}"
DOWNLOAD_DIR="$CACHE_DIR/downloads"
DESKTOP_DIR="${ESO_DESKTOP_DIR:-$HOME/.local/share/applications}"

ADDONS_DIR="${ESO_ADDONS_DIR:-$HOME/Documenti/Elder Scrolls Online/live/AddOns}"
UPDATER_DIR="$SCRIPT_DIR/ttc-esoui-updater"
UPDATER_SH="$UPDATER_DIR/Linux_Tamriel_Trade_Center.sh"
UI_VENV="${ESO_TTC_UI_VENV:-$SCRIPT_DIR/eso-ttc-ui-venv}"
UI_LAUNCHER="$SCRIPT_DIR/eso-ttc-ui"
UI_SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/eso-ttc-ui.py"
GENERATOR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/generate-ttc-wrapper.sh"

ESOUI_INFO_URL="https://www.esoui.com/downloads/info3249-LinuxTamrielTradeCenter.html"
ESOUI_DOWNLOAD_PAGE_URL="https://www.esoui.com/downloads/download3249-TamrielTradeCenterHarvestMapampESO-HubAuto-UpdaterLinuxmacOSSteamDeckampWindows"

msg() {
  printf '\n== %s ==\n' "$*"
}

fail() {
  printf 'ERRORE: %s\n' "$*" >&2
  exit 1
}

usage() {
  cat <<EOF
Uso:
  scripts/setup-ttc-updater.sh [opzioni]

Opzioni:
  --addon-dir PATH    Percorso AddOns ESO. Default:
                      $HOME/Documenti/Elder Scrolls Online/live/AddOns

  --desktop           Crea launcher desktop per la UI Python.
  -h, --help          Mostra questo aiuto.

Variabili ambiente:
  ESO_SCRIPT_DIR      Directory dove installare gli script utente.
                      Default: $HOME/scripts/games

  ESO_CACHE_DIR       Cache/download temporanei.
                      Default: $HOME/.cache/eso-linux

  ESO_ADDONS_DIR      Percorso AddOns ESO.
                      Default: $HOME/Documenti/Elder Scrolls Online/live/AddOns

Note:
  Questo script NON installa gli addon ESO. Tamriel Trade Centre, HarvestMap
  e simili vanno installati/aggiornati con Minion.
EOF
}

CREATE_DESKTOP=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --addon-dir)
      shift
      [[ $# -gt 0 ]] || fail "--addon-dir richiede un percorso"
      ADDONS_DIR="$1"
      ;;
    --desktop)
      CREATE_DESKTOP=1
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      fail "opzione sconosciuta: $1"
      ;;
  esac
  shift
done

need_cmds=(curl unzip python chmod grep sed awk)
missing_cmds=()

for c in "${need_cmds[@]}"; do
  command -v "$c" >/dev/null 2>&1 || missing_cmds+=("$c")
done

if (( ${#missing_cmds[@]} > 0 )); then
  printf 'Comandi mancanti: %s\n' "${missing_cmds[*]}" >&2
  cat >&2 <<'EOF'
Installa prima le dipendenze base:

  sudo pacman -S --needed curl unzip python python-pip tk

Per la UI grafica serve anche Tkinter:

  sudo pacman -S --needed tk
EOF
  exit 1
fi

python -m venv --help >/dev/null 2>&1 || {
  cat >&2 <<'EOF'
Il modulo venv di Python non è disponibile.
Su Arch/Garuda installa o reinstalla Python e pip:

  sudo pacman -S --needed python python-pip tk
EOF
  exit 1
}

mkdir -p "$SCRIPT_DIR" "$CACHE_DIR" "$DOWNLOAD_DIR" "$UPDATER_DIR"

msg "riepilogo"
cat <<EOF
Script dir:   $SCRIPT_DIR
Updater dir:  $UPDATER_DIR
AddOns dir:   $ADDONS_DIR
Cache dir:    $CACHE_DIR
EOF

if [[ ! -d "$ADDONS_DIR" ]]; then
  msg "attenzione"
  cat <<EOF
La cartella AddOns non esiste:

  $ADDONS_DIR

La creo, ma ricordati che gli addon ESO vanno installati con Minion.
EOF
  mkdir -p "$ADDONS_DIR"
fi

msg "controllo addon gestiti da Minion"
if [[ -d "$ADDONS_DIR/TamrielTradeCentre" ]]; then
  echo "OK: TamrielTradeCentre presente"
else
  echo "ATTENZIONE: TamrielTradeCentre non presente in AddOns"
  echo "Installalo con Minion prima di usare il sync TTC."
fi

if [[ -d "$ADDONS_DIR/HarvestMap" ]]; then
  echo "OK: HarvestMap presente"
else
  echo "INFO: HarvestMap non presente o non installato. Non è obbligatorio per TTC."
fi

msg "scarico pagina download ESOUI"
HTML="$DOWNLOAD_DIR/ttc-esoui-download-page.html"
ZIP="$DOWNLOAD_DIR/ttc-esoui-updater.zip"

curl -L --fail --retry 3 \
  -A "Mozilla/5.0" \
  -e "$ESOUI_INFO_URL" \
  -o "$HTML" \
  "$ESOUI_DOWNLOAD_PAGE_URL"

msg "estraggo URL zip reale dalla pagina"
ZIP_URL="$(
  python - "$HTML" <<'PY'
from html.parser import HTMLParser
from pathlib import Path
from urllib.parse import quote, urlsplit, urlunsplit
import re
import sys

html = Path(sys.argv[1]).read_text(errors="replace")
matches = []

class Parser(HTMLParser):
    def handle_starttag(self, tag, attrs):
        for key, value in attrs:
            if not value:
                continue
            value = value.replace("&amp;", "&")
            if re.search(r"https://cdn\.esoui\.com/downloads/file3249/.*\.zip", value):
                matches.append(value)

Parser().feed(html)

if not matches:
    sys.exit(1)

url = matches[0]
parts = urlsplit(url)

safe_path = quote(parts.path, safe="/")
safe_query = quote(parts.query, safe="=&")

print(urlunsplit((parts.scheme, parts.netloc, safe_path, safe_query, parts.fragment)))
PY
)" || fail "non riesco a trovare il link zip nella pagina ESOUI"

echo "$ZIP_URL"

msg "scarico zip updater"
curl -L --fail --retry 3 \
  -A "Mozilla/5.0" \
  -o "$ZIP" \
  "$ZIP_URL"

msg "verifico zip"
file "$ZIP"
unzip -l "$ZIP" | sed -n '1,80p'

msg "estraggo Linux_Tamriel_Trade_Center.sh"
unzip -o "$ZIP" Linux_Tamriel_Trade_Center.sh -d "$UPDATER_DIR"
chmod +x "$UPDATER_SH"

msg "genero wrapper eso-ttc.sh"
[[ -x "$GENERATOR" ]] || chmod +x "$GENERATOR"
"$GENERATOR" --addon-dir "$ADDONS_DIR"

msg "installa client UI Python CustomTkinter"
if [[ -f "$UI_SRC" ]]; then
  msg "creo/aggiorno venv UI"
  python -m venv "$UI_VENV"
  "$UI_VENV/bin/python" -m pip install --upgrade pip
  "$UI_VENV/bin/python" -m pip install --upgrade customtkinter

  cp -av "$UI_SRC" "$SCRIPT_DIR/eso-ttc-ui.py"
  chmod +x "$SCRIPT_DIR/eso-ttc-ui.py"

  cat > "$UI_LAUNCHER" <<EOF
#!/usr/bin/env bash
set -Eeuo pipefail
exec "$UI_VENV/bin/python" "$SCRIPT_DIR/eso-ttc-ui.py" "\$@"
EOF
  chmod +x "$UI_LAUNCHER"

  echo "Creato: $UI_LAUNCHER"
else
  echo "ATTENZIONE: UI sorgente non trovata: $UI_SRC"
fi

if (( CREATE_DESKTOP == 1 )); then
  msg "creo desktop launcher UI"
  mkdir -p "$DESKTOP_DIR"
  cat > "$DESKTOP_DIR/eso-ttc-ui.desktop" <<EOF
[Desktop Entry]
Type=Application
Name=ESO Tamriel Trade Centre
Comment=Aggiorna dati Tamriel Trade Centre per ESO
Exec=$UI_LAUNCHER
Terminal=false
Categories=Game;Utility;
EOF
  update-desktop-database "$DESKTOP_DIR" >/dev/null 2>&1 || true
  echo "Creato: $DESKTOP_DIR/eso-ttc-ui.desktop"
fi

msg "controllo finale"
"$SCRIPT_DIR/eso-ttc.sh" --status || true

cat <<EOF

Setup TTC updater completato.

Comandi principali:

  $SCRIPT_DIR/eso-ttc.sh --once
  $SCRIPT_DIR/eso-ttc.sh --loop
  $SCRIPT_DIR/eso-ttc.sh --status
  $SCRIPT_DIR/eso-ttc-ui

Nota:
  Non viene usato --steam.
  Non vengono installati addon ESO: usa Minion.
EOF
