#!/usr/bin/env bash
# =====================================================================
#  pre-reinstall-backup.sh — da eseguire PRIMA di formattare
#
#  Raccoglie in una cartella tutto cio' che non vive nel repo dotfiles:
#  chiavi ssh e gpg, repository apt di terze parti, impostazioni delle
#  app, inventari dei pacchetti.
#
#  USO
#    ./pre-reinstall-backup.sh                  -> ~/salvataggio
#    ./pre-reinstall-backup.sh /media/usb/bk    -> destinazione scelta
#    ENCRYPT=1 ./pre-reinstall-backup.sh        -> cifra i segreti con gpg
#
#  I DATI PERSONALI (progetti, documenti, vault) NON sono inclusi:
#  sono troppo grandi e troppo tuoi perche' uno script decida per te.
#  Lo script te li elenca alla fine.
# =====================================================================
set -uo pipefail
export LC_ALL=C

DEST="${1:-$HOME/salvataggio}"
ENCRYPT="${ENCRYPT:-0}"

c_ok=$'\033[32m'; c_warn=$'\033[33m'; c_head=$'\033[1;35m'
c_dim=$'\033[2m'; c_off=$'\033[0m'
step() { printf '\n%s==> %s%s\n' "$c_head" "$1" "$c_off"; }
ok()   { printf '    %s✓%s %s\n' "$c_ok" "$c_off" "$1"; }
warn() { printf '    %s!%s %s\n' "$c_warn" "$c_off" "$1"; }
dim()  { printf '    %s%s%s\n' "$c_dim" "$1" "$c_off"; }

mkdir -p "$DEST"
cd "$DEST" || exit 1

# ---------------------------------------------------------------------
step "Repository apt e chiavi"
# ---------------------------------------------------------------------
if sudo tar czf etc-apt-backup.tar.gz /etc/apt 2>/dev/null; then
    sudo chown "$(id -u):$(id -g)" etc-apt-backup.tar.gz
    ok "etc-apt-backup.tar.gz ($(du -h etc-apt-backup.tar.gz | cut -f1))"
else
    warn "backup di /etc/apt fallito"
fi

# ---------------------------------------------------------------------
step "Inventari dei pacchetti"
# ---------------------------------------------------------------------
dpkg --get-selections            > pacchetti-prima.txt        && ok "pacchetti-prima.txt"
apt-mark showmanual              > installati-manualmente.txt && ok "installati-manualmente.txt"
apt-mark showhold                > hold.txt                   && ok "hold.txt"
flatpak list --app --columns=application \
                                 > flatpak-prima.txt 2>/dev/null \
    && ok "flatpak-prima.txt" || dim "flatpak non installato"
[ -d /etc/greetd ] && sudo cp /etc/greetd/config.toml greetd-config.toml 2>/dev/null \
    && sudo chown "$(id -u):$(id -g)" greetd-config.toml && ok "greetd-config.toml"

# ---------------------------------------------------------------------
step "Segreti e impostazioni applicazioni"
# ---------------------------------------------------------------------
# tar preserva permessi e proprietario: fondamentale per ~/.ssh e ~/.gnupg,
# che smettono di funzionare se i modi non sono 700/600.
SECRET_PATHS=()
for p in .ssh .gnupg .gitconfig .git-credentials \
         .config/Code/User .config/gh .npmrc .cargo/credentials.toml \
         .var/app/md.obsidian.Obsidian .var/app/app.zen_browser.zen \
         .mozilla; do
    [ -e "$HOME/$p" ] && SECRET_PATHS+=("$p")
done

if [ ${#SECRET_PATHS[@]} -gt 0 ]; then
    tar czf secrets.tar.gz -C "$HOME" --numeric-owner "${SECRET_PATHS[@]}" 2>/dev/null
    chmod 600 secrets.tar.gz
    ok "secrets.tar.gz ($(du -h secrets.tar.gz | cut -f1))"
    for p in "${SECRET_PATHS[@]}"; do dim "  $p"; done

    if [ "$ENCRYPT" = "1" ]; then
        if command -v gpg >/dev/null 2>&1; then
            step "Cifratura"
            if gpg --symmetric --cipher-algo AES256 secrets.tar.gz; then
                shred -u secrets.tar.gz 2>/dev/null || rm -f secrets.tar.gz
                chmod 600 secrets.tar.gz.gpg
                ok "secrets.tar.gz.gpg — ricordati la passphrase"
            else
                warn "cifratura fallita: resta il file in chiaro"
            fi
        else
            warn "gpg non disponibile: file in chiaro"
        fi
    else
        warn "secrets.tar.gz e' IN CHIARO: contiene le tue chiavi private"
        dim  "per cifrarlo:  ENCRYPT=1 ./pre-reinstall-backup.sh $DEST"
    fi
else
    warn "nessun file di segreti trovato"
fi

# ---------------------------------------------------------------------
step "Verifica"
# ---------------------------------------------------------------------
for f in etc-apt-backup.tar.gz secrets.tar.gz secrets.tar.gz.gpg; do
    [ -f "$f" ] || continue
    case "$f" in
        *.gpg) ok "$f (cifrato, non verificabile senza passphrase)" ;;
        *) if tar tzf "$f" >/dev/null 2>&1; then ok "$f apribile"
           else warn "$f DANNEGGIATO — rifai il backup"; fi ;;
    esac
done

printf '\n%s==> Backup in %s%s\n' "$c_head" "$DEST" "$c_off"
ls -lh "$DEST"

cat <<EOF

${c_warn}Restano da copiare a mano — lo script non li tocca:${c_off}
    ~/code-projects        i tuoi progetti (controlla che siano pushati)
    ~/Documents ~/Downloads
    i vault di Obsidian, ovunque si trovino
    ~/Hyprland             solo se vuoi conservare i sorgenti

${c_warn}E soprattutto:${c_off} copia $DEST su un supporto ESTERNO
prima di formattare. Verifica di poterlo leggere da li'.
EOF
