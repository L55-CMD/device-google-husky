# Husky bring-up log

## ROOT CAUSE FOUND (2026-11-04 ~10:05 UTC)
Kernel is NOT hanging - it PANICS at ~1.41s every boot:
  CFI failure at exynos_usbdrd_s2mpu_manual_control+0x74 [phy_exynos_usbdrd_eusb_super]
  (target: etm2dram_probe+0x1a8 [etm2dram]; expected type 0xd1c748b3)
  Call trace: exynos_usbdrd_s2mpu_manual_control -> dwc3_exynos_probe (deferred probe)
Mechanism: dwc3_exynos_usb's function pointer for exynos_usbdrd_s2mpu_manual_control
CONTAINS THE ADDRESS OF etm2dram_probe - a cross-module binding/relocation fault INSIDE
ONE consistent build (modules from same r12 build, kver matches). Classic thin-LTO
mis-link signature. Our kernel: CONFIG_LTO_CLANG_THIN=y; LOS kernel: CONFIG_LTO_NONE=y.
tegu (works, same patch set, byte-identical aosp/ patches) is on zumapro - zuma code +
thin LTO + our patchset trips it; zumapro doesn't.

VISIBILITY METHOD THAT WORKS (reuse this!): flash our boot.img + LOS vendor_boot +
our init_boot/vkb/dtbo -> reboot (panics ~1.4s, screen dies, resets to fastboot ~40-90s
or 'frozen logo' - cosmetic timing) -> flash full LOS stack -> fastboot reboot recovery
-> adb (state shows 'recovery' after a while; accept auth dialog) -> cat
/sys/fs/pstore/console-ramoops-0. Buffer holds 257KB incl. PRE-boot DSS panic record.

ALSO LEARNED: any cmdline in boot.img changes failure flavor (reset vs frozen) -
test with CI images; cmdline content bisect was a red herring.
CFI_PERMISSIVE from halium.config silently not in effect (# CONFIG_CFI_PERMISSIVE is
not set in built image) - wouldn't matter, the pointer itself is wrong.

NEXT: r12-lto-none build (tools/bazel run --lto=none ... zuma_shusky_dist) - if it
boots, permanent fix = disable LTO (match LOS). los-pure build = no halium patches
axis also in flight. Watch for NEXT crash after USB PHY (display handoff / initrd
rootfs mount) - pstore loop above gives eyes.

pstore capture saved locally: ~/bootdebug/pstore-ours-kernel.txt (also 2-boot record
in same buffer: u18:4 and u18:5, identical crash).

---

## RESUME HERE (state at end of day 2 morning, 2026-11-04 ~09:10 UTC)
**Running now:** TWO kernel builds on CI (pushed ~08:58 UTC, ~1h each):
- `test-los-pure`: STOCK LOS kernel content (no halium patches/config) on our kleaf
  pipeline, kernel/common r12. Question: does our BUILD PIPELINE produce a booting kernel?
  Boots to ~20s like LOS nightly -> pipeline exonerated, halium patches/config guilty.
  Frozen -> kleaf flags/LTO/toolchain chain guilty.
- `test-kernel-r12-lto-none`: r12 + halium patches/config but `--lto=none`
  (LOS kernel is LTO_NONE=y, ours LTO_CLANG_THIN=y - never-tested axis).

**When each kernel build succeeds:** dispatch device build on the SAME-named branch in
device-google-husky (branches already created):
`POST /repos/l55-cmd/device-google-husky/actions/workflows/build-final.yml/dispatches {"ref":"<branch>"}`

**Then:** download boot-images.zip from release `latest-<branch>` -> phone to fastboot
(Power+VolDown) -> flash boot stack (super unchanged) -> reboot -> watch screen.
NOTE: after many failed boots ABL boot-loops and fastboot screen may be BLACK but USB
fastboot still works - just flash. `fastboot set_active b` stabilizes.

## Day 2 results (2026-11-04 morning)
- r12 kernel VERIFIED to contain CONFIG_ARM64_ERRATUM_4118414=y (IKCONFIG extracted from
  Image.lz4: lz4 legacy frame + IKCFG_ST magic; lz4.exe in ~/bin, python-lz4 CANNOT do it).
  Erratum theory dead as sole cause: mitigation present, canonical r12 still FROZEN LOGO.
- Canonical CI r12 boot-images (latest-test-kernel-r12): FROZEN LOGO (same as main r8).
- Local repack r12 (kernel-only boot.img, empty cmdline): BLANK -> fastboot fallback (~60s).
  Repack is NOT behavior-equivalent to CI image (bootconfig/ramdisk sections differ) -
  always test with canonical CI images from now on.
- r12 + boot.img cmdline lsm=selinux (no kvm override): FROZEN LOGO. Yesterday's
  "lsm override progresses" was confounded by kvm-arm.mode=protected.
- pstore empty after every failure mode - still zero kernel visibility into the hang.
- LOS kernel + halium initrd (our init_boot) + LOS vkb/dtbo: boots past logo, dies
  ~90-100s -> fastboot fallback. EXPECTED: LOS kernel config lacks SQUASHFS/PID_NS/
  anbox-binder (config diff confirms) -> cannot mount UT rootfs. CONCLUSION: LOS kernel
  alone cannot run UT userspace; we MUST make OUR kernel boot. Current builds test that.
- Config diff ours(r12) vs LOS kernel: halium features + LTO thin-vs-none +
  MODULE_SIG_PROTECT + default-LSM ordering only. Nothing else suspicious.

## Key assets on this machine
- ~/bootdebug: mkbootimg.py/unpack_bootimg.py, r12-ikconfig.txt, los-ikconfig.txt,
  kernel-r12.lz4/raw, boot-r12-lsm.img (repack recipe: hdr v4, kernel-only,
  --os_version 16.0.0 --os_patch_level 2026-09)
- ~/bin/lz4.exe (handles legacy lz4 frame)
- ~/husky-flash (our images + super), ~/husky-verify (LOS 23.2 stack),
  /tmp/r12-boot (canonical r12 images; C:/Users/lukes/AppData/Local/Temp on Windows)
- Branches: kernel manifest test-kernel-r12 (bumped common only),
  test-kernel-r12-lto-none, test-los-pure; kernel-patches-husky@los-pure (stripped);
  device repo branches of same names
- CI dispatches need PAT (repo+workflow scope); watcher auto-dispatches device builds
  when kernel builds succeed.

## Experiment matrix (flashed + watched, day 1+2)
| Kernel variant | Result |
|---|---|
| Full halium (main, r8) | FROZEN LOGO |
| No halium.config fragment | FROZEN LOGO |
| No sched.h ABI padding 0001 | FROZEN LOGO |
| No binder.c hunk of 0014 | FROZEN LOGO |
| No apparmor patches 0007-0012 | FROZEN LOGO |
| clang r487747c pinned | FROZEN LOGO |
| r12 canonical (erratum fix IN) | FROZEN LOGO |
| r12 local repack, empty cmdline | BLANK -> fastboot (~60s) |
| r12 + lsm=selinux cmdline | FROZEN LOGO |
| LOS kernel + LOS stack | boots to ~20s, orderly shutdown (expected) |
| LOS kernel + halium initrd | dies ~90-100s -> fastboot (UT fs unsupported) |
| STOCK LOS content, our pipeline (test-los-pure) | BUILDING - pipeline test |
| r12 + LTO_NONE (test-kernel-r12-lto-none) | BUILDING - LTO test |

## Phone facts
- serial 38111FDJG001WM, slot b, bootloader unlocked; stock was Android 16
- After repeated boot failures: ABL boot-loops, rescue mode possible, fastboot screen
  can be black while USB fastboot stays responsive.

## Failure-mode glossary
- FROZEN LOGO: ABL logo stays, kernel hangs in first 1-3s (before ramoops probe);
  no pstore flush ever observed
- BLANK -> fastboot: panel off then ABL fallback to fastboot (~60-100s)
- los-pure boots to ~20s = pipeline exonerated; frozen = kleaf flags/LTO/toolchain guilty

---
# Day 1 log (archived)
 (2026-11-03, evening session)

## RESUME HERE (state at end of day 1)
**Running now:** `test-kernel-r12` kernel build on GitHub CI (dispatched ~23:05 UTC).
Check: `https://github.com/l55-cmd/lineage-kernel-manifest-husky/actions` (branch test-kernel-r12).

**When the kernel build succeeds:** dispatch device build (branch `test-kernel-r12`
already exists in the device repo):
`POST /repos/l55-cmd/device-google-husky/actions/workflows/build-final.yml/dispatches {"ref":"test-kernel-r12"}`

**When device images land:** download
`https://github.com/l55-cmd/device-google-husky/releases/download/latest-test-kernel-r12/boot-images.zip`
→ phone to fastboot (Power+VolDown) → flash boot stack (super unchanged, ours
is still on the phone) → reboot → WATCH SCREEN. Success = anything other than
frozen white Google logo.

**If r12 boots:** permanent fix = bump kernel/common to android14-6.1-2025-08_r12
in lineage-kernel-manifest-husky default.xml on MAIN. Then continue normal
bring-up (display/touch/WiFi/audio matrix per README).

**If r12 still hangs:** verify the r12 tag actually contains
CONFIG_ARM64_ERRATUM_4118414 (extract IKCFG from a local build or check AOSP
tag contents) before more cycles; then compare kleaf flags against LOS's
published kernel build config, and diff LOS's gs-6.1 lineage-23.2 branches for
out-of-tree erratum patches.

Token: API/dispatch calls need a fresh classic PAT from the user (repo+workflow
scope); previous tokens were chat-visible - assume revoked. CI runs themselves
need no secrets (GITHUB_TOKEN only).

## Pipeline status (all green)
- kernel.zip + boot images + super.img building and publishing on GitHub CI (l55-cmd)
- Images flashed to Pixel 8 Pro successfully (slot b)

## Symptom
- Our full image set: boot hangs forever on white Google logo (no display handover)
- Kernel has CONFIG_PSTORE_RAM=y but ramoops buffer stays empty -> hang before
  pstore console probe (~first 1-3 s of kernel init)

## Experiments so far (evidence chain)
1. Garbage kernel -> ABL shows "boot failure" fast => ABL validates; our kernel starts
2. LOS kernel + our stack -> reaches display handover (black phases), dies ~20 s
   (pstore showed orderly shutdown: LOS ramdisk fails against UT super, expected)
3. Our kernel + LOS ramdisk -> fastboot fallback quickly
4. boot.img cmdline overrides ARE honored by ABL (behavior changed)
5. kvm-arm.mode=protected + lsm=selinux override -> fast fail (not the fix)
6. dtbo.img == LOS dtbo content (first 2.18 MB identical; LOS file just padded to 16 MB)
7. vendor_boot structure == working tegu vendor_boot (4 multi-DTBs embedded ~15.9-17.2 MB,
   same cmdline incl. kvm-arm.mode=nvhe + exynos_drm.dp_rate=2, same 64 MB boot.img padding)
8. LOS kernel boots fine with OUR vendor_boot + nvhe cmdline => nvhe itself OK on husky

## Conclusion so far
Our halium kernel (tegu-proven config/patches/toolchain on identical kernel/common)
hangs in first seconds on zuma where LOS kernel doesn't. Delta candidates:
- shusky_defconfig vs tegu_defconfig builtins x halium.config interaction
- zuma google-modules
- halium.config itself (AppArmor default LSM etc.)

## Running now
- CI branch test-no-halium-config: kernel WITHOUT halium.config fragment (pure GKI+shusky)
  - builds clean -> halium.config is the killer -> bisect its options
  - still hangs -> next: branch without apparmor patches (aosp/0007-0012)

## Key assets on this machine
- ~/husky-flash: our full image set + reassembled super.img (reflashing set)
- ~/husky-verify: LOS 23.2 boot stack (boot.img, los-init_boot.img, vendor_boot.img,
  los-vendor_kernel_boot.img, los-dtbo.img) - the "known-good boot stack" kit
- ~/tegu-ref: Steffon's WORKING tegu images.zip (structural reference)
- ~/bootdebug: mkbootimg.py + unpack_bootimg.py + boot-unpacked/kernel + debug images
- ~/platform-tools: fastboot/adb for Windows
- pstore capture method: flash LOS stack -> fastboot reboot recovery -> accept adb
  dialog on phone -> adb shell cat /sys/fs/pstore/console-ramoops-0
  (ramoops flushes only on panic/clean-kmsg-dump; watchdog/ABL resets leave it empty)

## Experiment matrix (flashed + watched)
| Kernel variant | Result |
|---|---|
| Full halium (main) | FROZEN LOGO |
| No halium.config fragment (test-no-halium-config) | FROZEN LOGO -> config exonerated |
| No sched.h ABI padding 0001 (test-no-sched-padding) | FROZEN LOGO -> exonerated |
| No binder.c hunk of 0014 (test-no-binder-patch) | building -> device images next |
| No apparmor patches 0007-0012 (test-no-apparmor) | FROZEN LOGO -> exonerated |
| clang r487747c pinned (test-clang-r487747c) | FROZEN LOGO -> exonerated |
| LOS kernel (reference) | boots to ~20s |
| kernel/common android14-6.1-2025-08_r12 (test-kernel-r12) | building - LEAD THEORY |

## Lead theory: kernel base too old (TLBI erratum)
LOS pins kernel/common android14-6.1-2025-08_r12; tegu manifest had _r8 (4 respins
behind). Config diff vs LOS kernel showed CONFIG_ARM64_ERRATUM_4118414=y in LOS,
absent in ours - the CVE-2025-10263 TLBI completion erratum affects Cortex-X4
and the whole X/A7xx family (same mitigation series covers Cortex-X3 = zuma's
big core). A kernel without the mitigation can hard-hang in the first seconds
on affected silicon - matches our symptom exactly (hang before ramoops probe).
tegu/zumapro silicon presumably predates or misses the erratum, which is why
tegu works on r8.

## Experiment loop learnings

Build gotchas learned:
- GKI trim build requires BT/RFKILL as MODULES (0014 config hunk makes them =m;
  dropping 0014 config side without compensation fails with 'Unable to find
  net/bluetooth/bluetooth.ko')
- halium.config: hci_vhci needs CONFIG_BT_HCIVHCI; MODULE_OUTS entry must match config
- 0014's halium.config hunk also edits AppArmor lines -> can't be used verbatim
  when the apparmor patches are dropped
- experiment loop: kernel-patches branch + manifest branch (revision pointer) +
  workflow_dispatch + device branch of same name + device dispatch; ~1h per round

Next if all patch experiments fail: pin prebuilts/clang/host/linux-x86 to
r487747c (clang 17.0.2, what LOS builds with; manifest currently floats with
the AOSP tag = newer clang) - possible miscompile of zuma early-boot code.

## Phone facts
- serial 38111FDJG001WM, slot b, bootloader unlocked
- stock firmware: Android 16 (was QPR3 beta - never confirmed which stock build)
- DTBO match seen in LOS-stack boot: id 0x40206 rev 0x10000, SOC DTB index 2,
  panel google-hk3 (husky display) - DTB/DTBO selection works
