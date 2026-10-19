// DisplayWake (Sources/SillHost/DisplayWake.swift) on its own: when the host declares user activity
// on the Mac for a device (issue #134, PR #151), what a key press on the Mac does, so a sleeping
// display wakes for a device and sleeps again by the Mac's own setting once nobody uses it.
//
//   swiftc -O Sources/SillHost/DisplayWake.swift Tests/checks/display-wake/main.swift -o check && ./check
//
// What it checks: the constants (the 5 s interval, the assertion's name and its 128-character limit,
// the stats keys); a connect declares every time; a pick and input declare only 5 s or more after the
// last declaration, at exactly 5 s too, and a pick right after the connect (the device asking for the
// Desktop by itself) adds nothing; what was held off does not restart the interval, a declaration
// does; a clock set back never holds a declaration off; a test host counts exactly where a real one
// declares and never declares; the lines (the woke line per event, the refusal's with its IOKit code
// in hex) and when DisplayActivity says them (Report: only for a display that was asleep and a
// declaration that went through; a refusal once, again after a success); then 20,000 random sessions
// against these invariants:
//   I1 every connect declares (a test host: counts);
//   I2 two declarations by picks or input are never under 5 s apart, unless the clock went back;
//   I3 a pick or input 5 s or more after the last declaration declares;
//   I4 a test host never declares, a real one never counts;
//   I5 through input that keeps coming (no gap over g), the time since the last declaration is never
//      over 5 s + g: the display stays on as it would for local input.
import Foundation

var failures = 0, passes = 0
func check(_ ok: Bool, _ what: String) {
    if ok { passes += 1; print("ok   \(what)") } else { failures += 1; print("FAIL \(what)") }
}
func eq<T: Equatable>(_ a: T, _ b: T, _ what: String) { check(a == b, "\(what): \(a)" + (a == b ? "" : " (want \(b))")) }

typealias W = DisplayWake

extension DisplayWake.Decision: CustomStringConvertible {
    var description: String {
        switch self {
        case .nothing: return "nothing"
        case .declare: return "declare"
        case .count: return "count"
        }
    }
}

/// Runs `events` (event, time) through a fresh rule and returns its decisions.
func run(_ events: [(W.Event, TimeInterval)], testHost: Bool = false) -> [W.Decision] {
    var w = W(testHost: testHost)
    return events.map { w.decide($0.0, at: $0.1) }
}

// MARK: - The constants

eq(W.interval, 5, "the interval: 5 s")
eq(W.assertionName, "Sill: a device is using this Mac", "the assertion's name in pmset -g assertions")
check(W.assertionName.utf8.count <= 128, "the assertion's name within IOPMLib.h's 128 characters (\(W.assertionName.utf8.count))")
eq(W.declaredKey, "disp.wake", "the stats key for a declaration")
eq(W.dryKey, "disp.wakeDry", "the stats key for a test host's count")
eq(W.success, 0, "kIOReturnSuccess is 0")
check(W.declaredKey != W.dryKey, "the two keys differ")

// MARK: - A fresh rule

do {
    var w = W(testHost: false)
    eq(w.lastDeclared, nil, "fresh: nothing declared yet")
    eq(w.decide(.input, at: 100), .declare, "fresh: the first input declares")
    eq(w.lastDeclared, 100, "fresh: the declaration's time kept")
    var p = W(testHost: false)
    eq(p.decide(.pick, at: 100), .declare, "fresh: the first pick declares")
    var c = W(testHost: false)
    eq(c.decide(.connect, at: 100), .declare, "fresh: the first connect declares")
}

// MARK: - The connect: every time

eq(run([(.connect, 0), (.connect, 0.001), (.connect, 0.002)]), [.declare, .declare, .declare],
   "three connects within 2 ms: each declares (two devices, a move's second connection)")
eq(run([(.input, 0), (.connect, 1)]), [.declare, .declare], "a connect 1 s after input's declaration still declares")
eq(run([(.connect, 0), (.input, 0.5)]), [.declare, .nothing], "input 0.5 s after the connect: nothing")
do {
    // The connect restarts the interval as any declaration does.
    eq(run([(.input, 0), (.connect, 4), (.input, 5), (.input, 9)]), [.declare, .declare, .nothing, .declare],
       "a connect at 4 s restarts the interval: input at 5 s nothing, at 9 s declares")
}

// MARK: - The pick

eq(run([(.connect, 10), (.pick, 10.05)]), [.declare, .nothing],
   "the device's own Desktop request 50 ms after the connect: nothing")
eq(run([(.connect, 10), (.pick, 14.999)]), [.declare, .nothing], "a pick 4.999 s after: nothing")
eq(run([(.connect, 10), (.pick, 15)]), [.declare, .declare], "a pick exactly 5 s after: declares")
eq(run([(.connect, 10), (.pick, 75)]), [.declare, .declare], "a pick a minute later: declares")
eq(run([(.connect, 0), (.pick, 6), (.pick, 7), (.pick, 11), (.pick, 12)]), [.declare, .declare, .nothing, .declare, .nothing],
   "picks every second or so: one in 5 s")

// MARK: - Input

do {
    // A stream of input every 0.1 s for a minute, after a connect at 0.
    var w = W(testHost: false)
    var declaredAt: [TimeInterval] = []
    if w.decide(.connect, at: 0) == .declare { declaredAt.append(0) }
    for i in 1...600 {
        let t = Double(i) / 10
        if w.decide(.input, at: t) == .declare { declaredAt.append(t) }
    }
    let gaps = zip(declaredAt.dropFirst(), declaredAt).map { $0 - $1 }
    eq(declaredAt.count, 13, "input every 0.1 s for 60 s after a connect: 13 declarations (0, 5, …, 60)")
    check(gaps.allSatisfy { abs($0 - 5) < 0.0001 }, "input every 0.1 s: declarations 5 s apart (\(gaps.map { String(format: "%.1f", $0) }.joined(separator: " ")))")
}
eq(run([(.input, 0), (.input, 1), (.input, 2), (.input, 3), (.input, 4), (.input, 5), (.input, 6)]),
   [.declare, .nothing, .nothing, .nothing, .nothing, .declare, .nothing],
   "input every second: what was held off does not restart the interval (5 s declares)")
eq(run([(.input, 0), (.input, 4.9), (.input, 9.8), (.input, 14.7)]), [.declare, .nothing, .declare, .nothing],
   "input every 4.9 s: every other one declares")
eq(run([(.input, 0), (.input, 600)]), [.declare, .declare], "input after 10 minutes of nothing: declares at once (the display may have slept)")
eq(run([(.input, 0), (.input, 5 - 1e-9)]), [.declare, .nothing], "input just under 5 s: nothing")
eq(run([(.input, 0), (.input, 5)]), [.declare, .declare], "input at exactly 5 s: declares")

// MARK: - A clock set back

eq(run([(.input, 1000), (.input, 10)]), [.declare, .declare], "the clock set back 990 s: input declares")
eq(run([(.input, 1000), (.input, 10), (.input, 11), (.input, 15)]), [.declare, .declare, .nothing, .declare],
   "after the clock went back, the interval counts from the new time")
eq(run([(.input, 1000), (.input, 999.9)]), [.declare, .declare], "the clock back by 0.1 s: declares")
eq(run([(.input, 1000), (.input, 1000)]), [.declare, .nothing], "the same instant: nothing")

// MARK: - A test host

do {
    let events: [(W.Event, TimeInterval)] = [(.connect, 0), (.pick, 0.1), (.input, 2), (.input, 5.2), (.connect, 5.3), (.pick, 11)]
    let real = run(events), test = run(events, testHost: true)
    eq(real, [.declare, .nothing, .nothing, .declare, .declare, .declare], "a session on a real host")
    eq(test, [.count, .nothing, .nothing, .count, .count, .count], "the same session on a test host: counts where it declares")
    check(!test.contains(.declare), "a test host never declares")
    var t = W(testHost: true)
    eq(t.decide(.connect, at: 0), .count, "a test host's connect counts")
    eq(t.lastDeclared, 0, "a test host's count restarts the interval as a declaration does")
    eq(t.decide(.input, at: 1), .nothing, "a test host's input 1 s later: nothing")
}

// MARK: - The lines

eq(W.wokeLine(device: "iPad (iPad14,1)", event: .connect), "Woke the display for iPad (iPad14,1), which connected.",
   "the woke line for a connect")
eq(W.wokeLine(device: "iPad (iPad14,1)", event: .pick), "Woke the display for iPad (iPad14,1), which picked what to stream.",
   "the woke line for a pick")
eq(W.wokeLine(device: "Noah’s iPhone", event: .input), "Woke the display for Noah’s iPhone, which sent input.",
   "the woke line for input")
eq(W.wokeLine(device: "127.0.0.1:52011", event: .connect), "Woke the display for 127.0.0.1:52011, which connected.",
   "the woke line naming an address")
check(Set(W.Event.allCases.map { W.wokeLine(device: "d", event: $0) }).count == W.Event.allCases.count,
      "each event's line says something of its own")
check(W.Event.allCases.allSatisfy { !W.wokeLine(device: "d", event: $0).contains("\n") }, "every woke line is one line")
// kIOReturnNotPrivileged, 0xe00002c1.
let notPrivileged = Int32(bitPattern: 0xe000_02c1)
eq(W.failedLine(notPrivileged),
   "Could not wake the display: macOS refused to declare user activity (IOKit error 0xe00002c1). A sleeping display stays dark until someone wakes it at the Mac.",
   "the refusal's line, its code in hex")
eq(W.failedLine(1), "Could not wake the display: macOS refused to declare user activity (IOKit error 0x1). A sleeping display stays dark until someone wakes it at the Mac.",
   "a small code in hex")

// MARK: - What DisplayActivity says (Report)

do {
    var r = W.Report()
    eq(r.line(device: "iPad", event: .connect, wasAsleep: true, result: 0), "Woke the display for iPad, which connected.",
       "report: asleep, declared: the woke line")
    eq(r.line(device: "iPad", event: .input, wasAsleep: false, result: 0), nil, "report: awake, declared: nothing")
    eq(r.line(device: "iPad", event: .input, wasAsleep: true, result: notPrivileged), W.failedLine(notPrivileged),
       "report: refused: the refusal's line, not the woke line")
    check(r.saidFailure, "report: the refusal noted")
    eq(r.line(device: "iPad", event: .input, wasAsleep: true, result: notPrivileged), nil, "report: refused again: nothing")
    eq(r.line(device: "iPad", event: .input, wasAsleep: false, result: 0), nil, "report: then declared, awake: nothing")
    check(!r.saidFailure, "report: a declaration that went through clears the refusal")
    eq(r.line(device: "iPad", event: .pick, wasAsleep: true, result: notPrivileged), W.failedLine(notPrivileged),
       "report: refused after a success: said again")
    eq(r.line(device: "iPad", event: .pick, wasAsleep: true, result: 0), "Woke the display for iPad, which picked what to stream.",
       "report: then asleep and declared: the woke line")
    var fresh = W.Report()
    eq(fresh.line(device: "iPad", event: .pick, wasAsleep: false, result: 1), W.failedLine(1), "report: a first refusal is said")
}

// MARK: - 20,000 random sessions

/// SplitMix64: the same sessions every run.
struct Rng {
    var s: UInt64
    mutating func next() -> UInt64 {
        s &+= 0x9E37_79B9_7F4A_7C15
        var z = s
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
    mutating func unit() -> Double { Double(next() >> 11) / Double(1 << 53) }
    mutating func below(_ n: Int) -> Int { Int(next() % UInt64(n)) }
}

var rng = Rng(s: 0x5111_134)
var violations: [String: Int] = [:], firstViolation: [String: String] = [:]
func violated(_ what: String, _ detail: String) {
    violations[what, default: 0] += 1
    if firstViolation[what] == nil { firstViolation[what] = detail }
}
/// The documented interval, written out: the invariants do not take it from the rule.
let five: TimeInterval = 5
var events = 0, declared = 0, counted = 0, heldOff = 0, clockBacks = 0, streamed = 0
for session in 0..<20_000 {
    let testHost = rng.below(4) == 0
    var w = W(testHost: testHost)
    var now = rng.unit() * 1_000_000
    var lastDecl: TimeInterval?            // the model's own: when the last declaration (or count) was made
    // Input that keeps coming: no gap over `streamGap` (I5).
    let streamGap = 0.05 + rng.unit() * 3
    for _ in 0..<(5 + rng.below(60)) {
        // The next event: mostly input, sometimes a pick or a connect; gaps from milliseconds to minutes,
        // input that keeps coming within `streamGap`, and now and then the clock set back.
        let roll = rng.below(100)
        let event: W.Event = roll < 8 ? .connect : roll < 22 ? .pick : .input
        let gap: TimeInterval
        let kind = rng.below(100)
        if kind < 3 {
            gap = -(rng.unit() * 600)                       // the clock set back
        } else if kind < 60 {
            gap = rng.unit() * streamGap                    // input that keeps coming
        } else if kind < 90 {
            gap = rng.unit() * 12
        } else {
            gap = rng.unit() * 900
        }
        now += gap
        if gap < 0 { clockBacks += 1 }
        let detail = "session \(session) (test host \(testHost)): \(event) at \(now), last \(lastDecl.map { "\($0)" } ?? "none")"
        // I5, before the decision: through input that keeps coming, never more than 5 s + the gap since the
        // last declaration (it was due at 5 s, and the input before it came under 5 s after it).
        if event == .input, gap >= 0, gap <= streamGap, let last = lastDecl {
            streamed += 1
            if now - last > five + streamGap { violated("I5 input kept coming and the display was not kept on", detail) }
        }
        let d = w.decide(event, at: now)
        events += 1
        let said = detail + ": \(d)"
        // I4
        if testHost, d == .declare { violated("I4 a test host declared", said) }
        if !testHost, d == .count { violated("I4 a real host counted", said) }
        let acted = d != .nothing
        // I1
        if event == .connect, !acted { violated("I1 a connect that did not declare", said) }
        if event != .connect {
            if let last = lastDecl {
                // I2
                if acted, now >= last, now - last < five { violated("I2 two declarations under 5 s apart", said) }
                // I3
                if !acted, now - last >= five { violated("I3 a due declaration held off", said) }
                if !acted, now < last { violated("I3 a clock set back held a declaration off", said) }
            } else if !acted {
                violated("I3 the first declaration held off", said)
            }
        }
        if acted {
            lastDecl = now
            if testHost { counted += 1 } else { declared += 1 }
        } else {
            heldOff += 1
        }
        // The rule's own record agrees with the model's.
        if w.lastDeclared != lastDecl { violated("the rule's last declaration is not the model's", said) }
    }
}
for (what, count) in violations.sorted(by: { $0.key < $1.key }) {
    check(false, "\(what): \(count) times; first: \(firstViolation[what] ?? "")")
}
check(violations.isEmpty && declared > 50_000 && counted > 15_000 && heldOff > 100_000 && clockBacks > 10_000 && streamed > 100_000,
      "20,000 random sessions, \(events) events (\(declared) declared, \(counted) counted on test hosts, \(heldOff) held off, "
      + "\(clockBacks) clocks set back, \(streamed) inputs that kept coming): every invariant")

print(failures == 0 ? "ok: \(passes) checks" : "FAILED: \(failures) of \(passes + failures) checks")
exit(failures == 0 ? 0 : 1)
