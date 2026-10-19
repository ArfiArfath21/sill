import Foundation

/// When the host tells macOS that someone is using the Mac on a device's behalf (issue #134): a Mac
/// whose display is asleep gives the stream black frames until someone wakes the display, so the host
/// declares user activity, what a key press on the Mac does, and DisplayActivity makes the call. The
/// display powers on if it was asleep, and it sleeps again by the Mac's own display-sleep setting,
/// counted from the last declaration, as after the last key press: nothing is held.
///
/// - A device's session connecting declares at once, every connection: the wake.
/// - A pick (a window, the Desktop, an app the device launches) and input (kind 8, and the device's
///   gestures, menu choices and a window's buttons) declare when the last declaration is `interval`
///   or more ago, so a stream of input declares at most once every 5 s and keeps the display on as
///   local input would, while a device that sends nothing lets it sleep. A pick right after the
///   connect (the device asks for the Desktop by itself) adds nothing.
/// - A test host (`--synthetic`: it does not advertise, as `InputInjector.dryRun`) declares nothing:
///   it counts what it would declare (`dryKey` in the stats line), and the Mac's display is never
///   touched.
///
/// One rule for every device: there is one display. The clock is the caller's; one that goes back
/// counts as time passed, so a clock set back never holds a declaration off. A value type on the
/// main actor (StreamCoordinator); `Report` is DisplayActivity's, on its queue. Pure: Foundation only,
/// checked with swiftc (Tests/checks/display-wake).
struct DisplayWake {
    enum Event: CaseIterable {
        /// A device's session connected: the coordinator's client-connected path, once per connection.
        case connect
        /// A device picked what to stream (kind 6), or launched an app (kind 7).
        case pick
        /// A device's input (kind 8), gesture (28), menu choice (25) or window button (15).
        case input
    }

    enum Decision: Equatable {
        /// Too soon after the last declaration: the display is already counted as in use.
        case nothing
        /// Declare user activity (DisplayActivity).
        case declare
        /// A test host: count `dryKey` and declare nothing.
        case count
    }

    /// How often a stream of picks and input declares at most. The display sleeps a minute or more
    /// after the last declaration (macOS's shortest display-sleep setting), so 5 s keeps it on through
    /// any input, and a display put to sleep at the Mac while a device works wakes at the device's
    /// input within 5 s.
    static let interval: TimeInterval = 5

    /// The name `pmset -g assertions` shows beside the UserIsActive assertion (IOPMLib.h: at most 128
    /// characters).
    static let assertionName = "Sill: a device is using this Mac"

    /// The stats line's keys, each only in a second it happened: a declaration made, and a test host's
    /// that was not.
    static let declaredKey = "disp.wake"
    static let dryKey = "disp.wakeDry"

    /// `--synthetic`: count, never declare.
    let testHost: Bool
    /// When the last declaration (or a test host's count) was made; nil before the first.
    private(set) var lastDeclared: TimeInterval?

    init(testHost: Bool) { self.testHost = testHost }

    /// What `event` at `now` does. A declaration (or count) restarts the interval; nothing does not.
    mutating func decide(_ event: Event, at now: TimeInterval) -> Decision {
        if event != .connect, let last = lastDeclared, now >= last, now - last < Self.interval {
            return .nothing
        }
        lastDeclared = now
        return testHost ? .count : .declare
    }

    /// The one line, when the main display was asleep just before a declaration that went through:
    /// "Woke the display for iPad (iPad14,1), which connected." The device's name as the Mac's card
    /// has it (cleaned), else its address.
    static func wokeLine(device: String, event: Event) -> String {
        let why: String
        switch event {
        case .connect: why = "connected"
        case .pick: why = "picked what to stream"
        case .input: why = "sent input"
        }
        return "Woke the display for \(device), which \(why)."
    }

    /// IOKit refused a declaration (it needs no privilege, so this should never show).
    static func failedLine(_ result: Int32) -> String {
        "Could not wake the display: macOS refused to declare user activity (IOKit error 0x"
            + String(UInt32(bitPattern: result), radix: 16)
            + "). A sleeping display stays dark until someone wakes it at the Mac."
    }

    /// kIOReturnSuccess (KERN_SUCCESS), without importing IOKit here.
    static let success: Int32 = 0

    /// What DisplayActivity says after each declaration: the woke line only when the main display was
    /// asleep just before and the declaration went through; a refusal's line the first time, and again
    /// only after a declaration has gone through since. Nothing else: no line per declaration.
    struct Report {
        private(set) var saidFailure = false

        mutating func line(device: String, event: Event, wasAsleep: Bool, result: Int32) -> String? {
            guard result == DisplayWake.success else {
                if saidFailure { return nil }
                saidFailure = true
                return DisplayWake.failedLine(result)
            }
            saidFailure = false
            return wasAsleep ? DisplayWake.wokeLine(device: device, event: event) : nil
        }
    }
}
