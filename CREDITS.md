# Credits

## Kernel driver (`driver/`)

I did **not** write the AIC8800D80 kernel driver. It is vendored here, unchanged,
for convenience and to keep this repo self-contained. Its lineage:

- **AICSemi / Tenda** — original AIC8800 vendor driver (`MODULE_LICENSE("GPL")`).
- **[goecho/aic8800_linux_drvier](https://github.com/goecho/aic8800_linux_drvier)** — community Linux driver.
- **[shenmintao/aic8800d80](https://github.com/shenmintao/aic8800d80) (`bluetooth` branch)** — the version vendored here.
  It adds the Bluetooth-mode firmware upload (so stock `btusb` brings up `hci0`),
  USB IDs for `368b:8d80/8d81`, and fixes for kernel 6.15–6.17+. See its PR #35
  for the "btusb instead of a custom aic_btusb" approach.

The driver keeps its original license. The firmware blobs under `driver/fw/` are
**proprietary AICSemi firmware**, redistributed as published by upstream.

## My contributions (MIT, see `LICENSE`)

- `bazzite/install.sh` — turn-key installer for atomic/immutable Fedora
  (Bazzite/Silverblue/Kinoite): builds the driver, stores modules + firmware in
  writable `/var`, fixes the SELinux module label, installs a boot loader service
  and udev rule — no package layering, no reboot.
- `bazzite/aic8800.service` — idempotent, kernel-version-guarded module loader.
- `monitor-app/` — `aic-mode-worker.sh` (root worker), `aic-wifi-mode` (kdialog
  GUI menu with pkexec elevation), and the `.desktop` launcher to toggle the
  adapter between **monitor** and **normal** WiFi while keeping Bluetooth up.
- `docs/patch_rwnx_main_kernel6.17.py` — content-based patcher that fixes the
  cfg80211 callback signatures (added `link_id` / `radio_idx` / `net_device`
  params) needed to build the **WiFi-only** forks (e.g. Xanderful/aic8800d80) on
  kernel 6.17. The vendored `bluetooth` branch already builds clean on 6.17, so
  this is reference material for other forks.

Developed and verified on an **ASRock BC-250** running **Bazzite (Kinoite),
kernel 6.17.7-ba29**.
