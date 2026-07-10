import Foundation

#if canImport(SharedPaneling)
import SharedPaneling

class SwiftStorageBridge: SharedReadingProgressManagerStorageBridge {
    func getString(key: String) -> String? {
        return UserDefaults.standard.string(forKey: key)
    }
    
    func putString(key: String, value: String?) {
        UserDefaults.standard.set(value, forKey: key)
    }
    
    func getCurrentTimeMs() -> Int64 {
        return Int64(Date().timeIntervalSince1970 * 1000)
    }
}
#endif

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
        #if canImport(SharedPaneling)
        let bridge = SwiftStorageBridge()
        let ktDict = SharedReadingProgressManager.shared.loadProgress(bridge: bridge)
        var dict: [UUID: ComicProgress] = [:]
        for (key, value) in ktDict {
            if let bookId = UUID(uuidString: key) {
                dict[bookId] = ComicProgress(from: value)
            }
        }
        self.progresses = dict
        #else
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
        #endif
    }
    
    public func saveProgress() {
        #if canImport(SharedPaneling)
        let bridge = SwiftStorageBridge()
        let ktList = progresses.values.map { $0.toKotlin() }
        SharedReadingProgressManager.shared.saveProgress(bridge: bridge, progresses: ktList)
        #else
        do {
            let encoder = JSONEncoder()
            let list = Array(progresses.values)
            let data = try encoder.encode(list)
            UserDefaults.standard.set(data, forKey: storageKey)
        } catch {
            print("Failed to encode reading progress: \(error)")
        }
        #endif
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
