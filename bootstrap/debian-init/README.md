# bootstrap — ricostruire macdebian su Debian trixie pulita

Ricrea la macchina dopo una reinstallazione: pacchetti, repository di terze
parti, app flatpak, dotfiles via stow, greetd con sessione sway.

## Prima di reinstallare

```bash
cd ~/dotfiles && git status && git push        # il repo deve essere pushato
cd ~/dotfiles/bootstrap

./pre-reinstall-backup.sh                      # -> ~/salvataggio
ENCRYPT=1 ./pre-reinstall-backup.sh            # cifra i segreti con gpg
./pre-reinstall-backup.sh /media/usb/backup    # direttamente sulla chiavetta
```

Lo script raccoglie in una cartella sola:

| File | Contenuto |
|---|---|
| `etc-apt-backup.tar.gz` | repo di terze parti e chiavi in `/etc/apt` |
| `secrets.tar.gz` | `~/.ssh`, `~/.gnupg`, `.gitconfig`, impostazioni di VSCode, gh, Obsidian, Zen |
| `pacchetti-prima.txt` | `dpkg --get-selections`, come riferimento |
| `installati-manualmente.txt` | `apt-mark showmanual` |
| `flatpak-prima.txt` | app flatpak installate |
| `greetd-config.toml` | configurazione del greeter |

Alla fine verifica da solo che gli archivi siano apribili.

`secrets.tar.gz` contiene **le tue chiavi private in chiaro**: usa `ENCRYPT=1`
se il backup passa da una chiavetta o da un cloud. La cifratura è
`gpg --symmetric AES256`, quindi serve solo una passphrase — che devi
ricordarti, perché senza non si recupera.

Restano da copiare a mano, perché troppo grandi o troppo personali perché uno
script decida al posto tuo: `~/code-projects` (verifica che sia tutto pushato),
`~/Documents`, `~/Downloads`, i vault di Obsidian, ed eventualmente `~/Hyprland`
se vuoi conservare i sorgenti.

**Copia la cartella su un supporto esterno e verifica di poterla leggere da lì**
prima di formattare.

## Durante l'installazione di Debian

- Scegli l'immagine con firmware non libero (necessaria per il wifi Broadcom
  del MacBook).
- **Non** installare nessun ambiente desktop: nella schermata di selezione
  software lascia solo *standard system utilities* e *SSH server* se ti serve.
  Sway lo installa `bootstrap.sh`.
- Il MacBook 2014 avvia in modalità EFI: lascia che l'installer metta GRUB
  sulla partizione EFI esistente.

## Dopo il primo avvio

```bash
sudo apt install -y git
git clone <URL-del-tuo-repo-dotfiles> ~/dotfiles
cd ~/dotfiles/bootstrap

# rimetti il backup dove lo script lo cerca
cp -r /media/.../salvataggio ~/salvataggio

# guarda cosa farebbe, senza toccare niente
DRY_RUN=1 ./bootstrap.sh all

# poi esegui davvero
./bootstrap.sh all
```

Passi singoli, se preferisci andare per gradi:

```bash
./bootstrap.sh sources apt          # sistema base + desktop
./bootstrap.sh dotfiles secrets env # config, chiavi, variabili
./bootstrap.sh greetd check         # login grafico e verifiche
```

## Cosa fa ogni passo

| Passo | Azione |
|---|---|
| `sources` | Aggiunge `contrib non-free-firmware non-free`, verifica che non ci sia sid, rimuove ogni pinning |
| `apt` | Installa le liste in `pkg/`, saltando e registrando i pacchetti non trovati |
| `repos` | Ripristina i repo di terze parti dal backup di `/etc/apt` |
| `flatpak` | Flathub, Zen Browser, Obsidian |
| `dotfiles` | Clona il repo e fa stow, spostando di lato i file che bloccherebbero i link |
| `secrets` | Ripristina `~/.ssh`, `~/.gnupg` e impostazioni app, con i permessi corretti |
| `env` | Aggiunge le variabili wayland a `~/.profile` |
| `greetd` | Scrive `config.toml` con selettore di sessione e default sway |
| `check` | Verifica binari, link, servizi e assenza di pacchetti orfani |

### Nota sul passo `secrets`

Ripristina **file per file**, non cartella per cartella. Sembra un dettaglio ma
non lo è: l'archivio contiene percorsi come `.config/Code/User`, e sostituire
l'intera `~/.config` cancellerebbe i link che `stow` ha appena creato. I file
preesistenti vengono spostati in `*.pre-bootstrap-<data>` invece di essere
sovrascritti.

Riapplica poi i permessi a mano — `~/.ssh` a 700 con le chiavi a 600, `~/.gnupg`
a 700/600 — perché ssh e gpg si rifiutano di usare chiavi leggibili da altri, e
lo fanno con messaggi poco chiari.

Se il backup è cifrato, lo script trova da solo `secrets.tar.gz.gpg` e chiede la
passphrase.

## Le liste in `pkg/`

Sono file di testo, una riga per pacchetto, `#` per i commenti. Modificale
liberamente: `bootstrap.sh` salta da solo quello che non esiste nei repo e lo
elenca in `~/bootstrap-mancanti.txt` invece di fallire.

- `10-hardware.list` — firmware, wifi Broadcom, ventole, alimentazione
- `20-sway.list` — compositore, barra, portali, audio, rete e bluetooth grafici
- `30-apps.list` — applicazioni quotidiane
- `40-dev.list` — toolchain e linguaggi

Rispetto ai 379 pacchetti manuali del vecchio sistema mancano circa un
centinaio di `-dev`: servivano a compilare Hyprland dai sorgenti. Con Sway dai
repo non servono più.

## Fuori dai repo Debian

| Software | Come |
|---|---|
| VSCode, GitHub CLI, Docker | repo ripristinati dal passo `repos`, poi `apt install` |
| Claude Desktop | reinstallare dalla pagina ufficiale: rimette repo e chiave |
| Zen Browser, Obsidian | flatpak, passo `flatpak` |
| plugin neovim | si ricostruiscono da soli al primo avvio, da `lazy-lock.json` |
| `cliphist` | se non è nei repo: `go install go.senan.xyz/cliphist@latest` |

## Verifiche dopo il ripristino delle chiavi

```bash
ssh-add -l                 # chiavi caricate nell'agent
ssh -T git@github.com      # autenticazione git funzionante
gpg --list-secret-keys     # chiavi private presenti
git -C ~/dotfiles push     # prova reale end-to-end
```

Se `ssh` si lamenta di permessi troppo aperti, rilancia `./bootstrap.sh secrets`:
la correzione dei modi è idempotente.

## Se qualcosa va storto

Il passo `greetd` fa un backup di `config.toml` accanto all'originale. Un
errore lì ti lascia con il login testuale: da una TTY rimetti il backup e
riavvia il servizio.

Prova sempre sway da TTY (`Ctrl`+`Alt`+`F2`, login, `sway`) prima di affidarti
al greeter: se parte da lì parte anche dal greeter, il contrario non è
garantito.
