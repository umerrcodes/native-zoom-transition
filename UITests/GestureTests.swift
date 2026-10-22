import XCTest

final class GestureTests: XCTestCase {
    @MainActor
    func testRecordingDemoOpensTogglesAndCloses() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launch()
        let row = app.buttons["sample-1"]
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        row.tap()
        let close = app.buttons["close-zoom-preview"]
        XCTAssertTrue(close.waitForExistence(timeout: 5))
        let image = app.descendants(matching: .any)["zoom-preview-image"].firstMatch
        XCTAssertEqual(image.value as? String, "Image 1 of 2")
        saveScreenshot(app, "preview")
        image.tap()
        XCTAssertEqual(image.value as? String, "Image 2 of 2")
        close.tap()
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        XCTAssertFalse(close.exists)
        row.tap()
        XCTAssertTrue(close.waitForExistence(timeout: 5))
        XCTAssertEqual(image.value as? String, "Image 1 of 2")
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.08, dy: 0.35))
            .press(forDuration: 0.05, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.35)), withVelocity: .slow, thenHoldForDuration: 0.1)
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        XCTAssertFalse(close.exists)
        saveScreenshot(app, "gallery")
    }

    @MainActor
    private func saveScreenshot(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
