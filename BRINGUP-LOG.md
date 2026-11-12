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

1. Bottom screen region is fragmented and appears to mirror content from the top. **Isolation results (2026-11-10 night):** present in all four Lomiri flag combinations (quirk/overlays matrix, see `bootdebug/flag-tests/MATRIX.md` on bring-up host); visible from the boot-splash window before Lomiri starts; unaffected by `vendor.display.preferred_mode` / `persist.vendor.display.primary.boot_config` props (composer3 HAL ignores them); unchanged at 1008x2244@120 in every test. DRM geometry is consistent (fb 1008x2256, plane 2244 lines @ +0+0, DSI-1 mode 1008x2244x120); dmesg shows clean panel bring-up with no underrun/DSC errors. All panel modes use DSC (HK3_FHD_DSC / HK3_WQHD_DSC). Working theory: compressed DSI stream ends before the last panel lines, leaving stale content in the bottom band. **Next: confirm whether LineageOS on the same kernel is clean (slot a boot), then bisect DSC/mode config.**
2. Calls connect, but bidirectional call audio does not work; normal PulseAudio speaker/mic ports exist, while telephony patch routing is incomplete.
3. Camera and Messaging open permission settings that expose no usable toggles. Camera confinement and trust-store startup are now fixed; remaining permission behavior needs retesting from a clean image.
4. Lomiri's on-screen clock does not update even though the system clock advances.
5. Bluetooth, sensors, camera capture, suspend/resume, charging states, and USB-C DisplayPort are not validated. **Wi-Fi works (2026-11-10): phone joined LAN, SSH over Wi-Fi functional.**
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

## 2026-11-12 update

### Display experiments (kernel CI, queued — branches prepared, not yet pushed)

- `test-display-force60` (kernel-patches + manifest): hides both 120Hz
  HK3 modes → panel exposes only 1344x2992x60 + 1008x2244x60.
  Isolates refresh rate / TE2 / op-hs as the artifact cause.
- `test-display-wqhd` (alternative branch): hides FHD + WQHD120 →
  WQHD60 only. Isolates the FHD DSC path.
- Both are `#if 0` toggle patches on `panel-google-hk3.c` (the driver
  actually bound via `google,hk3` compatible; `panel-gs-hk3.c` is NOT
  used by husky). Kernel side exonerated by 2026-11-11 register audit.
- Audit side-note: `hk3_init` hardcodes the WQHD CASET/PASET address
  window for FHD too — but the `gs_` rewrite (panel-gs-hk3.c) does the
  same and ships in Android, so it is NOT a plausible artifact cause.
  Deprioritized; the force-60Hz and WQHD experiments come first.

### Defect #2 (call audio) — root cause found offline

The Halium 16 GSI ships with the framework audio stack stripped:
no `/system/bin/audioserver`, no `audioserver.rc`, no audio libs
(libaudioflinger*, libaudiopolicy*), no audio_policy_configuration.xml;
the GSI init.rc's `service audioserver` definition is scrubbed
(the `mkdir /data/misc/audioserver` remains). `/system/bin/
minimediaservice` registers the dead `media.audio_policy` stub
(`media.audio_policy` string present in its binary). Fix candidate #1
from 2026-11-11 is therefore answered: the real AudioPolicyService
cannot run from this image as-is.

Restore overlay ASSEMBLED + validated (24 files, 6.7 MB): audioserver
+ rc + 18 closure libs from the LOS 23.2 system image, audio policy
config (AOSP primary module, telephony routing intact, non-essential
XIncludes stripped) + volume tables + audio_effects.xml. Injection via
the existing pre-start halium-overlay rsync (fixup-overlay-husky runs
Before=lxc-android-config.service, so init parses the restored rc).
A16 FactoryHal auto-prefers the AIDL IModule (verified in AOSP source),
so halVersion="3.0" in the config is harmless. Staging:
bring-up host `work/audio-restore/overlay-root/`, evidence
`husky-verify/audio-20261112/NOTES.md`. Not yet committed to the device
repo.

## Next display tests

Run each configuration from a clean boot or a LightDM restart, and record a photo, compositor log, composer3 logcat, and DRM state:

1. quirk `true`, overlays `true` — current baseline
2. quirk `true`, overlays `false`
3. quirk `false`, overlays `true`
4. quirk `false`, overlays `false`

Do not alter GridUnit/DPR until scanout geometry is correct. Only test refresh-rate and native-resolution changes after removing framebuffer-debug contamination and capturing the baseline above.
