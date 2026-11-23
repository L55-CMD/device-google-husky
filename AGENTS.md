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
2026-11-23

- PHONE: `test-audio-restore` debug @ `ee64390` (CI run 45061652269,
  kver `g799ecb77416a`, slot `_b`), flashed+validated today; healthy —
  Wi-Fi ×2, Vodafone gsm, container/NM/repowerd active. Evidence of the
  day: `husky-verify/quiesce-validation-20261123/`.
- SUSPEND TRACK: **defect #12 workaround VALIDATED** — quiesce hook +
  auto-heal (shipped `9f8e84c`+`ee64390`) ran clean on the production
  logind path: 11/11 suspends (two full validation runs), deep entry
  every cycle, state restored every cycle, zero genuine signatures,
  0 dhd suspend failures (stats 17 ok / 6 env-abort fails, all
  alarmtimer-class, retried). Max hook-path window 28.9 s ×2; >33 s on
  the hook path itself not yet landed (waker-dependent: cp2ap modem +
  alarmtimer aborts — the parked waker-hunt family, NOT dhd). Combined
  with 2026-11-22 manual quiesce+deep >33 s clean runs, the integrated
  workaround covers the characterized defect-#12 regime. Defect #12
  CLOSED-WORKAROUND; real fix remains firmware/driver-side.
- Defect #16: **CLOSED-WORKAROUND** (flash-pending). Root cause refined
  2026-11-23 (late): usbdp_gbinder EXONERATED (strace: pure IUsbCallback
  relay, no configfs access); usb-moded's replug recomposition is the
  prime suspect (INFERRED). Fix integrated: `husky-rndis-rescue`
  (overlay-debug) pins a custom RNDIS composer (Conflicts=usb-moded),
  writes Android-tethering class codes e0/01/03 (inbox Windows rndismp
  match, no os_desc dependency; 02/02/ff fell back to usbser, 02/06/00
  is the original broken ECM state). Validated live: replug survives,
  SSH/adapter uninterrupted. Pending: same validation on the flashed
  integrated image; post-flash remove ad-hoc /userdata/husky-usb-diag*.
- Harness fixes (2026-11-23, `husky-verify/quiesce-validation.sh` only):
  sorted Wi-Fi-scoped state comparator (nmcli order + mid-run gsm
  registration false-failed); trap regex now `Dongle trap|
  host_wake_asserted|error -19` only (`wakelock c-1 wl-1` and
  `Suspend failed because of wakelock` are benign-while-awake patterns);
  dhd entry race authority = fail-stat `last_failed_dev=0001:01:00.0`;
  environmental alarmtimer aborts retried (stage0 ×3).
- Known-good baseline facts: defect #1 bottom artifact RESOLVED
  (mechanism UNKNOWN); defect #6 CLOSED; clean poweroff PASSED; defect
  #8 OPEN (6/6 healthy cold-offs, no repro); defect #4 closed
  (2026-11-22, mechanism unknown).
- Comms state (2026-11-22 user tests): SMS/MMS send+receive WORKS, call
  audio bidirectional WORKS (defect #2 closure candidate), mobile data
  active, VoLTE parked (ofono<->SIT-RIL gap). Fails: hotspot from Lomiri
  UI (#8; NM-level AP works), GPS (#13, root-caused: lomiri-location-
  service SEGVs — no UAL lib, no provider config). Auto-brightness:
  no backend on image (sensorfw ALS + consumer needed). Untested:
  wireless charging, NFC tag, USB-C DP, fingerprint.
- CLEAN-INSTALL CHECK still pending on next clean flash: verify
  `~/.local/share/history-service/history.sqlite` non-zero with expected
  schema before any SMS workaround.
- Next discriminating actions (in order): (1) PM_AUTOSLEEP increment
  (repowerd libsuspend path — hooks do NOT run on autosleep; decide per
  spec step 4); (2) opportunistic hook-path >33 s deep window (waker-
  dependent); (3) SMS end-to-end + MMS with user, defect #10/#11, audio
  defect #7; (4) defect #16 flashed-image validation + ad-hoc diag
  cleanup; (5) kernel patch-stack isolation bisect; (6) r12 freeze
  bisect before any kernel-foundation move.
