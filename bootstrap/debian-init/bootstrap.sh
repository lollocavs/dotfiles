#!/usr/bin/env bash
# =====================================================================
#  bootstrap.sh — ricostruisce macdebian dopo una reinstallazione
#                 pulita di Debian trixie
#
#  USO
#    ./bootstrap.sh              elenca i passi disponibili
#    ./bootstrap.sh all          esegue tutto in ordine
#    ./bootstrap.sh sources apt  esegue solo i passi indicati
#    DRY_RUN=1 ./bootstrap.sh all    mostra cosa farebbe, non tocca nulla
#
#  PRINCIPI
#    - idempotente: rieseguirlo non rompe niente
#    - nessun pacchetto mancante fa fallire l'intero passo: viene
#      elencato a fine esecuzione e si prosegue
#    - nessuna sorgente sid, nessun pinning: solo trixie
# =====================================================================
set -uo pipefail
export LC_ALL=C

DOTFILES="${DOTFILES:-$HOME/dotfiles}"
DOTFILES_REPO="${DOTFILES_REPO:-}"          # es. git@github.com:utente/dotfiles.git
BACKUP_DIR="${BACKUP_DIR:-$HOME/salvataggio}"
APT_BACKUP="${APT_BACKUP:-$BACKUP_DIR/etc-apt-backup.tar.gz}"
SECRETS="${SECRETS:-$BACKUP_DIR/secrets.tar.gz}"
DRY_RUN="${DRY_RUN:-0}"

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PKGDIR="$HERE/pkg"
MISSING_LOG="$HOME/bootstrap-mancanti.txt"

# --- output -----------------------------------------------------------
c_ok=$'\033[32m'; c_warn=$'\033[33m'; c_err=$'\033[31m'
c_head=$'\033[1;35m'; c_dim=$'\033[2m'; c_off=$'\033[0m'

step()  { printf '\n%s==> %s%s\n' "$c_head" "$1" "$c_off"; }
info()  { printf '    %s\n' "$1"; }
ok()    { printf '    %s✓%s %s\n' "$c_ok" "$c_off" "$1"; }
warn()  { printf '    %s!%s %s\n' "$c_warn" "$c_off" "$1"; }
fail()  { printf '    %s✗%s %s\n' "$c_err" "$c_off" "$1"; }
dim()   { printf '    %s%s%s\n' "$c_dim" "$1" "$c_off"; }

run() {
    if [ "$DRY_RUN" = "1" ]; then
        dim "[dry-run] $*"
    else
        "$@"
    fi
}

need_sudo() {
    if [ "$DRY_RUN" = "1" ]; then return 0; fi
    sudo -v || { fail "servono privilegi sudo"; exit 1; }
}

# =====================================================================
#  PASSO: sources — componenti apt, senza sid e senza pinning
# =====================================================================
do_sources() {
    step "Sorgenti apt"
    need_sudo

    local src=/etc/apt/sources.list.d/debian.sources
    if [ ! -f "$src" ]; then
        fail "$src non trovato — installazione non standard?"
        return 1
    fi

    if grep -qE '^\s*Components:.*non-free-firmware' "$src"; then
        ok "componenti gia' a posto"
    else
        info "aggiungo contrib non-free-firmware non-free"
        run sudo cp "$src" "$src.bak-$(date +%Y%m%d%H%M%S)"
        run sudo sed -i \
            's/^\(Components:.*\)$/\1 contrib non-free-firmware non-free/' "$src"
        run sudo sed -i 's/  */ /g' "$src"
    fi

    # Il pinning trixie/sid del vecchio sistema e' la causa del disastro
    # precedente: qui non deve esistere.
    if compgen -G "/etc/apt/preferences.d/*" >/dev/null; then
        warn "trovato pinning in /etc/apt/preferences.d — lo sposto via"
        run sudo mkdir -p /etc/apt/preferences.d.disattivate
        run sudo mv /etc/apt/preferences.d/* /etc/apt/preferences.d.disattivate/
    else
        ok "nessun pinning: corretto"
    fi

    if grep -rqiE '(^|[^a-z])(sid|unstable)([^a-z]|$)' \
            /etc/apt/sources.list.d/ 2>/dev/null; then
        fail "una sorgente cita ancora sid/unstable — rimuovila prima di proseguire"
        grep -rniE '(^|[^a-z])(sid|unstable)([^a-z]|$)' /etc/apt/sources.list.d/
        return 1
    fi
    ok "nessuna sorgente sid"

    run sudo apt update
}

# =====================================================================
#  PASSO: apt — installa le liste in pkg/, saltando cio' che non esiste
# =====================================================================
install_list() {
    local list="$1"
    local name; name="$(basename "$list")"
    local avail=() missing=() p

    while IFS= read -r p; do
        p="${p%%#*}"; p="$(echo "$p" | tr -d '[:space:]')"
        [ -z "$p" ] && continue
        if apt-cache show "$p" >/dev/null 2>&1; then
            avail+=("$p")
        else
            missing+=("$p")
        fi
    done < "$list"

    info "$name: ${#avail[@]} disponibili, ${#missing[@]} non trovati"

    if [ ${#missing[@]} -gt 0 ]; then
        printf '%s\n' "${missing[@]}" >> "$MISSING_LOG"
        for p in "${missing[@]}"; do warn "non nei repo: $p"; done
    fi

    if [ ${#avail[@]} -gt 0 ]; then
        run sudo apt install -y "${avail[@]}" \
            || fail "$name: installazione fallita, vedi output sopra"
    fi
}

do_apt() {
    step "Pacchetti dai repo Debian"
    need_sudo
    : > "$MISSING_LOG"

    local list
    for list in "$PKGDIR"/*.list; do
        [ -f "$list" ] || continue
        install_list "$list"
    done

    if [ -s "$MISSING_LOG" ]; then
        warn "pacchetti non trovati elencati in $MISSING_LOG"
    fi
}

# =====================================================================
#  PASSO: repos — ripristina i repository di terze parti dal backup
#
#  Il backup di /etc/apt fatto prima della reinstallazione contiene
#  gia' i file .list/.sources e le chiavi in /etc/apt/keyrings.
#  Ripristinarli e' piu' sicuro che ricostruire a mano URL e chiavi.
#  NON si ripristina preferences.d (il pinning) ne' debian.sources
#  (lo fornisce l'installazione nuova).
# =====================================================================
do_repos() {
    step "Repository di terze parti"
    need_sudo

    if [ ! -f "$APT_BACKUP" ]; then
        warn "backup non trovato: $APT_BACKUP"
        info "salta questo passo e aggiungi i repo a mano:"
        dim "  VSCode          https://code.visualstudio.com/docs/setup/linux"
        dim "  Docker          https://docs.docker.com/engine/install/debian/"
        dim "  GitHub CLI      https://github.com/cli/cli/blob/trunk/docs/install_linux.md"
        dim "  Claude Desktop  https://claude.ai/download"
        return 0
    fi

    local tmp; tmp="$(mktemp -d)"
    tar xzf "$APT_BACKUP" -C "$tmp"
    local base="$tmp/etc/apt"

    local f name
    for f in "$base"/sources.list.d/*; do
        [ -f "$f" ] || continue
        name="$(basename "$f")"
        case "$name" in
            debian.sources|debian.list)
                dim "salto $name (lo fornisce l'installazione nuova)" ; continue ;;
        esac
        if grep -qiE '(^|[^a-z])(sid|unstable)([^a-z]|$)' "$f"; then
            warn "salto $name: cita sid/unstable"
            continue
        fi
        info "ripristino $name"
        run sudo cp "$f" /etc/apt/sources.list.d/
    done

    if [ -d "$base/keyrings" ]; then
        run sudo mkdir -p /etc/apt/keyrings
        for f in "$base"/keyrings/*; do
            [ -f "$f" ] || continue
            info "chiave $(basename "$f")"
            run sudo cp "$f" /etc/apt/keyrings/
            run sudo chmod 0644 "/etc/apt/keyrings/$(basename "$f")"
        done
    fi

    warn "le chiavi in /usr/share/keyrings NON sono nel backup di /etc/apt"
    dim  "Claude Desktop usa /usr/share/keyrings/claude-desktop-archive-keyring.asc:"
    dim  "reinstallalo dalla pagina ufficiale, che rimette repo e chiave."

    rm -rf "$tmp"
    run sudo apt update

    info "ora installa i pacchetti dei repo esterni che vuoi, ad esempio:"
    dim  "  sudo apt install code gh"
    dim  "  sudo apt install docker-ce docker-ce-cli containerd.io \\"
    dim  "       docker-buildx-plugin docker-compose-plugin"
    dim  "  (il sistema precedente aveva sia docker.io di Debian sia i"
    dim  "   plugin di docker.com: scegline uno solo)"
}

# =====================================================================
#  PASSO: flatpak — app fuori dai repo Debian
# =====================================================================
do_flatpak() {
    step "Flatpak (Zen Browser, Obsidian)"
    need_sudo

    if ! command -v flatpak >/dev/null 2>&1; then
        run sudo apt install -y flatpak
    fi

    run sudo flatpak remote-add --if-not-exists \
        flathub https://dl.flathub.org/repo/flathub.flatpakrepo

    local app
    for app in app.zen_browser.zen md.obsidian.Obsidian; do
        info "installo $app"
        run sudo flatpak install -y flathub "$app" \
            || warn "$app non installato — verifica il nome su flathub.org"
    done

    dim "le app flatpak compaiono in wofi dopo il primo logout/login"
}

# =====================================================================
#  PASSO: dotfiles — clona e applica con stow
# =====================================================================
do_dotfiles() {
    step "Dotfiles"

    if [ ! -d "$DOTFILES" ]; then
        if [ -z "$DOTFILES_REPO" ]; then
            fail "$DOTFILES non esiste e DOTFILES_REPO non e' impostata"
            dim  "  DOTFILES_REPO=git@github.com:tuoutente/dotfiles.git ./bootstrap.sh dotfiles"
            return 1
        fi
        info "clono $DOTFILES_REPO"
        run git clone "$DOTFILES_REPO" "$DOTFILES"
    else
        ok "$DOTFILES gia' presente"
    fi

    command -v stow >/dev/null 2>&1 || run sudo apt install -y stow

    # Sposta di lato i file che impedirebbero a stow di creare i link
    local d target
    for d in kitty nvim wofi waybar starship backgrounds sway swaylock; do
        [ -d "$DOTFILES/$d" ] || continue
        while IFS= read -r target; do
            local rel="${target#"$DOTFILES/$d"/}"
            local dest="$HOME/$rel"
            if [ -e "$dest" ] && [ ! -L "$dest" ]; then
                warn "sposto $dest -> $dest.pre-stow"
                run mv "$dest" "$dest.pre-stow"
            fi
        done < <(find "$DOTFILES/$d" -type f)
    done

    info "stow dei pacchetti"
    for d in kitty nvim wofi waybar starship backgrounds sway swaylock; do
        [ -d "$DOTFILES/$d" ] || continue
        run stow -d "$DOTFILES" -t "$HOME" -R "$d" \
            && ok "stow $d" || warn "stow $d fallito"
    done

    # starship: la riga nel bashrc, se manca
    if ! grep -q 'starship init bash' "$HOME/.bashrc" 2>/dev/null; then
        info "aggiungo starship a ~/.bashrc"
        run bash -c 'echo "eval \"\$(starship init bash)\"" >> "$HOME/.bashrc"'
    fi

    # sfondo pre-sfocato per swaylock
    if command -v convert >/dev/null 2>&1 \
       && [ -f "$HOME/.config/backgrounds/shaded.png" ] \
       && [ ! -f "$HOME/.config/backgrounds/shaded-blur.png" ]; then
        info "genero lo sfondo sfocato per swaylock"
        run convert "$HOME/.config/backgrounds/shaded.png" -blur 0x8 \
                    "$HOME/.config/backgrounds/shaded-blur.png"
    fi
}

# =====================================================================
#  PASSO: secrets — ripristina ~/.ssh, ~/.gnupg e impostazioni app
#
#  Da secrets.tar.gz creato da pre-reinstall-backup.sh. Il tar preserva
#  i permessi, ma li riapplichiamo comunque: ssh e gpg rifiutano di
#  funzionare se una chiave privata e' leggibile da altri.
#  Nulla viene sovrascritto: cio' che esiste gia' viene spostato di lato.
# =====================================================================
do_secrets() {
    step "Chiavi e impostazioni applicazioni"

    local archive="$SECRETS"
    if [ ! -f "$archive" ] && [ -f "$archive.gpg" ]; then
        archive="$archive.gpg"
    fi

    if [ ! -f "$archive" ]; then
        warn "archivio non trovato: $SECRETS"
        dim  "creane uno prima di formattare con:  ./pre-reinstall-backup.sh"
        dim  "oppure indica il percorso:  SECRETS=/media/usb/secrets.tar.gz ..."
        return 0
    fi

    local tmp; tmp="$(mktemp -d)"; chmod 700 "$tmp"

    if [ "$DRY_RUN" = "1" ]; then
        dim "[dry-run] estrarrei $archive e ripristinerei le chiavi"
        rm -rf "$tmp"; return 0
    fi

    if [[ "$archive" == *.gpg ]]; then
        info "archivio cifrato: inserisci la passphrase"
        if ! gpg --decrypt "$archive" 2>/dev/null | tar xzf - -C "$tmp"; then
            fail "decifratura o estrazione fallita"
            rm -rf "$tmp"; return 1
        fi
    else
        if ! tar xzf "$archive" -C "$tmp"; then
            fail "estrazione fallita"
            rm -rf "$tmp"; return 1
        fi
    fi
    ok "archivio estratto"

    # Si ripristina FILE PER FILE, non cartella per cartella: l'archivio
    # contiene percorsi come .config/Code/User, e spostare di lato l'intera
    # ~/.config cancellerebbe i link creati da stow al passo precedente.
    local stamp; stamp="$(date +%Y%m%d%H%M%S)"
    local restored=0 displaced=0
    local rel src dest
    while IFS= read -r -d '' src; do
        rel="${src#"$tmp"/}"
        dest="$HOME/$rel"

        if [ -e "$dest" ] || [ -L "$dest" ]; then
            mv "$dest" "$dest.pre-bootstrap-$stamp"
            displaced=$((displaced + 1))
        fi

        mkdir -p "$(dirname "$dest")"
        cp -a "$src" "$dest"
        restored=$((restored + 1))
    done < <(find "$tmp" -type f -print0)

    ok "$restored file ripristinati"
    [ "$displaced" -gt 0 ] && \
        warn "$displaced file preesistenti spostati in *.pre-bootstrap-$stamp"

    # Riepilogo per cartella di primo livello, senza elencare ogni file
    while IFS= read -r rel; do
        dim "  ~/$rel"
    done < <(find "$tmp" -mindepth 1 -maxdepth 1 -printf '%f\n' | sort)

    # Permessi: ssh e gpg sono severi e falliscono in silenzio se sbagliati
    if [ -d "$HOME/.ssh" ]; then
        chmod 700 "$HOME/.ssh"
        find "$HOME/.ssh" -type f -exec chmod 600 {} +
        find "$HOME/.ssh" -type f -name '*.pub' -exec chmod 644 {} +
        [ -f "$HOME/.ssh/known_hosts" ] && chmod 644 "$HOME/.ssh/known_hosts"
        ok "permessi ~/.ssh (700 / 600, chiavi pubbliche 644)"
    fi

    if [ -d "$HOME/.gnupg" ]; then
        chmod 700 "$HOME/.gnupg"
        find "$HOME/.gnupg" -type d -exec chmod 700 {} +
        find "$HOME/.gnupg" -type f -exec chmod 600 {} +
        ok "permessi ~/.gnupg (700 / 600)"
    fi

    [ -f "$HOME/.git-credentials" ] && chmod 600 "$HOME/.git-credentials"

    rm -rf "$tmp"

    info "verifica rapida:"
    dim  "  ssh-add -l            elenca le chiavi caricate"
    dim  "  gpg --list-secret-keys"
    dim  "  ssh -T git@github.com"
}

# =====================================================================
#  PASSO: env — variabili in ~/.profile (sway non ha la direttiva env)
# =====================================================================
do_env() {
    step "Variabili d'ambiente in ~/.profile"

    local marker="# --- bootstrap: sway/wayland ---"
    if grep -qF "$marker" "$HOME/.profile" 2>/dev/null; then
        ok "gia' presenti"
        return 0
    fi

    if [ "$DRY_RUN" = "1" ]; then
        dim "[dry-run] aggiungerei il blocco sway/wayland a ~/.profile"
        return 0
    fi

    cat >> "$HOME/.profile" <<EOF

$marker
export XCURSOR_SIZE=24
export QT_QPA_PLATFORMTHEME=qt6ct
export QT_QPA_PLATFORM="wayland;xcb"
export SDL_VIDEODRIVER=wayland
export CLUTTER_BACKEND=wayland
export MOZ_ENABLE_WAYLAND=1
EOF
    ok "blocco aggiunto"
}

# =====================================================================
#  PASSO: greetd — sway come sessione, con selettore
# =====================================================================
do_greetd() {
    step "greetd + tuigreet"
    need_sudo

    local cfg=/etc/greetd/config.toml
    if [ ! -f "$cfg" ]; then
        fail "$cfg non trovato: installa greetd tuigreet prima"
        return 1
    fi

    if [ ! -d /usr/share/wayland-sessions ]; then
        fail "/usr/share/wayland-sessions non esiste: installa sway prima"
        return 1
    fi

    run sudo cp "$cfg" "$cfg.bak-$(date +%Y%m%d%H%M%S)"

    if [ "$DRY_RUN" = "1" ]; then
        dim "[dry-run] scriverei $cfg con --sessions e --cmd sway"
        return 0
    fi

    sudo tee "$cfg" >/dev/null <<'EOF'
[terminal]
vt = 1

[default_session]
command = "tuigreet --time --asterisks --remember --remember-session --sessions /usr/share/wayland-sessions --cmd sway"
user = "greeter"
EOF

    ok "config scritta (backup accanto)"
    warn "NON riavviare per provare: da una TTY esegui"
    dim  "  sudo systemctl restart greetd && systemctl status greetd --no-pager"
    dim  "Se avevi lo script /usr/local/bin/set-console-colors, rimettilo"
    dim  "nel comando avvolgendolo in  sh -c '... && tuigreet ...'"
}

# =====================================================================
#  PASSO: check — verifiche finali
# =====================================================================
do_check() {
    step "Verifiche"

    local b
    for b in sway swaymsg swaybg swayidle swaylock waybar wofi kitty nvim; do
        if command -v "$b" >/dev/null 2>&1; then ok "$b"; else fail "$b mancante"; fi
    done

    [ -L "$HOME/.config/sway/config" ] && ok "config sway collegata" \
        || warn "~/.config/sway/config non e' un link di stow"

    if systemctl is-active --quiet NetworkManager 2>/dev/null
        then ok "NetworkManager attivo"; else warn "NetworkManager non attivo"; fi
    if systemctl is-active --quiet bluetooth 2>/dev/null
        then ok "bluetooth attivo"; else warn "bluetooth non attivo"; fi

    if LC_ALL=C apt list --installed 2>/dev/null | grep -q 'local\]'; then
        warn "esistono pacchetti non forniti dai repo:"
        dim  "  LC_ALL=C apt list --installed 2>/dev/null | grep 'local\]'"
    else
        ok "nessun pacchetto orfano: il sistema e' coerente con i repo"
    fi

    [ -s "$MISSING_LOG" ] && warn "pacchetti non trovati: $MISSING_LOG"

    printf '\n'
    info "Prova sway da una TTY prima di affidarti al greeter:"
    dim  "  Ctrl+Alt+F2, login, poi:  sway"
}

# =====================================================================
#  main
# =====================================================================
STEPS=(sources apt repos flatpak dotfiles secrets env greetd check)

usage() {
    cat <<EOF
bootstrap.sh — ricostruisce macdebian su Debian trixie pulita

  ./bootstrap.sh all              esegue tutti i passi in ordine
  ./bootstrap.sh <passo> [...]    esegue solo quelli indicati
  DRY_RUN=1 ./bootstrap.sh all    mostra cosa farebbe senza toccare nulla

Passi disponibili, nell'ordine consigliato:
  sources    componenti apt (non-free-firmware), nessun sid, nessun pinning
  apt        pacchetti dalle liste in pkg/
  repos      repository di terze parti dal backup di /etc/apt
  flatpak    Flathub, Zen Browser, Obsidian
  dotfiles   clone del repo e stow
  secrets    ripristina ~/.ssh, ~/.gnupg e impostazioni app dal backup
  env        variabili wayland in ~/.profile
  greetd     sway come sessione con selettore tuigreet
  check      verifiche finali

Variabili:
  DOTFILES       destinazione del repo      (default ~/dotfiles)
  DOTFILES_REPO  URL da clonare se assente
  BACKUP_DIR     cartella del backup        (default ~/salvataggio)
  APT_BACKUP     tarball di /etc/apt        (default \$BACKUP_DIR/etc-apt-backup.tar.gz)
  SECRETS        archivio dei segreti       (default \$BACKUP_DIR/secrets.tar.gz)
                 se manca, prova anche \$SECRETS.gpg

Il backup si crea PRIMA di formattare, con lo script accanto:
  ./pre-reinstall-backup.sh [destinazione]
  ENCRYPT=1 ./pre-reinstall-backup.sh    per cifrare i segreti con gpg
EOF
}

main() {
    [ $# -eq 0 ] && { usage; exit 0; }

    local requested=("$@")
    [ "${1:-}" = "all" ] && requested=("${STEPS[@]}")

    [ "$DRY_RUN" = "1" ] && warn "DRY_RUN attivo: nessuna modifica al sistema"

    local s
    for s in "${requested[@]}"; do
        case " ${STEPS[*]} " in
            *" $s "*) "do_$s" ;;
            *) fail "passo sconosciuto: $s"; usage; exit 1 ;;
        esac
    done

    printf '\n%s==> fatto%s\n' "$c_head" "$c_off"
}

main "$@"
