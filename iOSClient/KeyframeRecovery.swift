import Foundation

/// When the device asks the Mac for a keyframe after its picture was interrupted (issue #101): the
/// display layer failed, could not decode a frame, or needs a flush before it decodes again (iOS
/// sets that when Sill goes to the background). HEVCDisplayView flushes the layer and waits for a
/// keyframe, and a still window on the Mac sends none, so the device asks for one (kind 44,
/// `keyframeRequest`), which the Mac answers by encoding its last frame again. Never a pick of the
/// source again: that restarts every device's stream and, in regular mode, raises the window.
///
/// - One ask per interruption: from the picture lost to the next keyframe shown. A trip to the
///   background in between owes the ask again (a keyframe that comes meanwhile is lost to it).
/// - Only while Sill is active and something streams: an interruption seen in the background is
///   asked for on the way back.
/// - At least `spacing` (2 s) after the last ask, whatever interrupted the picture; an ask the
///   spacing holds back is owed until then (`askAt`).
/// - A picture that fails again within `calm` (10 s) of its keyframe, Sill active throughout, waits
///   longer for each ask: each repeat doubles the spacing (4, 8, 16, then 32 s at most), so a decoder
///   that cannot keep up never costs every device a keyframe every 2 s. A picture that stays back
///   for `calm`, or a trip to the background, starts the spacing at 2 s again.
///
/// Pure: the client feeds it the view's events and the clock (`ProcessInfo.systemUptime`, seconds).
/// Main thread (StreamClient). `Tests/checks/keyframe-recovery` checks this file alone.
struct KeyframeRecovery {
    /// The least time between two asks.
    static let spacing: TimeInterval = 2
    /// The most, for a picture that fails again right after each keyframe.
    static let longestSpacing: TimeInterval = 32
    /// A picture back for this long has recovered: the next interruption is a new one, not a repeat.
    static let calm: TimeInterval = 10

    enum Decision: Equatable {
        /// Nothing to ask: no interruption, its ask already out, Sill not active, or nothing streams.
        case nothing
        /// Ask now (`consider` has counted the ask).
        case askNow
        /// Owed, held back by the spacing: consider again at this time.
        case askAt(TimeInterval)
    }

    /// The picture was lost and no keyframe has been shown since.
    private(set) var open = false
    /// This interruption's one ask went out (since it opened, or since Sill last came back to it).
    private(set) var asked = false
    /// Interruptions in a row that each came less than `calm` after the picture came back, with Sill
    /// in the foreground throughout: each doubles the spacing.
    private(set) var repeats = 0
    /// When the last ask went out.
    private(set) var lastAsk: TimeInterval?
    /// When the picture last came back after an interruption.
    private var backAt: TimeInterval?
    /// Sill left the foreground since the picture came back: the next interruption is the background's.
    private var wentAway = false

    /// The spacing the next ask keeps from the last one.
    var spacingNow: TimeInterval { min(Self.spacing * pow(2, Double(repeats)), Self.longestSpacing) }

    /// The view flushed its layer and waits for a keyframe. Opens an interruption, or is part of the
    /// open one (the layer reads interrupted at every frame until it decodes again).
    mutating func interrupted(now: TimeInterval) {
        guard !open else { return }
        open = true
        asked = false
        if !wentAway, let back = backAt, now >= back, now - back < Self.calm {
            repeats += 1
        } else {
            repeats = 0
        }
    }

    /// A keyframe was shown after the interruption: the picture is back.
    mutating func pictureBack(now: TimeInterval) {
        guard open else { return }
        open = false
        backAt = now
        wentAway = false
    }

    /// Sill is no longer active (another app, the background, Control Center). An open interruption's
    /// ask is owed again: its keyframe may come while Sill is away, and be lost to it.
    mutating func leftForeground() {
        wentAway = true
        asked = false
    }

    /// Whether to ask now. Counts the ask when it says `askNow`. `active`: Sill is the active app;
    /// `streaming`: the session streams a source.
    mutating func consider(now: TimeInterval, active: Bool, streaming: Bool) -> Decision {
        guard open, !asked, active, streaming else { return .nothing }
        // Against the time it is due, not `now - last < spacing`: (last + s) - last can round below s,
        // and an ask held until then would be held again at that very time.
        if let last = lastAsk, now >= last, now < last + spacingNow { return .askAt(last + spacingNow) }
        asked = true
        lastAsk = now
        return .askNow
    }
}
