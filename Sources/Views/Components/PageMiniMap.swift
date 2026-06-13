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
                        let rect = panel.rect
                        
                        let px = rect.origin.x * w
                        let py = rect.origin.y * h
                        let pw = rect.size.width * w
                        let ph = rect.size.height * h
                        
                        let isActive = idx == activePanelIndex
                        
                        let strokeColor = isActive ? Color.cyan : Color.white.opacity(0.35)
                        let lineWidth: CGFloat = isActive ? 1.5 : 0.5
                        let fillColor = isActive ? Color.cyan.opacity(0.15) : Color.clear
                        let shadowColor = isActive ? Color.cyan.opacity(0.4) : Color.clear
                        let posX = px + pw / 2
                        let posY = py + ph / 2
                        let pwVal = max(2, pw)
                        let phVal = max(2, ph)
                        
                        ZStack {
                            RoundedRectangle(cornerRadius: 2)
                                .fill(fillColor)
                            
                            RoundedRectangle(cornerRadius: 2)
                                .stroke(strokeColor, lineWidth: lineWidth)
                        }
                        .frame(width: pwVal, height: phVal)
                        .position(x: posX, y: posY)
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
