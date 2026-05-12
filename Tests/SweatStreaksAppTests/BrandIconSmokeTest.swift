import AppKit
import XCTest
@testable import SweatStreaksApp

final class BrandIconSmokeTest: XCTestCase {
    func testGitHubIconRendersNonEmpty() {
        let image = BrandIcon.github
        XCTAssertTrue(image.isTemplate)
        XCTAssertGreaterThan(image.size.width, 0)
        XCTAssertGreaterThan(nonTransparentPixelCount(of: image), 50, "GitHub mark should produce a visible silhouette")
    }

    func testLeetCodeIconRendersNonEmpty() {
        let image = BrandIcon.leetcode
        XCTAssertTrue(image.isTemplate)
        XCTAssertGreaterThan(image.size.width, 0)
        XCTAssertGreaterThan(nonTransparentPixelCount(of: image), 50, "LeetCode mark should produce a visible silhouette")
    }

    func testCodexIconRendersNonEmpty() {
        let image = BrandIcon.codex
        XCTAssertTrue(image.isTemplate)
        XCTAssertGreaterThan(image.size.width, 0)
        XCTAssertGreaterThan(nonTransparentPixelCount(of: image), 20, "Codex mark should produce a visible silhouette")
    }

    func testClaudeCodeIconRendersNonEmpty() {
        let image = BrandIcon.claudeCode
        XCTAssertTrue(image.isTemplate)
        XCTAssertGreaterThan(image.size.width, 0)
        XCTAssertGreaterThan(nonTransparentPixelCount(of: image), 20, "Claude Code mark should produce a visible silhouette")
    }

    func testCursorIconRendersNonEmpty() {
        let image = BrandIcon.cursor
        XCTAssertTrue(image.isTemplate)
        XCTAssertGreaterThan(image.size.width, 0)
        XCTAssertGreaterThan(nonTransparentPixelCount(of: image), 20, "Cursor mark should produce a visible silhouette")
    }

    private func nonTransparentPixelCount(of image: NSImage) -> Int {
        guard let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff) else { return 0 }
        var count = 0
        for x in 0..<rep.pixelsWide {
            for y in 0..<rep.pixelsHigh {
                if let color = rep.colorAt(x: x, y: y), color.alphaComponent > 0.05 {
                    count += 1
                }
            }
        }
        return count
    }
}
