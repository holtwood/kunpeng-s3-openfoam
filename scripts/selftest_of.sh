#!/bin/bash
#DSUB -n selftest-of
#DSUB -q <你的队列>
#DSUB -nn 1
#DSUB -R "cpu=576,mem=256G"
#DSUB -T 14400
#DSUB -o <你的工作目录>/selftest_of.out
#DSUB -e <你的工作目录>/selftest_of.err
#
# Fill the three placeholders before dsub.
# This script follows the official guide; it does not modify the case.

TEMPLATE=/home/share/chentao/s3/release/case/of_21M_template.tar.gz
WORKDIR="<你的工作目录>"
LOG_TAG="${LOG_TAG:-selftest}"

source /home/share/chentao/s3/env-build/init.sh --quiet
export MY_SUFFIX=_bisheng_native
source /home/share/chentao/s3/data/OpenFOAM-v2606/etc/bashrc
export FOAM_EXTRA_LDFLAGS="-L/home/share/chentao/s3/env-build/cxx-lib -L/home/share/chentao/s3/env-build/hpckit/26.1.RC1/compiler/gcc/lib64"

RUN=/tmp/${LOG_TAG}_$USER
rm -rf "$RUN"; mkdir -p "$RUN"
tar -xzf "$TEMPLATE" -C "$RUN"
cd "$RUN"/of_21M

export PATH="$FOAM_USER_APPBIN:$PATH"
echo "simpleFoam = $(command -v simpleFoam)"

# The official Allrun-solve already contains the 576-rank mpirun parameters.
bash Allrun-solve

LOG=$(ls -t logFiles/50_simpleFoam.*.log | head -1)
echo "log = $LOG"
echo "--- steps (expect 500) ---"
grep -c '^Time = ' "$LOG"
echo "--- final ExecutionTime ---"
grep -E '^ExecutionTime' "$LOG" | tail -1
echo "--- final residuals (last block) ---"
tail -40 "$LOG"
