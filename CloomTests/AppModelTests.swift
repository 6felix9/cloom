import XCTest
@testable import Cloom

@MainActor
final class AppModelTests: XCTestCase {
    func testRefreshReadsEveryRequiredPermission() async {
        let checker = FakePermissionChecker(statuses: [
            .screen: .authorized,
            .camera: .denied,
            .microphone: .authorized,
        ])
        let model = AppModel(permissionChecker: checker)

        await model.refreshPermissions()

        XCTAssertEqual(model.permissions[.screen], .authorized)
        XCTAssertEqual(model.permissions[.camera], .denied)
        XCTAssertEqual(model.permissions[.microphone], .authorized)
        XCTAssertEqual(checker.statusRequests, Set(CapturePermission.allCases))
    }

    func testRequestStoresReturnedStatus() async {
        let checker = FakePermissionChecker(statuses: [.camera: .notDetermined])
        checker.requestResults[.camera] = .authorized
        let model = AppModel(permissionChecker: checker)

        await model.request(.camera)

        XCTAssertEqual(model.permissions[.camera], .authorized)
    }
}

@MainActor
final class FakePermissionChecker: PermissionChecking {
    var statuses: [CapturePermission: PermissionState]
    var requestResults: [CapturePermission: PermissionState] = [:]
    private(set) var statusRequests: Set<CapturePermission> = []
    private(set) var openedSettings: [CapturePermission] = []

    init(statuses: [CapturePermission: PermissionState]) {
        self.statuses = statuses
    }

    func status(for permission: CapturePermission) -> PermissionState {
        statusRequests.insert(permission)
        return statuses[permission] ?? .notDetermined
    }

    func request(_ permission: CapturePermission) async -> PermissionState {
        requestResults[permission] ?? statuses[permission] ?? .notDetermined
    }

    func openSettings(for permission: CapturePermission) {
        openedSettings.append(permission)
    }
}
