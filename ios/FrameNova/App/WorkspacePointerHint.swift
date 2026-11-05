import SwiftUI

struct WorkspacePointerHint: Equatable {
    var location: CGPoint
    var symbol: String
}

struct WorkspacePointerHintKey: PreferenceKey {
    static let defaultValue: WorkspacePointerHint? = nil
    static func reduce(value: inout WorkspacePointerHint?, nextValue: () -> WorkspacePointerHint?) {
        if let next = nextValue() {value = next}
    }
}

/// Draws outside the ruler and dividers without changing their hit areas.
struct WorkspacePointerHintOverlay: View {
    var hint: WorkspacePointerHint?
    var body: some View {
        GeometryReader { proxy in
            if let hint {
                let origin = proxy.frame(in:.global).origin
                Image(systemName:hint.symbol)
                    .font(.system(size:12,weight:.bold)).foregroundStyle(.white)
                    .frame(width:26,height:26).background(Palette.accent,in:Circle())
                    .position(x:hint.location.x-origin.x+40,y:hint.location.y-origin.y+32)
            }
        }
        .transaction {$0.animation = nil}
        .allowsHitTesting(false).accessibilityHidden(true)
    }
}
