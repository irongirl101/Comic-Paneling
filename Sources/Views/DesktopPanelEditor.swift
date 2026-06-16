import SwiftUI
import CoreGraphics

public struct DesktopPanelEditor: View {
    @Environment(\.dismiss) var dismiss
    
    @State public var page: ComicPage
    public var readingDirection: ReadingDirection
    public var onSave: (ComicPage) -> Void
    
    @State private var selectedPanelId: UUID? = nil
    @State private var dragStartRect: CGRect? = nil
    @State private var dragStartPoints: [CGPoint]? = nil
    @State private var isDetecting: Bool = false
    @State private var detectionMode: PanelDetector.DetectionMode = .xycut
    
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
                .buttonStyle(.bordered)
                
                Spacer()
                
                Text("Edit Panels - Page \(page.pageNumber)")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(.white)
                
                Spacer()
                
                Button("Save Layout") {
                    var updatedPage = page
                    updatedPage.panels = page.panels.enumerated().map { idx, panel in
                        var p = panel
                        p.order = idx
                        return p
                    }
                    onSave(updatedPage)
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .tint(.green)
                .foregroundColor(.white)
            }
            .padding()
            .background(Color.black.opacity(0.85))
            
            // Workspace
            GeometryReader { workspaceGeo in
                let containerSize = workspaceGeo.size
                let imgSize = getImageSize(path: page.imagePath)
                let fitSize = calculateFitImageSize(imageSize: imgSize, containerSize: containerSize)
                
                ZStack {
                    Color.black
                    
                    ComicImage(path: page.imagePath)
                        .aspectRatio(contentMode: .fit)
                        .frame(width: containerSize.width, height: containerSize.height)
                        .opacity(0.7)
                    
                    // Box Overlay Canvas
                    ZStack {
                        ForEach($page.panels) { $panel in
                            let isSelected = panel.id == selectedPanelId
                            let pts = panel.getPoints()
                            let screenPoints = pts.map { p in
                                CGPoint(x: p.x * fitSize.width, y: p.y * fitSize.height)
                            }
                            
                            ZStack {
                                // Dynamic polygon background
                                Path { path in
                                    path.move(to: screenPoints[0])
                                    path.addLine(to: screenPoints[1])
                                    path.addLine(to: screenPoints[2])
                                    path.addLine(to: screenPoints[3])
                                    path.closeSubpath()
                                }
                                .fill(isSelected ? Color.blue.opacity(0.2) : Color.white.opacity(0.1))
                                
                                // Dynamic polygon border
                                Path { path in
                                    path.move(to: screenPoints[0])
                                    path.addLine(to: screenPoints[1])
                                    path.addLine(to: screenPoints[2])
                                    path.addLine(to: screenPoints[3])
                                    path.closeSubpath()
                                }
                                .stroke(isSelected ? Color.cyan : Color.white.opacity(0.4), lineWidth: isSelected ? 2.0 : 1.0)
                                
                                // Order Badge (centered within bounding box)
                                let rect = panel.rect
                                let px = rect.origin.x * fitSize.width
                                let py = rect.origin.y * fitSize.height
                                let pw = rect.width * fitSize.width
                                let ph = rect.height * fitSize.height
                                
                                Text("#\(panel.order + 1)")
                                    .font(.system(size: 10, weight: .bold))
                                    .foregroundColor(.white)
                                    .padding(.horizontal, 5)
                                    .padding(.vertical, 2)
                                    .background(isSelected ? Color.cyan : Color.gray.opacity(0.8))
                                    .cornerRadius(4)
                                    .position(x: px + pw/2, y: py + ph/2)
                            }
                            .contentShape(Path { path in
                                path.move(to: screenPoints[0])
                                path.addLine(to: screenPoints[1])
                                path.addLine(to: screenPoints[2])
                                path.addLine(to: screenPoints[3])
                                path.closeSubpath()
                            })
                            .gesture(
                                DragGesture(minimumDistance: 0)
                                    .onChanged { gesture in
                                        if dragStartRect == nil {
                                            dragStartRect = panel.rect
                                            if panel.polygonPoints == nil {
                                                panel.polygonPoints = panel.getPoints()
                                            }
                                            dragStartPoints = panel.polygonPoints
                                            selectedPanelId = panel.id
                                        }
                                        guard let startRect = dragStartRect,
                                              let startPoints = dragStartPoints else { return }
                                        
                                        let dx = gesture.translation.width / fitSize.width
                                        let dy = gesture.translation.height / fitSize.height
                                        
                                        var newX = startRect.origin.x + dx
                                        var newY = startRect.origin.y + dy
                                        
                                        newX = max(0.0, min(1.0 - startRect.width, newX))
                                        newY = max(0.0, min(1.0 - startRect.height, newY))
                                        
                                        let finalDx = newX - startRect.origin.x
                                        let finalDy = newY - startRect.origin.y
                                        
                                        panel.rect.origin = CGPoint(x: newX, y: newY)
                                        
                                        panel.polygonPoints = startPoints.map { p in
                                            CGPoint(
                                                x: max(0.0, min(1.0, p.x + finalDx)),
                                                y: max(0.0, min(1.0, p.y + finalDy))
                                            )
                                        }
                                    }
                                    .onEnded { _ in
                                        dragStartRect = nil
                                        dragStartPoints = nil
                                    }
                            )
                            .onTapGesture(count: 2) {
                                deletePanel(id: panel.id)
                            }
                            .onTapGesture(count: 1) {
                                selectedPanelId = panel.id
                            }
                            
                            // 4 Corner resizing handles for full dynamic shape customization
                            if isSelected {
                                ForEach(0..<4, id: \.self) { idx in
                                    let p = screenPoints[idx]
                                    Circle()
                                        .fill(Color.cyan)
                                        .frame(width: 14, height: 14)
                                        .overlay(Circle().stroke(Color.white, lineWidth: 1.5))
                                        .position(p)
                                        .gesture(
                                            DragGesture()
                                                .onChanged { gesture in
                                                    if dragStartPoints == nil {
                                                        if panel.polygonPoints == nil {
                                                            panel.polygonPoints = panel.getPoints()
                                                        }
                                                        dragStartPoints = panel.polygonPoints
                                                    }
                                                    guard var startPoints = dragStartPoints else { return }
                                                    
                                                    let dx = gesture.translation.width / fitSize.width
                                                    let dy = gesture.translation.height / fitSize.height
                                                    
                                                    let pt = startPoints[idx]
                                                    let newX = max(0.0, min(1.0, pt.x + dx))
                                                    let newY = max(0.0, min(1.0, pt.y + dy))
                                                    
                                                    startPoints[idx] = CGPoint(x: newX, y: newY)
                                                    panel.polygonPoints = startPoints
                                                    
                                                    // Recompute rect from bounding box of points
                                                    let xs = startPoints.map { $0.x }
                                                    let ys = startPoints.map { $0.y }
                                                    if let minX = xs.min(), let maxX = xs.max(),
                                                       let minY = ys.min(), let maxY = ys.max() {
                                                        panel.rect = CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
                                                    }
                                                }
                                                .onEnded { _ in
                                                    dragStartPoints = nil
                                                }
                                        )
                                }
                            }
                        }
                    }
                    .frame(width: fitSize.width, height: fitSize.height)
                }
                .frame(width: containerSize.width, height: containerSize.height)
            }
            
            // Bottom Bar Controls
            VStack(spacing: 8) {
                if isDetecting {
                    ProgressView("Analyzing layout...")
                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                        .padding()
                } else {
                    HStack(spacing: 16) {
                        Button(action: addPanel) {
                            Label("Add Panel", systemImage: "plus.app")
                        }
                        
                        Button(action: runAutoDetect) {
                            Label("Auto-Detect", systemImage: "wand.and.stars")
                        }
                        
                        Picker("Detection Mode", selection: $detectionMode) {
                            Text("XY-Cut").tag(PanelDetector.DetectionMode.xycut)
                            Text("Contour").tag(PanelDetector.DetectionMode.contour)
                        }
                        .pickerStyle(.segmented)
                        .frame(width: 150)
                        .labelsHidden()
                        
                        if selectedPanelId != nil {
                            Button(action: runSnapActivePanel) {
                                Label("Snap Box", systemImage: "sparkles")
                            }
                            .buttonStyle(.bordered)
                            .foregroundColor(.cyan)
                            
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
                            .help("Move panel earlier in reading order")
                            
                            Button(action: moveDown) {
                                Image(systemName: "arrow.down")
                            }
                            .help("Move panel later in reading order")
                        }
                    }
                    .padding(.vertical, 12)
                }
                
                Text("Drag panels to move. Drag the neon blue corner handle to resize. Double-click a panel to delete it.")
                    .font(.system(size: 11))
                    .foregroundColor(.gray)
                    .padding(.bottom, 12)
            }
            .frame(maxWidth: .infinity)
            .background(Color.black.opacity(0.85))
        }
        .frame(minWidth: 600, minHeight: 500)
        .background(Color.black)
    }
    
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
    
    private func runSnapActivePanel() {
        guard let id = selectedPanelId,
              let idx = page.panels.firstIndex(where: { $0.id == id }),
              let nsImage = NSImage(contentsOfFile: page.imagePath),
              let cgImage = nsImage.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return }
        
        let panel = page.panels[idx]
        let currentPoints = panel.getPoints()
        let snappedPoints = PanelSnapper.snapPoints(currentPoints, in: cgImage)
        
        var updatedPanel = panel
        updatedPanel.polygonPoints = snappedPoints
        
        let xs = snappedPoints.map { $0.x }
        let ys = snappedPoints.map { $0.y }
        if let minX = xs.min(), let maxX = xs.max(),
           let minY = ys.min(), let maxY = ys.max() {
            updatedPanel.rect = CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
        }
        
        page.panels[idx] = updatedPanel
    }
    
    private func reorderPanels() {
        for idx in 0..<page.panels.count {
            page.panels[idx].order = idx
        }
    }
    
    private func runAutoDetect() {
        guard let nsImage = NSImage(contentsOfFile: page.imagePath),
              let cgImage = nsImage.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return }
        isDetecting = true
        Task {
            let rects = await PanelDetector.detectPanels(in: cgImage, direction: readingDirection, mode: detectionMode)
            page.panels = rects.enumerated().map { idx, rect in
                ComicPanel(rect: rect, order: idx)
            }
            isDetecting = false
            selectedPanelId = page.panels.first?.id
        }
    }
    
    private func calculateFitImageSize(imageSize: CGSize, containerSize: CGSize) -> CGSize {
        let imageAspect = imageSize.width / imageSize.height
        let containerAspect = workspaceGeoAspect(containerSize)
        
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
    
    private func workspaceGeoAspect(_ size: CGSize) -> CGFloat {
        return size.width / max(1, size.height)
    }
    
    private func getImageSize(path: String) -> CGSize {
        guard let img = NSImage(contentsOfFile: path) else {
            return CGSize(width: 800, height: 1200)
        }
        if let cg = img.cgImage(forProposedRect: nil, context: nil, hints: nil) {
            return CGSize(width: cg.width, height: cg.height)
        }
        return img.size
    }
}
