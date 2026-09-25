import Foundation
import XCTest

final class TinyJSONUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testLaunchesWithFixtureAndParsesObjects() {
        let fixturePath = fixturePath(named: "sample.json")
        let app = XCUIApplication()
        app.launchArguments += ["--ui-testing", "--disable-ai", "--disable-spotlight", "--disable-file-watchers"]
        app.launchEnvironment["TINY_FIXTURE_PATH"] = fixturePath

        app.launch()

        let probe = app.staticTexts["ui-smoke-status"]
        XCTAssertTrue(probe.waitForExistence(timeout: 10))
        XCTAssertTrue(probe.label.contains("sample.json"))
        XCTAssertTrue(probe.label.contains("parsed:2"))
    }

    private func fixturePath(named name: String) -> String {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures/\(name)")
            .path
    }
}
