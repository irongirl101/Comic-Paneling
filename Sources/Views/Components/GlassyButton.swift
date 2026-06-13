import SwiftUI

public struct GlassyButton: View {
    public var icon: String
    public var label: String?
    public var action: () -> Void
    
    public init(icon: String, label: String? = nil, action: @escaping () -> Void) {
        self.icon = icon
        self.label = label
        self.action = action
    }
    
    public var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .bold))
                
                if let label = label {
                    Text(label)
                        .font(.system(size: 13, weight: .medium))
                }
            }
            .foregroundColor(.white)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(.ultraThinMaterial)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(Color.white.opacity(0.12), lineWidth: 1)
            )
            .shadow(color: Color.black.opacity(0.2), radius: 4, x: 0, y: 2)
        }
        .buttonStyle(.plain)
    }
}
