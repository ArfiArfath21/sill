import CoreGraphics
import Foundation
import IOKit.pwr_mgt

/// Tells macOS that someone is using the Mac, for a device (issue #134): IOKit's
/// IOPMAssertionDeclareUserActivity with kIOPMUserActiveLocal, the declaration `caffeinate -u`
/// makes, and the kind WindowServer makes for a key press. A display that is asleep powers on, and
/// display sleep is postponed "up to the user's display sleep Energy Saver settings" (IOPMLib.h), so
/// the display sleeps again by the Mac's own setting once no device uses it: nothing is held.
/// (WindowServer's UserIsActive assertion for a key press shows that setting as its timeout in
/// `pmset -g assertions`.) The same ID goes back with each call, as the header asks; it is never
/// released early, and the process's assertions go with it when it quits.
///
/// DisplayWake decides when (the coordinator, on the main actor); a test host never gets here. The
/// call is an IPC to powerd and may block, so it runs on a queue of its own, with the read of the
/// main display's sleep state just before it and the one line DisplayWake.Report allows.
final class DisplayActivity: @unchecked Sendable {
    private let queue = DispatchQueue(label: "sill.display-wake", qos: .userInitiated)
    // On `queue`.
    private var assertionID = IOPMAssertionID(kIOPMNullAssertionID)
    private var report = DisplayWake.Report()

    /// Declares user activity for `device` (its name for the line) because of `event`.
    func declare(for device: String, _ event: DisplayWake.Event) {
        queue.async { [self] in
            // Only a display that was asleep was woken: a declaration while it is on only postpones its
            // sleep, which is not worth a line.
            let wasAsleep = CGDisplayIsAsleep(CGMainDisplayID()) != 0
            var id = assertionID
            let result = IOPMAssertionDeclareUserActivity(DisplayWake.assertionName as CFString, kIOPMUserActiveLocal, &id)
            if result == kIOReturnSuccess {
                assertionID = id
                Stats.shared.bump(DisplayWake.declaredKey)
            }
            if let line = report.line(device: device, event: event, wasAsleep: wasAsleep, result: result) { print(line) }
        }
    }
}
