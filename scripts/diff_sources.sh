#!/usr/bin/env bash
# Show the source-level delta from the official v2606 files.
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"

diff -u "$root/reference/lduMatrixATmul.C" \
        "$root/src/matrices/lduMatrix/lduMatrix/lduMatrixATmul.C" || true
diff -u "$root/reference/GaussSeidelSmoother.C" \
        "$root/src/matrices/lduMatrix/smoothers/GaussSeidel/GaussSeidelSmoother.C" || true
diff -u "$root/reference/smoothSolver.C" \
        "$root/src/matrices/lduMatrix/solvers/smoothSolver/smoothSolver.C" || true
diff -u "$root/reference/GAMGSolverInterpolate.C" \
        "$root/src/matrices/lduMatrix/solvers/GAMG/GAMGSolverInterpolate.C" || true
diff -u "$root/reference/GAMGSolverSolve.C" \
        "$root/src/matrices/lduMatrix/solvers/GAMG/GAMGSolverSolve.C" || true
diff -u "$root/reference/GAMGAgglomeration.C" \
        "$root/src/matrices/lduMatrix/solvers/GAMG/GAMGAgglomerations/GAMGAgglomeration/GAMGAgglomeration.C" || true
diff -u "$root/reference/pairGAMGAgglomeration.C" \
        "$root/src/matrices/lduMatrix/solvers/GAMG/GAMGAgglomerations/pairGAMGAgglomeration/pairGAMGAgglomeration.C" || true
