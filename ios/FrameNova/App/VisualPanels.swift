import SwiftUI

struct LayoutPanel:View {
    @ObservedObject var model:EditorModel
    @ViewState<Double> private var spacing = 0
    @ViewState<String?> private var chosen:String?
    private var count:Int {model.project.tracks.filter {!$0.hidden && ($0.kind == .main || $0.kind == .overlay)}.filter {$0.clips.contains(where:{$0.contains(model.playhead)})}.count}
    var body:some View {
        VStack(alignment:.leading,spacing:8) {
            Text(count <= 1 ? loc("Add overlays at the playhead, then pick a layout to arrange them in one frame.") : localized("Arranges the \(count) clips showing at the playhead. Drag on the preview to fine-tune each one."))
                .font(.system(size:12)).foregroundStyle(Palette.dim)
            ScrollView(.horizontal,showsIndicators:false) {HStack(alignment:.top,spacing:10) {
                ForEach(LayoutPreset.all) {preset in
                    let match = preset.cells.count == count || preset.id == "fit"
                    Button {
                        chosen = preset.id;model.change {$0.layout(preset,at:model.playhead,gap:spacing)}
                    } label:{VStack(spacing:5) {
                        Canvas {context,size in
                            context.fill(Path(CGRect(origin:.zero,size:size)),with:.color(Palette.surface3))
                            for (index,cell) in preset.cells.enumerated() {
                                let rect = CGRect(x:cell.x*size.width+2,y:cell.y*size.height+2,width:max(1,cell.w*size.width-4),height:max(1,cell.h*size.height-4))
                                context.fill(Path(rect),with:.color((match ? Palette.accent:Palette.dim).opacity(0.35+0.15*Double(index%3))))
                            }
                        }.frame(width:64,height:min(72,64/clamp(model.project.canvas.aspect.ratio,0.5,2.2)))
                            .overlay(Rectangle().stroke(.white.opacity(0.3),lineWidth:1))
                        Text(loc(preset.label)).font(.system(size:10)).lineLimit(1).foregroundStyle(match ? Palette.text:Palette.dim)
                    }.frame(width:72)}.buttonStyle(.plain).accessibilityLabel(loc(preset.label))
                }
            }.padding(.vertical,8)}
            ValueSlider(title:"Spacing",value:$spacing,range:0...0.05,format:{"\(($0*1000).rounded()/10)%"})
                .onChange(of:spacing) {_,value in if let id = chosen,let preset = LayoutPreset.all.first(where:{$0.id == id}) {model.change {$0.layout(preset,at:model.playhead,gap:value)}}}
        }
    }
}
struct FilterPreview:View {
    let id:String?
    let selected:Bool
    let onPick:()->Void
    private var colors:[Color] {
        [0xFF3B6EA8,0xFFE0A46A,0xFF5E8C4A,0xFFD8D2C8,0xFF2A2A2A].map {value in
            let r = Double((value>>16)&255)/255,g = Double((value>>8)&255)/255,b = Double(value&255)/255
            let output = id.map {FilterCube.apply($0,r,g,b,intensity:1)} ?? [r,g,b]
            return Color(red:output[0],green:output[1],blue:output[2])
        }
    }
    var body:some View {Button(action:onPick) {VStack(spacing:5) {
        RoundedRectangle(cornerRadius:10).fill(LinearGradient(colors:colors,startPoint:.topLeading,endPoint:.bottomTrailing)).frame(width:56,height:56)
            .overlay(RoundedRectangle(cornerRadius:10).stroke(selected ? Palette.accent:.clear,lineWidth:2))
        Text(filterName(id)).font(.system(size:11)).lineLimit(1).foregroundStyle(selected ? Palette.accent:Palette.text)
    }}.buttonStyle(.plain)}
}
struct EditGestureActions {var begin:()->Void;var end:()->Void}
private struct EditGestureKey:EnvironmentKey {static let defaultValue:EditGestureActions? = nil}
extension EnvironmentValues {
    var editGestureActions:EditGestureActions? {get {self[EditGestureKey.self]} set {self[EditGestureKey.self] = newValue}}
}
