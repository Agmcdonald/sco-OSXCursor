//
//  ReaderSettings.swift
//  SCO-OSXCursor
//
//  Created by Cursor AI on 11/9/25.
//

import Foundation
import Combine
import SwiftUI

enum PageTransition: String, CaseIterable, Codable {
    case slide = "Slide"
    case fade = "Fade"
    case zoom = "Zoom"
    case curl = "Page Curl"
    case none = "None"
    
    var icon: String {
        switch self {
        case .slide: return "arrow.left.arrow.right"
        case .fade: return "circle.dotted"
        case .zoom: return "arrow.up.left.and.arrow.down.right"
        case .curl: return "book.pages"
        case .none: return "minus"
        }
    }
    
    var isAvailableOnCurrentPlatform: Bool {
        #if os(iOS)
        return true
        #else
        return self != .curl
        #endif
    }
    
    func transition(for direction: Edge) -> AnyTransition {
        switch self {
        case .slide:
            return .asymmetric(
                insertion: .move(edge: direction),
                removal: .move(edge: direction == .trailing ? .leading : .trailing)
            )
        case .fade:
            return .opacity
        case .zoom:
            return .scale.combined(with: .opacity)
        case .curl, .none:
            return .identity
        }
    }
    
    func animation() -> Animation {
        #if os(macOS)
        let baseDuration = 0.25  // Faster on macOS for performance
        #else
        let baseDuration = 0.3
        #endif
        
        switch self {
        case .slide, .zoom:
            return .easeInOut(duration: baseDuration)
        case .fade:
            return .easeInOut(duration: 0.2)
        case .curl, .none:
            return .linear(duration: 0.05)
        }
    }
}

class ReaderSettings: ObservableObject {
    static let shared = ReaderSettings()
    
    @Published var pageTransition: PageTransition  // Global default
    private var cancellables = Set<AnyCancellable>()
    
    private init() {
        if let saved = UserDefaults.standard.string(forKey: "pageTransition"),
           let transition = PageTransition(rawValue: saved) {
            self.pageTransition = transition
        } else {
            self.pageTransition = .slide
        }
        
        // Debounced save on main thread (macOS 26 safe)
        $pageTransition
            .removeDuplicates()
            .debounce(for: .milliseconds(250), scheduler: RunLoop.main)
            .sink { value in
                UserDefaults.standard.set(value.rawValue, forKey: "pageTransition")
            }
            .store(in: &cancellables)
    }
    
    /// Get the effective transition for a specific comic (uses book's preference if set, otherwise global default)
    func effectiveTransition(for comic: Comic?) -> PageTransition {
        // Check if comic has a preferred transition set
        if let comic = comic,
           let preferredString = comic.preferredTransition,
           let preferred = PageTransition(rawValue: preferredString),
           preferred.isAvailableOnCurrentPlatform {
            return preferred
        }
        
        // Fall back to global default
        return pageTransition
    }
    
    /// Save per-book preference
    func setPreferredTransition(_ transition: PageTransition?, for comic: inout Comic) {
        comic.preferredTransition = transition?.rawValue
        comic.dateModified = Date()
    }
}

