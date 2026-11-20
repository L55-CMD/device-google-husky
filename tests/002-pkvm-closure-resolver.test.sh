#!/usr/bin/env bash
# Tests for make-pkvm-ramdisk-segment.sh dependency-resolver failure
# handling. The resolver (embedded python) must abort the build when it
# exits non-zero - even after printing partial output - instead of
# silently shipping a truncated module set to the device (a partial
# closure means pKVM cannot finalize and the MFC NULL-IOMMU panic from
# BRINGUP-LOG comes back).
#
# Uses a stub debugfs/cpio serving a fixture (see mk-pkvm-stubs.sh), so no
# real vendor_dlkm.flatten.img or e2fsprogs is needed.
set -euo pipefail

repo_root="$(realpath "$(dirname "$0")/..")"
# shellcheck source=tests/mk-pkvm-stubs.sh
source "${repo_root}/tests/mk-pkvm-stubs.sh"

command -v python3 >/dev/null 2>&1 || { echo "python3 missing"; exit 77; }

work="$(mktemp -d)"
trap 'rm -rf "${work}"' EXIT

real_python3="$(command -v python3)"
export STUB_PYTHON3_REAL="${real_python3}"

# --- fixture: flat layout, resolvable 3-module closure ----------------------
fix="${work}/fixture"
mkdir -p "${fix}/mods"
cat > "${fix}/ls.txt" <<'EOF'
/2/040755/0/0/.//
/2/040755/0/0/..//
/18/0100644/0/0/modules.dep/76/
/19/0100644/0/0/modules.builtin/0/
/20/0100644/0/0/dep1.ko/100/
/21/0100644/0/0/exynos-pd.ko/200/
/22/0100644/0/0/pkvm-s2mpu-v9.ko/300/
EOF
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

kernel_dir="${work}/kernel"
mkdir -p "${kernel_dir}"
: > "${kernel_dir}/vendor_dlkm.flatten.img"

run_segment() {
    local stub_dir="$1" log="$2" out="$3"
    PATH="${stub_dir}:${PATH}" \
        STUB_DEBUGFS_LOG="${log}" \
        STUB_CPIO_CAPTURE="${out}.listing" \
        bash "${repo_root}/scripts/make-pkvm-ramdisk-segment.sh" \
        "${kernel_dir}" "${out}"
}

# --- case 1 (positive): resolvable closure stages all modules ---------------
bin1="${work}/bin1"
mk_pkvm_stubs "${bin1}" "${fix}"
run_segment "${bin1}" "${work}/dfs1.log" "${work}/seg1.cpio"
for mod in dep1.ko exynos-pd.ko pkvm-s2mpu-v9.ko; do
    grep -qx "lib/modules/${mod}" "${work}/seg1.cpio.listing" \
        || { echo "expected ${mod} in staged cpio listing:"; cat "${work}/seg1.cpio.listing"; exit 1; }
done
grep -qx 'lib/modules/modules.dep' "${work}/seg1.cpio.listing" \
    || { echo "modules.dep missing from staged cpio listing"; exit 1; }
echo "resolvable closure: all 3 modules staged"

# --- case 2 (negative): unresolvable dependency must fail the build ---------
fix2="${work}/fixture2"
cp -r "${fix}" "${fix2}"
cat > "${fix2}/tree/lib/modules/modules.dep" <<'EOF'
exynos-pd.ko: not-shipped-anywhere.ko
pkvm-s2mpu-v9.ko: exynos-pd.ko
EOF
bin2="${work}/bin2"
mk_pkvm_stubs "${bin2}" "${fix2}"
if run_segment "${bin2}" "${work}/dfs2.log" "${work}/seg2.cpio" > "${work}/case2.log" 2>&1; then
    echo "build succeeded despite unresolvable module dependency"
    exit 1
fi
grep -q 'unresolvable module deps' "${work}/case2.log" \
    || { echo "expected resolver diagnostics; got:"; cat "${work}/case2.log"; exit 1; }
[ -e "${work}/seg2.cpio" ] && { echo "cpio produced despite resolver failure"; exit 1; }
echo "unresolvable dependency: build failed as expected"

# --- case 3 (negative): resolver crash mid-output must fail the build -------
# The stub python3 prints one module line, then exits 1. The old process-
# substitution capture (mapfile < <(python3 ...)) swallowed exactly this:
# mapfile succeeded on the partial line and the build continued with a
# 1-module closure.
bin3="${work}/bin3"
mk_pkvm_stubs "${bin3}" "${fix}"
if PATH="${bin3}:${PATH}" \
    STUB_DEBUGFS_LOG="${work}/dfs3.log" \
    STUB_CPIO_CAPTURE="${work}/seg3.listing" \
    STUB_PYTHON3_FAIL=1 \
    bash "${repo_root}/scripts/make-pkvm-ramdisk-segment.sh" \
    "${kernel_dir}" "${work}/seg3.cpio" > "${work}/case3.log" 2>&1; then
    echo "build succeeded despite resolver crash mid-output (partial closure accepted)"
    exit 1
fi
grep -q 'resolver failed' "${work}/case3.log" \
    || { echo "expected resolver-failure message; got:"; cat "${work}/case3.log"; exit 1; }
[ -e "${work}/seg3.cpio" ] && { echo "cpio produced despite resolver crash"; exit 1; }
echo "resolver crash mid-output: build failed as expected"

echo "PASS"
