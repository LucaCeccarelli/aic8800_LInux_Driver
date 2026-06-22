#!/bin/bash
# Install the AIC8800D80 USB WiFi+BT driver + monitor-mode app on an
# atomic/immutable Fedora system (Bazzite / Silverblue / Kinoite), WITHOUT
# layering packages or rebooting. Works around the read-only /usr by keeping
# modules + firmware in writable /var and loading them with a systemd service.
#
# Tested on: ASRock BC-250, Bazzite (Kinoite) kernel 6.17.7-ba29.
#
# Run from the repo root:  sudo bash bazzite/install.sh
set -euo pipefail

REPO="$(cd "$(dirname "$0")/.." && pwd)"
DRV="$REPO/driver/drivers/aic8800"
FWSRC="$REPO/driver/fw/aic8800D80"
KREL="$(uname -r)"

say(){ echo -e "\033[1;36m==>\033[0m $*"; }
err(){ echo -e "\033[1;31mERROR:\033[0m $*" >&2; }

[ "$(id -u)" = 0 ] && SUDO="" || SUDO="sudo"

# --- 0. prerequisites ---------------------------------------------------------
say "Checking build tools and kernel headers for $KREL"
if [ ! -e "/lib/modules/$KREL/build/Makefile" ]; then
    err "Kernel headers not found at /lib/modules/$KREL/build."
    err "On Bazzite they are usually already present; otherwise install kernel-devel."
    exit 1
fi
for t in gcc make iw; do command -v "$t" >/dev/null || { err "missing tool: $t"; exit 1; }; done

# --- 1. build the modules -----------------------------------------------------
say "Building driver (this is the shenmintao 'bluetooth' branch; builds clean on 6.15-6.17+)"
make -C "$DRV" clean >/dev/null 2>&1 || true
make -C "$DRV"
LOADFW="$DRV/aic_load_fw/aic_load_fw.ko"
FDRV="$DRV/aic8800_fdrv/aic8800_fdrv.ko"
[ -f "$LOADFW" ] && [ -f "$FDRV" ] || { err "build did not produce both .ko files"; exit 1; }

# --- 2. install modules to writable /var (with the kernel-version stamp) ------
say "Installing modules to /var/lib/aic8800"
$SUDO mkdir -p /var/lib/aic8800
$SUDO cp -f "$LOADFW" "$FDRV" /var/lib/aic8800/
$SUDO bash -c "echo '$KREL' > /var/lib/aic8800/built-for-kernel"

# --- 3. SELinux: kernel modules under /var are var_lib_t and a systemd service
#        is NOT allowed to insmod them ("Permission denied"). Relabel them. -----
if command -v getenforce >/dev/null && [ "$(getenforce)" != "Disabled" ]; then
    say "Relabeling modules for SELinux (modules_object_t)"
    $SUDO chcon -t modules_object_t /var/lib/aic8800/*.ko
    if command -v semanage >/dev/null; then
        $SUDO semanage fcontext -a -t modules_object_t '/var/lib/aic8800/.*\.ko' 2>/dev/null || true
    fi
fi

# --- 4. firmware to writable /var/lib/firmware (flat AND subdir) --------------
#  The driver ignores the kernel firmware_class.path and opens hardcoded paths;
#  it is loaded with module param aic_fw_path=/var/lib/firmware. The BT/load_fw
#  side reads <path>/<file> (flat) while the WiFi side appends aic8800D80/ — so
#  we place the files in BOTH locations.
say "Installing firmware to /var/lib/firmware"
$SUDO rm -rf /var/lib/firmware/aic8800D80
$SUDO mkdir -p /var/lib/firmware
$SUDO cp -rf "$FWSRC" /var/lib/firmware/
$SUDO cp -f /var/lib/firmware/aic8800D80/* /var/lib/firmware/

# --- 5. udev auto-eject rule (mass-storage -> WiFi mode switch) ----------------
say "Installing udev auto-eject rule"
$SUDO cp -f "$REPO/driver/aic.rules" /etc/udev/rules.d/aic.rules
$SUDO udevadm control --reload

# --- 6. systemd service to load the modules on boot ---------------------------
say "Installing and enabling aic8800.service"
$SUDO cp -f "$REPO/bazzite/aic8800.service" /etc/systemd/system/aic8800.service
$SUDO systemctl daemon-reload
$SUDO systemctl enable aic8800.service

# --- 7. monitor-mode app (worker + GUI menu + KDE launcher) -------------------
say "Installing monitor-mode toggle app"
$SUDO install -o root -g root -m 0755 "$REPO/monitor-app/aic-mode-worker.sh" /var/lib/aic8800/aic-mode-worker.sh
USER_HOME="${SUDO_USER:+$(getent passwd "$SUDO_USER" | cut -d: -f6)}"; USER_HOME="${USER_HOME:-$HOME}"
install -d "$USER_HOME/.local/bin" "$USER_HOME/.local/share/applications"
install -m 0755 "$REPO/monitor-app/aic-wifi-mode" "$USER_HOME/.local/bin/aic-wifi-mode"
# write the launcher with the real Exec path
sed "s|^Exec=.*|Exec=$USER_HOME/.local/bin/aic-wifi-mode|" \
    "$REPO/monitor-app/aic-wifi-mode.desktop" > "$USER_HOME/.local/share/applications/aic-wifi-mode.desktop"
[ -n "${SUDO_USER:-}" ] && chown -R "$SUDO_USER": "$USER_HOME/.local/bin/aic-wifi-mode" "$USER_HOME/.local/share/applications/aic-wifi-mode.desktop" 2>/dev/null || true
command -v update-desktop-database >/dev/null && update-desktop-database "$USER_HOME/.local/share/applications" 2>/dev/null || true

# --- 8. load now --------------------------------------------------------------
say "Loading the driver now"
$SUDO systemctl restart bluetooth 2>/dev/null || true
$SUDO modprobe btusb 2>/dev/null || true
$SUDO systemctl start aic8800.service || true
sleep 6

echo
say "Done. Current status:"
echo "  WiFi iface : $(ls /sys/class/net/ | grep -E 'wlan' || echo 'not up yet — replug the dongle')"
echo "  Bluetooth  : $(ls /sys/class/bluetooth/ 2>/dev/null || echo 'no hci yet — replug the dongle')"
echo
echo "If WiFi/BT did not appear, UNPLUG and REPLUG the adapter once (cold start"
echo "from mass-storage mode lets the udev rule + driver run the full sequence)."
echo "Launch the monitor-mode toggle from your app menu: 'AIC8800 WiFi Mode'."
