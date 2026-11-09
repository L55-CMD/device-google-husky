# Husky bring-up log

## MORNING CHECKLIST (2026-11-09, r8-lazylink first boot)

1. Check kernel CI run 42559072596 (lineage-kernel-manifest-husky) finished
   green; kernel.zip at release tag `test-r8-lazylink`.
2. Dispatch device build: POST build-final.yml dispatches ref=test-r8-lazylink
   (device branch ALREADY pushed; path filter won't auto-trigger).
   Watch for the ~1/3 publish flake -> re-run failed jobs if so.
3. Download release latest-test-r8-lazylink: boot-images.zip (unzip to
   boot-new/) + super.img parts (SEQUENTIAL downloads only; assembled size
   must equal the sum of parts).
4. Phone is in LOS recovery with adb enabled -> `adb reboot bootloader`, flash
   boot-new/ stack + super.img, `fastboot reboot`.
5. Watch: RNDIS/adb on host within ~2 min = USERSPACE REACHED.  White logo +
   no USB = r8 theory wrong -> read /userdata/husky-blackbox.log (markers now
   cover the whole initrd; watchdog dumps task stacks).
6. If hung: force-reboot (VolDown+Power) -> recovery for reads (full LOS stack
   needed for recovery boots; Enable ADB toggle resets every boot).
## UPDATE 2026-11-09 ~10:35 UTC (day 6, morning) -- r8 theory DEAD; freeze follows the lazy-link patch

### r8-lazylink first boot result (run 42596000434, flashed 10:08)
- Froze at EXACTLY the same op as r12-lazylink: last marker
  `pre-move-userdata` at 6.45s (bb: ~/bootdebug/day6/bb1-full.txt).
  So the freeze is NOT an r12 GKI bug: it tracks the LAZY-LINK module
  patches on BOTH kernel bases.
- Last night's "patches exonerated" cross-experiment was FLAWED: with the
  rootfsfix kernel, the lazylink modules almost certainly never loaded
  (vermagic mismatch / its own vendor_kernel_boot carries stock modules).
  That boot ran STOCK modules -> passed the move -> SysMMU panic 6.47s.
  Corrected correlation:
    stock/noop/rtpm modules -> pass mount --move (every time)
    lazy-link modules      -> total freeze at ~6.1-6.45s (6/6 boots)

### New patch (kernel-patches d93680c, branch test-r8-lazylink)
- manual_control(): NO of_find_device_by_node (deadlock risk in the hsi0
  power-domain path vs dm-node uevent probes at ~6.26s), NO raw
  cross-module s2mpu_notify pointer (CFI/lifetime hazard).  Now uses
  pm_runtime_resume/suspend(phy_drd->s2mpu) -- the rtpm approach, the
  only variant that ever reached userspace with working USB (08:47).
- Probe-order race fix kept ONLY in set_s2mpu_pm_ops() (pkvm probe
  context, safe): links phy_drd->s2mpu when the phy probed first.
- 0003 self-pin kept (harmless, still guards module lifetime).
- Honest caveat: exact freeze mechanism not proven (link may resolve at
  2.4s, so repeated lookups may not even fire).  This build is also an
  experiment: if it still freezes at the same op, the cause is elsewhere
  (self-pin, or the S2MPU bypass itself), NOT the power-path lookup.

### Code review findings (day 6, ~10:55, full source pass)
Sources reviewed line-by-line: phy-exynos-usbdrd-eusb.c (2421 lines),
pkvm_s2mpu.c, common/s2mpu.c, exports.c, exynos-pd.c, exynos-pd_hsi0.c,
dwc3-exynos.c (LineageOS gs-6.1 @ lineage-23.2).
- Caller context: exynos_pd_power_on/off holds pd->access_lock = MUTEX
  (sleepable) -> pm_runtime_* in manual_control is LEGAL there and at the
  dwc3-exynos probe call site (dwc3-exynos.c:1286).
- s2mpu_pm_ops SET_RUNTIME_PM_OPS maps to the SAME __pkvm_s2mpu_resume/
  suspend functions the raw notify pointer called.  nvhe resume = single
  writel_relaxed (no hypercall).
- phy_drd->s2mpu used ONLY in manual_control; no other phy-code surface.
- Stock get_struct() ALREADY does of_find_device_by_node on every
  manual_control call -> the old patch's added lookup was NOT a new risk
  class; the ABBA-lookup theory is weak.
- BUS-STALL HYPOTHESIS (best fit for the freeze): old patch called
  s2mpu_pm_control DIRECTLY -> raw S2MPU MMIO writes without PM core
  powering the S2MPU block/domain first.  MMIO to an unclocked IP = bus
  transaction never completes -> CPU stalls in the store, interconnect
  backpressure -> TOTAL freeze, no pstore/hung_task/watchdog.  Explains
  the wandering freeze time (fires on a pd-hsi0 transition, not on a
  specific initrd op) and why stock-with-NULL-link never froze (no write).
  The pm_runtime path powers suppliers first -> write always lands on a
  clocked block.  The d93680c build tests exactly this.
- If the new build STILL freezes: next suspect is the S2MPU allow-all
  state itself (silent DMA mis-routing corrupting RAM) or non-USB causes.

### v2 (rtpm-style) boot result + noop experiment (day 6, ~22:00)
- v2 kernel (05f10bf, pm_runtime manual_control + safe link): froze at
  pre-move-userdata 6.32s (bb2-full.txt).  EXONERATED: power-path lookup,
  raw notify pointer vs pm_runtime, r12 kernel.  The only common factor
  left: the S2MPU allow-all bypass actually being WRITTEN/ACTIVE.
- Note stock SysMMU panic at ~6.47s vs our freezes at 6.32-6.45s = SAME
  moment -> first gadget DMA is likely the killer in both cases: stock =
  DMA faults -> clean panic; bypass-active = DMA proceeds to a bogus
  address -> silent RAM corruption -> total freeze, zero logs.
- New experiment (kernel-patches 8620ca4, kernel CI run 42706607439):
  manual_control = COMPLETE NOOP on the same r8 base (self-pin kept).
  Freeze persists -> S2MPU theory dead entirely.  SysMMU panic returns
  instead of freeze -> bypass-active confirmed as the killer; fix
  direction becomes "correct HSI0 DMA mappings", not "bypass S2MPU".
- Infra lesson: NO backslash escapes in shell heredocs on this host -
  they get eaten (broke the first v2 kernel build with a literal newline
  inside pr_debug).  Use WriteFile for code content, generate diffs with
  git diff, assemble patches with cat.

### Pipeline
- Kernel CI run 42601712688 building (~45 min).  Then re-dispatch device
  build-final.yml ref=test-r8-lazylink (branch + all initrd instrumentation
  unchanged), download to ~/husky-flash/r8-lazylink/, flash, boot, watch
  for RNDIS/adb.  Blackbox read path unchanged (LOS recovery stack in
  ~/husky-verify, adb pull /mnt/ud/husky-blackbox.log -- use Windows-style
  local path and MSYS_NO_PATHCONV=1).
- Infra note: git push to kernel-patches needs the PAT in the URL
  (x-access-token:...@github.com/L55-CMD/kernel-patches-husky.git);
  credential helper has no stored entry and terminal prompts are disabled.

## HANDOVER 2026-11-09 ~04:00 UTC (day 5/6) -- THE ACTUAL ROOT CAUSE FAMILY

### Correction to earlier notes
**rootfsfix and nos2mpu kernels are GKI tag android14-6.1-2025-08_r8.  ALL
"test-r12-*" kernels are r12.**  I repeatedly called rootfsfix "r12" -- wrong.
The r8->r12 bump happened at the hold branch (day 2/3 era).  Verify the pinned
tag in default.xml before assuming anything from branch names.

### The week, correctly explained
- r8 kernels: boot ALWAYS passes the initrd mount phase (rootfsfix reached
  USERSPACE on Nov 6; nos2mpu pstore shows tasks at 6.3s+).  They still have
  the S2MPU NULL-link race -> 6.4s SysMMU panic unless the race is won.
- r12 kernels: carry an ADDITIONAL latent, intermittent TOTAL-FREEZE bug.
  Day 2's "test-kernel-r12 canonical: FROZEN LOGO, no pstore, unexplained" was
  this freeze.  rtpm (r12) won the dice at 08:47 and ran 5 min; lazylink (r12)
  froze 5/5 boots.  When the S2MPU panic is unfixed it masks the freeze (panic
  at 6.4s vs freeze at ~6.1s are adjacent; whichever fires first wins).
- Our lazylink patches (lazy s2mpu link + pkvm self-pin) are EXONERATED:
  rootfsfix(r8) kernel + lazylink modules + lazylink super -> NO freeze;
  it panicked at 6.47s with the plain stock-S2MPU fault instead (expected --
  that kernel runs unpatched vendor modules from ITS OWN vendor_kernel_boot).

### Freeze signature (fully localized)
- Boot walks to `mount --move /tmpmnt ${rootmnt}/userdata` (~6.1s) then TOTAL
  freeze: no printk, no pstore, no hung_task/softlockup, no watchdog timers,
  no reboots.  White logo forever.
- Per-op flash markers (qlprog -> /tmpmnt/husky-blackbox.log on userdata)
  give line-by-line localization through the whole initrd; the +25s/+60s
  watchdogs also froze, proving it's not a single blocked task but a
  system-wide freeze.
- data=journal vs ordered: irrelevant.  The freeze is an r12 codegen/layout-
  sensitive latent race (a test-no-sched-padding branch exists from earlier
  work -- the r12 scheduler was already suspected once).

### ACTION IN FLIGHT (kernel CI ~45 min, then ~15 min device CI)
- Branch `test-r8-lazylink` (kernel-patches + manifest): GKI **r8** base +
  the same 0001 GPU + 0002 lazy-link + 0003 self-pin patches.  Kernel CI run
  42559072596 building NOW; kernel.zip will land at release tag
  `test-r8-lazylink`.
- Next: create DEVICE branch `test-r8-lazylink` (from test-r12-lazylink tip --
  keeps all initrd instrumentation), push (paths filter may not trigger ->
  dispatch build-final.yml manually), flash boot stack + super, boot.
- EXPECTATION: boot completes to userspace with the S2MPU race fixed -> USB
  gadget comes up when UT's usb service configures it -> RNDIS/ADB on host ->
  live shell.  Then: display handover (never seen working yet), and
  eventually chase the r12 freeze for the merge to main (or stay on r8).

### Working state right now
- Phone: LOS recovery, adb ENABLED (toggle resets every boot).
- On-disk image sets: ~/husky-flash/r12-lazylink (latest r12 build),
  ~/husky-flash/r12-rootfsfix (Nov 6 r8 stack -- the proven-good base),
  ~/husky-verify (LOS recovery stack).
- Blackbox with all stage traces: /userdata/husky-blackbox.log (read from
  recovery: mkdir /mnt/ud; mount /dev/block/by-name/userdata /mnt/ud).
- Never flash a super whose parts were assembled concurrently by a "lost"
  background task -- they keep running and corrupt each other (hit twice).

### Infra quick reference (accumulated)
- Pushes: use PAT inline (GCM hangs): git push https://$TOKEN@github.com/...
  Token: first ghp_... in ~/bootdebug/watch-ci.sh. MSYS_NO_PATHCONV=1 for
  adb pull/push of absolute remote paths.
- CI: device build-final.yml must be dispatched MANUALLY for new branches
  (path filter quirk).  The `gh release create` publish step flakes ~1/3
  (404 on super.img.part-ac) -- just re-run failed jobs.
- Kernel CI triggers automatically on manifest-branch push.
- Device CI resolves its kernel.zip by RELEASE TAG == DEVICE BRANCH NAME.
- Boot images from this pipeline have a NONSTANDARD header (ramdisk size at
  offset 0x0C) -- no local mkbootimg surgery; use CI-built images.
- Recovery reads: flash the FULL LOS stack (boot+dtbo+init_boot+vendor_boot+
  vendor_kernel_boot from ~/husky-verify) or it falls back to fastboot.
- fastboot watch loops: grep for the SERIAL (38111), never the word "device"
  (adb header false-positive).

## DAY 5 night (~01:30 UTC) -- printk-wedge localization

- qlprog markers flush DIRECTLY to /tmpmnt/husky-blackbox.log once userdata is
  mounted (line-by-line, no printk dependency) -- this finally gives exact
  localization through the failure window.
- Boot reaches userdata-mounted at ~5.5s reliably; USB gadget/phy fully up at
  2.4-2.6s (the S2MPU fix works).  dynparts/dmsetup/rootfs-mount either run
  fine or fail fast; the boot ALWAYS wedges in the 5.5-6.0s window.
- Working theory: the kernel console/printk path wedges permanently at ~5.5s
  (some task holds console/pstore lock; all later printks and pstore writes
  block; hung_task then can't even panic because panic printk blocks too --
  explaining no reboots + empty pstore).  Wedge time drifts with which printk
  crosses first.
- Mitigation in build d24da93: after userdata mount, tell_kmsg is redefined to
  write the flash log ONLY, so the initrd can walk through printk-wedge
  territory.  If the boot completes, systemd/userspace (journald doesn't
  printk) may bring up the USB gadget -> live adb shell -> inspect the lock
  holder directly.
- busybox `timeout` applet does NOT exist in this initrd (rc=127).
- dm nodes: dynparts creates them fine; without them the script guesses
  slot suffix _a -- needs verification which suffix the cmdline carries.
- `git am`-able patch flow and all infra lessons remain in this log below.

## DAY 5 late additions (~22:00 UTC)

- **adb watch false positive**: `adb devices` output always contains the header
  "List of devices attached" -- grep for "device" matches it. Watch loops must grep
  for a device serial / state token, never the word "device". An "adb=1" report from
  these loops was bogus.
- **pstore is empty after hung-task panics** (3x confirmed: mount rc=0, dir empty).
  Likely mechanism: the hung task holds a lock the panic dump path needs; the 10s
  panic_timeout fires mid-dump and the reboot lands with nothing written. Short clean
  panics (SysMMU at 6.4s) always wrote fine. Do not expect pstore after hangs.
- **UT userdata layout**: `system-data/{etc,nix,opt,root,snap,var}` -- there is NO
  `system-data/writable/`. UT's /etc/writable is a different mechanism. Any flash-
  resident diagnostics must write to the partition root or self-mount.
- **qlprog design** (build 7d37e7a): per-stage markers from the DYING boot itself,
  appended to /husky-blackbox.log on userdata (survives hard resets). Stages:
  mountroot-entry, pre/post-fsck (with duration), userdata-mounted, post-modules,
  mountroot-done + dmesg tails at each. Systemd logger self-mounts userdata at
  /mnt/husky-dbg. The last QL-PROG line in the black box names the hang stage.
- **release-publish flake**: `gh release create` step intermittently fails after a
  successful build (~1 in 3 lately). Just re-run failed jobs; the build is fine.

## HANDOVER 2026-11-08 ~19:45 UTC (day 5)
STATUS: the 6.4s boot blocker is FIXED in the kernel (test-r12-lazylink:
lazy s2mpu link + pkvm-s2mpu self-pin). Boots now run PAST the old panic
point and hang LATER: steady white logo, zero USB, kernel alive (power
button turns screen off/on = soft hang). hung_task_panic fires after
~60-120s (phone eventually panic-loops to fastboot as ABL retries
exhaust). The hanging task is UNKNOWN - every forensics channel we built
keeps coming back empty (details below). Next session: land the
flash-resident console logger, identify the hung task, fix it.

### Verified today (hard evidence)
1. ROOT CAUSE of the whole week: exynos_usbdrd_set_s2mpu_pm_ops()
   publishes s2mpu_pm_control into a RAW STATIC POINTER in the phy module
   with no lifetime management. phy-probes-first -> link NULL forever ->
   HSI0 SysMMU PTW fault at first USB gadget DMA (6.3-6.4s). Module
   unloaded after publish (modprobe failure cleanup of a zero-refcount
   dep, e.g. after samsung_iommu_v9 fails) -> dangling pointer -> CFI
   fatal in manual_control (observed target = fips140 module memory,
   day-2/3 'garbage CFI pointer' = same family, etm2dram).
2. FIX pushed & CI-green: kernel-patches + manifest branch
   test-r12-lazylink (0002 lazy link resolution in manual_control() AND
   set_s2mpu_pm_ops(); 0003 __module_get(THIS_MODULE) self-pin in
   pkvm_s2mpu mod_init). Both patches validated with git am --3way
   simulation. Kernel CI run 42483940304 SUCCESS; device CI 42487357822
   SUCCESS.
3. phydefer (EPROBE_DEFER in the phy probe) REGRESSED: phy never
   re-probes at all -> zero USB. Do NOT rely on driver-core re-probe on
   this platform. Probe stays 100% stock in lazylink.
4. The stock phy probe has its OWN pd-hsi0 LDO defer; whether its retry
   fires is timing-luck. Hypothesis for the CURRENT hang (unproven):
   defer lands -> no dwc3 -> no UDC -> UT waits for USB forever. An
   initrd UDC-empty bounce of phy-exynos-usbdrd-eusb-super is already in
   the branch (needs a test where the forensics actually capture).
5. hung_task_panic WORKS: initrd sets /proc/sys/kernel/hung_task_panic=1
   @60s (sysctl exists; bootparam compiled out). D-state hang ->
   panic -> 10s -> reboot -> loop until ABL parks in fastboot.
6. Forensics that FAILED and why:
   - pstore after LONG hangs: EMPTY. pstore mounts fine in initrd
     (rc=0, verified d442d17 build) but ALL zones are empty after a
     hung_task panic+reboot. After SHORT panics (6.4s SysMMU) records
     survived. Mechanism unknown (suspect bootloader/DSS stomping or
     zone-header invalidation during the long hang). DO NOT rely on
     pstore for hang forensics on this device.
   - vibrator/backlight user-signals: mistimed - vibrator module loads
     AFTER mountroot-start; detection must happen post-module-load.
     Backlight probes ~2.4s with the panel. Unproven whether any signal
     ever fired (user felt nothing, but timing made stage-1 impossible).
   - quickload initrd preload of pkvm-s2mpu-v9: CAUSED the dangling
     pointer CFI trip (module load-then-unload via modprobe cleanup).
     With kernel 0003 self-pin this is now safe, but the preload itself
     is unnecessary - the kernel patches make any module order work.

### Next actions (ordered)
1. LAND THE FLASH LOGGER (device CI, ~15 min): a systemd service in
   overlay/system that every ~15s writes `dmesg | tail -200` + `ps` to
   /userdata/system-data/husky-console.snap (simple overwrite, no pstore
   dependency; userdata survives panics, initrd e2fsck handles unclean).
   This is THE reliable channel - it captures the last boot messages
   before silence regardless of hang type. (huskies have no standalone
   cache partition; /cache is a userdata dir.)
2. Boot the lazylink build + logger; let it hang; panic-loop; then
   recovery -> mount userdata -> read husky-console.snap. The last lines
   before silence name the hung subsystem (candidates: USB gadget config
   (no UDC), display/DECON handover, lxc/android container, fstab/mount
   wait).
3. If the snapshot shows no UDC: the stock pd-hsi0 defer hypothesis is
   confirmed; the in-branch initrd phy-bounce is the test (or promote it
   to always-run after modules). If it shows a different task: fix that.
4. Only after UT reaches userspace with USB: revisit display (white logo
   never replaced = no fb handover ever observed) and Lomiri.
5. Cleanup debt: remove the abandoned quickload preload + pmsg trace
   services from the device branch once the logger lands; squash 0002
   patch iterations before any merge; delete dead CI branches
   (test-r12-nocfi/nos2mpu/newkleaf/ltonone*/los-pure*).

### Infra/method notes (do not rediscover)
- Git pushes via credential manager HANG (invisible GCM prompt). Push
  with the watch-ci.sh PAT inline:
  git -c credential.helper= push https://x-access-token:TOKEN@github.com/... 
  (TOKEN=$(grep -m1 -oE 'ghp_[A-Za-z0-9]+' ~/bootdebug/watch-ci.sh))
- Device CI push trigger often does NOT fire on new branches; dispatch
  manually: POST /actions/workflows/build-final.yml/dispatches {ref}.
  GitHub 504s on release-asset downloads happen daily; just re-run the
  failed job.
- Device builds ~13-15 min, kernel builds ~40-45 min. Image sets:
  boot-images.zip + super.img.part-{aa,ab,ac}, cat the parts.
- CI-built boot images have a NONSTANDARD header (ramdisk size at 0x0C,
  payload at 4096). Do NOT hand-repack boot images for this pipeline.
- ABL slot-retry-count POISONS diagnosis: after ~3 failed boots ABL
  parks in fastboot and every attempt looks like instant failure. Check
  `fastboot getvar slot-retry-count:b`; reset with set_active a&&b.
  Panic loops exhausting retries look identical to ABL rejection.
- Recovery boots need the FULL LOS stack from ~/husky-verify (boot.img,
  los-dtbo.img, los-init_boot.img, vendor_boot.img,
  los-vendor_kernel_boot.img) - partial swaps fall back to fastboot or
  'no command'. Recovery ADB toggle (Advanced) resets EVERY boot. In
  recovery: mount userdata with `mount /dev/block/by-name/userdata
  /mnt/ud`. adb pull needs MSYS_NO_PATHCONV=1 for absolute unix paths.
- HOST: adb/fastboot verified working (Google USB driver oem28.inf);
  flaky cable was replaced - if the phone drops off USB entirely, reseat
  or swap it. /tmp on this Windows box is aggressively cleaned between
  shell calls - keep scratch files under ~/bootdebug.
- Local artifacts: ~/husky-flash/r12-lazylink (current full image set),
  ~/husky-verify (LOS stack), ~/bootdebug/day5 (pstores, blackboxes,
  CI logs). 26 GB of dead-end experiment images were deleted today.

## DAY 5 2026-11-08 ~10:45 UTC
- phydefer (EPROBE_DEFER in phy probe) EMPIRICALLY WORSE: boot -> zero USB
  enumeration at all (no gadget, no fastboot flap, stable white logo; host
  PnP clean). Two boots identical. The phy never re-probes after defer.
  Lesson: do not rely on driver-core re-probe; keep probe 100% stock.
- GROUND TRUTH from nos2mpu pstore: initrd module order is SEQUENTIAL
  modprobe over modules.load, and the list has
  phy-exynos-usbdrd-eusb-super at ~1.58s BEFORE pkvm-s2mpu-v9 at ~1.89s
  (209 entries). Intermittency = whether the phy's probe deferred at its
  slot (pd-hsi0 state), not list order (fixed per image).
- QUICKLOAD EXPERIMENT (device repo only, d536fae on test-r12-rootfsfix):
  halium init script preloads pkvm-s2mpu-v9 (modprobe, deps auto) ahead
  of the modules.load loop. Tests load-order theory on the STOCK-s2mpu
  r12 kernel (~15 min CI, no kernel rebuild). Device CI run 42473851840.
- Kernel-side robust fix prepared (not pushed): test-r12-lazylink in
  kernel-patches (73ef7d1) + manifest (71ea960): resolve phy_drd->s2mpu
  lazily in manual_control() AND in exynos_usbdrd_set_s2mpu_pm_ops()
  (called from pkvm_s2mpu probe -> device guaranteed to exist). Validated
  vs CI apply path (git am --3way simulation OK). Belt+suspenders for
  post-merge regardless of quickload outcome.
- Also ruled out today: /dev/mem shortcut (CONFIG_DEVMEM not set), and
  the non-super phy-exynos-usbdrd.c symbol collision (not built on zuma;
  zuma_defconfig has only CONFIG_PHY_EXYNOS_USBDRD_EUSB=m).
- BLACKBOX v1 RESULT (6 appends, all empty): the initrd blackbox ran
  during the panic loop but captured nothing - /sys/fs/pstore was never
  MOUNTED in the initrd (pstore is a separate fs; sysfs only provides the
  mountpoint). Added mount + rc/dir logging (d442d17). Also learned:
  recovery adb pull needs MSYS_NO_PATHCONV=1 for absolute unix paths.
- Power-button liveness test: during the hang, a short power press turns
  the screen off/on -> kernel + input are ALIVE -> soft hang (not a hard
  freeze). hung_task_panic later fires (phone eventually lands in
  fastboot after retries exhaust), so the stuck task is D-state.
- HANG DIAGNOSIS CATCH-22 SOLVED: hangs can only be escaped by hard
  button-reset, which DESTROYS ramoops (DRAM lost). Panics survive (soft
  reboot, panic=10). Fix: initrd arms hung_task_panic=1 @60s (sysctl
  exists; the bootparam variant is compiled out but sysctl works), so a
  D-state hang self-panics cleanly; PLUS an initrd 'black box' appends
  the previous boot's entire pstore to /husky-blackbox.log on USERDATA
  (flash) every boot - survives hard resets, readable by mounting
  userdata from recovery. Built in run after 22f74ea (test-r12-lazylink).
- LAZYLINK BOOT RESULT: kernel patches eliminated the panic loop
  entirely (no SysMMU fault, no CFI trip, stable white logo 5+ min) but
  the boot now hangs LATER with zero USB (no adb/rndis/gadget on host).
  Nov-6 rootfsfix reached userspace with same super content, so this is a
  new later-phase hang - probably userspace/USB-gadget/display. Hung-task
  panic + blackbox will capture exactly where.
- ROOT CAUSE UPGRADE (2026-11-08 ~13:00 UTC): instrumented initrd pstore
  capture showed the quickload boot died differently - CFI fatal in
  exynos_usbdrd_s2mpu_manual_control called from exynos-pd kworker, call
  target = fips140 module memory. Mechanism: set_s2mpu_pm_ops() publishes
  s2mpu_pm_control into a RAW STATIC POINTER in the phy module with ZERO
  lifetime management. Load order: samsung_iommu_v9 fails (1.17s, pkvm not
  loaded yet) -> hook loads pkvm-s2mpu-v9 (1.45s, notify set, refcount 0)
  -> loop retries samsung_iommu_v9, fails again -> modprobe failure cleanup
  UNLOADS pkvm-s2mpu-v9 (zero refcount dep) -> notify dangles -> pd-hsi0
  power-on post (kworker) calls it -> CFI fatal (fips140 reused the memory).
  SAME FAMILY as day-2/3 'garbage CFI pointer' (etm2dram). THE S2MPU NOTIFY
  POINTER IS THE WHOLE BUG: NULL link -> SysMMU fault; dangling pointer ->
  CFI fatal; both intermittent by module load timing.
- FIX (test-r12-lazylink, pushed): 0002 lazy link resolution (both failure
  modes of the NULL link) + 0003 __module_get(THIS_MODULE) self-pin in
  pkvm_s2mpu mod_init after successful registration (notify can never
  dangle again). Device-side quickload preload ABANDONED - it caused the
  unload race it tried to fix; with the kernel patches any module order
  works.
- Also captured: kernel cmdline has kvm-arm.protected_modules=
  exynos-pd,pkvm_s2mpu-v9 and *.load_sequential=1 (stock Pixel bootconfig);
  'Failed to load pkvm module exynos-pd: 11' at 0.24s is the kernel-side
  protected-module preload failing pre-initrd - harmless, initrd reloads.
- RETRY-COUNTER POISONING (major methodology lesson): ABL slot-retry-count
  had decremented to 1 across the day's failed boots; afterwards every boot
  attempt showed 'logo briefly -> fastboot' which LOOKED like instant ABL
  rejection but was the normal ~6.4s SysMMU panic + ABL parking in fastboot
  after retries. ALWAYS check `getvar slot-retry-count` before diagnosing;
  `set_active a && set_active b` resets it.
- Console-ramoops wraps: the 6.4s panic's huge stack dumps overwrite the
  1.5-2.5s module-loading window in the 100KB console zone, so initrd debug
  (kmsg) is unrecoverable from pstore. pstore-pmsg (/dev/pmsg0) is the
  answer: CONFIG_PSTORE_PMSG=y in our kernel, separate zone, survives panic.
- Instrumented initrd (a4ec1ae): hook logs every step to /dev/pmsg0. CI
  build 42480936012. Local cpio-surgery repack of init_boot produced a
  structurally valid image but the phone's pstore ended up EMPTY afterwards
  (nonstandard header in CI-built images: ramdisk size lives at 0x0C, not
  the standard 0x10) - do not hand-repack boot images for this pipeline.
- HOST DRIVER BLOCKER GONE: adb works (LOS recovery enumerated, adb
  authorized). Fastboot+adb+PnP all verified today.

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
