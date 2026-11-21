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
2026-11-21T23:42Z

- Canonical device branch: `test-audio-restore`. Phase 3 communications
  documentation was committed separately on `phase3-comms-docs` (@e73001d)
  and fast-forwarded here; `harden-build-release` is reserved for
  build/release hardening only.
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
- Defect #1 bottom-screen artifact: RESOLVED on this baseline (mechanism
  UNKNOWN; force60/wqhd queue MOOT). RUN-98 is superseded but retained as
  fallback; both effective kernels use CONFIG_LTO_CLANG_THIN=y.
- Defect #8 OPEN, intermittent, low-reproduction: the 2026-11-20 cold-off
  Lomiri crash-loop did NOT recur in six valid controlled cold-off rounds
  on 2026-11-21 (all `healthy-stable`, LightDM `NRestarts=0`). Evidence:
  husky-verify/defect8-capture/evidence-20261121/ (verified SHA256SUMS).
  Keep the capture unit enabled; do not declare the startup race fixed.
- Phase 3 communications state (BRINGUP-LOG 2026-11-20, evidence
  husky-verify/comms-20261120/): SMS works on the CURRENT INSTALLATION
  only after the 0-byte history.sqlite recovery; defect #9's first-boot
  DB-initialization root cause remains OPEN. MMS receive/display tested;
  MMS send untested. Airplane mode and hotspot are PARTIAL: low-level/NM
  mechanisms work, Lomiri indicator actions are defect #10. Bluetooth
  media/A2DP/reconnect/suspend survival pass; call audio untested. NFC
  is defect #11 (AIDL-capable nfcd plugin needed). VoLTE is research only.
- Defect #12 REPRODUCED 2026-11-21 on the known-good baseline: after a
  controlled deep suspend/resume followed by a failed suspend attempt in
  `dhdpcie_pm_suspend`, wlan0/wlan1 remained UP/associated and NM claimed
  connected/full, but both phone-side and host-side traffic failed. Driver
  logs repeat `WLC_GET_ASSOCLIST error -19` / `failed to get assoc_info:
  err=-19`. Full failed-state journal + dmesg were captured before reboot:
  husky-verify/defect12-evidence-20261121/ (verified SHA256SUMS). Phone was
  intentionally left in the failed state for inspection; PM_AUTOSLEEP
  flashing/reboot will destroy it. NEVER unload bcmdhd4398.
- CLEAN-INSTALL CHECK: after the next clean flash, verify
  `~/.local/share/history-service/history.sqlite` is non-zero and has the
  expected schema before applying any SMS workaround; if it is 0-byte,
  capture first-boot journal + lomiri-history-daemon logs first.
- 2026-11-18 bootloop root cause (SOLVED, separate): incomplete flash —
  stale vendor_kernel_boot_b. Guard: husky-verify/preflight-boot-images.sh
  (wired into flash scripts; BRINGUP.md warns). Flash over root SSH via
  /userdata (phablet sudo now needs a password; /tmp is PrivateTmp).
- RAMOOPS FACT: cold poweroff wipes console-ramoops; use the persistent
  journal (journalctl -b -N) for shutdown verdicts.
- Phone: integrated baseline (on-device known-good) running, healthy.
  Defect #7 audio stub work queued (husky-verify/audio-20261112/).
  Unlisted hardware remains UNTESTED.
- Hardening promotion COMPLETE: device CI run 44957022617 succeeded;
  Agent 2 verified both complete normal/debug five-image sets, coordinated
  revisions, kernel provenance, and 209-module kver consistency. Canonical
  main was deliberately fast-forwarded to device `24d9591`, manifest
  `dd6cdda`, with patches main already at `22c33ed`. The main-push CI run
  44958836687 was in progress at this update; the merged tree is exactly
  the green hardening commit.
- PM_AUTOSLEEP experiment STOPPED after evidence capture: CI run
  44960937874 green; matched debug boot set flashed (kver gc5e9bc394477).
  `/sys/power/autosleep` exists and repowerd successfully selected the
  Libsuspend path (no fallback log; it changed autosleep to `mem`).
  However, both manual and automatic suspend failed to enter suspend:
  bcmdhd4398 reported internal wakelock/busy state (`dhdpcie_bus_suspend:
  Suspend failed because of wakelock`, `dhd_bus_busy_state: 0x44`).
  Autosleep was set back to `off`; evidence:
  husky-verify/pm-autosleep-20261121/ (verified SHA256SUMS). Do not run
  incoming-call wake until suspend-entry is reliable. Phone remains on the
  PM test image pending a deliberate rollback/investigation decision.
- Next discriminating actions, in priority order: (1) decide whether to
  roll back to the known-good baseline or isolate the bcmdhd4398 suspend
  wakelock as its own experiment; (2) only then schedule defect #10,
  defect #11, remaining communications tests, VoLTE research, defect #7,
  and patch-stack isolation as separately scoped work.
