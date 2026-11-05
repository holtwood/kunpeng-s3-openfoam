#!/usr/bin/env python3
"""Parse an OpenFOAM simpleFoam log for A/B reporting.

Usage:
    python3 scripts/parse_log.py logFiles/50_simpleFoam.xxxx.log

Outputs JSON with:
  - number of Time = lines
  - last ExecutionTime and ExecutionTime/500
  - final residual per solved field
  - total and last-step solver iterations per field
"""

import json
import re
import sys

TIME_RE = re.compile(r"^Time = ")
EXEC_RE = re.compile(r"^ExecutionTime\s*=\s*([0-9.eE+-]+)")
SOLVE_RE = re.compile(
    r"Solving for ([A-Za-z0-9_]+),\s*"
    r"Initial residual = ([^,]+),\s*"
    r"Final residual = ([^,]+),\s*"
    r"No Iterations\s+(\d+)"
)


def main(path: str) -> int:
    steps = 0
    execution_times = []
    final_residuals = {}
    iterations_total = {}
    iterations_last_step = {}
    last_step_seen = set()

    with open(path, "r", encoding="utf-8", errors="replace") as f:
        for raw in f:
            line = raw.rstrip("\n")

            if TIME_RE.match(line):
                steps += 1
                last_step_seen.clear()
                continue

            m = EXEC_RE.match(line)
            if m:
                execution_times.append(float(m.group(1)))
                continue

            m = SOLVE_RE.search(line)
            if m:
                field, _initial, final, niter = m.groups()
                final_residuals[field] = float(final)
                n = int(niter)
                iterations_total[field] = iterations_total.get(field, 0) + n
                if field not in last_step_seen:
                    iterations_last_step[field] = 0
                    last_step_seen.add(field)
                iterations_last_step[field] += n

    execution_time = execution_times[-1] if execution_times else None

    out = {
        "log": path,
        "steps": steps,
        "execution_time_s": execution_time,
        "time_per_step_s": (execution_time / steps) if execution_time and steps else None,
        "final_residuals": final_residuals,
        "iterations_total": iterations_total,
        "iterations_last_step": iterations_last_step,
    }

    print(json.dumps(out, indent=2, sort_keys=True))

    problems = []
    if steps != 500:
        problems.append(f"steps = {steps}, expected 500")
    if execution_time is None:
        problems.append("no ExecutionTime line")
    bad = {k: v for k, v in final_residuals.items() if v >= 5e-3}
    if bad:
        problems.append(f"final residuals >= 5e-3: {bad}")

    if problems:
        print("\nWARNING:", file=sys.stderr)
        for p in problems:
            print("  -", p, file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    if len(sys.argv) != 2:
        print(__doc__, file=sys.stderr)
        sys.exit(2)
    sys.exit(main(sys.argv[1]))
