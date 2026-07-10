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

#if canImport(SharedPaneling)
import SharedPaneling

extension ReadingDirection {
    public func toKotlin() -> SharedPaneling.ReadingDirection {
        switch self {
        case .leftToRight: return .leftToRight
        case .rightToLeft: return .rightToLeft
        }
    }
    
    public static func fromKotlin(_ direction: SharedPaneling.ReadingDirection) -> ReadingDirection {
        switch direction {
        case .leftToRight: return .leftToRight
        case .rightToLeft: return .rightToLeft
        default: return .leftToRight
        }
    }
}

extension ComicPanel {
    public func toKotlin() -> SharedPaneling.ComicPanel {
        let pts = polygonPoints?.map { SharedPaneling.PointF(x: Double($0.x), y: Double($0.y)) }
        let kRect = SharedPaneling.RectF(
            x: Double(rect.origin.x),
            y: Double(rect.origin.y),
            width: Double(rect.width),
            height: Double(rect.height)
        )
        return SharedPaneling.ComicPanel(
            id: id.uuidString,
            rect: kRect,
            order: Int32(order),
            polygonPoints: pts
        )
    }
    
    public init(from kotlinPanel: SharedPaneling.ComicPanel) {
        let kRect = kotlinPanel.rect
        let rect = CGRect(x: kRect.x, y: kRect.y, width: kRect.width, height: kRect.height)
        let points = kotlinPanel.polygonPoints?.map { CGPoint(x: $0.x, y: $0.y) }
        self.init(
            id: UUID(uuidString: kotlinPanel.id) ?? UUID(),
            rect: rect,
            order: Int(kotlinPanel.order),
            polygonPoints: points
        )
    }
}

extension ComicPage {
    public func toKotlin() -> SharedPaneling.ComicPage {
        return SharedPaneling.ComicPage(
            id: id.uuidString,
            pageNumber: Int32(pageNumber),
            imagePath: imagePath,
            panels: panels.map { $0.toKotlin() },
            isCustomImported: isCustomImported
        )
    }
    
    public init(from kotlinPage: SharedPaneling.ComicPage) {
        self.init(
            id: UUID(uuidString: kotlinPage.id) ?? UUID(),
            pageNumber: Int(kotlinPage.pageNumber),
            imagePath: kotlinPage.imagePath,
            panels: kotlinPage.panels.map { ComicPanel(from: $0) },
            isCustomImported: kotlinPage.isCustomImported
        )
    }
}

extension ComicBook {
    public func toKotlin() -> SharedPaneling.ComicBook {
        return SharedPaneling.ComicBook(
            id: id.uuidString,
            title: title,
            author: author,
            coverImagePath: coverImagePath,
            readingDirection: readingDirection.toKotlin(),
            pages: pages.map { $0.toKotlin() },
            isCustomImported: isCustomImported
        )
    }
    
    public init(from kotlinBook: SharedPaneling.ComicBook) {
        self.init(
            id: UUID(uuidString: kotlinBook.id) ?? UUID(),
            title: kotlinBook.title,
            author: kotlinBook.author,
            coverImagePath: kotlinBook.coverImagePath,
            readingDirection: ReadingDirection.fromKotlin(kotlinBook.readingDirection),
            pages: kotlinBook.pages.map { ComicPage(from: $0) },
            isCustomImported: kotlinBook.isCustomImported
        )
    }
}
#endif
