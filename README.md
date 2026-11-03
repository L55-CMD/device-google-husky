# Ubuntu Touch for Google Pixel 8 Pro (husky)

This is a port of Ubuntu Touch to the Google Pixel 8 Pro (codename husky, Tensor G3 / zuma),
forked from the [Pixel 9a (tegu) port](https://git.deusch.me/ubports/device-google-tegu).
Like its parent it is very much a work in progress.

## Status

**Early bring-up. Nothing below is confirmed on husky yet.** The feature matrix from the
tegu port is kept as a *target* checklist only; entries will be re-validated one by one on
the Pixel 8 Pro (zuma differs from zumapro in touch, display, audio and sensor plumbing).

|                                   |                                |                             |
|-----------------------------------|--------------------------------|-----------------------------|
| **Actors**                        | ❓ Battery lifetime            | **Network (cont.)**         |
| ❓ Manual brightness              | ❓ Stability                   | ❓ Hotspot                  |
| ❓ Torchlight                     |                                | ❓ NFC                      |
| ❓ Vibration                      | **GPU**                        | ❓ WiFi                     |
|                                   | ❓ Boot into UI                |                             |
| **Camera**                        | ❓ Hardware video playback     | **Sensors**                 |
| ❓ Flashlight                     |                                | ❓ Automatic brightness     |
| ❓ Photo                          | **Misc**                       | ❓ Fingerprint reader       |
| ❓ Video                          | ❓ AppArmor patches            | ❓ GPS                      |
| ❓ Switching between cameras      | ❓ Battery percentage          | ❓ Proximity                |
|                                   | ❓ Offline charging            | ❓ Rotation                 |
| **Cellular**                      | ❓ Online charging             | ❓ Touchscreen              |
| ❓ Carrier info, signal strength  | ❓ Wireless Charging           | ❓ Double touch to wake     |
| ❓ Data connection                | ❓ Recovery image              |                             |
| ❓ Dual SIM functionality         | ❓ Reset to factory defaults   | **Sound**                   |
| ❓ Incoming, outgoing calls       | ❓ RTC time                    | ❓ Earphones                |
| ❓ LTE calling (VoLTE)            | ❓ Wireless External monitor   | ❓ Loudspeaker              |
| ❓ MMS in, out                    | ❓ Waydroid                    | ❓ Microphone               |
| ❓ PIN unlock                     | ❓ KVM acceleration            | ❓ Volume control           |
| ❓ SMS in, out                    |                                |                             |
| ❓ Change audio routings          | **Network**                    |                             |
| ❓ Voice in calls                 | ❓ Bluetooth                   | **USB**                     |
| ❓ Volume control in calls        | ❓ Flight mode                 | ❓ MTP access               |
|                                   |                                | ❓ ADB access               |
|                                   |                                | ❓ Wired External monitor   |

✅ Working
❌ Not Working
⚠️ Partial
❓ Untested / Unknown

Known tegu quirks that must be re-checked on husky during bring-up:

- GTI touch co-processor edge filtering (`device-hacks` sysfs writes)
- `aware_nmi*` NetworkManager rule
- cs40l26 vibrator / hfd-service LED crash workaround
- sensorfwd / bluebinder / AIDL HAL service names (`bcmbtlinux` etc.)
- AIDL-only audio HAL (pulse `module-droid-card-aidl`)
- USB-C DisplayPort (`usbdp_gbinder`, `exynos_drm.dp_rate=2`, UART disable)

## Differences from the tegu port

Same build pipeline and Halium 16/Android 16 base. Device-specific changes:

- `deviceinfo`: codename `husky`, OS patch level matches the LineageOS 23.2 husky build,
  `google-husky.dtb` placeholder (unused, populated from the kernel zip at build time —
  the committed `google-tegu.dtb` was dropped for the same reason).
- Recovery ramdisk: `init.recovery.husky.rc` / `init.recovery.zuma.rc` (zuma uses the same
  `11210000.dwc3` USB controller and `13200000.ufs` boot device as zumapro).
- Overlay: systemd units/ Drop-ins renamed `tegu-*` → `husky-*`; `build.prop`/`prop.halium`
  device props set to `husky`; deviceinfo yaml for Lomiri shell scaling
  (GridUnit 26 / DPR 2.75 — adjust after first boot).
- Super partition layout is identical (`8531214336` bytes, group `8527020032`).

## Build

Identical to tegu (see the [tegu README](https://git.deusch.me/ubports/device-google-tegu)
for the full description):

- The kernel is built by `lineage-kernel-manifest-husky` CI (LineageOS gs-6.1 zuma kernel
  + halium patches from `kernel-patches-husky`) and published as `kernel.zip` to the
  `generic/husky` package registry.
- This repo's CI fetches the kernel, the Halium 16 GSI system image, the libhybris update
  and a LineageOS 23.2 husky zip, repacks `boot.img`/`init_boot.img`/`vendor_boot.img`,
  fuses `super.img` and publishes `images.zip` as a rolling release.

> NOTE: the LineageOS zip URL in the CI config will rot once LineageOS drops the build
> from its mirror (only the last ~3 builds are kept). Mirror it like the tegu zip on
> `anubis.steffend.me` and update `LINEAGE_ZIP_URL`.

## Flashing

Flash the latest **Android 16** stock image from Google first (both slots), then download
`boot-images.zip` and all `super.img.part-*` files from [the releases](https://github.com/l55-cmd/device-google-husky/releases/tag/latest-main)
(assets are split because of GitHub's 2 GB per-file limit), and from the bootloader:

```bash
unzip boot-images.zip
cat super.img.part-* > super.img
fastboot flash boot boot.img
fastboot flash dtbo dtbo.img
fastboot flash init_boot init_boot.img
fastboot flash vendor_boot vendor_boot.img
fastboot flash vendor_kernel_boot vendor_kernel_boot.img
fastboot flash super super.img
fastboot erase userdata
fastboot reboot
```

For USB-C display testing later: `fastboot oem uart disable` (see the tegu port's issue #9).
