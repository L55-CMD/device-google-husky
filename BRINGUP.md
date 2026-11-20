# Husky build and bring-up guide

This guide describes the current GitHub-based normal/debug build pipeline. It replaces the obsolete Forgejo and package-registry bootstrap instructions.

## Coordinated baseline

| Repository | Baseline revision |
|---|---|
| `device-google-husky` | tag `known-good-r8-20261120` (= `test-audio-restore`; promotion to `main` pending the manifest `main` kernel.zip, then fast-forward) |
| `lineage-kernel-manifest-husky` | `a979a7abfe8800b845d653c6abdd9fadc96a0257` (= tag `known-good-r8-20261120` = branch `main`) |
| `kernel-patches-husky` | `22c33ed85ad235fdc2bc09d4ef1a89379f5a207f` (= tag `known-good-r8-20261120` = branches `halium-husky`/`test-audio-restore`/`main`) |

This baseline is validated ON-DEVICE (2026-11-20): boots, pKVM/IOMMU
chain bound, YouTube with audio (defect #6 closed), clean shutdown.
Details: BRINGUP-LOG.md 2026-11-20.

The historical working device revision `a9d9187556e684352f26f21370c5cf90b259f14d` is preserved by the `known-good-r8-20261110` tag; run-98 is preserved by local tags `known-good-ltonone-run98` (not pushed).

## Normal and debug images

Every device build produces two separately labelled rolling releases:

- `latest-<branch>-normal`
- `latest-<branch>-debug`

The normal image contains no automatic rescue SSH, forced developer mode, framebuffer random-write test, vibrator heartbeat, or unconditional video-node mask.

The debug image is for bring-up only. It enables temporary RNDIS rescue networking, tracing, and manual framebuffer/backlight tests. SSH remains key-only; install an authorized key for the `phablet` user before enabling SSH.

## Build inputs

`dependencies.lock` pins the build-tools commit and records SHA-256 checksums for the Halium system image, libhybris update, LineageOS zip, Halium initramfs, and recovery image. The workflow resolves the exact kernel release for the current branch and fails if that release or its checksum metadata is missing.

Do not replace these inputs with floating `lastSuccessfulBuild` URLs or a silently fallback kernel branch.

## Local preflight

```bash
./scripts/validate-overlay.sh
bash -n scripts/*.sh build.sh
```

Run ShellCheck if it is installed:

```bash
shellcheck scripts/*.sh build.sh
```

## CI build

Pushes to any branch run a preflight job and then build both variants. The jobs use separate concurrency groups so a newer build cannot delete the rolling release being produced by another job.

Each published release contains:

- `boot-images.zip`
- split `super.img.part-*`
- `android-rootfs.img`
- `SHA256SUMS`
- `MANIFEST.txt`

The manifest records the device, kernel manifest, and kernel patch revisions, build variant, and all pinned dependency versions/checksums.

## Flashing

Prerequisite: flash the matching Android 16 LineageOS/stock vendor base first and unlock the bootloader.

Download the desired variant’s assets, verify `SHA256SUMS`, and assemble the split super image:

```bash
sha256sum -c SHA256SUMS
cat super.img.part-* > super.img
unzip boot-images.zip -d boot-images
```

Boot to fastboot and flash:

```bash
fastboot flash boot boot-images/boot.img
fastboot flash dtbo boot-images/dtbo.img
fastboot flash init_boot boot-images/init_boot.img
fastboot flash vendor_boot boot-images/vendor_boot.img
fastboot flash vendor_kernel_boot boot-images/vendor_kernel_boot.img
fastboot flash super super.img
fastboot erase userdata
fastboot reboot
```

If the Android container image is not already on userdata from an earlier install, boot the matching recovery and push `android-rootfs.img` to the userdata root before starting UT.

### Partial flashes break booting — always flash the complete matched set

`vendor_kernel_boot` carries the full `/lib/modules/<kver>` tree that the
halium initrd loads at boot; `init_boot` only adds the flat pKVM closure.
Flashing a subset (e.g. only `boot` + `init_boot`) pairs a new kernel with
a stale module tree: on kver mismatch the initrd cannot find
`modules.load` and storage never probes ("Couldn't find data partition",
8.4s panic — 2026-11-18 incident, NEXT-SESSION-NOTES.md 2026-11-19). All
five images (`boot`, `init_boot`, `vendor_kernel_boot`, `vendor_boot`,
`dtbo`) must come from the same CI run. The bring-up host's dd scripts run
`preflight-boot-images.sh` to enforce this structurally before flashing.

## Test discipline

Record the release tag, all three repository revisions, test result, and relevant logs for every hardware test. Use the ordered matrix in `BRINGUP-LOG.md`; do not mark a feature working based only on a related device port.
