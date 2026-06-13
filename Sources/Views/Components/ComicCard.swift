import SwiftUI

#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

public struct ComicImage: View {
    public var path: String
    
    public init(path: String) {
        self.path = path
    }
    
    public var body: some View {
        #if canImport(UIKit)
        if let uiImage = UIImage(contentsOfFile: path) {
            Image(uiImage: uiImage)
                .resizable()
        } else {
            fallbackView
        }
        #elseif canImport(AppKit)
        if let nsImage = NSImage(contentsOfFile: path) {
            Image(nsImage: nsImage)
                .resizable()
        } else {
            fallbackView
        }
        #else
        fallbackView
        #endif
    }
    
    private var fallbackView: some View {
        ZStack {
            Color.gray.opacity(0.15)
            VStack(spacing: 8) {
                Image(systemName: "photo.badge.plus")
                    .font(.system(size: 24))
                Text("Missing Page")
                    .font(.system(size: 10, weight: .semibold))
            }
            .foregroundColor(.white.opacity(0.4))
        }
    }
}

public struct ComicCard: View {
    public var book: ComicBook
    public var progress: ComicProgress
    
    public init(book: ComicBook, progress: ComicProgress) {
        self.book = book
        self.progress = progress
    }
    
    public var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ZStack(alignment: .bottomTrailing) {
                // Book Cover
                ComicImage(path: book.coverImagePath)
                    .aspectRatio(2/3, contentMode: .fit)
                    .cornerRadius(12)
                    .shadow(color: Color.black.opacity(0.4), radius: 8, x: 0, y: 4)
                
                // Reading progress percent bubble
                if percentRead > 0 {
                    Text("\(Int(percentRead * 100))%")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(
                            Capsule()
                                .fill(percentRead >= 1.0 ? Color.green.opacity(0.85) : Color.blue.opacity(0.85))
                        )
                        .padding(8)
                }
            }
            
            VStack(alignment: .leading, spacing: 2) {
                Text(book.title)
                    .font(.system(size: 15, weight: .bold))
                    .foregroundColor(.white)
                    .lineLimit(1)
                
                Text(book.author)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.gray)
                    .lineLimit(1)
            }
            .padding(.horizontal, 4)
            
            // Progress Bar
            if percentRead > 0 {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 3)
                            .fill(Color.white.opacity(0.1))
                            .frame(height: 5)
                        
                        RoundedRectangle(cornerRadius: 3)
                            .fill(LinearGradient(
                                colors: [Color.blue, Color.cyan],
                                startPoint: .leading,
                                endPoint: .trailing
                            ))
                            .frame(width: geo.size.width * CGFloat(percentRead), height: 5)
                    }
                }
                .frame(height: 5)
                .padding(.horizontal, 4)
            }
        }
        .frame(width: 140)
        .padding(8)
        .background(Color.white.opacity(0.02))
        .cornerRadius(16)
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.white.opacity(0.04), lineWidth: 1)
        )
    }
    
    private var percentRead: Double {
        guard !book.pages.isEmpty else { return 0 }
        
        let totalPanels = book.totalPanelsCount
        guard totalPanels > 0 else { return 0 }
        
        if progress.isCompleted {
            return 1.0
        }
        
        // Calculate reading index
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
