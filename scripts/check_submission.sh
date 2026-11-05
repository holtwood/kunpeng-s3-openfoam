#!/usr/bin/env bash
# Static checks before packaging. Does not compile and does not run the case.
#
# Usage:
#   ./scripts/check_submission.sh [submission-dir]

set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
sub="${1:-$root/submission/simpleFoam-submission}"

fail=0
note() { printf '%-58s %s\n' "$1" "$2"; }
check() {
    if eval "$2"; then note "$1" "OK"; else note "$1" "FAIL"; fail=1; fi
}

echo "submission: $sub"
echo

check "directory exists"                 "[ -d '$sub' ]"
check "simpleFoam.C exists"              "[ -f '$sub/simpleFoam.C' ]"
check "UEqn.H exists"                    "[ -f '$sub/UEqn.H' ]"
check "pEqn.H exists"                    "[ -f '$sub/pEqn.H' ]"
check "createFields.H exists"            "[ -f '$sub/createFields.H' ]"
check "Make/files exists"                "[ -f '$sub/Make/files' ]"
check "Make/options exists"              "[ -f '$sub/Make/options' ]"
check "matrices/ exists"                 "[ -d '$sub/matrices' ]"

# No build artefacts or binaries anywhere.
forbidden="$(find "$sub" -type f \( \
    -name '*.so' -o -name '*.so.*' -o -name '*.a' -o -name '*.o' -o \
    -name '*.dylib' -o -name '*.exe' -o -perm -111 \) -print 2>/dev/null || true)"
if [ -n "$forbidden" ]; then
    note "no .so/.a/.o/executable files" "FAIL"
    echo "$forbidden" | sed 's/^/    /'
    fail=1
else
    note "no .so/.a/.o/executable files" "OK"
fi

size_kb="$(du -sk "$sub" | awk '{print $1}')"
if [ "$size_kb" -le $((30 * 1024)) ]; then
    note "package size <= 30 MB (${size_kb} KiB)" "OK"
else
    note "package size <= 30 MB (${size_kb} KiB)" "FAIL"
    fail=1
fi

# Every source listed in Make/files must be simpleFoam.C or under matrices/.
bad_paths="$(awk '
    /^[[:space:]]*#/ { next }
    /^[[:space:]]*$/ { next }
    /^[[:space:]]*EXE[[:space:]]*=/ { next }
    {
        p=$1
        if (p != "simpleFoam.C" && p !~ /^matrices\//) print p
    }
' "$sub/Make/files" 2>/dev/null || true)"
if [ -n "$bad_paths" ]; then
    note "Make/files paths are under matrices/ or simpleFoam.C" "FAIL"
    echo "$bad_paths" | sed 's/^/    /'
    fail=1
else
    note "Make/files paths are under matrices/ or simpleFoam.C" "OK"
fi

# Byte-identical check against the official installation, when available.
if [ -n "${FOAM_APP:-}" ] && [ -n "${FOAM_SRC:-}" ]; then
    appdir="$FOAM_APP/solvers/incompressible/simpleFoam"
    for f in simpleFoam.C UEqn.H pEqn.H createFields.H; do
        if cmp -s "$sub/$f" "$appdir/$f"; then
            note "$f matches official" "OK"
        else
            note "$f matches official" "FAIL"
            fail=1
        fi
    done
else
    note "official file comparison" "SKIP (source the OpenFOAM env first)"
fi

echo
if [ "$fail" -eq 0 ]; then
    echo "static checks passed"
else
    echo "static checks FAILED" >&2
    exit 1
fi
