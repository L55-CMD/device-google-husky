#!/usr/bin/env bash
# Tests for the existing flash guards in husky-verify (OUTSIDE this repo):
#   preflight-boot-images.sh  - matched-kver gate (boot.img kver must have
#                               its module tree in vendor_kernel_boot.img,
#                               init_boot pkvm closure flat and complete)
#   verify-integration.sh     - full-image offline acceptance (used by the
#                               flash-*-full.sh guards before dd'ing)
#
# These guards are the device-side backstop for everything the build
# scripts produce; the build hardening on this branch must not regress
# what they check. Synthetic image sets (tests/mk-image-fixture.py) stand
# in for CI artifacts so both the PASS and the stale-kver FAIL path are
# exercised without a phone or a kernel build.
#
# Skips (77) when husky-verify is not checked out next to this repo.
set -euo pipefail

repo_root="$(realpath "$(dirname "$0")/..")"
verify_dir="$(realpath "${repo_root}/../husky-verify")"
preflight="${verify_dir}/preflight-boot-images.sh"

if [ ! -f "${preflight}" ]; then
    echo "SKIP: ${preflight} not found (flash guards live outside this repo)"
    exit 77
fi
command -v python3 >/dev/null 2>&1 || { echo "python3 missing"; exit 77; }
command -v lz4 >/dev/null 2>&1 || { echo "lz4 missing"; exit 77; }

work="$(mktemp -d)"
trap 'rm -rf "${work}"' EXIT

# --- case 1 (positive): synthetic matched set must PASS ---------------------
python3 "${repo_root}/tests/mk-image-fixture.py" "${work}/matched" matched
if ! bash "${preflight}" "${work}/matched" > "${work}/matched.log" 2>&1; then
    echo "preflight FAILED a matched set (guard regression or fixture drift):"
    cat "${work}/matched.log"
    exit 1
fi
grep -q "PREFLIGHT PASSED" "${work}/matched.log" \
    || { echo "expected PREFLIGHT PASSED; got:"; cat "${work}/matched.log"; exit 1; }
echo "matched set: preflight PASSED"

# --- case 2 (negative): stale module kver must FAIL -------------------------
# vendor_kernel_boot carries a DIFFERENT <kver> tree than the boot.img
# kernel - the run-98 partial-flash failure mode.
python3 "${repo_root}/tests/mk-image-fixture.py" "${work}/stale" stale-kver
if bash "${preflight}" "${work}/stale" > "${work}/stale.log" 2>&1; then
    echo "preflight PASSED a stale-kver set - the guard is broken:"
    cat "${work}/stale.log"
    exit 1
fi
grep -q "PREFLIGHT FAILED" "${work}/stale.log" \
    || { echo "expected PREFLIGHT FAILED; got:"; cat "${work}/stale.log"; exit 1; }
echo "stale-kver set: preflight FAILED as expected"

# --- case 3: the full-image acceptance guard, if its reference inputs exist --
# verify-integration.sh needs a kernel.zip (IKCONFIG reference check);
# without one it is expected to fail - assert exactly that, which pins the
# guard's reject behaviour for incomplete inputs.
if [ -f "${verify_dir}/verify-integration.sh" ]; then
    if bash "${verify_dir}/verify-integration.sh" "${work}/matched" \
            > "${work}/vi.log" 2>&1; then
        echo "verify-integration accepted a dir without kernel.zip (guard regression):"
        cat "${work}/vi.log"
        exit 1
    fi
    grep -q "kernel.zip missing" "${work}/vi.log" \
        || { echo "unexpected verify-integration diagnostic; got:"; cat "${work}/vi.log"; exit 1; }
    echo "verify-integration: rejects missing kernel.zip as expected"
fi

# --- informational: run the guard against real local sets, if present -------
for real in "${repo_root}/../husky-flash/tar-audio-lto" \
            "${repo_root}/../husky-flash/ltonone-ci"; do
    if [ -f "${real}/boot.img" ] && [ -f "${real}/vendor_kernel_boot.img" ]; then
        if bash "${preflight}" "${real}" > "${work}/real.log" 2>&1; then
            echo "real set $(basename "${real}"): preflight PASSED"
        else
            echo "real set $(basename "${real}"): preflight FAILED:"
            cat "${work}/real.log"
            exit 1
        fi
    fi
done

echo "PASS"
