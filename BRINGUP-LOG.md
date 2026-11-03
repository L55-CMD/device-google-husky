# Husky bring-up log (2026-11-03, evening session)

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
