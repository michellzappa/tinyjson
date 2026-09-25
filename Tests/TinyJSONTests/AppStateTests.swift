import Foundation
import XCTest
@testable import TinyJSON

final class AppStateTests: XCTestCase {
    func testLenientParsingRepairsCommonJSONMistakes() {
        let state = AppState()
        state.selectedFile = URL(fileURLWithPath: "/tmp/sample.json")
        state.content = "\u{FEFF}{\n// comment\n'name': 'TinyJSON',\n}\n"

        let parsed = state.lenientParsedJSON as? [String: String]

        XCTAssertEqual(parsed?["name"], "TinyJSON")
        XCTAssertTrue(state.jsonWarnings.contains("Stripped BOM"))
        XCTAssertTrue(state.jsonWarnings.contains(where: { $0.contains("Stripped 1 comment") }))
        XCTAssertTrue(state.jsonWarnings.contains(where: { $0.contains("Removed 1 trailing comma") }))
        XCTAssertTrue(state.jsonWarnings.contains("Replaced single quotes with double quotes"))
    }

    func testJSONLErrorReportsBadLinesAndKeepsValidObjects() {
        let state = AppState()
        state.selectedFile = URL(fileURLWithPath: "/tmp/sample.jsonl")
        state.content = """
        {"id":1}
        not json
        {"id":2}
        """

        let parsed = state.parsedJSON as? [[String: Int]]
        let error = state.jsonError

        XCTAssertEqual(parsed?.count, 2)
        XCTAssertEqual(state.errorLines, [2])
        XCTAssertEqual(error, "1 invalid line (of 3): 2 — 2 parsed OK")
    }
}
