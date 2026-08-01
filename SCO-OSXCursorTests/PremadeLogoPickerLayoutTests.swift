//
//  PremadeLogoPickerLayoutTests.swift
//  SCO-OSXCursorTests
//
//  Regression tests for the iPhone layout of PremadeLogoPickerSheet.
//  The sheet previously hard-coded a 540×480 frame (macOS sizing), which
//  overflowed the iPhone viewport and clipped the header, Cancel button,
//  and logo grid on both edges.
//

import SwiftUI
import Testing

@testable import SCO_OSXCursor

#if !os(macOS)
    @MainActor
    struct PremadeLogoPickerLayoutTests {

        private func renderedWidth(proposedWidth: CGFloat, height: CGFloat) -> CGFloat? {
            let renderer = ImageRenderer(
                content: PremadeLogoPickerSheet(publisherName: "Marvel") { _ in })
            renderer.proposedSize = ProposedViewSize(width: proposedWidth, height: height)
            return renderer.uiImage?.size.width
        }

        @Test func fitsIPhonePortraitWidth() {
            let width = renderedWidth(proposedWidth: 390, height: 844)
            #expect(width != nil)
            #expect(width ?? .infinity <= 390)
        }

        @Test func fitsIPhoneLandscapeSheetWidth() {
            // iPhone landscape sheets are inset narrower than the old fixed 540pt frame.
            let width = renderedWidth(proposedWidth: 500, height: 390)
            #expect(width != nil)
            #expect(width ?? .infinity <= 500)
        }
    }
#endif
