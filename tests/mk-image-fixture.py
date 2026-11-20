#!/usr/bin/env python3
"""Build synthetic husky boot-image sets for testing the flash guards in
husky-verify/preflight-boot-images.sh without a real kernel build.

usage: mk-image-fixture.py <out-dir> <variant>
  variant = matched : boot/init_boot/vendor_kernel_boot/vendor_boot agree
                      on the kernel version and carry a complete module set
  variant = stale-kver : vendor_kernel_boot carries a DIFFERENT <kver>
                      module tree (the run-98 partial-flash failure mode)

Image shapes follow exactly what preflight-boot-images.sh parses:
  boot.img / init_boot.img : ANDROID! header (kernel_size @0x08,
      ramdisk_size @0x0C), 4096-byte pages, lz4 payloads
  vendor_kernel_boot.img / vendor_boot.img : VNDRBOOT header
      (vrs @0x18, hdr @0x830, dtbsz @0x834, table num/ent @0x844/0x848),
      0x800 pages, lz4'd newc cpio fragments
lz4 payloads use the legacy frame format with uncompressed blocks, so no
lz4 binary is required.
"""
import os
import struct
import subprocess
import sys

PAGE = 0x800
KVER_MATCHED = "6.1.49-android14-11-g1234567"
KVER_STALE = "6.1.49-android14-11-g7654321"
PKVM_MODS = ["dep1.ko", "exynos-pd.ko", "pkvm-s2mpu-v9.ko"]
FULL_MOD_COUNT = 160


def lz4_legacy_raw(data: bytes) -> bytes:
    """lz4 legacy-frame compression, exactly like make-bootimage.sh's
    'lz4 -l -9' (the preflight guard already requires the lz4 binary)."""
    proc = subprocess.run(["lz4", "-l", "-9", "-q", "-c"],
                          input=data, capture_output=True, check=True)
    return proc.stdout


def cpio_newc(entries) -> bytes:
    """entries: list of (name, mode, data) - data is link target for symlinks."""
    out = []
    ino = 1
    for name, mode, data in entries:
        if isinstance(data, str):
            data = data.encode()
        namelen = len(name) + 1
        fields = (ino, mode, 0, 0, 1, 0, len(data), 0, 0, 0, 0, namelen, 0)
        hdr = b"070701" + b"".join(f"{v:08x}".encode() for v in fields)
        ino += 1
        out.append(hdr)
        out.append(name.encode() + b"\0")
        pad = (-(110 + namelen)) % 4
        out.append(b"\0" * pad)
        out.append(data)
        out.append(b"\0" * (-len(data) % 4))
    out.append(b"070701" + b"00000000" * 11 + f"{11:08x}".encode() + b"00000000")
    out.append(b"TRAILER!\0")
    out.append(b"\0" * (-(110 + 11) % 4))
    return b"".join(out)


def android_image(kernel: bytes, ramdisk: bytes) -> bytes:
    hdr = bytearray(4096)
    hdr[0:8] = b"ANDROID!"
    struct.pack_into("<I", hdr, 0x08, len(kernel))
    struct.pack_into("<I", hdr, 0x0C, len(ramdisk))
    return bytes(hdr) + kernel + ramdisk


def vndrboot_image(fragments) -> bytes:
    """fragments: list of (type, name, lz4_cpio_bytes).

    Layout per preflight-boot-images.sh's parser: dtb region of vrs bytes
    after datastart, then the fragment table, then the fragment blobs
    (referenced by offset from datastart).
    """
    hdr = bytearray(PAGE)
    hdr[0:8] = b"VNDRBOOT"
    data_start = PAGE * 2
    table_off = data_start + PAGE  # dtb region: one page (dtbsz = 0)
    entry_len = 48
    frag_base = table_off + entry_len * len(fragments)
    blob = bytearray(hdr)
    if len(blob) < frag_base:
        blob.extend(b"\0" * (frag_base - len(blob)))
    table = bytearray()
    for ty, name, frag in fragments:
        entry = struct.pack("<III", len(frag), len(blob) - data_start, ty)
        entry += name.encode()[:31].ljust(32, b"\0")
        table.extend(entry)
        blob.extend(frag)
        blob.extend(b"\0" * (-len(frag) % PAGE))
    struct.pack_into("<I", blob, 0x18, PAGE)          # vrs
    struct.pack_into("<I", blob, 0x830, data_start)   # hdr offset -> datastart
    struct.pack_into("<I", blob, 0x834, 0)            # dtbsz
    struct.pack_into("<I", blob, 0x844, len(fragments))  # table entries
    struct.pack_into("<I", blob, 0x848, entry_len)
    blob[table_off:table_off + len(table)] = table
    return bytes(blob)


def init_boot_ramdisk() -> bytes:
    entries = [
        ("scripts", 0o40755, b""),
        ("scripts/halium", 0o100755, b"#!/bin/sh\n# halium init\n"),
        ("lib", 0o40755, b""),
        ("lib/modules", 0o40755, b""),
    ]
    for mod in PKVM_MODS:
        entries.append((f"lib/modules/{mod}", 0o100644, b"\x7fELF fake module\n"))
    entries.append(("lib/modules/modules.dep", 0o100644,
                    "exynos-pd.ko: dep1.ko\npkvm-s2mpu-v9.ko: exynos-pd.ko\n"))
    entries.append(("system", 0o40755, b""))
    entries.append(("system/bin", 0o40755, b""))
    entries.append(("system/bin/modprobe", 0o120777, "/bin/kmod"))
    return lz4_legacy_raw(cpio_newc(entries))


def full_modules_cpio(kver: str) -> bytes:
    entries = [
        ("lib", 0o40755, b""),
        ("lib/modules", 0o40755, b""),
        (f"lib/modules/{kver}", 0o40755, b""),
    ]
    load = []
    for i in range(FULL_MOD_COUNT):
        name = f"samsung-modules/mod{i}.ko"
        if i == 0:
            name = "samsung-modules/ufs_husky.ko"
        entries.append((f"lib/modules/{kver}/{name}", 0o100644, b"\x7fELF\n"))
        load.append(name)
    entries.append((f"lib/modules/{kver}/modules.load", 0o100644,
                    "\n".join(load) + "\n"))
    return lz4_legacy_raw(cpio_newc(entries))


def main() -> int:
    out_dir, variant = sys.argv[1], sys.argv[2]
    os.makedirs(out_dir, exist_ok=True)
    vkb_kver = KVER_STALE if variant == "stale-kver" else KVER_MATCHED

    kernel_plain = (b"\0" * 64
                    + f"Linux version {KVER_MATCHED} (builder@host) #1 SMP\n".encode()
                    + b"\0" * 4096)
    with open(os.path.join(out_dir, "boot.img"), "wb") as f:
        f.write(android_image(lz4_legacy_raw(kernel_plain), b""))
    with open(os.path.join(out_dir, "init_boot.img"), "wb") as f:
        f.write(android_image(b"", init_boot_ramdisk()))
    with open(os.path.join(out_dir, "vendor_kernel_boot.img"), "wb") as f:
        f.write(vndrboot_image([(1, "ramdisk", full_modules_cpio(vkb_kver))]))
    # vendor_boot: placeholder fragment without any module tree
    placeholder = lz4_legacy_raw(cpio_newc(
        [("first_stage_ramdisk", 0o40755, b""),
         ("fstab.zuma", 0o100644, b"# placeholder\n")]))
    with open(os.path.join(out_dir, "vendor_boot.img"), "wb") as f:
        f.write(vndrboot_image([(0, "boot", placeholder)]))
    print(f"built {variant} set in {out_dir} (boot kver={KVER_MATCHED}, "
          f"vendor_kernel_boot kver={vkb_kver})")
    return 0


if __name__ == "__main__":
    sys.exit(main())
