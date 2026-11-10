# Husky build and bring-up guide

This guide describes the current GitHub-based normal/debug build pipeline. It replaces the obsolete Forgejo and package-registry bootstrap instructions.

## Coordinated baseline

| Repository | Baseline revision |
|---|---|
| `device-google-husky` | cleaned `main` branch after validation |
| `lineage-kernel-manifest-husky` | `c71fde597bcf06374d26972c70f19c5e7f719d63` |
| `kernel-patches-husky` | `6d9a42798c9577508ee7dd227bb8976d05cac48e` |

The historical working device revision `a9d9187556e684352f26f21370c5cf90b259f14d` is preserved by the `known-good-r8-20261110` tag.

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

## Test discipline

Record the release tag, all three repository revisions, test result, and relevant logs for every hardware test. Use the ordered matrix in `BRINGUP-LOG.md`; do not mark a feature working based only on a related device port.
