import CoreGraphics
import XCTest
@testable import Cloom

final class CaptureDisplayFrameResolverTests: XCTestCase {
    private let main = CGRect(x: 0, y: 0, width: 1920, height: 1080)

    func testResolvesDisplayAboveMainScreen() {
        let above = CGRect(x: 0, y: 1080, width: 1440, height: 900)

        XCTAssertEqual(
            CaptureDisplayFrameResolver.resolve(
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

    private func resolve(_ contentRect: CGRect, _ screens: [CGRect]) -> CGRect {
        CaptureDisplayFrameResolver.resolve(
            contentRect: contentRect,
            screenFrames: screens
        )
    }
}
