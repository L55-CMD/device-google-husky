#!/usr/bin/env bash
set -euo pipefail

workspace_dir="${WORKSPACE_DIR:-$(pwd)}"

git config --global user.name "${GIT_USER_NAME:-Forgejo CI}"
git config --global user.email "${GIT_USER_EMAIL:-ci@git.deusch.me}"
git config --global --add safe.directory "${workspace_dir}"

"${workspace_dir}/scripts/assemble-final-image.sh"
