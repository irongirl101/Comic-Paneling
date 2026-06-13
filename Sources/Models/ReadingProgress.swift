import Foundation

public struct ComicProgress: Codable, Equatable {
    public var bookId: UUID
    public var currentPageIndex: Int
    public var currentPanelIndex: Int
    public var isCompleted: Bool
    public var lastReadDate: Date
    
    public init(bookId: UUID, currentPageIndex: Int = 0, currentPanelIndex: Int = 0, isCompleted: Bool = false, lastReadDate: Date = Date()) {
        self.bookId = bookId
        self.currentPageIndex = currentPageIndex
        self.currentPanelIndex = currentPanelIndex
        self.isCompleted = isCompleted
        self.lastReadDate = lastReadDate
    }
}

@MainActor
public class ReadingProgressManager: ObservableObject {
    @Published public var progresses: [UUID: ComicProgress] = [:]
    private let storageKey = "comic_panel_reader_progress"
    
    public static let shared = ReadingProgressManager()
    
    private init() {
        loadProgress()
    }
    
    public func loadProgress() {
        guard let data = UserDefaults.standard.data(forKey: storageKey) else { return }
        do {
            let decoder = JSONDecoder()
            let list = try decoder.decode([ComicProgress].self, from: data)
            var dict: [UUID: ComicProgress] = [:]
            for progress in list {
                dict[progress.bookId] = progress
            }
            self.progresses = dict
        } catch {
            print("Failed to decode reading progress: \(error)")
        }
    }
    
    public func saveProgress() {
        do {
            let encoder = JSONEncoder()
            let list = Array(progresses.values)
            let data = try encoder.encode(list)
            UserDefaults.standard.set(data, forKey: storageKey)
        } catch {
            print("Failed to encode reading progress: \(error)")
        }
    }
    
    public func getProgress(for bookId: UUID) -> ComicProgress {
        if let progress = progresses[bookId] {
            return progress
        }
        let newProgress = ComicProgress(bookId: bookId)
        return newProgress
    }
    
    public func updateProgress(bookId: UUID, pageIndex: Int, panelIndex: Int, isCompleted: Bool = false) {
        var progress = getProgress(for: bookId)
        progress.currentPageIndex = pageIndex
        progress.currentPanelIndex = panelIndex
        progress.isCompleted = isCompleted
        progress.lastReadDate = Date()
        
        progresses[bookId] = progress
        saveProgress()
    }
}
