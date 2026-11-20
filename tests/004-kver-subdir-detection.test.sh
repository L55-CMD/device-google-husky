#!/usr/bin/env bash
# Tests for the kernel-version (<kver>) subdirectory detection in
# make-pkvm-ramdisk-segment.sh.
#
# The flatten image has been seen flat (modules directly in
# /lib/modules) and nested (single <kver>/ subdir). Detection must:
#   - use the flat dir when there is no subdir;
#   - use exactly one <kver> subdir when present (the old 'NF == 7' awk
#     parse never matched real debugfs output, so this path was dead);
#   - FAIL on an ambiguous image with several <kver> candidates instead
#     of silently picking one in debugfs directory order.
set -euo pipefail

repo_root="$(realpath "$(dirname "$0")/..")"
# shellcheck source=tests/mk-pkvm-stubs.sh
source "${repo_root}/tests/mk-pkvm-stubs.sh"

command -v python3 >/dev/null 2>&1 || { echo "python3 missing"; exit 77; }

work="$(mktemp -d)"
trap 'rm -rf "${work}"' EXIT
export STUB_PYTHON3_REAL="$(command -v python3)"

KVER="6.1.49-android14-11-gdeadbeef"
KVER2="6.1.49-android14-11-gcafebabe"

make_fixture() {
    local fix="$1" ls_content="$2"
    mkdir -p "${fix}/mods"
    printf '%s\n' "${ls_content}" > "${fix}/ls.txt"
    cat > "${fix}/modules.dep" <<'EOF'
dep1.ko:
exynos-pd.ko: dep1.ko
pkvm-s2mpu-v9.ko: exynos-pd.ko
EOF
    mkdir -p "${fix}/tree/lib/modules"
    mv "${fix}/modules.dep" "${fix}/tree/lib/modules/modules.dep"
    : > "${fix}/tree/lib/modules/modules.builtin"
    for m in dep1 exynos-pd pkvm-s2mpu-v9; do
        printf 'fake module %s\n' "${m}" > "${fix}/mods/${m}.ko"
    done
}

kernel_dir="${work}/kernel"
mkdir -p "${kernel_dir}"
: > "${kernel_dir}/vendor_dlkm.flatten.img"

run_segment() {
    local fix="$1" tag="$2"
    local bin="${work}/bin-${tag}" log="${work}/dfs-${tag}.log"
    mk_pkvm_stubs "${bin}" "${fix}"
    PATH="${bin}:${PATH}" \
        STUB_DEBUGFS_LOG="${log}" \
        STUB_CPIO_CAPTURE="${work}/seg-${tag}.listing" \
        bash "${repo_root}/scripts/make-pkvm-ramdisk-segment.sh" \
        "${kernel_dir}" "${work}/seg-${tag}.cpio" > /dev/null
    printf '%s' "${log}"
}

FLAT_LS='/2/040755/0/0/.//
/2/040755/0/0/..//
/18/0100644/0/0/modules.dep/76/
/19/0100644/0/0/modules.builtin/0/
/20/0100644/0/0/dep1.ko/100/
/21/0100644/0/0/exynos-pd.ko/200/
/22/0100644/0/0/pkvm-s2mpu-v9.ko/300/'

SUB_LS="/2/040755/0/0/.//
/2/040755/0/0/..//
/10/040755/0/0/${KVER}//
/18/0100644/0/0/modules.dep/76/"

# --- case 1: flat layout (current kernel.zip shape) -------------------------
fix1="${work}/fix1"; make_fixture "${fix1}" "${FLAT_LS}"
log1="$(run_segment "${fix1}" flat)"
grep -qx "cat /lib/modules/modules.dep" "${log1}" \
    || { echo "flat layout: expected 'cat /lib/modules/modules.dep', debugfs log:"; cat "${log1}"; exit 1; }
echo "flat layout: modules read from /lib/modules"

# --- case 2: single <kver> subdir ------------------------------------------
fix2="${work}/fix2"; make_fixture "${fix2}" "${SUB_LS}"
mkdir -p "${fix2}/tree/lib/modules/${KVER}"
mv "${fix2}/tree/lib/modules/modules.dep" "${fix2}/tree/lib/modules/modules.builtin" \
    "${fix2}/tree/lib/modules/${KVER}/"
log2="$(run_segment "${fix2}" sub)"
grep -qx "cat /lib/modules/${KVER}/modules.dep" "${log2}" \
    || { echo "kver layout: expected 'cat /lib/modules/${KVER}/modules.dep', debugfs log:"; cat "${log2}"; exit 1; }
grep -qx "lib/modules/exynos-pd.ko" "${work}/seg-sub.listing" \
    || { echo "kver layout: module not staged"; cat "${work}/seg-sub.listing"; exit 1; }
echo "kver layout: modules read from /lib/modules/<kver> and staged flat"

# --- case 3 (negative): two <kver> candidates must fail ---------------------
fix3="${work}/fix3"; make_fixture "${fix3}" "/2/040755/0/0/.//
/2/040755/0/0/..//
/10/040755/0/0/${KVER}//
/11/040755/0/0/${KVER2}//"
bin3="${work}/bin-ambig"
mk_pkvm_stubs "${bin3}" "${fix3}"
if PATH="${bin3}:${PATH}" \
    STUB_CPIO_CAPTURE="${work}/seg-ambig.listing" \
    bash "${repo_root}/scripts/make-pkvm-ramdisk-segment.sh" \
    "${kernel_dir}" "${work}/seg-ambig.cpio" > "${work}/ambig.log" 2>&1; then
    echo "ambiguous <kver> candidates were silently accepted"
    exit 1
fi
grep -q "ambiguous module dirs" "${work}/ambig.log" \
    || { echo "expected ambiguity diagnostic; got:"; cat "${work}/ambig.log"; exit 1; }
grep -q "${KVER}" "${work}/ambig.log" && grep -q "${KVER2}" "${work}/ambig.log" \
    || { echo "ambiguity diagnostic must list all candidates:"; cat "${work}/ambig.log"; exit 1; }
[ -e "${work}/seg-ambig.cpio" ] && { echo "cpio produced despite ambiguous layout"; exit 1; }
echo "ambiguous layout: build failed as expected, candidates listed"

echo "PASS"
