//
//  PDFBookTapZoneTests.swift
//  TEMPORARY — measurement harness for the PDF book reader's edge tap zones.
//  Delete after use.
//

import XCTest

final class PDFBookTapZoneTests: XCTestCase {

    func testEdgeTapTurnsPage() throws {
        let app = XCUIApplication()
        app.launch()

        // Onboarding
        let cont = app.buttons["Continue"]
        if cont.waitForExistence(timeout: 5) {
            cont.tap()
        }
        sleep(2)

        print("### LIBRARY TREE START")
        print(app.debugDescription)
        print("### LIBRARY TREE END")

        // Find the injected PDF (title: ZZZ TAP ZONE TEST)
        let book = app.descendants(matching: .any)
            .matching(NSPredicate(format: "label CONTAINS[c] 'ZZZ TAP ZONE'"))
            .firstMatch

        guard book.waitForExistence(timeout: 10) else {
            XCTFail("### RESULT: could not find the injected PDF in the library")
            return
        }
        book.tap()
        sleep(1)
        book.tap()   // some libraries need a second tap / double-tap to open
        sleep(3)

        print("### READER TREE START")
        print(app.debugDescription)
        print("### READER TREE END")

        // The reader HUD shows "<page> / <total>"
        func pageLabel() -> String? {
            for t in app.staticTexts.allElementsBoundByIndex {
                let l = t.label
                if l.contains("/"), l.contains("8") {
                    return l
                }
            }
            return nil
        }

        let before = pageLabel()
        print("### PAGE INDICATOR BEFORE: \(before ?? "nil")")

        // Tap the RIGHT edge zone
        let right = app.coordinate(withNormalizedOffset: CGVector(dx: 0.93, dy: 0.5))
        right.tap()
        sleep(2)

        let after = pageLabel()
        print("### PAGE INDICATOR AFTER RIGHT-EDGE TAP: \(after ?? "nil")")

        // Tap the LEFT edge zone to go back
        let left = app.coordinate(withNormalizedOffset: CGVector(dx: 0.07, dy: 0.5))
        left.tap()
        sleep(2)
        print("### PAGE INDICATOR AFTER LEFT-EDGE TAP: \(pageLabel() ?? "nil")")

        print("### RESULT before=\(before ?? "nil") after=\(after ?? "nil")")
    }
}
