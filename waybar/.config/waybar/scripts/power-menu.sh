#!/bin/bash
# Power menu — funziona sia su Hyprland che su sway.
# Durante la migrazione entrambe le sessioni restano avviabili, quindi
# il logout rileva il compositore invece di assumerlo.

chosen=$(echo -e "  Logout\n  Suspend\n  Reboot\n  Shutdown" | \
    wofi --dmenu -i -p "Power" --width 200 --height 180)

logout() {
    if [ -n "${SWAYSOCK:-}" ] && command -v swaymsg >/dev/null 2>&1; then
        swaymsg exit
    elif command -v hyprctl >/dev/null 2>&1; then
        hyprctl dispatch exit
    else
        loginctl terminate-session "${XDG_SESSION_ID:-self}"
    fi
}

case $chosen in
    *Logout)
        logout
        ;;
    *Suspend)
        systemctl suspend
        ;;
    *Reboot)
        systemctl reboot
        ;;
    *Shutdown)
        systemctl poweroff
        ;;
esac
