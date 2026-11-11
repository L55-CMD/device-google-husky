# Ubuntu Touch for Google Pixel 8 Pro (husky)

This repository contains an in-progress Ubuntu Touch port for the Pixel 8 Pro (Tensor G3, zuma), derived from the Pixel 9a/tegu bring-up. The port uses a Halium 16/Android 16 base with an Ubuntu 24.04-based Ubuntu Touch rootfs.

## Current verified state

| Area | Status |
|---|---|
| Boot to Lomiri | Working, with a bottom-region scanout artifact |
| Boot/reboot stability | Working (many deliberate reboots and session restarts during bring-up) |
| Touch | Working, including edge gestures and app drawer |
| Terminal app / Morph browser | Working (used for on-device setup and downloads) |
| Android container | Working |
| Graphics/composer | Mali and composer3 initialize; panel handover works; `--enable-num-framebuffers-quirk=true` required for tear-free interaction |
| Mobile data | Working |
| System clock/NTP | Working |
| Wi-Fi | Working (validated 2026-11-10: joins WPA2 LAN, sustained SSH over Wi-Fi) |
| Bluetooth | Not validated |
| SSH access | Working on debug images via bring-up key (RNDIS `10.15.19.82`, also Wi-Fi); normal images are key-only and must not expose rescue mode |
| Calls | Connects; bidirectional call audio not working |
| SMS | Permission flow needs retest on cleaned image (trust-store fix is now in-image) |
| Camera app | Permission/trust-store startup fixed in image; capture untested |
| UI clock widget | Does not update despite correct system clock |
| Audio playback/microphone | Pulse devices exist; call routing incomplete |
| Sensors / vibration | Not validated |
| Camera/video acceleration | Blocked by exynos MFC IOMMU fault; node masked |
| Suspend/resume / shutdown | Not validated (reboots are stable; suspend untested) |
| USB-C DisplayPort | Not validated |
| Recovery/offline charging | Not validated |

The bottom screen defect appears to mirror fragmented content from the top of the panel. A full Lomiri flag matrix (framebuffer-count quirk × overlay disable, four combinations) showed the artifact is **independent of both compositor flags** — investigation now focuses on the DSC-compressed DSI stream and panel scanout, not UI scaling. Defaults remain quirk on + overlays off per the matrix findings. Evidence: bring-up host `flag-tests/` bundle (see `docs/HANDOVER.md` §5).

## Release layout

CI publishes two rolling variants for every branch:

- `latest-<branch>-normal` — no bring-up instrumentation or forced rescue mode
- `latest-<branch>-debug` — labelled debug image with temporary RNDIS rescue access and tracing

Both variants include boot images, split `super.img`, Android rootfs, `SHA256SUMS`, and a `MANIFEST.txt` recording the coordinated device/kernel revisions and pinned dependency versions. See `BRINGUP.md` for flashing and verification.

## First shell on a fresh debug flash

Debug images force usb-moded rescue mode, whose sshd on port 8022 accepts publickey only, and `/userdata` may not carry an `authorized_keys` for the bring-up key. On a fresh flash, open the Terminal app on the device and paste (one line):

```
sudo sh -c 'mkdir -p /home/phablet/.ssh && echo "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIAnvrzASLnD1GionxTigb/9oRZU92SCLEKuElJlwsabs husky-bringup" > /home/phablet/.ssh/authorized_keys && chown -R 32011:32011 /home/phablet/.ssh && chmod 700 /home/phablet/.ssh && chmod 600 /home/phablet/.ssh/authorized_keys && echo KEY-INSTALLED'
```

Expected output: `KEY-INSTALLED`. Afterwards SSH works from the bring-up host on `10.15.19.82:8022` with the `husky-rndis-key` private key (no password). The `chown 32011:32011` matters: the `phablet` user is UID/GID 32011, and sshd ignores `authorized_keys` with wrong ownership.

## Known-good baseline

The r8 kernel baseline is coordinated across:

- `lineage-kernel-manifest-husky` at `c71fde597bcf06374d26972c70f19c5e7f719d63`
- `kernel-patches-husky` at `6d9a42798c9577508ee7dd227bb8976d05cac48e`

Tag `known-good-r8-20261110` preserves the tested device/kernel combination. A newer r12 kernel is not the baseline until its separate freeze is bisected.

## Important fixes in this tree

- `kvm-arm.mode=protected` restores stock S2MPU behavior.
- A DWC3 probe-defer fix allows OTG initialization instead of leaving the UDC unattached.
- Lomiri waits for Android composer3 registration.
- Container mount, APEX, AppArmor, `libgbinder`, `vndservicemanager`, and executable-mode packaging issues are fixed.
- Debug framebuffer random-write tests are manual-only and absent from normal images.

## Security defaults

Normal images do not force USB rescue/developer mode or automatically enable SSH. SSH is key-only. Debug images are intended for isolated bring-up and must not be promoted as production defaults.

## Documentation

- `BRINGUP.md` — current build, release, checksum, and flashing workflow
- `BRINGUP-LOG.md` — authoritative current state and ordered test queue
- `BRINGUP-LOG-ARCHIVE.md` — summarized superseded diagnoses
- `docs/HANDOVER.md` — session handover: status snapshot, device access playbook, active investigations, roadmap progress
- `RESUME-NOTES.md` — current resume entry point
- `dependencies.lock` — pinned third-party inputs and checksums
