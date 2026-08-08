//
//  EPUBHeadCharsetInjectorTests.swift
//  SCO-OSXCursorTests
//
//  Regression tests for the EPUB mojibake bug: chapter HTML written to a
//  temp file and loaded via loadFileURL was parsed as Latin-1 by WebKit
//  when the source had no charset declaration, garbling UTF-8 curly
//  quotes/em-dashes. The fix injects <meta charset="utf-8"/> as the FIRST
//  element of <head> so it always falls inside the HTML parser's
//  1024-byte encoding prescan window.
//

import Foundation
import Testing

@testable import SCO_OSXCursor

struct EPUBHeadCharsetInjectorTests {

    private let injection = "<style>body { color: red; }</style>"
    private let charset = EPUBHeadCharsetInjector.charsetMeta

    private func offset(of needle: String, in html: String) -> Int? {
        guard let range = html.range(of: needle) else { return nil }
        return html.distance(from: html.startIndex, to: range.lowerBound)
    }

    // MARK: - Bare head (the failing EPUBs from the bug report)

    @Test func charsetIsFirstElementOfBareHead() {
        let html = "<html><head><title>Ch1</title></head><body><p>â€œ-free “text”</p></body></html>"
        let result = EPUBHeadCharsetInjector.inject(injection, into: html)

        let charsetPos = try! #require(offset(of: charset, in: result))
        let titlePos = try! #require(offset(of: "<title>", in: result))
        #expect(charsetPos < titlePos)
    }

    @Test func styleInjectionStaysAtEndOfHeadToPreserveCSSCascade() {
        let html = "<html><head><link rel=\"stylesheet\" href=\"book.css\"/></head><body></body></html>"
        let result = EPUBHeadCharsetInjector.inject(injection, into: html)

        let bookCSSPos = try! #require(offset(of: "book.css", in: result))
        let injectedPos = try! #require(offset(of: injection, in: result))
        let headClosePos = try! #require(offset(of: "</head>", in: result))
        #expect(bookCSSPos < injectedPos)
        #expect(injectedPos < headClosePos)
    }

    // MARK: - Head tag variants

    @Test func headWithAttributesGetsCharsetDirectlyAfterOpeningTag() {
        let html = "<html><head class=\"x\" id=\"h\"><title>T</title></head><body/></html>"
        let result = EPUBHeadCharsetInjector.inject(injection, into: html)
        #expect(result.contains("<head class=\"x\" id=\"h\">\(charset)"))
    }

    @Test func uppercaseHeadIsRecognized() {
        let html = "<HTML><HEAD><TITLE>T</TITLE></HEAD><BODY></BODY></HTML>"
        let result = EPUBHeadCharsetInjector.inject(injection, into: html)

        let charsetPos = try! #require(offset(of: charset, in: result))
        let titlePos = try! #require(offset(of: "<TITLE>", in: result))
        #expect(charsetPos < titlePos)
        // Injection must land inside the head, not be appended as a fragment wrapper.
        #expect(result.contains("<HTML>"))
        let injectedPos = try! #require(offset(of: injection, in: result))
        let headClosePos = try! #require(offset(of: "</HEAD>", in: result))
        #expect(injectedPos < headClosePos)
    }

    // MARK: - No head at all

    @Test func missingHeadIsCreatedAfterHtmlTagWithAttributes() {
        let html = "<html lang=\"en\" xmlns=\"http://www.w3.org/1999/xhtml\"><body><p>Hi</p></body></html>"
        let result = EPUBHeadCharsetInjector.inject(injection, into: html)
        #expect(
            result.contains(
                "<html lang=\"en\" xmlns=\"http://www.w3.org/1999/xhtml\"><head>\(charset)"))
        #expect(result.contains(injection))
    }

    @Test func bareFragmentIsWrappedWithCharsetFirst() {
        let html = "<p>Just a paragraph</p>"
        let result = EPUBHeadCharsetInjector.inject(injection, into: html)

        let charsetPos = try! #require(offset(of: charset, in: result))
        let injectedPos = try! #require(offset(of: injection, in: result))
        let bodyPos = try! #require(offset(of: "<p>Just a paragraph</p>", in: result))
        #expect(charsetPos < injectedPos)
        #expect(injectedPos < bodyPos)
    }

    // MARK: - Things that must NOT confuse the matcher

    @Test func headerElementIsNotMistakenForHead() {
        let html = "<html><body><header>Site header</header><p>Text</p></body></html>"
        let result = EPUBHeadCharsetInjector.inject(injection, into: html)
        // No <head> exists, so one is created after <html>; the charset must
        // NOT be shoved inside the <header> element.
        #expect(result.contains("<html><head>\(charset)"))
        #expect(result.contains("<header>Site header</header>"))
    }

    @Test func doctypeIsNotMistakenForHtmlTag() {
        let html = "<!DOCTYPE html><html><head></head><body></body></html>"
        let result = EPUBHeadCharsetInjector.inject(injection, into: html)
        #expect(result.contains("<head>\(charset)"))
        #expect(result.hasPrefix("<!DOCTYPE html>"))
    }

    // MARK: - Encoding prescan guarantees

    @Test func charsetLandsInsideFirst1024BytesDespiteLargeInjection() {
        // Simulate the real injected blob (~3.5 KB of CSS/JS): if the charset
        // were appended before </head> along with it, it would fall outside
        // the prescan window whenever the book's own head is long.
        let bigInjection = "<style>" + String(repeating: "/* filler */ ", count: 400) + "</style>"
        let longHead =
            "<head>" + String(repeating: "<meta name=\"x\" content=\"y\"/>", count: 40)
            + "</head>"
        let html = "<?xml version=\"1.0\"?><html>\(longHead)<body><p>“quotes”</p></body></html>"
        let result = EPUBHeadCharsetInjector.inject(bigInjection, into: html)

        let charsetByteOffset = try! #require(
            offset(of: EPUBHeadCharsetInjector.charsetMeta, in: result))
        #expect(charsetByteOffset < 1024)
    }

    @Test func injectedCharsetPrecedesAnySourceCharset() {
        let html =
            "<html><head><meta charset=\"iso-8859-1\"/><title>T</title></head><body></body></html>"
        let result = EPUBHeadCharsetInjector.inject(injection, into: html)

        let oursPos = try! #require(offset(of: charset, in: result))
        let legacyPos = try! #require(offset(of: "iso-8859-1", in: result))
        #expect(oursPos < legacyPos)
    }
}
