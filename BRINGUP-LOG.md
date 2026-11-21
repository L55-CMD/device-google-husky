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

### YouTube playback reboots the phone — root cause FOUND (defect #6 escalated)

Playing any YouTube video in morph-browser kernel-panics and reboots.
ramoops (saved: `husky-verify/ramoops-full.{bin,txt}`) shows:

- Crash: `Comm: binder:332_1` (codec2) in `mfc_open` ->
  `mfc_iommu_map_firmware` -> `iommu_map_sg(domain=NULL)` -> NULL+8 deref
  -> panic. MFC device has NO IOMMU domain.
- Same boot's earlier shutdown also panicked in `iommu_release_device`
  (same NULL-domain family).

Chain: MFC platform device has `samsung,iommu-group = <&iommu_group_mfc>`;
the group driver (sysmmu-group) probed, but NOT ONE samsung SysMMU bound a
driver (`*.sysmmu` devices unbound; only pcie-sysmmu). Root cause:
**`samsung_iommu_v9.ko` is never loaded.** Verified against the rolling
kernel release (`test-r8-lazylink/kernel.zip`, Nov 10 14:21 — the exact
image on the phone): the module IS built and packaged in
vendor_dlkm.flatten.img (274 modules; modules.dep + modalias correct:
`samsung,sysmmu-v9` -> `samsung_iommu_v9`), and
`zuma_defconfig` has CONFIG_SAMSUNG_IOMMU_V9=m, but the boot-time load
lists (modules.load 63 lines, husky insmod cfg 5 modules) do not include
it, and no uevent/modalias autoload reaches it. `exynos_mfc` gets
modprobed by the codec path and lands domain-less.

Fix (queued, one-liner class): load `samsung_iommu_v9` at container
start (device-hacks modprobe once vendor_dlkm is mounted), or add to the
insmod cfg. Live test: modprobe it, confirm `*.sysmmu` bind, unmask MFC
nodes, play YouTube. Likely also fixes the shutdown
`iommu_release_device` panic. NOT a defect in the s2mpu lazy-link
patches after all — the earlier suspicion is retracted; those patches
touched USB-GSA S2MPU, unrelated to the media SysMMU group.

Live mitigation applied on the phone until the fix ships: container MFC
nodes `chmod 000` (software decode fallback; survives until reboot only).

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

## 2026-11-17 update

### Defect #6 fix: LANDED (pKVM ramdisk segment) — on-device verify still pending

The queued one-liner modprobe fix evolved into the root-cause fix, committed
on `test-audio-restore` (`c42b131`..`2028e9d`, CI green): a cpio segment
appended to the halium boot ramdisk (`scripts/make-pkvm-ramdisk-segment.sh`)
that ships `exynos-pd` + `pkvm-s2mpu-v9` and their full dependency closure
(25 modules, flat `/lib/modules` layout, `/system/bin/modprobe -> /bin/kmod`
symlink — both paths dictated by the kernel's own config:
`CONFIG_MODPROBE_PATH`, `CONFIG_PKVM_MODULE_PATH`). This lets the kernel's
early pKVM usermode modprobe succeed before pKVM finalizes, so
`samsung_iommu_v9` can load afterwards, `*.sysmmu` bind, and MFC gets a real
IOMMU domain.

Still open: on-device verification (handover #3 step 2 — flash ONLY the
test-audio-restore boot images onto the baseline super; expect `samsung_iommu`
in lsmod, no s2mpu resume spam, YouTube playback without panic, clean
shutdown). Also note the 2026-11-12 modprobe-at-container-start alternative
was NOT taken — the ramdisk segment addresses the root cause instead.

### Display diagnostics status

`kernel-patches-husky` branches `test-display-force60` and
`test-display-wqhd` are pushed; `lineage-kernel-manifest-husky` is staged on
`test-display-wqhd`. The wqhd patch was corrected on 2026-11-17 (`7201582`):
the original diff wrapped both FHD entries but left WQHD120 exposed (not the
intended WQHD60-only isolation). Kernel CI builds pending; test after the
call-audio work per the ordered queue.

### Defect #6 fix VERIFICATION FAILED on first try — second root cause found and fixed (2026-11-17)

Flashing the Nov-13 `test-audio-restore-debug` boot images (handover #3
step 2) did NOT fix the IOMMU chain: `pkvm_s2mpu-v9` and
`samsung_iommu_v9` both absent from lsmod, no `samsung-sysmmu` driver
bound (25 sysmmu devices idle), `exynos_mfc` loaded domain-less again.
The pKVM segment never reached the device.

**Root cause (second, in the packaging):** `prepare-device-tarball.sh`
appended the raw pkvm cpio AFTER the gzip-compressed halium initrd.
`make-bootimage.sh` recompresses the ramdisk for
`deviceinfo_ramdisk_compression="lz4"` via `gzip -dc | lz4` — gzip decodes
only the first stream, drops the raw segment as "trailing garbage
ignored" (exit 2, masked by the pipe). Verified by unpacking the flashed
`init_boot.img`: segments = halium initrd (357 files) + ramdisk-overlay
(`scripts/halium`) only. The 2026-11-13 "validated against kernel.zip"
claim covered the segment CONTENTS, not its survival through the image
pipeline.

**Fix:** `6b7fc69` — concatenate the RAW cpio streams (halium initrd
decoded + pkvm segment) before re-gzipping, so the build-tools
recompression round-trips everything. Round-trip validated locally with
the pinned initrd. Success criteria for the NEXT on-device attempt:
`lsmod | grep pkvm_s2mpu`, `ls /sys/bus/platform/drivers | grep
samsung-sysmmu`, `dmesg | grep samsung_iommu`.

Side note: the `16470000.s2mpu_s0_gsa: failed to resume s2mpu (-13)` spam
is from the USB-GSA s2mpu instance, NOT pkvm-s2mpu — it appears on
baseline too; do not use it as the pKVM success/failure signal.

### Defect #6 second on-device verify — 2026-11-17 evening: THREE root causes found (2 fixed, 1 needs kernel work)

Verification loop from handover #3 step 2, all against the Nov-17 CI release
(`6b7fc69`) flashed as boot-images-only onto the baseline super:

**Root cause #3 (packaging, NOW FIXED in working tree):** the pkvm segment's
cpio contained ONLY files and symlinks — `find ... \( -type f -o -type l \)`
**excluded directory entries**. The kernel initramfs unpacker does NOT create
parent directories implicitly, so the segment's `system/bin/modprobe`
symlink was silently dropped. Captured on device via an initramfs hook that
dumped the early dmesg to userdata before the 1MB log buffer wrapped:
`Failed to load pkvm module exynos-pd: -2` (ENOENT exec of
/system/bin/modprobe), after `Couldn't mount /proc, pKVM module parameters
will be ignored` (benign, /proc already mounted). The /lib/modules files
from the SAME segment unpacked fine because /lib/modules exists in the
halium initrd. Fix: include dirs in the cpio (`find ... -type d -o -type f -o
-type l`). Commit pending.

**Capture technique (reusable):** patched the flashed init_boot.img
in-place: decode ramdisk lz4 stream at 0x1000, rebuild seg0 cpio with a
hook before `exec run-init` (`dmesg > ${rootmnt}/userdata/pkvm-boot.log` +
/proc/modules + /lib/modules listing), recompress (`lz4 -l -9`), splice with
zero-padding (header untouched, region per hdr@0x0C), `dd` to
/dev/disk/by-partlabel/init_boot_b from root SSH, `cmp` to verify. Script:
`husky-verify/tmp/repack-initrd.py`. Note: header ramdisk_size field reads 0
at 0x10; the real region size lives at 0x0C; layout is two concatenated lz4
legacy frames (halium initrd + pkvm/overlay) — repack as ONE frame, the
kernel's unlz4 handles it.

**Panic after dir-entry fix (root cause #4, the REAL blocker):** with the
modprobe symlink present, the full chain now loads at ~0.3s (exynos-pd,
pkvm-s2mpu-v9 incl. its EL2 module) and samsung_iommu_v9 binds via ueventd
at ~13.5s — then the phone boot-loops. Panic captured from
`/var/lib/systemd/pstore/console-ramoops-0` (systemd-pstore archives and
clears /sys/fs/pstore every boot — that's why pstore always looked empty;
dmesg-ramoops-* absent means no oops-dump, the panic text IS in the console
archive because abl shares the region; full trace:
`husky-verify/tmp/console-ramoops-attempt2-3.log`):

```
[13.887] sysmmu: SysMMU READ PTW ACCESS FAULT from HSI0 PMMU 0 VID 0
         Stream ID 0x0 AXI ID 0x0 at 0x0ffffe000 (pgtable @ 0x97e40000)
[13.887] pkvm-s2mpu-v9 11070000.s2mpu_s0_hsi0: S2MPU FAULT DETECTED
         PA=0x97e7fff0 FAULT_INFO=0x80400002 read, access permission fault
[13.888] Kernel panic - not syncing: ... (samsung_sysmmu_irq_thread [samsung_iommu_v9])
```

Mechanism: the S2MPU **blocks the SysMMU's own page-table walk** — the host
samsung_iommu's PGD (0x97e40000, domain attached for some master) was never
registered to the pKVM side, so its PTW reads are access-faults. A master
with Stream ID 0 / AXI ID 0 on HSI0 (NOT the USB default stream 0x108; NOT
the RNDIS gadget necessarily — usb@11210000 has no iommus prop at all and
sysmmu@11040000 has **no `s2mpus` property**, unlike the other SysMMUs)
triggers it 13.9s into userspace. On stock the pkvm<->host-iommu
registration covers these tables; ours doesn't. Also noted: the CI
vendor_dlkm modules.dep is NOT a real symbol-dependency file — ELF parsing
(`husky-verify/tmp/elfdeps.py`) shows the true closure of
{exynos-pd, pkvm-s2mpu-v9} is only FIVE modules (exynos-pd, pkvm-s2mpu-v9,
phy-exynos-usbdrd-eusb-super, exynos-pd_hsi0, eusb_repeater); the 24-module
closure from the CI dep file drags in dss/vh_sched/cmupmucal and must not be
used as-is.

**Next steps (kernel/DT work, next session):**
1. Decide the fix direction: (a) investigate why the pkvm_s2mpu_of_link /
   pkvm_iommu_s2mpu_register handshake doesn't cover the host PGD (compare
   samsung_iommu_v9 registration path, check the missing `s2mpus` DT prop
   on sysmmu@11040000, compare lineage vs stock DTB), or (b) late-load
   approach: patch pkvm_s2mpu.c to skip the EL2 load when
   `is_pkvm_initialized()` (module then loads at container start, exports
   the pkvm_s2mpu_of_link_v9 symbols samsung_iommu needs, no S2MPU
   enforcement, MFC still gets a real domain) — needs a kernel build.
2. Ship only the TRUE 5-module closure + ELF-derived modules.dep (update
   `scripts/make-pkvm-ramdisk-segment.sh` to compute deps from ELF symbol
   tables, not the CI modules.dep).
3. Commit the dir-entry fix (working tree) once the above lands.

**Option B investigation (2026-11-17 late, user chose full pKVM fix):**
mechanism fully mapped from sources (lineage google-modules, lineage-23.2):
- S2MPU MPT = mirror of the pKVM HOST STAGE-2 map (`hyp/s2mpu.c`:
  `initialize_with_mpt(dev, &host_mpt)`, kept current by the
  host-stage-2 map/unmap notifiers `s2mpu_host_stage2_idmap_*`). Anything
  allocated+mapped after S2MPU init (like samsung_iommu's FLPT, kmem_cache
  at ~13.5s) reaches the MPT ONLY via those notifiers.
- Our boot: notifiers never fired for the FLPT -> S2MPU denies the PTW
  read -> panic. Same module, same 0.3s load timing as stock, so the
  suspect is OUR KERNEL BUILD: `CONFIG_LTO_CLANG_THIN=y` (+CFI) breaking
  the EL2 module's notifier/relocation registration
  (`kvm_apply_hyp_module_relocations`). /proc/config.gz is the GKI core
  config only - it cannot show vendor-module CONFIG_PKVM_S2MPU_V9 (=m in
  the vendor build; Kconfig default n, enabled in the shusky vendor
  defconfig).
- `sysmmu_hsi0` lacking the `s2mpus` DT prop is UPSTREAM zuma design (also
  absent on sysmmu_misc/sysmmu_gsa); `dwc3@11210000` HAS
  `iommus = <&sysmmu_hsi0>` + phy `s2mpus = <&s2mpu_s0_hsi0>`, so dwc3 is
  the master that gets the HSI0 domain.
- CORRECTION (2026-11-18): the "CI modules.dep is bogus / true ELF
  closure is 5 modules" claim above was WRONG. A hand-rolled ELF closure
  over-counts (kernel shim exports like strlcpy, exported by bcmdhd,
  falsely pull wifi/pcie chains - depmod knows the kernel symbol table)
  and under-counts (attempt-3's pkvm-boot.log shows `modprobe -d
  /lib/modules/` FAILED on the 5-module set; only the kernel's
  fallback-to-default-path retry loaded the modules). depmod's
  modules.dep (25-module closure incl. dss/vh_sched) is authoritative
  after all; the segment script keeps using it. The ltonone test images
  therefore ship the depmod closure.
- TEST IN FLIGHT: kernel-patches-husky branch `test-audio-restore-ltonone`
  (+ manifest branch same name) = test-audio-restore with
  CONFIG_LTO_NONE=y / LTO_CLANG_THIN=n in halium.config. Kernel CI builds
  kernel.zip tagged `test-audio-restore-ltonone`; verify by splicing the
  new Image + pkvm-s2mpu-v9.ko into the local init_boot/boot images
  (tooling in husky-verify/tmp/) and dd-flashing. If the 13.9s HSI0 panic
  is gone -> LTO confirmed as the breaker; if not, next suspects are the
  host-stage-2 notifier wiring in the el2 module init path.

**Phone state:** restored to r8-baseline-debug boot images on baseline
super (boots, SSH OK). The test-audio-restore CI release is still valid;
local patched init_boot images (attempt1/2/min) are in `husky-verify/tmp/`.

## 2026-11-19 — integration of the validated build + RETRACTION of the LTO claims

### Correction first (supersedes the 2026-11-19 verdict section on the
### test-audio-restore-ltonone branch)
RETRACTED: "CONFIG_LTO_CLANG_THIN confirmed as the EL2 S2MPU notifier
breaker" and "LTO_NONE is the verified fix". The user extracted the actual
effective configs: run-98's kernel AND the rebuilt integrated kernel both
contain CONFIG_LTO_CLANG_THIN=y. The halium.config LTO_NONE fragment is
inert in the GKI build; the "LTO" experiment compared two kernels with
identical effective configs and isolated nothing. The beneficial run-98
delta vs the panicking kernels (test-r8-lazylink lineage: g0b2699b6e265,
g7e26db69eb15) is the PATCH-STACK difference (halium-husky 0f72552
lineage) — UNIDENTIFIED, pending a dedicated bisect. Run 98 is retained
as a validated known-good image set; its beneficial source delta is
unidentified. "ltonone" names are historical misnomers; the inert
fragment stays as part of the validated source tree.

### What remains TRUE and validated (run 98, user-tested 2026-11-19)
Full matched 5-image flash (incl. vendor_kernel_boot — see bootloop root
cause below) boots past the 13.9s HSI0 SysMMU PTW panic: pkvm_s2mpu_v9 +
samsung_iommu_v9 + samsung_iommu_group loaded, 26 sysmmus bound incl.
11040000 (HSI0), mfc-core bound to MFC-0, dwc3/RNDIS alive, zero
S2MPU/access-fault/panic lines in live dmesg. YouTube playback WORKING.
Defect #1 bottom-region scanout artifact GONE (mechanism UNKNOWN; the
Lomiri quirk matrix / force60 / wqhd queue is MOOT — do not rerun).
Evidence: husky-verify/tmp/ltonone-full-20261119-105157/. kver
gc9a0580a0791; hashes: boot 6764e3c5...01eef, init_boot 3476aad7...440dd,
vendor_kernel_boot da3e1db5...e78f, vendor_boot a3a44eba...872c, dtbo
3dba3e31...4798c (boot-images.zip 7276a00c, MANIFEST device b808d33).

### 2026-11-18 bootloop root cause (SOLVED — packaging/process, not kernel)
"Couldn't find data partition" at 8.4s was an INCOMPLETE FLASH: only
boot+init_boot were dd'd; the phone kept r8-baseline's vendor_kernel_boot
whose modules live under the old kver dir. The halium initrd only reads
/lib/modules/<running-kver>/modules.load; on mismatch its mv-logic buries
modules.load one level down -> only the 25 flat pkvm .ko visible -> UFS
never probed. The device CI images were never at fault. Guard:
husky-verify/preflight-boot-images.sh (structural matched-set gate;
PASSes good sets, REFUSES the stale-vkb scenario — negative-tested) wired
into the dd flash scripts; see also the BRINGUP.md flashing warning.

### Integrated mainline baseline (CI-verified, OFFLINE-VERIFIED, NOT flashed)
- kernel-patches-husky: halium-husky = test-audio-restore = 22c33ed
  (cherry-pick of 24ffa8d; tree byte-identical to the validated patches
  tree; fragment inert per Correction).
- lineage-kernel-manifest-husky: test-audio-restore = a979a7a
  (kernel-patches ref -> refs/heads/test-audio-restore).
- device-google-husky: test-audio-restore = ca7a9ea (= 67bc584 cherry-pick
  of b808d33 recovery pin build 603, kept separate; + 1ce89c5/ca7a9ea
  buildlog-on-failure diagnostics cherry-picked after the first
  integration run 44521196681 failed silently).
- kernel.zip (manifest repo release, tag test-audio-restore) digest
  8594fe4574e4a9977cdc3ef9a4244049fd7a101bcc0c718f2aeecba041d484e6;
  Image kver 6.1.145-android14-11-g799ecb77416a (per-run workspace hash —
  internal match is the requirement, not equality with run-98's kver);
  vendor_kernel_boot + initramfs both carry the 209-module tree with
  modules.load under g799ecb77416a.
- Device CI run 44612802506 (debug) green; boot-images.zip digest
  fcb8b563aea97b13cd198f756984d0b5741bbbeeb87b6d5793e3ba8e9b9a0c6a.
  Image hashes: boot.img 09891f5e540eab9f1307e375948203c3738777edf028addddb89b8d3ccc58c56,
  init_boot.img e6b1f6e8f78e2aaa5091146892e6ddb20969100911db92f8940829127b27e01d,
  vendor_kernel_boot.img 0fbce5ae4dd03cc448c51a4dc3c3dc585d26a85a6c75f7a811c9d4c23660817d,
  vendor_boot.img bdecf19d40d0485ba7433eb0bbd9d9336a83f119fbdd288c341f9d330a9bfb18,
  dtbo.img 3dba3e31d69264dc1519d1cad24dc5dda294c96a1d4d9fbe526f9cb379a4798c.
  Offline checks: preflight-boot-images.sh FULL PASS; MANIFEST device
  ca7a9ea / manifest a979a7a / patches 22c33ed / kernel tag
  test-audio-restore; boot-images.zip sha256 OK. Local copies:
  husky-kernels/kernel-test-audio-restore.zip, husky-flash/tar-audio-lto/.
  NOTE: effective kernel config is CONFIG_LTO_CLANG_THIN=y (see
  Correction) — do not reject these artifacts for "not being LTO_NONE".
- Preservation: local tags known-good-ltonone-run98 on all three repos
  (run-98 tips); run-98 images + evidence preserved on the bring-up host.

### Status / next
- Defect #6 (MFC/IOMMU): open ONLY for the clean-shutdown test (one
  reboot, user decision). Defect #1: resolved on this build (mechanism
  UNKNOWN). Defect #2/#7 audio: unchanged (stub work queued). All
  unlisted hardware UNTESTED.
- Next discriminating experiment (own session, one variable): bisect the
  patch-stack delta halium-husky(0f72552) vs test-r8-lazylink(6d9a427)
  to identify the beneficial commit(s); until then treat the whole
  integrated family as the validated unit.
- Do NOT flash the integrated artifacts merely because CI is green; the
  phone already runs the validated build and was not accessed during
  integration.

## Next display tests

> MOOT 2026-11-19: the bottom-region artifact is GONE on the validated
> build (user-verified; mechanism UNKNOWN). Retained below for history
> only — do not schedule these runs unless the artifact regresses.

Run each configuration from a clean boot or a LightDM restart, and record a photo, compositor log, composer3 logcat, and DRM state:

1. quirk `true`, overlays `true` — current baseline
2. quirk `true`, overlays `false`
3. quirk `false`, overlays `true`
4. quirk `false`, overlays `false`

Do not alter GridUnit/DPR until scanout geometry is correct. Only test refresh-rate and native-resolution changes after removing framebuffer-debug contamination and capturing the baseline above.


## 2026-11-20 — Integrated baseline on-device; clean-shutdown PASS; new flaky defect #8

**Flash (TESTED):** CI run 44612802506 debug set (device ca7a9ea / manifest
a979a7a / patches 22c33ed, kernel kver 6.1.145-android14-11-g799ecb77416a)
flashed boot-images-only to slot b 2026-11-20 18:22Z; per-image sha256
verified phone-side; preflight matched-set gate PASSED (flat 25-.ko pkvm
closure in init_boot; 209-module vendor_kernel_boot tree at kver).

**Post-boot verification (TESTED):** identical to run-98 criteria — pkvm_s2mpu_v9
@2.4s, samsung_iommu_v9 with 21 domain refs, 25 sysmmus bound incl HSI0,
mfc-core on MFC-0, mali s2mpu @16.2s, zero S2MPU/PTW/panic lines.

**Clean-shutdown test (TESTED):** `systemctl poweroff` → normal unmount
sequence, no panic, no hang. The `iommu_release_device` NULL-domain
shutdown-panic suspect did NOT reproduce (consistent with samsung_iommu_v9
loaded with real domains). Ramoops is wiped by cold poweroff — post-poweroff
pstore is never available; use the persistent journal for shutdown verdicts.

**Defect #8 (UNKNOWN, flaky):** the first boot after a cold poweroff
crash-looped Lomiri (lightdm restarting ~every 65s, black screen, no host
RNDIS reachability despite the phone-side gadget reporting up); a later boot
of the same images/slot was fully healthy → startup race. Also observed:
with Lomiri down, a short power press powers the phone off via logind's
default action. Full detail: `husky-verify/NEXT-SESSION-NOTES.md`
2026-11-20 section. Next discriminating action: capture `journalctl -b`
plus lightdm/xsession logs from a bad boot before rebooting.

**Defect #6 CLOSED (TESTED 2026-11-20 evening):** YouTube playback WITH
AUDIO on the integrated baseline passed with no panic and no reboot
(user-verified). The integrated build is recorded as ON-DEVICE
KNOWN-GOOD, superseding run-98.

**Known-good recording + promotion (2026-11-20):**
- Coordinated tag `known-good-r8-20261120` pushed on all three repos:
  device @660bfb3 (this branch), manifest @a979a7a, patches @22c33ed.
- kernel-patches-husky: branch `main` created @22c33ed (device CI
  resolves patches by branch name).
- lineage-kernel-manifest-husky: branch `main` fast-forwarded
  98068de..a979a7a; its kernel CI is rebuilding the identical source to
  publish kernel.zip under release tag `main`.
- PENDING (mechanical, do after the manifest `main` kernel.zip exists):
  fast-forward device `main` to this branch's head (old main 107090e is
  an ancestor, FF-verified). Device CI for `main` then resolves: manifest
  release `main` + manifest heads/main + patches heads/main — all in
  place except the release artifact.

**Defect #8 remains OPEN (intermittent):** post-cold-off Lomiri
crash-loop boot; capture procedure prepared in
husky-verify/defect8-capture/ (not yet run; awaits user go).

**Phone state:** integrated baseline running, healthy (Lomiri greeter,
container, RNDIS/SSH). This is the on-device known-good build.


## 2026-11-20 — Phase 3 (communications) test session on the integrated baseline

Tested on the CI 44612802506 debug set already on the phone (no new
flash). Full evidence + probe scripts: bring-up host
`husky-verify/comms-20261120/` (NOTES.md is the session log;
probe-comms.sh, messaging-app-debug.sh, bt-pair-test.sh).

### Defect #9 — messaging-app crash — recovery applied; first-boot DB initialization root cause OPEN

Symptom: messaging app crashed on open and when tapping SMS
notifications (SMS itself reached ofono fine — `incoming sms` log
lines at 19:09Z). Root cause: `lomiri-history-daemon` never created
its database — `~/.local/share/history-service/history.sqlite` was a
0-byte file from first boot (Nov 10 18:14); the daemon logged
`Failed to create or update the database` on every boot and every
query failed with `no such table: threads`. The messaging app crashes
because its history backend is an empty schema.
Recovery (TESTED, NOT A DURABLE FIX): back up + remove the 0-byte
DB, restart `lomiri-history-daemon.service` (user scope) → proper 53
KB schema created, queued SMS imported, messaging app fully working
on the current installation (user confirmed send/receive). Root cause
of the original first-boot creation failure is UNKNOWN (first-boot
race suspected) and remains OPEN: reproduce from a clean flash or fix
the initialization path in code. WATCH ITEM: may recur on clean
flashes; check for a 0-byte history.sqlite first if messaging breaks
again. Cosmetic: history-daemon complains "The phone number is
not a valid number: Vodafone" for carrier alphanumeric senders —
messages still save.

### Communications results (all on-device TESTED unless marked)

- SMS: receive + send WORKING ON THE CURRENT INSTALLATION (via ofono
  1.29 + telepathy-ofono; messaging-app layer needed the defect #9
  recovery workaround). The first-boot DB-initialization failure is not
  closed.
- MMS: RECEIVE/DISPLAY WORKING — picture message received + displayed
  (nuntium dbus-activated; Vodafone MMS APN + proxy + MMSC provisioned
  in ofono context2). MMS SENDING REMAINS UNTESTED.
- Carrier/signal reporting: WORKING (operator "vodafone UK",
  MCC/MNC, CellId, LTE tech, registration state). ofono Strength read
  3/100 indoors (~-112 dBm per husky.conf range) while data worked —
  likely genuine weak coverage; UI-bar cross-check pending.
- VoLTE: NOT WORKING. IMS (IpMultimediaSystem) present but
  Registered=false, Voice/SmsCapable=false; Register() →
  org.ofono.Error.Failed. IMS APN (context3, "ims") provisioned but
  inactive. Container has rild_exynos (Samsung SIT RIL V2.3) + no
  vendor ims daemon; carrier_id=28, default_network=27. Pixels
  generally need Google IMS (GMS) for VoLTE — this GSI has no GMS.
  RESEARCH ITEM, not a simple ofono fix. Voice calls work via the
  legacy CS path meanwhile.
- Airplane mode: PARTIAL/defect. System level WORKS (NM rfkill as
  root kills Wi-Fi; ofono Online=false/true cycles the modem with
  clean LTE re-registration + data restore in ~10 s). Lomiri
  indicator flight-mode toggle is a NO-OP. urfkilld exposes only two
  Ofono-type devices (name "unknown unknown", platform=false) and NO
  wlan/bt killswitches, though kernel rfkill devices exist and work.
  Defect #10. Next step (own session): restart urfkilld, re-enumerate.
- Mobile hotspot: PARTIAL/defect. System level WORKS: NM AP mode
  (nmcli-created "phase3-hotspot" on wlan1) beacons (iw: type AP,
  ch 11), NM shared mode + dnsmasq DHCP up, phone side 10.42.0.1/24,
  iptables/NAT functional (CONFIG_IP_NF_* built-in; the modprobe
  FATAL lines at hotspot start are benign). AP survived a suspend
  cycle. Lomiri indicator hotspot creation FAILS ("Hotspot network
  creation took too long", NM log 20:40Z — the indicator also
  deactivated the test AP at 20:39Z). Client join E2E untested (user
  test device flaky at scanning). Treat this as part of defect #10's
  indicator/UI plumbing, not as a fully working hotspot.
- Bluetooth: MEDIA PATH WORKING. MOMENTUM TW 4 earbuds: pair/trust/
  connect PASS; PA bluez A2DP sink registered (module-bluez5-
  discover); 2 s test tone audible in earbuds (user confirmed);
  disconnect → re-open case → auto-reconnect within 5 s, sink
  reappears. BT call audio/mic UNTESTED — blocked by defect #2.
  Pairing state survived suspend.
- NFC: NOT WORKING, root cause IDENTIFIED. Kernel modules fine (nfc,
  st21nfc, st54spi; /dev/st21nfc), container AIDL HAL
  (android.hardware.nfc-service.st) running, but nfcd 1.2.1
  (ubports) registers ZERO adapters — its binder plugin is
  HIDL-only (strings show only `android.hardware.nfc@1.0::INfc` on
  /dev/hwbinder) while the device ships an AIDL-only NFC HAL. Defect
  #11. Fix direction: rebuild nfcd-binder-plugin with AIDL support
  (upstream mer-hybris has it) — a package build, own session.
- SIM PIN unlock / dual-SIM: UNTESTED (user opted out; SIM has no
  PIN; slot2 empty but correctly enumerated as absent by ofono
  binder).

### Notes for other phases

- The ofono 1.29 fork does NOT implement freedesktop
  Properties.GetAll — use per-interface `GetProperties` methods.
- root@ SSH (same key) sees the full journal and `lxc-attach -n
  android -- getprop/ps`.
- FOLLOW-UP PRIORITY: (1) let Phase 1 finish the defect #8 capture
  series; (2) hand the defect #12 Wi-Fi-after-suspend evidence to
  Phase 2; (3) handle defect #10 indicator/UI plumbing as its own
  change; (4) handle defect #11 NFC AIDL plugin support as its own
  change; (5) keep VoLTE as a separate research item — do not combine
  IMS experimentation with the current stability work.
- CLEAN-INSTALL TEST PLAN: after the next clean flash, check
  `~/.local/share/history-service/history.sqlite` before applying any
  workaround. It must be non-zero and contain the expected schema;
  if it is 0-byte, capture the first-boot journal plus
  `lomiri-history-daemon.service` logs before recovery so defect #9's
  root cause can be reproduced or fixed at the source.
- Session interrupted by Phase 1/2 suspend-reboot cycles 3 times —
  wait-for-phone.sh reconnect handles it; comms state survived.

### Defect #12 — Wi-Fi-after-suspend (Phase 2 overlap, observed during Phase 3)
After the ~20:56Z suspend cycle both wlan0/wlan1 were link-DOWN with
rfkill soft-blocked; the indicator oscillated "Setting WiFi enabled
= false/true" ~1/s on resume. rfkill unblock, `nmcli radio wifi
off/on`, and a full NetworkManager restart did NOT recover
("Couldn't initialize supplicant interface: Timeout was reached");
only a reboot healed it. Also seen at 18:48 boot ("wpa_supplicant
couldn't grab this interface" on wlan0). Driver: bcmdhd4398. This
blocks resume reliability — Phase 2 should pick it up.
Defect #12 evidence handoff: Phase 2 owns investigation/fix; Phase 3
records the communications-context symptoms above. Before attempting a
fix, inspect NetworkManager state, rfkill/urfkill state, wpa_supplicant
logs, wlan interface state, and bcmdhd4398 suspend/resume journal
entries.
WARNING: capture the complete failed-state journal plus `ip link`,
`rfkill list`, `nmcli radio/device/general`, `iw dev`, and relevant
wpa_supplicant/bcmdhd4398 logs BEFORE rebooting. `rmmod bcmdhd4398`
succeeds but the module is NOT in the host /lib/modules/<kver> tree
(loaded from the vendor image at boot), so it cannot be reloaded —
Wi-Fi stays dead until reboot. Do NOT unload bcmdhd4398 again or use
driver reload as a recovery handle.


## 2026-11-21 — Defect #8 controlled cold-off series: 6/6 GOOD, no reproduction

On-device image remained the integrated known-good baseline (kver
`6.1.145-android14-11-g799ecb77416a`, slot `_b`). The defect-#8 capture
unit was installed and enabled; each valid round used
`systemctl poweroff --no-block`, waited for RNDIS drop, cold-soaked for
60 seconds, then powered on and polled for SSH. Per-boot evidence was
captured under `/userdata/defect8-capture/<timestamp>-boot/`.

An initial round-1 attempt was invalid: the phone entered the bootloader
instead of Ubuntu and created no boot capture. It was excluded from the
defect verdict. The subsequent six valid rounds all reached SSH and were
classified by the capture unit as `healthy-stable`; LightDM was active
with `NRestarts=0` in every capture.

Valid result: **0/6 reproduction** (defect #8 did not recur). Host
archive: `husky-verify/defect8-capture/evidence-20261121/` with
`SERIES-LOG.md`, per-round captures, and a verified `SHA256SUMS`
manifest. Per the runbook decision matrix, the failure is currently
rarer than 1/6 cold-offs; keep the capture unit enabled and leave
defect #8 OPEN as an intermittent low-reproduction startup race until
new evidence identifies the trigger.


## 2026-11-21 — Full hardening CI green; canonical main promoted

Defect #8 released the phone after six valid controlled cold-off rounds,
so the no-change-kernel hardening CI route was dispatched as run
**44957022617**. Result: SUCCESS (preflight plus both matrix jobs,
normal and debug).

Offline artifact gate (Agent 2, evidence under
`husky-verify/tmp/a2-harden/`):

- Both `latest-harden-build-release-{normal,debug}` release sets include
  the complete five boot images (`boot`, `init_boot`, `vendor_boot`,
  `vendor_kernel_boot`, `dtbo`) plus split `super.img`, Android rootfs,
  `SHA256SUMS`, and `MANIFEST.txt`; release digests and local downloads
  match.
- Coordinated revisions match the three branch tips: device
  `24d9591771141174691acc4f3a341b896e15bc96`, manifest
  `dd6cdda6096b47ba28a4c9bcdb9816b4d1b94598`, patches
  `22c33ed85ad235fdc2bc09d4ef1a89379f5a207f`.
- Kernel provenance: boot-embedded Image in both device variants is
  byte-identical to the `harden-build-release` kernel-release Image,
  kver `6.1.145-android14-11-gfb8153ed82aa`; vendor_kernel_boot has the
  full 209-module tree and matching kver. Kernel release digest:
  `a2b18e86091ab791480b9fcea1f8bce46ad46db5a22d0c29b46bf12efe0a9d39`.
- Boot-images.zip hashes: normal `73741770…544a8d`, debug
  `c63d771f…0f8739` (full records in Agent 2 evidence/report).

Canonical promotion was deliberately limited to the exact green CI
commit: device `main` fast-forwarded `107090e..24d9591`; manifest `main`
fast-forwarded `a979a7a..dd6cdda`; patches `main` already equaled
`22c33ed`. The push to device `main` started CI run 44958836687 on the
same tree as the verified green commit.

Caution retained for follow-up: the shipped hardening kernel's embedded
IKCONFIG confirms `CONFIG_LTO_CLANG_THIN=y`, `# CONFIG_LTO_NONE is not
set`, `# CONFIG_CFI_PERMISSIVE is not set`, and `# CONFIG_PM_AUTOSLEEP
is not set`. This matches the current on-device known-good baseline
config but contradicts the historical `CONFIG_LTO_NONE` claim attached
to patch `22c33ed`; correct/revalidate that claim separately. It does
not invalidate the green hardening artifact gate.
