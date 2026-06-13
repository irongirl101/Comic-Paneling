import Foundation
import CoreGraphics

public enum ReadingDirection: String, Codable, CaseIterable, Identifiable {
    case leftToRight = "Left to Right"
    case rightToLeft = "Right to Left (Manga)"
    
    public var id: String { self.rawValue }
}

public struct ComicPanel: Identifiable, Codable, Equatable {
    public var id: UUID
    public var rect: CGRect
    public var order: Int
    public var polygonPoints: [CGPoint]?
    
    public init(id: UUID = UUID(), rect: CGRect, order: Int, polygonPoints: [CGPoint]? = nil) {
        self.id = id
        self.rect = rect
        self.order = order
        self.polygonPoints = polygonPoints
    }
    
    public func getPoints() -> [CGPoint] {
        if let pts = polygonPoints, pts.count == 4 {
            return pts
        }
        return [
            CGPoint(x: rect.minX, y: rect.minY),
            CGPoint(x: rect.maxX, y: rect.minY),
            CGPoint(x: rect.maxX, y: rect.maxY),
            CGPoint(x: rect.minX, y: rect.maxY)
        ]
    }
}

public struct ComicPage: Identifiable, Codable, Equatable {
    public var id: UUID
    public var pageNumber: Int
    public var imagePath: String
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

extension Collection {
    public subscript(safe index: Index) -> Element? {
        return indices.contains(index) ? self[index] : nil
    }
}
