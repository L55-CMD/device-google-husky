#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd -P)"
cd "${repo_root}"

status=0
fail() {
    echo "ERROR: $*" >&2
    status=1
}

for tree in overlay overlay-debug; do
    [ -d "${tree}" ] || continue
    while IFS= read -r wants_dir; do
        while IFS= read -r entry; do
            [ -f "${entry}" ] || continue
            target="$(cat "${entry}")"
            if [[ -z "${target}" || "${target}" == *$'\n'* || "${target}" == '[Unit]'* ]]; then
                fail "Invalid systemd wants target in ${entry}"
                continue
            fi
            case "${target}" in
                /*) ;;
                ../*)
                    [ -e "$(dirname "${entry}")/${target}" ] || fail "Broken relative wants target ${target} in ${entry}"
                    ;;
                *)
                    fail "Wants target must be absolute or relative in ${entry}"
                    ;;
            esac
        done < <(find "${wants_dir}" -maxdepth 1 -type f -print)
    done < <(find "${tree}" -type d -name '*.wants' -print)
done

for link in \
    overlay/system/usr/lib/aarch64-linux-gnu/libgbinder.so.1 \
    overlay/system/usr/lib/aarch64-linux-gnu/libgbinder.so.1.1 \
    overlay/system/usr/lib/aarch64-linux-gnu/libgbinder-radio.so.1 \
    overlay/system/usr/lib/aarch64-linux-gnu/libgbinder-radio.so.1.6; do
    [ -f "${link}" ] || fail "Missing library link payload ${link}"
done

while read -r mode _ path; do
    case "${path}" in
        overlay/system/usr/libexec/lxc-android-config/*|overlay/system/usr/share/ubuntu-touch-session/lsc-wrapper|overlay/system/usr/share/halium-overlay/vendor/bin/vndservicemanager|overlay/system/usr/sbin/usbdp_gbinder|scripts/*.sh|build.sh)
            if [ "${mode}" != "100755" ]; then
                fail "${path} has mode ${mode}, expected 100755"
            fi
            ;;
    esac
done < <(git ls-files -s)

if [ "${status}" -ne 0 ]; then
    exit 1
fi

echo "Overlay validation passed."
