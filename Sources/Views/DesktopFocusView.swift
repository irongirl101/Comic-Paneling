import SwiftUI

public struct DesktopFocusView: View {
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
            
            let activePanel = page.panels[safe: activePanelIndex] ?? ComicPanel(rect: CGRect(x: 0, y: 0, width: 1, height: 1), order: 0)
            let panelRect = activePanel.rect
            
            let panelWidthOnScreen = panelRect.width * fitImageSize.width
            let panelHeightOnScreen = panelRect.height * fitImageSize.height
            
            let targetScaleX = containerSize.width / max(1, panelWidthOnScreen)
            let targetScaleY = containerSize.height / max(1, panelHeightOnScreen)
            
            let targetScale = min(4.5, max(1.0, min(targetScaleX, targetScaleY)))
            
            let dx = (panelRect.midX - 0.5) * fitImageSize.width
            let dy = (panelRect.midY - 0.5) * fitImageSize.height
            
            let offsetX = -dx * targetScale
            let offsetY = -dy * targetScale
            
            ZStack {
                Color.black
                
                ComicImage(path: page.imagePath)
                    .aspectRatio(contentMode: .fit)
                    .frame(width: containerSize.width, height: containerSize.height)
                    .scaleEffect(targetScale)
                    .offset(x: offsetX, y: offsetY)
                
                // Top edge blur - soft and glasslike
                Rectangle()
                    .fill(.ultraThinMaterial)
                    .frame(height: 80)
                    .mask(
                        LinearGradient(
                            stops: [
                                .init(color: .white, location: 0.0),
                                .init(color: .white, location: 0.25), // top 20px is fully blurred
                                .init(color: .white.opacity(0.5), location: 0.6),
                                .init(color: .clear, location: 1.0)   // feathers out softly
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                    .allowsHitTesting(false)
                
                // Bottom edge blur - soft and glasslike
                Rectangle()
                    .fill(.ultraThinMaterial)
                    .frame(height: 80)
                    .mask(
                        LinearGradient(
                            stops: [
                                .init(color: .clear, location: 0.0),
                                .init(color: .white.opacity(0.5), location: 0.4),
                                .init(color: .white, location: 0.75), // bottom 20px is fully blurred
                                .init(color: .white, location: 1.0)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                    .allowsHitTesting(false)
            }
            .frame(width: containerSize.width, height: containerSize.height)
            .clipped()
            .animation(.spring(response: 0.4, dampingFraction: 0.8, blendDuration: 0), value: activePanelIndex)
            .animation(.spring(response: 0.4, dampingFraction: 0.8, blendDuration: 0), value: page.id)
        }
    }
    
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
        guard let img = NSImage(contentsOfFile: path) else {
            return CGSize(width: 800, height: 1200)
        }
        if let cg = img.cgImage(forProposedRect: nil, context: nil, hints: nil) {
            return CGSize(width: cg.width, height: cg.height)
        }
        return img.size
    }
}
