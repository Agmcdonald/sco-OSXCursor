//
//  ReaderViewModel.swift
//  SCO-OSXCursor
//
//  Created by Cursor AI on 11/6/25.
//

import Foundation
import SwiftUI
import Combine

// MARK: - Reader ViewModel
@MainActor
class ReaderViewModel: ObservableObject {
    @Published var comicBook: ComicBook?
    @Published var currentPage: Int = 0
    @Published var isLoading: Bool = false
    @Published var loadingProgress: Double = 0.0
    @Published var errorMessage: String?
    
    private let cbzReader = CBZReader()
    private let pdfReader = PDFReader()
    private var loadedPages: [Int: ComicPage] = [:]
    
    // MARK: - Load Comic (Fast - metadata only)
    func loadComic(from comic: Comic) async {
        isLoading = true
        errorMessage = nil
        loadingProgress = 0.0
        
        do {
            let reader: ComicReaderProtocol
            
            // Select appropriate reader based on file type
            switch comic.fileType {
            case .cbz:
                reader = cbzReader
            case .pdf:
                reader = pdfReader
            case .cbr:
                // CBR not yet supported
                throw ComicReaderError.invalidFormat
            }
            
            // Quick load: Just get page count first
            loadingProgress = 0.1
            let pageCount = try await reader.getPageCount(from: comic.filePath)
            
            loadingProgress = 0.3
            
            // Load only the first page to show immediately
            let fullComic = try await reader.loadComic(from: comic.filePath)
            
            loadingProgress = 1.0
            
            // Update UI
            comicBook = fullComic
            
            // Start from saved progress or beginning
            currentPage = comic.currentPage
            
        } catch let error as ComicReaderError {
            errorMessage = error.errorDescription
        } catch {
            errorMessage = "An unexpected error occurred: \(error.localizedDescription)"
        }
        
        isLoading = false
        loadingProgress = 0.0
    }
    
    // MARK: - Navigation
    func goToPage(_ page: Int) {
        guard let comic = comicBook else { return }
        currentPage = max(0, min(page, comic.totalPages - 1))
    }
    
    func nextPage() {
        guard let comic = comicBook else { return }
        if currentPage < comic.totalPages - 1 {
            currentPage += 1
        }
    }
    
    func previousPage() {
        if currentPage > 0 {
            currentPage -= 1
        }
    }
    
    // MARK: - Progress
    var progress: Double {
        guard let comic = comicBook, comic.totalPages > 0 else { return 0.0 }
        return Double(currentPage + 1) / Double(comic.totalPages)
    }
    
    var progressPercentage: String {
        "\(Int(progress * 100))%"
    }
}

