# Resume notes

The port has moved from repository setup and kernel bring-up to coordinated
normal/debug releases. The suspend workaround (quiesce + auto-heal) is
integrated and validated on the production logind path (2026-11-23).

## Current entry point

Read `BRINGUP-LOG.md` first for known-good revisions, verified functionality,
and the ordered test queue. Use `BRINGUP.md` for build and release mechanics.

## Active branches

- `device-google-husky`: cleaned normal/debug integration branch, then `main` after validation
- `lineage-kernel-manifest-husky`: r8 known-good kernel manifest
- `kernel-patches-husky`: r8 known-good patch stack

## Preserved baseline

Tag `known-good-r8-20261110` identifies the three coordinated revisions listed
in `BRINGUP-LOG.md`. Do not move the kernel foundation to r12 until the r12
freeze has been bisected and repeatedly boot-tested.

## Immediate priorities

1. PM_AUTOSLEEP increment (repowerd libsuspend path) — hooks do NOT run on
   autosleep; decide the approach per `husky-verify/repowerd-suspend-hooks-spec.md`
   step 4 after the logind-path validation (now complete).
2. Continue hardware validation in dependency order: hotspot defect #8
   (NM-level AP works, Lomiri UI path broken), GPS defect #13 (provider
   backend needed), defect #10 (airplane/hotspot), #11 (NFC tag), wireless
   charging, USB-C DP, fingerprint.
3. Defect #16: CLOSED-WORKAROUND. Fix integrated in overlay-debug
   (`husky-rndis-rescue`, pinned composer + e0/01/03 codes); validated
   live incl. replug. Remaining: validate on flashed image, then remove
   the ad-hoc `/userdata/husky-usb-diag*` on the phone.
4. Camera/SMS permission re-test from a clean flash (with the history DB
   check) when the next clean flash happens.
