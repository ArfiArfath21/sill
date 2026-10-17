import Foundation
import IOKit.pwr_mgt

/// Keeps the Mac's framebuffer available for a live Sill stream. A power assertion prevents the
/// display from idling off; declaring remote user activity at stream start also wakes a display
/// that had already gone dark. The assertion is held only while at least one device is connected.
package final class DisplayActivity {
    private var assertion: IOPMAssertionID = 0
    private var wakeAssertion: IOPMAssertionID = 0
    private var active = false

    package init() {}

    package func setStreaming(_ streaming: Bool) {
        guard streaming != active else { return }
        active = streaming
        if streaming {
            var wakeAssertion: IOPMAssertionID = 0
            let wakeResult = IOPMAssertionDeclareUserActivity(
                "Sill is starting a screen stream" as CFString,
                kIOPMUserActiveRemote,
                &wakeAssertion
            )
            if wakeResult == kIOReturnSuccess {
                self.wakeAssertion = wakeAssertion
            } else {
                NSLog("Sill: could not wake the display (power management error %d)", wakeResult)
            }

            let result = IOPMAssertionCreateWithName(
                kIOPMAssertionTypePreventUserIdleDisplaySleep as CFString,
                IOPMAssertionLevel(kIOPMAssertionLevelOn),
                "Sill is streaming a Mac screen" as CFString,
                &assertion
            )
            if result != kIOReturnSuccess {
                assertion = 0
                NSLog("Sill: could not keep the display awake (power management error %d)", result)
            }
        } else {
            if assertion != 0 {
                IOPMAssertionRelease(assertion)
                assertion = 0
            }
            if wakeAssertion != 0 {
                IOPMAssertionRelease(wakeAssertion)
                wakeAssertion = 0
            }
        }
    }

    deinit {
        if assertion != 0 { IOPMAssertionRelease(assertion) }
        if wakeAssertion != 0 { IOPMAssertionRelease(wakeAssertion) }
    }
}
