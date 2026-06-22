# AIC8800D80 Linux Driver + Monitor-Mode App (Bazzite / atomic-Fedora ready)

Get an **AIC8800D80** USB WiFi+Bluetooth dongle (sold as *EZcool UWF-619*, Tenda U11,
CUDY WU900, AX900, and many unbranded sticks) fully working on Linux — **WiFi,
Bluetooth, and WiFi monitor mode** — including on **immutable / atomic** distros
(Bazzite, Silverblue, Kinoite) where `/usr` is read-only.

This was built and verified on an **ASRock BC-250** running **Bazzite (Kinoite),
kernel 6.17.7**.

| Capability | Status |
|---|---|
| WiFi (2.4/5 GHz, WPA2/WPA3) | ✅ works |
| Bluetooth (`hci0` via stock `btusb`) | ✅ works |
| WiFi monitor mode (capture) | ✅ works (single-iface, see notes) |
| Frame injection | ⚠️ untested |
| Works on read-only atomic OS | ✅ via `/var` + systemd loader |

USB ID path: `a69c:5721` (mass-storage) → eject → `a69c:8d80` (boot ROM) →
`368b:8d81` (operational: WiFi vendor iface + 2× Bluetooth `e0` interfaces).

---

## Contents

```
driver/        AIC8800D80 kernel driver (shenmintao 'bluetooth' branch — see CREDITS.md)
monitor-app/   Monitor↔Normal toggle: GUI menu + KDE launcher + root worker
bazzite/       Atomic-OS installer (no package layering, no reboot) + systemd unit
docs/          Kernel 6.17 cfg80211 porting notes / patch (for the WiFi-only forks)
```

## Why this exists

The AIC8800 family is **not in mainline Linux**, and most third-party forks are
**WiFi-only** — their `aic_load_fw` never enables Bluetooth mode, so no `hci0`
appears. The **`bluetooth` branch** of `shenmintao/aic8800d80` sets the chip's
`BTMODE` during firmware upload so the device enumerates a **standard Bluetooth
USB interface that the kernel's stock `btusb` claims** — no custom `aic_btusb`
module needed. This repo packages that driver with a turn-key installer for
atomic distros and a desktop monitor-mode toggle.

## Quick install (Bazzite / Silverblue / Kinoite)

```bash
git clone https://github.com/DeDuplicate/aic8800_LInux_Driver-MonMODE.git
cd aic8800_LInux_Driver-MonMODE
sudo bash bazzite/install.sh
# then UNPLUG + REPLUG the dongle once
```

This builds the modules, stores them + firmware under writable `/var`, fixes the
SELinux label, installs a boot-time loader service + udev auto-eject rule, and
installs the monitor-mode app. No `rpm-ostree` layering and no reboot required.

On a normal (non-atomic) distro you can instead use the upstream flow in
`driver/README.md` (`make && sudo make install`).

## The three atomic-OS gotchas this solves

1. **Read-only `/usr`** — `/lib/modules` and `/lib/firmware` can't be written.
   Modules live in `/var/lib/aic8800`, firmware in `/var/lib/firmware`, loaded by
   a systemd service.
2. **Firmware path** — the driver ignores the kernel `firmware_class.path` and
   opens hardcoded paths, so it's loaded with `aic_fw_path=/var/lib/firmware`.
   Firmware is placed both flat and in an `aic8800D80/` subdir (the BT and WiFi
   code paths look in different places).
3. **SELinux (Enforcing)** — a `.ko` under `/var` is labeled `var_lib_t`, and a
   confined systemd service gets **`insmod: Permission denied`** loading it (an
   interactive root shell is unconfined, so it loads fine — a misleading trap).
   Fix: relabel to `modules_object_t` (`chcon` + persistent `semanage fcontext`).

## Monitor mode

Monitor mode works, but the driver **does not allow a separate monitor interface
alongside the managed one** (`iw ... interface add mon0 type monitor` fails with
`-22`; "Monitor+Data" is disabled). You must convert the single interface:

```bash
sudo nmcli device set wlan_cudy managed no
sudo ip link set wlan_cudy down
sudo iw dev wlan_cudy set type monitor
sudo ip link set wlan_cudy up
sudo iw dev wlan_cudy set channel 6          # or let airodump-ng hop
sudo tcpdump -i wlan_cudy -e                 # or: sudo airodump-ng wlan_cudy
```

The **monitor-app** does this for you from a GUI menu (KDE app launcher:
*"AIC8800 WiFi Mode (Monitor / Normal)"*), with **Enable Monitor / Return to
Normal / Status** options. Bluetooth is on a separate USB interface and keeps
working in either mode.

> ⚠️ The AIC driver can hit a NULL-pointer oops in `rwnx_rxdataind_aicwf` if you
> *rapidly* toggle monitor↔managed or USB-reset while frames are flowing, which
> can wedge the adapter. Normal click-through use is fine; if it ever wedges,
> unplug/replug the dongle.

## After a kernel update

The out-of-tree module is tied to the kernel's vermagic; the loader service skips
loading on a mismatch. Rebuild:

```bash
sudo bash bazzite/install.sh
```

(or build a DKMS/RPM with the upstream `driver/bazzite/aic8800d80.spec` +
`driver/dkms.conf` if you prefer auto-rebuild across kernel updates).

## Credits & license

The kernel driver is **not my work** — see [CREDITS.md](CREDITS.md) (Tenda →
goecho → shenmintao lineage), and the kernel firmware blobs are proprietary AIC,
redistributed from upstream. My original contributions (the atomic-OS installer,
systemd unit, SELinux fix, and the monitor-mode app) are MIT-licensed; see
[LICENSE](LICENSE). The driver retains its original (GPL) license under `driver/`.
