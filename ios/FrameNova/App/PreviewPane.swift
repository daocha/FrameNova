import SwiftUI

struct PreviewLayer:Identifiable {
    let clip:Clip
    let rect:CGRect
    let rotation:Double
    var id:String {clip.id}
    var corners:[CGPoint] {EditorPresentation.corners(of:rect,rotation:rotation)}
    func contains(_ point:CGPoint,slop:Double = 0)->Bool {
        let x = point.x-rect.midX,y = point.y-rect.midY,r = -rotation * .pi/180
        return abs(x*cos(r)-y*sin(r))<=rect.width/2+slop && abs(x*sin(r)+y*cos(r))<=rect.height/2+slop
    }
    func outside(_ canvas:CGRect,tolerance:Double)->Bool {
        corners.contains {!canvas.insetBy(dx:-tolerance,dy:-tolerance).contains($0)}
    }
}
struct PreviewPane:View {
    @ObservedObject var model:EditorModel
    @StateObject private var pointer = DesktopPointerState()
    var onText:((String)->Void)? = nil
    @ViewState<Transform?> private var base:Transform?
    @ViewState<CGSize> private var translation = .zero
    @ViewState<Double> private var magnification = 1
    @ViewState<Double> private var rotation = 0
    @ViewState<Set<String>> private var gestures = []
    @ViewState<Bool> private var snapX = false
    @ViewState<Bool> private var snapY = false
    @ViewState<CGPoint?> private var dragStart = nil
    @ViewState<String?> private var dragTarget = nil
    @ViewState<CGPoint?> private var resizeCenter = nil
    @ViewState<Double> private var resizeDistance = 1
    @ViewState<Bool> private var moved = false
    @ViewState<String?> private var lastTapID = nil
    @ViewState<Double> private var lastTapTime = 0
    private let outsideColor = Color(argb:0xFFFFA726)
    var body:some View {
        GeometryReader {geometry in
            let canvas = EditorPresentation.canvasRect(in:geometry.size,aspect:model.project.canvas.aspect.ratio)
            let layers = layers(in:canvas)
            let selected = layers.first {model.selectedIDs.count == 1 && $0.id == model.selected}
            let outside = selected?.outside(canvas,tolerance:canvas.width/Double(model.project.canvas.size.width)) == true
            ZStack(alignment:.topLeading) {
                Color(argb:0xFF2A2A33)
                PlayerSurface(player:model.player).frame(width:canvas.width,height:canvas.height).background(.black).clipped().position(x:canvas.midX,y:canvas.midY)
                Rectangle().stroke(.white.opacity(0.55),lineWidth:1.5)
                    .frame(width:canvas.width+1.5,height:canvas.height+1.5).position(x:canvas.midX,y:canvas.midY)
                    .allowsHitTesting(false).accessibilityIdentifier("editor.canvasBoundary")
                Canvas {context,size in
                    if let selected {
                        let color:Color = outside ? outsideColor:.white
                        var path = Path();path.addLines(selected.corners);path.closeSubpath()
                        context.stroke(path,with:.color(color),style:StrokeStyle(lineWidth:1.5,dash:outside ? [7,4]:[]))
                        for point in selected.corners {
                            context.fill(Path(ellipseIn:CGRect(x:point.x-4.5,y:point.y-4.5,width:9,height:9)),with:.color(color))
                            context.fill(Path(ellipseIn:CGRect(x:point.x-3,y:point.y-3,width:6,height:6)),with:.color(Palette.accent))
                        }
                    }
                    if snapX {var path = Path();path.move(to:CGPoint(x:canvas.midX,y:canvas.minY));path.addLine(to:CGPoint(x:canvas.midX,y:canvas.maxY));context.stroke(path,with:.color(Palette.teal),style:StrokeStyle(lineWidth:1,dash:[6,5]))}
                    if snapY {var path = Path();path.move(to:CGPoint(x:canvas.minX,y:canvas.midY));path.addLine(to:CGPoint(x:canvas.maxX,y:canvas.midY));context.stroke(path,with:.color(Palette.teal),style:StrokeStyle(lineWidth:1,dash:[6,5]))}
                }.allowsHitTesting(false)
                if outside {
                    Text("Partly outside the canvas: only the part inside is in the video")
                        .font(.system(size:11)).foregroundStyle(.black).padding(.horizontal,8).padding(.vertical,3)
                        .background(outsideColor,in:RoundedRectangle(cornerRadius:6)).frame(maxWidth:.infinity).padding(.top,6)
                        .allowsHitTesting(false).accessibilityIdentifier("editor.outsideCanvas")
                }
                if model.project.durationUs == 0 {Text("Add videos and photos to start").foregroundStyle(Palette.dim).frame(width:geometry.size.width,height:geometry.size.height).allowsHitTesting(false)}
            }
            .clipped().contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance:0).onChanged {value in
                if dragStart == nil {
                    dragStart = value.startLocation;moved = false
                    let corner = selected?.corners.contains {hypot($0.x-value.startLocation.x,$0.y-value.startLocation.y)<28} == true
                    let current = selected.flatMap {$0.contains(value.startLocation,slop:$0.clip.text == nil ? 0:20) || corner ? $0:nil}
                    dragTarget = current?.id ?? hit(value.startLocation,layers:layers)?.id
                    if corner,let selected {resizeCenter = CGPoint(x:selected.rect.midX,y:selected.rect.midY);resizeDistance = max(1,hypot(value.startLocation.x-selected.rect.midX,value.startLocation.y-selected.rect.midY))}
                }
                guard let target = dragTarget,hypot(value.translation.width,value.translation.height)>=10 || moved else {return}
                if !moved {model.selected = target;model.selectedGap = nil;moved = true;begin("drag")}
                if let center = resizeCenter {
                    magnification = hypot(value.location.x-center.x,value.location.y-center.y)/resizeDistance
                } else {translation = value.translation}
                apply(canvas:canvas)
            }.onEnded {value in
                if !moved && gestures.isEmpty {
                    let target = hit(value.startLocation,layers:layers),now = CACurrentMediaTime()
                    if pointer.command,let target {model.selectClip(target.id,extending:true)}
                    else if !pointer.command {model.selected = target?.id}
                    model.selectedGap = nil
                    if let target,target.clip.text != nil,lastTapID == target.id,now-lastTapTime<0.32 {onText?(target.id);lastTapID = nil}
                    else {lastTapID = target?.id;lastTapTime = now}
                }
                end("drag");dragStart = nil;dragTarget = nil;resizeCenter = nil;moved = false
            })
            .simultaneousGesture(MagnificationGesture().onChanged {value in begin("scale");magnification = value;apply(canvas:canvas)}.onEnded {_ in end("scale")})
            .simultaneousGesture(RotationGesture().onChanged {value in begin("rotation");rotation = value.degrees;apply(canvas:canvas)}.onEnded {_ in end("rotation")})
        }
        #if targetEnvironment(macCatalyst)
        .background {DesktopPointerModifiers(state:pointer)}
        #endif
        .accessibilityIdentifier("editor.preview")
    }
    private func hit(_ point:CGPoint,layers:[PreviewLayer])->PreviewLayer? {
        layers.reversed().first {$0.clip.text != nil && $0.contains(point,slop:20)} ?? layers.reversed().first {$0.contains(point)}
    }
    private func begin(_ gesture:String) {
        guard model.canEditSelection else {return}
        if base == nil {model.scrub(model.playhead);base = model.clip?.transform(at:model.playhead);model.beginGesture()}
        gestures.insert(gesture)
    }
    private func end(_ gesture:String) {
        gestures.remove(gesture)
        if gestures.isEmpty {model.endGesture();base = nil;translation = .zero;magnification = 1;rotation = 0;snapX = false;snapY = false}
    }
    private func apply(canvas:CGRect) {
        guard var t = base,canvas.width>0,canvas.height>0 else {return}
        t.cx += translation.width/canvas.width;t.cy += translation.height/canvas.height
        if resizeCenter == nil {
            snapX = abs(t.cx-0.5)*canvas.width<(snapX ? 20:8);snapY = abs(t.cy-0.5)*canvas.height<(snapY ? 20:8)
        }
        if snapX {t.cx = 0.5};if snapY {t.cy = 0.5}
        t.scale = clamp(t.scale*magnification,0.05,20);t.rotation += rotation
        let rightAngle = (t.rotation/90).rounded()*90;if abs(t.rotation-rightAngle)<3 {t.rotation = rightAngle}
        let time = model.playhead,fps = model.project.canvas.fps
        model.liveVisualEdit {$0.setTransform(t,at:time,fps:fps)}
    }
    private func layers(in canvas:CGRect)->[PreviewLayer] {
        var layers:[PreviewLayer] = []
        for track in model.project.tracks.reversed() where !track.hidden && !track.locked && track.kind != .audio {
            var visible = track.clips.filter {$0.contains(model.playhead) && !$0.audioOnly}
            if track.kind == .main {visible.sort {a,b in
                let i = track.clips.firstIndex(where:{$0.id == a.id}) ?? 0,j = track.clips.firstIndex(where:{$0.id == b.id}) ?? 0
                return !TransitionEffects.upper(track.clips,index:i) && TransitionEffects.upper(track.clips,index:j)
            }}
            for clip in visible {
                var t = clip.transform(at:model.playhead)
                let fx = TransitionEffects.at(track,clipID:clip.id,time:model.playhead)
                t.cx += fx.dx;t.cy += fx.dy;t.scale *= fx.scale;t.opacity *= fx.alpha
                if let text = clip.text {let animation = TextAnimationMath.at(text,local:model.playhead-clip.startUs,duration:clip.durationUs);t.cy += animation.dy;t.scale *= animation.scale;t.opacity *= animation.alpha}
                if t.opacity<0.01 {continue}
                var width:Double,height:Double
                if let text = clip.text {
                    let attributes = TextFonts.layoutAttributes(text,size:canvas.height*text.size)
                    let size = (text.text as NSString).boundingRect(with:CGSize(width:canvas.width*0.9,height:canvas.height),options:[.usesLineFragmentOrigin,.usesFontLeading],attributes:attributes,context:nil).size
                    width = size.width*t.scale;height = size.height*t.scale
                } else if let asset = model.project.asset(clip.assetID),asset.width>0,asset.height>0 {
                    let w = Double(asset.width)*max(0.01,1-clip.crop.left-clip.crop.right),h = Double(asset.height)*max(0.01,1-clip.crop.top-clip.crop.bottom)
                    let factor = min(canvas.width/w,canvas.height/h)*t.scale;width = w*factor;height = h*factor
                } else {continue}
                layers.append(PreviewLayer(clip:clip,rect:CGRect(x:canvas.minX+t.cx*canvas.width-width/2,y:canvas.minY+t.cy*canvas.height-height/2,width:width,height:height),rotation:t.rotation))
            }
        }
        return layers
    }
}
