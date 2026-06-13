import Foundation
import CoreGraphics

public class SampleComicBuilder {
    
    public static func findResourcePath(subpath: String) -> String {
        #if SWIFT_PACKAGE
        let bundle = Bundle.module
        let url = URL(fileURLWithPath: subpath)
        let filename = url.deletingPathExtension().lastPathComponent
        let ext = url.pathExtension
        let directory = "Resources/" + url.deletingLastPathComponent().path
        
        if let path = bundle.path(forResource: filename, ofType: ext, inDirectory: directory) {
            return path
        }
        if let path = bundle.path(forResource: filename, ofType: ext, inDirectory: url.deletingLastPathComponent().path) {
            return path
        }
        #endif
        
        let fileManager = FileManager.default
        let srcPaths = [
            "Sources/Resources/\(subpath)",
            "./Sources/Resources/\(subpath)",
            "\(fileManager.currentDirectoryPath)/Sources/Resources/\(subpath)"
        ]
        
        for path in srcPaths {
            if fileManager.fileExists(atPath: path) {
                return URL(fileURLWithPath: path).path
            }
        }
        
        print("WARNING: Resource path not found for \(subpath)")
        return ""
    }
    
    public static func buildSampleComics() -> [ComicBook] {
        var books: [ComicBook] = []
        
        // 1. Antigravity Man (Left-to-Right)
        let antigravityId = UUID(uuidString: "11111111-1111-1111-1111-111111111111")!
        let agCover = findResourcePath(subpath: "SampleComics/antigravity/cover.png")
        let agPage1 = findResourcePath(subpath: "SampleComics/antigravity/page1.png")
        
        let agPages = [
            ComicPage(
                id: UUID(uuidString: "11111111-1111-1111-1111-222222222222")!,
                pageNumber: 1,
                imagePath: agPage1,
                panels: [
                    ComicPanel(id: UUID(), rect: CGRect(x: 0.02, y: 0.02, width: 0.96, height: 0.29), order: 0),
                    ComicPanel(id: UUID(), rect: CGRect(x: 0.02, y: 0.33, width: 0.96, height: 0.31), order: 1),
                    ComicPanel(id: UUID(), rect: CGRect(x: 0.02, y: 0.66, width: 0.96, height: 0.32), order: 2)
                ],
                isCustomImported: false
            )
        ]
        
        let agBook = ComicBook(
            id: antigravityId,
            title: "Antigravity Man",
            author: "Google DeepMind",
            coverImagePath: agCover,
            readingDirection: .leftToRight,
            pages: agPages,
            isCustomImported: false
        )
        books.append(agBook)
        
        // 2. Cyberpunk Shadow (Right-to-Left / Manga)
        let cyberpunkId = UUID(uuidString: "22222222-2222-2222-2222-222222222222")!
        let cbCover = findResourcePath(subpath: "SampleComics/cyberpunk/cover.png")
        let cbPage1 = findResourcePath(subpath: "SampleComics/cyberpunk/page1.png")
        
        let cbPages = [
            ComicPage(
                id: UUID(uuidString: "22222222-2222-2222-2222-333333333333")!,
                pageNumber: 1,
                imagePath: cbPage1,
                panels: [
                    // Right-to-Left (Manga) read sequence:
                    // 1. Top-Right: Ninja leaping
                    ComicPanel(id: UUID(), rect: CGRect(x: 0.45, y: 0.02, width: 0.53, height: 0.32), order: 0),
                    // 2. Top-Left: Text building
                    ComicPanel(id: UUID(), rect: CGRect(x: 0.02, y: 0.02, width: 0.41, height: 0.32), order: 1),
                    // 3. Middle-Right: Cityscape/cars
                    ComicPanel(id: UUID(), rect: CGRect(x: 0.54, y: 0.36, width: 0.44, height: 0.29), order: 2),
                    // 4. Middle-Left: Ninja crawling in vent
                    ComicPanel(id: UUID(), rect: CGRect(x: 0.02, y: 0.36, width: 0.50, height: 0.29), order: 3),
                    // 5. Bottom: Visor close-up
                    ComicPanel(id: UUID(), rect: CGRect(x: 0.02, y: 0.67, width: 0.96, height: 0.31), order: 4)
                ],
                isCustomImported: false
            )
        ]
        
        let cbBook = ComicBook(
            id: cyberpunkId,
            title: "Cyberpunk Shadow",
            author: "M. Tanaka",
            coverImagePath: cbCover,
            readingDirection: .rightToLeft,
            pages: cbPages,
            isCustomImported: false
        )
        books.append(cbBook)
        
        return books
    }
}
