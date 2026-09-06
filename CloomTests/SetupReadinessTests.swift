import XCTest
@testable import Cloom

@MainActor
final class SetupReadinessTests: XCTestCase {
    func testConfigurationRequiresAllPermissions() async {
        let checker = FakePermissionChecker(statuses: [
            .screen: .authorized,
            .camera: .authorized,
            .microphone: .denied,
        ])
        let model = AppModel(
            permissionChecker: checker,
            settingsStore: InMemorySettingsStore()
        )

        await model.refreshPermissions()

        XCTAssertFalse(model.isReadyToConfigure)
    }

    func testAllAuthorizedPermissionsEnableConfiguration() async {
        let statuses = Dictionary(
            uniqueKeysWithValues: CapturePermission.allCases.map {
                ($0, PermissionState.authorized)
            }
        )
        let model = AppModel(
            permissionChecker: FakePermissionChecker(statuses: statuses),
            settingsStore: InMemorySettingsStore()
        )

        await model.refreshPermissions()

        XCTAssertTrue(model.isReadyToConfigure)
    }

    func testScreenOnlyConfigurationIgnoresDisabledInputPermissions() async {
        var settings = RecordingSettings.default
        settings.includeCamera = false
        settings.includeMicrophone = false
        let model = AppModel(
            permissionChecker: FakePermissionChecker(statuses: [
                .screen: .authorized,
                .camera: .denied,
                .microphone: .denied,
            ]),
            settingsStore: InMemorySettingsStore(value: settings)
        )

        await model.refreshPermissions()

        XCTAssertTrue(model.hasScreenCapturePermission)
        XCTAssertTrue(model.isReadyToConfigure)
    }

    func testEnabledCameraStillRequiresPermission() async {
        var settings = RecordingSettings.default
        settings.includeMicrophone = false
        let model = AppModel(
            permissionChecker: FakePermissionChecker(statuses: [
                .screen: .authorized,
                .camera: .denied,
                .microphone: .denied,
            ]),
            settingsStore: InMemorySettingsStore(value: settings)
        )

        await model.refreshPermissions()

        XCTAssertTrue(model.hasScreenCapturePermission)
        XCTAssertFalse(model.isReadyToConfigure)
    }
}
