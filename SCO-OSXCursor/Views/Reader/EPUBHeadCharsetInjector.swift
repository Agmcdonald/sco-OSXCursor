//
//  EPUBHeadCharsetInjector.swift
//  SCO-OSXCursor
//
//  Chapter HTML is decoded as strict UTF-8, re-styled, written to a temp
//  file (no BOM) and loaded with WKWebView.loadFileURL. For .html chapters
//  WebKit's HTML parser then re-detects the encoding itself and defaults
//  to Latin-1 unless a charset declaration appears within its 1024-byte
//  prescan window — turning curly quotes/em-dashes into mojibake (â€œ …).
//  Apple Books is unaffected because it decodes per the EPUB spec (UTF-8).
//
//  The charset meta therefore goes IMMEDIATELY after the opening <head>
//  tag: appended at the end of the head it would sit behind the book's own
//  head content and the ~3.5 KB injected CSS/JS blob, outside the prescan
//  window. The style/script injection itself stays at the END of the head
//  so the app's CSS keeps winning the cascade against the book's own
//  stylesheets, exactly as before the fix.
//

import Foundation

enum EPUBHeadCharsetInjector {

    /// First declaration wins WebKit's prescan, so this neutralizes any
    /// legacy charset the book declares later in its head. Always correct:
    /// the content was strictly decoded from UTF-8 and is re-written as UTF-8.
    static let charsetMeta = "<meta charset=\"utf-8\"/>"

    /// Returns `html` with `charsetMeta` as the first element of the head and
    /// `headInjection` (viewport/CSS/JS) at the end of the head, creating the
    /// head — or a full document wrapper — when the source lacks one.
    static func inject(_ headInjection: String, into html: String) -> String {
        // \b keeps <header> from matching; [^>]* tolerates attributes.
        if let headOpen = html.range(
            of: "<head\\b[^>]*>", options: [.regularExpression, .caseInsensitive])
        {
            if let headClose = html.range(
                of: "</head\\s*>", options: [.regularExpression, .caseInsensitive],
                range: headOpen.upperBound..<html.endIndex)
            {
                return html[..<headOpen.upperBound] + charsetMeta
                    + html[headOpen.upperBound..<headClose.lowerBound] + headInjection
                    + html[headClose.lowerBound...]
            }
            // Malformed head that never closes — keep everything together.
            return html[..<headOpen.upperBound] + charsetMeta + headInjection
                + html[headOpen.upperBound...]
        }

        if let htmlOpen = html.range(
            of: "<html\\b[^>]*>", options: [.regularExpression, .caseInsensitive])
        {
            return html[..<htmlOpen.upperBound] + "<head>\(charsetMeta)\(headInjection)</head>"
                + html[htmlOpen.upperBound...]
        }

        return "<html><head>\(charsetMeta)\(headInjection)</head><body>\(html)</body></html>"
    }
}
