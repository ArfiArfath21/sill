// CaptureScale (Sources/SillHost/CaptureScale.swift): the pixel scale a capture runs at, the
// Resolution knob held to the display's own (2026-10-27: on an external 2560×1440 display at 1x, a
// window picked at Retina filled the top-left quarter of the picture, and the Desktop was captured at
// 5120×2880). Compiled with Sources/SillHost/CaptureScale.swift alone (run.sh):
//   swiftc -O Sources/SillHost/CaptureScale.swift Tests/checks/capture-scale/main.swift
// The rule case by case (Sill.log's own sizes among them), then random knobs and displays against
// its properties.
import CoreGraphics
import Foundation

var failures = 0, checks = 0
func check(_ ok: Bool, _ what: @autoclosure () -> String) {
    checks += 1
    if ok { print("ok   \(what())") } else { failures += 1; print("FAIL \(what())") }
}
typealias C = CaptureScale

/// WindowCapture.swift's, which needs ScreenCaptureKit and so is not compiled here: HEVC wants even
/// dimensions.
func evenPixels(_ v: CGFloat) -> Int { Int(v.rounded(.down)) & ~1 }
/// What `select` asks ScreenCaptureKit for: the content's points at the capture's pixel scale.
func size(_ w: CGFloat, _ h: CGFloat, knob: CGFloat, display: CGFloat?) -> String {
    let s = C.effective(knob: knob, displayScale: display)
    return "\(evenPixels(w * s))×\(evenPixels(h * s))"
}
/// The part of each side of the buffer a window fills: ScreenCaptureKit draws it at its display's own
/// scale and never scales it up (the bug: a 2x buffer of a window on a 1x display, a half each way).
func fill(capture: CGFloat, display: CGFloat) -> CGFloat { min(1, display / capture) }

// MARK: - The capture's pixel scale

// Noah's display, 2026-10-27: an external 2560×1440 at 1x, ScreenCaptureKit's "scale 1.0".
check(C.effective(knob: 2, displayScale: 1) == 1, "Retina on a 1x display captures at 1x")
check(C.effective(knob: 1, displayScale: 1) == 1, "Standard on a 1x display captures at 1x")
check(C.effective(knob: 2, displayScale: 2) == 2, "Retina on a 2x display captures at 2x, as before")
check(C.effective(knob: 1, displayScale: 2) == 1, "Standard on a 2x display captures at 1x, as before")
check(C.effective(knob: 2, displayScale: 3) == 2, "never more than the knob, whatever the display")
check(C.effective(knob: 2, displayScale: 1.5) == 1.5, "a display's own scale between the two is its own")
// The software encoder's knob is 1 at most (StreamCoordinator.captureScale).
check(C.effective(knob: 1, displayScale: 1) == 1 && C.effective(knob: 1, displayScale: 2) == 1, "the software encoder's 1x on either display")
// The test pattern has no display: the knob, as before (1512×949 × knob).
check(C.effective(knob: 2, displayScale: nil) == 2 && C.effective(knob: 1, displayScale: nil) == 1, "no display (the test pattern): the knob")
check(size(1512, 949, knob: 2, display: nil) == "3024×1898" && size(1512, 949, knob: 1, display: nil) == "1512×948",
      "the test pattern's sizes as before: 3024×1898 at Retina, 1512×948 at Standard")
// A scale that is none keeps the knob.
for bad: CGFloat in [0, -1, -2, .nan, .infinity, -.infinity] {
    check(C.effective(knob: 2, displayScale: bad) == 2 && C.effective(knob: 1, displayScale: bad) == 1,
          "a display scale of \(bad) is none: the knob")
}
// Sill's own virtual display, made at 2x: a staged window captures at the knob, as before.
check(C.virtualDisplay == 2, "Sill's virtual display is 2x")
check(C.effective(knob: 2, displayScale: C.virtualDisplay) == 2 && C.effective(knob: 1, displayScale: C.virtualDisplay) == 1,
      "a staged window captures at the knob")

// ScreenCaptureKit's `pointPixelScale` (a Float) as a display scale.
check(C.displayScale(pointPixelScale: 1) == 1 && C.displayScale(pointPixelScale: 2) == 2, "pointPixelScale 1.0 and 2.0 read as 1 and 2")
for bad: Float in [0, -2, .nan, .infinity, -.infinity] {
    check(C.displayScale(pointPixelScale: bad) == nil, "pointPixelScale \(bad) is no scale")
}

// Sill.log's own captures, 2026-10-27 and before: what was asked, and what is asked now.
check(size(2560, 1440, knob: 2, display: 1) == "2560×1440",
      "the 1x Desktop: 2560×1440 (Sill.log: 5120×2880, four times the pixels, upscaled)")
check(size(1117, 610, knob: 2, display: 1) == "1116×610",
      "the window on the 1x display: 1116×610 (Sill.log: 2234×1220, the window in its top-left quarter)")
check(size(2234, 1220, knob: 2, display: 1) == "2234×1220", "a 2234×1220-point window on the 1x display (Sill.log: 4468×2440)")
check(size(1512, 982, knob: 2, display: 2) == "3024×1964" && size(1512, 982, knob: 1, display: 2) == "1512×982",
      "the Retina Desktop as before: 3024×1964 at Retina, 1512×982 at Standard")
check(size(1091, 753, knob: 2, display: 2) == "2182×1506", "a window on the Retina display as before (Sill.log: 2182×1506)")
check(size(2234, 1220, knob: 2, display: C.virtualDisplay) == "4468×2440" && size(1117, 610, knob: 2, display: C.virtualDisplay) == "2234×1220",
      "staged windows as before (Sill.log: 4468×2440 and 2234×1220 of the virtual display)")

// What the picture shows: before, a window drawn at 1x into a 2x buffer filled a half each way.
check(fill(capture: 2, display: 1) == 0.5, "the bug as ScreenCaptureKit draws it: a quarter of the picture (a half each way)")
for knob: CGFloat in [1, 2] {
    for display: CGFloat in [1, 2] {
        let e = C.effective(knob: knob, displayScale: display)
        check(fill(capture: e, display: display) == 1, "knob \(knob)x on a \(display)x display: the window fills the picture")
    }
}

// The capture line's words.
check(C.words(knob: 2, displayScale: 1) == "capturing at 1x, the display's own (2x asked)", "the words on a 1x display at Retina")
check(C.words(knob: 2, displayScale: 2) == "capturing at 2x", "the words on a 2x display at Retina")
check(C.words(knob: 1, displayScale: 2) == "capturing at 1x", "Standard on a 2x display: nothing held down")
check(C.words(knob: 1, displayScale: 1) == "capturing at 1x", "Standard on a 1x display: nothing held down")
check(C.words(knob: 2, displayScale: nil) == "capturing at 2x", "no display: the knob")
check(C.times(1) == "1x" && C.times(2) == "2x" && C.times(1.5) == "1.5x", "1x, 2x and 1.5x")

// MARK: - Random knobs and displays

var seed: UInt64 = 0x5111_CA9E
func next() -> UInt64 {   // a seeded generator, so a failure repeats
    seed = seed &* 6364136223846793005 &+ 1442695040888963407
    return seed >> 11
}
func pick<T>(_ xs: [T]) -> T { xs[Int(next() % UInt64(xs.count))] }

var ruleBad = 0, upscaled = 0
for _ in 0..<20_000 {
    let knob = pick([CGFloat(1), 2])
    let display: CGFloat? = pick([nil, 1, 2, 3, 1.5, 0, -1, .nan, .infinity])
    let e = C.effective(knob: knob, displayScale: display)
    let valid = display.map { $0.isFinite && $0 > 0 } ?? false
    if e > knob || (valid && e > display!) || (!valid && e != knob) || !(e == knob || e == display) { ruleBad += 1 }
    if valid, fill(capture: e, display: display!) < 1 { upscaled += 1 }
}
check(ruleBad == 0, "20,000 random knobs and displays: the knob held to a real display's own, else the knob (\(ruleBad) not)")
check(upscaled == 0, "a window always fills its picture: never captured above its display's scale (\(upscaled) not)")

print("\(checks) checks, \(failures) failed")
exit(failures == 0 ? 0 : 1)
