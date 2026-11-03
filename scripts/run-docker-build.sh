#!/usr/bin/env bash
set -euo pipefail

workspace_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
image_tag="${IMAGE_TAG:-husky-final-builder:local}"
skip_docker_build="${SKIP_DOCKER_BUILD:-0}"

if [ "${skip_docker_build}" != "1" ]; then
    docker build -t "${image_tag}" -f "${workspace_dir}/Dockerfile" "${workspace_dir}"
fi

docker_volumes=(-v "${workspace_dir}:${workspace_dir}")
if [ -n "${JOB_CONTAINER_NAME:-}" ]; then
  docker_volumes=(--volumes-from "${JOB_CONTAINER_NAME}")
fi

docker run --rm --privileged \
    -e WORKSPACE_DIR="$(pwd)" \
    -e BUILD_TOOLS_BRANCH="${BUILD_TOOLS_BRANCH:-unified-recovery}" \
    -e BUILD_TOOLS_REPO="${BUILD_TOOLS_REPO:-https://gitlab.com/ubports/porting/community-ports/halium-generic-adaptation-build-tools.git}" \
    -e PACKAGE_REGISTRY_BASE="${PACKAGE_REGISTRY_BASE:-}" \
    -e PACKAGE_BRANCH="${PACKAGE_BRANCH:-}" \
    "${docker_volumes[@]}" \
    -w "$(pwd)" \
    "${image_tag}" \
    ./scripts/run-in-container.sh
