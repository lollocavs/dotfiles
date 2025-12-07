#!/bin/bash

chosen=$(echo -e "  Logout\n  Suspend\n  Reboot\n  Shutdown" | \
    wofi --dmenu -i -p "Power" --width 200 --height 180)

case $chosen in
    *Logout)
        hyprctl dispatch exit
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
