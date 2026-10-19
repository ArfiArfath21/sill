// KeyframeRecovery (iOSClient): when the device asks the Mac for a keyframe after its picture was
// interrupted (issue #101). Compiled with iOSClient/KeyframeRecovery.swift alone (run.sh). The rule
// case by case at its edges, then 20,000 random sessions against a model that keeps the history of
// events rather than the type's flags.
import Foundation

var failures = 0, checks = 0
func check(_ ok: Bool, _ what: String) {
    checks += 1
    if ok { print("ok   \(what)") } else { failures += 1; print("FAIL \(what)") }
}
typealias R = KeyframeRecovery

// MARK: - Cases

var r = R()
check(r.consider(now: 10, active: true, streaming: true) == .nothing, "no interruption: nothing to ask")
r.interrupted(now: 10)
check(r.open && !r.asked, "an interruption opens")
check(r.consider(now: 10, active: true, streaming: true) == .askNow, "the first ask goes at once")
check(r.asked && r.lastAsk == 10, "the ask is counted")
check(r.consider(now: 10.1, active: true, streaming: true) == .nothing, "one ask per interruption")
check(r.consider(now: 100, active: true, streaming: true) == .nothing, "still one, however long the keyframe takes (an older Mac never answers)")
r.interrupted(now: 11)
check(r.consider(now: 11, active: true, streaming: true) == .nothing, "the layer read interrupted again: the same interruption, no second ask")

var bg = R()
bg.leftForeground()
bg.interrupted(now: 5)
check(bg.consider(now: 5, active: false, streaming: true) == .nothing, "seen in the background: held")
check(bg.lastAsk == nil && !bg.asked, "a held ask is not counted")
check(bg.consider(now: 7, active: true, streaming: true) == .askNow, "active again: asked")

var idle = R()
idle.interrupted(now: 20)
check(idle.consider(now: 20, active: true, streaming: false) == .nothing, "nothing streams: no ask")
check(idle.lastAsk == nil, "nor is one counted, so the spacing holds nothing back")
check(idle.consider(now: 20.5, active: true, streaming: true) == .askNow, "a stream again: asked")

// The spacing between interruptions with a trip to the background between them: 2 s.
var sp = R()
sp.interrupted(now: 100)
_ = sp.consider(now: 100, active: true, streaming: true)
sp.pictureBack(now: 100.5)
check(!sp.open, "a keyframe shown closes the interruption")
sp.leftForeground()
sp.interrupted(now: 101)
check(sp.repeats == 0 && sp.spacingNow == 2, "after a trip to the background: the base spacing")
check(sp.consider(now: 101, active: true, streaming: true) == .askAt(102), "1 s after the last ask: owed at 2 s")
check(sp.consider(now: 101.999, active: true, streaming: true) == .askAt(102), "just under 2 s: still owed")
check(!sp.asked, "an owed ask is not counted")
check(sp.consider(now: 102, active: true, streaming: true) == .askNow, "at 2 s: asked")

// A picture that fails again right after each keyframe, Sill active throughout: 2, 4, 8, 16, 32, 32 s.
var rep = R()
var t = 0.0
rep.interrupted(now: t)
check(rep.consider(now: t, active: true, streaming: true) == .askNow, "a failing picture's first ask")
var gaps: [Double] = []
var lastAskTime = t
for _ in 0..<6 {
    rep.pictureBack(now: t + 0.1)
    rep.interrupted(now: t + 0.2)
    guard case .askAt(let at) = rep.consider(now: t + 0.2, active: true, streaming: true) else { check(false, "a repeat is held back"); break }
    t = at
    check(rep.consider(now: t, active: true, streaming: true) == .askNow, "a repeat asked at \(at - lastAskTime) s")
    gaps.append(t - lastAskTime)
    lastAskTime = t
}
check(gaps == [4, 8, 16, 32, 32, 32], "the spacing doubles for repeats, up to 32 s (\(gaps))")
check(rep.spacingNow == 32, "and stays there")

// A picture that stayed back for `calm` has recovered.
var calm = R()
calm.interrupted(now: 0); _ = calm.consider(now: 0, active: true, streaming: true)
calm.pictureBack(now: 1)
calm.interrupted(now: 11)
check(calm.repeats == 0 && calm.spacingNow == 2, "back for 10 s: a new interruption, the base spacing")
var nearly = R()
nearly.interrupted(now: 0); _ = nearly.consider(now: 0, active: true, streaming: true)
nearly.pictureBack(now: 1)
nearly.interrupted(now: 10.99)
check(nearly.repeats == 1 && nearly.spacingNow == 4, "back for just under 10 s: a repeat")
check(nearly.consider(now: 10.99, active: true, streaming: true) == .askNow, "a repeat 11 s after the last ask is not held by its 4 s")

// A trip to the background ends a streak.
var trip = R()
trip.interrupted(now: 0); _ = trip.consider(now: 0, active: true, streaming: true)
trip.pictureBack(now: 0.1); trip.interrupted(now: 0.2)
check(trip.repeats == 1, "a repeat")
_ = trip.consider(now: 4, active: true, streaming: true)
trip.pictureBack(now: 4.1)
trip.leftForeground()
trip.interrupted(now: 4.3)
check(trip.repeats == 0 && trip.spacingNow == 2, "back from the background: the streak ends")
check(trip.consider(now: 5, active: true, streaming: true) == .askAt(6), "and only the base spacing holds it back")

// A trip to the background while the ask is out: owed again on the way back.
var out = R()
out.interrupted(now: 50)
_ = out.consider(now: 50, active: true, streaming: true)
out.leftForeground()
check(out.open && !out.asked, "the keyframe may come while Sill is away: the ask is owed again")
check(out.consider(now: 51, active: false, streaming: true) == .nothing, "not while away")
check(out.consider(now: 51, active: true, streaming: true) == .askAt(52), "back within 2 s: owed at the spacing")
check(out.consider(now: 53, active: true, streaming: true) == .askNow, "then asked")
check(out.consider(now: 54, active: true, streaming: true) == .nothing, "once")

// A keyframe shown with nothing open changes nothing.
var stray = R()
stray.interrupted(now: 0); _ = stray.consider(now: 0, active: true, streaming: true)
stray.pictureBack(now: 1)
stray.pictureBack(now: 9)
stray.interrupted(now: 11.5)
check(stray.repeats == 0, "a keyframe with nothing open does not move when the picture came back (10.5 s ago, not 2.5)")

// The owed ask made moot: the picture came back on its own (another device's ask, a moving window).
var moot = R()
moot.interrupted(now: 0); _ = moot.consider(now: 0, active: true, streaming: true)
moot.pictureBack(now: 0.1); moot.interrupted(now: 0.2)
check(moot.consider(now: 0.2, active: true, streaming: true) == .askAt(4), "owed at 4 s")
moot.pictureBack(now: 1)
check(moot.consider(now: 4, active: true, streaming: true) == .nothing, "back before then: nothing to ask")

// A clock gone back (never with the uptime, but never a stuck ask either).
var clock = R()
clock.interrupted(now: 200); _ = clock.consider(now: 200, active: true, streaming: true)
clock.pictureBack(now: 200.1); clock.leftForeground(); clock.interrupted(now: 200.2)
check(clock.consider(now: 10, active: true, streaming: true) == .askNow, "a clock before the last ask: asked")
var early = R()
early.interrupted(now: 300); _ = early.consider(now: 300, active: true, streaming: true)
early.pictureBack(now: 300.1)
early.interrupted(now: 20)
check(early.repeats == 0, "a clock before the picture's return: not a repeat")

// The cap on repeats keeps the spacing at 32 s.
var cap = R()
var ct = 0.0
cap.interrupted(now: ct); _ = cap.consider(now: ct, active: true, streaming: true)
for _ in 0..<20 {
    cap.pictureBack(now: ct + 0.1); cap.interrupted(now: ct + 0.2)
    if case .askAt(let at) = cap.consider(now: ct + 0.2, active: true, streaming: true) { ct = at; _ = cap.consider(now: ct, active: true, streaming: true) }
}
check(cap.spacingNow == 32 && cap.repeats == 20, "twenty repeats: still 32 s (repeats \(cap.repeats))")

// MARK: - A model: the history of events, not flags

/// The rule restated from what happened: the interruption is the span since the last open, its
/// asks those since then and since the last trip away, the streak read back through the history.
struct Model {
    enum Event { case open(Double), back(Double), away, ask(Double) }
    var events: [Event] = []
    var isOpen: Bool {
        for e in events.reversed() { if case .open = e { return true }; if case .back = e { return false } }
        return false
    }
    /// Asks since the open interruption opened and since the last trip away within it.
    var askedInSegment: Bool {
        for e in events.reversed() {
            switch e {
            case .ask: return true
            case .away, .open: return false
            default: continue
            }
        }
        return false
    }
    var lastAsk: Double? {
        for e in events.reversed() { if case .ask(let t) = e { return t } }
        return nil
    }
    /// The streak of the open interruption: each open that came less than `calm` after the picture
    /// came back, with no trip away between them, adds one to the one before.
    var streak: Int {
        var k = 0
        var lastBack: Double? = nil
        var awaySinceBack = false
        for e in events {
            switch e {
            case .back(let t): lastBack = t; awaySinceBack = false
            case .away: awaySinceBack = true
            case .open(let t):
                if let b = lastBack, !awaySinceBack, t >= b, t - b < R.calm { k += 1 } else { k = 0 }
            case .ask: break
            }
        }
        return k
    }
    var spacing: Double { min(2 * pow(2, Double(streak)), 32) }

    mutating func interrupted(_ t: Double) { if !isOpen { events.append(.open(t)) } }
    mutating func back(_ t: Double) { if isOpen { events.append(.back(t)) } }
    mutating func away() { events.append(.away) }
    mutating func consider(_ t: Double, active: Bool, streaming: Bool) -> R.Decision {
        guard isOpen, !askedInSegment, active, streaming else { return .nothing }
        if let last = lastAsk, t >= last, t < last + spacing { return .askAt(last + spacing) }
        events.append(.ask(t))
        return .askNow
    }
}

struct LCG {
    var s: UInt64
    mutating func next() -> UInt64 { s = s &* 6364136223846793005 &+ 1442695040888963407; return s >> 33 }
    mutating func unit() -> Double { Double(next() % 1_000_000) / 1_000_000 }
}

var rng = LCG(s: 0x5eed_101)
var disagreements = 0, asks = 0, held = 0, tooClose = 0, whileIdle = 0, twicePerSegment = 0, owedNotAsked = 0
for session in 0..<20_000 {
    var rule = R(), model = Model()
    var now = Double(rng.next() % 1000)
    var active = true, streaming = true
    var askTimes: [Double] = []
    var segmentAsks = 0
    for _ in 0..<60 {
        let roll = rng.unit()
        if roll < 0.22 {
            if !rule.open { segmentAsks = 0 }
            rule.interrupted(now: now); model.interrupted(now)
        } else if roll < 0.40 {
            rule.pictureBack(now: now); model.back(now)
        } else if roll < 0.48 {
            if active { active = false; rule.leftForeground(); model.away(); segmentAsks = 0 } else { active = true }
        } else if roll < 0.52 {
            streaming.toggle()
        } else {
            let decided = rule.consider(now: now, active: active, streaming: streaming)
            let expected = model.consider(now, active: active, streaming: streaming)
            if decided != expected {
                disagreements += 1
                if disagreements <= 5 { print("     session \(session): at \(now) the rule said \(decided), the model \(expected)") }
            }
            switch decided {
            case .askNow:
                asks += 1
                if let last = askTimes.last, now - last < R.spacing { tooClose += 1 }
                if !active || !streaming { whileIdle += 1 }
                segmentAsks += 1
                if segmentAsks > 1 { twicePerSegment += 1 }
                askTimes.append(now)
            case .askAt(let at):
                held += 1
                // Owed: at that time, unless something changes, it goes.
                var copy = rule
                if copy.consider(now: at, active: true, streaming: true) != .askNow { owedNotAsked += 1 }
            case .nothing: break
            }
        }
        // Mostly short steps (a frame, a round trip), sometimes seconds, now and then minutes.
        let step = rng.unit()
        now += step < 0.6 ? rng.unit() * 0.5 : step < 0.9 ? rng.unit() * 6 : rng.unit() * 120
    }
}
check(disagreements == 0, "20,000 random sessions: the rule decides as the model does (\(disagreements) differ)")
check(asks > 10_000 && held > 1_000, "the sessions ask (\(asks)) and hold asks back (\(held))")
check(tooClose == 0, "no two asks less than 2 s apart (\(tooClose))")
check(whileIdle == 0, "no ask while Sill is not active or nothing streams (\(whileIdle))")
check(twicePerSegment == 0, "at most one ask per interruption between trips away (\(twicePerSegment))")
check(owedNotAsked == 0, "an ask held back goes at the time it was owed (\(owedNotAsked))")

print("\(checks) checks, \(failures) failed")
exit(failures == 0 ? 0 : 1)
