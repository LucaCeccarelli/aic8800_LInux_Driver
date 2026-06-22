#!/bin/bash
# AIC8800D80 WiFi mode worker (runs as root via pkexec/sudo).
# Switches the AIC WiFi interface between monitor and managed mode.
# Bluetooth (hci0, a separate USB interface) is never touched here.
set -u
export PATH=/usr/sbin:/usr/bin:/sbin:/bin

detect_iface() {
    local d drv
    for d in /sys/class/net/*; do
        [ -e "$d/device/driver" ] || continue
        drv=$(basename "$(readlink -f "$d/device/driver")")
        if [ "$drv" = "aic8800_fdrv" ]; then basename "$d"; return; fi
    done
    echo wlan_cudy
}
IFACE=$(detect_iface)

mode_of()    { iw dev "$IFACE" info 2>/dev/null | awk '/type/{print $2}'; }
chan_of()    { iw dev "$IFACE" info 2>/dev/null | sed -n 's/.*channel /channel /p' | head -1; }
conn_of()    { nmcli -t -f DEVICE,STATE,CONNECTION device status 2>/dev/null \
                 | awk -F: -v i="$IFACE" '$1==i{print $2" / "$3}'; }

case "${1:-}" in
    monitor)
        CHAN="${2:-}"
        nmcli device set "$IFACE" managed no >/dev/null 2>&1
        ip link set "$IFACE" down
        iw dev "$IFACE" set type monitor
        ip link set "$IFACE" up
        if [ -n "$CHAN" ]; then iw dev "$IFACE" set channel "$CHAN" 2>&1; fi
        echo "WiFi interface : $IFACE"
        echo "Mode           : $(mode_of)"
        echo "Channel        : $(chan_of)"
        ;;
    managed)
        ip link set "$IFACE" down
        iw dev "$IFACE" set type managed
        ip link set "$IFACE" up
        nmcli device set "$IFACE" managed yes >/dev/null 2>&1
        sleep 2
        echo "WiFi interface : $IFACE"
        echo "Mode           : $(mode_of)"
        echo "Connection     : $(conn_of)"
        ;;
    status)
        echo "WiFi interface : $IFACE"
        echo "Mode           : $(mode_of)"
        echo "Channel        : $(chan_of)"
        echo "Connection     : $(conn_of)"
        echo "Bluetooth (hci): $(ls /sys/class/bluetooth/ 2>/dev/null | tr '\n' ' ')"
        ;;
    *)
        echo "usage: $0 {monitor [channel]|managed|status}"; exit 2 ;;
esac
