import SwiftUI

public enum DesktopViewMode: String, Codable, CaseIterable {
    case guided = "Guided Spotlight"
    case focus = "Focused Crop"
}

public struct DesktopReaderView: View {
    @Environment(\.dismiss) var dismiss
    
    @State public var book: ComicBook
    @State private var currentPageIndex: Int = 0
    @State private var currentPanelIndex: Int = 0
    @State private var viewMode: DesktopViewMode = .guided
    
    @State private var showControls: Bool = true
    @State private var showEditor: Bool = false
    @State private var isAdjustingPanel: Bool = false
    
    @FocusState private var isReaderFocused: Bool
    
    public init(book: ComicBook) {
        self._book = State(initialValue: book)
    }
    
    public var body: some View {
        let isRTL = book.readingDirection == .rightToLeft
        
        ZStack {
            Color.black.edgesIgnoringSafeArea(.all)
            
            if !book.pages.isEmpty {
                let currentPage = book.pages[currentPageIndex]
                
                ZStack {
                    if viewMode == .guided {
                        DesktopGuidedView(
                            page: $book.pages[currentPageIndex],
                            activePanelIndex: currentPanelIndex,
                            isAdjusting: isAdjustingPanel,
                            onAdjustEnded: {
                                if book.isCustomImported {
                                    let bookDir = ComicImporter.comicsDirectory.appendingPathComponent(book.id.uuidString)
                                    try? ComicImporter.shared.saveMetadata(book, in: bookDir)
                                }
                                saveReadingProgress()
                            }
                        )
                    } else {
                        DesktopFocusView(page: currentPage, activePanelIndex: currentPanelIndex)
                    }
                    
                    // Mouse Click Tap Zones
                    HStack(spacing: 0) {
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
                        
                        Color.clear
                            .contentShape(Rectangle())
                            .onTapGesture {
                                withAnimation(.easeInOut(duration: 0.2)) {
                                    showControls.toggle()
                                }
                            }
                        
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
            } else {
                VStack(spacing: 12) {
                    Image(systemName: "magazine")
                        .font(.system(size: 40))
                        .foregroundColor(.gray)
                    Text("No pages in this comic book.")
                        .foregroundColor(.white)
                }
            }
            
            // Overlays
            if showControls && !book.pages.isEmpty {
                VStack(spacing: 0) {
                    // Top Bar
                    HStack {
                        Button(action: { dismiss() }) {
                            HStack(spacing: 6) {
                                Image(systemName: "chevron.left")
                                    .font(.system(size: 14, weight: .bold))
                                Text("Library")
                                    .font(.system(size: 13, weight: .medium))
                            }
                            .foregroundColor(.white)
                            .padding(8)
                            .background(RoundedRectangle(cornerRadius: 8).fill(Color.white.opacity(0.1)))
                        }
                        .buttonStyle(.plain)
                        .help("Exit reader and return to shelf (Esc)")
                        
                        VStack(alignment: .leading, spacing: 1) {
                            Text(book.title)
                                .font(.system(size: 15, weight: .bold))
                                .foregroundColor(.white)
                            Text(book.author)
                                .font(.system(size: 11, weight: .medium))
                                .foregroundColor(.gray)
                        }
                        .padding(.leading, 8)
                        
                        Spacer()
                        
                        Picker("View Mode", selection: $viewMode) {
                            ForEach(DesktopViewMode.allCases, id: \.self) { mode in
                                Text(mode.rawValue).tag(mode)
                            }
                        }
                        .pickerStyle(.segmented)
                        .frame(width: 200)
                        
                        Spacer()
                        
                        HStack(spacing: 8) {
                            Button(action: { isAdjustingPanel.toggle() }) {
                                Label(isAdjustingPanel ? "Done" : "Adjust Panel", systemImage: isAdjustingPanel ? "checkmark.circle.fill" : "crop")
                                    .font(.system(size: 13, weight: .medium))
                                    .foregroundColor(isAdjustingPanel ? .green : .white)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 8)
                                    .background(RoundedRectangle(cornerRadius: 8).fill(isAdjustingPanel ? Color.green.opacity(0.2) : Color.white.opacity(0.12)))
                            }
                            .buttonStyle(.plain)
                            .help("Tweak active panel's 4 corner shapes in real-time")
                            
                            Button(action: { showEditor = true }) {
                                Label("Edit Page", systemImage: "rectangle.and.pencil.and.ellipsis")
                                    .font(.system(size: 13, weight: .medium))
                                    .foregroundColor(.white)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 8)
                                    .background(RoundedRectangle(cornerRadius: 8).fill(Color.white.opacity(0.12)))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding()
                    .background(Color.black.opacity(0.85))
                    .transition(.move(edge: .top))
                    
                    Spacer()
                    
                    // Floating Minimap
                    HStack {
                        Spacer()
                        PageMiniMap(page: book.pages[currentPageIndex], activePanelIndex: currentPanelIndex)
                            .padding(.trailing, 20)
                            .padding(.bottom, 16)
                    }
                    
                    // Bottom Navigation
                    VStack(spacing: 10) {
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
        // Native Keyboard Event Handlers
        .focusable()
        .focused($isReaderFocused)
        .onKeyPress { press in
            switch press.key {
            case .rightArrow, .downArrow:
                if isRTL {
                    goToPreviousPanel()
                } else {
                    goToNextPanel()
                }
                return .handled
                
            case .leftArrow, .upArrow:
                if isRTL {
                    goToNextPanel()
                } else {
                    goToPreviousPanel()
                }
                return .handled
                
            case .escape:
                dismiss()
                return .handled
                
            default:
                if press.characters == " " {
                    goToNextPanel()
                    return .handled
                }
                // Handle backspace/delete to go back
                if press.characters == "\u{7F}" || press.characters == "\u{08}" {
                    goToPreviousPanel()
                    return .handled
                }
                return .ignored
            }
        }
        .onAppear {
            isReaderFocused = true
            
            // Restore progress
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
                DesktopPanelEditor(
                    page: book.pages[currentPageIndex],
                    readingDirection: book.readingDirection,
                    onSave: { updatedPage in
                        book.pages[currentPageIndex] = updatedPage
                        if currentPanelIndex >= updatedPage.panels.count {
                            currentPanelIndex = max(0, updatedPage.panels.count - 1)
                        }
                        if book.isCustomImported {
                            let bookDir = ComicImporter.comicsDirectory.appendingPathComponent(book.id.uuidString)
                            try? ComicImporter.shared.saveMetadata(book, in: bookDir)
                        }
                        saveReadingProgress()
                        // Refocus keyboard receiver
                        isReaderFocused = true
                    }
                )
            }
        }
    }
    
    private func goToNextPanel() {
        let currentPage = book.pages[currentPageIndex]
        if currentPanelIndex < currentPage.panels.count - 1 {
            withAnimation {
                currentPanelIndex += 1
            }
        } else if currentPageIndex < book.pages.count - 1 {
            withAnimation {
                currentPageIndex += 1
                currentPanelIndex = 0
            }
        } else {
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
            withAnimation {
                currentPanelIndex -= 1
            }
        } else if currentPageIndex > 0 {
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
