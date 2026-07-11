//
//  SearchBarSpaceTests.swift
//  SCO-OSXCursorUITests
//
//  Regression test: typing a space in the Library search field must insert
//  a space, not trigger the Space "open reader" shortcut (which hijacked
//  multi-word searches like "What If").
//

import XCTest

final class SearchBarSpaceTests: XCTestCase {

    @MainActor
    func testTypingMultiWordSearchWithSpaces() throws {
        let app = XCUIApplication()
        app.launch()

        // Go to the Library tab
        let libraryNav = app.staticTexts["Library"].firstMatch
        if libraryNav.waitForExistence(timeout: 10) {
            libraryNav.click()
        }

        // Click a comic card first so a comic is "focused" — this is the
        // exact repro condition: the Space shortcut only fired when
        // focusedComic != nil.
        let firstImage = app.images.firstMatch
        if firstImage.waitForExistence(timeout: 10) {
            firstImage.click()
        }

        // Find the search field and type a multi-word query
        let searchField = app.textFields["Search comics, series, publisher..."]
        XCTAssertTrue(searchField.waitForExistence(timeout: 10), "Search field not found")
        searchField.click()
        searchField.typeText("What If")

        // The field must contain the space — and the app must still be on
        // the Library screen (not the reader).
        let value = searchField.value as? String ?? ""
        XCTAssertEqual(value, "What If", "Space was swallowed: field contains '\(value)'")

        // Reader UI must not have opened (search field still exists / hittable)
        XCTAssertTrue(searchField.isHittable, "Search field vanished — reader likely opened")
    }
}
