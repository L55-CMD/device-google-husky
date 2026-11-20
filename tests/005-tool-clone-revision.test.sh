#!/usr/bin/env bash
# Tests for git_clone_if_missing (scripts/git-clone-lib.sh), used by
# prepare-device-tarball.sh for the pinned tool clones (avb, mkbootimg,
# halium_bootable_recovery).
#
# Negative focus: a REUSED local clone must match the requested branch -
# a stale or wrong-branch checkout must fail loudly instead of silently
# baking the wrong tool revision into the images.
set -euo pipefail

repo_root="$(realpath "$(dirname "$0")/..")"
# shellcheck source=scripts/git-clone-lib.sh
source "${repo_root}/scripts/git-clone-lib.sh"

command -v git >/dev/null 2>&1 || { echo "git missing"; exit 77; }

work="$(mktemp -d)"
trap 'rm -rf "${work}"' EXIT

# Two fixture remotes: one with the wanted branch, one without.
make_remote() {
    local path="$1" branch="$2"
    mkdir -p "${path}"
    (
        cd "${path}"
        git init -q
        git checkout -q -b "${branch}"
        printf 'tool fixture on %s\n' "${branch}" > tool.txt
        git add tool.txt
        git -c user.name=test -c user.email=test@example.com commit -qm "fixture"
    )
}

make_remote "${work}/remote-wanted" "lineage-20.0"
make_remote "${work}/remote-other" "master"

# --- case 1: fresh clone (positive) -----------------------------------------
git_clone_if_missing "${work}/remote-wanted" "lineage-20.0" "${work}/clone1"
[ -f "${work}/clone1/tool.txt" ] || { echo "fresh clone missing content"; exit 1; }
echo "fresh clone: OK"

# --- case 2: reuse of a matching clone (positive) ---------------------------
out="$(git_clone_if_missing "${work}/remote-wanted" "lineage-20.0" "${work}/clone1")"
grep -q "Reusing existing clone" <<< "${out}" \
    || { echo "expected reuse message, got: ${out}"; exit 1; }
echo "matching reuse: OK (${out})"

# --- case 3 (negative): cloning a repo without the wanted branch fails ---
if git_clone_if_missing "${work}/remote-other" "lineage-20.0" "${work}/clone3" 2> "${work}/c3.err"; then
    echo "unexpected: cloned a repo that does not carry the wanted branch"
    exit 1
fi
grep -qi "lineage-20.0" "${work}/c3.err" \
    || { echo "expected branch name in clone failure diagnostic:"; cat "${work}/c3.err"; exit 1; }
echo "missing-branch clone: failed as expected"
# Now create the wrong-branch situation directly: clone the master repo...
git clone -q "${work}/remote-other" "${work}/clone4"
# ...and ask for it as if it were the pinned lineage-20.0 checkout.
if git_clone_if_missing "${work}/remote-wanted" "lineage-20.0" "${work}/clone4" > "${work}/c4.log" 2>&1; then
    echo "stale wrong-branch clone was silently reused"
    exit 1
fi
grep -q "expected branch 'lineage-20.0'" "${work}/c4.log" \
    || { echo "expected revision-mismatch diagnostic, got:"; cat "${work}/c4.log"; exit 1; }
echo "wrong-branch reuse: failed as expected"

# --- case 4 (negative): corrupt .git without a valid HEAD must fail ---------
mkdir -p "${work}/clone5/.git"
if git_clone_if_missing "${work}/remote-wanted" "lineage-20.0" "${work}/clone5" > "${work}/c5.log" 2>&1; then
    echo "corrupt clone was silently reused"
    exit 1
fi
grep -q "no valid HEAD" "${work}/c5.log" \
    || { echo "expected invalid-HEAD diagnostic, got:"; cat "${work}/c5.log"; exit 1; }
echo "corrupt clone: failed as expected"

echo "PASS"
