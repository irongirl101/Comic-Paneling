import Foundation
import CoreGraphics

public enum ReadingDirection: String, Codable, CaseIterable, Identifiable {
    case leftToRight = "Left to Right"
    case rightToLeft = "Right to Left (Manga)"
    
    public var id: String { self.rawValue }
}

public struct ComicPanel: Identifiable, Codable, Equatable {
    public var id: UUID
    /// Bounding box normalized relative to the page dimensions (values between 0.0 and 1.0)
    public var rect: CGRect
    /// The order in which the panel is read
    public var order: Int
    
    public init(id: UUID = UUID(), rect: CGRect, order: Int) {
        self.id = id
        self.rect = rect
        self.order = order
    }
}

public struct ComicPage: Identifiable, Codable, Equatable {
    public var id: UUID
    public var pageNumber: Int
    /// Path or name of the image asset.
    /// For pre-packaged assets: name of the asset in bundle.
    /// For custom imported comics: full file URL to local sandbox folder.
    public var imagePath: String
    /// Panel metadata, sorted by read order.
    public var panels: [ComicPanel]
    public var isCustomImported: Bool
    
    public init(id: UUID = UUID(), pageNumber: Int, imagePath: String, panels: [ComicPanel] = [], isCustomImported: Bool = false) {
        self.id = id
        self.pageNumber = pageNumber
        self.imagePath = imagePath
        self.panels = panels
        self.isCustomImported = isCustomImported
    }
}

public struct ComicBook: Identifiable, Codable, Equatable {
    public var id: UUID
    public var title: String
    public var author: String
    public var coverImagePath: String
    public var readingDirection: ReadingDirection
    public var pages: [ComicPage]
    public var isCustomImported: Bool
    
    public var totalPanelsCount: Int {
        pages.reduce(0) { $0 + $1.panels.count }
    }
    
    public init(id: UUID = UUID(), title: String, author: String, coverImagePath: String, readingDirection: ReadingDirection = .leftToRight, pages: [ComicPage] = [], isCustomImported: Bool = false) {
        self.id = id
        self.title = title
        self.author = author
        self.coverImagePath = coverImagePath
        self.readingDirection = readingDirection
        self.pages = pages
        self.isCustomImported = isCustomImported
    }
}
