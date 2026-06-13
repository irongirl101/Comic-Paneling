import SwiftUI

public enum ViewMode: String, Codable, CaseIterable {
    case guided = "Guided Spotlight"
    case focus = "Focused Crop"
}

public struct ReaderView: View {
    @Environment(\.dismiss) var dismiss
    
    @State public var book: ComicBook
    @State private var currentPageIndex: Int = 0
    @State private var currentPanelIndex: Int = 0
    @State private var viewMode: ViewMode = .guided
    
    @State private var showControls: Bool = true
    @State private var showEditor: Bool = false
    
    public init(book: ComicBook) {
        self._book = State(initialValue: book)
    }
    
    public var body: some View {
        let isRTL = book.readingDirection == .rightToLeft
        
        ZStack {
            Color.black.edgesIgnoringSafeArea(.all)
            
            // Reading area
            if !book.pages.isEmpty {
                let currentPage = book.pages[currentPageIndex]
                
                ZStack {
                    if viewMode == .guided {
                        GuidedView(page: currentPage, activePanelIndex: currentPanelIndex)
                    } else {
                        FocusView(page: currentPage, activePanelIndex: currentPanelIndex)
                    }
                    
                    // Reading Navigation Tap Zones
                    HStack(spacing: 0) {
                        // Left Tap Zone
                        Color.clear
                            .contentShape(Rectangle())
                            .frame(width: 80)
                            .onTapGesture {
                                if isRTL {
                                    goToNextPanel()
                                } else {
                                    goToPreviousPanel()
                                }
                            }
                        
                        // Center Toggle controls zone
                        Color.clear
                            .contentShape(Rectangle())
                            .onTapGesture {
                                withAnimation(.easeInOut(duration: 0.25)) {
                                    showControls.toggle()
                                }
                            }
                        
                        // Right Tap Zone
                        Color.clear
                            .contentShape(Rectangle())
                            .frame(width: 80)
                            .onTapGesture {
                                if isRTL {
                                    goToPreviousPanel()
                                } else {
                                    goToNextPanel()
                                }
                            }
                    }
                }
                .gesture(
                    DragGesture(minimumDistance: 15)
                        .onEnded { value in
                            let threshold: CGFloat = 30
                            if value.translation.width < -threshold {
                                // Swipe left
                                if isRTL {
                                    goToPreviousPanel()
                                } else {
                                    goToNextPanel()
                                }
                            } else if value.translation.width > threshold {
                                // Swipe right
                                if isRTL {
                                    goToNextPanel()
                                } else {
                                    goToPreviousPanel()
                                }
                            }
                        }
                )
            } else {
                VStack(spacing: 12) {
                    Image(systemName: "magazine")
                        .font(.system(size: 48))
                        .foregroundColor(.gray)
                    Text("No pages in this comic book.")
                        .foregroundColor(.white)
                }
            }
            
            // Controls Overlay
            if showControls && !book.pages.isEmpty {
                VStack(spacing: 0) {
                    // Top HUD Bar
                    HStack {
                        Button(action: { dismiss() }) {
                            Image(systemName: "chevron.left")
                                .font(.system(size: 18, weight: .bold))
                                .foregroundColor(.white)
                        }
                        
                        VStack(alignment: .leading, spacing: 2) {
                            Text(book.title)
                                .font(.system(size: 16, weight: .bold))
                                .foregroundColor(.white)
                            Text(book.author)
                                .font(.system(size: 11, weight: .medium))
                                .foregroundColor(.gray)
                        }
                        .padding(.leading, 8)
                        
                        Spacer()
                        
                        // View mode Picker
                        Picker("View Mode", selection: $viewMode) {
                            ForEach(ViewMode.allCases, id: \.self) { mode in
                                Text(mode.rawValue).tag(mode)
                            }
                        }
                        .pickerStyle(.segmented)
                        .frame(width: 180)
                        
                        Spacer()
                        
                        // Edit Panels Button
                        Button(action: { showEditor = true }) {
                            Image(systemName: "rectangle.and.pencil.and.ellipsis")
                                .font(.system(size: 16, weight: .bold))
                                .foregroundColor(.white)
                                .padding(10)
                                .background(RoundedRectangle(cornerRadius: 8).fill(Color.white.opacity(0.15)))
                        }
                    }
                    .padding()
                    .background(Color.black.opacity(0.85))
                    .transition(.move(edge: .top))
                    
                    Spacer()
                    
                    // Mini Map Overlay (Floating bottom right, above bottom control bar)
                    HStack {
                        Spacer()
                        PageMiniMap(page: book.pages[currentPageIndex], activePanelIndex: currentPanelIndex)
                            .padding(.trailing, 16)
                            .padding(.bottom, 12)
                    }
                    
                    // Bottom Navigation Bar
                    VStack(spacing: 12) {
                        // Panel stepper & label
                        HStack {
                            Text("Page \(currentPageIndex + 1) of \(book.pages.count)")
                                .font(.system(size: 13, weight: .bold))
                                .foregroundColor(.white)
                            
                            Spacer()
                            
                            let pagePanels = book.pages[currentPageIndex].panels.count
                            Text("Panel \(currentPanelIndex + 1) of \(pagePanels)")
                                .font(.system(size: 13, weight: .bold))
                                .foregroundColor(.cyan)
                        }
                        
                        // Page Slider
                        if book.pages.count > 1 {
                            Slider(
                                value: Binding(
                                    get: { Double(currentPageIndex) },
                                    set: { newValue in
                                        let idx = Int(newValue)
                                        if idx >= 0 && idx < book.pages.count {
                                            currentPageIndex = idx
                                            currentPanelIndex = 0
                                            saveReadingProgress()
                                        }
                                    }
                                ),
                                in: 0...Double(book.pages.count - 1),
                                step: 1.0
                            )
                            .accentColor(.cyan)
                        }
                    }
                    .padding()
                    .background(Color.black.opacity(0.85))
                    .transition(.move(edge: .bottom))
                }
            }
        }
        #if os(iOS)
        .statusBarHidden(!showControls)
        #endif
        .onAppear {
            // Load saved reading progress
            let progress = ReadingProgressManager.shared.getProgress(for: book.id)
            if progress.currentPageIndex < book.pages.count {
                currentPageIndex = progress.currentPageIndex
                let panelsCount = book.pages[currentPageIndex].panels.count
                if progress.currentPanelIndex < panelsCount {
                    currentPanelIndex = progress.currentPanelIndex
                } else {
                    currentPanelIndex = 0
                }
            }
        }
        .sheet(isPresented: $showEditor) {
            if !book.pages.isEmpty {
                PanelEditorView(
                    page: book.pages[currentPageIndex],
                    readingDirection: book.readingDirection,
                    onSave: { updatedPage in
                        book.pages[currentPageIndex] = updatedPage
                        // If currentPanelIndex is out of range, reset it
                        if currentPanelIndex >= updatedPage.panels.count {
                            currentPanelIndex = max(0, updatedPage.panels.count - 1)
                        }
                        // Save to disk if custom imported
                        if book.isCustomImported {
                            let bookDir = ComicImporter.comicsDirectory.appendingPathComponent(book.id.uuidString)
                            try? ComicImporter.shared.saveMetadata(book, in: bookDir)
                        }
                        saveReadingProgress()
                    }
                )
            }
        }
    }
    
    // Logic for navigating panels
    private func goToNextPanel() {
        let currentPage = book.pages[currentPageIndex]
        if currentPanelIndex < currentPage.panels.count - 1 {
            // Move to next panel on this page
            withAnimation {
                currentPanelIndex += 1
            }
        } else if currentPageIndex < book.pages.count - 1 {
            // Last panel on this page, move to first panel on NEXT page
            withAnimation {
                currentPageIndex += 1
                currentPanelIndex = 0
            }
        } else {
            // Finished the comic!
            ReadingProgressManager.shared.updateProgress(
                bookId: book.id,
                pageIndex: currentPageIndex,
                panelIndex: currentPanelIndex,
                isCompleted: true
            )
            return
        }
        saveReadingProgress()
    }
    
    private func goToPreviousPanel() {
        if currentPanelIndex > 0 {
            // Move to previous panel on this page
            withAnimation {
                currentPanelIndex -= 1
            }
        } else if currentPageIndex > 0 {
            // First panel on this page, move to last panel on PREVIOUS page
            withAnimation {
                currentPageIndex -= 1
                let previousPage = book.pages[currentPageIndex]
                currentPanelIndex = max(0, previousPage.panels.count - 1)
            }
        }
        saveReadingProgress()
    }
    
    private func saveReadingProgress() {
        ReadingProgressManager.shared.updateProgress(
            bookId: book.id,
            pageIndex: currentPageIndex,
            panelIndex: currentPanelIndex,
            isCompleted: false
        )
    }
}
