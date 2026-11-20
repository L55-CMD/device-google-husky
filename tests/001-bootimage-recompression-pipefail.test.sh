#!/usr/bin/env bash
# Negative test: the build-tools make-bootimage.sh boot-image recompression
# pipeline (`gzip -dc "$RAMDISK" | $COMPRESSION_CMD`, reached for
# deviceinfo_ramdisk_compression="lz4") must fail when gzip fails instead of
# silently dropping data (verified on device 2026-11-17: gzip exits 2 with
# "trailing garbage ignored", masked by the pipe, and the whole pkvm module
# segment vanished from init_boot.img).
#
# Fetches the pinned build-tools revision (dependencies.lock), applies
# build-patches (incl. 0003 pipefail), and runs the real script against a
# port-tree fixture with a corrupt gzip ramdisk. Skips (77) when the
# build-tools source cannot be fetched.
set -euo pipefail

repo_root="$(realpath "$(dirname "$0")/..")"
source "${repo_root}/dependencies.lock"

command -v curl >/dev/null 2>&1 || { echo "curl missing"; exit 77; }
command -v gzip >/dev/null 2>&1 || { echo "gzip missing"; exit 77; }
command -v git >/dev/null 2>&1 || { echo "git missing"; exit 77; }

work="$(mktemp -d)"
trap 'rm -rf "${work}"' EXIT

fetch() {
    curl -fsSL --retry 2 --connect-timeout 15 \
        "${BUILD_TOOLS_REPO%.git}/-/archive/${BUILD_TOOLS_REVISION}/halium-generic-adaptation-build-tools-${BUILD_TOOLS_REVISION}.tar.gz" \
        -o "${work}/upstream.tar.gz"
}

if ! fetch; then
    echo "SKIP: cannot fetch build-tools at ${BUILD_TOOLS_REVISION} (offline?)"
    exit 77
fi
tar -xzf "${work}/upstream.tar.gz" -C "${work}"
upstream="${work}/halium-generic-adaptation-build-tools-${BUILD_TOOLS_REVISION}"

# Apply every build patch, exactly like scripts/apply-patches.sh does.
# Normalize CRLF checkouts (Windows autocrlf) back to LF first: git apply
# refuses CRLF context lines against LF files.
patch_dir="${work}/patches"
mkdir -p "${patch_dir}"
for p in "${repo_root}"/build-patches/halium-generic-adaptation-build-tools/*.patch; do
    tr -d '\r' < "${p}" > "${patch_dir}/$(basename "${p}")"
done
cd "${upstream}"
if ! git apply --check --whitespace=nowarn "${patch_dir}"/*.patch 2>"${work}/apply.err"; then
    echo "build patches do not apply cleanly to ${BUILD_TOOLS_REVISION}:"
    cat "${work}/apply.err"
    exit 1
fi
git apply --whitespace=nowarn "${patch_dir}"/*.patch

grep -q '^set -exo pipefail$' "${upstream}/make-bootimage.sh" \
    || { echo "patched make-bootimage.sh lacks pipefail"; exit 1; }

# Port-tree fixture: just enough deviceinfo to reach the recompression step.
port_tree="${work}/port-tree"
mkdir -p "${port_tree}" "${work}/tmpdown" "${work}/kernel_obj" "${work}/out"
cat > "${port_tree}/deviceinfo" <<'EOF'
deviceinfo_arch="aarch64"
deviceinfo_kernel_image_name="Image"
deviceinfo_ramdisk_compression="lz4"
EOF

# lz4 is only needed as a pipeline sink; a pass-through stub is enough to
# prove the pipeline propagates gzip's failure.
if command -v lz4 >/dev/null 2>&1; then
    lz4_bin="$(command -v lz4)"
else
    lz4_bin="${work}/bin/lz4"
    mkdir -p "${work}/bin"
    cat > "${lz4_bin}" <<'EOF'
#!/usr/bin/env bash
cat
EOF
    chmod +x "${lz4_bin}"
fi

make_ramdisk() {
    # $1 = target; $2 = "clean" or "garbage"
    printf 'fake cpio content\n' | gzip -9 > "$1"
    if [ "$2" = "garbage" ]; then
        printf 'trailing garbage pkvm segment bytes' >> "$1"
    fi
}

run_make_bootimage() {
    local ramdisk="$1"
    (
        cd "${port_tree}"
        PATH="$(dirname "${lz4_bin}"):${PATH}" \
            bash "${upstream}/make-bootimage.sh" \
            "${work}/tmpdown" "${work}/kernel_obj" "${ramdisk}" \
            "${work}/out/boot.img" "${work}/install_mod"
    )
}

# --- case 1: corrupt gzip (trailing garbage) must fail at recompression ----
# Note: the > redirect creates ${corrupt_rd}.lz4 even when the pipeline
# fails, so the signal is the script's exit code, not the file's absence.
corrupt_rd="${work}/tmpdown/ramdisk-corrupt.img"
make_ramdisk "${corrupt_rd}" garbage
if run_make_bootimage "${corrupt_rd}" > "${work}/corrupt.log" 2>&1; then
    echo "make-bootimage.sh succeeded on a corrupt gzip ramdisk (pipe still masks gzip failure)"
    exit 1
fi
grep -q 'trailing garbage' "${work}/corrupt.log" \
    || { echo "expected gzip trailing-garbage diagnostic; got:"; cat "${work}/corrupt.log"; exit 1; }
if [ -e "${work}/out/boot.img" ]; then
    echo "boot.img was produced despite recompression failure"
    exit 1
fi
echo "corrupt gzip ramdisk: build failed at recompression as expected (rc!=0, no boot.img)"

# --- case 2: clean gzip must get PAST recompression (positive control) -----
# Without a real mkbootimg the script must fail LATER (missing mkbootimg.py),
# and the recompressed ramdisk must exist. This proves case 1's failure
# happened at recompression, not at some unrelated later step.
clean_rd="${work}/tmpdown/ramdisk-clean.img"
make_ramdisk "${clean_rd}" clean
if run_make_bootimage "${clean_rd}" > "${work}/clean.log" 2>&1; then
    echo "unexpected: make-bootimage.sh fully succeeded without mkbootimg fixture"
    exit 1
fi
if [ ! -s "${clean_rd}.lz4" ]; then
    echo "clean gzip ramdisk did not reach/past recompression (regression?)"
    echo "--- clean.log:"; cat "${work}/clean.log"
    exit 1
fi
echo "clean gzip ramdisk: recompression completed, script failed later as expected (no mkbootimg fixture)"

echo "PASS"
