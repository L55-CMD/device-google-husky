# Husky bring-up log

## Current state — 2026-11-10

### Known-good coordinated revisions

| Repository | Revision |
|---|---|
| `device-google-husky` | `a9d9187556e684352f26f21370c5cf90b259f14d` before cleanup; cleaned baseline follows in `main` |
| `lineage-kernel-manifest-husky` | `c71fde597bcf06374d26972c70f19c5e7f719d63` |
| `kernel-patches-husky` | `6d9a42798c9577508ee7dd227bb8976d05cac48e` |

Tag these revisions as `known-good-r8-20261110`. The port remains on the r8 kernel until the separate r12 freeze is understood.

### Working

- UT boots into Lomiri.
- Basic touch interaction works.
- Android LXC container starts; vendor/system_dlkm/vendor_dlkm mount.
- Composer3 registers and Lomiri waits for it before startup.
- Mobile data works.
- System clock and NTP are correct; the shell clock advances.
- RNDIS rescue networking works in explicitly labelled debug builds after binding Microsoft RNDIS on the host and installing an SSH key.
- AppArmor profiles load after replacing the non-system-image cache helper with a no-op.
- Camera trust-store now starts after restoring the executable Mir client platform.

### Current defects

1. Bottom screen region is fragmented and appears to mirror content from the top. Treat this as framebuffer wrap/stride/offset scanout corruption until proven otherwise.
2. Calls connect, but bidirectional call audio does not work; normal PulseAudio speaker/mic ports exist, while telephony patch routing is incomplete.
3. Camera and Messaging open permission settings that expose no usable toggles. Camera confinement and trust-store startup are now fixed; remaining permission behavior needs retesting from a clean image.
4. Lomiri's on-screen clock does not update even though the system clock advances.
5. Wi-Fi, Bluetooth, sensors, camera capture, suspend/resume, charging states, and USB-C DisplayPort are not validated.
6. Camera/video acceleration remains blocked by the exynos MFC IOMMU fault; only the MFC node is masked.

### Required runtime fixes now in normal image

- `kvm-arm.mode=protected`
- DWC3 child-readiness `-EPROBE_DEFER` patch
- composer-ready wait in `lsc-wrapper`
- executable `vndservicemanager` and `usbdp_gbinder`
- valid `libgbinder` soname links
- Android APEX duplicate-mount handling
- AppArmor cache-helper no-op
- narrowed MFC V4L2 mask
- executable Mir client platform bind fix

### Operational notes

- Normal and debug images are separate rolling releases:
  - `latest-<branch>-normal`
  - `latest-<branch>-debug`
- Debug images include temporary RNDIS rescue networking and tracing. They must remain clearly labelled and must not be treated as production defaults.
- SSH is key-only. Install an authorized key before enabling either SSH path.
- Do not reintroduce automatic framebuffer random writes, infinite vibrator heartbeats, or unconditional `/dev/video*` masking.
- Superseded diagnoses are summarized in `BRINGUP-LOG-ARCHIVE.md`.

## Next display tests

Run each configuration from a clean boot or a LightDM restart, and record a photo, compositor log, composer3 logcat, and DRM state:

1. quirk `true`, overlays `true` — current baseline
2. quirk `true`, overlays `false`
3. quirk `false`, overlays `true`
4. quirk `false`, overlays `false`

Do not alter GridUnit/DPR until scanout geometry is correct. Only test refresh-rate and native-resolution changes after removing framebuffer-debug contamination and capturing the baseline above.
