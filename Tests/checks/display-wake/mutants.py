"""Each mutant changes DisplayWake.swift (issue #134, PR #151) in one place and must fail the check
(main.swift). usage: mutants.py"""
import os, subprocess, sys
SP = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(SP, "..", "..", ".."))   # the repository
OUT = os.path.join(ROOT, ".build", "checks", "display-wake")   # the mutants' sources and binaries
os.makedirs(OUT, exist_ok=True)
SRC = os.path.join(ROOT, "Sources/SillHost/DisplayWake.swift")
orig = open(SRC).read()
GUARD = "if event != .connect, let last = lastDeclared, now >= last, now - last < Self.interval {"
MUTANTS = {
    "M1 the connect held off like input": (GUARD, "if let last = lastDeclared, now >= last, now - last < Self.interval {"),
    "M2 a pick declares at once, as the connect": (GUARD, "if event == .input, let last = lastDeclared, now >= last, now - last < Self.interval {"),
    "M3 input declares at once": (GUARD, "if event == .pick, let last = lastDeclared, now >= last, now - last < Self.interval {"),
    "M4 the interval 10 s": ("static let interval: TimeInterval = 5", "static let interval: TimeInterval = 10"),
    "M5 the interval 2 s": ("static let interval: TimeInterval = 5", "static let interval: TimeInterval = 2"),
    "M6 nothing at exactly 5 s": (GUARD, "if event != .connect, let last = lastDeclared, now >= last, now - last <= Self.interval {"),
    "M7 a declaration that does not restart the interval": ("        lastDeclared = now\n        return testHost", "        return testHost"),
    "M8 what was held off restarts it too": ("    mutating func decide(_ event: Event, at now: TimeInterval) -> Decision {\n",
                                             "    mutating func decide(_ event: Event, at now: TimeInterval) -> Decision {\n        defer { lastDeclared = now }\n"),
    "M9 a clock set back holds declarations off": (GUARD, "if event != .connect, let last = lastDeclared, now - last < Self.interval {"),
    "M10 a test host declares": ("return testHost ? .count : .declare", "return .declare"),
    "M11 a real host only counts": ("return testHost ? .count : .declare", "return .count"),
    "M12 the woke line without the device": ('return "Woke the display for \\(device), which \\(why)."', 'return "Woke the display, which \\(why)."'),
    "M13 a connect said as input": ('case .connect: why = "connected"', 'case .connect: why = "sent input"'),
    "M14 a pick said as a connect": ('case .pick: why = "picked what to stream"', 'case .pick: why = "connected"'),
    "M15 the refusal's code in decimal": ("String(UInt32(bitPattern: result), radix: 16)", "String(result)"),
    "M16 the woke line for a display that was on": ("return wasAsleep ? DisplayWake.wokeLine(device: device, event: event) : nil",
                                                    "return DisplayWake.wokeLine(device: device, event: event)"),
    "M17 no woke line at all": ("return wasAsleep ? DisplayWake.wokeLine(device: device, event: event) : nil", "return nil"),
    "M18 a refusal taken for a success": ("guard result == DisplayWake.success else {", "guard result == DisplayWake.success || result != 0 else {"),
    "M19 a refusal said every time": ("                if saidFailure { return nil }\n", ""),
    "M20 a refusal never said again after a success": ("            saidFailure = false\n            return wasAsleep", "            return wasAsleep"),
    "M21 the assertion's name": ('static let assertionName = "Sill: a device is using this Mac"', 'static let assertionName = "Sill is streaming a Mac screen"'),
    "M22 the declaration's stats key": ('static let declaredKey = "disp.wake"', 'static let declaredKey = "in.wake"'),
    "M23 the test host's stats key": ('static let dryKey = "disp.wakeDry"', 'static let dryKey = "disp.wake"'),
    "M24 success is not 0": ("static let success: Int32 = 0", "static let success: Int32 = 1"),
}
caught = 0
for name, (old, new) in MUTANTS.items():
    if orig.count(old) != 1:
        print(f"{name}: NOT APPLIED (pattern found {orig.count(old)} times)"); continue
    path = os.path.join(OUT, "mutant.swift")
    open(path, "w").write(orig.replace(old, new))
    b = subprocess.run(["swiftc", "-O", path, os.path.join(SP, "main.swift"), "-o", os.path.join(OUT, "mutant")],
                       capture_output=True, text=True)
    if b.returncode != 0:
        print(f"{name}: DOES NOT COMPILE\n{b.stderr[:600]}"); continue
    r = subprocess.run([os.path.join(OUT, "mutant")], capture_output=True, text=True, timeout=300)
    failed = [l[5:] for l in r.stdout.splitlines() if l.startswith("FAIL")]
    ok = r.returncode != 0
    caught += ok
    print(f"{'caught' if ok else 'MISSED'} {name}: {len(failed)} failing, e.g. {[f[:100] for f in failed[:2]]}")
print(f"{caught} of {len(MUTANTS)} mutants caught")
sys.exit(0 if caught == len(MUTANTS) else 1)
