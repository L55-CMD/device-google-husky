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

## CORRECTION 2026-11-19 (read before Current state)

RETRACTED CLAIMS (earlier versions of this file and BRINGUP-LOG.md):
"CONFIG_LTO_CLANG_THIN confirmed as the EL2 S2MPU notifier breaker" and
"LTO_NONE is the verified fix". The user extracted the ACTUAL EFFECTIVE
CONFIGS: run-98's kernel AND the rebuilt integrated kernel both contain
CONFIG_LTO_CLANG_THIN=y. The halium.config LTO_NONE fragment is INERT in
the GKI build (google/shusky/halium.config is not an effective defconfig
fragment for the GKI Image — unverified why; do not chase without an
experiment). The 2026-11-17 "LTO_NONE" and "LTO_CLANG_THIN" kernels had
identical effective configs; nothing was isolated by that experiment.

The beneficial run-98 delta vs the panicking kernels (old test-r8-lazylink
stack lineage: g0b2699b6e265, g7e26db69eb15) is the PATCH-STACK DIFFERENCE
(halium-husky/0f72552 lineage vs test-r8-lazylink/6d9a427 lineage) —
UNIDENTIFIED, pending isolation (candidate set includes the dropped s2mpu
lazy-link/self-pin/diagnostic commits). Run 98 remains a VALIDATED
known-good image set; its beneficial source delta is UNIDENTIFIED. The
"ltonone" branch/commit names are historical misnomers; the inert
LTO_NONE fragment stays because it is part of the validated source tree.

## Current state
2026-11-19T21:10Z

- Commits (integrated family, all PUSHED): kernel-patches-husky
  halium-husky = test-audio-restore = 22c33ed (cherry-pick of 24ffa8d;
  tree byte-identical to validated 24ffa8d — the LTO_NONE fragment is
  INERT, see CORRECTION above); lineage-kernel-manifest-husky
  test-audio-restore = a979a7a; device-google-husky test-audio-restore =
  ca7a9ea (67bc584 recovery-pin cherry-pick + 1ce89c5/ca7a9ea buildlog
  diagnostics). device repo also carries this AGENTS.md + BRINGUP updates
  as docs commits.
- RUN-98 (validated known-good, RETAINED): full matched 5-image debug set
  flashed 2026-11-19 10:51Z; boots past 13.9s, lsmod pkvm_s2mpu_v9 +
  samsung_iommu_v9 + group, 26 sysmmus bound incl. HSI0 11040000,
  mfc-core bound, dwc3/RNDIS alive, ZERO s2mpu/access-fault/PTW/panic in
  live dmesg; kver gc9a0580a0791. Hashes: boot 6764e3c5...01eef,
  init_boot 3476aad7...440dd, vendor_kernel_boot da3e1db5...e78f,
  vendor_boot a3a44eba...872c, dtbo 3dba3e31...4798c (zip 7276a00c).
  User-tested: YouTube WORKING; defect #1 bottom-screen artifact GONE
  (mechanism UNKNOWN). Evidence: husky-verify/tmp/ltonone-full-20261119-
  105157/. Effective config: CONFIG_LTO_CLANG_THIN=y (see CORRECTION).
- INTEGRATED REBUILD (offline-verified, NOT flashed): kernel.zip tag
  test-audio-restore digest 8594fe45...4e6 (Image kver g799ecb77416a;
  internal 209-module trees consistent). Device run 44612802506 debug
  green: boot-images.zip fcb8b563...0c6a; boot.img 09891f5e...58c56,
  init_boot e6b1f6e8...01d, vendor_kernel_boot 0fbce5ae...17d,
  vendor_boot bdecf19d...18, dtbo 3dba3e31...98c. preflight-boot-images.sh
  FULL PASS; MANIFEST device ca7a9ea / manifest a979a7a / patches 22c33ed.
  Local copies: husky-kernels/kernel-test-audio-restore.zip,
  husky-flash/tar-audio-lto/.
- 2026-11-18 bootloop root cause (SOLVED, separate): incomplete flash —
  stale vendor_kernel_boot_b; halium initrd buries modules.load on kver
  mismatch. Guard: husky-verify/preflight-boot-images.sh (PASSes good
  sets, REFUSES stale-vkb — negative-tested); wired into flash scripts;
  BRINGUP.md warns.
- Phone: run-98 known-good debug on slot b, user-verified (YouTube,
  display artifact absent). Do NOT reflash merely because CI is green.
- Defect #6 open ONLY for the clean-shutdown test. Defect #1 display
  artifact resolved on this build (mechanism UNKNOWN; force60/wqhd queue
  MOOT). Defect #7 audio stub work queued (helpers husky-verify/
  audio-20261112/). Unlisted hardware remains UNTESTED.
- Next discriminating actions: (1) clean-shutdown test on run-98 build
  (user decision, one reboot); (2) isolate the beneficial patch-stack
  delta (bisect halium-husky lineage vs test-r8-lazylink lineage) —
  SCHEDULE AS ITS OWN EXPERIMENT, do not bundle; (3) then defect #7.
