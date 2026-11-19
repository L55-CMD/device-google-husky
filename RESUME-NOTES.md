# Resume notes

The port has moved from repository setup and kernel bring-up to coordinated normal/debug releases.

## Current entry point

Read `BRINGUP-LOG.md` first for known-good revisions, verified functionality, and the ordered test queue. Use `BRINGUP.md` for build and release mechanics.

## Active branches

- `device-google-husky`: cleaned normal/debug integration branch, then `main` after validation
- `lineage-kernel-manifest-husky`: r8 known-good kernel manifest
- `kernel-patches-husky`: r8 known-good patch stack

## Preserved baseline

Tag `known-good-r8-20261110` identifies the three coordinated revisions listed in `BRINGUP-LOG.md`. Do not move the kernel foundation to r12 until the r12 freeze has been bisected and repeatedly boot-tested.

## Immediate priorities

1. Build and flash normal/debug variants from the cleaned device branch.
2. Retest camera/SMS permissions now that AppArmor and Mir trust-store startup are fixed.
3. Display: Lomiri quirk matrix already run (all four combinations —
   artifact present in every one); next is the force60/wqhd kernel-branch
   tests, then DSC/mode bisect. Do not re-run the quirk matrix.
4. Continue hardware validation in dependency order: UI/touch/backlight, power cycles, Wi-Fi/Bluetooth, audio, sensors, cellular, camera.

## Post-stability research (not critical path)

- GPU (Mali G715) as the on-device ML inference tier via Mesa Vulkan/OpenCL.
- Bounded experiment: stock libedgetpu + firmware vs. our kernel edgetpu
  driver in-container, to get a definitive TPU accept/reject verdict.
  Details in husky-verify/NEXT-SESSION-NOTES.md "Post-stability research queue".
