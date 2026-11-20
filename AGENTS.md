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
2026-11-20T19:15Z

- ON-DEVICE KNOWN-GOOD BASELINE (TESTED 2026-11-20): integrated family
  kernel-patches-husky 22c33ed / manifest a979a7a / device test-audio-
  restore (build code ca7a9ea; docs through 660bfb3+), coordinated tag
  `known-good-r8-20261120` on all three repos. CI run 44612802506 debug
  set (boot-images fcb8b563, kver g799ecb77416a) flashed boot-images-
  only to slot b; pkvm chain verified (pkvm_s2mpu_v9 @2.4s,
  samsung_iommu_v9 21 refs, 25 sysmmus incl HSI0, mfc-core on MFC-0,
  zero fault/panic lines). DEFECT #6 CLOSED: YouTube with audio passed,
  no panic/reboot. Clean-shutdown test PASSED (normal unmount, no
  iommu_release_device panic). Evidence: husky-verify/NEXT-SESSION-NOTES.md
  2026-11-20 section; BRINGUP-LOG 2026-11-20.
- Promotion status: patches repo branch `main` created @22c33ed; manifest
  repo branch `main` FF'd to a979a7a (its kernel CI is republishing
  kernel.zip as release `main`). PENDING: FF device `main` to this
  branch's head once the manifest `main` kernel.zip exists (FF-verified,
  old main 107090e is an ancestor). Details: BRINGUP-LOG 2026-11-20.
- RUN-98 (superseded by the integrated baseline, RETAINED as fallback):
  kver gc9a0580a0791, same on-device verdicts (boots past 13.9s, pkvm
  chain bound, YouTube working, defect #1 artifact gone). Artifacts:
  husky-flash/ltonone-ci/, evidence husky-verify/tmp/ltonone-full-
  20261119-105157/. Effective config CONFIG_LTO_CLANG_THIN=y (CORRECTION
  above applies to both).
- Defect #1 bottom-screen artifact: RESOLVED on this baseline (mechanism
  UNKNOWN; force60/wqhd queue MOOT). Defect #8 OPEN (intermittent):
  first boot after cold poweroff may crash-loop Lomiri (~65s lightdm
  restart cycle, black screen, no host RNDIS); identical later boot
  healthy → startup race. GOTCHA: with Lomiri down, a short power press
  powers the phone OFF via logind. Capture procedure: husky-verify/
  defect8-capture/ (prepared, NOT started).
- 2026-11-18 bootloop root cause (SOLVED, separate): incomplete flash —
  stale vendor_kernel_boot_b. Guard: husky-verify/preflight-boot-images.sh
  (wired into flash scripts; BRINGUP.md warns). Flash over root SSH via
  /userdata (phablet sudo now needs a password; /tmp is PrivateTmp).
- RAMOOPS FACT: cold poweroff wipes console-ramoops; use the persistent
  journal (journalctl -b -N) for shutdown verdicts.
- Phone: integrated baseline (on-device known-good) running, healthy.
  Defect #7 audio stub work queued (husky-verify/audio-20261112/).
  Unlisted hardware remains UNTESTED.
- Next discriminating actions: (1) finish device-main promotion once the
  manifest `main` kernel.zip exists (mechanical, FF); (2) defect #8
  capture series (awaits user go); (3) isolate the beneficial patch-stack
  delta (bisect halium-husky vs test-r8-lazylink lineage) — OWN
  EXPERIMENT, do not bundle; (4) then defect #7.
