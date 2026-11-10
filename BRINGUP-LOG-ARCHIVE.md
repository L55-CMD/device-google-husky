# Husky bring-up archive

This file summarizes superseded or historical diagnoses. The authoritative current state is in `BRINGUP-LOG.md`.

## Kernel bring-up history

- Early r8 kernels froze during init because `kvm-arm.mode=nvhe` left S2MPU protection incomplete. Stock behavior is restored with `kvm-arm.mode=protected`.
- Thin LTO, toolchain version, kleaf revision, module post-processing, and the CFI-off experiment were investigated and are not the accepted fix. CFI remains enabled.
- `dwc3-exynos` returned success when the DWC3 child was not ready. The accepted kernel patch returns `-EPROBE_DEFER`; this fixed UDCs remaining `not attached`.
- The known-good kernel combination is:
  - manifest `c71fde597bcf06374d26972c70f19c5e7f719d63`
  - patches `6d9a42798c9577508ee7dd227bb8976d05cac48e`

## Ubuntu Touch integration history

- usb-moded initially selected MTP or charging after rescue mode because the persistent/default mode was rewritten. The intended debug marker is `.force-ssh`; `.force-adb` must not coexist.
- The correct USB environment path is `/etc/default/usb-moded.d/`; `/etc/usb-moded.d/` is not read for those environment values.
- The Android rootfs must contain `fstab.zuma` and is preferred from `/userdata/android-rootfs.img` when present.
- Container scripts, `libgbinder` soname links, APEX duplicate mounts, `lsc-wrapper`, `vndservicemanager`, and `usbdp_gbinder` all required executable modes in the generated image.
- Composer registration requires executable `vndservicemanager`; Lomiri waits for `android.hardware.graphics.composer3.IComposer/default` before starting.
- `gst-plugin-scan` can trigger a fatal exynos MFC IOMMU fault. Until that driver issue is fixed, the MFC V4L2 node is masked at boot. Do not mask unrelated video devices.
- The Mir client platform module shipped without the executable bit, which broke Mir clients such as trust-store. The runtime now binds an executable copy from userdata until the rootfs package mode is fixed.
- AppArmor profile loading was blocked by a channel-cache helper that returned failure on non-system-image builds. The helper is a no-op for this rootfs.

## Display observations retained for investigation

- Lomiri reaches the panel through Android composer3 and Mali.
- DRM initially reports a `1008x2244` panel mode with RGBA buffers.
- The current artifact is confined to the bottom region and appears to mirror fragmented content from the top of the screen. That points to scanout wrap/stride/offset handling rather than panel damage or UI scaling.
- A debug service once wrote random data to `/dev/fb0`; it has been moved to a manual debug-only test and removed from normal boots.
