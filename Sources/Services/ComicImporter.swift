import Foundation
import ZIPFoundation
import CoreGraphics
import AppKit

public class ComicImporter {
    
    public static let shared = ComicImporter()
    
    private init() {}
    
    public static var comicsDirectory: URL {
        let paths = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)
        let appSupportDir = paths[0].appendingPathComponent("Panels", isDirectory: true)
        let dir = appSupportDir.appendingPathComponent("Comics", isDirectory: true)
        
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true, attributes: nil)
        return dir
    }
    
    public func importComic(from fileURL: URL, title: String, author: String = "Unknown", direction: ReadingDirection = .leftToRight) async throws -> ComicBook {
        let bookId = UUID()
        let bookDir = ComicImporter.comicsDirectory.appendingPathComponent(bookId.uuidString, isDirectory: true)
        
        try? FileManager.default.removeItem(at: bookDir)
        try FileManager.default.createDirectory(at: bookDir, withIntermediateDirectories: true, attributes: nil)
        
        let fileManager = FileManager.default
        
        let isSecurityScoped = fileURL.startAccessingSecurityScopedResource()
        defer {
            if isSecurityScoped {
                fileURL.stopAccessingSecurityScopedResource()
            }
        }
        
        try fileManager.unzipItem(at: fileURL, to: bookDir)
        
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
        
        imageURLs.sort { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
        
        var pages: [ComicPage] = []
        for (index, imgURL) in imageURLs.enumerated() {
            let pageNum = index + 1
            let relativePath = imgURL.path.replacingOccurrences(of: bookDir.path + "/", with: "")
            
            var panels: [ComicPanel] = []
            if let cgImage = createCGImage(from: imgURL) {
                let rects = await PanelDetector.detectPanels(in: cgImage, direction: direction)
                panels = rects.enumerated().map { (panelIdx, rect) in
                    ComicPanel(rect: rect, order: panelIdx)
                }
            } else {
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
        
        try saveMetadata(book, in: bookDir)
        return book
    }
    
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
    
    public func saveMetadata(_ book: ComicBook, in directory: URL) throws {
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
    
    private func createCGImage(from url: URL) -> CGImage? {
        guard let nsImage = NSImage(contentsOfFile: url.path),
              let cgImage = nsImage.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            return nil
        }
        return cgImage
    }
}
