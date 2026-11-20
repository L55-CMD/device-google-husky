# Shared helpers for the build scripts. Sourced, not executed.
#
# shellcheck shell=bash

# git_clone_if_missing <url> <branch> <target>
#
# Clone <url> at <branch> into <target> unless <target> is already a clone.
# A REUSED clone must match the requested revision: tool checkouts are
# pinned by branch, and a stale or wrong-branch reuse would silently bake
# the wrong tool into the device images.
git_clone_if_missing() {
    local url="$1"
    local branch="$2"
    local target="$3"

    if [ -d "${target}/.git" ]; then
        local head_branch head_sha
        head_branch="$(git -C "${target}" symbolic-ref -q --short HEAD 2>/dev/null || true)"
        head_sha="$(git -C "${target}" rev-parse -q --verify HEAD 2>/dev/null || true)"
        if [ -z "${head_sha}" ]; then
            echo "Existing clone at ${target} has no valid HEAD; remove it and re-run" >&2
            return 1
        fi
        if [ "${head_branch}" != "${branch}" ]; then
            echo "Existing clone at ${target} is on '${head_branch:-detached}', expected branch '${branch}'; remove it and re-run" >&2
            return 1
        fi
        echo "Reusing existing clone of ${url} (${branch} @ ${head_sha})"
        return 0
    fi

    git clone --depth 1 --branch "${branch}" "${url}" "${target}"
}

# require_files <file>...
#
# Every listed file must exist. A release missing ANY expected artifact
# must fail the build with the missing filename(s) - silently shipping a
# partial artifact set leads to partial-image flashes on the device.
require_files() {
    local missing=()
    local f
    for f in "$@"; do
        [ -f "${f}" ] || missing+=("${f}")
    done
    if [ "${#missing[@]}" -gt 0 ]; then
        echo "Missing expected release artifacts:" >&2
        printf '  %s\n' "${missing[@]}" >&2
        return 1
    fi
}
