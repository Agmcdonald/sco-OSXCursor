//
//  Comic+Merge.swift
//  SCO-OSXCursor
//
//  Created by Cursor AI on 11/9/25.
//

import Foundation

extension Comic {
    
    /// Merge extracted metadata onto an existing comic without overwriting user-entered values.
    /// Policy: "fill missing" (existing wins if non-empty).
    /// - Parameters:
    ///   - existing: The current persisted/in-memory comic (source of truth for user edits & reading state)
    ///   - extracted: Freshly extracted comic built from metadata/files
    /// - Returns: A merged comic safe to persist
    static func merged(existing: Comic?, extracted: Comic) -> Comic {
        guard let existing else {
            // New comic import: just ensure dates are sane.
            return Comic(
                id: extracted.id,
                filePath: extracted.filePath,
                fileName: extracted.fileName,
                bookmarkData: extracted.bookmarkData,
                
                title: extracted.title,
                publisher: extracted.publisher,
                series: extracted.series,
                issueNumber: extracted.issueNumber,
                volume: extracted.volume,
                year: extracted.year,
                
                writer: extracted.writer,
                artist: extracted.artist,
                coverArtist: extracted.coverArtist,
                summary: extracted.summary,
                
                coverImageData: extracted.coverImageData,
                
                status: extracted.status,
                currentPage: extracted.currentPage,
                totalPages: extracted.totalPages,
                lastReadDate: extracted.lastReadDate,
                
                tags: extracted.tags,
                rating: extracted.rating,
                isFavorite: extracted.isFavorite,
                preferredTransition: extracted.preferredTransition,
                
                fileSize: extracted.fileSize,
                fileType: extracted.fileType,
                
                dateAdded: extracted.dateAdded,
                dateModified: extracted.dateModified
            )
        }
        
        // Helper: treat nil/empty/whitespace as "missing"
        func preferredString(existing: String?, extracted: String?) -> String? {
            let e = existing?.trimmingCharacters(in: .whitespacesAndNewlines)
            if let e, !e.isEmpty { return existing }
            
            let x = extracted?.trimmingCharacters(in: .whitespacesAndNewlines)
            if let x, !x.isEmpty { return extracted }
            
            return nil
        }
        
        func preferredInt(existing: Int?, extracted: Int?) -> Int? {
            existing ?? extracted
        }
        
        // File-derived values: extracted should generally win because they're factual
        // But keep existing cover if extracted has none.
        let mergedCover = extracted.coverImageData ?? existing.coverImageData
        
        // Reading/user state: existing MUST win
        let mergedStatus = existing.status
        let mergedCurrentPage = existing.currentPage
        let mergedLastReadDate = existing.lastReadDate
        let mergedTags = existing.tags
        let mergedRating = existing.rating
        let mergedFavorite = existing.isFavorite
        let mergedPreferredTransition = existing.preferredTransition
        
        // Metadata: existing wins if populated
        return Comic(
            id: existing.id, // Preserve identity
            filePath: extracted.filePath, // always trust current file location
            fileName: extracted.fileName,
            bookmarkData: extracted.bookmarkData ?? existing.bookmarkData,
            
            title: preferredString(existing: existing.title, extracted: extracted.title),
            publisher: preferredString(existing: existing.publisher, extracted: extracted.publisher),
            series: preferredString(existing: existing.series, extracted: extracted.series),
            issueNumber: preferredString(existing: existing.issueNumber, extracted: extracted.issueNumber),
            volume: preferredInt(existing: existing.volume, extracted: extracted.volume),
            year: preferredInt(existing: existing.year, extracted: extracted.year),
            
            writer: preferredString(existing: existing.writer, extracted: extracted.writer),
            artist: preferredString(existing: existing.artist, extracted: extracted.artist),
            coverArtist: preferredString(existing: existing.coverArtist, extracted: extracted.coverArtist),
            summary: preferredString(existing: existing.summary, extracted: extracted.summary),
            
            coverImageData: mergedCover,
            
            status: mergedStatus,
            currentPage: mergedCurrentPage,
            totalPages: max(existing.totalPages, extracted.totalPages), // keep the larger
            lastReadDate: mergedLastReadDate,
            
            tags: mergedTags,
            rating: mergedRating,
            isFavorite: mergedFavorite,
            preferredTransition: mergedPreferredTransition,

            // A rescan re-reads the file, not the reader. The chapter index is
            // already carried over above; the passage within that chapter has
            // to come with it, or a rescan silently throws the reader back to
            // the top of the chapter they were in.
            epubChapterIndex: existing.epubChapterIndex,
            epubChapterProgress: existing.epubChapterProgress,
            epubLocatorFragment: existing.epubLocatorFragment,
            epubLocatorElement: existing.epubLocatorElement,
            epubLocatorProgress: existing.epubLocatorProgress,
            pdfReadsAsBook: existing.pdfReadsAsBook,

            fileSize: extracted.fileSize,
            fileType: extracted.fileType,
            
            dateAdded: existing.dateAdded,
            dateModified: Date() // refresh when we merge anything
        )
    }
}
