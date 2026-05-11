# ESO Linux Wine/Proton setup

Repository per installare, aggiornare e avviare **The Elder Scrolls Online** su Arch/Garuda Linux usando un prefisso Wine pulito, comprensivo di gestore addon **Minion**.

Il setup separa due operazioni:

- **Launcher/update ESO** tramite Wine di sistema.
- **Gioco (`eso64.exe`)** avviato direttamente con GE-Proton tramite `umu-run`.
- **Gestione AddOns** tramite Minion Flatpak nativo Linux; non usa Wine/Proton, ma punta alla cartella `AddOns` usata da ESO.

Questa separazione è intenzionale: il launcher viene usato solo per installare e aggiornare, mentre il gioco viene avviato direttamente dallo script dedicato, mentre Minion gira nativamente.

## Sommario

- [Guida di installazione](#guida-di-installazione)
  - [Installazione base](#installazione-base)
  - [Installazione Minion](#installazione-minion)
- [Troubleshooting](#troubleshooting)
  - [Timeout del launcher](#timeout-del-launcher)
  - [Crash premendo PLAY dal launcher](#crash-premendo-play-dal-launcher)
  - [Client obsoleto](#client-obsoleto)
  - [GE-Proton non trovato](#ge-proton-non-trovato)
  - [Wine Mono](#wine-mono)
  - [Video iniziali ancora visibili](#video-iniziali-ancora-visibili)
  - [Minion non trova gli AddOns](#minion-non-trova-gli-addons)
  - [Log](#log)
- [Altro](#altro)
  - [Schema operativo](#schema-operativo)
  - [Percorsi generati](#percorsi-generati)
  - [Variabili ambiente](#variabili-ambiente)
  - [Note](#note)

## Guida di installazione

### Installazione base

#### 1. Installare le dipendenze

Su Arch-based:

```bash
sudo pacman -S --needed wine winetricks umu-launcher curl unzip rsync desktop-file-utils
```

Serve anche **GE-Proton**, installato di norma in:

```text
~/.local/share/Steam/compatibilitytools.d/
```

Lo script cerca automaticamente l'ultima directory `GE-Proton*`.

#### 2. Clonare il repository

```bash
git clone git@github.com:DavideFasolo/Elder-Scrolls-Online---Arh-linux-setup.git eso-linux-wine-proton-setup
cd eso-linux-wine-proton-setup
```

#### 3. Eseguire il setup

```bash
./setup-eso.sh
```

Lo script:

- crea un prefisso Wine pulito;
- scarica il launcher ufficiale ESO;
- verifica lo SHA256 del pacchetto launcher;
- installa il launcher nel prefisso;
- installa runtime utili tramite `winetricks`;
- genera gli script di avvio;
- genera i file `.desktop`.

#### 4. Installare o aggiornare ESO

Avvia il launcher:

```bash
~/scripts/games/eso-launcher-update.sh
```

Nel launcher premi **Install** o lascia completare l'aggiornamento.

Quando il launcher mostra **PLAY**, chiudilo.

Non avviare il gioco dal pulsante **PLAY** del launcher.

#### 5. Avviare il gioco

Avvia direttamente il client:

```bash
~/scripts/games/eso-play.sh
```

Lo script cerca `eso64.exe` dentro il prefisso e lo avvia con GE-Proton tramite `umu-run`.

Lo script imposta anche:

```text
SET SkipPregameVideos "1"
```

nei file `UserSettings.txt` trovati, così i video iniziali Bethesda/ZeniMax vengono saltati quando possibile.

### Installazione Minion

Minion può essere usato per gestire gli AddOns di ESO.

#### 1. Installare le dipendenze

```bash
sudo pacman -S --needed flatpak desktop-file-utils
```

#### 2. Eseguire lo script Minion

```bash
scripts/setup-minion-addon-manager.sh
```

Lo script:

- configura Flathub se manca;
- installa Minion Flatpak;
- concede a Minion accesso alla home;
- crea le cartelle `AddOns` e `SavedVariables`;
- genera un launcher desktop dedicato.

#### 3. Percorso AddOns

Il percorso consigliato viene scritto in:

```text
~/.cache/eso-linux/minion-addon-path.txt
```

Nel setup verificato, il percorso AddOns è:

```text
~/Documenti/Elder Scrolls Online/live/AddOns
```

Avvio Minion:

```bash
flatpak run gg.minion.Minion
```

## Troubleshooting

### Timeout del launcher

Se compare:

```text
Timeout waiting for window to load
```

non avviare il launcher con Proton, UMU o Lutris.

Usa:

```bash
eso-launcher-update
```

oppure:

```bash
~/scripts/games/eso-launcher-update.sh
```

### Crash premendo PLAY dal launcher

È previsto in questa configurazione.

Il launcher serve solo per installare e aggiornare.

Chiudilo quando mostra **PLAY**, poi avvia:

```bash
eso-play
```

### Client obsoleto

Avvia:

```bash
eso-launcher-update
```

Lascia aggiornare.

Quando il launcher mostra **PLAY**, chiudilo e poi avvia:

```bash
eso-play
```

### GE-Proton non trovato

Installa GE-Proton in:

```text
~/.local/share/Steam/compatibilitytools.d/
```

Oppure forza il percorso:

```bash
export ESO_PROTON_DIR="$HOME/.local/share/Steam/compatibilitytools.d/GE-Proton10-34"
./setup-eso.sh
```

### Wine Mono

Lo script del launcher disabilita Wine Mono con:

```bash
WINEDLLOVERRIDES="mscoree=d"
```

Controllo rapido:

```bash
grep -n 'WINEDLLOVERRIDES' ~/scripts/games/eso-launcher-update.sh
```

### Video iniziali ancora visibili

Controlla:

```bash
grep -RIn '^SET SkipPregameVideos ' \
  "$HOME/Documenti/Elder Scrolls Online/live" \
  "$HOME/Games/eso-clean-wine11-prefix/drive_c/users" 2>/dev/null
```

Valore atteso:

```text
SET SkipPregameVideos "1"
```

### Minion non trova gli AddOns

Controlla:

```bash
cat ~/.cache/eso-linux/minion-addon-path.txt
```

Poi usa in Minion il percorso `AddOns` indicato lì.

### Log

Launcher:

```bash
cat ~/.cache/eso-linux/eso-launcher-update.log
```

Gioco:

```bash
cat ~/.cache/eso-linux/eso-play.log
```

## Altro

### Schema operativo

Uso normale:

```bash
eso-play
```

Aggiornamento:

```bash
eso-launcher-update
```

Flusso consigliato:

```text
1. Avvia eso-launcher-update
2. Installa o aggiorna dal launcher
3. Quando compare PLAY, chiudi il launcher
4. Avvia eso-play
```

### Percorsi generati

Prefisso Wine:

```text
~/Games/eso-clean-wine11-prefix
```

Script:

```text
~/scripts/games/eso-launcher-update.sh
~/scripts/games/eso-play.sh
```

Desktop entry:

```text
~/.local/share/applications/eso-launcher.desktop
~/.local/share/applications/eso-game.desktop
```

Log:

```text
~/.cache/eso-linux/eso-launcher-update.log
~/.cache/eso-linux/eso-play.log
```

Minion:

```text
~/.local/share/applications/eso-addon-minion.desktop
~/.cache/eso-linux/minion-addon-path.txt
```

### Variabili ambiente

Percorsi personalizzabili:

```bash
export ESO_PREFIX="$HOME/Games/eso-clean-wine11-prefix"
export ESO_SCRIPT_DIR="$HOME/scripts/games"
export ESO_DESKTOP_DIR="$HOME/.local/share/applications"
export ESO_PROTON_DIR="$HOME/.local/share/Steam/compatibilitytools.d/GE-Proton10-34"

./setup-eso.sh
```

Ricreare da zero il prefisso:

```bash
./setup-eso.sh --force
```

Attenzione: `--force` cancella il prefisso indicato da `ESO_PREFIX`.

### Note

Questo repository non contiene file del gioco, credenziali, account, launcher binario o contenuti Bethesda/ZeniMax.

Lo script scarica il launcher ufficiale e prepara solo l'ambiente locale.

