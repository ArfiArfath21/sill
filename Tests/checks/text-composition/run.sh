#!/bin/bash
# TextComposition (iOSClient/TextComposition.swift) on its own, with StreamProtocol's Input.swift: an
# input method's composition stays on the device until it is committed, and dictation's and an input
# method's edits reach the Mac as backspaces and text (#138); what was typed is kept whole while the
# text system may revise it, trimmed only past its limit, and a correction taken before a forget sends
# nothing; and TextInputRules: which input moves the Mac's caret, which input modes are keyboards, and
# whose ⌃Space it is.
#   Tests/checks/text-composition/run.sh             compile and run the check
here="$(cd "$(dirname "$0")" && pwd)"
source "$here/../common.sh"
swiftc -O iOSClient/TextComposition.swift Sources/StreamProtocol/Input.swift "$here/main.swift" -o "$out/check"
"$out/check"
