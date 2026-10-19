#!/bin/bash
# DisplayWake (Sources/SillHost/DisplayWake.swift) on its own: when the host declares user activity on
# the Mac for a device, as a key press would (issue #134): a connect every time, picks and input at
# most once every 5 s, a test host counting instead, the lines and when they are said, then 20,000
# random sessions against the invariants. Pure: nothing is declared.
#   Tests/checks/display-wake/run.sh             compile and run the check
#   Tests/checks/display-wake/run.sh --mutants   one-line mutants of DisplayWake.swift; each must fail it
here="$(cd "$(dirname "$0")" && pwd)"
source "$here/../common.sh"
if [ "${1:-}" = "--mutants" ]; then run_mutants python3 "$here/mutants.py"; exit; fi
swiftc -O Sources/SillHost/DisplayWake.swift "$here/main.swift" -o "$out/check"
"$out/check"
