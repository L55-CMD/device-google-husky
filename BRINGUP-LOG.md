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


## 2026-11-21 — Defect #12 reproduced on known-good baseline; failed state captured

After the hardening promotion and defect-#8 series, the known-good
baseline (kver `g799ecb77416a`, same boot) was used for a controlled
Wi-Fi-after-suspend reproduction. Evidence root:
`husky-verify/defect12-evidence-20261121/` (SERIES-LOG plus verified
SHA256SUMS).

Suspend attempts:

- `systemctl suspend --no-block` at 22:55:28Z did not enter suspend;
  `systemd-sleep` reported `Device or resource busy`, and PM showed the
  bcmdhd4398 PCI suspend callback failing with `-16` on deep/s2idle.
- Two rtcwake deep-suspend attempts (22:59:08Z and 23:00:45Z) entered
  suspend but resumed immediately on `bt_host_wake`; Wi-Fi remained
  data-working afterward.
- Temporarily disabling the BT platform wake source produced a failed
  suspend attempt (`bcmdhd4398 ... error -16`), then the setting was
  restored.
- Temporarily soft-blocking Bluetooth allowed a real ~23-second deep
  suspend/resume cycle (23:05:59Z→23:06:22Z, wake via `s2mpg14-irq`);
  Wi-Fi still worked immediately afterward. Bluetooth was restored.
- A later 60-second rtcwake attempt at 23:07:20Z failed immediately in
  the bcmdhd4398 suspend path with `failed to suspend async: error -1`.

Failed state captured before reboot:

- By 23:10:56Z, wlan0/wlan1 remained UP with IP addresses, `iw dev`
  still reported AP association, and NetworkManager reported
  `connected/full`.
- In reality the data plane was dead: phone-side pings to the AP and
  host failed at 100%; host-side pings to both Wi-Fi addresses failed
  and ARP remained unresolved.
- Kernel logs repeatedly reported `wl_cfg80211_dump_station :
  WLC_GET_ASSOCLIST error -19` and `wl_check_assoc_state : failed to
  get assoc_info : err=-19`.
- Full `journalctl -b` and `dmesg` were captured in the failed state,
  along with rfkill/NM/interface/host probes. The phone stayed on boot
  `21151961-f92d-47b2-aead-fab7c83fb540`; no reboot or driver reload
  was performed.

Current interpretation: defect #12 is a bcmdhd4398 suspend-path failure
mode, not merely an rfkill/UI state issue. A successful deep
suspend/resume followed by a failed suspend attempt that aborts in
`dhdpcie_pm_suspend` can leave the driver internally inconsistent
(association reported, ENODEV internally, no traffic). Keep #12 OPEN;
do not unload bcmdhd4398. PM_AUTOSLEEP is the next separate experiment;
flashing/rebooting for it will intentionally destroy this live failed
state after the evidence capture above.


## 2026-11-21 — PM_AUTOSLEEP image: repowerd path fixed, suspend entry blocked by bcmdhd4398

Device CI run **44960937874** for `test-pm-autosleep` succeeded. The debug
release was digest/preflight verified and only the complete matched
five-image boot set was flashed to slot b (no super/userdata changes).
Preflight: PM kernel kver `6.1.145-android14-11-gc5e9bc394477`, flat
25-module pKVM closure in init_boot, full 209-module
vendor_kernel_boot tree. Evidence:
`husky-verify/pm-autosleep-20261121/`.

First-boot result:

- `/sys/power/autosleep` EXISTS; `/proc/config.gz` confirms
  `CONFIG_PM_AUTOSLEEP=y` and `CONFIG_PM_WAKELOCKS=y`.
- repowerd 2025.01 starts without the prior deterministic
  `Failed to create LibsuspendSystemPowerControl` message and changes
  autosleep from `off` to `mem`, so the intended repowerd/libsuspend
  path is selected.
- Quick pKVM chain spot-check showed `pkvm_s2mpu_v9`,
  `samsung_iommu_v9` (21 refs), and Mali loaded; no panic/fault signature
  in the quick scan.

Suspend-entry result:

- Manual `systemctl suspend --no-block` at 23:35:51Z did not enter
  suspend; RNDIS stayed up and systemd-sleep returned `Device or resource
  busy`.
- With autosleep=`mem`, automatic suspend attempts also failed repeatedly
  (examples at 23:37:12Z, 23:38:00Z, 23:39:30Z).
- Kernel evidence: `dhd_net_bus_suspend: wait to clear dhd_bus_busy_state:
  0x44` and repeated `dhdpcie_bus_suspend(): Suspend failed because of
  wakelock restoring Dongle to D0`. System `/sys/power/wake_lock` was
  empty; this is an internal bcmdhd4398 busy/wakelock state.
- Full journal/dmesg captured, then `/sys/power/autosleep` was set back
  to `off` to stop repeated failed attempts.

Verdict: the PM_AUTOSLEEP kernel change fixes the repowerd/libsuspend
configuration problem but is NOT a validated suspend fix because actual
system suspend is blocked by bcmdhd4398. Do not test incoming-call wake
on top of this; it would conflate wake behavior with suspend-entry
failure. The phone remains on the PM test image pending a deliberate
rollback or a separately scoped bcmdhd4398 wakelock investigation.


## 2026-11-21 — Approved rollback to known-good baseline completed

After the PM_AUTOSLEEP suspend-entry blocker was captured, the preserved
known-good matched debug boot set was flashed back to slot b with explicit
user approval. Only `boot_b`, `init_boot_b`, `vendor_kernel_boot_b`,
`vendor_boot_b`, and `dtbo_b` were rewritten; `super` and userdata were not
touched.

Rollback coordinates:

- Artifact directory: `husky-flash/tar-audio-lto/`
- Device revision: `ca7a9eabea02ae0d1fe820b29403d85319dbf9e9`
- Manifest revision: `a979a7abfe8800b845d653c6abdd9fadc96a0257`
- Patches revision: `22c33ed85ad235fdc2bc09d4ef1a89379f5a207f`
- boot-images.zip sha256:
  `fcb8b563aea97b13cd198f756984d0b5741bbbeeb87b6d5793e3ba8e9b9a0c6a`
- Kernel/module kver: `6.1.145-android14-11-g799ecb77416a`

Post-boot verification at 23:53Z: slot `_b`, LightDM active with
`NRestarts=0`, `/sys/power/autosleep` absent as expected on this baseline,
`# CONFIG_PM_AUTOSLEEP is not set`, `CONFIG_LTO_CLANG_THIN=y`, pKVM chain
loaded (`pkvm_s2mpu_v9`, `samsung_iommu_v9` with 21 refs), and
NetworkManager connected/full. Evidence:
`husky-verify/rollback-known-good-20261121/rollback-verification.txt`.

Canonical `BRINGUP.md` now includes the CI precondition to verify the
same-named manifest kernel release before pushing or dispatching a device
branch. `husky-verify/NEXT-SESSION-NOTES.md` has the final branch tips,
CI runs, artifact digests, evidence roots, and the next serialized action:
scope the `bcmdhd4398` suspend-wakelock investigation separately.


## 2026-11-22 — bcmdhd4398 suspend failures classified into two separate defects

Agent 2 completed the bounded offline classification of the defect-#12 and
PM_AUTOSLEEP evidence.

Defect #12 (known-good baseline, `defect12-evidence-20261121/`): the
first genuine ~23-second deep suspend entered cleanly, but the dongle
trapped during resume with `pciedev_host_wake_asserted_for_too_long`.
The driver then wedged (`WLC_GET_ASSOCLIST error -19`, `failed to get
assoc_info`), and no hang recovery ever ran. NetworkManager,
wpa_supplicant, rfkill/urfkill, and the indicator were reporting stale
state; they are not the cause. Full classification:
`CLASSIFICATION-20261121.md`.

PM_AUTOSLEEP blocker (`pm-autosleep-20261121/`): a separate
suspend-entry race. logind sleep handling caused NM/wpa_supplicant Wi-Fi
teardown while PM suspend was starting; the bcmdhd4398 suspend callback
then hit busy state `0x44` and left a stuck dhd `wl` wakelock
(`wakelock c-1 wl-1`). With `/sys/power/autosleep=mem`, the kernel kept
retrying against the locked driver. No `PM: suspend entry` line ever
appeared in that capture, so the PM failure is not evidence about
deep-suspend resume.

Next single phone test, pending explicit approval: on the known-good
image with autosleep absent/off, disable networking (`nmcli networking
off`), wait about five seconds, then perform one manual suspend or
`rtcwake -m mem -s 20`. Capture dmesg/journal before and after. The
prediction is that removing live Wi-Fi teardown lets suspend enter
cleanly; failure with a persistent `c-1 wl-1` lock would instead point
at the autosleep retry path itself. Do not unload `bcmdhd4398`.


## 2026-11-22 — P1–P4: suspend characterized end-to-end; defect #12 reproduced (bounded retries) + recovery found

Four bounded on-device experiments on the known-good baseline (kver
`g799ecb77416a`, slot `_b`; evidence roots `husky-verify/p{1..4}-suspend-20261122/`
with REPORT.md files). SSH drops at suspend entry are expected (RNDIS
rebind lag, ~30 s); uptime was continuous in all runs (no reboots).

**P1 (TESTED) — teardown BEFORE suspend works.** `nmcli networking off`,
~5 s settle, `rtcwake -m mem -s 20`: the dhd busy state `0x44` seen
during teardown cleared in ~5 s, `PM: suspend entry (deep)` fired, RTC
wake exactly 20 s, zero `-19`/trap/stuck-wakelock lines, Wi-Fi healthy
after `nmcli networking on`. Verdict: the PM_AUTOSLEEP blocker was the
teardown-DURING-suspend race (H1/H2 confirmed); a pre-suspend Wi-Fi
quiesce hook makes manual suspend reliable.

**P2 (TESTED) — armed suspend with Wi-Fi up survives short cycles.**
Wi-Fi associated, baseline WoWLAN arm, `rtcwake -m mem -s 20`: suspend
entered; a `pci_pm_suspend: State of device not saved by
dhdpcie_pm_suspend` WARNING fired — this WARN only triggers on callback
SUCCESS (the PCI core saves state itself), so it is benign. WoWLAN
packets woke the phone at 2.2 s (LAN broadcast traffic through the
baseline triggers); resume clean, driver healthy.

**P3 (TESTED) — two mechanisms prevent long armed suspends.**
(a) `iw phy0 wowlan disable` with the interface up makes
`dhdpcie_pm_suspend` persistently return -16 (userspace sees EBUSY on
`/sys/power/state`) even with clean `busy_state:0x0` — a driver policy
refusal (no wake mechanism), NOT a wakelock wedge. (b) With WoWLAN armed
on this LAN, every suspend aborts <1 s on `host_wake caused by packets`.
Side finding: this driver rejects every per-trigger WoWLAN set via
cfg80211 (EINVAL, interfaces up or down); only `any` is accepted, so the
baseline 4-trigger arm is driver-internal and not user-reproducible.

**P4 (TESTED) — defect #12 REPRODUCED with byte-identical signature.**
A detached phone-side loop (`p4-loop.sh`, RTC-bounded `echo mem`
attempts, wowlan=`any`, Wi-Fi up) caught a quiet window on cycle 3:
genuine 33 s deep suspend, resume via rtc-alarm0, then `Dongle trap but
no etd` and hang reason
`Dongle_Trap_0x0_0x0_pciedev_host_wake_asserted_for_too_long+0x53` —
identical to the 2026-11-21 classification. The `-19` wedge followed
(SSSR dump ran; firmware stayed dead; NM stale "connected").

**Observed repro conditions (P4; quiet-LAN dependent — reproducible
within bounded RTC-loop retries, not one-shot "on demand"):** (1) WoWLAN armed
(disabled -> policy -16, never sleeps); (2) a genuine deep suspend —
clean at 2.2 s (P2), traps at 33 s (P4): a BRACKET, not a threshold
(nothing between 2.2 s and 33 s is probed); (3) RTC resume tested
(WoWLAN-armed; "any resume source" NOT proven —
the 2026-11-21 wake source is not implicated, but no other source was tested).

**Recovery (TESTED):** `nmcli networking off`, 8 s, `nmcli networking
on` — the driver's own stop/start reset reloaded the firmware
(`WLC_E_LINK UP` both interfaces, ping 0% loss), no module unload. This
is exactly the recovery that did not run on 2026-11-21. Basis for a
repowerd post-resume auto-heal hook (see
`husky-verify/repowerd-suspend-hooks-spec.md`).

Net: suspend/resume is workable today via prevention (pre-suspend
quiesce) plus cure (post-resume NM reset if wedged). Real fixes remain
firmware/driver-side. WoWLAN currently set to `any` (cosmetic; reverts
on reboot). Do NOT unload `bcmdhd4398`.


## 2026-11-22 — Corrections to the P1-P4 section (review-driven)

The P1-P4 section above overstated four points. Corrected record:

1. **"Suspend track closed" is retracted.** Defect #12 remains OPEN
   until a workaround or fix is integrated and validated on device.
   Today's state is: characterization complete, repro within bounded RTC
   retries (quiet-LAN dependent),
   recovery proven, prevention designed — nothing integrated yet.
2. P4 reproduced the trap with WoWLAN `any` + a 33 s deep suspend +
   **RTC** resume. It does NOT prove "any resume source" triggers the
   trap — only the RTC wake was tested.
3. WoWLAN-armed is NOT proven strictly required for the trap.
   Disabling WoWLAN makes `dhdpcie_pm_suspend` return -16, so that
   condition never reached a deep suspend and could not test the trap.
4. The duration result is a **bracket** (2.2 s passed, 33 s failed),
   not an established threshold.
5. P1's single clean teardown-first cycle strongly supports the
   teardown-race diagnosis and validates quiescing as a workaround,
   but one clean cycle is not universal proof by itself.

**Agreed implementation order (2026-11-22 review):**
1. Finish and review the hook specification (design constraints below).
2. Implement and validate the pre-suspend Wi-Fi quiesce **alone**.
3. Repeated genuine deep suspends >33 s with the quiesce hook:
   confirm clean resume and correct network restoration.
4. Test the validated hook with PM_AUTOSLEEP as the next incremental
   experiment.
5. Implement the post-resume auto-heal as a **separate** change
   (bounded retries, evidence capture).
6. Only then: VoLTE Register experiment and remaining communications
   work.

**Design constraints the spec must satisfy (review):**
- No blind global `nmcli networking off/on` in production behavior:
  preserve the user's prior networking/Wi-Fi state, never enable Wi-Fi
  the user disabled, handle hotspot/airplane cases.
- A `systemd-sleep` hook does NOT run when libsuspend writes autosleep
  directly — the spec must identify the actual execution path on both
  the logind path and the libsuspend path.
- Post-resume recovery must check local association/driver health
  BEFORE any Internet ping, with a cooldown/single-attempt limit so a
  network outage cannot cause an endless NetworkManager restart loop.


## 2026-11-22 (evening) — User hardware matrix results + defect updates

User-tested on the current debug build (known-good kernel + `a0bab3e`
device tree with sleep hooks):

**WORKS (user-verified):**
- SMS send and receive; MMS send (receive/display was already tested).
  Defect #9's remaining scope is now only first-boot init on a clean
  install.
- **Call audio bidirectional** — defect #2 candidate closure (repeat
  confirmation advised before closing; mechanism was the integrated
  baseline's vendor audio routing).
- Offline charging (charging screen when powered off + cable).
- Camera full set: front/back, photo, video, flash, torch.
- Bluetooth A2DP reconnect + playback.
- **Overnight suspend: clean wake, Wi-Fi reconnected** — first
  real-world idle-suspend pass, consistent with the P1-P4 conclusions.
- Airplane toggle in Settings drops/restores radios (rfkill-backed;
  urfkill service itself remains absent from the image).

**FAILS:**
- Hotspot from the Lomiri UI ("failed to create hotspot") — the NM-level
  AP works (tested via `nmcli device wifi hotspot`); the UI action path
  is the remaining defect. Client join untested.
- **GPS/location** — ROOT-CAUSED: `lomiri-location-service` SEGVs at
  startup: the default gps provider needs `libubuntu_application_api.so`
  (Ubuntu Platform API), which is absent from the image (and from the
  available apt repos), and `/var/lib/lomiri-location-service/config.ini`
  is missing so no provider can be configured out. Fix options:
  package/provide the UAL library (ABI work) or write a hybris-binder
  GPS provider against the container's `android.hardware.gnss.IGnss`
  (HAL + kernel drivers verified present and running). The service
  fails inert (no location, no crash loop).

**Untested:** wireless charging, NFC tag read, USB-C DisplayPort,
fingerprint.

**Also this date:**
- Auto-brightness: NOT a missing toggle — the entire backend is absent
  (no sensorfw ALS adaptor/plugins on image; repowerd 2025.01 has no
  light-sensor support). Feature requires building that layer.
- Proximity-in-call works; clock widget (#4) no longer reproduces —
  defect #4 closed (mechanism unknown, same class as defect #1).
- Suspend track completed: quiesce hook v2 + post-resume auto-heal
  (Change 2, `ee64390`), deep-suspend race-window method validated
  (clean 3.6-55.3 s deep suspends, zero defect-#12 signatures with
  teardown-first). See the earlier 2026-11-22 sections.


## 2026-11-23 — Hook image ee64390 flashed; logind-path validation 11/11 clean; defect #12 workaround validated (combined); defect #16 found (USB gadget reconfigures to ECM on replug)

### Flash (TESTED)

Device CI run `45061652269` (branch `test-audio-restore` @ `ee64390`,
kernel patches `22c33ed`, manifest `a979a7a`, same kver `g799ecb77416a`
as known-good — ramdisk/overlay-only delta). Offline
`verify-integration.sh` PASS (IKCONFIG CLANG_THIN matches run-98
reference; matched image set; same-run provenance). Flashed to slot `_b`
via `dd` (5 images, on-phone sha256 match), one reboot. Phone healthy
after boot: container/NM/repowerd active, Wi-Fi ×2 connected, Vodafone
gsm registered (registration completes ~1-2 min after boot —
observation, not a defect).

### Hook-path validation (TESTED) — `quiesce-validation.sh` on device

Two full runs of the staged plan (stage-0 logind-path proof + 5, then 4,
RTC-bounded deep cycles; evidence `husky-verify/quiesce-validation-20261123/`):

- **Run A: stage0 + 5/5 PASS. Run B: stage0 (1 env-abort retry) + 4/4
  PASS. Total 11/11 hook-path suspends clean.**
- Every cycle: pre-hook snapshot → active teardown (`nmcli networking
  off`) → handoff to suspend in ~10 s → **deep entry confirmed in dmesg
  every cycle** → clean resume → post-hook restore per snapshot → Wi-Fi
  device state and connections match pre-suspend (sorted Wi-Fi-scoped
  comparator). suspend_stats: 17 success, **0 dhd failures**.
- Real suspend windows: 1.1-28.9 s (max 28.9 s ×2, RTC wake). **No >33 s
  window landed on the hook path this session** — early wakes came from
  the environmental waker family (`cp2ap_wakeup` modem ×3, plus
  `alarmtimer.3.auto` entry aborts on 3 attempts, all retried/ recovered).
  This is the parked waker-hunt phenomenon (quiet-LAN dependent), NOT a
  dhd defect: last_failed_dev is the alarmtimer, never `0001:01:00.0`.
- Zero genuine defect-#12 signatures in any cycle (no Dongle trap, no
  `host_wake_asserted`, no `-19` wedge).

**Verdict: defect #12 workaround (pre-suspend quiesce + post-resume
auto-heal, shipped `9f8e84c`+`ee64390`) is VALIDATED on the production
logind path.** Combined with 2026-11-22 manual quiesce+deep evidence
(clean 40.7/52/55.3 s deep suspends, zero signatures), the integrated
workaround covers the characterized defect-#12 window. Residual gap
(recorded, not blocking): a >33 s deep window ON THE HOOK PATH itself
has not landed (28.9 s max; waker-dependent, opportunistic). Real fix
remains firmware/driver-side; defect #12 stays CLOSED-WORKAROUND.

### Harness lessons (evidence hygiene; scripts in `husky-verify/`, NOT product)

Three false-stops in the validation harness, all corrected in-script
with evidence comments: (1) raw `diff` state comparator false-FAILED on
nmcli ordering + mid-run **gsm registration** (cellular is not this
validation's variable) → sorted Wi-Fi-scoped comparator; (2) bare
`wakelock c-1 wl-1` false-TRAPPED a healthy cycle (short self-limiting
bursts, no `Suspend failed`, fail-stat clean — distinct from P4's
paired `Suspend failed because of wakelock` + Dongle trap) → signature
removed; (3) `Suspend failed because of wakelock` false-TRAPPED on a
**dhd runtime-PM line while awake** (Wi-Fi reconnect churn; benign) →
removed; the dhd suspend-ENTRY race keeps its own authority: suspend
fail-stat with `last_failed_dev=0001:01:00.0`. Environmental entry
aborts (alarmtimer) are retried, never passes.

### Defect #16 (NEW, OPEN) — USB gadget reconfigures to ECM descriptors on cable replug; Windows RNDIS breaks until reboot

Evidence (2026-11-23): after a cable replug while running, the phone's
configfs gadget (`/sys/kernel/config/usb_gadget/g1`, functions
`rndis.usb0`+`mass_storage.usb0`) was re-composed by the android USB
HAL relay (`usbdp_gbinder`, `notifyPortStatusChange` at re-plug time)
with the control interface written as **CDC-ECM** (`class 02 subclass
06 protocol 00`) instead of RNDIS (`02/02/ff`). Windows has no inbox ECM
driver → devnode code 28, no network adapter; reboot is unaffected
(cold-boot usb-moded rescue `-r` writes a working RNDIS composition).
INFERRED trigger: any port-status change while running (replug, and
possibly suspend-resume USB renegotiation). Workaround: reboot the
phone (or live-fix: `echo 02 > .../rndis.usb0/subclass`, `echo ff >
.../rndis.usb0/protocol`, rebind UDC — TESTED 2026-11-23: Windows then
binds; note `protocol 00` makes Windows see a plain CDC-ACM serial
instead). Fix direction: make the usbdp/ container USB-HAL path write
RNDIS codes (or pin usb-moded as gadget owner). Wifi SSH
(`root@<lan-ip>`, port 22 open) is the reliable fallback channel —
used for the entire 2026-11-23 session after RNDIS broke.


## 2026-11-23 (late) — Defect #16: composer identified (usbdp exonerated), pinned-composer fix integrated and validated

### Replug experiment with traps armed (TESTED)

Setup: 1 s gadget watcher (descriptors + function-dir mtime + UDC state →
`/userdata/gadget-watch.log`), strace on usbdp_gbinder (PID 5556) and on the
container `android.hardware.usb-service` (PID 4024). User cable replug while
the gadget was owned by the ad-hoc `/userdata/husky-usb-diag` composer
(2026-11-23 session leftover; `husky-usb-diag.service` with
`Conflicts=usb-moded.service`; NOT part of the repo image).

Result: **defect #16 did NOT reproduce.** UDC cycled
`configured → not attached → configured`; descriptors never changed; the
SSH session over RNDIS and the Windows adapter survived the replug.

- **usbdp_gbinder EXONERATED** (2026-11-23 log's attribution RETRACTED):
  the entire strace is `IUsbCallback.notifyPortStatusChange` callback
  relaying — zero configfs access (the binary carries no configfs strings
  either). It only logs callbacks to stdout.
- Container `android.hardware.usb-service`: only reads typec/power sysfs.
  No configfs path exists in the container.
- usb-moded was INACTIVE this boot (diag `Conflicts=` pin) — yet the
  gadget was fully composed, proving the diag script (not usb-moded)
  composed it. The 2026-11-23 broken composition (rndis.usb0 +
  mass_storage.usb0, ECM codes) matches **usb-moded's** composition shape;
  usb-moded's replug recomposition is now the prime defect-#16 suspect —
  INFERRED, not re-confirmed on a usb-moded-owned boot (would need a
  diag-disabled reboot + replug; parked, low value).

### Class-code matrix on Windows 11 host (TESTED, same device, same session)

Composition (class/subclass/protocol) → Windows result:

| Codes | os_desc RNDIS | Windows result |
|---|---|---|
| 02/06/00 (kernel default) | present | works only when the MS OS descriptor query is honored (adapter "Remote NDIS Compatible Device"); code 28 when it is not (the original defect) |
| 02/02/ff | present | **usbser.inf wins** ("USB Serial Device COMx"); compatible IDs contained only `USB\Class_02&SubClass_02&Prot_ff` — `USB\MS_COMP_RNDIS` was never generated. os_desc matching is NOT reliable across re-enumerations |
| **e0/01/03** (Android tethering) | present | **inbox match `USB\Class_E0&SubClass_01&Prot_03`** → "Remote NDIS based Internet Sharing Device", Up at 426 Mbps, no os_desc dependency |

Validation of e0/01/03 + pinned composer: full cable replug survived
(descriptors untouched, UDC reconfigured, adapter stays Up, SSH over RNDIS
uninterrupted). Windows-side note: a newly-enumerated RNDIS devnode starts
with APIPA; assign 10.15.19.83/24 to the new adapter (needs admin) or wait
for the address from the usual host playbook.

### Fix integrated (repo)

`overlay-debug/system/usr/libexec/husky-rndis-rescue` +
`husky-rndis-rescue.service` (`oneshot`, `RemainAfterExit=yes`,
`Conflicts=usb-moded.service`, `Before=usb-moded.service`, WantedBy
multi-user.target): composes g1 = RNDIS-only, idVendor 18d1, idProduct
4ee3, os_desc MSFT100/RNDIS, **class codes e0/01/03**, binds UDC, sets
usb0 = 10.15.19.82/24. Replaces the ad-hoc on-phone state with the same
mechanism, now with validated descriptors. Debug images only (normal images
have no rescue RNDIS path). `validate-overlay.sh` PASS; script smoke-tested
live on device (composition correct after run).

Phone-side interim state (until next flash): `/userdata/husky-usb-diag`
updated in place to write e0/01/03 so an unexpected reboot keeps the
validated composition. Post-flash cleanup: remove
`/etc/systemd/system/husky-usb-diag.service` + `/userdata/husky-usb-diag*`
(the integrated service supersedes them; both composers running would
fight over descriptors — diag lacks the e0/01/03 writes).

Defect #16: **CLOSED-WORKAROUND** (pending one validation on the integrated
image: flash → boot → replug). Residual INFERRED item: usb-moded as the
original replug-time recomposer.


## 2026-11-24 — d4c88d4 flashed; defect #16 CLOSED; BT host-wake root-caused and quiesce validated; defect #12 stays OPEN

### Flash + defect #16 closure (TESTED)

- Flashed the `d4c88d4` debug set (kver `g799ecb77416a`, slot `_b`) via
  the corrected rootfs path: extract `system_a` from the CI super
  (`husky-verify/lp-extract.py`), dd into `/dev/mapper/system_a` live
  (ro rootfs), forced reboot. The earlier "initrd reflashes from
  /userdata/system_a.img" note was WRONG — the halium initrd only
  dm-maps the on-device super; `/userdata/system_a.img` is a staging
  copy. `/etc/systemd/system` is a persistent bind from
  `/userdata/system-data/etc/systemd/system` (units survive reflashes).
- Defect #16 replug test PASSED on the integrated image: dwc3 role
  cycled, configfs descriptors stayed e0/01/03, Windows adapter
  re-enumerated Up 426 Mbps, RNDIS SSH verified. Interim
  `/userdata/husky-usb-diag*` removed after the pass; the integrated
  `husky-rndis-rescue` alone composes the gadget at boot. **Defect #16
  CLOSED.** Evidence: `husky-verify/idle-suspend-20261124/replug-test-20261124.log`.
- Packaging fix `f7ead41`: the CI image had shipped the system-sleep
  hooks non-executable (100644; systemd-sleep ignores them). Fixed to
  100755 in git; the earlier 11/11 validation had only worked because of
  a manual 0755 injection.

### PM_AUTOSLEEP parked (project decision)

Overnight soak on the PM kernel: zero successful suspends, 52,969
recorded failures; sampled failures at freeze with `-EBUSY` while the
dhd `wl-1` wakelock was held (cause not established for every historical
failure). The autosleep path has no Wi-Fi-quiesce mechanism
(systemd-sleep hooks do not run on it). PARKED by project decision; no
autosleep-path quiesce to be built; autosleep disarmed. Evidence:
`husky-verify/pm-autosleep-20261123/`. repowerd on the non-PM kernel
uses the logind path (Libsuspend init fails, `LogindSystemPowerControl`
selected). Incoming-call wake and BT regression tests transferred to the
logind track.

### Defect #12 status (precise wording)

The failure signature is reproduced and the quiesce/auto-heal
workarounds are validated on the recorded logind paths (11/11 manual
2026-11-23; automatic repowerd path 2026-11-24,
`husky-verify/idle-suspend-20261124`). The trap is associated with the
Broadcom firmware/driver resume path, but the underlying mechanism
remains UNKNOWN; P4 established a 33-second reproduction, not a
universal duration threshold. **Defect #12 stays OPEN** (2026-11-24
decision); the workaround does not close it.

### BT host-wake: root cause and validated quiesce (TESTED)

- Symptom: every BT-on deep suspend woke in ~0.5 s. Wake source
  `bt_host_wake` (IRQ 514, gpn6-0 "odm:btbcm") + AOC mailbox (IRQ 423).
- Isolation (`husky-verify/bt-hostwake-20261124/`): stock zuma DTS +
  nitrous driver are correct (host-wake active-high edge; driver
  deasserts DEV_WAKE then `enable_irq_wake` at suspend). No runtime IRQ
  wake-arming mask exists (gpn6 has no set_wake;
  `/sys/kernel/irq/N/wakeup` read-only). The nitrous logbuffer
  (`/dev/logbuffer_btlpm`) showed a BT UART transaction IN FLIGHT at
  suspend entry; the writer is the container's `bcmbtlinux` (sole
  `/proc/bluetooth/sleep/btwrite` holder). BlueZ adapter power-off does
  NOT prevent it (E1); there is no background traffic (45 s idle watch);
  the transaction is suspend-triggered.
- Quiesce VALIDATED: stop `bcmbtlinux` pre-suspend, restart post-resume,
  preserving the BlueZ adapter's initial state (a `bcmbtlinux` start
  powers the adapter on as a side effect — caught and fixed). Four deep
  suspends with BT on: 49.4/12.6/~15/~26 s, all woken by the
  environmental family (cp2ap/rtc-alarm0/s2mpg14), ZERO bt_host_wake.
  Earbud reconnect + A2DP user-confirmed. Wi-Fi hooks unchanged; zero
  defect-#12 signatures.
- Integrated as `00-husky-bt-quiesce` (overlay-debug) alongside the
  unchanged Wi-Fi quiesce/auto-heal — pending flash.
- Remaining limiter: environmental wakers (12–49 s). Measure unattended
  cycles before choosing an aggressive auto-suspend timeout; the
  persistent default is a SEPARATE later change.

### New tools

- `husky-verify/lp-extract.py` — liblp (super) logical-partition
  extractor (header magic 0x414c5030; 52 B partition / 24 B extent
  entries).

## 2026-11-25 — Defect #10 root-caused + fixed (urfkill boot race); hotspot re-test on current image

**Defect #10 (airplane/flight-mode UI) — ROOT CAUSE + FIX, validated.**
urfkilld starts at ~12 s into boot, BEFORE /dev/rfkill and the rfkill
switches exist (they appear with the container/driver load seconds later);
it fails the control-device open once ("Error opening RFKILL control
device"), never retries, and enumerates ZERO rfkill killswitches for the
whole boot — so the Lomiri indicator flight-mode/Wi-Fi toggles (which call
org.freedesktop.URfkill FlightMode) had nothing to act on and no-opped.
The Settings airplane toggle worked because it is NM/rfkill-backed, not
urfkill-backed. Evidence chain: boot journal error line; post-boot
EnumerateDevices = only two ofono WWAN devices; after a manual urfkilld
restart (devices present) = 6 devices incl. rfkill 0/1/2/17 and the
indicator code path (UrfkillFlightModeToggle -> org.freedesktop.URfkill
interface, polkit allow_active=yes) verified end-to-end.

FIX: `overlay-debug/system/etc/systemd/system/urfkill.service.d/
rfkill-wait.conf` — After=dev-rfkill.device + bounded ExecStartPre wait
(<=20 s) for /dev/rfkill + first rfkill switch. VALIDATED on the
2026-11-25 21:53 reboot: no open error, "adding killswitch" lines at
boot, EnumerateDevices = 6, no state re-block (saved-states clean),
Wi-Fi auto-connects, user-confirmed indicator airplane toggle works.

Operational notes: urfkilld persists per-type soft states in
/var/lib/urfkill/saved-states and re-applies them on start (a mid-session
restart with stale "blocked" state will re-block Wi-Fi — check
saved-states first). The shipped org.freedesktop.URfkill dbus policy
allows only the plain org.freedesktop.URfkill interface — that is the
interface the indicator actually uses (the Killswitches-named interface
does not exist on urfkill 0.6.0); no dbus policy change is needed.

**Hotspot (defect #8 family) — re-tested via the indicator's own API on
the current image: WORKS.** Driving com.lomiri.connectivity1 Private
SetHotspot{ Ssid,Auth,Password,Enabled} exactly as the Settings UI does:
wlan1 came up as AP "HuskyTest" in ~5 s and tore down cleanly on disable.
The 2026-11-20 "creation took too long" failure does not reproduce on
this build. mechanicd wifi_change_fw_path returns -1 (Critical log) but
is non-fatal — brcmfmac needs no firmware switch; the indicator proceeds
and finds wlan1 immediately. RESIDUAL GAP (upstream indicator code, not
husky-specific): after hotspot-off, Wi-Fi does NOT auto-reconnect — the
indicator's setDisconnectWifi(false) only re-enables autoconnect, while
its earlier user-requested deactivate blocks NM autoconnect; an explicit
ActivateConnection (or manual reconnect) is needed. Recorded as an
upstream lomiri-indicator-network issue; not fixed here.

## 2026-11-26 — Ubuntu Plus visual modernization integrated (Phases 2–7)

The approved Ubuntu Plus theme work (spec: user's "Husky Ubuntu Plus Lomiri
Modernization Plan", evidence husky-verify/ubuntu-plus/) is integrated into
`overlay/` (ships in normal AND debug images). All files are full-file
replacements of stock UT QML; every change was prototyped live on-device via
the reversible loop (backup -> rw window -> session restart -> user visual
review) and approved phase by phase. Device-side originals + SHA256SUMS:
/userdata/theme-backup/.

Integrated files (13):
- Themes/Ambiance/1.3/AmbianceNormal.qml — light tokens: warm ground #FAF9F7,
  aubergine-charcoal text #2C252B, orange accent family (#E95420 graphics /
  #C7430F text+focus), orange selection wash.
- Themes/SuruDark/1.3/SuruDarkNormal.qml — dark tokens (user runs dark mode;
  plan's "do not edit SuruDark" superseded by user decision 2026-11-26):
  near-black warm ground #0D0B0C, field #080707, surfaces #1F1C1D, warm
  off-white text #F4F1EE, orange accent (brand orange graphics, #F4743B
  small accent text), all WCAG-checked (see PROPOSED-TOKEN-DIFF-DARK.md).
- Themes/Ambiance/1.3/PageHeaderStyle.qml — title/subtitle Font.Light ->
  Font.Normal (typography hierarchy).
- Themes/Ambiance/1.3/TextAreaStyle.qml + FocusShape.qml — field/focus-ring
  radius gu(1.7) -> gu(1.2) (~10 px, spec radius hierarchy).
- Themes/Ambiance/1.3/SwitchStyle.qml — checked switch positive(green) ->
  activity(orange) per user decision.
- Launcher/LauncherPanel.qml, Launcher/Drawer.qml,
  Launcher/LauncherDelegate.qml — hardcoded shell surfaces warmed to the
  theme family (#F2FAF9F7 / #F20D0B0C panel+quicklist+shortcut-hint,
  #CAFAF9F7 / #BF0D0B0C drawer, tooltip -> #1F1C1D); notification count
  badge positive -> activity(orange). Home button already LomiriColors.orange
  by default (no change).
- Panel/Panel.qml, Panel/PanelMenu.qml — top bar + indicator menu surface
  #FFFFFF/#000000 -> #FAF9F7/#0D0B0C.
- Notifications/Notification.qml — card radius "small" -> units.gu(1.5)
  (~12 px cards; numeric radius accepted by LomiriShape, journal-clean).
- Greeter/ButtonPrompt.qml — passcode pill #7A111111 -> #7A0D0B0C,
  radius gu(0.5) -> gu(1). No auth behavior touched.

Untouched by design: icon sizes/labels/touch targets, gestures, indicator
behavior, PAM/passcode policy, positive/negative semantics, all structural
QML. Wallpapers NOT included — final artwork to be supplied by an external
artist (spec Phase 8 deferred); local prototype candidates remain in
husky-verify/ubuntu-plus/phase8/ (original generative art, 3 renderer
generations, sources included).

Known cosmetic notes: pre-existing stock QML startup noise unchanged
(Panel.qml:451, ImageResolver.qml:51, OrientedShell.qml:309, greeter
null-model TypeErrors) — all verified present on the 2026-11-25 stock boot.

## 2026-11-26 (pm) — Ubuntu Plus Phase 3-5 on-device results (spec v2)

All user-approved live on device; repo integration STAGED in overlay-debug
(uncommitted, push held by user); commits 798441b + 2c40a25 still local-only.

- Phase 3 icon pilot: 62 original parametric SVGs (generate-icons.py),
  deployed to /usr/share/icons/suru/{status,actions,apps}; 5 stock-symlink
  names replaced with real files after restoring clobbered targets from the
  system_a backup image (see overlay-debug .../suru/SYMLINK-NOTE.md).
  Icon cache rebuilt; zero missing-icon errors.
- Phase 4 Stage A: PanelItemRow selected-tab underline -> palette activity
  (orange); IndicatorItem unselected tab labels -> backgroundTertiaryText.
  Cutout spacing audited: no Lane-A knob exists (emergent layout) — skipped.
- Phase 5: mouse/printing .settings entries removed (user-approved; the
  form-factors filter is unimplemented in lomiri-system-settings 1.3.2);
  about page gained read-only Kernel + Build rows via the existing
  StorageAbout plugin API (no new backend, redaction reviewed).
- Operational lesson (IMPORTANT for future image/edit work): never use
  sysrq-u as a remount fallback — sda34 carries a permanent orphan inode
  (deleted zram_swap held by loop36), so forcing /userdata ro makes it
  un-remountable rw until reboot. When the icon cache was replaced, restart
  the session FIRST (releases the deleted cache), then remount ro normally.
  Two user-approved reboots occurred; phone healthy after each.
- Evidence: husky-verify/ubuntu-plus/{phase3-icons,phase4-panel,
  phase5-settings}/ + VALIDATION-20261126.md.

## 2026-11-26 (eve) — User asset pack integrated on-device; overlay-debug refreshed

User supplied their own "Ubuntu Plus Project Icons" pack (v0.4) + 12
wallpapers, superseding the generated pilot icon set. Applied on device:
- 81 shell/status/settings icons baked from the pack (currentColor->on-dark
  foreground; battery level variants baked into the pack outline incl.
  charging; cellular bar-count levels; wifi secure = padlock composite;
  battery family scaled 1.18x after user size feedback).
- 18 app icons mapped via installed .desktop Icon= paths (click apps +
  core system apps; third-party clicks untouched).
- Dark keyboard: maliit SuruDark.json retuned to the warm dark family +
  gsettings theme switch (user-approved "great"); light Ambiance keyboard
  also retuned and retained.
- Stage fixes: WorkspacePreview selected border blue->orange;
  FakeMaximizeDelegate/ResizeGrip warmed.
- 12 pack wallpapers on device (Pictures/Wallpapers/Ubuntu Plus).
overlay-debug refreshed to match (108 files: pack icons, app icons,
keyboard themes, Stage/Panel/settings QML). validate-overlay.sh PASS.
NOT committed; push still held by user. Build-time packaging notes:
overlay-debug/system/usr/share/icons/suru/SYMLINK-NOTE.md.

## 2026-11-27/28 — Stage 5: Settings modernization (spec §9, Gates 1-2 approved)

Full IA rework of lomiri-system-settings 1.3.2, QML/manifest-only:
- Custom landing (qml-plugins/landing/EntryComponent.qml, uncategorized-top
  entry): grouped card sections with live values (Wi-Fi/BT on-off, volume %,
  battery % via upower, brightness %, cellular state), in-place search
  filtering via pluginManager.filter, navigation via shell loadPluginByName.
- 3 submenu hubs (More connections / Personalization / System & updates +
  Danger zone) pushing STOCK pages unchanged via pluginManager.getByName().
- 23 stock manifests demoted to unrendered "hub-internal" category (loaded,
  deep-linkable, invisible on landing); renames: About phone, Sound & haptics.
- Key architecture facts recorded in husky-verify/ubuntu-plus/phase5b-settings/:
  landing grid is qrc-compiled (5 fixed sections), rich entry-components and
  hub pages are the supported extension points; hide-by-default would break
  deep links (do not use).
- Backups: /userdata/settings-backup/phase5b/ (26 originals + SHA256SUMS).
- User-approved on device; app-restart iteration only, no session restart.

## 2026-11-28 — Unified Icon Concept 1.0.0: Phases 0-4 (pilot + Light rollout)

Migration per "Ubuntu Plus Unified Icon UI Migration Plan" + readiness pack
(evidence: husky-verify/ubuntu-plus/icons-migration/). Source ZIP hash
verified (1b831e29...); 28-concept inventory validated (18 installed /
10 not-installed / third-party retained); fail-closed validator PASS.

- Phase 2: 40 deterministic exports (Qt SVG renderer; 512 masters +
  128px PNG targets for calendar/media-player), five Light+Dark
  before/after proofs approved by user (Gate M2).
- Phase 3 pilot (calculator/clock/notes): deployed byte-identical to
  approved exports; rollback proven (hashes restored exactly).
  KEY OPERATIONAL LESSONS: (1) app-icon reload requires killing the
  thumbnailer daemon AND restarting lomiri-full-greeter — shell restart
  alone serves stale pixmaps; (2) NEVER strace the live compositor —
  it wedges the display pipeline (recovered via clean shell restart,
  no reboot needed).
- Phase 4 Stage A: all 18 installed project apps now carry the Unified
  Light family (16 SVG + 2 PNG at 128x128, owners/modes preserved,
  sha256-verified vs export manifest). Third-party branding untouched.
  Originals (v0.4) in /userdata/icon-stageA-backup/ + git history.
- Phase 5: Dark family PREPARED — NOT ACTIVE (no supported selection
  mechanism on this image; separate Lane B/D proposal required).
- User visual pass approved; rootfs returned to ro; no reboot, no CI,
  no flash. Commit prepared in overlay-debug, push held by user.

## 2026-11-28 (pm) — Stage 4B: Quick Controls landing in the pull-down panel

Per approved v4.1 mockup 06, replacing the staged v3/v4 prototype:
- LandingPage v5: "Controls" header + "Pixel 8 Pro · N% battery" (BatteryMonitor,
  hidden if unavailable); 7 coloured state tiles (Wi-Fi/BT/Mobile/Rotation/
  Silent/Location/Hotspot — accent fill + status dot when ON, dark when OFF,
  live state text incl. "No SIM"); brightness + volume sliders bound to the
  display/sound indicator actions (restore-binding pattern, no optimistic UI).
  No Torch tile: no flashlight backend on this image (spec rule).
- LandingTile: new mockup-06 tile component (tap = toggle, long-press =
  indicator submenu deep link; state-honest: colour follows action.state only).
- v4 architecture retained: landing + calendar pager replaces the per-indicator
  pager in landing mode; indicator pages open as overlay submenu with back row;
  bar stays collapsed. All tile icons verified present in suru pre-deploy.
- Deployed to /usr/share/lomiri/Panel/ (7 files, device == staged copies),
  zero QML errors on shell restart, user visual pass approved.
  Backups: /userdata/stage4b-backup/ (5 replaced files + SHA256SUMS).

### Stage 4B polish (same session): accent sliders + now-playing card

- AccentSlider.qml: per-instance accent slider (stock Slider colours are
  theme-style-only); amber brightness / pink volume per mockup 06; honest
  snap-back on rejected writes.
- Now-playing card: bound to the sound indicator's media-player action
  state; visible ONLY while the stock player runs (no placeholder);
  prev/play-pause/next via the indicator's own actions. Supports the stock
  media player id; other players hide the card (recorded limitation).
- "Silent" tile keeps its honest name (UT silent-mode is not DND).
- One scoping bug found+fixed on deploy (playerState on wrong object).
  New shell instance clean (only documented stock startup noise).

### Settings hubs v3 (same session): mockup-13 stacked cards

Hub pages restyled to the v4.1 submenu language: per-row cards with coloured
icon chips + subtitles; live status value only where a truthful backend
exists (Hotspot On/Off via the network indicator action). Navigation and
stock pages unchanged. Zero QML errors; user-approved on device.

### Quick Controls extras (same session): flight-mode tile + multi-player probe

- 8th tile: Flight Mode (slate accent, airplane-mode icons, network submenu
  on long-press) — grid now 2 full rows.
- Now-playing card generalized: QDBusActionGroup cannot enumerate actions,
  so known player ids are probed on a 2s timer (mediaplayer + music app ids);
  first running player wins; unknown players honestly hidden. Transport
  actions resolved per active player. Limitation recorded: click id versions
  need updating on app upgrades.
- Deployed clean (no LandingPage errors); user-approved direction "all of it".
- Docs: icons-migration/DARK-ACTIVATION-PROPOSAL.md (recommendation: keep
  Dark packaged/inactive), ubuntu-plus/NEXT-SURFACES-PROPOSAL.md (scoping).

## 2026-11-28 (eve) — v4.1 batch: lock screen, notification pills, Wi-Fi hero

Final feasible v4.1 surfaces, one batch (user-directed "all at once"):
- Greeter (mockup 01): hero clock gu(7.5)->gu(10.5), date "dddd, d MMMM";
  "Swipe up to unlock" + handle bar (error-message path and fade animation
  preserved). Rebased onto live files (warm-white #F4F1EE drift from an
  earlier phase caught by pre-deploy cmp check).
- Notifications (mockup 07): action buttons -> full pills, readable weight.
- Wi-Fi settings (mockup 13): display-only hero status card (chip + on/off
  status word); no duplicate toggle, no faked SSID. Installed wifi page
  diffed vs upstream first (174-line installed variant, NOT master).
- Lock-screen weather/media widgets intentionally omitted (no such greeter
  widgets exist on UT — no placeholders).
Backups: /userdata/batch-final-backup/. Zero QML errors; user-approved.
