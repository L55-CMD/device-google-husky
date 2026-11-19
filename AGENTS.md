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
2026-11-19T10:05Z

- Commits: device-google-husky @ test-audio-restore-ltonone (b808d33
  plus UNCOMMITTED doc/script cleanup); kernel-patches-husky 24ffa8d
  (halium.config CONFIG_LTO_NONE=y); lineage-kernel-manifest-husky
  2f6f5fd.
- Images tested: latest-test-audio-restore-ltonone-debug, CI run 98
  (boot.img sha 6764e3c5, init_boot.img sha 3476aad7), flashed to
  slot b 2026-11-18 ~21:56Z.
- Result: BOOTLOOP, died at 8.4s — halium initrd "PANIC: Couldn't find
  data partition". The CI-built boot ramdisk held 25 .ko (pkvm-segment
  closure size) instead of 209, with an EMPTY modules.load; only the
  pkvm closure loaded, so UFS/storage never probed.
- Evidence: husky-verify/tmp/console-ramoops-ltonone-ci.log; images in
  husky-flash/ltonone-ci/.
- Exonerated: (1) the LTO_NONE kernel.zip itself — its initramfs.img
  carries the full 209-module set with byte-identical modules.load to
  the working test-audio kernel.zip; (2) "LTO zip breaks the device
  build" — the run 94-97 CI failures were the rolling recovery-image
  URL hash drift, fixed by pinning build 603 (b808d33).
- NO VERDICT: CONFIG_LTO_CLANG_THIN as the EL2 S2MPU notifier breaker.
  Both LTO_NONE attempts died at 8.4s, BEFORE the 13.9s HSI0 SysMMU
  panic mark — hypothesis open, neither confirmed nor cleared.
- Phone: r8-baseline-debug on slot b, UP, SSH OK (root key, RNDIS
  10.15.19.82). Failed boot's pstore archived locally (systemd-pstore
  clears /sys/fs/pstore each boot — read /var/lib/systemd/pstore).
- Next discriminating action: unpack run 98's boot/init_boot ramdisk
  properly (husky-verify/tools/mkbootimg.py + tmp/repack*.py), confirm
  25-vs-209 and where modules.load went; diff run-98 build log vs
  working run 93 module assembly; fix the device build's module pickup;
  re-run CI, flash boot_b+init_boot_b, and finally get the LTO_NONE
  verdict at the 13.9s mark.
- Also open: cherry-pick b808d33 onto test-audio-restore (its CI is
  broken by the same rolling-URL drift). Queues: defect #7 audio stub
  (phone scripts ready in husky-verify/audio-20261112/); display
  force60/wqhd kernel tests.
