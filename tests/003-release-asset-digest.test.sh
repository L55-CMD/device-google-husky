#!/usr/bin/env bash
# Tests for scripts/resolve-release-asset-digest.py, used by
# prepare-device-tarball.sh to re-resolve the kernel.zip digest when a
# rolling release was re-uploaded mid-build.
#
# Negative focus: the digest must be selected by ASSET NAME. The old
# positional grep (first "digest" in the release JSON) would pin whatever
# asset happens to be listed first.
set -euo pipefail

repo_root="$(realpath "$(dirname "$0")/..")"
resolver="${repo_root}/scripts/resolve-release-asset-digest.py"

command -v python3 >/dev/null 2>&1 || { echo "python3 missing"; exit 77; }

work="$(mktemp -d)"
trap 'rm -rf "${work}"' EXIT

K_DIGEST="1111111111111111111111111111111111111111111111111111111111111111"
O_DIGEST="2222222222222222222222222222222222222222222222222222222222222222"

# --- case 1: another asset is listed FIRST; kernel.zip digest must win ----
cat > "${work}/release.json" <<EOF
{
  "tag_name": "test-audio-restore",
  "assets": [
    {"name": "build-final.log", "digest": "sha256:${O_DIGEST}"},
    {"name": "kernel.zip", "digest": "sha256:${K_DIGEST}"}
  ]
}
EOF
got="$(python3 "${resolver}" "${work}/release.json" kernel.zip)"
[ "${got}" = "${K_DIGEST}" ] || {
    echo "wrong digest selected with kernel.zip second: got ${got}, want ${K_DIGEST}"
    exit 1
}
echo "asset-name selection: kernel.zip digest picked despite ordering"

# --- case 2: kernel.zip listed first, other digest second (control) -------
got="$(python3 "${resolver}" "${work}/release.json" build-final.log)"
[ "${got}" = "${O_DIGEST}" ] || { echo "control case failed: ${got}"; exit 1; }
echo "control: other asset digest picked by name"

# --- case 3 (negative): kernel.zip missing from the release ---------------
cat > "${work}/no-kernel.json" <<EOF
{"tag_name": "x", "assets": [{"name": "build-final.log", "digest": "sha256:${O_DIGEST}"}]}
EOF
if python3 "${resolver}" "${work}/no-kernel.json" kernel.zip > "${work}/c3.log" 2>&1; then
    echo "resolver succeeded although kernel.zip is absent"
    exit 1
fi
grep -q "not found" "${work}/c3.log" || { echo "unexpected diagnostic:"; cat "${work}/c3.log"; exit 1; }
echo "missing kernel.zip: resolver failed as expected"

# --- case 4 (negative): kernel.zip has no usable digest -------------------
cat > "${work}/no-digest.json" <<EOF
{"tag_name": "x", "assets": [{"name": "kernel.zip"}]}
EOF
if python3 "${resolver}" "${work}/no-digest.json" kernel.zip > "${work}/c4.log" 2>&1; then
    echo "resolver succeeded although kernel.zip has no digest"
    exit 1
fi
grep -q "no usable sha256 digest" "${work}/c4.log" || { echo "unexpected diagnostic:"; cat "${work}/c4.log"; exit 1; }
echo "digest-less kernel.zip: resolver failed as expected"

echo "PASS"
