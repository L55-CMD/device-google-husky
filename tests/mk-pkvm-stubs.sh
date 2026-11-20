# Helper for the make-pkvm-ramdisk-segment.sh unit tests: writes stub
# `debugfs` / `cpio` / `python3` executables that serve a fixture directory
# instead of a real vendor_dlkm.flatten.img, so the script's parsing and
# failure handling can be tested without e2fsprogs or a real image.
#
# Usage: mk_pkvm_stubs <bin-dir> <fixture-dir>
# Fixture layout:
#   ls.txt           output of `debugfs -R "ls -p /lib/modules"` (parsable
#                    format: /<ino>/<mode>/<uid>/<gid>/<name>/ + size/ or /)
#   modules.dep      content served for `cat .../modules.dep`
#   modules.builtin  content served for `cat .../modules.builtin`
#   mods/<name>.ko   files served for `dump .../<name>.ko <dst>`
# Environment read by the stubs:
#   STUB_DEBUGFS_LOG   if set, every debugfs -R command is appended to it
#   STUB_CPIO_CAPTURE  if set, the file list cpio is asked to archive is
#                      written there (the archive itself goes to stdout)
#   STUB_PYTHON3_FAIL  if set, the stub python3 prints one module line then
#                      exits 1 (simulates a resolver crash mid-output)
#   STUB_PYTHON3_REAL  real python3 to exec when STUB_PYTHON3_FAIL is unset
mk_pkvm_stubs() {
    local bin_dir="$1" fixture_dir="$2"
    mkdir -p "${bin_dir}"

    cat > "${bin_dir}/debugfs" <<'EOF'
#!/usr/bin/env bash
# stub debugfs serving fixtures; usage: debugfs -R <cmd> <img>
cmd=""
prev=""
for arg in "$@"; do
    if [ "${prev}" = "-R" ]; then
        cmd="${arg}"
        break
    fi
    prev="${arg}"
done
fix="${STUB_DEBUGFS_FIXTURE:?STUB_DEBUGFS_FIXTURE not set}"
[ -n "${STUB_DEBUGFS_LOG:-}" ] && printf '%s\n' "${cmd}" >> "${STUB_DEBUGFS_LOG}"
case "${cmd}" in
    "ls -p /lib/modules")
        cat "${fix}/ls.txt"
        ;;
    cat\ /lib/modules/*|cat\ /lib/modules)
        name="$(basename "${cmd}")"
        cat "${fix}/${name}"
        ;;
    dump\ *)
        # dump <src> <dst>
        src="$(printf '%s' "${cmd}" | awk '{print $2}')"
        dst="$(printf '%s' "${cmd}" | awk '{print $3}')"
        mod="$(basename "${src}")"
        if [ -f "${fix}/mods/${mod}" ]; then
            cp "${fix}/mods/${mod}" "${dst}"
        else
            echo "dump: ${src}: No such file or directory" >&2
            exit 1
        fi
        ;;
    *)
        echo "stub debugfs: unhandled command: ${cmd}" >&2
        exit 1
        ;;
esac
EOF

    cat > "${bin_dir}/cpio" <<'EOF'
#!/usr/bin/env bash
# stub cpio: archive nothing, but record the file list it was given
cat > "${STUB_CPIO_CAPTURE:-/dev/null}"
EOF

    cat > "${bin_dir}/python3" <<'EOF'
#!/usr/bin/env bash
# The resolver call passes exactly 2 file args (dep_file, builtin_file);
# the modules.dep writer passes 3+. Only the resolver is made to fail.
if [ -n "${STUB_PYTHON3_FAIL:-}" ] && [ "$#" -le 3 ]; then
    echo "exynos-pd.ko"
    echo "synthetic resolver crash mid-output" >&2
    exit 1
fi
exec "${STUB_PYTHON3_REAL:?STUB_PYTHON3_REAL not set}" "$@"
EOF

    # Windows hosts without symlink privileges cannot `ln -s` at all; the
    # real build runs in Linux Docker. Shadow ln with a stub that leaves a
    # regular-file placeholder (find -type f still picks it up).
    cat > "${bin_dir}/ln" <<'EOF'
#!/usr/bin/env bash
[ -n "${STUB_LN_LOG:-}" ] && printf '%s\n' "$*" >> "${STUB_LN_LOG}"
for last; do :; done
touch "${last}"
EOF

    chmod +x "${bin_dir}/debugfs" "${bin_dir}/cpio" "${bin_dir}/python3" "${bin_dir}/ln"
    export STUB_DEBUGFS_FIXTURE="${fixture_dir}"
}
