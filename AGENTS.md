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
2026-11-21T23:58Z

- Canonical device docs branch: `test-audio-restore` (latest pushed commit;
  rollback/CI-precondition record: `9fb3bc1`).
  Canonical device integration branch `main`: `24d9591`; manifest `main`:
  `dd6cdda`; patches `main`: `22c33ed`. Hardening CI `44957022617` and
  main-push CI `44958836687` succeeded; Agent 2 verified both complete
  artifact sets. `BRINGUP.md` now records the same-named-kernel-release CI
  precondition. Hard branch caveat: local-only unpushed docs commit `e352d76`
  is not part of the green merge.
- PHONE STATE: rolled back 2026-11-21T23:52Z to the preserved known-good
  matched debug boot set (`husky-flash/tar-audio-lto/`, boot-images
  fcb8b563; device ca7a9ea / manifest a979a7a / patches 22c33ed).
  Verified kver `g799ecb77416a`, slot `_b`, LightDM active (`NRestarts=0`),
  `/sys/power/autosleep` ENOENT, `# CONFIG_PM_AUTOSLEEP is not set`, pKVM
  chain loaded, NM connected/full. Evidence: husky-verify/rollback-known-
  good-20261121/.
- Known-good baseline facts: defect #1 bottom artifact RESOLVED (mechanism
  UNKNOWN); defect #6 CLOSED (YouTube with audio, no panic); clean
  poweroff PASSED. Defect #8 remains OPEN after 6/6 healthy controlled
  cold-offs (evidence: husky-verify/defect8-capture/evidence-20261121/).
- Communications state: SMS works only after defect #9's zero-byte history
  DB recovery; first-boot initialization remains OPEN. MMS receive/display
  tested, send untested. Airplane/hotspot remain defect #10 partial; NFC is
  defect #11; Bluetooth A2DP/reconnect/suspend survival pass, call audio
  untested; VoLTE research only.
- Defect #12 CLASSIFIED (offline, TESTED from capture): the bcmdhd4398
  dongle trapped at deep-suspend resume (`pciedev_host_wake_asserted_for_
  too_long`), after which the driver wedged and `WLC_GET_ASSOCLIST` /
  `assoc_info` returned -19; no recovery ran. NM/supplicant/rfkill were
  stale-state victims, not causes. See defect12-evidence-20261121/
  CLASSIFICATION-20261121.md. NEVER unload bcmdhd4398.
- PM_AUTOSLEEP TEST FAILED/PARTIAL and now classified separately from #12:
  CI `44960937874` green; Libsuspend path selected, but logind/NM/
  wpa_supplicant Wi-Fi teardown raced PM suspend and left a stuck dhd `wl`
  wakelock (`wakelock c-1 wl-1`; `0x44` busy state). `autosleep=mem`
  retried against the locked driver; no system suspend was entered.
  Evidence: husky-verify/pm-autosleep-20261121/.
- CLEAN-INSTALL CHECK: after the next clean flash, verify
  `~/.local/share/history-service/history.sqlite` is non-zero and has the
  expected schema before any SMS workaround; if 0-byte, capture first-boot
  journal + history-daemon logs first.
- Next discriminating action, pending explicit approval: P1 on the
  known-good image — autosleep off, `nmcli networking off`, wait ~5s, then
  one manual suspend / `rtcwake -m mem -s 20`; capture dmesg/journal. This
  tests whether suspend enters cleanly when live Wi-Fi teardown is removed.
  Do not unload bcmdhd4398. Only after the suspend-path result, schedule
  #10, #11, remaining communications tests, VoLTE research, #7, and
  patch-stack isolation separately.
