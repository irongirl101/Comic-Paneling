import SwiftUI

public enum DesktopViewMode: String, Codable, CaseIterable {
    case guided = "Guided Spotlight"
    case focus = "Focused Crop"
}

public struct DesktopReaderView: View {
    public var onDismiss: () -> Void
    
    @State public var book: ComicBook
    @State private var currentPageIndex: Int = 0
    @State private var currentPanelIndex: Int = 0
    @State private var viewMode: DesktopViewMode = .guided
    
    @State private var showControls: Bool = true
    @State private var showEditor: Bool = false
    @State private var isAdjustingPanel: Bool = false
    
    @FocusState private var isReaderFocused: Bool
    
    @State private var zoomFactor: CGFloat = 1.0
    @GestureState private var gestureZoom: CGFloat = 1.0
    
    public init(book: ComicBook, onDismiss: @escaping () -> Void) {
        self._book = State(initialValue: book)
        self.onDismiss = onDismiss
    }
    
    public var body: some View {
        let isRTL = book.readingDirection == .rightToLeft
        
        let magnifyGesture = MagnifyGesture()
            .updating($gestureZoom) { value, state, _ in
                state = value.magnification
            }
            .onEnded { value in
                zoomFactor = min(3.0, max(0.5, zoomFactor * value.magnification))
            }
        
        GeometryReader { windowGeo in
            let safeAreaTop = windowGeo.safeAreaInsets.top
            let safeAreaBottom = windowGeo.safeAreaInsets.bottom
            
            ZStack {
                Color.black
                .ignoresSafeArea()
            
            if !book.pages.isEmpty {
                let currentPage = book.pages[currentPageIndex]
                
                ZStack {
                    if viewMode == .guided {
                        DesktopGuidedView(
                            page: $book.pages[currentPageIndex],
                            activePanelIndex: currentPanelIndex,
                            isAdjusting: isAdjustingPanel,
                            zoomFactor: zoomFactor * gestureZoom,
                            onAdjustEnded: {
                                if book.isCustomImported {
                                    let bookDir = ComicImporter.comicsDirectory.appendingPathComponent(book.id.uuidString)
                                    try? ComicImporter.shared.saveMetadata(book, in: bookDir)
                                }
                                saveReadingProgress()
                            }
                        )
                    } else {
                        DesktopFocusView(page: currentPage, activePanelIndex: currentPanelIndex, zoomFactor: zoomFactor * gestureZoom)
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
                .gesture(magnifyGesture)
                .ignoresSafeArea()
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
                    VStack(spacing: 0) {
                        Spacer()
                            .frame(height: safeAreaTop)
                        
                        GeometryReader { topBarGeo in
                        let w = topBarGeo.size.width
                        let maxSideWidth = max(145, (w - 200) / 2 - 16)
                        
                        ZStack {
                            // Center View Mode Picker (guaranteed centered)
                            Picker("View Mode", selection: $viewMode) {
                                ForEach(DesktopViewMode.allCases, id: \.self) { mode in
                                    Text(mode.rawValue).tag(mode)
                                }
                            }
                            .pickerStyle(.segmented)
                            .frame(width: 180)
                            
                            HStack(spacing: 0) {
                                // Left side
                                HStack(spacing: 6) {
                                    Button(action: { onDismiss() }) {
                                        HStack(spacing: 4) {
                                            Image(systemName: "chevron.left")
                                                .font(.system(size: 13, weight: .bold))
                                            Text("Library")
                                                .font(.system(size: 12, weight: .medium))
                                        }
                                        .foregroundColor(.white)
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 6)
                                        .background(RoundedRectangle(cornerRadius: 6).fill(Color.white.opacity(0.1)))
                                    }
                                    .buttonStyle(.plain)
                                    .help("Exit reader (Esc)")
                                    
                                    VStack(alignment: .leading, spacing: 0) {
                                        Text(book.title)
                                            .font(.system(size: 12, weight: .bold))
                                            .foregroundColor(.white)
                                            .lineLimit(1)
                                        Text(book.author)
                                            .font(.system(size: 9, weight: .medium))
                                            .foregroundColor(.gray)
                                            .lineLimit(1)
                                    }
                                }
                                .frame(maxWidth: maxSideWidth, alignment: .leading)
                                
                                Spacer()
                                
                                // Right side
                                HStack(spacing: 6) {
                                    // Zoom Controls
                                    HStack(spacing: 0) {
                                        Button(action: {
                                            withAnimation(.easeInOut(duration: 0.15)) {
                                                zoomFactor = max(0.5, zoomFactor - 0.15)
                                            }
                                        }) {
                                            Image(systemName: "minus.magnifyingglass")
                                                .font(.system(size: 11))
                                                .foregroundColor(.white)
                                                .frame(width: 28, height: 28)
                                                .contentShape(Rectangle())
                                        }
                                        .buttonStyle(.plain)
                                        .help("Zoom Out (-)")
                                        
                                        Divider()
                                            .frame(height: 14)
                                            .background(Color.white.opacity(0.15))
                                        
                                        Button(action: {
                                            withAnimation(.easeInOut(duration: 0.15)) {
                                                zoomFactor = 1.0
                                            }
                                        }) {
                                            Text("\(Int(zoomFactor * 100))%")
                                                .font(.system(size: 10, weight: .bold, design: .monospaced))
                                                .foregroundColor(.cyan)
                                                .frame(width: 44, height: 28)
                                                .contentShape(Rectangle())
                                        }
                                        .buttonStyle(.plain)
                                        .help("Reset Zoom (0)")
                                        
                                        Divider()
                                            .frame(height: 14)
                                            .background(Color.white.opacity(0.15))
                                        
                                        Button(action: {
                                            withAnimation(.easeInOut(duration: 0.15)) {
                                                zoomFactor = min(3.0, zoomFactor + 0.15)
                                            }
                                        }) {
                                            Image(systemName: "plus.magnifyingglass")
                                                .font(.system(size: 11))
                                                .foregroundColor(.white)
                                                .frame(width: 28, height: 28)
                                                .contentShape(Rectangle())
                                        }
                                        .buttonStyle(.plain)
                                        .help("Zoom In (+)")
                                    }
                                    .background(RoundedRectangle(cornerRadius: 6).fill(Color.white.opacity(0.1)))
                                    
                                    Button(action: { showEditor = true }) {
                                        Image(systemName: "rectangle.and.pencil.and.ellipsis")
                                            .font(.system(size: 12))
                                            .foregroundColor(.white)
                                            .frame(width: 28, height: 28)
                                            .background(RoundedRectangle(cornerRadius: 6).fill(Color.white.opacity(0.1)))
                                    }
                                    .buttonStyle(.plain)
                                    .help("Edit Page Panels")
                                }
                                .frame(maxWidth: maxSideWidth, alignment: .trailing)
                            }
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                    }
                    .frame(height: 44)
                    }
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
                    VStack(spacing: 0) {
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
                        
                        Spacer()
                            .frame(height: safeAreaBottom)
                    }
                    .background(Color.black.opacity(0.85))
                    .transition(.move(edge: .bottom))
                }
                .ignoresSafeArea()
            }
        }
        }
        .ignoresSafeArea()
        .toolbar(.hidden)
        .navigationTitle("")
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
                onDismiss()
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
                                // Zoom keyboard shortcuts
                                if press.characters == "=" || press.characters == "+" {
                                    withAnimation(.easeInOut(duration: 0.15)) {
                                        zoomFactor = min(3.0, zoomFactor + 0.15)
                                    }
                                    return .handled
                                }
                                if press.characters == "-" {
                                    withAnimation(.easeInOut(duration: 0.15)) {
                                        zoomFactor = max(0.5, zoomFactor - 0.15)
                                    }
                                    return .handled
                                }
                                if press.characters == "0" {
                                    withAnimation(.easeInOut(duration: 0.15)) {
                                        zoomFactor = 1.0
                                    }
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
