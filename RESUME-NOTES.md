# Husky port - resume notes (2026-11-03)

State: all three repos prepared LOCALLY, committed, NOT pushed anywhere.
deusch.me migration: user has NO login on git.deusch.me (Steffen's instance) ->
pivot to GitHub. CI adapted: Forgejo workflows replaced with GitHub Actions
(.github/workflows/), --volumes-from replaced with bind mounts, package registry
replaced by release assets of a <owner>/husky-packages repo (per-branch release
tags + "main" fallback, which matches assemble-final-image.sh's resolver).

## Pushed to GitHub (2026-11-03) - repos live
- https://github.com/Luk3-ss/device-google-husky (main)
- https://github.com/Luk3-ss/lineage-kernel-manifest-husky (main)
- https://github.com/Luk3-ss/kernel-patches-husky (halium-husky)
- https://github.com/Luk3-ss/husky-packages: release tag "main" with
  system.img.zip + libhybris-16-update.tar.xz (mirrored from deusch public
  registry) + lineage-23.2-20261009 zip (sha256-verified local copy kept at
  ~/husky-verify). kernel.zip is published by kernel CI into the kernel repo's
  own per-branch releases (GITHUB_TOKEN can't write cross-repo).

## BLOCKER: GitHub account locked (billing)
First kernel CI run failed instantly: "your account is locked due to a
billing issue". Actions will not run until Luk3-ss fixes it at
https://github.com/settings/billing (usually an expired card on file or an
old unpaid invoice; updating/removing the payment method unlocks it).
After it is fixed: re-run the failed workflow (Actions -> build-kernel ->
Re-run jobs) or push any commit; then the device repo build-final will
produce images.zip on its rolling latest-main release.
Token used for setup should be revoked by the user once everything runs.

## Local repos (ready to push)
- ~/device-google-husky           branch main          (4 commits: tegu import -> husky adapt -> BRINGUP.md -> ExecStart fix)
- ~/lineage-kernel-manifest-husky branch main          (1 commit on top of tegu history)
- ~/kernel-patches-husky          branch halium-husky  (1 commit on top of tegu history)

## To resume
1. Get a Forgejo token (repo + package scope) from the user -> create the 3 repos
   under ubports/ via API, push, and bootstrap the generic/husky registry
   (system.img.zip + libhybris-16-update.tar.xz copied from generic/tegu - both
   anonymously downloadable; one-liners in ~/device-google-husky/BRINGUP.md).
2. Mirror the LineageOS zip: already downloaded at
   ~/husky-verify/lineage-23.2-20261009-nightly-husky-signed.zip
   (sha256 7b3cd1db0b76d043f4270a23c89e382894c955d77e2cc23b6f10986f7d2167a2 - verified)
   -> upload to anubis.steffend.me and update LINEAGE_ZIP_URL in
   device-google-husky/.forgejo/workflows/build-final.yml.
3. CI secrets needed: REGISTRY_TOKEN + RELEASE_TOKEN (device repo),
   REGISTRY_TOKEN + SSH_KEY (kernel manifest repo).
4. Push order: kernel-patches-husky -> lineage-kernel-manifest-husky (long kernel
   build; watch `git am --3way` failures) -> device-google-husky -> flash & bring-up.

## Key verified facts
- LOS 23.2 (A16) supports husky; zuma shares tegu's UFS (13200000.ufs), USB DWC3
  (11210000.dwc3), UART earlycon (exynos4210,0x10870000), super size 8531214336.
- Kernel: build_shusky.sh -> out/shusky/dist (zuma_shusky_dist target).
- Patches regenerated for google/zuma/constants.bzl + google/shusky; GKI/apparmor/
  kleaf/Mali patches verified against lineage-23.2 sources.
- open questions left for device bring-up: Lomiri GridUnit/DPR values (26/2.75 guess),
  tegu quirks re-validation (GTI sysfs, aware_nmi, cs40l26, AIDL audio, DP).
