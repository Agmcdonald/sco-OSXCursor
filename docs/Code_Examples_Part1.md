# Super Comic Organizer - Code Examples & Ready-to-Use Implementations

This document contains production-ready code snippets that you can copy directly into your project.

---

## Table of Contents
1. [Complete CBZ Reader Implementation](#complete-cbz-reader-implementation)
2. [Library View with Grid](#library-view-with-grid)
3. [Drag and Drop Implementation](#drag-and-drop-implementation)
4. [Database Setup with GRDB](#database-setup-with-grdb)
5. [Metadata Extraction](#metadata-extraction)
6. [File Organization Service](#file-organization-service)
7. [Settings Management](#settings-management)
8. [View Models](#view-models)

---

## Complete CBZ Reader Implementation

### ComicReaderService.swift
Create this in `Services/ComicReader/`

```swift
import Foundation
import ZIPFoundation
import AppKit // Use UIKit for iOS

// MARK: - Protocol
protocol ComicReaderProtocol {
    func loadComic(from url: URL) async throws -> Comic
    func extractCover(from url: URL) async throws -> NSImage?
    func extractPages(from url: URL) async throws -> [NSImage]
}

// MARK: - CBZ Reader Implementation
class CBZReader: ComicReaderProtocol {
    
    func loadComic(from url: URL) async throws -> Comic {
        var comic = Comic(filePath: url)
        
        // Get security-scoped access
        guard url.startAccessingSecurityScopedResource() else {
            throw ComicReaderError.accessDenied
        }
        defer { url.stopAccessingSecurityScopedResource() }
        
        // Open archive
        guard let archive = Archive(url: url, accessMode: .read) else {
            throw ComicReaderError.invalidArchive
        }
        
        // Get all image entries
        let imageEntries = getImageEntries(from: archive)
        
        // Extract cover (first image)
        if let firstEntry = imageEntries.first {
            let imageData = try extractEntry(firstEntry, from: archive)
            comic.coverImageData = imageData
        }
        
        // Look for ComicInfo.xml
        if let comicInfoEntry = archive["ComicInfo.xml"] {
            let xmlData = try extractEntry(comicInfoEntry, from: archive)
            if let metadata = try? parseComicInfo(xmlData) {
                comic.title = metadata.title
                comic.publisher = metadata.publisher
                comic.series = metadata.series
                comic.issueNumber = metadata.issue
                comic.year = metadata.year
            }
        }
        
        // Try to extract metadata from filename if not found
        if comic.title == nil {
            let metadata = extractMetadataFromFilename(url.lastPathComponent)
            comic.title = metadata.title
            comic.publisher = metadata.publisher
            comic.series = metadata.series
            comic.issueNumber = metadata.issue
            comic.year = metadata.year
        }
        
        comic.status = .processing
        return comic
    }
    
    func extractCover(from url: URL) async throws -> NSImage? {
        guard url.startAccessingSecurityScopedResource() else {
            return nil
        }
        defer { url.stopAccessingSecurityScopedResource() }
        
        guard let archive = Archive(url: url, accessMode: .read) else {
            return nil
        }
        
        let imageEntries = getImageEntries(from: archive)
        guard let firstEntry = imageEntries.first else {
            return nil
        }
        
        let imageData = try extractEntry(firstEntry, from: archive)
        return NSImage(data: imageData)
    }
    
    func extractPages(from url: URL) async throws -> [NSImage] {
        guard url.startAccessingSecurityScopedResource() else {
            throw ComicReaderError.accessDenied
        }
        defer { url.stopAccessingSecurityScopedResource() }
        
        guard let archive = Archive(url: url, accessMode: .read) else {
            throw ComicReaderError.invalidArchive
        }
        
        let imageEntries = getImageEntries(from: archive)
        var images: [NSImage] = []
        
        for entry in imageEntries {
            let imageData = try extractEntry(entry, from: archive)
            if let image = NSImage(data: imageData) {
                images.append(image)
            }
        }
        
        return images
    }
    
    // MARK: - Private Helpers
    
    private func getImageEntries(from archive: Archive) -> [Entry] {
        archive.filter { entry in
            // Skip hidden files and folders
            let path = entry.path.lowercased()
            guard !path.contains("__macosx") && !path.hasPrefix(".") else {
                return false
            }
            
            // Only include image files
            return path.hasSuffix(".jpg") ||
                   path.hasSuffix(".jpeg") ||
                   path.hasSuffix(".png") ||
                   path.hasSuffix(".gif") ||
                   path.hasSuffix(".webp")
        }.sorted { entry1, entry2 in
            // Natural sort (1, 2, 3... instead of 1, 10, 11, 2...)
            entry1.path.localizedStandardCompare(entry2.path) == .orderedAscending
        }
    }
    
    private func extractEntry(_ entry: Entry, from archive: Archive) throws -> Data {
        var data = Data()
        _ = try archive.extract(entry) { chunk in
            data.append(chunk)
        }
        return data
    }
    
    private func parseComicInfo(_ xmlData: Data) throws -> ComicMetadata {
        let parser = ComicInfoParser()
        return try parser.parse(xmlData)
    }
    
    private func extractMetadataFromFilename(_ filename: String) -> ComicMetadata {
        let extractor = FilenameMetadataExtractor()
        return extractor.extract(from: filename)
    }
}

// MARK: - PDF Reader Implementation
class PDFReader: ComicReaderProtocol {
    func loadComic(from url: URL) async throws -> Comic {
        import PDFKit
        
        var comic = Comic(filePath: url)
        
        guard url.startAccessingSecurityScopedResource() else {
            throw ComicReaderError.accessDenied
        }
        defer { url.stopAccessingSecurityScopedResource() }
        
        guard let pdfDocument = PDFDocument(url: url) else {
            throw ComicReaderError.invalidPDF
        }
        
        // Extract metadata from PDF
        if let title = pdfDocument.documentAttributes?[PDFDocumentAttribute.titleAttribute] as? String {
            comic.title = title
        }
        
        if let author = pdfDocument.documentAttributes?[PDFDocumentAttribute.authorAttribute] as? String {
            // Author might be publisher
            comic.publisher = author
        }
        
        // Extract first page as cover
        if let firstPage = pdfDocument.page(at: 0) {
            let pageRect = firstPage.bounds(for: .mediaBox)
            let renderer = NSGraphicsImageRenderer(size: pageRect.size)
            let image = renderer.image { ctx in
                NSGraphicsContext.saveGraphicsState()
                ctx.cgContext.translateBy(x: 0, y: pageRect.size.height)
                ctx.cgContext.scaleBy(x: 1.0, y: -1.0)
                firstPage.draw(with: .mediaBox, to: ctx.cgContext)
                NSGraphicsContext.restoreGraphicsState()
            }
            comic.coverImageData = image.tiffRepresentation
        }
        
        comic.status = .processing
        return comic
    }
    
    func extractCover(from url: URL) async throws -> NSImage? {
        import PDFKit
        
        guard url.startAccessingSecurityScopedResource() else {
            return nil
        }
        defer { url.stopAccessingSecurityScopedResource() }
        
        guard let pdfDocument = PDFDocument(url: url),
              let firstPage = pdfDocument.page(at: 0) else {
            return nil
        }
        
        let pageRect = firstPage.bounds(for: .mediaBox)
        let renderer = NSGraphicsImageRenderer(size: pageRect.size)
        return renderer.image { ctx in
            NSGraphicsContext.saveGraphicsState()
            ctx.cgContext.translateBy(x: 0, y: pageRect.size.height)
            ctx.cgContext.scaleBy(x: 1.0, y: -1.0)
            firstPage.draw(with: .mediaBox, to: ctx.cgContext)
            NSGraphicsContext.restoreGraphicsState()
        }
    }
    
    func extractPages(from url: URL) async throws -> [NSImage] {
        import PDFKit
        
        guard url.startAccessingSecurityScopedResource() else {
            throw ComicReaderError.accessDenied
        }
        defer { url.stopAccessingSecurityScopedResource() }
        
        guard let pdfDocument = PDFDocument(url: url) else {
            throw ComicReaderError.invalidPDF
        }
        
        var images: [NSImage] = []
        
        for pageIndex in 0..<pdfDocument.pageCount {
            if let page = pdfDocument.page(at: pageIndex) {
                let pageRect = page.bounds(for: .mediaBox)
                let renderer = NSGraphicsImageRenderer(size: pageRect.size)
                let image = renderer.image { ctx in
                    NSGraphicsContext.saveGraphicsState()
                    ctx.cgContext.translateBy(x: 0, y: pageRect.size.height)
                    ctx.cgContext.scaleBy(x: 1.0, y: -1.0)
                    page.draw(with: .mediaBox, to: ctx.cgContext)
                    NSGraphicsContext.restoreGraphicsState()
                }
                images.append(image)
            }
        }
        
        return images
    }
}

// MARK: - Supporting Types

struct ComicMetadata {
    var title: String?
    var publisher: String?
    var series: String?
    var issue: String?
    var year: Int?
    var writer: String?
    var artist: String?
    var summary: String?
}

enum ComicReaderError: LocalizedError {
    case invalidArchive
    case accessDenied
    case noImages
    case invalidMetadata
    case invalidPDF
    case unsupportedFormat
    
    var errorDescription: String? {
        switch self {
        case .invalidArchive:
            return "The file is not a valid comic archive"
        case .accessDenied:
            return "Unable to access the file"
        case .noImages:
            return "No images found in the comic"
        case .invalidMetadata:
            return "Comic metadata is invalid or corrupted"
        case .invalidPDF:
            return "The PDF file is invalid or corrupted"
        case .unsupportedFormat:
            return "This file format is not supported"
        }
    }
}

// MARK: - ComicInfo.xml Parser

class ComicInfoParser {
    func parse(_ data: Data) throws -> ComicMetadata {
        var metadata = ComicMetadata()
        
        guard let xmlString = String(data: data, encoding: .utf8) else {
            throw ComicReaderError.invalidMetadata
        }
        
        // Simple regex-based parsing (use XMLParser for production)
        metadata.title = extractValue(from: xmlString, tag: "Title")
        metadata.publisher = extractValue(from: xmlString, tag: "Publisher")
        metadata.series = extractValue(from: xmlString, tag: "Series")
        metadata.issue = extractValue(from: xmlString, tag: "Number")
        metadata.writer = extractValue(from: xmlString, tag: "Writer")
        metadata.artist = extractValue(from: xmlString, tag: "Penciller")
        metadata.summary = extractValue(from: xmlString, tag: "Summary")
        
        if let yearString = extractValue(from: xmlString, tag: "Year"),
           let year = Int(yearString) {
            metadata.year = year
        }
        
        return metadata
    }
    
    private func extractValue(from xml: String, tag: String) -> String? {
        let pattern = "<\(tag)>(.*?)</\(tag)>"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]),
              let match = regex.firstMatch(in: xml, range: NSRange(xml.startIndex..., in: xml)),
              let range = Range(match.range(at: 1), in: xml) else {
            return nil
        }
        
        return String(xml[range]).trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

// MARK: - Filename Metadata Extractor

class FilenameMetadataExtractor {
    func extract(from filename: String) -> ComicMetadata {
        var metadata = ComicMetadata()
        
        // Remove file extension
        let name = filename
            .replacingOccurrences(of: ".cbz", with: "", options: .caseInsensitive)
            .replacingOccurrences(of: ".cbr", with: "", options: .caseInsensitive)
            .replacingOccurrences(of: ".pdf", with: "", options: .caseInsensitive)
        
        // Pattern 1: "Series #123 (Year)"
        // Example: "Batman #1 (2024)"
        if let match = name.range(of: #"^(.+?)\s*#(\d+)\s*\((\d{4})\)"#, options: .regularExpression) {
            let extracted = String(name[match])
            let parts = extracted.components(separatedBy: "#")
            if parts.count >= 2 {
                metadata.series = parts[0].trimmingCharacters(in: .whitespaces)
                let issueAndYear = parts[1].components(separatedBy: "(")
                metadata.issue = issueAndYear[0].trimmingCharacters(in: .whitespaces)
                if issueAndYear.count > 1 {
                    let yearString = issueAndYear[1].replacingOccurrences(of: ")", with: "")
                    metadata.year = Int(yearString)
                }
            }
        }
        
        // Pattern 2: "Series v1 001 (Year) (Publisher)"
        // Example: "Amazing Spider-Man v1 001 (1963) (Marvel)"
        else if let match = name.range(of: #"^(.+?)\s+v\d+\s+(\d+)\s*\((\d{4})\)\s*\((.+?)\)"#, options: .regularExpression) {
            let components = parseComplexFilename(String(name[match]))
            metadata.series = components.series
            metadata.issue = components.issue
            metadata.year = components.year
            metadata.publisher = components.publisher
        }
        
        // Pattern 3: "Publisher - Series - Issue (Year)"
        // Example: "DC Comics - Batman - 001 (1940)"
        else if name.contains(" - ") {
            let parts = name.components(separatedBy: " - ")
            if parts.count >= 2 {
                metadata.publisher = parts[0].trimmingCharacters(in: .whitespaces)
                metadata.series = parts[1].trimmingCharacters(in: .whitespaces)
                if parts.count >= 3 {
                    let issueAndYear = parts[2]
                    if let yearRange = issueAndYear.range(of: #"\((\d{4})\)"#, options: .regularExpression) {
                        let yearString = String(issueAndYear[yearRange])
                            .replacingOccurrences(of: "(", with: "")
                            .replacingOccurrences(of: ")", with: "")
                        metadata.year = Int(yearString)
                    }
                    metadata.issue = issueAndYear
                        .replacingOccurrences(of: #"\(\d{4}\)"#, with: "", options: .regularExpression)
                        .trimmingCharacters(in: .whitespaces)
                }
            }
        }
        
        // Fallback: use entire filename as title
        if metadata.title == nil && metadata.series == nil {
            metadata.title = name
        }
        
        return metadata
    }
    
    private func parseComplexFilename(_ filename: String) -> (series: String?, issue: String?, year: Int?, publisher: String?) {
        var series: String?
        var issue: String?
        var year: Int?
        var publisher: String?
        
        // Extract components using regex
        if let regex = try? NSRegularExpression(pattern: #"^(.+?)\s+v\d+\s+(\d+)\s*\((\d{4})\)\s*\((.+?)\)"#) {
            let nsString = filename as NSString
            if let match = regex.firstMatch(in: filename, range: NSRange(location: 0, length: nsString.length)) {
                if match.numberOfRanges >= 5 {
                    series = nsString.substring(with: match.range(at: 1))
                    issue = nsString.substring(with: match.range(at: 2))
                    if let yearString = Int(nsString.substring(with: match.range(at: 3))) {
                        year = yearString
                    }
                    publisher = nsString.substring(with: match.range(at: 4))
                }
            }
        }
        
        return (series, issue, year, publisher)
    }
}
```

---

## Library View with Grid

### LibraryView.swift
```swift
import SwiftUI

struct LibraryView: View {
    @StateObject private var viewModel = LibraryViewModel()
    @State private var searchText = ""
    @State private var selectedComic: Comic?
    @State private var viewMode: ViewMode = .grid
    
    enum ViewMode {
        case grid, list
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Toolbar
            HStack {
                // Search
                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(.secondary)
                    TextField("Search comics...", text: $searchText)
                        .textFieldStyle(.plain)
                }
                .padding(8)
                .background(Color.gray.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 8))
                
                Spacer()
                
                // View mode toggle
                Picker("View Mode", selection: $viewMode) {
                    Label("Grid", systemImage: "square.grid.2x2")
                        .tag(ViewMode.grid)
                    Label("List", systemImage: "list.bullet")
                        .tag(ViewMode.list)
                }
                .pickerStyle(.segmented)
                .frame(width: 150)
                
                // Add button
                Button(action: { viewModel.showFilePicker = true }) {
                    Label("Add Comics", systemImage: "plus")
                }
                .buttonStyle(.borderedProminent)
            }
            .padding()
            
            Divider()
            
            // Content
            if viewModel.isLoading {
                ProgressView("Loading comics...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if filteredComics.isEmpty {
                EmptyLibraryView()
            } else {
                switch viewMode {
                case .grid:
                    LibraryGridView(comics: filteredComics, selectedComic: $selectedComic)
                case .list:
                    LibraryListView(comics: filteredComics, selectedComic: $selectedComic)
                }
            }
        }
        .sheet(item: $selectedComic) { comic in
            ComicDetailView(comic: comic)
        }
        .fileImporter(
            isPresented: $viewModel.showFilePicker,
            allowedContentTypes: [.zip, .pdf],
            allowsMultipleSelection: true
        ) { result in
            Task {
                await viewModel.handleFileImport(result: result)
            }
        }
        .task {
            await viewModel.loadComics()
        }
    }
    
    var filteredComics: [Comic] {
        if searchText.isEmpty {
            return viewModel.comics
        } else {
            return viewModel.comics.filter { comic in
                comic.displayName.localizedCaseInsensitiveContains(searchText) ||
                (comic.publisher?.localizedCaseInsensitiveContains(searchText) ?? false) ||
                (comic.series?.localizedCaseInsensitiveContains(searchText) ?? false)
            }
        }
    }
}

// MARK: - Grid View
struct LibraryGridView: View {
    let comics: [Comic]
    @Binding var selectedComic: Comic?
    
    let columns = [
        GridItem(.adaptive(minimum: 160, maximum: 200), spacing: 20)
    ]
    
    var body: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 20) {
                ForEach(comics) { comic in
                    ComicGridCard(comic: comic)
                        .onTapGesture {
                            selectedComic = comic
                        }
                }
            }
            .padding()
        }
    }
}

// MARK: - List View
struct LibraryListView: View {
    let comics: [Comic]
    @Binding var selectedComic: Comic?
    
    var body: some View {
        List(comics) { comic in
            ComicListRow(comic: comic)
                .onTapGesture {
                    selectedComic = comic
                }
        }
        .listStyle(.plain)
    }
}

// MARK: - Grid Card
struct ComicGridCard: View {
    let comic: Comic
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Cover
            if let coverData = comic.coverImageData,
               let nsImage = NSImage(data: coverData) {
                Image(nsImage: nsImage)
                    .resizable()
                    .aspectRatio(2/3, contentMode: .fill)
                    .frame(width: 160, height: 240)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .shadow(color: .black.opacity(0.3), radius: 8, x: 0, y: 4)
            } else {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.gray.opacity(0.2))
                    .frame(width: 160, height: 240)
                    .overlay(
                        VStack {
                            Image(systemName: "book.closed")
                                .font(.largeTitle)
                                .foregroundColor(.secondary)
                            Text("No Cover")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    )
            }
            
            // Title
            Text(comic.displayName)
                .font(.system(size: 13, weight: .medium))
                .lineLimit(2)
                .frame(width: 160, alignment: .leading)
            
            // Publisher
            if let publisher = comic.publisher {
                HStack(spacing: 4) {
                    Circle()
                        .fill(publisherColor(for: publisher))
                        .frame(width: 6, height: 6)
                    Text(publisher)
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
            }
            
            // Issue info
            HStack {
                if let issue = comic.issueNumber {
                    Text("#\(issue)")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
                if let year = comic.year {
                    Text("(\(year))")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
            }
        }
        .frame(width: 160)
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(NSColor.controlBackgroundColor))
        )
    }
    
    private func publisherColor(for publisher: String) -> Color {
        switch publisher.lowercased() {
        case let p where p.contains("dc"):
            return .blue
        case let p where p.contains("marvel"):
            return .red
        case let p where p.contains("image"):
            return .orange
        case let p where p.contains("dark horse"):
            return .yellow
        default:
            return .green
        }
    }
}

// MARK: - List Row
struct ComicListRow: View {
    let comic: Comic
    
    var body: some View {
        HStack(spacing: 12) {
            // Thumbnail
            if let coverData = comic.coverImageData,
               let nsImage = NSImage(data: coverData) {
                Image(nsImage: nsImage)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 40, height: 60)
                    .clipShape(RoundedRectangle(cornerRadius: 4))
            } else {
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.gray.opacity(0.2))
                    .frame(width: 40, height: 60)
            }
            
            // Info
            VStack(alignment: .leading, spacing: 4) {
                Text(comic.displayName)
                    .font(.system(size: 14, weight: .medium))
                
                HStack(spacing: 8) {
                    if let publisher = comic.publisher {
                        Text(publisher)
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                    }
                    if let issue = comic.issueNumber {
                        Text("â€¢")
                            .foregroundColor(.secondary)
                        Text("#\(issue)")
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                    }
                    if let year = comic.year {
                        Text("â€¢")
                            .foregroundColor(.secondary)
                        Text("\(year)")
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                    }
                }
            }
            
            Spacer()
            
            // Status indicator
            StatusBadge(status: comic.status)
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Empty State
struct EmptyLibraryView: View {
    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "books.vertical")
                .font(.system(size: 80))
                .foregroundColor(.gray)
            
            Text("No Comics Yet")
                .font(.title2)
                .fontWeight(.semibold)
            
            Text("Click 'Add Comics' to start building your library")
                .font(.body)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Status Badge
struct StatusBadge: View {
    let status: Comic.Status
    
    var body: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(statusColor)
                .frame(width: 8, height: 8)
            Text(status.rawValue.capitalized)
                .font(.system(size: 11))
                .foregroundColor(.secondary)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(statusColor.opacity(0.1))
        .clipShape(Capsule())
    }
    
    private var statusColor: Color {
        switch status {
        case .unprocessed:
            return .gray
        case .processing:
            return .blue
        case .organized:
            return .green
        case .error:
            return .red
        }
    }
}
```

---

## Drag and Drop Implementation

### OrganizeView.swift
```swift
import SwiftUI
import UniformTypeIdentifiers

struct OrganizeView: View {
    @StateObject private var viewModel = OrganizeViewModel()
    @State private var isDropTargeted = false
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Organize Comics")
                        .font(.title2)
                        .fontWeight(.bold)
                    Text("Drop files to automatically organize them")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                // Stats
                HStack(spacing: 20) {
                    StatView(title: "Queued", value: "\(viewModel.queuedCount)", color: .blue)
                    StatView(title: "Processing", value: "\(viewModel.processingCount)", color: .orange)
                    StatView(title: "Completed", value: "\(viewModel.completedCount)", color: .green)
                }
            }
            .padding()
            
            Divider()
            
            if viewModel.processingQueue.isEmpty {
                // Drop Zone
                dropZone
                    .frame(maxHeight: .infinity)
            } else {
                // Processing Queue
                processingQueue
            }
        }
        .fileImporter(
            isPresented: $viewModel.showFilePicker,
            allowedContentTypes: [.zip, .pdf],
            allowsMultipleSelection: true
        ) { result in
            Task {
                await viewModel.handleFileImport(result: result)
            }
        }
    }
    
    // MARK: - Drop Zone
    private var dropZone: some View {
        ZStack {
            // Background
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(
                    style: StrokeStyle(lineWidth: 3, dash: [12, 8])
                )
                .foregroundColor(isDropTargeted ? .accentColor : .gray.opacity(0.5))
                .background(
                    RoundedRectangle(cornerRadius: 16)
                        .fill(isDropTargeted ? Color.accentColor.opacity(0.1) : Color.clear)
                )
                .animation(.easeInOut(duration: 0.2), value: isDropTargeted)
            
            // Content
            VStack(spacing: 24) {
                // Icon
                ZStack {
                    Circle()
                        .fill(isDropTargeted ? Color.accentColor.opacity(0.2) : Color.gray.opacity(0.1))
                        .frame(width: 120, height: 120)
                    
                    Image(systemName: isDropTargeted ? "arrow.down.circle.fill" : "folder.badge.plus")
                        .font(.system(size: 60))
                        .foregroundColor(isDropTargeted ? .accentColor : .gray)
                        .symbolEffect(.bounce, value: isDropTargeted)
                }
                
                VStack(spacing: 8) {
                    Text(isDropTargeted ? "Release to add files" : "Drop Comic Files Here")
                        .font(.title2)
                        .fontWeight(.semibold)
                    
                    Text("Supports CBZ, PDF formats")
                        .font(.body)
                        .foregroundColor(.secondary)
                }
                
                // Browse button
                Button(action: { viewModel.showFilePicker = true }) {
                    Label("Browse Files", systemImage: "doc.badge.plus")
                        .font(.body)
                        .padding(.horizontal, 24)
                        .padding(.vertical, 12)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            }
        }
        .padding(40)
        .onDrop(of: [.fileURL], isTargeted: $isDropTargeted) { providers in
            handleDrop(providers: providers)
            return true
        }
    }
    
    // MARK: - Processing Queue
    private var processingQueue: some View {
        ScrollView {
            LazyVStack(spacing: 12) {
                ForEach(viewModel.processingQueue) { item in
                    ProcessingItemRow(item: item)
                }
            }
            .padding()
        }
    }
    
    // MARK: - Helpers
    private func handleDrop(providers: [NSItemProvider]) {
        Task {
            var urls: [URL] = []
            
            for provider in providers {
                if let url = try? await provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier) as? Data {
                    if let fileURL = URL(dataRepresentation: url, relativeTo: nil) {
                        urls.append(fileURL)
                    }
                }
            }
            
            if !urls.isEmpty {
                await viewModel.processFiles(urls: urls)
            }
        }
    }
}

// MARK: - Stat View
struct StatView: View {
    let title: String
    let value: String
    let color: Color
    
    var body: some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.title)
                .fontWeight(.bold)
                .foregroundColor(color)
            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }
}

// MARK: - Processing Item Row
struct ProcessingItemRow: View {
    let item: ProcessingItem
    
    var body: some View {
        HStack(spacing: 12) {
            // Status icon
            Group {
                switch item.status {
                case .queued:
                    Image(systemName: "clock")
                        .foregroundColor(.blue)
                case .processing:
                    ProgressView()
                        .scaleEffect(0.8)
                case .completed:
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                case .error:
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.red)
                }
            }
            .frame(width: 24, height: 24)
            
            // File info
            VStack(alignment: .leading, spacing: 4) {
                Text(item.fileName)
                    .font(.body)
                    .lineLimit(1)
                
                if let message = item.statusMessage {
                    Text(message)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            
            Spacer()
            
            // Confidence indicator
            if let confidence = item.confidence {
                ConfidenceIndicator(confidence: confidence)
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(NSColor.controlBackgroundColor))
        )
    }
}

// MARK: - Processing Item Model
struct ProcessingItem: Identifiable {
    let id: UUID
    let fileName: String
    var status: Status
    var statusMessage: String?
    var confidence: Double?
    
    enum Status {
        case queued
        case processing
        case completed
        case error
    }
}

// MARK: - Confidence Indicator
struct ConfidenceIndicator: View {
    let confidence: Double
    
    var body: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(confidenceColor)
                .frame(width: 8, height: 8)
            Text("\(Int(confidence * 100))%")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(confidenceColor.opacity(0.1))
        .clipShape(Capsule())
    }
    
    private var confidenceColor: Color {
        switch confidence {
        case 0.8...1.0:
            return .green
        case 0.5..<0.8:
            return .yellow
        default:
            return .red
        }
    }
}
```

---

## Database Setup with GRDB

### DatabaseManager.swift
```swift
import Foundation
import GRDB

class DatabaseManager {
    static let shared = DatabaseManager()
    
    private var dbQueue: DatabaseQueue?
    
    private init() {
        setupDatabase()
    }
    
    private func setupDatabase() {
        do {
            let dbPath = try getDatabasePath()
            dbQueue = try DatabaseQueue(path: dbPath.path)
            try migrator.migrate(dbQueue!)
            print("âœ… Database initialized at: \(dbPath.path)")
        } catch {
            print("âŒ Database setup error: \(error)")
        }
    }
    
    private func getDatabasePath() throws -> URL {
        let fileManager = FileManager.default
        let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let appFolder = appSupport.appendingPathComponent("SuperComicOrganizer")
        
        // Create directory if needed
        try fileManager.createDirectory(at: appFolder, withIntermediateDirectories: true)
        
        return appFolder.appendingPathComponent("comics.db")
    }
    
    private var migrator: DatabaseMigrator {
        var migrator = DatabaseMigrator()
        
        // Version 1: Initial schema
        migrator.registerMigration("v1") { db in
            try createComicsTable(db)
            try createPublisherMappingsTable(db)
            try createActivityLogTable(db)
            try createIndexes(db)
        }
        
        return migrator
    }
    
    private func createComicsTable(_ db: Database) throws {
        try db.create(table: "comics") { t in
            t.column("id", .text).primaryKey()
            t.column("file_path", .text).notNull()
            t.column("file_name", .text).notNull()
            t.column("title", .text)
            t.column("publisher", .text)
            t.column("series", .text)
            t.column("issue_number", .text)
            t.column("year", .integer)
            t.column("cover_image_data", .blob)
            t.column("status", .text).notNull()
            t.column("date_added", .datetime).notNull()
        }
    }
    
    private func createPublisherMappingsTable(_ db: Database) throws {
        try db.create(table: "publisher_mappings") { t in
            t.column("id", .text).primaryKey()
            t.column("publisher_name", .text).notNull().unique()
            t.column("aliases", .text).notNull() // JSON
            t.column("keywords", .text).notNull() // JSON
            t.column("folder_name", .text).notNull()
            t.column("times_used", .integer).defaults(to: 0)
            t.column("confidence", .real).defaults(to: 0.5)
            t.column("user_confirmed", .boolean).defaults(to: false)
            t.column("last_used", .datetime)
        }
    }
    
    private func createActivityLogTable(_ db: Database) throws {
        try db.create(table: "activity_log") { t in
            t.autoIncrementedPrimaryKey("id")
            t.column("comic_id", .text)
            t.column("action", .text).notNull()
            t.column("old_value", .text)
            t.column("new_value", .text)
            t.column("timestamp", .datetime).notNull()
            t.column("user_confirmed", .boolean).defaults(to: false)
        }
    }
    
    private func createIndexes(_ db: Database) throws {
        try db.create(index: "idx_comics_publisher", on: "comics", columns: ["publisher"])
        try db.create(index: "idx_comics_series", on: "comics", columns: ["series"])
        try db.create(index: "idx_comics_status", on: "comics", columns: ["status"])
        try db.create(index: "idx_comics_year", on: "comics", columns: ["year"])
    }
    
    // MARK: - CRUD Operations
    
    func saveComic(_ comic: Comic) async throws {
        try await dbQueue?.write { db in
            try comic.save(db)
        }
    }
    
    func fetchAllComics() async throws -> [Comic] {
        try await dbQueue?.read { db in
            try Comic.fetchAll(db)
        } ?? []
    }
    
    func fetchComics(with status: Comic.Status) async throws -> [Comic] {
        try await dbQueue?.read { db in
            try Comic.filter(Column("status") == status.rawValue).fetchAll(db)
        } ?? []
    }
    
    func updateComic(_ comic: Comic) async throws {
        try await dbQueue?.write { db in
            try comic.update(db)
        }
    }
    
    func deleteComic(_ comic: Comic) async throws {
        try await dbQueue?.write { db in
            try comic.delete(db)
        }
    }
    
    func searchComics(query: String) async throws -> [Comic] {
        try await dbQueue?.read { db in
            let pattern = "%\(query)%"
            return try Comic
                .filter(
                    Column("title").like(pattern) ||
                    Column("publisher").like(pattern) ||
                    Column("series").like(pattern)
                )
                .fetchAll(db)
        } ?? []
    }
}

// MARK: - Make Comic conform to GRDB
extension Comic: FetchableRecord, PersistableRecord {
    static let databaseTableName = "comics"
    
    enum Columns {
        static let id = Column("id")
        static let filePath = Column("file_path")
        static let fileName = Column("file_name")
        static let title = Column("title")
        static let publisher = Column("publisher")
        static let series = Column("series")
        static let issueNumber = Column("issue_number")
        static let year = Column("year")
        static let coverImageData = Column("cover_image_data")
        static let status = Column("status")
        static let dateAdded = Column("date_added")
    }
}
```

---

**This is part 1 of the code examples. The document continues with:**
- Metadata Extraction implementation
- File Organization Service
- Settings Management
- View Models with full business logic

Would you like me to continue with the remaining sections?
