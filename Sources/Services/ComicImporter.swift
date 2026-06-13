import Foundation
import ZIPFoundation
import CoreGraphics
import SwiftUI

#if canImport(UIKit)
import UIKit
typealias PlatformImage = UIImage
#elseif canImport(AppKit)
import AppKit
typealias PlatformImage = NSImage
#endif

public class ComicImporter {
    
    public static let shared = ComicImporter()
    
    private init() {}
    
    /// Returns the base directory for storing imported comics
    public static var comicsDirectory: URL {
        let paths = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)
        let dir = paths[0].appendingPathComponent("Comics", isDirectory: true)
        
        // Ensure directory exists
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true, attributes: nil)
        return dir
    }
    
    /// Imports a comic book from a local ZIP/CBZ file URL.
    /// Performs unzip, scans for images, runs auto-panel detection on each image,
    /// saves the metadata JSON, and returns the constructed ComicBook.
    public func importComic(from fileURL: URL, title: String, author: String = "Unknown", direction: ReadingDirection = .leftToRight) async throws -> ComicBook {
        let bookId = UUID()
        let bookDir = ComicImporter.comicsDirectory.appendingPathComponent(bookId.uuidString, isDirectory: true)
        
        // Ensure clean destination
        try? FileManager.default.removeItem(at: bookDir)
        try FileManager.default.createDirectory(at: bookDir, withIntermediateDirectories: true, attributes: nil)
        
        // Unzip archive
        let fileManager = FileManager.default
        try fileManager.unzipItem(at: fileURL, to: bookDir)
        
        // Scan for images recursively
        var imageURLs: [URL] = []
        let resourceKeys: [URLResourceKey] = [.isDirectoryKey]
        
        guard let enumerator = fileManager.enumerator(at: bookDir, includingPropertiesForKeys: resourceKeys, options: [.skipsHiddenFiles]) else {
            throw NSError(domain: "ComicImporter", code: 1, userInfo: [NSLocalizedDescriptionKey: "Failed to read unzipped contents"])
        }
        
        while let url = enumerator.nextObject() as? URL {
            let resourceValues = try url.resourceValues(forKeys: Set(resourceKeys))
            if let isDirectory = resourceValues.isDirectory, isDirectory {
                continue
            }
            
            let ext = url.pathExtension.lowercased()
            if ["jpg", "jpeg", "png", "webp", "gif"].contains(ext) {
                imageURLs.append(url)
            }
        }
        
        guard !imageURLs.isEmpty else {
            throw NSError(domain: "ComicImporter", code: 2, userInfo: [NSLocalizedDescriptionKey: "No comic pages found in archive"])
        }
        
        // Sort images alphabetically to ensure correct page sequence
        imageURLs.sort { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
        
        var pages: [ComicPage] = []
        
        // Process pages and run panel detection
        for (index, imgURL) in imageURLs.enumerated() {
            let pageNum = index + 1
            
            // Get relative path of image inside the book directory
            let relativePath = imgURL.path.replacingOccurrences(of: bookDir.path + "/", with: "")
            
            var panels: [ComicPanel] = []
            
            // Attempt auto-detection using CGImage
            if let cgImage = createCGImage(from: imgURL) {
                let rects = await PanelDetector.detectPanels(in: cgImage, direction: direction)
                panels = rects.enumerated().map { (panelIdx, rect) in
                    ComicPanel(rect: rect, order: panelIdx)
                }
            } else {
                // Fallback to one panel representing the whole page
                panels = [ComicPanel(rect: CGRect(x: 0, y: 0, width: 1, height: 1), order: 0)]
            }
            
            let page = ComicPage(
                pageNumber: pageNum,
                imagePath: relativePath,
                panels: panels,
                isCustomImported: true
            )
            pages.append(page)
        }
        
        // Set first page as cover (or search for cover in name)
        let coverImgPath = pages.first?.imagePath ?? ""
        
        let book = ComicBook(
            id: bookId,
            title: title,
            author: author,
            coverImagePath: coverImgPath,
            readingDirection: direction,
            pages: pages,
            isCustomImported: true
        )
        
        // Save metadata file inside the book directory
        try saveMetadata(book, in: bookDir)
        
        return book
    }
    
    /// Loads all custom imported books from the documents directory
    public func loadImportedComics() -> [ComicBook] {
        let fileManager = FileManager.default
        let comicsDir = ComicImporter.comicsDirectory
        
        guard let subdirs = try? fileManager.contentsOfDirectory(at: comicsDir, includingPropertiesForKeys: nil) else {
            return []
        }
        
        var books: [ComicBook] = []
        for dir in subdirs {
            let metadataURL = dir.appendingPathComponent("metadata.json")
            if fileManager.fileExists(atPath: metadataURL.path),
               let data = try? Data(contentsOf: metadataURL) {
                do {
                    var book = try JSONDecoder().decode(ComicBook.self, from: data)
                    // Update image paths to point to absolute directory URLs
                    // because sandbox path shifts on each app launch in iOS simulator / device
                    book.pages = book.pages.map { page in
                        var newPage = page
                        newPage.imagePath = dir.appendingPathComponent(page.imagePath).path
                        return newPage
                    }
                    book.coverImagePath = dir.appendingPathComponent(book.coverImagePath).path
                    books.append(book)
                } catch {
                    print("Error decoding metadata for \(dir.lastPathComponent): \(error)")
                }
            }
        }
        
        return books
    }
    
    /// Saves a comic's metadata to its local directory
    public func saveMetadata(_ book: ComicBook, in directory: URL) throws {
        // Strip absolute path elements before saving metadata to preserve relative pathing
        var cleanBook = book
        cleanBook.pages = book.pages.map { page in
            var p = page
            p.imagePath = URL(fileURLWithPath: p.imagePath).lastPathComponent
            return p
        }
        cleanBook.coverImagePath = URL(fileURLWithPath: cleanBook.coverImagePath).lastPathComponent
        
        let encoder = JSONEncoder()
        encoder.outputFormatting = .prettyPrinted
        let data = try encoder.encode(cleanBook)
        let metadataURL = directory.appendingPathComponent("metadata.json")
        try data.write(to: metadataURL)
    }
    
    /// Helper to convert a file URL into a CGImage in a platform-agnostic way
    private func createCGImage(from url: URL) -> CGImage? {
        #if canImport(UIKit)
        guard let uiImage = UIImage(contentsOfFile: url.path) else { return nil }
        return uiImage.cgImage
        #elseif canImport(AppKit)
        guard let nsImage = NSImage(contentsOfFile: url.path),
              let cgImage = nsImage.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            return nil
        }
        return cgImage
        #else
        return nil
        #endif
    }
}
