import SwiftUI
import CoreGraphics
import AppKit


// A simple polygon shape that maps 4 normalized [0,1] points to the shape's own local rect.
// This means if you give it a frame of fitImageSize, it renders the polygon pixel-perfectly
// in image-coordinate space — no manual container-center offset math needed.
public struct PanelPolygonShape: Shape {
    public var p0: CGPoint
    public var p1: CGPoint
    public var p2: CGPoint
    public var p3: CGPoint

    public init(points: [CGPoint]) {
        let pts = points.count == 4 ? points : [
            CGPoint(x: 0, y: 0), CGPoint(x: 1, y: 0),
            CGPoint(x: 1, y: 1), CGPoint(x: 0, y: 1)
        ]
        self.p0 = pts[0]; self.p1 = pts[1]; self.p2 = pts[2]; self.p3 = pts[3]
    }

    public var animatableData: AnimatablePair<
        AnimatablePair<AnimatablePair<CGFloat, CGFloat>, AnimatablePair<CGFloat, CGFloat>>,
        AnimatablePair<AnimatablePair<CGFloat, CGFloat>, AnimatablePair<CGFloat, CGFloat>>
    > {
        get {
            AnimatablePair(
                AnimatablePair(AnimatablePair(p0.x, p0.y), AnimatablePair(p1.x, p1.y)),
                AnimatablePair(AnimatablePair(p2.x, p2.y), AnimatablePair(p3.x, p3.y))
            )
        }
        set {
            p0 = CGPoint(x: newValue.first.first.first, y: newValue.first.first.second)
            p1 = CGPoint(x: newValue.first.second.first, y: newValue.first.second.second)
            p2 = CGPoint(x: newValue.second.first.first, y: newValue.second.first.second)
            p3 = CGPoint(x: newValue.second.second.first, y: newValue.second.second.second)
        }
    }

    public func path(in rect: CGRect) -> Path {
        // Map normalized [0,1] points directly to the local rect size.
        // Since this shape is framed to fitImageSize, these map exactly to image pixels.
        let sp = [p0, p1, p2, p3].map { p in
            CGPoint(x: rect.minX + p.x * rect.width, y: rect.minY + p.y * rect.height)
        }
        var path = Path()
        path.move(to: sp[0])
        path.addLine(to: sp[1])
        path.addLine(to: sp[2])
        path.addLine(to: sp[3])
        path.closeSubpath()
        return path
    }
}

// The pulsing neon border that traces the panel polygon.
// Frame it to fitImageSize and apply the same scale/offset as the image.
public struct SpotlightBorder: View {
    public var panelPoints: [CGPoint]
    public var fitImageSize: CGSize
    public var renderScale: CGFloat
    public var renderOffsetX: CGFloat
    public var renderOffsetY: CGFloat

    @State private var glowPulse = 0.0

    public init(panelPoints: [CGPoint], fitImageSize: CGSize, renderScale: CGFloat, renderOffsetX: CGFloat, renderOffsetY: CGFloat) {
        self.panelPoints = panelPoints
        self.fitImageSize = fitImageSize
        self.renderScale = renderScale
        self.renderOffsetX = renderOffsetX
        self.renderOffsetY = renderOffsetY
    }

    public var body: some View {
        PanelPolygonShape(points: panelPoints)
            .stroke(
                LinearGradient(
                    colors: [Color.cyan, Color.purple, Color.blue],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                lineWidth: max(1.0, (2.0 + CGFloat(glowPulse * 0.5)) / renderScale)
            )
            .shadow(color: Color.cyan.opacity(0.4 + glowPulse * 0.3), radius: 6.0 + CGFloat(glowPulse * 4.0))
            .frame(width: fitImageSize.width, height: fitImageSize.height)
            .scaleEffect(renderScale)
            .offset(x: renderOffsetX, y: renderOffsetY)
            .onAppear {
                withAnimation(.easeInOut(duration: 1.5).repeatForever(autoreverses: true)) {
                    glowPulse = 1.0
                }
            }
            .allowsHitTesting(false)
    }
}

public struct DesktopGuidedView: View {
    @Binding public var page: ComicPage
    public var activePanelIndex: Int
    public var isAdjusting: Bool
    public var onAdjustEnded: (() -> Void)? = nil

    @State private var dragStartPoints: [CGPoint]? = nil
    @State private var dragStartScale: CGFloat? = nil
    @State private var dragStartOffsetX: CGFloat? = nil
    @State private var dragStartOffsetY: CGFloat? = nil

    public init(page: Binding<ComicPage>, activePanelIndex: Int, isAdjusting: Bool, onAdjustEnded: (() -> Void)? = nil) {
        self._page = page
        self.activePanelIndex = activePanelIndex
        self.isAdjusting = isAdjusting
        self.onAdjustEnded = onAdjustEnded
    }

    public var body: some View {
        GeometryReader { geo in
            let topPadding: CGFloat = 20
            let containerSize = CGSize(width: geo.size.width, height: geo.size.height - topPadding)
            let imgSize = getImageSize(path: page.imagePath)
            let fitImageSize = calculateFitImageSize(imageSize: imgSize, containerSize: containerSize)

            let activePanel = page.panels[safe: activePanelIndex]
                ?? ComicPanel(rect: CGRect(x: 0, y: 0, width: 1, height: 1), order: 0)
            let panelRect = activePanel.rect
            let panelPoints = activePanel.getPoints()

            let panelWidthOnScreen  = panelRect.width  * fitImageSize.width
            let panelHeightOnScreen = panelRect.height * fitImageSize.height

            let horizontalPadding: CGFloat = 48
            let verticalPadding:   CGFloat = 96

            let targetScaleX = (containerSize.width  - horizontalPadding) / max(1, panelWidthOnScreen)
            let targetScaleY = (containerSize.height - verticalPadding)   / max(1, panelHeightOnScreen)
            let targetScale  = min(4.0, max(1.0, min(targetScaleX, targetScaleY)))

            let dx = (panelRect.midX - 0.5) * fitImageSize.width
            let dy = (panelRect.midY - 0.5) * fitImageSize.height
            let offsetX = -dx * targetScale
            let offsetY = -dy * targetScale

            // Freeze coordinates during drag to prevent cursor-drift loop
            let renderScale   = dragStartScale   ?? targetScale
            let renderOffsetX = dragStartOffsetX ?? offsetX
            let renderOffsetY = dragStartOffsetY ?? offsetY

            ZStack {
                Color.black

                ZStack {
                    // ── 2. Comic image ───────────────────────────────────────────────
                    // aspectRatio(.fit) in a containerSize frame renders the image at
                    // fitImageSize, centered. scaleEffect scales from the frame center.
                    ComicImage(path: page.imagePath)
                        .aspectRatio(contentMode: .fit)
                        .frame(width: fitImageSize.width, height: fitImageSize.height)
                        .scaleEffect(renderScale)
                        .offset(x: renderOffsetX, y: renderOffsetY)

                    // ── 3. Dimming overlay with punched-out panel hole ───────────────
                    // compositingGroup isolates blending; destinationOut erases the
                    // panel-shaped area so the image below shows through unobscured.
                    ZStack {
                        Color.black.opacity(isAdjusting ? 0.30 : 0.65)

                        PanelPolygonShape(points: panelPoints)
                            .frame(width: fitImageSize.width, height: fitImageSize.height)
                            .scaleEffect(renderScale)
                            .offset(x: renderOffsetX, y: renderOffsetY)
                            .blendMode(.destinationOut)
                    }
                    .compositingGroup()
                    .allowsHitTesting(false)

                    // ── 4. Neon border tracing the panel ─────────────────────────────
                    SpotlightBorder(
                        panelPoints: panelPoints,
                        fitImageSize: fitImageSize,
                        renderScale: renderScale,
                        renderOffsetX: renderOffsetX,
                        renderOffsetY: renderOffsetY
                    )

                    // ── 5. Live calibration handles (adjust mode only) ───────────────
                    if isAdjusting {
                        // Each handle is a Circle() placed with .position() in the
                        // coordinate space of this ZStack (which is containerSize).
                        // We convert normalized image-space point → container-space point
                        // by applying the same transform the image uses:
                        //   screen = (fitImageCenter + normalized offset) * scale + offset
                        // Since fitImageSize is centered in containerSize:
                        let fitOriginX = (containerSize.width  - fitImageSize.width)  / 2
                        let fitOriginY = (containerSize.height - fitImageSize.height) / 2

                        ForEach(0..<4, id: \.self) { idx in
                            let p = panelPoints[idx]
                            // Point in unscaled fitImage space
                            let unscaledX = fitOriginX + p.x * fitImageSize.width
                            let unscaledY = fitOriginY + p.y * fitImageSize.height
                            // Apply the same scale-from-center + offset that the image uses
                            let centerX = containerSize.width  / 2
                            let centerY = containerSize.height / 2
                            let px = centerX + (unscaledX - centerX) * renderScale + renderOffsetX
                            let py = centerY + (unscaledY - centerY) * renderScale + renderOffsetY

                            Circle()
                                .fill(Color.cyan)
                                .frame(width: 16, height: 16)
                                .overlay(Circle().stroke(Color.white, lineWidth: 2))
                                .shadow(color: .black.opacity(0.6), radius: 3)
                                .position(x: px, y: py)
                                .gesture(
                                    DragGesture()
                                        .onChanged { gesture in
                                            if dragStartPoints == nil {
                                                dragStartPoints = activePanel.getPoints()
                                                dragStartScale   = targetScale
                                                dragStartOffsetX = offsetX
                                                dragStartOffsetY = offsetY
                                            }
                                            guard var startPoints = dragStartPoints,
                                                  let startScale  = dragStartScale else { return }

                                            let dpX = gesture.translation.width  / (fitImageSize.width  * startScale)
                                            let dpY = gesture.translation.height / (fitImageSize.height * startScale)

                                            let pt   = startPoints[idx]
                                            let newX = max(0.0, min(1.0, pt.x + dpX))
                                            let newY = max(0.0, min(1.0, pt.y + dpY))
                                            startPoints[idx] = CGPoint(x: newX, y: newY)

                                            var updatedPanel = activePanel
                                            updatedPanel.polygonPoints = startPoints

                                            let xs = startPoints.map { $0.x }
                                            let ys = startPoints.map { $0.y }
                                            if let minX = xs.min(), let maxX = xs.max(),
                                               let minY = ys.min(), let maxY = ys.max() {
                                                updatedPanel.rect = CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
                                            }
                                            if activePanelIndex < page.panels.count {
                                                page.panels[activePanelIndex] = updatedPanel
                                            }
                                        }
                                        .onEnded { _ in
                                            dragStartPoints = nil
                                            dragStartScale   = nil
                                            dragStartOffsetX = nil
                                            dragStartOffsetY = nil
                                            onAdjustEnded?()
                                        }
                                )
                        }

                        // "Snap to Borders" button centered on the active panel
                        let fitOriginX2 = (containerSize.width  - fitImageSize.width)  / 2
                        let fitOriginY2 = (containerSize.height - fitImageSize.height) / 2
                        let midNX = panelRect.midX
                        let midNY = panelRect.midY
                        let unscaledMidX = fitOriginX2 + midNX * fitImageSize.width
                        let unscaledMidY = fitOriginY2 + midNY * fitImageSize.height
                        let centerX2 = containerSize.width  / 2
                        let centerY2 = containerSize.height / 2
                        let btnX = centerX2 + (unscaledMidX - centerX2) * renderScale + renderOffsetX
                        let btnY = centerY2 + (unscaledMidY - centerY2) * renderScale + renderOffsetY

                        Button(action: {
                            guard let nsImage = NSImage(contentsOfFile: page.imagePath),
                                  let cg = nsImage.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return }
                            let snapped = PanelSnapper.snapPoints(activePanel.getPoints(), in: cg)

                            var updatedPanel = activePanel
                            updatedPanel.polygonPoints = snapped

                            let xs = snapped.map { $0.x }
                            let ys = snapped.map { $0.y }
                            if let minX = xs.min(), let maxX = xs.max(),
                               let minY = ys.min(), let maxY = ys.max() {
                                updatedPanel.rect = CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
                            }
                            if activePanelIndex < page.panels.count {
                                withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                                    page.panels[activePanelIndex] = updatedPanel
                                }
                                onAdjustEnded?()
                            }
                        }) {
                            HStack(spacing: 5) {
                                Image(systemName: "sparkles")
                                Text("Snap to Borders")
                                    .font(.system(size: 11, weight: .bold))
                            }
                            .foregroundColor(.black)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(Capsule().fill(Color.cyan))
                            .shadow(radius: 3)
                        }
                        .buttonStyle(.plain)
                        .position(x: btnX, y: btnY)
                    }
                }
                .padding(.top, topPadding)
            }
            .animation(.spring(response: 0.45, dampingFraction: 0.85, blendDuration: 0), value: activePanelIndex)
            .animation(.spring(response: 0.45, dampingFraction: 0.85, blendDuration: 0), value: page.id)
        }
        .ignoresSafeArea()
    }

    private func calculateFitImageSize(imageSize: CGSize, containerSize: CGSize) -> CGSize {
        let imageAspect = imageSize.width / imageSize.height
        let containerAspect = containerSize.width / containerSize.height
        if imageAspect > containerAspect {
            let w = containerSize.width
            return CGSize(width: w, height: w / imageAspect)
        } else {
            let h = containerSize.height
            return CGSize(width: h * imageAspect, height: h)
        }
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
