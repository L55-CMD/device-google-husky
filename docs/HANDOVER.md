# Husky port — session handover (2026-11-10/11)

> **2026-11-13 addendum #3 (CI rescue + flash + flicker + SSH recovery — READ FIRST):**
> Full session recap. All CI fixes are pushed on `test-audio-restore`
> (`c42b131`, `2028e9d`, `bcbed87`); CI is GREEN; release
> `latest-test-audio-restore-debug` is built and downloaded.
> The phone currently runs a **mixed state: baseline super (good
> screen) + Nov-12 kernel boot images without the pKVM segment**.
> SSH access works with the **NEW key** (see access changes in §3).
>
> **Flicker matrix (defect: fullscreen flicker on test-audio image):**
> new super = flicker with EITHER boot set; baseline super = good with
> EITHER boot set ⇒ **the test-audio-restore super causes it**, not the
> pKVM segment, not the panel. Kernel source/manifest are identical
> between the builds (kernel-patches `test-audio-restore` is *behind*
> baseline, manifest *identical* — verified via GitHub compare), so the
> delta is content or rebuild variance inside the super (audio overlay
> ships in the 3.5 GB rootfs partition; `android-rootfs.img` also
> differs by hash). NOT yet narrowed to a file. Host-side super
> analysis tooling exists (see §8 tools).
>
> **Audio live test — mechanism solved:** the restored AudioPolicyService
> constructor blocks forever in `AudioSystem::getService` when
> audioserver is started as **root**, because `AudioSystem.cpp`
> (`android16-release`) only takes the non-blocking local-service path
> when `getuid() == AID_AUDIOSERVER`. Started via the injected
> `audioserver.rc` (user audioserver) at boot this cannot happen — but
> any MANUAL/live-injection start must use the `audioserver` user.
> Also: the minimedia init service is named **`minimedia`** (binary is
> `minimediaservice`; `setprop ctl.stop minimediaservice` is a no-op).
> Prior live run proved the real APM loads the full telephony policy
> (in-call-playback → AUDIO_DEVICE_OUT_TELEPHONY_TX patches created).
>
> **pKVM script fixes (all validated against the real Nov-12 kernel.zip
> with a local debugfs shim):** (1) +x bit lost in Windows checkout
> (handover §2 gotcha struck again); (2) `debugfs ls -p` output is
> `/ino/mode/uid/gid/name/` — the old awk parse never matched; (3) the
> kernel's own config (verified on-device `/proc/config.gz`):
> `CONFIG_MODPROBE_PATH="/system/bin/modprobe"` — **the halium initrd
> only has /sbin/modprobe → the segment must ship the
> `/system/bin/modprobe → /bin/kmod` symlink** — and
> `CONFIG_PKVM_MODULE_PATH="/lib/modules/"` ⇒ upstream kmod uses the
> `-d` dir AS-IS ⇒ **flat** `/lib/modules/modules.dep` + `*.ko` (no
> `<kver>` subdir). Script handles both flat and `<kver>/` source
> layouts. Closure: 25 modules, ELF-valid.
>
> **Access playbook changes (§3 outdated — read this):**
> - The OLD bring-up private key was DESTROYED with `bootdebug/`.
>   NEW keypair: host `husky-verify/husky-rndis-key(.pub)` (ed25519,
>   comment `husky-bringup-20261113`); pubkey baked into repo
>   `docs/phone-first-shell/key.sh` (bcbed87). **Hazard:** stale
>   `~/Downloads/key.sh` copies on the phone contain the DEAD old key —
>   always fetch fresh (cache-buster query) or install from recovery.
> - **Recovery-adb key install (no phone typing needed):** boot the
>   pinned UBports recovery (`husky-flash/ramdisk-recovery.img`,
>   sha256 in dependencies.lock; `fastboot flash recovery` may fail on
>   husky — instead `fastboot reboot recovery` boots the already-flashed
>   halium recovery) → `adb shell` is ROOT → **GOTCHA: the recovery
>   mounts a tmpfs OVER the real userdata at /cache** — unmount it
>   (`umount /cache` twice / mount by-name at /mnt/u) or writes vanish.
>   Real tree: `user-data/phablet/...` (bind source of /home/phablet).
>   Write `user-data/phablet/.ssh/authorized_keys`, `chown -R
>   32011:32011`, 700/600, sync, umount, reboot.
> - userdata = sda34 (ext4, was wiped/reformatted 2026-11-10 17:59 —
>   R0 drill side effect; halium initrd auto-mke2fs's zeroed headers).
>   UT rootfs lives as image files at its root (`system_a.img`,
>   `android-rootfs.img`); bring-up artifacts (lsc-wrapper-husky,
>   husky-journal.txt, …) persist there.
> - pstore: by-name `pstore` mounts with `mount -t pstore` in recovery;
>   last system boot's panic was `iommu_release_device` in
>   systemd-shutdown (defect #6 family, seen on the test-audio boot).
>
> **Host state (post-cleanup rebuild):** `husky-verify/` (new key +
> key.sh, wait-for-phone.sh, fetch-release.sh, cpio-ls.py, unsparse.py,
> ext4-ls.py with offset support, debugfs-shim.py + cpio shim under
> /tmp/shims), `husky-flash/` (test-audio-restore-debug + r8-baseline-debug
> releases, verified, plus extracted super.raw for BOTH), `work/audio-restore/`
> (overlay staging tree recovered from git 19f85ff, 41 files).
> NOTE: a PARALLEL tegu session repurposed dirs and flipped local repo
> checkouts (kernel-patches-husky / lineage-kernel-manifest-husky are on
> display branches with mixed remotes) — use GitHub API for branch facts.
>
> **Next session, in order:**
> 1. Phone must reach a call-testable state: current mixed state is
>    good-screen + SSH-capable. Live-inject the audio overlay (staging
>    tree at `work/audio-restore/overlay-root/...`; injector must stop
>    `minimedia` and start audioserver AS USER `audioserver` — check for
>    `su` in container first), verify `service list` shows
>    `media.audio_policy: [android.media.IAudioPolicyService]`, then
>    call test per `call-test.md` (was lost with husky-verify; recreate
>    from this doc's audio section).
> 2. Flash ONLY the test-audio-restore boot images (already in
>    `husky-flash/test-audio-restore-debug/boot-images/`) onto the
>    baseline super: verifies the pKVM segment (samsung_iommu/s2mpu in
>    lsmod, no "failed to resume s2mpu" spam, YouTube no-panic, clean
>    shutdown) while the screen should stay good. If the flicker
>    returns, the segment IS implicated after all — recheck.
> 3. Narrow the super flicker: content-level diff the 3.5 GB rootfs
>    partition of both supers (binary diff is allocation-noise-blind;
>    regions mapped: whole rootfs + 6872-6940 MB small partitions),
>    and/or bisect by flashing test-audio super + removing overlay.
> 4. Only then reflash the full test-audio image and run the §-order
>    verification: lsmod/sysmmu → YouTube → camera → shutdown → call
>    audio → display kernel zips (force60/wqhd — note kernel CI for
>    those branches may be invalidated by the parallel session's work).
> 5. Docs housekeeping: README status matrix + BRINGUP-LOG defect #2/#6
>    entries pending the verifications above.

> **2026-11-12 addendum #2 (push day + YouTube-crash fix):**
> ALL of addendum #1 is now PUSHED and building on CI:
> - `test-display-force60` + `test-display-wqhd`: kernel experiment
>   branches (kernel-patches `5fec8a3`/`db8e90b`, manifest
>   `496a30e`/`976be53`) → rolling `*/kernel.zip` when CI finishes.
> - `test-audio-restore` (device repo `19f85ff` + `ea99c53`): framework
>   audio restore overlay (defect #2) AND the pKVM ramdisk injection
>   (defect #6 / YouTube reboot fix).
> **YouTube crash root cause (fully verified):** MFC opens with a NULL
> IOMMU domain → `iommu_map_sg(NULL)` → panic. Chain: pKVM-protected
> `pkvm_s2mpu-v9` must load from the boot ramdisk before pKVM finalize;
> the halium initramfs has no vendor modules → early load fails →
> `samsung_iommu_v9` can never resolve `pkvm_s2mpu_of_link_v9` → no
> SysMMU binds → MFC domainless. Fix: `scripts/make-pkvm-ramdisk-
> segment.sh` injects the protected modules + 25-module dep closure as
> a cpio segment into the boot ramdisk. Full analysis:
> `husky-verify/YOUTUBE-CRASH-ANALYSIS.md`.
> **Next session:** wait for device CI image, then verify in order:
> (1) `lsmod | grep samsung_iommu` + sysmmu driver bindings, (2) YouTube
> playback, (3) camera capture, (4) clean shutdown, (5) call audio per
> `husky-verify/audio-20261112/call-test.md`, (6) flash force60/wqhd
> kernel zips and run `husky-verify/display-experiment-check.sh`.
> Phone RNDIS (10.15.19.82, key `bootdebug/husky-rndis-key`, empty sudo
> pw) drops often — retry loops are in `husky-verify/wait-for-phone.sh`.

> **2026-11-12 addendum #1 (offline session — SUPERSEDED by #2, kept for
> history):** display experiment branches prepared; call-audio root
> cause found (GSI strips the framework audio stack; `minimediaservice`
> registers the dead `media.audio_policy` stub) with a fully assembled,
> validated restore overlay; live-injection test kit requires only an
> SSH-connected phone — no reflash. Details: `BRINGUP-LOG.md`
> 2026-11-12 section and `husky-verify/audio-20261112/NOTES.md`.

> **2026-11-11 late session addendum (display + call audio):** see §5 for
display-artifact results (kernel side exonerated, slot-a dead, next: LOS flash
or kernel mode patch) and **§9 for the call-audio workstream** (root cause
found: dead media.audio_policy stub + missing telephony patch driver; working
ITelephony mode-switch tooling built). Evidence bundles:
`husky-verify/evidence-20261111-display/` and `husky-verify/audio-20261111/`.

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

Phone: Pixel 8 Pro (verify identity with `fastboot getvar product` before every flash; do not publish the serial), normally slot **b**.
Host: Windows + Git Bash; adb/fastboot live on the bring-up host (not in this repo).

- **Fastboot:** Power+Vol Down at boot. Verify `fastboot devices` shows the
  serial before every flash.
- **Flash UT:** unzip release; `fastboot set_active b`; flash `boot`,
  `init_boot`, `vendor_boot`, `vendor_kernel_boot`, `dtbo` from
  `boot-images.zip`; `fastboot flash super super.img` (reassembled from parts,
  verify `SHA256SUMS` first); `fastboot reboot`. Full sequence lives in
  `reflash-super.sh` (bring-up host).
- **First shell after a fresh debug flash** (documented in README):
  rescue sshd on `10.15.19.82:8022` accepts **publickey only** (usb-moded
  rescue mode spawns it; our own `usb-moded-ssh.service` fights for the same
  port and loses). Install the bring-up key from the Terminal app on the
  phone: run `sudo sh ~/Downloads/key.sh` after downloading
  `docs/phone-first-shell/key.sh` from raw.githubusercontent (browser copy of
  long commands is unreliable; PC-hosted HTTP doesn't reach the phone through
  Windows firewall).
- **Bring-up key:** private `husky-rndis-key` on the bring-up host (pubkey in
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
  Harness: `flag-test.py <label> <quirk:on|off> <overlays:on|off>` (bring-up host)
  does exactly this + restarts lightdm.
- Restarting lightdm drops networking for ~30–60s (both RNDIS and Wi-Fi);
  wait and retry all channels.
- **Recovery** (pstore, last_kmsg): flash the archived LOS stack (bring-up host) →
  recovery → Advanced → Enable ADB → mount userdata → pull logs. See
  `BRINGUP.md`.

## 4. Token / credential hygiene (ACTION REQUIRED)

The GitHub PAT used for API/git access is stored only on the bring-up host and
**appeared in plain text in session tool output**. It must be **revoked on GitHub**
(`Settings → Developer settings → Personal access tokens`) once CI use is
done, and replaced with a fresh token stored outside the repo/docs. No token
may be committed to the repos (roadmap SAFE-029 / Phase 0 gate).

## 5. Display bottom-band artifact — investigation state (defect #1)

Symptom: bottom ~1 inch of the panel shows a persistent fragmented **mirror of
top-of-screen content**; visible from the boot-splash window (before Lomiri),
constant across all UI activity. Evidence bundle:
the bring-up host's `flag-tests/` evidence bundle (MATRIX.md, per-test DRM
state, compositor logs, props).

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

Working theory: the compressed DSI stream is short by roughly the
corrupted band, or the DECON/DPP window wraps — the band shows stale buffer
memory rather than fresh pixels. Why UT differs from Android is unknown;
candidates: DSC PPS programming via composer3 in the halium path, GIDLE/
self-refresh entry, TE2 config.

### 2026-11-11 session results (photos + register audit)

- **Artifact classified** (photos/video in `husky-verify/evidence-20261111-display/`):
  bottom ~10% shows live squished/striped content + constant red strip at the
  very bottom edge. Not stale-frame, not Lomiri-related (predates Lomiri).
- **fb 1008x2256 = benign**: ceil(2244/16)*16 gralloc alignment padding; DPP
  window scans exactly 2244 (WIN0 end regs, LCD size regs all 2244).
- **Decon DSC registers verified CORRECT** (reg dump decoded against
  `display/samsung` headers): PPS matches `fhd_pps_config` byte-for-byte
  (pic 1008x2244, slice 504x187, 12 slices, all RC params); GRPCNTLINE=168 /
  REMAINDER=3 consistent with slice_width 504. DSC2 off as expected.
- **Panel driver audit** (`panel-google-hk3.c` @ gs-6.1_devices lineage-23.2):
  FHD DSC config self-consistent (12x187); PPS re-sent every `hk3_enable`
  per-mode; BUT `hk3_init` hardcodes CASET 0-1343 / PASET 0-2991 (WQHD) and
  `hk3_mode_set` never updates the address window for FHD. Same behavior
  under Android though, so not sufficient to explain the artifact alone.
- **No SurfaceFlinger in container** — Mir drives `hwc3-service.pixel`
  directly. Props (`vendor.display.preferred_mode`, boot_config) confirmed
  ignored (mode stays 1008x2244@120); `vendor.primarydisplay.op.hs_hz=120`
  (stock defaults 60Hz NS and switches dynamically — we run locked 120Hz HS).
- underrun_cnt=2, idma_err=0, ecc=0, recovery=1 — no systemic underrun.
- **Slot a is dead** (fastboot fell back to b) — no LOS baseline on device.
  LOS images exist at `work/forensics/los-images/` (payload.bin etc., Nov 4).
- RNDIS link dropped 3x this session; recovers on its own or via replug.

Next: force-60Hz or WQHD experiment (kernel patch, CI) and/or flash LOS to
slot a for the native baseline (see BRINGUP.md; slot b UT stays intact).

### Pre-2026-11-11 state

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

- **Display:** §5 checklist; all tooling on the bring-up host.
- **New device-repo change:** commit on `cleanup-r8-baseline`, push, watch run
  via `watch-ci-safe.sh <run-id>` (bring-up host) (run id from the API), download
  from the rolling release, `reflash-super.sh` pattern (super-only if boot images unchanged).
- **Kernel change:** commit patch in `kernel-patches-husky` (see its README +
  `apply-patches.sh`), push branch (triggers kernel CI, hours), then device CI
  picks the new kernel.zip automatically.
- **Validation runs:** SSH helper pattern in `flag-test.py` (bring-up host)
  (paramiko, multi-channel connect, `sudo -S` with empty password).

## 9. Call audio workstream (2026-11-11 evening, defect #2)

**Symptom:** calls connect, no bidirectional audio. PA voicecall profile 0/0.

**Root cause chain (established):**
1. `module-droid-card-aidl` (PA) tries generic AIDL patches
   (telephony-rx→speaker, mics→telephony-tx); the Pixel HAL rejects them
   ("Audio patch ... not implemented" in PA log). Generic patches are the wrong
   mechanism for telephony on this HAL.
2. **`media.audio_policy` in the container is a dead stub** — 41 transaction
codes scanned (1-10, 40-70), ALL return status=0 with empty replies; registered
   with empty interface `[]`. The real AudioPolicyService is NOT running/driving
   anything. Therefore nobody creates the telephony patches and the HAL voice
   engine never starts (`Voice call started: false` even with ACTIVE call +
   IN_CALL mode). **This is the thing to fix** — if the real APM runs, telephony
   works as on Android. Next probe: why is it a stub (audioserver boot crash?
   missing config? check logcat from boot, check halium rootfs init.rc).
3. HAL itself is fine: full telephony port/route declarations, and it learns
   call state from the modem by itself (`cs: [CallSession ACTIVE]` during call).

**Proven working tooling (host-side, Python ctypes + libgbinder on /dev/binder):**
- `IModule.getTelephony` (txn 2) → ITelephony object.
- `ITelephony.switchAudioMode(mode)` (txn 2) → **works**, HAL AudioMode flips
  (IN_CALL↔NORMAL verified in dumpsys). Does NOT start the voice path alone.
- `ITelephony.setTelecomConfig` (txn 3) → fails (-22/-61/0x80000008): parcel
  layout for TelecomConfig still wrong (voiceVolume @nullable Float, ttyMode
  enum, isHacEnabled @nullable Boolean). `Voice volume: 0` in HAL — likely
  needs fixing for audible downlink once the path starts.
- Scripts: `husky-verify/audio-20261111/` (telephony_switch_mode.py works;
  aps_*.py probes; NOTES.md has the full ctypes/gbinder recipe + txn codes).
- Wrapper: `husky-verify/on-phone.sh <file> <basename> <interp> [args]` —
  copies to phone (waits for RNDIS), runs, retries on drops. `wait-for-phone.sh`
  for RNDIS-or-Wi-Fi.

**Fix candidates (ranked):**
1. Revive the real AudioPolicyService (find why it's a stub) — cleanest.
2. Hand-create telephony patches via raw binder (IModule.setAudioPortConfig=18
   + setAudioPatch=17), replicating APM sequence; exact AudioPortConfig values
   for speaker/mic are in `audio-20261111/imodule-dump.txt` method log.
3. Once path starts: set voice volume (fix setTelecomConfig parcel).
4. Then wire ofono call state → switchAudioMode (+patches if needed) via a
   host daemon; `audio-20261111/ofono-call-audio-mode.sh` is a draft skeleton.

**Reference:** hater.cc blog "cmcc-volte-on-self-built-aosp" — same AIDL aoc
HAL on komodo; voice path = AoC; uplink route `microphones ->
voice-call-uplink` in media logs when healthy.
