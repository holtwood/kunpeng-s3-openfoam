#!/usr/bin/env bash
# Assemble a submission tree for one A/B profile.
#
# Usage:
#   ./scripts/assemble.sh baseline
#   ./scripts/assemble.sh p1
#   ./scripts/assemble.sh p1p2
#   ./scripts/assemble.sh p1p2p3p4
#   ./scripts/assemble.sh p5
#   ./scripts/assemble.sh all
#
# The script only copies source files. It never compiles anything.

set -euo pipefail

profile="${1:-baseline}"
root="$(cd "$(dirname "$0")/.." && pwd)"
out="$root/submission/simpleFoam-submission"

case "$profile" in
    baseline)
        defs="-DKUNPENG_BASELINE"
        with_gamg_defaults=0
        ;;
    p1)
        defs="-DKUNPENG_SYMMETRIC"
        with_gamg_defaults=0
        ;;
    p1p2)
        defs="-DKUNPENG_SYMMETRIC -DKUNPENG_GS_OVERLAP"
        with_gamg_defaults=0
        ;;
    p1p2p3p4)
        defs="-DKUNPENG_SYMMETRIC -DKUNPENG_GS_OVERLAP -DKUNPENG_REUSE_RESIDUAL -DKUNPENG_GAMG_RESIDUAL"
        with_gamg_defaults=0
        ;;
    diag)
        defs="-DKUNPENG_GS_OVERLAP -DKUNPENG_GS_DIAG"
        with_gamg_defaults=0
        ;;
    p5)
        defs="-DKUNPENG_GAMG_COARSEST_CELLS=128 -DKUNPENG_GAMG_MERGE_LEVELS=2"
        with_gamg_defaults=1
        ;;
    all)
        defs="-DKUNPENG_SYMMETRIC -DKUNPENG_GS_OVERLAP -DKUNPENG_REUSE_RESIDUAL -DKUNPENG_GAMG_RESIDUAL -DKUNPENG_GAMG_COARSEST_CELLS=128 -DKUNPENG_GAMG_MERGE_LEVELS=2"
        with_gamg_defaults=1
        ;;
    *)
        echo "unknown profile: $profile" >&2
        echo "choose from: baseline p1 p1p2 p1p2p3p4 diag p5 all" >&2
        exit 2
        ;;
esac

rm -rf "$out"
mkdir -p "$out/Make"

# Prefer the official installation for the unmodified app sources, so the
# submission is byte-identical to the judge environment.
appdir="${FOAM_APP:-}/solvers/incompressible/simpleFoam"
if [ -n "${FOAM_APP:-}" ] && [ -d "$appdir" ]; then
    cp "$appdir/simpleFoam.C" "$out/"
    cp "$appdir/UEqn.H" "$out/"
    cp "$appdir/pEqn.H" "$out/"
    cp "$appdir/createFields.H" "$out/"
    echo "app sources: $appdir (official)"
else
    cp "$root/src/simpleFoam.C" "$out/"
    cp "$root/src/UEqn.H" "$out/"
    cp "$root/src/pEqn.H" "$out/"
    cp "$root/src/createFields.H" "$out/"
    echo "app sources: $root/src (local backup; source the OpenFOAM env to use the official copy)"
fi

cp -a "$root/src/matrices" "$out/"

sed -e "s|@PROFILE@|$profile|g" -e "s|@DEFINES@|$defs|g" \
    "$root/src/README.submission.md" > "$out/README.md"

# Make/files: order follows the official guide (our .C files above simpleFoam.C).
{
    echo "matrices/lduMatrix/lduMatrix/lduMatrixATmul.C"
    echo "matrices/lduMatrix/smoothers/GaussSeidel/GaussSeidelSmoother.C"
    echo "matrices/lduMatrix/solvers/smoothSolver/smoothSolver.C"
    echo "matrices/lduMatrix/solvers/GAMG/GAMGSolverInterpolate.C"
    echo "matrices/lduMatrix/solvers/GAMG/GAMGSolverSolve.C"
    if [ "$with_gamg_defaults" -eq 1 ]; then
        echo "matrices/lduMatrix/solvers/GAMG/GAMGAgglomerations/GAMGAgglomeration/GAMGAgglomeration.C"
        echo "matrices/lduMatrix/solvers/GAMG/GAMGAgglomerations/pairGAMGAgglomeration/pairGAMGAgglomeration.C"
    fi
    echo "simpleFoam.C"
    echo
    echo "EXE = \$(FOAM_USER_APPBIN)/simpleFoam"
} > "$out/Make/files"

sed "s|@KUNPENG_DEFINES@|$defs|" "$root/src/Make/options.in" > "$out/Make/options"

echo "profile : $profile"
echo "defines : $defs"
echo "output  : $out"
echo
echo "Next (on the target machine, after sourcing the official env):"
echo "  cd $out && wclean && wmake -j 16"
echo "  ls -l \"\$FOAM_USER_APPBIN/simpleFoam\""
