# Husky port — session handover (2026-11-10/11)

This document is the authoritative "where are we and how do I touch the phone"
brief. It complements `BRINGUP-LOG.md` (defect list + fixes) and the README
(status matrix). Update all three when state changes.

## 1. Status snapshot

- **Working:** boot to Lomiri; touch; Android LXC container + composer3;
  mobile data; Wi-Fi (validated 2026-11-10: phone joins LAN, SSH over Wi-Fi
  works); NTP/clock; AppArmor; camera trust-store (executable Mir client
  platform, now persistent in image via `fixup-overlay-husky`).
- **Known-good coordinated baseline** (tagged `known-good-r8-20261110` in all
  three repos):
  | Component | Revision |
  |---|---|
  | `device-google-husky` | `a9d91875…` pre-cleanup; active branch is `cleanup-r8-baseline` |
  | `lineage-kernel-manifest-husky` | `c71fde597bcf06374d26972c70f19c5e7f719d63` |
  | `kernel-patches-husky` | `6d9a42798c9577508ee7dd227bb8976d05cac48e` |
- **Active branches:** `cleanup-r8-baseline` in all three repos (kernel
  manifest branch adds one CI-only commit on top of the tag).
- **Defects:** see `BRINGUP-LOG.md` "Current defects". The display bottom-band
  artifact is defect #1 and the active investigation (section 5 below).

## 2. Build / CI / release system (all on GitHub, `L55-CMD`)

- `device-google-husky` push → `.github/workflows/build-final.yml`:
  preflight (bash -n, shellcheck, YAML parse, `scripts/validate-overlay.sh`)
  → matrix `[normal, debug]` → rolling releases `latest-cleanup-r8-baseline-<variant>`
  with `super.img` split parts, `boot-images.zip`, `android-rootfs.img`,
  `MANIFEST.txt`, `SHA256SUMS`.
- `debug` variant = `overlay/` + `overlay-debug/` merged on top in
  `scripts/prepare-device-tarball.sh`. `normal` = `overlay/` only.
- Kernel: push to `lineage-kernel-manifest-husky` branch → `build-kernel.yml`
  builds kernel.zip → publishes rolling release named **the branch name**
  (`releases/download/cleanup-r8-baseline/kernel.zip`). Device CI resolves that
  release by branch tag and verifies the asset digest; if the kernel CI
  re-uploads kernel.zip mid-build, the device build re-resolves and tolerates
  it (`prepare-device-tarball.sh`).
- Everything versioned is pinned in `dependencies.lock` (build-tools
  `262bf2c9…`, halium system.img.zip, libhybris, initrd, recovery, lineage zip
  — all sha256-enforced).
- Do **not** push the build-tools pin, workflow, or lsc-wrapper without a CI
  run: Windows checkouts lose +x bits and symlink-ness; CI has normalization
  steps, preflight has mode checks. New scripts must be `git update-index
  --chmod=+x` immediately after creating.
- Docs-only commits: append `[ci skip]` to the subject.

## 3. Device access playbook (hard-won, read before touching the phone)

Phone: Pixel 8 Pro, serial `38111FDJG001WM`, normally slot **b**.
Host tools: `~/platform-tools/{adb,fastboot}.exe` (Git Bash on Windows).

- **Fastboot:** Power+Vol Down at boot. Verify `fastboot devices` shows the
  serial before every flash.
- **Flash UT:** unzip release; `fastboot set_active b`; flash `boot`,
  `init_boot`, `vendor_boot`, `vendor_kernel_boot`, `dtbo` from
  `boot-images.zip`; `fastboot flash super super.img` (reassembled from parts,
  verify `SHA256SUMS` first); `fastboot reboot`. Full sequence lives in
  `~/bootdebug/reflash-super.sh`.
- **First shell after a fresh debug flash** (documented in README):
  rescue sshd on `10.15.19.82:8022` accepts **publickey only** (usb-moded
  rescue mode spawns it; our own `usb-moded-ssh.service` fights for the same
  port and loses). Install the bring-up key from the Terminal app on the
  phone: run `sudo sh ~/Downloads/key.sh` after downloading
  `docs/phone-first-shell/key.sh` from raw.githubusercontent (browser copy of
  long commands is unreliable; PC-hosted HTTP doesn't reach the phone through
  Windows firewall).
- **Bring-up key:** private `~/bootdebug/husky-rndis-key` (pubkey in
  `docs/phone-first-shell/key.sh`). `authorized_keys` must be
  `chown 32011:32011` (phablet is UID 32011, not 1000). It lives in
  `/userdata` → survives reflashes.
- **SSH channels, in reliability order:** RNDIS `10.15.19.82:22` (key),
  RNDIS `:8022` (key), Wi-Fi port 22 (key; **IP changes on DHCP renew — rescan
  the subnet**; was `.189`, then `.246`). RNDIS link drops occasionally:
  unplug/replug the USB cable fixes it.
- **Root:** `printf '\n' | sudo -S <cmd>` — phablet has an empty password and
  sudo works with it. Do **not** pipe file content through the same stdin as
  `sudo -S` (use SFTP to `/tmp` then `sudo cp/install`).
- **/ is read-only.** Runtime-writable spots are bind mounts from
  `/userdata` (`/etc/writable`, `/etc/ssh`, selected `/etc` files, and
  **`/usr/share/ubuntu-touch-session/lsc-wrapper` ← `/userdata/lsc-wrapper-husky`**).
- **lsc-wrapper gotcha:** something in the lightdm/lxc-android-config restart
  chain re-copies the image's lsc-wrapper over `/userdata/lsc-wrapper-husky`
  at restart, so editing the wrapper never sticks. What **does** stick:
  bind-mount a file over `/etc/default/lsc-wrapper.d/50-default.conf` (the
  wrapper sources that dir *after* its built-in `LSC_FLAGS`, last wins).
  Harness: `~/bootdebug/flag-test.py <label> <quirk:on|off> <overlays:on|off>`
  does exactly this + restarts lightdm.
- Restarting lightdm drops networking for ~30–60s (both RNDIS and Wi-Fi);
  wait and retry all channels.
- **Recovery** (pstore, last_kmsg): flash LOS stack (`~/husky-verify`) →
  recovery → Advanced → Enable ADB → mount userdata → pull logs. See
  `BRINGUP.md`.

## 4. Token / credential hygiene (ACTION REQUIRED)

The GitHub PAT used for API/git access sits in `~/bootdebug/watch-ci.sh` and
**appeared in plain text in tool output**. It must be **revoked on GitHub**
(`Settings → Developer settings → Personal access tokens`) once CI use is
done, and replaced with a fresh token stored outside the repo/docs. No token
may be committed to the repos (roadmap SAFE-029 / Phase 0 gate).

## 5. Display bottom-band artifact — investigation state (defect #1)

Symptom: bottom ~1 inch of the panel shows a persistent fragmented **mirror of
top-of-screen content**; visible from the boot-splash window (before Lomiri),
constant across all UI activity. Evidence bundle:
`~/bootdebug/flag-tests/` (MATRIX.md, per-test DRM state, compositor logs,
props; bring-up host).

Established facts:
- **Independent of Lomiri flags.** Full quirk×overlays matrix (A–D) run:
  artifact identical in all four; quirk ON is what prevents interaction
  tearing → **defaults stay `--enable-num-framebuffers-quirk=true
  --disable-overlays=true`** (baked into `overlay/.../lsc-wrapper`).
- DRM geometry consistent: fb 1008x2256 (pitch 4032, RA24, Samsung compressed
  modifier), plane shows 2244 of 2256 lines at +0+0, DSI-1 mode
  `1008x2244x120 te@120`. dmesg: clean `hk3_enable (fhd)`, no underrun/DSC
  errors.
- Panel driver `panel-gs-hk3.c`: modes 1344x2992@1–120 (DSC WQHD) and
  1008x2244@30–120 (DSC FHD); `1344x2992x60` is DRM_MODE_TYPE_PREFERRED.
- Container props `vendor.display.preferred_mode` /
  `persist.vendor.display.primary.boot_config` are **ignored** by the
  composer3 HAL (set 60Hz and QHD+, both boots came up 1008x2244@120).
- **Never used LineageOS on this device** → no Android-side baseline exists.
  The same kernel DT + panel driver are believed clean under Android, but this
  is unverified.

Working theory: the compressed DSI stream (all HK3 modes use DSC) is short by
roughly the corrupted band, or the DECON/DPP window wraps — the band shows
stale buffer memory rather than fresh pixels. Why UT differs from Android is
unknown; candidates: DSC PPS programming via composer3 in the halium path,
GIDLE/self-refresh entry, TE2 config.

Next steps, in order:
1. **Photograph the artifact** (bottom 2 inches, top menu visible) — garbage
   vs mirrored-content vs stale-frame discriminates the three theories.
2. **Boot slot a** (`fastboot set_active a`) — may still hold a bootable
   Android/Lineage stack from bring-up; gives the missing clean/dirty
   baseline. Flip back to b afterwards.
3. If LOS is clean: diff display-HAL init between container logcat (Android)
   and UT boot (dmesg already clean) — focus DSC PPS, gidle, TE2, op_hz.
   If LOS is dirty: kernel-level; try a DT patch forcing 1344x2992 modes
   only (kernel CI rebuild + reflash boot images only).
4. Only then touch GridUnit/DPR scaling (roadmap DSP-009+).

## 6. Validation queue (after display is settled)

Ordered: suspend/resume (20 cycles) → reboot/shutdown → battery/charging →
Bluetooth → sensors (rotation/ALS/proximity) → camera capture (post-MFC-fix;
MFC nodes stay masked) → USB-C DP (`usbdp_gbinder`, `exynos_drm.dp_rate=2`) →
fingerprint (likely unsupported, document). Update README status matrix +
BRINGUP-LOG per roadmap evidence rules. Call audio defect (Pulse
`voicecall` profile 0 sinks/0 sources, "Audio patch telephony-rx not
implemented") is a separate workstream — Android AIDL audio HAL is running.

## 7. Roadmap progress mapping (see `~/Downloads/Pixel 8 Pro … Roadmap.md`)

Done or materially done: SAFE-013 (tags), CLN-001…005 (flavors+preflight
assertion), CLN-006…012 (debug-only services), CLN-013/014 (normal USB clean),
CLN-020…022 (modes/symlinks/preflight), BLD-002/003 (tools pin), BLD-004,
BLD-013…015 (lockfile+digest), BLD-016/017 (SHA256SUMS), BLD-020…023
(explicit artifacts), BLD-026 (concurrency), BLD-032…034 (preflight subset),
KRN-001 (protected KVM documented), KRN-013 (DWC3 defer), DSP-001, DSP-003/004
(flag matrix), NET-002 partially (Wi-Fi join + SSH; full WPA3/suspend suite
pending).

In progress: display DSP-002/005/007 (artifact), SEC/access hardening
(CLN-015…018: debug rescue SSH is empty-password by design — acceptable only
while debug builds stay private; see README security note).

Not started: everything from Phase 5 (power/audio/sensors/cellular validation
beyond data), Phase 6+, and the R0 gate items SAFE-001…012 (stock factory
package archive, return-to-stock runbook, recovery drill).

Immediate hygiene before sharing images (P0): revoke exposed PAT (§4),
complete SAFE-007…011 (stock package + runbook), CLN-015…017 (key-only SSH in
any image that leaves your bench).

## 8. How to resume each thread

- **Display:** §5 checklist; all tooling on bring-up host (`~/bootdebug/`).
- **New device-repo change:** commit on `cleanup-r8-baseline`, push, watch run
  via `~/bootdebug/watch-ci-safe.sh <run-id>` (run id from the API), download
  from the rolling release, `~/bootdebug/reflash-super.sh` pattern (super-only
  if boot images unchanged).
- **Kernel change:** commit patch in `kernel-patches-husky` (see its README +
  `apply-patches.sh`), push branch (triggers kernel CI, hours), then device CI
  picks the new kernel.zip automatically.
- **Validation runs:** SSH helper pattern in `~/bootdebug/flag-test.py`
  (paramiko, multi-channel connect, `sudo -S` with empty password).
