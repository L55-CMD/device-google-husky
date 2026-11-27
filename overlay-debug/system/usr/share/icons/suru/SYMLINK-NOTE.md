# Ubuntu Plus icon integration — build-time packaging notes (2026-11-26, rev2)

The staged icons are the user's own "Ubuntu Plus Project Icons" pack
(v0.4, user-supplied; source + license: user's asset archive; baked from
currentColor to the on-dark foreground and level-variant-baked by
husky-verify/ubuntu-plus/phase3-icons/bake-pack-icons.py). They supersede
the earlier generated pilot set.

## Symlinked stock names (cp-over-symlink hazard at image build)
Stock suru uses symlinks for these; the overlay ships REAL files. The build
must rm the stock symlink before copying, or the copy writes through and
clobbers the shared target:
  actions/scalable/back.svg            -> go-previous.svg   (overlay ships back.svg AND go-previous.svg)
  status/scalable/indicator-messages.svg -> messages.svg
  status/scalable/indicator-messages-new.svg -> messages-new.svg
  apps/scalable/system-settings-symbolic.svg -> ../../actions/scalable/settings.svg
  apps/scalable/preferences-system-phone-symbolic.svg -> call-start.svg
  apps/scalable/preferences-desktop-sounds-symbolic.svg -> actions/scalable/stock_music.svg
  apps/scalable/preferences-system-privacy-symbolic.svg -> actions/scalable/lock.svg
On-device these were handled by replacing the symlink with a real file after
backing up the target. Same procedure needed at image build.

## Entries REMOVED on device (overlay cannot express removal)
  /usr/share/lomiri-system-settings/mouse.settings
  /usr/share/lomiri-system-settings/printing.settings
User-approved removal (form-factors filtering unimplemented in
lomiri-system-settings 1.3.2). Image build needs an explicit rm step, or a
follow-up decision to ship them again.

## Runtime defaults NOT in the overlay (decisions pending)
- Keyboard theme: device switched to SuruDark via gsettings
  (com.lomiri.keyboard.maliit theme). Both retuned themes ship in the
  overlay; the DEFAULT switch needs a supported image-level mechanism
  (gsettings override) — separate decision.
- Wallpaper default: 12 user-pack wallpapers live in
  ~/Pictures/Wallpapers/Ubuntu Plus on device; NOT staged in the repo yet
  (~44 MB). Decide shipping set + default before adding to the image.
