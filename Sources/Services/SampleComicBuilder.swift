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
                return books
    }
}
