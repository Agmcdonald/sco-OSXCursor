//
//  ComicReaderProtocol.swift
//  SCO-OSXCursor
//
//  Created by Cursor AI on 11/6/25.
//

import Foundation
import ImageIO
import SwiftUI

#if os(macOS)
    import AppKit
    public typealias PlatformImage = NSImage
#else
    import UIKit
    public typealias PlatformImage = UIImage
#endif

// MARK: - Comic Reader Protocol
protocol ComicReaderProtocol {
    /// Load a comic from a file URL
    func loadComic(from url: URL) async throws -> ComicBook

    /// Extract cover image from comic
    func extractCover(from url: URL) async throws -> Data

    /// Get page count without loading entire comic
    func getPageCount(from url: URL) async throws -> Int

    /// Load a specific page (lazy loading)
    func loadPage(at index: Int, from url: URL) async throws -> ComicPage
}

// MARK: - Comic Book Structure
struct ComicBook {
    let id: UUID
    let sourceURL: URL
    let pages: [ComicPage]
    let metadata: ComicMetadata?
    let totalPages: Int
    let isLazyLoaded: Bool  // True when pages load on-demand

    init(sourceURL: URL, pages: [ComicPage], metadata: ComicMetadata? = nil, isLazyLoaded: Bool = false) {
        self.id = UUID()
        self.sourceURL = sourceURL
        self.pages = pages
        self.metadata = metadata
        self.totalPages = pages.count
        self.isLazyLoaded = isLazyLoaded
    }

    /// Create a lazy-loaded comic book (CBZ/CBR/PDF — pages load on-demand)
    init(sourceURL: URL, totalPages: Int, initialPages: [ComicPage], metadata: ComicMetadata? = nil) {
        self.id = UUID()
        self.sourceURL = sourceURL
        self.pages = initialPages
        self.metadata = metadata
        self.totalPages = totalPages
        self.isLazyLoaded = true
    }
}

// MARK: - Comic Page
/// A single comic page.
///
/// `id` is deterministic (derived from the page number) so that SwiftUI view
/// identity is stable when a placeholder page is later replaced by the real,
/// loaded page. This prevents zoom resets and scroll jumps mid-load.
struct ComicPage: Identifiable {
    let pageNumber: Int
    let imageData: Data
    let fileName: String

    var id: String { "page-\(pageNumber)" }

    /// True when actual image bytes are present (placeholders have empty data).
    var isLoaded: Bool { !imageData.isEmpty }

    /// Decoded image, downsampled to the display budget and cached.
    /// Repeated access is cheap — the decode happens once per page.
    var image: PlatformImage? {
        PageImageCache.shared.image(for: self)
    }

    /// Small decoded image for thumbnail grids (cached separately).
    var thumbnailImage: PlatformImage? {
        PageImageCache.shared.thumbnail(for: self)
    }

    /// Pixel dimensions read from the image header (no full decode), cached.
    /// Used for wide-page (double-spread) detection and layout.
    var pixelSize: CGSize? {
        PageImageCache.shared.pixelSize(for: self)
    }
}

// MARK: - Page Image Cache
/// Process-wide cache of decoded page images.
///
/// Why this exists: `NSImage(data:)`/`UIImage(data:)` re-decodes the full-resolution
/// bitmap every call. Comic scans are often 3000–4000 px, so a single decoded page
/// can cost 40+ MB and tens of milliseconds — previously paid on every SwiftUI
/// render. This cache decodes once, downsampled to a sensible display budget,
/// and lets NSCache handle eviction under memory pressure (automatic on iOS).
final class PageImageCache {
    static let shared = PageImageCache()

    private let imageCache = NSCache<NSString, PlatformImage>()
    /// Per-page thumbnails decoded from in-window page data (`thumbnail(for:)`).
    private let pageThumbnailCache = NSCache<NSString, PlatformImage>()
    /// Book-keyed thumbnails for the All Pages grid / filmstrip. Kept in its own
    /// cache so large library covers can never evict a book's grid thumbnails
    /// (which previously caused most cells to stay stuck on the spinner).
    private let gridThumbnailCache = NSCache<NSString, PlatformImage>()
    /// Library / dashboard cover images (decoded at up to 640 px, ~2.4 MB each).
    private let coverCache = NSCache<NSString, PlatformImage>()
    private let sizeCache = NSCache<NSString, NSValue>()
    /// Serial queue for best-effort disk persistence of grid thumbnails.
    private let diskQueue = DispatchQueue(label: "PageImageCache.gridThumbnailDisk", qos: .utility)

    /// Maximum pixel dimension for full-page decodes.
    /// Large enough for 4x zoom on retina displays without holding raw scan sizes.
    private let maxPageDimension: CGFloat
    private let maxThumbnailDimension: CGFloat = 320

    private init() {
        #if os(macOS)
            maxPageDimension = 3200
            imageCache.totalCostLimit = 512 * 1024 * 1024  // 512 MB
        #else
            maxPageDimension = 2600
            imageCache.totalCostLimit = 160 * 1024 * 1024  // 160 MB
        #endif
        // Per-page thumbnails are transient; a modest budget is plenty.
        pageThumbnailCache.totalCostLimit = 48 * 1024 * 1024  // 48 MB
        // Grid thumbnails need to hold a whole book at once (~0.6 MB each at
        // 320 px → ~300+ pages at 192 MB). Sized so a book's grid never evicts
        // itself mid-scroll. Disk persistence backs this up across evictions.
        #if os(macOS)
            gridThumbnailCache.totalCostLimit = 192 * 1024 * 1024  // 192 MB
            coverCache.totalCostLimit = 96 * 1024 * 1024  // 96 MB
        #else
            gridThumbnailCache.totalCostLimit = 96 * 1024 * 1024  // 96 MB
            coverCache.totalCostLimit = 48 * 1024 * 1024  // 48 MB
        #endif
        sizeCache.countLimit = 4096
    }

    // MARK: Keys

    private func key(for page: ComicPage) -> NSString {
        // fileName + byte count disambiguates pages across different books
        // and distinguishes placeholder (empty) from loaded data.
        "\(page.fileName)|\(page.pageNumber)|\(page.imageData.count)" as NSString
    }

    // MARK: Public API

    func image(for page: ComicPage) -> PlatformImage? {
        guard page.isLoaded else { return nil }
        let k = key(for: page)
        if let cached = imageCache.object(forKey: k) { return cached }
        guard let decoded = Self.decodeDownsampled(page.imageData, maxDimension: maxPageDimension) else {
            return nil
        }
        imageCache.setObject(decoded, forKey: k, cost: Self.cost(of: decoded))
        return decoded
    }

    func thumbnail(for page: ComicPage) -> PlatformImage? {
        guard page.isLoaded else { return nil }
        let k = key(for: page)
        if let cached = pageThumbnailCache.object(forKey: k) { return cached }
        guard let decoded = Self.decodeDownsampled(page.imageData, maxDimension: maxThumbnailDimension) else {
            return nil
        }
        pageThumbnailCache.setObject(decoded, forKey: k, cost: Self.cost(of: decoded))
        return decoded
    }

    /// Reads pixel dimensions from the image header only — no bitmap decode.
    func pixelSize(for page: ComicPage) -> CGSize? {
        guard page.isLoaded else { return nil }
        let k = key(for: page)
        if let cached = sizeCache.object(forKey: k) {
            #if os(macOS)
                return cached.sizeValue
            #else
                return cached.cgSizeValue
            #endif
        }
        guard
            let source = CGImageSourceCreateWithData(
                page.imageData as CFData,
                [kCGImageSourceShouldCache: false] as CFDictionary),
            let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [String: Any],
            let width = props[kCGImagePropertyPixelWidth as String] as? NSNumber,
            let height = props[kCGImagePropertyPixelHeight as String] as? NSNumber
        else { return nil }
        let size = CGSize(width: CGFloat(truncating: width), height: CGFloat(truncating: height))
        #if os(macOS)
            sizeCache.setObject(NSValue(size: size), forKey: k)
        #else
            sizeCache.setObject(NSValue(cgSize: size), forKey: k)
        #endif
        return size
    }

    /// Pre-decode a page off the caller's thread so the first render is instant.
    func warm(_ page: ComicPage) {
        guard page.isLoaded else { return }
        let k = key(for: page)
        guard imageCache.object(forKey: k) == nil else { return }
        _ = image(for: page)
    }

    // MARK: Book-keyed thumbnails (for filmstrip / All Pages grid)
    //
    // These survive page-data eviction: once a page's thumbnail has been
    // generated, it stays available (until NSCache evicts it) even after the
    // raw page data leaves the reading window. Keyed by book path + page index
    // so they never need the page bytes to look up.

    private func bookKey(_ bookPath: String, _ pageIndex: Int) -> NSString {
        "\(bookPath)#\(pageIndex)" as NSString
    }

    /// Memory-only grid-thumbnail lookup. Safe to call synchronously on the
    /// main thread during rendering (no disk I/O here — see `diskThumbnail`).
    func cachedThumbnail(bookPath: String, pageIndex: Int) -> PlatformImage? {
        gridThumbnailCache.object(forKey: bookKey(bookPath, pageIndex))
    }

    func storeThumbnail(_ image: PlatformImage, bookPath: String, pageIndex: Int) {
        gridThumbnailCache.setObject(
            image, forKey: bookKey(bookPath, pageIndex), cost: Self.cost(of: image))
        // Best-effort persistence so an eviction reloads from disk instead of
        // re-extracting the page from the archive.
        diskQueue.async { [weak self] in
            self?.writeGridThumbnailToDisk(image, bookPath: bookPath, pageIndex: pageIndex)
        }
    }

    /// Disk lookup for a grid thumbnail. Decodes from disk, so callers MUST
    /// invoke this off the main thread. On a hit it promotes the image back
    /// into the in-memory grid cache so later renders are instant.
    func diskThumbnail(bookPath: String, pageIndex: Int) -> PlatformImage? {
        guard let url = gridThumbnailDiskURL(bookPath: bookPath, pageIndex: pageIndex),
            let data = try? Data(contentsOf: url), !data.isEmpty,
            let image = Self.platformImage(from: data)
        else { return nil }
        gridThumbnailCache.setObject(
            image, forKey: bookKey(bookPath, pageIndex), cost: Self.cost(of: image))
        return image
    }

    /// Decode a small thumbnail directly from raw image bytes.
    func makeThumbnail(from data: Data) -> PlatformImage? {
        Self.decodeDownsampled(data, maxDimension: maxThumbnailDimension)
    }

    // MARK: Library covers

    /// Decoded cover for the library grid, downsampled and cached by comic ID.
    /// Previously every grid cell re-decoded the full-resolution cover bytes
    /// on every SwiftUI render.
    func coverImage(from data: Data, cacheKey: String) -> PlatformImage? {
        guard !data.isEmpty else { return nil }
        let k = "cover|\(cacheKey)|\(data.count)" as NSString
        if let cached = coverCache.object(forKey: k) { return cached }
        guard let decoded = Self.decodeDownsampled(data, maxDimension: 640) else { return nil }
        coverCache.setObject(decoded, forKey: k, cost: Self.cost(of: decoded))
        return decoded
    }

    /// Downsample raw cover bytes to a storage-friendly JPEG (max 800 px).
    /// Used at import time so the database stores ~100 KB covers instead of
    /// multi-MB full-resolution scans.
    static func storageCoverData(from data: Data) -> Data? {
        guard let image = decodeDownsampled(data, maxDimension: 800) else { return nil }
        return jpegData(from: image, quality: 0.85)
    }

    /// Platform-independent JPEG encoding.
    static func jpegData(from image: PlatformImage, quality: CGFloat) -> Data? {
        #if os(macOS)
            guard let tiff = image.tiffRepresentation,
                let rep = NSBitmapImageRep(data: tiff)
            else { return nil }
            return rep.representation(
                using: .jpeg, properties: [.compressionFactor: quality])
        #else
            return image.jpegData(compressionQuality: quality)
        #endif
    }

    func removeAll() {
        imageCache.removeAllObjects()
        pageThumbnailCache.removeAllObjects()
        gridThumbnailCache.removeAllObjects()
        coverCache.removeAllObjects()
        sizeCache.removeAllObjects()
    }

    // MARK: Disk-backed grid thumbnails

    /// Directory holding persisted grid thumbnails. A `static let` so it is
    /// initialized exactly once in a thread-safe way (this cache is touched
    /// from several background threads).
    private static let gridThumbnailDir: URL? = {
        let fm = FileManager.default
        guard let base = fm.urls(for: .cachesDirectory, in: .userDomainMask).first
        else { return nil }
        let dir = base.appendingPathComponent("GridThumbnails", isDirectory: true)
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()

    private func gridThumbnailDiskURL(bookPath: String, pageIndex: Int) -> URL? {
        guard let dir = Self.gridThumbnailDir else { return nil }
        return dir.appendingPathComponent("\(Self.stableHash(bookPath))-\(pageIndex).jpg")
    }

    private func writeGridThumbnailToDisk(
        _ image: PlatformImage, bookPath: String, pageIndex: Int
    ) {
        guard let url = gridThumbnailDiskURL(bookPath: bookPath, pageIndex: pageIndex),
            let data = Self.jpegData(from: image, quality: 0.8)
        else { return }
        try? data.write(to: url, options: .atomic)
    }

    /// Stable (launch-independent) hash for keying disk files by book path.
    /// Swift's `Hasher` is randomized per process, so it can't be used here.
    private static func stableHash(_ string: String) -> String {
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325  // FNV-1a 64-bit offset basis
        for byte in string.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x0000_0100_0000_01b3  // FNV prime
        }
        return String(hash, radix: 16)
    }

    private static func platformImage(from data: Data) -> PlatformImage? {
        #if os(macOS)
            return NSImage(data: data)
        #else
            return UIImage(data: data)
        #endif
    }

    // MARK: Decoding

    /// Decode image data with ImageIO, downsampling to `maxDimension` if larger.
    /// Never upscales. Produces a fully-decoded bitmap (no deferred decompression).
    ///
    /// ImageIO's budget limits the LONGEST side, which would crush the short
    /// side of very tall webtoon strips (e.g. 1600x20000 → 208x2600, badly
    /// pixelated). For extreme aspect ratios the budget is raised so the
    /// SHORT side keeps usable resolution, with a hard cap on the long side.
    private static func decodeDownsampled(_ data: Data, maxDimension: CGFloat) -> PlatformImage? {
        guard !data.isEmpty,
            let source = CGImageSourceCreateWithData(
                data as CFData,
                [kCGImageSourceShouldCache: false] as CFDictionary)
        else { return nil }

        var budget = maxDimension

        // Aspect-aware budget for full-page decodes (skip for small thumbnails)
        if maxDimension > 1000,
            let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [String: Any],
            let w = props[kCGImagePropertyPixelWidth as String] as? NSNumber,
            let h = props[kCGImagePropertyPixelHeight as String] as? NSNumber
        {
            let width = CGFloat(truncating: w)
            let height = CGFloat(truncating: h)
            let longSide = max(width, height)
            let shortSide = min(width, height)
            if shortSide > 0 {
                let ratio = longSide / shortSide
                if ratio > 2.0 {
                    // Keep the short side around 55% of the normal budget,
                    // cap the long side at 12k px (memory / GPU texture limits)
                    let shortTarget = maxDimension * 0.55
                    budget = min(longSide, min(shortTarget * ratio, 12000))
                }
            }
        }

        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: budget,
        ]

        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
        else { return nil }

        #if os(macOS)
            return NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
        #else
            return UIImage(cgImage: cgImage)
        #endif
    }

    private static func cost(of image: PlatformImage) -> Int {
        #if os(macOS)
            let size = image.size
        #else
            let size = CGSize(
                width: image.size.width * image.scale,
                height: image.size.height * image.scale)
        #endif
        return Int(size.width * size.height * 4)
    }
}

// MARK: - Comic Metadata
// Note: ComicMetadata is now defined in Services/Metadata/ComicMetadata.swift
// for a more comprehensive metadata model supporting ComicInfo.xml standard

// MARK: - Comic Reader Errors
enum ComicReaderError: LocalizedError {
    case fileNotFound
    case accessDenied
    case invalidFormat
    case corruptedFile
    case noImages
    case extractionFailed
    case metadataParsingFailed

    var errorDescription: String? {
        switch self {
        case .fileNotFound:
            return "Comic file not found"
        case .accessDenied:
            return "Access denied. Please grant permission to read this file."
        case .invalidFormat:
            return "Invalid or unsupported comic file format"
        case .corruptedFile:
            return "Comic file is corrupted or incomplete"
        case .noImages:
            return "No images found in comic file"
        case .extractionFailed:
            return "Failed to extract comic contents"
        case .metadataParsingFailed:
            return "Failed to parse comic metadata"
        }
    }
}
