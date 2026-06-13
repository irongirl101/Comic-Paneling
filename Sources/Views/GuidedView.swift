import SwiftUI
import CoreGraphics

#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

extension Collection {
    subscript(safe index: Index) -> Element? {
        return indices.contains(index) ? self[index] : nil
    }
}

public struct CutoutShape: Shape {
    public var rect: CGRect
    public var fitImageSize: CGSize
    public var scale: CGFloat
    public var offsetX: CGFloat
    public var offsetY: CGFloat
    
    // Conforms to Animatable for smooth morphing animations
    public var animatableData: AnimatablePair<
        AnimatablePair<CGFloat, CGFloat>, // scale, offsetX
        AnimatablePair<CGFloat, AnimatablePair<CGFloat, CGFloat>> // offsetY, rect.origin.x, rect.origin.y
    > {
        get {
            AnimatablePair(
                AnimatablePair(scale, offsetX),
                AnimatablePair(offsetY, AnimatablePair(rect.origin.x, rect.origin.y))
            )
        }
        set {
            scale = newValue.first.first
            offsetX = newValue.first.second
            offsetY = newValue.second.first
            rect.origin.x = newValue.second.second.first
            rect.origin.y = newValue.second.second.second
        }
    }
    
    public func path(in rect: CGRect) -> Path {
        var path = Path()
        // 1. Outer screen bounds
        path.addRect(rect)
        
        // 2. Compute the transformed panel boundary on screen
        let containerCenter = CGPoint(x: rect.width / 2, y: rect.height / 2)
        
        let left = containerCenter.x + (self.rect.minX - 0.5) * fitImageSize.width * scale + offsetX
        let right = containerCenter.x + (self.rect.maxX - 0.5) * fitImageSize.width * scale + offsetX
        let top = containerCenter.y + (self.rect.minY - 0.5) * fitImageSize.height * scale + offsetY
        let bottom = containerCenter.y + (self.rect.maxY - 0.5) * fitImageSize.height * scale + offsetY
        
        let cutoutRect = CGRect(x: left, y: top, width: max(0, right - left), height: max(0, bottom - top))
        
        // 3. Add rounded rect inside for the cutout spotlight
        path.addRoundedRect(in: cutoutRect, cornerSize: CGSize(width: 8, height: 8))
        
        return path
    }
}

public struct GuidedView: View {
    public var page: ComicPage
    public var activePanelIndex: Int
    
    public init(page: ComicPage, activePanelIndex: Int) {
        self.page = page
        self.activePanelIndex = activePanelIndex
    }
    
    public var body: some View {
        GeometryReader { containerGeo in
            let containerSize = containerGeo.size
            let imgSize = getImageSize(path: page.imagePath)
            let fitImageSize = calculateFitImageSize(imageSize: imgSize, containerSize: containerSize)
            
            // Get active panel, fallback to full page if index invalid
            let activePanel = page.panels[safe: activePanelIndex] ?? ComicPanel(rect: CGRect(x: 0, y: 0, width: 1, height: 1), order: 0)
            let panelRect = activePanel.rect
            
            // Convert relative panel width/height to absolute on-screen fit coordinates
            let panelWidthOnScreen = panelRect.width * fitImageSize.width
            let panelHeightOnScreen = panelRect.height * fitImageSize.height
            
            // Pad the focus slightly to fit beautifully inside the viewport margins
            let horizontalPadding: CGFloat = 32
            let verticalPadding: CGFloat = 80
            
            let targetScaleX = (containerSize.width - horizontalPadding) / max(1, panelWidthOnScreen)
            let targetScaleY = (containerSize.height - verticalPadding) / max(1, panelHeightOnScreen)
            
            // Choose the fit scale, cap it between 1.0x (whole page) and 4.0x (deep focus)
            let targetScale = min(4.0, max(1.0, min(targetScaleX, targetScaleY)))
            
            // Center difference of the panel compared to image center
            let dx = (panelRect.midX - 0.5) * fitImageSize.width
            let dy = (panelRect.midY - 0.5) * fitImageSize.height
            
            // Scaled shift translation
            let offsetX = -dx * targetScale
            let offsetY = -dy * targetScale
            
            ZStack {
                Color.black.edgesIgnoringSafeArea(.all)
                
                // Base Image
                ComicImage(path: page.imagePath)
                    .aspectRatio(contentMode: .fit)
                    .frame(width: containerSize.width, height: containerSize.height)
                    .scaleEffect(targetScale)
                    .offset(x: offsetX, y: offsetY)
                
                // Mask Overlay with cutout
                CutoutShape(
                    rect: panelRect,
                    fitImageSize: fitImageSize,
                    scale: targetScale,
                    offsetX: offsetX,
                    offsetY: offsetY
                )
                .fill(Color.black.opacity(0.65), style: FillStyle(eoFill: true))
                .edgesIgnoringSafeArea(.all)
            }
            .animation(.spring(response: 0.45, dampingFraction: 0.85, blendDuration: 0), value: activePanelIndex)
            .animation(.spring(response: 0.45, dampingFraction: 0.85, blendDuration: 0), value: page.id)
        }
    }
    
    // Calculates aspect fit box dimensions
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
    
    // Gets size of source image in a platform-agnostic way
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
}
