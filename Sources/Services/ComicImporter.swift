import Foundation
import ZIPFoundation
import CoreGraphics
import AppKit

#if canImport(SharedPaneling)
import SharedPaneling

class SwiftPlatformBridge: SharedComicImporterPlatformBridge {
    func unzip(zipFilePath: String, destFolder: String) -> [String] {
        let zipURL = URL(fileURLWithPath: zipFilePath)
        let destURL = URL(fileURLWithPath: destFolder)
        do {
            try FileManager.default.unzipItem(at: zipURL, to: destURL)
            var imageURLs: [URL] = []
            let resourceKeys: [URLResourceKey] = [.isDirectoryKey]
            guard let enumerator = FileManager.default.enumerator(at: destURL, includingPropertiesForKeys: resourceKeys, options: [.skipsHiddenFiles]) else {
                return []
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
            imageURLs.sort { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
            return imageURLs.map { $0.path }
        } catch {
            return []
        }
    }

    func getPixels(imagePath: String) -> SharedComicImporterPixelData? {
        guard let nsImage = NSImage(contentsOfFile: imagePath),
              let cgImage = nsImage.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            return nil
        }
        
        let W = cgImage.width
        let H = cgImage.height
        
        let maxDimension: CGFloat = 1024.0
        let scale = min(1.0, maxDimension / CGFloat(max(W, H)))
        let targetW = max(4, Int(CGFloat(W) * scale))
        let targetH = max(4, Int(CGFloat(H) * scale))
        
        let bpp = 4
        let bpr = bpp * targetW
        var raw = [UInt8](repeating: 0, count: targetH * bpr)
        
        guard let ctx = CGContext(
            data: &raw, width: targetW, height: targetH,
            bitsPerComponent: 8, bytesPerRow: bpr,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return nil
        }
        
        ctx.interpolationQuality = .medium
        ctx.draw(cgImage, in: CGRect(x: 0, y: 0, width: targetW, height: targetH))
        
        let ktRaw = KotlinByteArray.from(raw)
        return SharedComicImporterPixelData(
            raw: ktRaw,
            width: Int32(targetW),
            height: Int32(targetH),
            bytesPerRow: Int32(bpr)
        )
    }

    func generateUuid() -> String {
        return UUID().uuidString
    }
}
#endif

public final class ComicImporter: Sendable {
    
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
        
        #if canImport(SharedPaneling)
        let bridge = SwiftPlatformBridge()
        let ktBook = SharedComicImporter.shared.importComic(
            bridge: bridge,
            zipFilePath: fileURL.path,
            destFolder: bookDir.path,
            title: title,
            author: author,
            direction: direction.toKotlin()
        )
        let book = ComicBook(from: ktBook)
        try saveMetadata(book, in: bookDir)
        return book
        #else
        
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
        
        var pages = [ComicPage?](repeating: nil, count: imageURLs.count)
        let maxConcurrentTasks = max(2, ProcessInfo.processInfo.activeProcessorCount)
        
        await withTaskGroup(of: (Int, ComicPage).self) { group in
            var index = 0
            
            // Start the first batch of tasks
            while index < min(maxConcurrentTasks, imageURLs.count) {
                let currentIdx = index
                let imgURL = imageURLs[currentIdx]
                let pageNum = currentIdx + 1
                let relativePath = imgURL.path.replacingOccurrences(of: bookDir.path + "/", with: "")
                
                group.addTask {
                    let cgImage = self.createCGImage(from: imgURL)
                    var panels: [ComicPanel] = []
                    if let cgImage = cgImage {
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
                    return (currentIdx, page)
                }
                index += 1
            }
            
            // Collect completed tasks and submit new ones
            for await (idx, page) in group {
                pages[idx] = page
                
                if index < imageURLs.count {
                    let currentIdx = index
                    let imgURL = imageURLs[currentIdx]
                    let pageNum = currentIdx + 1
                    let relativePath = imgURL.path.replacingOccurrences(of: bookDir.path + "/", with: "")
                    
                    group.addTask {
                        let cgImage = self.createCGImage(from: imgURL)
                        var panels: [ComicPanel] = []
                        if let cgImage = cgImage {
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
                        return (currentIdx, page)
                    }
                    index += 1
                }
            }
        }
        
        let finalPages = pages.compactMap { $0 }
        let coverImgPath = finalPages.first?.imagePath ?? ""
        
        let book = ComicBook(
            id: bookId,
            title: title,
            author: author,
            coverImagePath: coverImgPath,
            readingDirection: direction,
            pages: finalPages,
            isCustomImported: true
        )
        
        try saveMetadata(book, in: bookDir)
        return book
        #endif
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
