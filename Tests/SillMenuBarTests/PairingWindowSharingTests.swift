import AppKit
import XCTest
@testable import SillMenuBar

final class PairingWindowSharingTests: XCTestCase {
    @MainActor
    func testSharingDefaultsToOffAndPersistsWithoutChangingHostConfig() async throws {
        let suite = "me.saffer.sill.tests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let settings = HostSettings(defaults: defaults)
        let originalConfig = settings.config
        var hostChanges = 0
        settings.onChange = { hostChanges += 1 }

        XCTAssertFalse(settings.displayQRCodeOnRemoteDesktops)
        settings.displayQRCodeOnRemoteDesktops = true
        XCTAssertTrue(HostSettings(defaults: defaults).displayQRCodeOnRemoteDesktops)
        settings.displayQRCodeOnRemoteDesktops = false
        XCTAssertFalse(HostSettings(defaults: defaults).displayQRCodeOnRemoteDesktops)
        XCTAssertEqual(settings.config, originalConfig)
        XCTAssertEqual(hostChanges, 0, "Changing QR visibility must not restart the host")
    }

    @MainActor
    func testPairingWindowUsesSavedChoiceAndUpdatesImmediately() async throws {
        _ = NSApplication.shared
        let suite = "me.saffer.sill.tests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let model = AppModel(defaults: defaults)
        let controller = PairDeviceWindowController(model: model)
        let window = try XCTUnwrap(controller.window)
        XCTAssertEqual(window.sharingType, .none)

        // Changes reach the existing window synchronously without closing or recreating it.
        model.settings.displayQRCodeOnRemoteDesktops = true
        XCTAssertEqual(window.sharingType, .readOnly)
        model.settings.displayQRCodeOnRemoteDesktops = false
        XCTAssertEqual(window.sharingType, .none)

        // A window created after opting in must also be shareable from its first frame.
        model.settings.displayQRCodeOnRemoteDesktops = true
        let relaunchedModel = AppModel(defaults: defaults)
        let relaunchedController = PairDeviceWindowController(model: relaunchedModel)
        let relaunchedWindow = try XCTUnwrap(relaunchedController.window)
        XCTAssertEqual(relaunchedWindow.sharingType, .readOnly)
        relaunchedModel.settings.displayQRCodeOnRemoteDesktops = false
        XCTAssertEqual(relaunchedWindow.sharingType, .none)
    }
}
