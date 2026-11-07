# Husky bring-up log

## DAY 4 2026-11-07 ~08:15 UTC
- Reflashed full `latest-test-r12-rootfsfix` (commit 0fdb15e; verified
  sha256 2b9b27b5... for reassembled super.img). Boot: white logo ~2.5 min
  -> self-reboot -> fastboot fallback. CONSISTENT with the known 6.349s
  HSI0/S2MPU USB panic (panic -> reboot; slot never marked successful).
- IKCFG re-verified on the flashed kernel: 6.1.145, CONFIG_ARM64_ERRATUM_4118414=y
  (method: unpack boot.img -> kernel is LZ4 LEGACY frame -> ~/bin/lz4 -d -l,
  then IKCFG_ST->IKCFG_ED region holds one gzip at +8, FLG has reserved bit so
  parse manually; python zlib wbits=31 works on the region slice).
- Device branch `test-r12-s2mpu-rtpm` created from test-r12-rootfsfix and PUSHED.
  NOTE: push did NOT trigger build-final (paths filter should have matched
  build-patches/**; GitHub never queued it) - dispatched manually with the
  watch-ci.sh PAT: run 42354412758 (workflow_dispatch, in_progress 08:11 UTC).
  Kernel dep: release tag test-r12-s2mpu-rtpm (kernel run 42301690735 SUCCESS).
- NEXT: when run 42354412758 goes green, download latest-test-r12-s2mpu-rtpm
  boot-images.zip + super.img.part-*, flash ALL incl. super (rootfsfix lives
  there), boot, watch for ADB/Lomiri. If panic: pstore capture per day-3 method.

## DAY 4 2026-11-07 ~09:00 UTC
- s2mpu-rtpm device build: run 42354412758 SUCCESS -> release latest-test-r12-s2mpu-rtpm
  (08:22). Full set flashed (boot stack 08:25 + super 08:29, sha256 9cac7a62...).
- Boot 08:32: HOST SAW USB GADGET ENUMERATE ~08:47 (RNDIS 18D1:D001 + composite
  4EE0/4EE2/4EE9 = MTP+ADB+MIDI) => kernel got PAST the 6.348s SysMMU USB panic -
  the rtpm workaround WORKS at least intermittently. ~08:52 USB dropped and never
  returned; no fastboot, no adb since. Phone presumed hung (at logo) or panic-looping
  silently. pstore should hold the successful boot's full log (ramoops keeps last
  flushed record) - CAPTURE IT when phone is back in fastboot.
- HOST BLOCKER: this Windows box has NO adb/rndis driver bound and NO admin rights
  (pnputil denied). Bootloader fastboot works (winusb.inf already bound to 4EE0).
  Prep for user: elevated `pnputil /add-driver <usb_driver>/android_winusb.inf
  /install` (already downloaded to C:\Users\lukes\AppData\Local\Temp\usb_driver)
  then RNDIS binds automatically -> ssh/adb over 10.15.19.x possible.
- Watcher logging phone state transitions: ~/bootdebug/day4/phone-state.log.
- pstore.txt (rootfsfix era) re-analysis: deterministic 6.348s panic loop; ABL-side
  DECON/panel (google-hk3 1344x2992) init seen in log is BL splash only.

## ROOT CAUSE + FIX 2026-11-07 ~22:15 UTC
Full source-level analysis (LineageOS gs-6.1 trees) unified every symptom:

1. exynos_usbdrd_phy_probe (eusb.c) resolves phy_drd->s2mpu via the
   "s2mpus" phandle AT PROBE TIME. If the phy probes before pkvm-s2mpu
   registers its platform device -> s2mpu_pdev = NULL -> phy_drd->s2mpu
   NULL FOREVER (never re-attempted). All exynos_usbdrd_s2mpu_manual_control()
   calls then silently no-op -> S2MPU never switched to allow-all ->
   HSI0 SysMMU PTW ACCESS FAULT at first USB gadget DMA -> panic.
   INTERMITTENT by module load order (uevents vs LOS init.insmod order):
   explains 08:47 success vs evening failures with identical images.
2. All "nvhe" CI boots were truly nvhe (last cmdline occurrence wins;
   el2-module lines absent; pstore shows "pKVM disabled, control from
   kernel"). Under nvhe __pkvm_s2mpu_resume writes the allow-all bypass
   register directly (S2MPU_V9 CTRL_PROT_EN_PER_VID_CLR) - fine.
3. The day-2/3 "garbage CFI pointer" (target etm2dram_probe) was a
   DANGLING s2mpu_notify: protected-mode experiments made pkvm_s2mpu
   module init fail (el2 load -95) AFTER set_s2mpu_pm_ops succeeded ->
   module unloaded -> static pointer into freed module memory reused by
   etm2dram. Not a build/CFI-type issue.
4. pm_runtime workaround patches (rtpm/hold) couldn't work: they sat on
   the same possibly-NULL phy_drd->s2mpu, and pm_runtime_resume !=
   __pkvm_s2mpu_resume when runtime PM disabled/not-enabled path taken.

FIX = single hunk in phy probe: return -EPROBE_DEFER when the s2mpu
platform device is not yet registered (driver core re-probes later).
Stock manual_control path restored; workarounds deleted.

Experiment test-r12-phydefer: kernel-patches 4cbfc29, manifest 531bd4d,
kernel CI run 42417595737. Device branch to follow (from s2mpu-hold:
keeps rootfsfix + panic=10 bootconfig).

## DAY 4 EVENING 2026-11-07 ~19:45 UTC
- Battery died while hung (black screen); pstore from the good 08:47 boot LOST
  with DRAM power. User charged, back in fastboot.
- RERUN of s2mpu-rtpm (boot stack reflashed, super unchanged): hung at logo ->
  ABL fallback -> fastboot. INTERMITTENCY CONFIRMED: the rtpm variant wins the
  S2MPU race only sometimes (when pkvm_s2mpu probed before dwc3 powers on).
- Theory refined with both failure modes:
  1. early: phy_drd->s2mpu still NULL at manual_control(true) -> silent no-op
     -> SysMMU fault at 6.3s (matches ABL-fallback-after-hang today)
  2. late: pm_runtime_suspend on off-path drops HSI0 translations mid-DMA
     (matches 08:47 USB-up-then-dead-after-5min this morning)
- FIX pushed as experiment test-r12-s2mpu-hold (kernel-patches 2d2e8ef,
  manifest d967396, kernel CI run 42407513837): retry-loop ~4s for s2mpu link +
  pm_runtime_resume_and_get held forever (off-path no-op). Device repo gets
  bootconfig panic=10 + softlockup_panic=1 so future panics self-reboot.
- Driver blocker SOLVED: user ran install-drivers.cmd (Google usb driver in
  store as oem28.inf). adb/rndis should bind on next gadget enumeration.
- device branch test-r12-s2mpu-hold to be pushed AFTER kernel release exists.

### Day 4 next actions (ordered)
1. Phone back in fastboot -> flash LOS stack from ~/husky-verify -> recovery ->
   read pstore: how far did the s2mpu-rtpm boot get before dying?
2. If user grants admin: install android_winusb.inf -> adb works -> much faster loop.
3. Next kernel iteration depends on pstore contents. DRAFT ready (uncommitted)
   in ~/kernel-patches-husky branch test-r12-s2mpu-hold: replaces suspend with
   pm_runtime_resume_and_get held forever (off-path = no-op) - theory: the rtpm
   variant's pm_runtime_suspend drops HSI0 translations while USB DMA is in
   flight (UT re-enumerates gadget during boot) -> repeat SysMMU fault.
4. Driver install for user (right-click as admin): ~/bootdebug/day4/install-drivers.cmd

## HANDOVER 2026-11-06 ~22:40 UTC (day 3)
STATUS: VERY CLOSE TO FIRST USERSPACE BOOT. The kernel now reaches Ubuntu Touch
userspace; the temporary USB/S2MPU workaround is the last known boot blocker.

### Verified today
- `test-r12-nocfi` (CFI disabled): no readable pstore and no ADB/fastboot
  recovery -> hang. CFI is not the root cause; it catches a real bad indirect
  call.
- `test-r12-nos2mpu` (S2MPU callback no-op): bypassed the original CFI panic
  and reached the Halium initrd. First it exposed a rootfs failure:
  `EXT4-fs (dm-0): couldn't mount RDWR because of unsupported optional
  features (4000)` = ext4 `shared_blocks`, newly enabled by CI e2fsprogs 1.47.
- Device branch `test-r12-rootfsfix` adds build-tools patch
  `0002-system-image-disable-shared_blocks.patch`; final working operation is:
  `e2fsck -fy -E unshare_blocks "$OUT/rootfs.img"` immediately after mkfs.
  The first two patch iterations (`mke2fs -O ^shared_blocks`, then tune2fs)
  failed in CI and should be squashed away before merging.
- Combined no-S2MPU kernel + fixed super reached UT userspace. Pstore contains
  running userspace tasks: `snapd`, `click`, `aa-clickhook`, `d-logind`.
  It then panicked at 6.349s when USB gadget started:
  `SysMMU READ PTW ACCESS FAULT from HSI0 ... at 0x0ffffe000`.
  Save: `~/bootdebug/test-r12-rootfsfix/pstore.txt`.
  CONCLUSION: `shared_blocks` fix is verified; no-S2MPU no-op is not viable
  because S2MPU must be resumed/bypassed for HSI0 USB DMA.

### Running overnight
- kernel-patches branch `test-r12-s2mpu-rtpm` (commit 6edb872) replaces the
  no-op with direct S2MPU runtime-PM calls in
  `exynos_usbdrd_s2mpu_manual_control()`:
  `pm_runtime_resume(phy_drd->s2mpu)` for on, `pm_runtime_suspend()` for off.
  This avoids the corrupted `s2mpu_notify` cross-module function pointer without
  skipping S2MPU configuration. Patch applies cleanly to lineage-23.2 source.
- kernel manifest branch `test-r12-s2mpu-rtpm` (commit 7e27949) points at that
  patch branch and was pushed at ~22:03 UTC.
- Kernel CI run to check first: `42301690735`
  (`lineage-kernel-manifest-husky`, branch `test-r12-s2mpu-rtpm`).
  Last confirmed state ~22:31 UTC: `in_progress`. GitHub unauthenticated API
  polling later hit 403/rate-limit; use an authenticated API call in the morning.

### Tomorrow: next steps in order
1. Check run `42301690735`. If green, download
   `https://github.com/L55-CMD/lineage-kernel-manifest-husky/releases/download/test-r12-s2mpu-rtpm/kernel.zip`.
2. Create/push device branch `test-r12-s2mpu-rtpm` from `test-r12-rootfsfix`
   (so it includes the verified shared_blocks fix). Device CI will resolve the
   same-name kernel release automatically and build boot images + super.
3. Download `boot-images.zip` and all `super.img.part-*` from
   `latest-test-r12-s2mpu-rtpm`; concatenate the super parts. Flash boot,
   dtbo, init_boot, vendor_boot, vendor_kernel_boot, AND super. Super is
   required: the rootfs fix lives there.
4. Phone: serial 38111FDJG001WM, slot b, bootloader unlocked. If in recovery:
   `adb reboot bootloader`. If frozen at logo: hold Power+VolUp+VolDown ~20s,
   then Power+VolDown for fastboot.
5. Boot and watch for ADB. Success means Lomiri/UT UI may appear; then run the
   normal display/touch/WiFi/audio/sensor matrix from README.
6. If it panics: pstore capture method is flash full LOS stack from
   `~/husky-verify`, boot recovery, accept ADB, then
   `adb shell cat /sys/fs/pstore/console-ramoops-0`.

### Key paths/branches
- Best evidence: `~/bootdebug/test-r12-rootfsfix/pstore.txt`
  (UT userspace reached, then HSI0/S2MPU panic).
- Device branch: `test-r12-rootfsfix` (contains shared_blocks fix; local branch
  has the final e2fsck version; remote history may still show the two failed
  iterations unless squashed/force-pushed).
- Kernel branch: `test-r12-s2mpu-rtpm` in both `kernel-patches-husky` and
  `lineage-kernel-manifest-husky`.
- Local repos now have a `github` remote because old `origin` points at tegu.
- `~/bootdebug/watch-ci.sh` contains a VALID classic PAT in plaintext. Revoke it
  when this phase is done; do not paste it into chat.

### Closeness estimate
The OS is effectively one boot blocker away from a usable first UI: kernel,
initrd, rootfs mount, and userspace startup are all proven. If runtime-PM
S2MPU control works, remaining work is expected to shift from boot bring-up to
device enablement/bug fixing (display, touch, WiFi, audio, sensors, USB).

---

## UPDATE 2026-11-04 ~11:20 UTC
- los-pure (STOCK LOS kernel content, zero halium patches/config) on our kleaf
  pipeline: FROZEN LOGO. Halium patches/config EXONERATED as the CFI crash cause.
  Delta vs working LOS nightly = our BUILD ENV. Prime suspect: thin LTO
  (kleaf gki default; LOS builds LTO_NONE).
- kleaf has NO --lto bazel flag at this revision (tools/bazel run --lto=none was
  silently ignored; kernel still CONFIG_LTO_CLANG_THIN). LTO is controlled by
  defconfig only.
- NEW BUILD RUNNING: test-r12-ltonone-cfg (kernel-patches branch
  halium-husky-ltonone = halium-husky + halium.config override:
  '# CONFIG_LTO_CLANG_THIN is not set' + CONFIG_LTO_NONE=y).
  VERIFY IKCONFIG LTO_NONE BEFORE FLASHING (lz4.exe -d + IKCFG_ST method).
- CI gotcha: pushes to kernel-patches repo do NOT trigger kernel builds (manifest
  repo workflow only) - re-dispatch workflow_dispatch manually after patch changes.
- git tree API commits default files to 100644 - preserve 100755 for *.sh or CI
  fails with Permission denied.

---

## UPDATE 2026-11-04 ~13:30 UTC
- gki_defconfig LTO_NONE append (aosp/0015) APPLIED in build but STILL THIN result:
  build log shows '.config:7550:warning: override: LTO_CLANG_THIN changes choice state'
  - a later merge stage re-asserts THIN after the defconfig. gki_defconfig has NO LTO
  line of its own; olddefconfig alone would default the choice to THIN.
- kleaf LTO mechanism FOUND (kernel/build @ 6b755daf, kleaf/BUILD.bazel): string_flag
  //build/kernel/kleaf:lto (values default/none/fast/thin/full; 'default' = defconfig).
  kernel_build(lto=...) selects lto_is_* config_settings. CORRECT FLAG:
  tools/bazel run --//build/kernel/kleaf:lto=none --config=stamp --config=shusky       //private/devices/google/shusky:zuma_shusky_dist
  Bare '--lto=none' is NOT a registered flag (silently ignored -> build still THIN).
- NEW BUILD RUNNING: test-kernel-r12-lto-none with the correct flag (branch also keeps
  0015 gki_defconfig LTO_NONE append - belt and suspenders).

---

## UPDATE 2026-11-04 ~15:10 UTC
- ROOT CAUSE OF 'CONFIG_LTO_CLANG_THIN=y WON'T DIE': upstream UBports
  arch/arm64/configs/halium.config (created by aosp/0002) contains
  CONFIG_LTO_CLANG_THIN=y explicitly ('full LTO needs too much RAM').
  It merges AFTER kleaf's lto=none fragment -> '.config: override:
  LTO_CLANG_THIN changes choice state' -> final config THIN.
  Evidence: build log action labels (halium.config;lto=none;trim) +
  override warning in @//aosp GKI config INFO; shusky device config had
  NO THIN warning but boot.img carries the GKI kernel (THIN).
- FIX: aosp/0016-halium.config-use-LTO_NONE.patch (1-line-context hunk,
  git apply --check verified locally). Branch halium-husky-ltonone now:
  0015 (gki_defconfig LTO_NONE append) + 0016 (halium.config LTO_NONE).
  Kernel build re-dispatched for test-r12-ltonone-cfg ~15:10 UTC.
- Watcher note: background watchers die at 3600s; restart after.

---

## UPDATE 2026-11-04 ~16:45 UTC
- LTO_NONE kernel (verified CONFIG_LTO_NONE=y in IKCONFIG): SAME CFI panic.
  LTO EXONERATED. Bogus target CHANGED between builds (etm2dram_probe ->
  gsa_unlink_s2mpu), same expected type hash 0xd1c748b3 -> NONDETERMINISTIC
  runtime corruption, not a link-time miscompile.
- SOURCE-LEVEL MECHANISM (phy-exynos-usbdrd-eusb.c):
  exynos_usbdrd_s2mpu_manual_control() reads static fn ptr 's2mpu_notify'
  (NULL until exynos_usbdrd_set_s2mpu_pm_ops registers a callback; NULL path
  is a graceful no-op). The pointer contains a LIVE address of ANOTHER
  module's EXPORTED function (varies per build). Static .data initialized
  NULL in the .ko -> runtime corruption = module loader symbol-resolution
  writes landing in wrong slots (corrupted relocs/symtab in built .kos),
  stomping that .data slot.
- Config diff vs LOS kernel now down to: MODULE_SIG_PROTECT + halium features
  only. Nothing CFI/reloc-relevant. Yet LOS nightly modules work.
- DECIDER BUILD RUNNING: test-los-pure-ltonone (los-pure patch set - zero
  halium content patches/config - PLUS kleaf lto=none). This is bit-for-bit
  LOS's content+config+LTO built on OUR pipeline.
  * crashes -> our kleaf/module post-processing pipeline corrupts modules
    (compare strip/sign/compress steps vs LOS build; try module signing off,
    strip variants, uncompressed modules)
  * boots (to ~20s orderly shutdown as with LOS stack) -> halium PATCHES are
    what breaks module relocation; bisect: 0001 (task_struct ABI padding)
    first, then 0014 (binder/config), 0003 (protected modules)...
- pstore capture (works reliably): our kernel + LOS vendor_boot + our
  init_boot/vkb/dtbo -> boot (crash ~1.5s) -> full LOS stack -> recovery ->
  cat /sys/fs/pstore/console-ramoops-0. Latest capture:
  ~/bootdebug/pstore-ltonone.txt (3530 lines, 2 boots, same crash).

---

## UPDATE 2026-11-04 ~19:35 UTC (day 2 wrap-up)
DECIDER RESULTS (test-los-pure-ltonone = stock LOS kernel content + LTO_NONE, our pipeline):
- In OUR full stack: hang/reset ~2min, pstore record UNREADABLE from recovery:
  'pstore: Invalid compression size for deflate: 0' = an EMPTY console capture
  (record exists -> pstore probed; size 0 -> nothing was ever printed to it).
- In FULL LOS stack: reset at ~55s, same empty-capture record.
- REFERENCE: LOS's own nightly kernel + LOS stack = ~20s ORDERLY shutdown with
  a FULL readable pstore capture.
-> Our kleaf build of LOS content behaves DIFFERENTLY from LOS's own build.
   TWO distinct failure signatures by patch state:
   * halium patches ON:  CFI panic @1.4s, corrupted cross-module fn ptr
     (deterministic site, random exported-symbol target per build)
   * patches OFF:        hang/late-death with EMPTY console capture
   COMMON: our build environment vs LOS's. Next suspects, in order:
   1. HOW LOS builds: their gs-6.1 CI may not use kleaf at all (plain make via
      build.config + their clang). Get LOS's exact build command/toolchain for
      husky nightly kernels; replicate exactly (ASK STEFFON / read LOS wiki CI).
   2. Toolchain version: our clang = r487747c-based 17.0.2 (AOSP tag float).
      LOS may build with newer clang (r510928). clang-pin test was done under
      THIN LTO; retry pin under the final config matrix if replicating LOS env.
   3. Module post-processing delta: strip/sign/compress of .ko files
      (kleaf default vs LOS). Compare phy-exynos-usbdrd-eusb-super.ko built by
      us vs extracted from LOS zip: readelf -r / modinfo on both.
- ACTIONABLE NEXT (no new builds needed): extract phy_exynos_usbdrd_eusb_super.ko
  + dwc3_exynos_usb.ko from BOTH our kernel.zip AND the LOS nightly zip;
  diff readelf -r output (relocations) and modinfo. If our .ko has bogus relocs
  -> kleaf module link/postprocess is the bug -> move kernel build to LOS-style
  (non-kleaf) build or fix the kleaf module pipeline flag.
- pstore capture caveat: stock-config kernels write console records that the
  recovery LOS kernel can't deflate-read (empty capture). Capture method only
  works when the CRASHING kernel has a halium-ish console config.

Day 2 final state:
- Branches: kernel manifest: test-kernel-r12 (baseline), test-kernel-r12-lto-none
  (real kleaf flag, THIN - flag alone insufficient), test-r12-ltonone-cfg
  (0015+0016 LTO_NONE, halium) - kernel OK but CFI panics, test-los-pure
  (no content patches, THIN), test-los-pure-ltonone (decider).
  kernel-patches: halium-husky-ltonone (= halium-husky + 0015 gki_defconfig
  LTO_NONE + 0016 halium.config LTO_NONE). device repo: same-name branches.
- pstore captures: ~/bootdebug/pstore-ours-kernel.txt (CFI, thin),
  pstore-ltonone.txt (CFI, LTO_NONE), pstore-decider*.txt (empty).
- IKCONFIGs: ~/bootdebug/*-ikconfig.txt (r12, los, ltonone2, ltofinal).
- Phone: LOS recovery, slot b.

---

## UPDATE 2026-11-04 ~20:20 UTC
- FORENSICS VERDICT (local .ko binary diff, no CI): our phy_exynos_usbdrd_eusb_super.ko
  and dwc3_exynos_usb.ko are BYTE-IDENTICAL to LOS prebuilt kernel's modules
  (all relocs/symbols/section layouts; only .modinfo vermagic/scmversion + build-id
  differ). NO build-time corruption. Saved: ~/work/forensics/ (both .kos,
  analysis.txt, relocations-and-symbols.txt, analyze_modules.py).
- TOOLCHAIN EXONERATED: both kernels built by identical clang 17.0.2 (r487747c)
  + LLD 17.0.2 (banner strings identical).
- REFERENCE KERNEL IDENTITY: LOS nightly husky kernel = GOOGLE'S OFFICIAL PREBUILT
  GKI kernel (banner suffix -ab16017558 = AOSP CI build id), not a LOS custom build.
  gki_defconfig there has NO LTO line (LTO_NONE = their GKI release default).
- REMAINING SUSPECT: the GKI kernel image itself - its module loader CFI jump-table
  fixup writes function addresses into module memory; wrong-offset writes would
  stomp static callback pointers with random exported-symbol addresses = our
  exact crash signature. Two builds queued:
  1. test-r12-newkleaf: manifest bit-identical to LOS's (kleaf + prebuilts float
     main-kernel-build-2023 instead of pinned 6b755daf + android-16.0.0_r0.0 tag)
     + halium patches with LTO_NONE (0015+0016). Tests kleaf version.
  2. test-r12-nocfi: halium LTO_NONE + aosp/0017 '# CONFIG_CFI_CLANG is not set'
     appended to gki_defconfig. Tests CFI jump-table mechanism directly.
  If nocfi boots -> CFI handling on zuma + our config is the bug; if newkleaf
  boots -> old kleaf was the bug. If BOTH boot, main should take both fixes.
---

## UPDATE 2026-11-04 ~21:25 UTC
- test-r12-newkleaf (LOS-matched kleaf/prebuilts + halium LTO_NONE): FROZEN LOGO.
  Kleaf version exonerated too.
- test-r12-nocfi first build failed: with CFI off, halium.config's
  CONFIG_CFI_PERMISSIVE=y becomes invalid -> kleaf fragment validation error.
  Fixed via private/devices/0004 (drop CFI_PERMISSIVE), re-dispatched.
- nocfi kernel = r12 + halium patches (THIN as upstream) + CFI_CLANG off.
  If it boots -> CFI jump-table fixup was stomping module memory. If not,
  remaining lead = GKI kernel image vs Google prebuilt GKI binary at runtime.
- Config warning analysis from decider boot: LOS stack cmdline has
  console=null/console=ttynull -> ramoops captures empty (no console output).
  Explains 'invalid compression size 0' on decider captures: decider HUNG early
  (no panic), not the same CFI crash. So unpatched+our-pipeline = EARLY HANG;
  halium-patched = CFI PANIC at 1.4s. Two failure flavors, one suspect: our
  GKI kernel build vs Google's prebuilt GKI binary.

---

## ROOT CAUSE FOUND (2026-11-04 ~10:05 UTC)
Kernel is NOT hanging - it PANICS at ~1.41s every boot:
  CFI failure at exynos_usbdrd_s2mpu_manual_control+0x74 [phy_exynos_usbdrd_eusb_super]
  (target: etm2dram_probe+0x1a8 [etm2dram]; expected type 0xd1c748b3)
  Call trace: exynos_usbdrd_s2mpu_manual_control -> dwc3_exynos_probe (deferred probe)
Mechanism: dwc3_exynos_usb's function pointer for exynos_usbdrd_s2mpu_manual_control
CONTAINS THE ADDRESS OF etm2dram_probe - a cross-module binding/relocation fault INSIDE
ONE consistent build (modules from same r12 build, kver matches). Classic thin-LTO
mis-link signature. Our kernel: CONFIG_LTO_CLANG_THIN=y; LOS kernel: CONFIG_LTO_NONE=y.
tegu (works, same patch set, byte-identical aosp/ patches) is on zumapro - zuma code +
thin LTO + our patchset trips it; zumapro doesn't.

VISIBILITY METHOD THAT WORKS (reuse this!): flash our boot.img + LOS vendor_boot +
our init_boot/vkb/dtbo -> reboot (panics ~1.4s, screen dies, resets to fastboot ~40-90s
or 'frozen logo' - cosmetic timing) -> flash full LOS stack -> fastboot reboot recovery
-> adb (state shows 'recovery' after a while; accept auth dialog) -> cat
/sys/fs/pstore/console-ramoops-0. Buffer holds 257KB incl. PRE-boot DSS panic record.

ALSO LEARNED: any cmdline in boot.img changes failure flavor (reset vs frozen) -
test with CI images; cmdline content bisect was a red herring.
CFI_PERMISSIVE from halium.config silently not in effect (# CONFIG_CFI_PERMISSIVE is
not set in built image) - wouldn't matter, the pointer itself is wrong.

NEXT: r12-lto-none build (tools/bazel run --lto=none ... zuma_shusky_dist) - if it
boots, permanent fix = disable LTO (match LOS). los-pure build = no halium patches
axis also in flight. Watch for NEXT crash after USB PHY (display handoff / initrd
rootfs mount) - pstore loop above gives eyes.

pstore capture saved locally: ~/bootdebug/pstore-ours-kernel.txt (also 2-boot record
in same buffer: u18:4 and u18:5, identical crash).

---

## RESUME HERE (state at end of day 2 morning, 2026-11-04 ~09:10 UTC)
**Running now:** TWO kernel builds on CI (pushed ~08:58 UTC, ~1h each):
- `test-los-pure`: STOCK LOS kernel content (no halium patches/config) on our kleaf
  pipeline, kernel/common r12. Question: does our BUILD PIPELINE produce a booting kernel?
  Boots to ~20s like LOS nightly -> pipeline exonerated, halium patches/config guilty.
  Frozen -> kleaf flags/LTO/toolchain chain guilty.
- `test-kernel-r12-lto-none`: r12 + halium patches/config but `--lto=none`
  (LOS kernel is LTO_NONE=y, ours LTO_CLANG_THIN=y - never-tested axis).

**When each kernel build succeeds:** dispatch device build on the SAME-named branch in
device-google-husky (branches already created):
`POST /repos/l55-cmd/device-google-husky/actions/workflows/build-final.yml/dispatches {"ref":"<branch>"}`

**Then:** download boot-images.zip from release `latest-<branch>` -> phone to fastboot
(Power+VolDown) -> flash boot stack (super unchanged) -> reboot -> watch screen.
NOTE: after many failed boots ABL boot-loops and fastboot screen may be BLACK but USB
fastboot still works - just flash. `fastboot set_active b` stabilizes.

## Day 2 results (2026-11-04 morning)
- r12 kernel VERIFIED to contain CONFIG_ARM64_ERRATUM_4118414=y (IKCONFIG extracted from
  Image.lz4: lz4 legacy frame + IKCFG_ST magic; lz4.exe in ~/bin, python-lz4 CANNOT do it).
  Erratum theory dead as sole cause: mitigation present, canonical r12 still FROZEN LOGO.
- Canonical CI r12 boot-images (latest-test-kernel-r12): FROZEN LOGO (same as main r8).
- Local repack r12 (kernel-only boot.img, empty cmdline): BLANK -> fastboot fallback (~60s).
  Repack is NOT behavior-equivalent to CI image (bootconfig/ramdisk sections differ) -
  always test with canonical CI images from now on.
- r12 + boot.img cmdline lsm=selinux (no kvm override): FROZEN LOGO. Yesterday's
  "lsm override progresses" was confounded by kvm-arm.mode=protected.
- pstore empty after every failure mode - still zero kernel visibility into the hang.
- LOS kernel + halium initrd (our init_boot) + LOS vkb/dtbo: boots past logo, dies
  ~90-100s -> fastboot fallback. EXPECTED: LOS kernel config lacks SQUASHFS/PID_NS/
  anbox-binder (config diff confirms) -> cannot mount UT rootfs. CONCLUSION: LOS kernel
  alone cannot run UT userspace; we MUST make OUR kernel boot. Current builds test that.
- Config diff ours(r12) vs LOS kernel: halium features + LTO thin-vs-none +
  MODULE_SIG_PROTECT + default-LSM ordering only. Nothing else suspicious.

## Key assets on this machine
- ~/bootdebug: mkbootimg.py/unpack_bootimg.py, r12-ikconfig.txt, los-ikconfig.txt,
  kernel-r12.lz4/raw, boot-r12-lsm.img (repack recipe: hdr v4, kernel-only,
  --os_version 16.0.0 --os_patch_level 2026-09)
- ~/bin/lz4.exe (handles legacy lz4 frame)
- ~/husky-flash (our images + super), ~/husky-verify (LOS 23.2 stack),
  /tmp/r12-boot (canonical r12 images; C:/Users/lukes/AppData/Local/Temp on Windows)
- Branches: kernel manifest test-kernel-r12 (bumped common only),
  test-kernel-r12-lto-none, test-los-pure; kernel-patches-husky@los-pure (stripped);
  device repo branches of same names
- CI dispatches need PAT (repo+workflow scope); watcher auto-dispatches device builds
  when kernel builds succeed.

## Experiment matrix (flashed + watched, day 1+2)
| Kernel variant | Result |
|---|---|
| Full halium (main, r8) | FROZEN LOGO |
| No halium.config fragment | FROZEN LOGO |
| No sched.h ABI padding 0001 | FROZEN LOGO |
| No binder.c hunk of 0014 | FROZEN LOGO |
| No apparmor patches 0007-0012 | FROZEN LOGO |
| clang r487747c pinned | FROZEN LOGO |
| r12 canonical (erratum fix IN) | FROZEN LOGO |
| r12 local repack, empty cmdline | BLANK -> fastboot (~60s) |
| r12 + lsm=selinux cmdline | FROZEN LOGO |
| LOS kernel + LOS stack | boots to ~20s, orderly shutdown (expected) |
| LOS kernel + halium initrd | dies ~90-100s -> fastboot (UT fs unsupported) |
| STOCK LOS content, our pipeline (test-los-pure) | BUILDING - pipeline test |
| r12 + LTO_NONE (test-kernel-r12-lto-none) | BUILDING - LTO test |

## Phone facts
- serial 38111FDJG001WM, slot b, bootloader unlocked; stock was Android 16
- After repeated boot failures: ABL boot-loops, rescue mode possible, fastboot screen
  can be black while USB fastboot stays responsive.

## Failure-mode glossary
- FROZEN LOGO: ABL logo stays, kernel hangs in first 1-3s (before ramoops probe);
  no pstore flush ever observed
- BLANK -> fastboot: panel off then ABL fallback to fastboot (~60-100s)
- los-pure boots to ~20s = pipeline exonerated; frozen = kleaf flags/LTO/toolchain guilty

---
# Day 1 log (archived)
 (2026-11-03, evening session)

## RESUME HERE (state at end of day 1)
**Running now:** `test-kernel-r12` kernel build on GitHub CI (dispatched ~23:05 UTC).
Check: `https://github.com/l55-cmd/lineage-kernel-manifest-husky/actions` (branch test-kernel-r12).

**When the kernel build succeeds:** dispatch device build (branch `test-kernel-r12`
already exists in the device repo):
`POST /repos/l55-cmd/device-google-husky/actions/workflows/build-final.yml/dispatches {"ref":"test-kernel-r12"}`

**When device images land:** download
`https://github.com/l55-cmd/device-google-husky/releases/download/latest-test-kernel-r12/boot-images.zip`
→ phone to fastboot (Power+VolDown) → flash boot stack (super unchanged, ours
is still on the phone) → reboot → WATCH SCREEN. Success = anything other than
frozen white Google logo.

**If r12 boots:** permanent fix = bump kernel/common to android14-6.1-2025-08_r12
in lineage-kernel-manifest-husky default.xml on MAIN. Then continue normal
bring-up (display/touch/WiFi/audio matrix per README).

**If r12 still hangs:** verify the r12 tag actually contains
CONFIG_ARM64_ERRATUM_4118414 (extract IKCFG from a local build or check AOSP
tag contents) before more cycles; then compare kleaf flags against LOS's
published kernel build config, and diff LOS's gs-6.1 lineage-23.2 branches for
out-of-tree erratum patches.

Token: API/dispatch calls need a fresh classic PAT from the user (repo+workflow
scope); previous tokens were chat-visible - assume revoked. CI runs themselves
need no secrets (GITHUB_TOKEN only).

## Pipeline status (all green)
- kernel.zip + boot images + super.img building and publishing on GitHub CI (l55-cmd)
- Images flashed to Pixel 8 Pro successfully (slot b)

## Symptom
- Our full image set: boot hangs forever on white Google logo (no display handover)
- Kernel has CONFIG_PSTORE_RAM=y but ramoops buffer stays empty -> hang before
  pstore console probe (~first 1-3 s of kernel init)

## Experiments so far (evidence chain)
1. Garbage kernel -> ABL shows "boot failure" fast => ABL validates; our kernel starts
2. LOS kernel + our stack -> reaches display handover (black phases), dies ~20 s
   (pstore showed orderly shutdown: LOS ramdisk fails against UT super, expected)
3. Our kernel + LOS ramdisk -> fastboot fallback quickly
4. boot.img cmdline overrides ARE honored by ABL (behavior changed)
5. kvm-arm.mode=protected + lsm=selinux override -> fast fail (not the fix)
6. dtbo.img == LOS dtbo content (first 2.18 MB identical; LOS file just padded to 16 MB)
7. vendor_boot structure == working tegu vendor_boot (4 multi-DTBs embedded ~15.9-17.2 MB,
   same cmdline incl. kvm-arm.mode=nvhe + exynos_drm.dp_rate=2, same 64 MB boot.img padding)
8. LOS kernel boots fine with OUR vendor_boot + nvhe cmdline => nvhe itself OK on husky

## Conclusion so far
Our halium kernel (tegu-proven config/patches/toolchain on identical kernel/common)
hangs in first seconds on zuma where LOS kernel doesn't. Delta candidates:
- shusky_defconfig vs tegu_defconfig builtins x halium.config interaction
- zuma google-modules
- halium.config itself (AppArmor default LSM etc.)

## Running now
- CI branch test-no-halium-config: kernel WITHOUT halium.config fragment (pure GKI+shusky)
  - builds clean -> halium.config is the killer -> bisect its options
  - still hangs -> next: branch without apparmor patches (aosp/0007-0012)

## Key assets on this machine
- ~/husky-flash: our full image set + reassembled super.img (reflashing set)
- ~/husky-verify: LOS 23.2 boot stack (boot.img, los-init_boot.img, vendor_boot.img,
  los-vendor_kernel_boot.img, los-dtbo.img) - the "known-good boot stack" kit
- ~/tegu-ref: Steffon's WORKING tegu images.zip (structural reference)
- ~/bootdebug: mkbootimg.py + unpack_bootimg.py + boot-unpacked/kernel + debug images
- ~/platform-tools: fastboot/adb for Windows
- pstore capture method: flash LOS stack -> fastboot reboot recovery -> accept adb
  dialog on phone -> adb shell cat /sys/fs/pstore/console-ramoops-0
  (ramoops flushes only on panic/clean-kmsg-dump; watchdog/ABL resets leave it empty)

## Experiment matrix (flashed + watched)
| Kernel variant | Result |
|---|---|
| Full halium (main) | FROZEN LOGO |
| No halium.config fragment (test-no-halium-config) | FROZEN LOGO -> config exonerated |
| No sched.h ABI padding 0001 (test-no-sched-padding) | FROZEN LOGO -> exonerated |
| No binder.c hunk of 0014 (test-no-binder-patch) | building -> device images next |
| No apparmor patches 0007-0012 (test-no-apparmor) | FROZEN LOGO -> exonerated |
| clang r487747c pinned (test-clang-r487747c) | FROZEN LOGO -> exonerated |
| LOS kernel (reference) | boots to ~20s |
| kernel/common android14-6.1-2025-08_r12 (test-kernel-r12) | building - LEAD THEORY |

## Lead theory: kernel base too old (TLBI erratum)
LOS pins kernel/common android14-6.1-2025-08_r12; tegu manifest had _r8 (4 respins
behind). Config diff vs LOS kernel showed CONFIG_ARM64_ERRATUM_4118414=y in LOS,
absent in ours - the CVE-2025-10263 TLBI completion erratum affects Cortex-X4
and the whole X/A7xx family (same mitigation series covers Cortex-X3 = zuma's
big core). A kernel without the mitigation can hard-hang in the first seconds
on affected silicon - matches our symptom exactly (hang before ramoops probe).
tegu/zumapro silicon presumably predates or misses the erratum, which is why
tegu works on r8.

## Experiment loop learnings

Build gotchas learned:
- GKI trim build requires BT/RFKILL as MODULES (0014 config hunk makes them =m;
  dropping 0014 config side without compensation fails with 'Unable to find
  net/bluetooth/bluetooth.ko')
- halium.config: hci_vhci needs CONFIG_BT_HCIVHCI; MODULE_OUTS entry must match config
- 0014's halium.config hunk also edits AppArmor lines -> can't be used verbatim
  when the apparmor patches are dropped
- experiment loop: kernel-patches branch + manifest branch (revision pointer) +
  workflow_dispatch + device branch of same name + device dispatch; ~1h per round

Next if all patch experiments fail: pin prebuilts/clang/host/linux-x86 to
r487747c (clang 17.0.2, what LOS builds with; manifest currently floats with
the AOSP tag = newer clang) - possible miscompile of zuma early-boot code.

## Phone facts
- serial 38111FDJG001WM, slot b, bootloader unlocked
- stock firmware: Android 16 (was QPR3 beta - never confirmed which stock build)
- DTBO match seen in LOS-stack boot: id 0x40206 rev 0x10000, SOC DTB index 2,
  panel google-hk3 (husky display) - DTB/DTBO selection works
