import SwiftUI

public struct PageMiniMap: View {
    public var page: ComicPage
    public var activePanelIndex: Int
    
    public init(page: ComicPage, activePanelIndex: Int) {
        self.page = page
        self.activePanelIndex = activePanelIndex
    }
    
    public var body: some View {
        VStack(spacing: 4) {
            ZStack {
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color.black.opacity(0.65))
                    .frame(width: 80, height: 120)
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(Color.white.opacity(0.15), lineWidth: 1)
                    )
                
                GeometryReader { geo in
                    let w = geo.size.width
                    let h = geo.size.height
                    
                    ForEach(0..<page.panels.count, id: \.self) { idx in
                        let panel = page.panels[idx]
                        let pts = panel.getPoints()
                        let screenPoints = pts.map { p in
                            CGPoint(x: p.x * w, y: p.y * h)
                        }
                        
                        let isActive = idx == activePanelIndex
                        
                        let strokeColor = isActive ? Color.cyan : Color.white.opacity(0.35)
                        let lineWidth: CGFloat = isActive ? 1.5 : 0.5
                        let fillColor = isActive ? Color.cyan.opacity(0.15) : Color.clear
                        let shadowColor = isActive ? Color.cyan.opacity(0.4) : Color.clear
                        
                        ZStack {
                            Path { path in
                                path.move(to: screenPoints[0])
                                path.addLine(to: screenPoints[1])
                                path.addLine(to: screenPoints[2])
                                path.addLine(to: screenPoints[3])
                                path.closeSubpath()
                            }
                            .fill(fillColor)
                            
                            Path { path in
                                path.move(to: screenPoints[0])
                                path.addLine(to: screenPoints[1])
                                path.addLine(to: screenPoints[2])
                                path.addLine(to: screenPoints[3])
                                path.closeSubpath()
                            }
                            .stroke(strokeColor, lineWidth: lineWidth)
                        }
                        .shadow(color: shadowColor, radius: 2)
                    }
                }
                .frame(width: 80, height: 120)
            }
            
            Text("Page \(page.pageNumber)")
                .font(.system(size: 9, weight: .bold))
                .foregroundColor(.white.opacity(0.5))
        }
        .padding(6)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(.ultraThinMaterial)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        )
        .shadow(radius: 4)
    }
}
