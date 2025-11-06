//
//  CBZReader.swift
//  SCO-OSXCursor
//
//  Created by Cursor AI on 11/6/25.
//

import Foundation
import ZIPFoundation

// MARK: - CBZ Reader
class CBZReader: ComicReaderProtocol {
    
    // MARK: - Load Comic
    func loadComic(from url: URL) async throws -> ComicBook {
        // Start accessing security-scoped resource
        let accessing = url.startAccessingSecurityScopedResource()
        defer {
            if accessing {
                url.stopAccessingSecurityScopedResource()
            }
        }
        
        // Verify file exists
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw ComicReaderError.fileNotFound
        }
        
        // Open archive
        guard let archive = Archive(url: url, accessMode: .read) else {
            throw ComicReaderError.invalidFormat
        }
        
        // Extract image entries
        let imageEntries = try getImageEntries(from: archive)
        
        guard !imageEntries.isEmpty else {
            throw ComicReaderError.noImages
        }
        
        // Sort entries naturally (1, 2, 3, 10, 11, not 1, 10, 11, 2, 3)
        let sortedEntries = imageEntries.sorted { entry1, entry2 in
            entry1.path.localizedStandardCompare(entry2.path) == .orderedAscending
        }
        
        // Extract images
        var pages: [ComicPage] = []
        for (index, entry) in sortedEntries.enumerated() {
            do {
                var imageData = Data()
                _ = try archive.extract(entry) { data in
                    imageData.append(data)
                }
                
                let page = ComicPage(
                    pageNumber: index + 1,
                    imageData: imageData,
                    fileName: entry.path
                )
                pages.append(page)
            } catch {
                print("Failed to extract page \(entry.path): \(error)")
                // Continue with other pages
                continue
            }
        }
        
        guard !pages.isEmpty else {
            throw ComicReaderError.extractionFailed
        }
        
        // Try to extract metadata
        let metadata = try? extractMetadata(from: archive)
        
        return ComicBook(sourceURL: url, pages: pages, metadata: metadata)
    }
    
    // MARK: - Extract Cover
    func extractCover(from url: URL) async throws -> Data {
        let accessing = url.startAccessingSecurityScopedResource()
        defer {
            if accessing {
                url.stopAccessingSecurityScopedResource()
            }
        }
        
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw ComicReaderError.fileNotFound
        }
        
        guard let archive = Archive(url: url, accessMode: .read) else {
            throw ComicReaderError.invalidFormat
        }
        
        let imageEntries = try getImageEntries(from: archive)
        
        guard !imageEntries.isEmpty else {
            throw ComicReaderError.noImages
        }
        
        // Sort and get first image
        let sortedEntries = imageEntries.sorted { entry1, entry2 in
            entry1.path.localizedStandardCompare(entry2.path) == .orderedAscending
        }
        
        guard let firstEntry = sortedEntries.first else {
            throw ComicReaderError.noImages
        }
        
        var coverData = Data()
        _ = try archive.extract(firstEntry) { data in
            coverData.append(data)
        }
        
        return coverData
    }
    
    // MARK: - Get Page Count
    func getPageCount(from url: URL) async throws -> Int {
        let accessing = url.startAccessingSecurityScopedResource()
        defer {
            if accessing {
                url.stopAccessingSecurityScopedResource()
            }
        }
        
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw ComicReaderError.fileNotFound
        }
        
        guard let archive = Archive(url: url, accessMode: .read) else {
            throw ComicReaderError.invalidFormat
        }
        
        let imageEntries = try getImageEntries(from: archive)
        return imageEntries.count
    }
    
    // MARK: - Helper Methods
    
    /// Get all image entries from archive
    private func getImageEntries(from archive: Archive) throws -> [Entry] {
        let imageExtensions = ["jpg", "jpeg", "png", "gif", "webp", "bmp"]
        
        let imageEntries = archive.filter { entry in
            let pathExtension = (entry.path as NSString).pathExtension.lowercased()
            return imageExtensions.contains(pathExtension) && !entry.path.hasPrefix("__MACOSX")
        }
        
        return Array(imageEntries)
    }
    
    /// Extract ComicInfo.xml metadata
    private func extractMetadata(from archive: Archive) throws -> ComicMetadata? {
        // Look for ComicInfo.xml
        guard let metadataEntry = archive["ComicInfo.xml"] else {
            return nil
        }
        
        var metadataData = Data()
        _ = try archive.extract(metadataEntry) { data in
            metadataData.append(data)
        }
        
        // Parse XML
        let decoder = XMLDecoder()
        decoder.keyDecodingStrategy = .useDefaultKeys
        
        do {
            let metadata = try decoder.decode(ComicInfoRoot.self, from: metadataData)
            return metadata.comicInfo
        } catch {
            print("Failed to parse ComicInfo.xml: \(error)")
            return nil
        }
    }
}

// MARK: - ComicInfo.xml Structure
private struct ComicInfoRoot: Codable {
    let comicInfo: ComicMetadata
    
    enum CodingKeys: String, CodingKey {
        case comicInfo = "ComicInfo"
    }
}

// MARK: - XML Decoder
private class XMLDecoder {
    var keyDecodingStrategy: KeyDecodingStrategy = .useDefaultKeys
    
    enum KeyDecodingStrategy {
        case useDefaultKeys
    }
    
    func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        // Simple XML to Plist conversion for basic ComicInfo.xml
        // This is a simplified version - a full XML parser would be better
        let parser = ComicInfoXMLParser()
        guard let metadata = parser.parse(data: data) else {
            throw ComicReaderError.metadataParsingFailed
        }
        
        // Convert to JSON then decode
        let jsonData = try JSONSerialization.data(withJSONObject: metadata, options: [])
        let decoder = JSONDecoder()
        return try decoder.decode(type, from: jsonData)
    }
}

// MARK: - Simple ComicInfo XML Parser
private class ComicInfoXMLParser: NSObject, XMLParserDelegate {
    private var currentElement = ""
    private var metadata: [String: Any] = [:]
    private var currentValue = ""
    
    func parse(data: Data) -> [String: Any]? {
        let parser = XMLParser(data: data)
        parser.delegate = self
        
        guard parser.parse() else {
            return nil
        }
        
        return ["ComicInfo": metadata]
    }
    
    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes attributeDict: [String : String] = [:]) {
        currentElement = elementName
        currentValue = ""
    }
    
    func parser(_ parser: XMLParser, foundCharacters string: String) {
        currentValue += string
    }
    
    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
        let trimmedValue = currentValue.trimmingCharacters(in: .whitespacesAndNewlines)
        
        if !trimmedValue.isEmpty && elementName != "ComicInfo" {
            // Try to convert to Int if possible
            if let intValue = Int(trimmedValue) {
                metadata[elementName] = intValue
            } else {
                metadata[elementName] = trimmedValue
            }
        }
        
        currentElement = ""
        currentValue = ""
    }
}

