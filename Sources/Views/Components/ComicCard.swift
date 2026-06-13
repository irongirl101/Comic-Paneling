import SwiftUI
import AppKit

public struct ComicImage: View {
    public var path: String
    
    public init(path: String) {
        self.path = path
    }
    
    public var body: some View {
        if let nsImage = NSImage(contentsOfFile: path) {
            Image(nsImage: nsImage)
                .resizable()
        } else {
            fallbackView
        }
    }
    
    private var fallbackView: some View {
        ZStack {
            Color.white.opacity(0.04)
            VStack(spacing: 8) {
                Image(systemName: "photo.badge.plus")
                    .font(.system(size: 24))
                Text("Missing Page")
                    .font(.system(size: 10, weight: .semibold))
            }
            .foregroundColor(.white.opacity(0.3))
        }
    }
}

public struct ComicCard: View {
    public var book: ComicBook
    public var progress: ComicProgress
    @State private var isHovered = false
    
    public init(book: ComicBook, progress: ComicProgress) {
        self.book = book
        self.progress = progress
    }
    
    public var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ZStack(alignment: .bottomTrailing) {
                ComicImage(path: book.coverImagePath)
                    .aspectRatio(2/3, contentMode: .fit)
                    .cornerRadius(10)
                    .shadow(color: Color.black.opacity(isHovered ? 0.5 : 0.35), radius: isHovered ? 12 : 6, x: 0, y: isHovered ? 6 : 3)
                
                if percentRead > 0 {
                    Text("\(Int(percentRead * 100))%")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(
                            Capsule()
                                .fill(percentRead >= 1.0 ? Color.green.opacity(0.8) : Color.blue.opacity(0.8))
                        )
                        .padding(6)
                }
            }
            
            VStack(alignment: .leading, spacing: 2) {
                Text(book.title)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(isHovered ? .cyan : .white)
                    .lineLimit(1)
                
                Text(book.author)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.gray)
                    .lineLimit(1)
            }
            .padding(.horizontal, 2)
            
            if percentRead > 0 {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 2.5)
                            .fill(Color.white.opacity(0.08))
                            .frame(height: 4)
                        
                        RoundedRectangle(cornerRadius: 2.5)
                            .fill(LinearGradient(
                                colors: [Color.blue, Color.cyan],
                                startPoint: .leading,
                                endPoint: .trailing
                            ))
                            .frame(width: geo.size.width * CGFloat(percentRead), height: 4)
                    }
                }
                .frame(height: 4)
                .padding(.horizontal, 2)
            }
        }
        .frame(width: 130)
        .padding(8)
        .background(isHovered ? Color.white.opacity(0.04) : Color.white.opacity(0.01))
        .cornerRadius(14)
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(isHovered ? Color.cyan.opacity(0.3) : Color.white.opacity(0.03), lineWidth: 1)
        )
        .scaleEffect(isHovered ? 1.03 : 1.0)
        .animation(.spring(response: 0.25, dampingFraction: 0.7), value: isHovered)
        .onHover { hovering in
            isHovered = hovering
        }
    }
    
    private var percentRead: Double {
        guard !book.pages.isEmpty else { return 0 }
        let totalPanels = book.totalPanelsCount
        guard totalPanels > 0 else { return 0 }
        
        if progress.isCompleted {
            return 1.0
        }
        
        var readCount = 0
        for (pIdx, page) in book.pages.enumerated() {
            if pIdx < progress.currentPageIndex {
                readCount += page.panels.count
            } else if pIdx == progress.currentPageIndex {
                readCount += min(progress.currentPanelIndex, page.panels.count)
                break
            } else {
                break
            }
        }
        
        return Double(readCount) / Double(totalPanels)
    }
}
