import SwiftUI

/// Rows of items that wrap onto new lines, like Android's chip rows.
struct FlowLayout: Layout {
    var spacing:CGFloat = 8
    var lineSpacing:CGFloat = 0
    private func rows(_ subviews:Subviews,width:CGFloat) -> (frames:[CGRect],size:CGSize) {
        var frames:[CGRect] = [],x:CGFloat = 0,y:CGFloat = 0,rowHeight:CGFloat = 0,maxX:CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x > 0 && x+size.width > width {y += rowHeight+lineSpacing;x = 0;rowHeight = 0}
            frames.append(CGRect(x:x,y:y,width:size.width,height:size.height))
            x += size.width+spacing;rowHeight = max(rowHeight,size.height);maxX = max(maxX,x-spacing)
        }
        return (frames,CGSize(width:maxX,height:y+rowHeight))
    }
    func sizeThatFits(proposal:ProposedViewSize,subviews:Subviews,cache:inout ()) -> CGSize {rows(subviews,width:proposal.width ?? .infinity).size}
    func placeSubviews(in bounds:CGRect,proposal:ProposedViewSize,subviews:Subviews,cache:inout ()) {
        let laid = rows(subviews,width:bounds.width)
        for (view,frame) in zip(subviews,laid.frames) {view.place(at:CGPoint(x:bounds.minX+frame.minX,y:bounds.minY+frame.minY),proposal:ProposedViewSize(frame.size))}
    }
}

/// Android's filter chip: 32pt tall, outlined, filled when selected. The row around it keeps a 48pt touch height.
struct Chip: View {
    let title:String
    var selected = false
    let action:()->Void
    var body: some View {
        Button(action:action) {
            Text(title).font(.system(size:14,weight:.medium)).lineLimit(1).foregroundStyle(selected ? Color(argb:0xFFE8DEF8):Palette.text).padding(.horizontal,12).frame(height:32)
                .background(selected ? Color(argb:0xFF4A4458):.clear,in:RoundedRectangle(cornerRadius:8))
                .overlay(RoundedRectangle(cornerRadius:8).stroke(selected ? .clear:Color(argb:0xFF938F99),lineWidth:1))
                .padding(.vertical,8).contentShape(Rectangle())
        }.buttonStyle(.plain)
    }
}

/// Android's outlined button: 40pt tall, fully rounded, accent text.
struct OutlinedAction: View {
    let title:String
    var enabled = true
    let action:()->Void
    var body: some View {
        Button(action:action) {
            Text(title).font(.system(size:14,weight:.medium)).lineLimit(1).foregroundStyle(Palette.accent).padding(.horizontal,24).frame(height:40)
                .overlay(Capsule().stroke(Color(argb:0xFF938F99),lineWidth:1)).padding(.vertical,4).contentShape(Rectangle())
        }.buttonStyle(.plain).disabled(!enabled).opacity(enabled ? 1:0.4)
    }
}

/// Android's text button: accent text, 40pt tall.
struct TextAction: View {
    let title:String
    var enabled = true
    var prominent = false
    let action:()->Void
    var body: some View {
        Button(action:action) {Text(title).font(.system(size:14,weight:prominent ? .semibold:.medium)).foregroundStyle(Palette.accent).padding(.horizontal,12).frame(height:40).contentShape(Rectangle())}
            .buttonStyle(.plain).disabled(!enabled).opacity(enabled ? 1:0.4)
    }
}

/// Android's filled button.
struct FilledAction: View {
    let title:String
    var enabled = true
    let action:()->Void
    var body: some View {
        Button(action:action) {Text(title).font(.system(size:14,weight:.medium)).foregroundStyle(.white).padding(.horizontal,24).frame(height:40).background(Palette.accent,in:Capsule())}
            .buttonStyle(.plain).disabled(!enabled).opacity(enabled ? 1:0.4)
    }
}

/// The small dim heading above a group of controls.
struct PanelLabel: View {
    let text:String
    init(_ text:String) {self.text = text}
    var body: some View {Text(loc(text)).font(.system(size:12)).foregroundStyle(Palette.dim)}
}

func percentText(_ value:Double) -> String {"\(Int((value*100).rounded()))%"}
func secondsText(_ value:Double) -> String {String(format:"%.1fs",value)}
/// A signed percentage, as Android's adjust sliders show it.
func signedText(_ value:Double) -> String {(value > 0 ? "+":"")+"\(Int((value*100).rounded()))"}
