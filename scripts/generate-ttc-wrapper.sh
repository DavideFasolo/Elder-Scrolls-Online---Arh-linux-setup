#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="${ESO_SCRIPT_DIR:-$HOME/scripts/games}"
ADDONS_DIR="${ESO_ADDONS_DIR:-$HOME/Documenti/Elder Scrolls Online/live/AddOns}"
OUT="$SCRIPT_DIR/eso-ttc.sh"

usage() {
  cat <<EOF
Uso:
  scripts/generate-ttc-wrapper.sh [opzioni]

Opzioni:
  --addon-dir PATH    Percorso AddOns ESO.
  --output PATH       Percorso wrapper generato.
  -h, --help          Mostra questo aiuto.
EOF
}

fail() {
  echo "ERRORE: $*" >&2
  exit 1
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --addon-dir)
      shift
      [[ $# -gt 0 ]] || fail "--addon-dir richiede un percorso"
      ADDONS_DIR="$1"
      ;;
    --output)
      shift
      [[ $# -gt 0 ]] || fail "--output richiede un percorso"
      OUT="$1"
      SCRIPT_DIR="$(dirname "$OUT")"
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

mkdir -p "$SCRIPT_DIR"

cat > "$OUT" <<'EOF'
#!/usr/bin/env bash
set -Eeuo pipefail

UPDATER="${ESO_TTC_UPDATER:-$HOME/scripts/games/ttc-esoui-updater/Linux_Tamriel_Trade_Center.sh}"
ADDONS="${ESO_ADDONS_DIR:-__ADDONS_DIR__}"
LIVE="$(dirname "$ADDONS")"
SETTINGS="$LIVE/AddOnSettings.txt"
LOG="$HOME/Documents/Linux_Tamriel_Trade_Center/Logs/LTTC.log"

SERVER="eu"
MODE="once"
DRY_RUN=false
ACTION="run"

usage() {
  cat <<USAGE
Uso:
  eso-ttc.sh [opzioni]

Modalità:
  --once              Aggiorna una volta e chiude. Default.
  --loop              Resta aperto e controlla periodicamente.
  --status            Mostra stato TTC/AddOnSettings/PriceTable.
  --log               Mostra le ultime righe del log updater.
  --enable-ttc        Abilita TamrielTradeCentre in AddOnSettings.txt.
  --enable-harvestmap Abilita HarvestMap in AddOnSettings.txt.
  --dry-run           Mostra il comando che verrebbe eseguito.

Server:
  --eu                Usa server EU. Default.
  --na                Usa server NA.

Path:
  --addon-dir PATH    Usa una cartella AddOns diversa.

Altro:
  -h, --help          Mostra questo aiuto.

Esempi:
  eso-ttc.sh
  eso-ttc.sh --once
  eso-ttc.sh --loop
  eso-ttc.sh --status
  eso-ttc.sh --enable-ttc
USAGE
}

die() {
  echo "ERRORE: $*" >&2
  exit 1
}

ensure_file() {
  [[ -f "$1" ]] || die "file non trovato: $1"
}

ensure_dir() {
  [[ -d "$1" ]] || die "directory non trovata: $1"
}

enable_addon() {
  local addon="$1"

  ensure_file "$SETTINGS"

  cp -av "$SETTINGS" "$SETTINGS.bak.$(date +%Y%m%d-%H%M%S)" >/dev/null

  python - "$SETTINGS" "$addon" <<'PY'
from pathlib import Path
import sys

p = Path(sys.argv[1])
addon = sys.argv[2]

lines = p.read_text(encoding="utf-8").splitlines()
out = []
found = False

for line in lines:
    if line.startswith(addon + " "):
        out.append(addon + " 1")
        found = True
    else:
        out.append(line)

if not found:
    out.append(addon + " 1")

p.write_text("\n".join(out) + "\n", encoding="utf-8")
PY

  echo "OK: ${addon} abilitato in AddOnSettings.txt"
}

show_status() {
  echo "=== Path ==="
  echo "LIVE:    $LIVE"
  echo "ADDONS:  $ADDONS"
  echo "UPDATER: $UPDATER"

  echo
  echo "=== AddOnSettings rilevanti ==="
  if [[ -f "$SETTINGS" ]]; then
    grep -nE "TamrielTradeCentre|HarvestMap|EsoTradingHub|EsoHubScanner|LibEsoHubPrices" "$SETTINGS" || true
  else
    echo "MANCA: $SETTINGS"
  fi

  echo
  echo "=== TTC PriceTable ==="
  find "$ADDONS/TamrielTradeCentre" -maxdepth 1 -type f -iname "PriceTable*.lua" \
    -printf "%TY-%Tm-%Td %TH:%TM  %10s  %f\n" 2>/dev/null | sort || true

  echo
  echo "=== TTC SavedVariables ==="
  find "$LIVE/SavedVariables" -maxdepth 1 -type f -iname "*tamriel*" \
    -printf "%TY-%Tm-%Td %TH:%TM  %10s  %f\n" 2>/dev/null | sort || true
}

show_log() {
  if [[ -f "$LOG" ]]; then
    tail -120 "$LOG"
  else
    echo "Log non trovato: $LOG"
  fi
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --once)
      MODE="once"
      ;;
    --loop)
      MODE="loop"
      ;;
    --eu)
      SERVER="eu"
      ;;
    --na)
      SERVER="na"
      ;;
    --addon-dir)
      shift
      [[ $# -gt 0 ]] || die "--addon-dir richiede un path"
      ADDONS="$1"
      LIVE="$(dirname "$ADDONS")"
      SETTINGS="$LIVE/AddOnSettings.txt"
      ;;
    --status)
      ACTION="status"
      ;;
    --log)
      ACTION="log"
      ;;
    --enable-ttc)
      ACTION="enable-ttc"
      ;;
    --enable-harvestmap)
      ACTION="enable-harvestmap"
      ;;
    --dry-run)
      DRY_RUN=true
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      die "opzione sconosciuta: $1"
      ;;
  esac
  shift
done

case "$ACTION" in
  status)
    show_status
    exit 0
    ;;
  log)
    show_log
    exit 0
    ;;
  enable-ttc)
    enable_addon "TamrielTradeCentre"
    exit 0
    ;;
  enable-harvestmap)
    enable_addon "HarvestMap"
    exit 0
    ;;
esac

ensure_file "$UPDATER"
ensure_dir "$ADDONS"

# Lo script upstream decide se TTC è abilitato leggendo AddOnSettings.txt.
# ESO può mostrare l'addon attivo in gioco senza scrivere qui la riga singola,
# quindi normalizziamo prima dell'esecuzione.
if [[ -d "$ADDONS/TamrielTradeCentre" ]]; then
  enable_addon "TamrielTradeCentre" >/dev/null
fi

CMD=( "$UPDATER" "--$SERVER" "--$MODE" "--addon-dir" "$ADDONS" )

echo "=== ESO Tamriel Trade Centre updater wrapper ==="
echo "Server: $SERVER"
echo "Mode:   $MODE"
echo "AddOns: $ADDONS"
echo

if [[ "$DRY_RUN" == true ]]; then
  printf 'Comando:\n'
  printf '%q ' "${CMD[@]}"
  echo
  exit 0
fi

exec "${CMD[@]}"
EOF

python - "$OUT" "$ADDONS_DIR" <<'PY'
from pathlib import Path
import sys

p = Path(sys.argv[1])
addons = sys.argv[2]
text = p.read_text(encoding="utf-8")
text = text.replace("__ADDONS_DIR__", addons)
p.write_text(text, encoding="utf-8")
PY

chmod +x "$OUT"

echo "Creato: $OUT"
