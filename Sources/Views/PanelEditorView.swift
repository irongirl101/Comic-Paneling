import SwiftUI
import CoreGraphics

public struct PanelEditorView: View {
    @Environment(\.dismiss) var dismiss
    
    // Binding to the page we are editing
    @State public var page: ComicPage
    public var readingDirection: ReadingDirection
    public var onSave: (ComicPage) -> Void
    
    @State private var selectedPanelId: UUID? = nil
    @State private var dragStartRect: CGRect? = nil
    @State private var isDetecting: Bool = false
    
    public init(page: ComicPage, readingDirection: ReadingDirection, onSave: @escaping (ComicPage) -> Void) {
        self._page = State(initialValue: page)
        self.readingDirection = readingDirection
        self.onSave = onSave
    }
    
    public var body: some View {
        VStack(spacing: 0) {
            // Top Bar
            HStack {
                Button("Cancel") {
                    dismiss()
                }
                .foregroundColor(.red)
                
                Spacer()
                
                Text("Edit Panels - Page \(page.pageNumber)")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(.white)
                
                Spacer()
                
                Button("Save") {
                    // Normalize panel orders
                    var updatedPage = page
                    updatedPage.panels = page.panels.enumerated().map { idx, panel in
                        var p = panel
                        p.order = idx
                        return p
                    }
                    onSave(updatedPage)
                    dismiss()
                }
                .foregroundColor(.green)
                .font(.system(size: 16, weight: .bold))
            }
            .padding()
            .background(Color.black.opacity(0.8))
            
            // Editor workspace
            GeometryReader { workspaceGeo in
                let containerSize = workspaceGeo.size
                let imgSize = getImageSize(path: page.imagePath)
                let fitSize = calculateFitImageSize(imageSize: imgSize, containerSize: containerSize)
                
                ZStack {
                    Color.black.edgesIgnoringSafeArea(.all)
                    
                    // Display Page Image centered
                    ComicImage(path: page.imagePath)
                        .aspectRatio(contentMode: .fit)
                        .frame(width: containerSize.width, height: containerSize.height)
                        .opacity(0.75)
                    
                    // Draw Interactive Bounding Boxes
                    // We overlay a canvas of the fit size directly on top of the image
                    ZStack {
                        ForEach($page.panels) { $panel in
                            let rect = panel.rect
                            let isSelected = panel.id == selectedPanelId
                            
                            let px = rect.origin.x * fitSize.width
                            let py = rect.origin.y * fitSize.height
                            let pw = rect.width * fitSize.width
                            let ph = rect.height * fitSize.height
                            
                            // Panel Boundary Box
                            ZStack(alignment: .topLeading) {
                                RoundedRectangle(cornerRadius: 4)
                                    .fill(isSelected ? Color.blue.opacity(0.2) : Color.white.opacity(0.1))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 4)
                                            .stroke(isSelected ? Color.cyan : Color.white.opacity(0.5), lineWidth: isSelected ? 2.0 : 1.0)
                                    )
                                
                                // Reading order index tag
                                Text("#\(panel.order + 1)")
                                    .font(.system(size: 11, weight: .bold))
                                    .foregroundColor(.white)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(isSelected ? Color.cyan : Color.gray.opacity(0.8))
                                    .cornerRadius(4)
                                    .padding(4)
                            }
                            .frame(width: max(20, pw), height: max(20, ph))
                            .position(x: px + pw/2, y: py + ph/2)
                            // Gestures for moving the panel
                            .gesture(
                                DragGesture(minimumDistance: 0)
                                    .onChanged { gesture in
                                        if dragStartRect == nil {
                                            dragStartRect = panel.rect
                                            selectedPanelId = panel.id
                                        }
                                        
                                        guard let startRect = dragStartRect else { return }
                                        
                                        // Calculate the relative drag shift
                                        let dx = gesture.translation.width / fitSize.width
                                        let dy = gesture.translation.height / fitSize.height
                                        
                                        // Update the origin, clamped to fit in 0..1
                                        var newX = startRect.origin.x + dx
                                        var newY = startRect.origin.y + dy
                                        
                                        newX = max(0.0, min(1.0 - startRect.width, newX))
                                        newY = max(0.0, min(1.0 - startRect.height, newY))
                                        
                                        panel.rect.origin = CGPoint(x: newX, y: newY)
                                    }
                                    .onEnded { _ in
                                        dragStartRect = nil
                                    }
                            )
                            // Double tap to delete
                            .onTapGesture(count: 2) {
                                deletePanel(id: panel.id)
                            }
                            // Single tap to select
                            .onTapGesture(count: 1) {
                                selectedPanelId = panel.id
                            }
                            
                            // Resize Handle at bottom right of selected panel
                            if isSelected {
                                Circle()
                                    .fill(Color.cyan)
                                    .frame(width: 16, height: 16)
                                    .overlay(Circle().stroke(Color.white, lineWidth: 1.5))
                                    .position(x: px + pw, y: py + ph)
                                    .gesture(
                                        DragGesture()
                                            .onChanged { gesture in
                                                if dragStartRect == nil {
                                                    dragStartRect = panel.rect
                                                }
                                                guard let startRect = dragStartRect else { return }
                                                
                                                let dw = gesture.translation.width / fitSize.width
                                                let dh = gesture.translation.height / fitSize.height
                                                
                                                var newW = startRect.width + dw
                                                var newH = startRect.height + dh
                                                
                                                // Clamp sizes
                                                newW = max(0.05, min(1.0 - startRect.origin.x, newW))
                                                newH = max(0.05, min(1.0 - startRect.origin.y, newH))
                                                
                                                panel.rect.size = CGSize(width: newW, height: newH)
                                            }
                                            .onEnded { _ in
                                                dragStartRect = nil
                                            }
                                    )
                            }
                        }
                    }
                    .frame(width: fitSize.width, height: fitSize.height)
                }
                .frame(width: containerSize.width, height: containerSize.height)
            }
            
            // Bottom Editing Palette
            VStack(spacing: 8) {
                if isDetecting {
                    ProgressView("Auto-detecting panels...")
                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                        .padding()
                } else {
                    HStack(spacing: 12) {
                        Button(action: addPanel) {
                            Label("Add", systemImage: "plus.app")
                        }
                        
                        Button(action: runAutoDetect) {
                            Label("Auto-Detect", systemImage: "wand.and.stars")
                        }
                        
                        if selectedPanelId != nil {
                            Button(role: .destructive, action: {
                                if let id = selectedPanelId {
                                    deletePanel(id: id)
                                }
                            }) {
                                Label("Delete", systemImage: "trash")
                            }
                            .foregroundColor(.red)
                            
                            Button(action: moveUp) {
                                Image(systemName: "arrow.up")
                            }
                            Button(action: moveDown) {
                                Image(systemName: "arrow.down")
                            }
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .padding(.vertical, 8)
                }
                
                Text("Drag panels to move. Drag the blue handle to resize. Double-tap to delete.")
                    .font(.system(size: 11))
                    .foregroundColor(.gray)
                    .padding(.bottom, 12)
            }
            .frame(maxWidth: .infinity)
            .background(Color.black.opacity(0.85))
        }
        .background(Color.black)
    }
    
    // Actions
    private func addPanel() {
        let order = page.panels.count
        let newPanel = ComicPanel(
            rect: CGRect(x: 0.25, y: 0.25, width: 0.5, height: 0.5),
            order: order
        )
        page.panels.append(newPanel)
        selectedPanelId = newPanel.id
    }
    
    private func deletePanel(id: UUID) {
        page.panels.removeAll { $0.id == id }
        if selectedPanelId == id {
            selectedPanelId = nil
        }
        reorderPanels()
    }
    
    private func moveUp() {
        guard let id = selectedPanelId,
              let index = page.panels.firstIndex(where: { $0.id == id }),
              index > 0 else { return }
        
        page.panels.swapAt(index, index - 1)
        reorderPanels()
    }
    
    private func moveDown() {
        guard let id = selectedPanelId,
              let index = page.panels.firstIndex(where: { $0.id == id }),
              index < page.panels.count - 1 else { return }
        
        page.panels.swapAt(index, index + 1)
        reorderPanels()
    }
    
    private func reorderPanels() {
        for idx in 0..<page.panels.count {
            page.panels[idx].order = idx
        }
    }
    
    private func runAutoDetect() {
        guard let cgImage = createCGImage(from: page.imagePath) else { return }
        isDetecting = true
        Task {
            let rects = await PanelDetector.detectPanels(in: cgImage, direction: readingDirection)
            page.panels = rects.enumerated().map { idx, rect in
                ComicPanel(rect: rect, order: idx)
            }
            isDetecting = false
            selectedPanelId = page.panels.first?.id
        }
    }
    
    // Helpers
    private func calculateFitImageSize(imageSize: CGSize, containerSize: CGSize) -> CGSize {
        let imageAspect = imageSize.width / imageSize.height
        let containerAspect = containerSize.width / containerSize.height
        
        if imageAspect > containerAspect {
            let w = containerSize.width
            let h = w / imageAspect
            return CGSize(width: w, height: h)
        } else {
            let h = containerSize.height
            let w = h * imageAspect
            return CGSize(width: w, height: h)
        }
    }
    
    private func getImageSize(path: String) -> CGSize {
        #if canImport(UIKit)
        guard let img = UIImage(contentsOfFile: path) else {
            return CGSize(width: 800, height: 1200)
        }
        if let cg = img.cgImage {
            return CGSize(width: cg.width, height: cg.height)
        }
        return img.size
        #elseif canImport(AppKit)
        guard let img = NSImage(contentsOfFile: path) else {
            return CGSize(width: 800, height: 1200)
        }
        if let cg = img.cgImage(forProposedRect: nil, context: nil, hints: nil) {
            return CGSize(width: cg.width, height: cg.height)
        }
        return img.size
        #else
        return CGSize(width: 800, height: 1200)
        #endif
    }
    
    private func createCGImage(from path: String) -> CGImage? {
        #if canImport(UIKit)
        guard let uiImage = UIImage(contentsOfFile: path) else { return nil }
        return uiImage.cgImage
        #elseif canImport(AppKit)
        guard let nsImage = NSImage(contentsOfFile: path),
              let cgImage = nsImage.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            return nil
        }
        return cgImage
        #else
        return nil
        #endif
    }
}
