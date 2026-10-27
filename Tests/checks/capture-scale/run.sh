#!/bin/bash
# CaptureScale (Sources/SillHost/CaptureScale.swift) on its own: the pixel scale a capture runs at, the
# Resolution knob held to the display's own (2026-10-27: on an external 2560×1440 display at 1x, a
# window picked at Retina filled the top-left quarter of the picture); then random knobs and displays
# against the rule's properties.
#   Tests/checks/capture-scale/run.sh             compile and run the check
#   Tests/checks/capture-scale/run.sh --mutants   one-line mutants of CaptureScale.swift; each must fail it
here="$(cd "$(dirname "$0")" && pwd)"
source "$here/../common.sh"
if [ "${1:-}" = "--mutants" ]; then run_mutants python3 "$here/mutants.py"; exit; fi
rm -f "$out/check"
swiftc -O Sources/SillHost/CaptureScale.swift "$here/main.swift" -o "$out/check"
"$out/check"
