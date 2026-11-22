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
2026-11-22

- Canonical device docs branch: `test-audio-restore`; device integration
  branch `main`: `24d9591`; manifest `main`: `dd6cdda`; patches `main`:
  `22c33ed` (all CI-green). PHONE: known-good matched debug boot set
  (kver `g799ecb77416a`, slot `_b`), healthy, uptime continuous.
- SUSPEND TRACK CLOSED (P1-P4, all TESTED 2026-11-22, evidence
  `husky-verify/p{1..4}-suspend-20261122/`): manual suspend/resume works
  when Wi-Fi is quiesced BEFORE the request (`nmcli networking off`, ~5 s
  settle). Defect #12 REPRODUCED on demand: WoWLAN armed + genuine deep
  suspend (>= ~30 s; clean at 2.2 s, traps at 33 s) -> dongle trap at
  resume, hang reason `pciedev_host_wake_asserted_for_too_long+0x53`
  (byte-identical to 2026-11-21). Recovery TESTED: `nmcli networking
  off` + `on` (driver stop/start reset, NO module unload) restores Wi-Fi
  fully. PM_AUTOSLEEP blocker root cause: teardown-DURING-suspend race
  (stuck dhd `wl` wakelock), NOT a resume defect. WoWLAN-disabled +
  interface up = policy -16 (EBUSY), not a wedge. Do NOT unload
  `bcmdhd4398`. Full write-up: BRINGUP-LOG.md 2026-11-22 P1-P4 section.
- Suspend workarounds: prevention (repowerd pre-suspend Wi-Fi quiesce)
  + cure (post-resume health check -> NM restart). Design spec:
  `husky-verify/repowerd-suspend-hooks-spec.md` (implementation pending
  decision).
- Known-good baseline facts: defect #1 bottom artifact RESOLVED
  (mechanism UNKNOWN); defect #6 CLOSED; clean poweroff PASSED; defect
  #8 OPEN (6/6 healthy cold-offs, no repro).
- Communications state: SIM-dislodgement incident 2026-11-21 23:33Z ->
  baseband reported SIM ABSENT (looked like a radio regression; evidence
  husky-verify/comms-20261122-radio-regression/) -> RESOLVED 2026-11-22
  by user SIM reseat (hot-detect): full stack recovered, SMS reception
  confirmed, mobile data active. The vendor.google.radioext crash-loop
  was collateral of the SIM-less state and self-resolved. VoLTE TESTED:
  ofono IpMultimediaSystem.Register returns Failed locally (no SIT
  traffic); modem reports VoLTE Available=1, so the gap is the
  ofono<->SIT-RIL path — VoLTE parked as research (driver work needed).
  Remaining comms queue: SMS end-to-end with user, MMS send, defect #10
  (airplane/hotspot), #11 (NFC), first-boot history DB check on clean
  flash (defect #9 follow-up).
- CLEAN-INSTALL CHECK: after the next clean flash, verify
  `~/.local/share/history-service/history.sqlite` is non-zero with the
  expected schema before any SMS workaround; if 0-byte, capture
  first-boot journal + history-daemon logs first.
- Next discriminating actions (no phone risk, in order): (1) implement
  or schedule the repowerd suspend hooks per the spec; (2) remaining
  comms queue: SMS first-boot init, MMS send, defect #10/#11, VoLTE
  Register experiment; (3) audio defect #7 (needs the stable-image
  binder work); (4) kernel patch-stack isolation bisect.
