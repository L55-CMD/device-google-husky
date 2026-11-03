# Ubuntu Touch for Google Pixel 9a (tegu)

This is an experiment of porting Ubuntu Touch to the Google Pixel 9a (codename tegu).
It is very much a work in progress and I will say this upfront:
I'm not experienced with Android development. AI (Claude) did a lot of work, so do expect slop in places.

## Status

This is not a port that is ready for general use. OTA updates probably don't work (untested).

|                                   |                                |                             |
|-----------------------------------|--------------------------------|-----------------------------|
| **Actors**                        | ✅ 24+ hours battery lifetime  | **Network (cont.)**         |
| ✅ Manual brightness              | ✅ 7+ days stability           | ❓ Hotspot                  |
| ❌ Torchlight                     |                                | ❓ NFC                      |
| ✅ Vibration                      | **GPU**                        | ✅ WiFi                     |
|                                   | ✅ Boot into UI                |                             |
| **Camera**                        | ⚠️ Hardware video playback^4   | **Sensors**                 |
| ✅ Flashlight                     |                                | ❓ Automatic brightness     |
| ✅ Photo                          | **Misc**                       | ❌ Fingerprint reader       |
| ⚠️ Video^1                        | ✅ AppArmor patches            | ❓ GPS                      |
| ✅ Switching between cameras^2    | ✅ Battery percentage          | ❓ Proximity                |
|                                   | ❓ Offline charging            | ✅ Rotation                 |
| **Cellular**                      | ✅ Online charging             | ✅ Touchscreen              |
| ✅ Carrier info, signal strength  | ✅ Wireless Charging           | ❌ Double touch to wake     |
| ✅ Data connection                | ❓ Recovery image              |                             |
| ❓ Dual SIM functionality         | ❓ Reset to factory defaults   | **Sound**                   |
| ✅ Incoming, outgoing calls       | ❓ RTC time                    | ✅ Earphones                |
| ❓ LTE calling (VoLTE)            | ✅ Shutdown / Reboot           | ✅ Loudspeaker              |
| ❓ MMS in, out                    | ❓ Wireless External monitor   | ✅ Microphone               |
| ❓ PIN unlock                     | ❌ Waydroid^5                  | ✅ Volume control           |
| ⚠️ SMS in, out^3                  | ✅ KVM acceleration            |                             |
| ✅ Change audio routings          |                                | **USB**                     |
| ✅ Voice in calls                 | **Network**                    | ❓ MTP access               |
| ✅ Volume control in calls        | ✅ Bluetooth                   | ❓ ADB access               |
|                                   | ❓ Flight mode                 | ✅ Wired External monitor^6 |
|                                   |                                |                             |

✅ Working
❌ Not Working
⚠️ Partial
❓ Untested / Unknown

^1: When starting the first recording, the Camera app hangs for ~1 minute until the audio permission dialog pops up. Afterwards, video records fine in 4k, but the recording is missing audio.

^2: Switching between front and main works, ultrawide not accessible because it is exposed as a single camera
and the Ubuntu Touch camera doesn't support 0.x zoom ratios.

^3: SMS sending works. I don't have a SIM card that can receive SMS at the moment.

^4: Hardware decoding seems to work, but CPU usage for rendering itself seems quite high.

^5: Waydroid starts with a [custom build](https://git.deusch.me/ubports/waydroid-build) and patches to the Waydroid
init script. Those are **not** included in the current overlay.

^6: A custom resolution can be set via `setprop vendor.display.external.preferred_mode 2560x1440@59` in the Terminal.

Also see the [issues](https://git.deusch.me/ubports/device-google-tegu/issues) for known problems.

## Build caveats

This port does NOT use the blessed way of building Ubuntu Touch.
The reason is that the Ubuntu Touch build tools don't currently support Android 16
and we need to do some adjustments to the kernel build itself and include custom halium patches.

Instead, we [manually build the kernel](https://git.deusch.me/ubports/lineage-kernel-manifest-tegu)
for tegu based on LineageOS sources and some [patches](https://git.deusch.me/ubports/kernel-patches-tegu).
This gives us a zip containing `Image.lz4`, `boot.img`, `dtb.img`, `dtbo.img`, `system_dlkm.img`,
`vendor_dlkm.flatten.img` and `vendor_kernel_boot.img`.

Of those, `dtbo.img`, `system_dlkm.img`, `vendor_dlkm.flatten.img` and `vendor_kernel_boot.img` are flashed
verbatim. `dtb.img` is *not* flashed (the device has no standalone `dtb` partition); it's used as a source
and embedded into `vendor_boot.img` below. The kernel's own `boot.img` is discarded - Android 16 uses
boot-image header v4, which splits the kernel, the DTB and the ramdisk across separate partitions, so we
repack them ourselves:

- `boot.img` is rebuilt from the extracted `Image.lz4` only (kernel, no ramdisk, no DTB).
- `init_boot.img` carries the ramdisk: Halium's generic [`initrd.img-touch-arm64`](https://github.com/halium/initramfs-tools-halium)
  with this repo's `ramdisk-overlay/` cpio-appended and re-LZ4-compressed.
- `vendor_boot.img` is rebuilt locally so we can embed the DTB (the freshly-built `dtb.img` from the kernel
  zip), inject bootconfig, and add the contents of `vendor-ramdisk-overlay/`.
  The `google-tegu.dtb` in this repo is currently unused (it was copied from LineageOS).

All three are produced by `make-bootimage.sh` in [halium-generic-adaptation-build-tools](https://gitlab.com/ubports/porting/community-ports/halium-generic-adaptation-build-tools).
The local patch in `build-patches/halium-generic-adaptation-build-tools/` only teaches the surrounding scripts about our patches
(local GSI tarball, libhybris overlay, clang revision).

Finally, CI downloads a LineageOS 23.2 zip and extracts `vendor`, `system_ext` and `product` from its
`payload.bin`. Those, together with the Ubuntu Touch `system.img`, `system_dlkm.img` and
`vendor_dlkm.flatten.img`, are fused into a single flashable `super.img` via `lpmake`
(see `scripts/build-super-image.sh`).

## Patches

The system includes a bunch of patches layered on top of the latest android9plus rootfs:

- Halium 16 patches: these are currently fetched from a [zip file](https://anubis.steffend.me/ubports-tegu/libhybris-16-update.tar.xz),
  because I deleted the temporay cloud VM I used when building the patches. I need to revisit the build.
- Device specific overlays:
  - `libgbinder-radio.so.1` [patched to relax type checks](https://git.deusch.me/ubports/libgbinder-readio/commit/cf0a1d54d027c5724ab5f068d8b2b2cb555c52f0)
  - `libgbinder.so` overlaid with v1.1.45 (most likely unnecessary now, since 1.1.45 is already included in the rootfs)
  - pulseaudio `module-droid-aidl.so` custom AIDL pulseaudio module (I think it leaks memory) - I wasn't able to create a working `audio_policy_configuration.xml` for tegu. Tegu only seems to support AIDL for audio.
  - sensorfwd 0.15.1 ships the AIDL backend patch but does not include commit `16b56bc` (backend split that drops the blocking `gbinder_servicemanager_wait` on hwbinder). On A16 there is no `hwservicemanager`, so the wait blocked forever. Rebuilt `libhidlsensorfw-qt5.so.1.0.0` with sailfishos/sensorfw PR #31 backends, overlaid into `/usr/lib/aarch64-linux-gnu/`.
  - Mali TLS - Vendor `.so`s use ELF TLS (initial-exec), reading `tpidr_el0` directly. In a libhybris environment that's glibc's TCB, not bionic's — segfault. Worked around via `LD_PRELOAD`. This should be re-visited, as there's already a `libtls-padding.so`, which does something similar. Right now, we overlay `libhybris-common.so.1` over `libtls-padding.so`. Patches from [upstream PR](https://github.com/libhybris/libhybris/pull/575).

### Device quirks

Some notes on device specific quirks and their workarounds in this port.

#### Kernel / cmdline

- **Mali GPU PID-namespace crash** - `gpu_dvfs_kctx_init` in `pixel_gpu_dvfs_metrics.c` calls `find_get_pid()` + `get_pid_task()` to attribute DVFS power to a UID. GPU clients in the Halium LXC live in a separate PID namespace, so `get_pid_task()` returns NULL and the next `task->cred->uid` deref oopses. [Patched the Pixel Mali platform code](https://git.deusch.me/ubports/kernel-patches-tegu/src/branch/halium-tegu/private/google-modules/0001-gpu-handle-PID-namespace-task-lookup-failure.patch) to fall back to `GLOBAL_ROOT_UID` when the task lookup fails — the UID is only used for per-UID power metrics, so it's cosmetic.
- **`vendor_dlkm.flatten.img` was missing `etc/`** - Without `etc/init.insmod.tegu.cfg`, `insmod.sh` never set `vendor.all.modules.ready=1`, the cs40l26 vibrator HAL stayed disabled and there was no haptic feedback. Patched kleaf's [`build_flattened_dlkm_image()`](https://git.deusch.me/ubports/kernel-patches-tegu/src/branch/halium-tegu/build/kernel/0002-build_utils-copy-etc-into-flattened-DLKM-image.patch) to also copy `etc/` into the flatten staging dir.
- **Kernel binder patched for AppArmor** - Vendor binaries (HWC3, etc.) link the stock vendor libbinder, which sets `FLAT_BINDER_FLAG_TXN_SECURITY_CTX` on parceled binder objects. With AppArmor as the active LSM, `security_secid_to_secctx()` returns `-EINVAL`, the kernel returns `BR_FAILED_REPLY` for every transaction, and HWC3 crash-loops. Patched `drivers/android/binder.c` to set `secctx = NULL; secctx_sz = 0; ret = 0` instead of `goto err_get_secctx_failed`. This may not be necessary after some more SELinux patches.

See https://git.deusch.me/ubports/kernel-patches-tegu.

#### Hardware / userspace

- **Touch co-processor edge filtering** - Google's GTI touch-offload pipeline (Synaptics TCM → co-processor → twoshay → v4l2) suppressed mid-edge swipes, breaking Lomiri's app drawer / app switcher gestures. Disabling `offload_enabled` and `v4l2_enabled` in the GTI sysfs routes raw events straight to `/dev/input/event3`. Persisted via the `device-hacks` script in the overlay.
- **WiFi works but NetworkManager has to ignore an aware interface** - A `aware_nmi*` interface gets exposed by the driver and causes a kernel panic when NetworkManager touches it. We tell NM to leave it alone via `overlay/system/etc/NetworkManager/conf.d/10-ignore-aware-nmi.conf` (`unmanaged-devices=interface-name:aware_nmi*`).

## Flashing

I flashed the latest Android 16 from Google before doing this (CP1A.260405.005 (15001963)).

Download the latest images CI artifact from [the releases](https://git.deusch.me/ubports/device-google-tegu/releases/tag/latest-main).

Extract the zip, cd into the folder. Then, from bootloader, flash via fastboot:

```bash
$ fastboot flash boot boot.img
Sending 'boot_a' (65536 KB)                        OKAY [  1.522s]
Writing 'boot_a'                                   OKAY [  0.282s]
Finished. Total time: 1.830s
$ fastboot flash dtbo dtbo.img
Sending 'dtbo_a' (1573 KB)                         OKAY [  0.049s]
Writing 'dtbo_a'                                   OKAY [  0.049s]
Finished. Total time: 0.125s
$ fastboot flash init_boot init_boot.img
Sending 'init_boot_a' (8192 KB)                    OKAY [  0.201s]
Writing 'init_boot_a'                              OKAY [  0.071s]
Finished. Total time: 0.300s
$ fastboot flash vendor_boot vendor_boot.img
Sending 'vendor_boot_a' (17112 KB)                 OKAY [  0.395s]
Writing 'vendor_boot_a'                            OKAY [  0.102s]
Finished. Total time: 0.551s
$ fastboot flash vendor_kernel_boot vendor_kernel_boot.img
Sending 'vendor_kernel_boot_a' (7936 KB)           OKAY [  0.190s]
Writing 'vendor_kernel_boot_a'                     OKAY [  0.071s]
Finished. Total time: 0.296s
$ fastboot flash super super.img
Sending sparse 'super' 1/22 (252321 KB)            OKAY [  5.948s]
Writing 'super'                                    OKAY [  1.635s]
Sending sparse 'super' 2/22 (254732 KB)            OKAY [  6.152s]
Writing 'super'                                    OKAY [  1.721s]
Sending sparse 'super' 3/22 (252687 KB)            OKAY [  6.010s]
Writing 'super'                                    OKAY [  1.537s]
Sending sparse 'super' 4/22 (252909 KB)            OKAY [  6.106s]
Writing 'super'                                    OKAY [  2.064s]
Sending sparse 'super' 5/22 (253817 KB)            OKAY [  6.286s]
Writing 'super'                                    OKAY [  2.130s]
Sending sparse 'super' 6/22 (254745 KB)            OKAY [  5.876s]
Writing 'super'                                    OKAY [  1.082s]
Sending sparse 'super' 7/22 (233973 KB)            OKAY [  5.408s]
Writing 'super'                                    OKAY [  0.951s]
Sending sparse 'super' 8/22 (254936 KB)            OKAY [  5.855s]
Writing 'super'                                    OKAY [  1.203s]
Sending sparse 'super' 9/22 (254126 KB)            OKAY [  5.952s]
Writing 'super'                                    OKAY [  1.262s]
Sending sparse 'super' 10/22 (254972 KB)           OKAY [  6.038s]
Writing 'super'                                    OKAY [  1.592s]
Sending sparse 'super' 11/22 (254972 KB)           OKAY [  5.850s]
Writing 'super'                                    OKAY [  1.005s]
Sending sparse 'super' 12/22 (244276 KB)           OKAY [  5.592s]
Writing 'super'                                    OKAY [  1.006s]
Sending sparse 'super' 13/22 (254972 KB)           OKAY [  5.855s]
Writing 'super'                                    OKAY [  1.663s]
Sending sparse 'super' 14/22 (242440 KB)           OKAY [  5.559s]
Writing 'super'                                    OKAY [  1.372s]
Sending sparse 'super' 15/22 (226328 KB)           OKAY [  5.219s]
Writing 'super'                                    OKAY [  0.857s]
Sending sparse 'super' 16/22 (223292 KB)           OKAY [  5.108s]
Writing 'super'                                    OKAY [  0.882s]
Sending sparse 'super' 17/22 (237301 KB)           OKAY [  5.428s]
Writing 'super'                                    OKAY [  0.935s]
Sending sparse 'super' 18/22 (240952 KB)           OKAY [  5.519s]
Writing 'super'                                    OKAY [  5.447s]
Sending sparse 'super' 19/22 (254972 KB)           OKAY [  5.827s]
Writing 'super'                                    OKAY [  0.986s]
Sending sparse 'super' 20/22 (231796 KB)           OKAY [  5.357s]
Writing 'super'                                    OKAY [  0.906s]
Sending sparse 'super' 21/22 (240340 KB)           OKAY [  5.521s]
Writing 'super'                                    OKAY [  0.940s]
Sending sparse 'super' 22/22 (98892 KB)            OKAY [  2.260s]
Writing 'super'                                    OKAY [  0.447s]
Finished. Total time: 155.052s
$ fastboot erase userdata
Erasing 'userdata'                                 OKAY [  0.189s]
Finished. Total time: 0.190s
$ fastboot reboot
Rebooting                                          OKAY [  0.000s]
Finished. Total time: 0.051s
```
