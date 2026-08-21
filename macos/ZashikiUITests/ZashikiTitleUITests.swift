//
//  ZashikiTitleUITests.swift
//  ZashikiUITests
//
//  Created by luca on 13.10.2025.
//

import XCTest

final class ZashikiTitleUITests: ZashikiCustomConfigCase {
    override func setUp() async throws {
        try await super.setUp()
        try updateConfig(#"title = "ZashikiUITestsLaunchTests""#)
    }

    @MainActor
    func testTitle() throws {
        let app = try zashikiApplication()
        app.launch()

        XCTAssertEqual(app.windows.firstMatch.title, "ZashikiUITestsLaunchTests", "Oops, `title=` doesn't work!")
    }
}
