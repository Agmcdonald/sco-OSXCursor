//
//  Notifications.swift
//  SCO-OSXCursor
//
//  Created by Antigravity on 1/12/26.
//

import Foundation

extension Notification.Name {
    static let scoToggleZoom = Notification.Name("scoToggleZoom")
    static let scoToggleControls = Notification.Name("scoToggleControls")
    static let scoOpenReaderSettings = Notification.Name("scoOpenReaderSettings")
    /// Posted by ComicPageView when zoom crosses 1× (userInfo["zoomed"]: Bool).
    /// ComicReaderView uses it to suspend swipe-down-to-dismiss while a
    /// zoomed page pans vertically.
    static let scoZoomStateChanged = Notification.Name("scoZoomStateChanged")
    /// Posted by ComicPageView when the user deliberately settles on a zoom
    /// level (pinch end, double-tap, zoom toggle). userInfo["scale"]: CGFloat.
    /// ComicReaderView persists it as the book's remembered zoom.
    static let scoZoomScaleSettled = Notification.Name("scoZoomScaleSettled")
}
