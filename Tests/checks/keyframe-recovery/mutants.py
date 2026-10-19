"""Mutants of KeyframeRecovery.swift (iOSClient): each changes it in one place, is compiled with the check
(main.swift) and must make it fail. usage: mutants.py"""
import os, subprocess, sys
SP = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(SP, "..", "..", ".."))   # the repository
OUT = os.path.join(ROOT, ".build", "checks", "keyframe-recovery")
os.makedirs(OUT, exist_ok=True)
SRC = os.path.join(ROOT, "iOSClient/KeyframeRecovery.swift")
orig = open(SRC).read()
GUARD = "        guard open, !asked, active, streaming else { return .nothing }"
HELD = "        if let last = lastAsk, now >= last, now < last + spacingNow { return .askAt(last + spacingNow) }"
REPEAT = "        if !wentAway, let back = backAt, now >= back, now - back < Self.calm {"
MUTANTS = [
    ("K1 more than one ask per interruption", GUARD, "        guard open, active, streaming else { return .nothing }"),
    ("K2 an ask while Sill is not active", GUARD, "        guard open, !asked, streaming else { return .nothing }"),
    ("K3 an ask while nothing streams", GUARD, "        guard open, !asked, active else { return .nothing }"),
    ("K4 an ask with no interruption", GUARD, "        guard !asked, active, streaming else { return .nothing }"),
    ("K5 no spacing", HELD, "        if let last = lastAsk, false { return .askAt(last + spacingNow) }"),
    ("K6 the spacing off by its edge", HELD,
     "        if let last = lastAsk, now >= last, now <= last + spacingNow { return .askAt(last + spacingNow) }"),
    ("K7 the spacing's rounding (held again when it is due)", HELD,
     "        if let last = lastAsk, now >= last, now - last < spacingNow { return .askAt(last + spacingNow) }"),
    ("K8 a clock gone back holds the ask", HELD,
     "        if let last = lastAsk, now < last + spacingNow { return .askAt(last + spacingNow) }"),
    ("K9 a repeat held back by the base spacing only", HELD,
     "        if let last = lastAsk, now >= last, now < last + Self.spacing { return .askAt(last + Self.spacing) }"),
    ("K10 the ask not counted", "        asked = true\n        lastAsk = now\n", "        lastAsk = now\n"),
    ("K11 the ask's time not kept", "        asked = true\n        lastAsk = now\n", "        asked = true\n"),
    ("K12 a spacing of 1 s", "    static let spacing: TimeInterval = 2", "    static let spacing: TimeInterval = 1"),
    ("K13 no longer spacing for repeats", "            repeats += 1\n", "            repeats = 0\n"),
    ("K14 no cap on the spacing",
     "    var spacingNow: TimeInterval { min(Self.spacing * pow(2, Double(repeats)), Self.longestSpacing) }",
     "    var spacingNow: TimeInterval { Self.spacing * pow(2, Double(repeats)) }"),
    ("K15 the cap at 16 s", "    static let longestSpacing: TimeInterval = 32", "    static let longestSpacing: TimeInterval = 16"),
    ("K16 calm by its edge", REPEAT, "        if !wentAway, let back = backAt, now >= back, now - back <= Self.calm {"),
    ("K17 never calm", REPEAT, "        if !wentAway, let back = backAt, now >= back {"),
    ("K18 a calm of 5 s", "    static let calm: TimeInterval = 10", "    static let calm: TimeInterval = 5"),
    ("K19 a trip away keeps the streak", REPEAT, "        if let back = backAt, now >= back, now - back < Self.calm {"),
    ("K20 the picture back keeps an old trip away", "        backAt = now\n        wentAway = false\n", "        backAt = now\n"),
    ("K21 a trip away marks nothing", "        wentAway = true\n        asked = false\n", "        asked = false\n"),
    ("K22 a trip away does not owe the ask again", "        wentAway = true\n        asked = false\n", "        wentAway = true\n"),
    ("K23 a stray keyframe moves when the picture came back",
     "    mutating func pictureBack(now: TimeInterval) {\n        guard open else { return }\n",
     "    mutating func pictureBack(now: TimeInterval) {\n"),
    ("K24 the layer read again opens a new interruption",
     "    mutating func interrupted(now: TimeInterval) {\n        guard !open else { return }\n",
     "    mutating func interrupted(now: TimeInterval) {\n"),
    ("K25 the picture back does not close it", "        guard open else { return }\n        open = false\n", "        guard open else { return }\n"),
    ("K26 a new interruption keeps the last one's ask", "        open = true\n        asked = false\n", "        open = true\n"),
    ("K27 a streak starts at one", "        } else {\n            repeats = 0\n        }", "        } else {\n            repeats = 1\n        }"),
    ("K28 a picture back before the clock counts", REPEAT, "        if !wentAway, let back = backAt, now - back < Self.calm {"),
]
caught = 0
for name, old, new in MUTANTS:
    if orig.count(old) != 1:
        print(f"{name}: NOT APPLIED (pattern found {orig.count(old)} times)"); continue
    src = os.path.join(OUT, "KeyframeRecovery.swift")
    open(src, "w").write(orig.replace(old, new, 1))
    exe = os.path.join(OUT, "mutant")
    if os.path.exists(exe): os.remove(exe)
    c = subprocess.run(["swiftc", "-O", src, os.path.join(SP, "main.swift"), "-o", exe], capture_output=True, text=True)
    if c.returncode != 0:
        print(f"{name}: did not compile: {c.stderr.strip().splitlines()[0] if c.stderr.strip() else ''}"); continue
    r = subprocess.run([exe], capture_output=True, text=True, timeout=600)
    failed = [l for l in r.stdout.splitlines() if l.startswith("FAIL")]
    if r.returncode != 0:
        caught += 1
        print(f"{name}: caught ({len(failed)} FAIL lines; first: {failed[0][:160] if failed else ''})")
    else:
        print(f"{name}: SURVIVED")
print(f"{caught} of {len(MUTANTS)} mutants caught")
sys.exit(0 if caught == len(MUTANTS) else 1)
