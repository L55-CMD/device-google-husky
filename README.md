# Ubuntu Touch for Google Pixel 8 Pro (husky)

This repository contains an in-progress Ubuntu Touch port for the Pixel 8 Pro (Tensor G3, zuma), derived from the Pixel 9a/tegu bring-up. The port uses a Halium 16/Android 16 base with an Ubuntu 24.04-based Ubuntu Touch rootfs.

## Current verified state

| Area | Status |
|---|---|
| Boot to Lomiri | Working, with a bottom-region scanout artifact |
| Touch | Basic UI interaction works |
| Android container | Working |
| Graphics/composer | Mali and composer3 initialize; panel handover works |
| Mobile data | Working |
| System clock/NTP | Working |
| Calls | Connects; bidirectional call audio not working |
| SMS | Permission flow needs retest on cleaned image |
| Camera app | Permission/trust-store startup fixed; capture untested |
| UI clock widget | Does not update despite correct system clock |
| Wi-Fi / Bluetooth | Not validated |
| Audio playback/microphone | Pulse devices exist; call routing incomplete |
| Sensors / vibration | Not validated |
| Camera/video acceleration | Blocked by exynos MFC IOMMU fault; node masked |
| Suspend/resume / shutdown | Not fully validated |
| USB-C DisplayPort | Not validated |
| Recovery/offline charging | Not validated |

The bottom screen defect appears to mirror fragmented content from the top of the panel, so current investigation focuses on framebuffer stride/offset/wrap rather than UI scaling.

## Release layout

CI publishes two rolling variants for every branch:

- `latest-<branch>-normal` — no bring-up instrumentation or forced rescue mode
- `latest-<branch>-debug` — labelled debug image with temporary RNDIS rescue access and tracing

Both variants include boot images, split `super.img`, Android rootfs, `SHA256SUMS`, and a `MANIFEST.txt` recording the coordinated device/kernel revisions and pinned dependency versions. See `BRINGUP.md` for flashing and verification.

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
- `RESUME-NOTES.md` — current resume entry point
- `dependencies.lock` — pinned third-party inputs and checksums
