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
                    // Panel 1: Top strip — lab scientist looking at reactor
                    ComicPanel(id: UUID(), rect: CGRect(x: 0.04, y: 0.04, width: 0.92, height: 0.28), order: 0),
                    // Panel 2: Middle strip — KA-BOOM explosion
                    ComicPanel(id: UUID(), rect: CGRect(x: 0.04, y: 0.35, width: 0.92, height: 0.30), order: 1),
                    // Panel 3: Bottom strip — scientist floating
                    ComicPanel(id: UUID(), rect: CGRect(x: 0.04, y: 0.68, width: 0.92, height: 0.28), order: 2)
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
                    // Panel 1 (read first): Top full-width — ninja leaping across city skyline
                    // Rect spans full width, top third of page
                    ComicPanel(
                        id: UUID(),
                        rect: CGRect(x: 0.04, y: 0.04, width: 0.92, height: 0.32),
                        order: 0
                    ),
                    // Panel 2 (read second): Middle-LEFT — ninja crawling through vent
                    // Right border is SLANTED: top-right corner is higher than bottom-right
                    ComicPanel(
                        id: UUID(),
                        rect: CGRect(x: 0.04, y: 0.37, width: 0.46, height: 0.32),
                        order: 1,
                        polygonPoints: [
                            CGPoint(x: 0.04, y: 0.37),  // top-left
                            CGPoint(x: 0.52, y: 0.37),  // top-right (slant starts here)
                            CGPoint(x: 0.48, y: 0.69),  // bottom-right (slant ends here)
                            CGPoint(x: 0.04, y: 0.69)   // bottom-left
                        ]
                    ),
                    // Panel 3 (read third): Middle-RIGHT — city/NEON sign scene
                    // Left border is the same slant as panel 2's right border
                    ComicPanel(
                        id: UUID(),
                        rect: CGRect(x: 0.48, y: 0.37, width: 0.48, height: 0.32),
                        order: 2,
                        polygonPoints: [
                            CGPoint(x: 0.52, y: 0.37),  // top-left (matches panel 2 top-right)
                            CGPoint(x: 0.96, y: 0.37),  // top-right
                            CGPoint(x: 0.96, y: 0.69),  // bottom-right
                            CGPoint(x: 0.48, y: 0.69)   // bottom-left (matches panel 2 bottom-right)
                        ]
                    ),
                    // Panel 4 (read last): Bottom full-width — visor close-up
                    // Top border has a slight slant matching the middle panels' bottom
                    ComicPanel(
                        id: UUID(),
                        rect: CGRect(x: 0.04, y: 0.70, width: 0.92, height: 0.26),
                        order: 3,
                        polygonPoints: [
                            CGPoint(x: 0.04, y: 0.70),  // top-left
                            CGPoint(x: 0.96, y: 0.70),  // top-right
                            CGPoint(x: 0.96, y: 0.96),  // bottom-right
                            CGPoint(x: 0.04, y: 0.96)   // bottom-left
                        ]
                    )
                ],
                isCustomImported: false
            )
        ]
        
        let cbBook = ComicBook(
            id: cyberpunkId,
            title: "Cyberpunk Shadow",
            author: "M. Tanaka",
            coverImagePath: cbCover,
            readingDirection: .leftToRight,
            pages: cbPages,
            isCustomImported: false
        )
        books.append(cbBook)
        
        return books
    }
}
