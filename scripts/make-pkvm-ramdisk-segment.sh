#!/usr/bin/env bash
# Build a cpio segment that makes the kernel's early pKVM module loader
# succeed at boot.
#
# zuma bootargs list kvm-arm.protected_modules=exynos-pd,pkvm_s2mpu-v9.
# Before finalizing pKVM, the kernel spawns a usermode `modprobe` (see
# __pkvm_request_early_module() in arch/arm64/kvm/pkvm.c) against the
# boot ramdisk's /lib/modules. The halium initrd ships no vendor modules,
# so the early load fails silently; once pKVM is finalized the protected
# module can never load (later insmod is refused), pkvm_s2mpu_of_link_v9
# stays unresolved, samsung_iommu_v9 cannot load, no SysMMU binds, and the
# MFC device ends up with a NULL IOMMU domain -> kernel panic on first
# video decode (YouTube playback reboots the phone).
#
# This script extracts the protected modules and their full dependency
# closure from the kernel CI's vendor_dlkm.flatten.img and packs them -
# plus a minimal modules.dep - into a plain newc cpio that the device
# build appends to the halium boot ramdisk (concatenated cpio segments
# are unpacked in order by the kernel).
#
# usage: make-pkvm-ramdisk-segment.sh <kernel-extracted-dir> <output.cpio>
set -euo pipefail

if [ "$#" -ne 2 ]; then
    echo "usage: $0 <kernel-extracted-dir> <output.cpio>" >&2
    exit 64
fi

kernel_dir="$1"
out_cpio="$(realpath -m "$2")"

flatten_img="$(find "${kernel_dir}" -type f -name 'vendor_dlkm.flatten.img' | head -n 1)"
if [ -z "${flatten_img}" ]; then
    echo "vendor_dlkm.flatten.img not found under ${kernel_dir}" >&2
    exit 1
fi

dfs() { debugfs -R "$1" "${flatten_img}" 2>/dev/null; }

modroot="/lib/modules"
kver="$(dfs "ls -p ${modroot}" | awk -F: '$2 == "d" {print $6}' | head -n 1)"
if [ -z "${kver}" ]; then
    echo "could not resolve kernel version dir under ${modroot}" >&2
    exit 1
fi
moddir="${modroot}/${kver}"

dep_file="$(mktemp)"
builtin_file="$(mktemp)"
trap 'rm -f "${dep_file}" "${builtin_file}"' EXIT

dfs "cat ${moddir}/modules.dep" > "${dep_file}"
# modules.builtin may be absent on flattened images; treat as empty.
dfs "cat ${moddir}/modules.builtin" > "${builtin_file}" || true

staging="$(mktemp -d)"
trap 'rm -rf "${staging}"; rm -f "${dep_file}" "${builtin_file}"' EXIT

mkdir -p "${staging}/lib/modules/${kver}"

# Resolve the transitive closure of the protected modules, drop built-ins,
# and stage every remaining .ko. Any dependency that is neither shipped
# nor built-in would fail modprobe at boot and wedge pKVM again - fail the
# build loudly instead.
mapfile -t ship_list < <(python3 - "$dep_file" "$builtin_file" <<'PY'
import sys

dep_path, builtin_path = sys.argv[1], sys.argv[2]

deps = {}
with open(dep_path) as f:
    for line in f:
        line = line.strip()
        if not line or ":" not in line:
            continue
        mod, _, rest = line.partition(":")
        mod = mod.strip().rsplit("/", 1)[-1]
        deps[mod] = [d.rsplit("/", 1)[-1] for d in rest.split()]

builtins = set()
try:
    with open(builtin_path) as f:
        for line in f:
            line = line.strip()
            if line:
                builtins.add(line.rsplit("/", 1)[-1])
except FileNotFoundError:
    pass

targets = ["exynos-pd.ko", "pkvm-s2mpu-v9.ko"]
ship, seen, missing = [], set(), []

def base(mod):  # kmod treats '-' and '_' as equivalent in module names
    return mod.rsplit("/", 1)[-1]

stack = list(targets)
while stack:
    mod = stack.pop()
    if mod in seen:
        continue
    seen.add(mod)
    if mod in builtins:
        continue
    if mod not in deps:
        missing.append(mod)
        continue
    ship.append(mod)
    for d in deps.get(mod, []):
        if d not in seen:
            stack.append(d)

if missing:
    print("unresolvable module deps (not shipped, not builtin): "
          + ", ".join(sorted(set(missing))), file=sys.stderr)
    sys.exit(1)

for mod in sorted(ship):
    print(mod)
PY
)

if [ "${#ship_list[@]}" -eq 0 ]; then
    echo "dependency closure resolved to an empty module set" >&2
    exit 1
fi

for mod in "${ship_list[@]}"; do
    dfs "dump ${moddir}/${mod} ${staging}/lib/modules/${kver}/${mod}" > /dev/null
    [ -s "${staging}/lib/modules/${kver}/${mod}" ] || {
        echo "failed to extract ${mod} from ${flatten_img}" >&2
        exit 1
    }
done

# Minimal modules.dep covering only the staged set, with dep paths
# rewritten to plain filenames (kmod resolves them relative to the
# module dir of the -d root / default /lib/modules/<kver>).
python3 - "${dep_file}" "${staging}/lib/modules/${kver}" "${ship_list[@]}" <<'PY'
import os, sys

dep_path, out_dir = sys.argv[1], sys.argv[2]
ship = set(sys.argv[3:])

deps = {}
with open(dep_path) as f:
    for line in f:
        line = line.strip()
        if not line or ":" not in line:
            continue
        mod, _, rest = line.partition(":")
        mod = mod.strip().rsplit("/", 1)[-1]
        deps[mod] = [d.rsplit("/", 1)[-1] for d in rest.split()]

lines = []
for mod in sorted(ship):
    keep = [d for d in deps.get(mod, []) if d in ship]
    lines.append(f"{mod}: {' '.join(keep)}".rstrip() + "\n")

with open(os.path.join(out_dir, "modules.dep"), "w") as f:
    f.writelines(lines)
PY

# Deterministic cpio (newc), root ownership: the kernel unpacks this as
# root regardless of the archived uid/gid.
(
    cd "${staging}"
    find lib -type f | LC_ALL=C sort | cpio -o -H newc --owner=0:0 --quiet > "${out_cpio}.tmp"
)
mv "${out_cpio}.tmp" "${out_cpio}"

echo "pkvm ramdisk segment: kver=${kver} modules=${#ship_list[@]} -> ${out_cpio}"
