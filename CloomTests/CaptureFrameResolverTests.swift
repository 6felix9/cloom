import CoreGraphics
import XCTest
@testable import Cloom

final class CaptureFrameResolverTests: XCTestCase {
    private let main = CGRect(x: 0, y: 0, width: 1920, height: 1080)

    func testResolvesDisplayAboveMainScreen() {
        let above = CGRect(x: 0, y: 1080, width: 1440, height: 900)

        XCTAssertEqual(
            CaptureFrameResolver.resolve(
                contentRect: CGRect(x: 0, y: -900, width: 1440, height: 900),
                screenFrames: [main, above]
            ),
            above
        )
    }

    func testResolvesDisplaysOnEverySideOfMainScreen() {
        let right = CGRect(x: 1920, y: 0, width: 1600, height: 900)
        let left = CGRect(x: -1280, y: 0, width: 1280, height: 1024)
        let below = CGRect(x: 0, y: -1024, width: 1280, height: 1024)
        let screens = [main, right, left, below]

        XCTAssertEqual(resolve(CGRect(x: 1920, y: 180, width: 1600, height: 900), screens), right)
        XCTAssertEqual(resolve(CGRect(x: -1280, y: 56, width: 1280, height: 1024), screens), left)
        XCTAssertEqual(resolve(CGRect(x: 0, y: 1080, width: 1280, height: 1024), screens), below)
    }

    func testWindowUsesScreenWithLargestIntersection() {
        let right = CGRect(x: 1920, y: 0, width: 1600, height: 900)

        XCTAssertEqual(
            resolve(CGRect(x: 1800, y: 280, width: 500, height: 500), [main, right]),
            right
        )
    }

    func testOffscreenWindowUsesNearestScreen() {
        let right = CGRect(x: 1920, y: 0, width: 1600, height: 900)

        XCTAssertEqual(
            resolve(CGRect(x: 4000, y: 180, width: 300, height: 300), [main, right]),
            right
        )
    }

    private let mainScreen = ScreenDescriptor(displayID: 1, frame: CGRect(x: 0, y: 0, width: 1920, height: 1080))
    private let rightScreen = ScreenDescriptor(displayID: 2, frame: CGRect(x: 1920, y: -200, width: 2560, height: 1440))

    func testDisplayTargetResolvesToScreenWithMatchingID() {
        XCTAssertEqual(
            CaptureFrameResolver.frame(for: .display(2), screens: [mainScreen, rightScreen], windowBounds: { _ in nil }),
            rightScreen.frame
        )
    }

    func testUnknownDisplayIsUnresolved() {
        XCTAssertNil(CaptureFrameResolver.frame(for: .display(9), screens: [mainScreen, rightScreen],
                                                windowBounds: { _ in nil }))
    }

    func testWindowTargetResolvesToWindowFrameNotItsScreen() {
        // CoreGraphics global rect: origin at the primary display's top-left, y grows down.
        let frame = CaptureFrameResolver.frame(
            for: .window(42), screens: [mainScreen, rightScreen],
            windowBounds: { $0 == 42 ? CGRect(x: 2000, y: 300, width: 800, height: 600) : nil }
        )
        XCTAssertEqual(frame, CGRect(x: 2000, y: 180, width: 800, height: 600))
    }

    func testWindowLeftOfAndAboveMainScreenFlipsIntoAppKitCoordinates() {
        let frame = CaptureFrameResolver.frame(
            for: .window(7), screens: [mainScreen],
            windowBounds: { _ in CGRect(x: -1500, y: -900, width: 1000, height: 700) }
        )
        XCTAssertEqual(frame, CGRect(x: -1500, y: 1280, width: 1000, height: 700))
    }

    func testClosedOrEmptyWindowIsUnresolved() {
        XCTAssertNil(CaptureFrameResolver.frame(for: .window(7), screens: [mainScreen], windowBounds: { _ in nil }))
        XCTAssertNil(CaptureFrameResolver.frame(for: .window(7), screens: [mainScreen], windowBounds: { _ in .zero }))
    }

    func testWindowWithoutScreensIsUnresolved() {
        XCTAssertNil(CaptureFrameResolver.frame(
            for: .window(7), screens: [],
            windowBounds: { _ in CGRect(x: 0, y: 0, width: 100, height: 100) }
        ))
    }

    private func resolve(_ contentRect: CGRect, _ screens: [CGRect]) -> CGRect {
        CaptureFrameResolver.resolve(
            contentRect: contentRect,
            screenFrames: screens
        )
    }
}
