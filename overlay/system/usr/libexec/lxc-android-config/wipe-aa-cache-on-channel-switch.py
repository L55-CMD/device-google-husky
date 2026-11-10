#!/bin/sh
# Husky ships a local rootfs, not a system-image channel, so cache wiping
# intentionally no-ops. The upstream helper exits 1 in that case and blocks
# AppArmor profile loading at boot.
exit 0
