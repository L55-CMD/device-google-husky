#!/usr/bin/env bash
# Run all script-level tests in this directory.
#
# Each *.test.sh must exit 0 on pass, 1 on failure, 77 to skip
# (missing optional fixture or tool). Usage: tests/run-tests.sh [test ...]
set -u

tests_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"

if [ "$#" -gt 0 ]; then
    tests=("$@")
else
    tests=()
    while IFS= read -r t; do
        tests+=("${t}")
    done < <(find "${tests_dir}" -maxdepth 1 -type f -name '*.test.sh' | LC_ALL=C sort)
fi

pass=0 fail=0 skip=0
failed_tests=()
for t in "${tests[@]}"; do
    name="$(basename "${t}")"
    if bash "${t}" > /tmp/husky-test.$$.log 2>&1; then
        echo "PASS ${name}"
        pass=$((pass + 1))
    else
        rc=$?
        if [ "${rc}" -eq 77 ]; then
            echo "SKIP ${name} ($(tail -n 1 /tmp/husky-test.$$.log))"
            skip=$((skip + 1))
        else
            echo "FAIL ${name} (rc=${rc})"
            sed 's/^/     /' /tmp/husky-test.$$.log
            failed_tests+=("${name}")
            fail=$((fail + 1))
        fi
    fi
done
rm -f /tmp/husky-test.$$.log

echo
echo "tests: ${pass} passed, ${fail} failed, ${skip} skipped"
[ "${fail}" -eq 0 ]
