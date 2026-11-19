# AGENTS.md — Pixel 8 Pro Ubuntu Touch port

## Objective
Early Ubuntu Touch bring-up on Pixel 8 Pro. Use evidence-based,
one-variable experiments. Never revisit an exonerated theory without
new contradictory evidence.

## Read order
1. This file, especially "Current state".
2. deviceinfo and .github/workflows/build-final.yml for current configuration.
3. BRINGUP-LOG.md only for the experiment or evidence explicitly needed —
   always read the NEWEST dated section first; retracted/superseded items
   are marked inline.
4. README.md for the target hardware matrix, not proof of functionality.

BRINGUP.md IS the current build/release/flashing guide (GitHub Actions
pipeline). It does NOT contain Forgejo instructions; the migration is
archived in docs/archive/2026-11-03-migration.md (historical only).
GitHub Actions is the current pipeline unless Current state says otherwise.
RESUME-NOTES.md is the resume entry point; its priority list ages —
cross-check it against Current state. The live working handover and
experiment queue live in husky-verify/NEXT-SESSION-NOTES.md on the
bring-up host (outside this repo). Dated "running now" / "TEST IN FLIGHT"
passages in BRINGUP-LOG.md are historical unless reaffirmed in Current
state.

## Fixed facts
- Device: Google Pixel 8 Pro
- Codename: husky
- SoC/platform: Tensor G3 / zuma
- Architecture: aarch64
- Base: Halium 16 / Android 16
- Ubuntu Touch: 24.04-1.x
- Reference userspace/vendor stack: LineageOS 23.2 husky
- Device repo: L55-CMD/device-google-husky
- Kernel manifest: L55-CMD/lineage-kernel-manifest-husky
- Kernel patches: L55-CMD/kernel-patches-husky
- Package/reference artifacts: L55-CMD/husky-packages

The kernel is built through the kernel-manifest CI using the patch repo.
Canonical boot tests use CI-produced images from matching branches.
Local ./build.sh invokes the Halium adaptation build tools.

## Experiment discipline
- Work on exactly one subsystem or hypothesis per session.
- Before editing, state:
  1. hypothesis;
  2. variable being changed;
  3. expected observable result;
  4. branch and artifact that will test it.
- Keep unrelated overlay, cmdline, config, and toolchain changes out
  of a discriminating kernel experiment.
- Label claims TESTED, INFERRED, or UNKNOWN.
- Never mark hardware working from source inspection alone.
- Save complete logs locally; put only relevant excerpts in chat.
- Never include PATs, passwords, device serial numbers, or other secrets.
- Ask before fastboot flash/erase, destructive git operations, or
  unsolicited device reboots.

## After every build or flash test
Replace "Current state" with:
- UTC date
- branch and commit
- exact images tested
- result and failure signature
- evidence file/location
- newly exonerated hypotheses
- single next discriminating action

Keep Current state below 80 lines. Append historical detail to
BRINGUP-LOG.md instead.

## Current state
2026-11-19T11:00Z

- Commits: device-google-husky @ test-audio-restore-ltonone 44f2ea6 (+ small
  UNCOMMITTED wording fixes in AGENTS.md/BRINGUP-LOG.md); kernel-patches-husky
  24ffa8d (CONFIG_LTO_NONE=y); lineage-kernel-manifest-husky 2f6f5fd.
- RUN-98 LTO_NONE TEST: PASS AT THE 13.9s MARK (TESTED on device).
  Full matched 5-image set (boot/init_boot/vendor_kernel_boot/vendor_boot/
  dtbo -> *_b) flashed 2026-11-19 10:51Z via the new
  husky-verify/flash-ltonone-full.sh; one reboot; observed to uptime 120s+.
  lsmod: pkvm_s2mpu_v9 + samsung_iommu_v9 + samsung_iommu_group all loaded;
  samsung-sysmmu-v9 bound to 26 sysmmus INCL. 11040000 (HSI0); mfc-core
  bound to 1a4d0000.MFC-0; dwc3 gadget + RNDIS/SSH alive (the HSI0 master
  that used to fault). Live dmesg: ZERO s2mpu/access-fault/PTW/panic lines;
  the 13.5-14.5s window shows normal ext4/overlay mounts.
- VERDICT: CONFIG_LTO_CLANG_THIN(+CFI) CONFIRMED as the breaker of the EL2
  S2MPU host-stage-2 notifier path (hypothesis open since 2026-11-17).
  LTO_NONE is currently the only known-booting config for this chain.
- Root cause of the 2026-11-18 bootloop (separate issue, SOLVED): incomplete
  flash — vendor_kernel_boot_b had not been re-flashed; halium initrd buried
  modules.load on kver mismatch. Device build was never at fault.
- Artifact hashes (== CI rolling release, boot-images.zip 7276a00c...e3d,
  MANIFEST device b808d33 = run 98): boot.img 6764e3c5...01eef,
  init_boot.img 3476aad7...440dd, vendor_kernel_boot.img da3e1db5...e78f,
  vendor_boot.img a3a44eba...872c, dtbo.img 3dba3e31...4798c.
  Kernel string + module dir + .ko vermagic all = 6.1.145-android14-11-
  gc9a0580a0791 (verified pre-flight).
- Evidence: husky-verify/tmp/ltonone-full-20261119-105157/
  {post-boot.txt, dmesg-live.txt, console-ramoops-0.log}. NOTE: the
  console-ramoops archive is the PRIOR r8-baseline boot's console (systemd-
  pstore archives at boot start); this boot's console is in dmesg-live.txt.
  Unpacker: husky-verify/tmp/unpack-init_boot.py (lz4-legacy u32 framing).
- r8 rollback set: verified present + hash-good (boot-images.zip_ 84ac198d,
  all 5 images match in-zip) at husky-flash/r8-baseline-debug/boot-images/.
- Phone: run-98 LTO_NONE debug on slot b, UP, SSH OK (10.15.19.82), battery
  99% charging. Rollback available if needed. User session on device:
  YouTube playback WORKING, bottom-screen artifact ABSENT.
- Remaining defect #6 acceptance: clean-shutdown test (second reboot —
  user decision). YouTube playback: WORKING (user-verified on this boot
  2026-11-19). BONUS: defect #1 bottom-region scanout artifact GONE on this
  build (user-verified) — the quirk/DSC-bisect queue is moot; mechanism
  UNKNOWN (suspects: LTO miscompile in the display path, or fall-out from
  the previously domain-less IOMMU/display modules). Re-test the quirk
  flag only if tearing reappears.
- Next actions: (1) merge decision — keep LTO_NONE in halium.config on the
  mainline patch branch (revisit CLANG_THIN only with a targeted fix);
  (2) cherry-pick b808d33 onto test-audio-restore; (3) defect #7 audio stub
  tests can run on THIS boot (helpers: husky-verify/audio-20261112/);
  (4) display force60/wqhd queue unchanged.
