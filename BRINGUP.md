# Husky port bring-up checklist

One-time setup and build order for the Pixel 8 Pro port. Everything below assumes
repos under `https://git.deusch.me/ubports` (adjust if using another org).

## 1. Create repos and push

Create three empty repos on git.deusch.me:

| repo | branch to push |
|------|----------------|
| `device-google-husky` | `main` |
| `lineage-kernel-manifest-husky` | `main` |
| `kernel-patches-husky` | `halium-husky` |

Then push the prepared trees:

```bash
cd device-google-husky
git remote add origin git@git.deusch.me:222/ubports/device-google-husky.git # or https
git push -u origin main

cd ../lineage-kernel-manifest-husky
git remote add origin git@git.deusch.me:222/ubports/lineage-kernel-manifest-husky.git
git push -u origin main

cd ../kernel-patches-husky   # already on branch halium-husky
git remote add origin git@git.deusch.me:222/ubports/kernel-patches-husky.git
git push -u origin halium-husky
```

## 2. CI secrets

- `device-google-husky` and `lineage-kernel-manifest-husky` need `REGISTRY_TOKEN`
  (package registry + container registry login), same as the tegu repos.
- `device-google-husky` additionally needs `RELEASE_TOKEN` (rolling release upload).
- `lineage-kernel-manifest-husky` additionally needs `SSH_KEY` (private key authorized
  for git-over-SSH on git.deusch.me, used by `repo` sync).
- Optional repo vars on the kernel manifest repo: `REPO_SYNC_JOBS`, `BUILD_JOBS`
  (same values as tegu).

## 3. Bootstrap the `generic/husky` package registry

The device CI resolves `system.img.zip` and `libhybris-16-update.tar.xz` from
`generic/husky` (falling back to its `main` version). The kernel CI publishes
`kernel.zip` there automatically. Until then, copy both files over from the tegu
registry (anonymous download, authenticated upload):

```bash
TOKEN=<registry token>
for f in system.img.zip libhybris-16-update.tar.xz; do
  curl -L --fail -o "$f" \
    "https://git.deusch.me/api/packages/ubports/generic/tegu/main/$f"
  curl --fail -u "deusch:${TOKEN}" -X DELETE \
    "https://git.deusch.me/api/packages/ubports/generic/husky/main/$f" || true
  curl --fail -u "deusch:${TOKEN}" -X PUT --upload-file "$f" \
    "https://git.deusch.me/api/packages/ubports/generic/husky/main/$f"
done
```

## 4. Mirror the LineageOS zip

LineageOS only keeps the last ~3 builds; the URL in `.forgejo/workflows/build-final.yml`
will 404 eventually. Download the zip (also stored locally in `~/husky-verify` on the
dev machine) and mirror it like the tegu zip on `anubis.steffend.me`, then update
`LINEAGE_ZIP_URL`:

```
lineage-23.2-20261009-nightly-husky-signed.zip
sha256: 7b3cd1db0b76d043f4270a23c89e382894c955d77e2cc23b6f10986f7d2167a2
```

## 5. Build order

1. Push `kernel-patches-husky` (halium-husky).
2. Push `lineage-kernel-manifest-husky` -> CI builds the zuma/shusky kernel and
   publishes `kernel.zip` to `generic/husky`. First build takes a long time
   (repo sync + full kleaf build); watch for patch-apply failures
   (`git am --3way` output in the build log).
3. Push `device-google-husky` -> CI builds `images.zip` (boot/init_boot/vendor_boot/
   vendor_kernel_boot/dtbo/super) and publishes a rolling `latest-main` release.

## 6. Flashing and bring-up

Prerequisites: bootloader unlocked, stock **Android 16** flashed on both slots first
(vendor blobs + firmware come from stock). Then download `boot-images.zip` and all
`super.img.part-*` from the rolling release and, from bootloader:

```bash
unzip boot-images.zip
cat super.img.part-* > super.img
fastboot flash boot boot.img
fastboot flash dtbo dtbo.img
fastboot flash init_boot init_boot.img
fastboot flash vendor_boot vendor_boot.img
fastboot flash vendor_kernel_boot vendor_kernel_boot.img
fastboot flash super super.img
fastboot erase userdata
fastboot reboot
```

Bring-up order of attack (see README status matrix; tegu quirks to re-validate):

1. Boot to UI at all -> check `last_kmsg`, LXC container logs if it stalls.
2. Touch (GTI offload sysfs paths in `device-hacks`).
3. Display/GL (Mali + hwcomposer; check for the GPU PID-namespace oops - patched).
4. Audio (AIDL pulse modules; tegu issues #3/#8 area).
5. WiFi (`aware_nmi` NM rule), Bluetooth (`bcmbtlinux` wait), cellular (ofono binder).
6. Sensors/vibrator (hfd/sensorfwd AIDL waits), camera, USB-C DP (`usbdp_gbinder`,
   `exynos_drm.dp_rate=2` already in cmdline, `fastboot oem uart disable` for DP).
