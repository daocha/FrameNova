import SwiftUI

struct PreviewLayer:Identifiable {
    let clip:Clip
    let rect:CGRect
    let rotation:Double
    var id:String {clip.id}
    func contains(_ point:CGPoint)->Bool {
        let x = point.x-rect.midX,y = point.y-rect.midY,r = -rotation * .pi/180
        return abs(x*cos(r)-y*sin(r))<=rect.width/2 && abs(x*sin(r)+y*cos(r))<=rect.height/2
    }
}
struct PreviewPane:View {
    @ObservedObject var model:EditorModel
    @ViewState<Transform?> private var base:Transform?
    @ViewState<CGSize> private var translation = .zero
    @ViewState<Double> private var magnification = 1
    @ViewState<Double> private var rotation = 0
    @ViewState<Set<String>> private var gestures = []
    @ViewState<Bool> private var snapX = false
    @ViewState<Bool> private var snapY = false
    var body:some View {
        GeometryReader {geometry in
            let available = geometry.size,ratio = model.project.canvas.aspect.ratio
            let width = min(available.width,available.height*ratio),height = width/ratio
            let canvas = CGRect(x:(available.width-width)/2,y:(available.height-height)/2,width:width,height:height)
            let layers = layers(in:canvas)
            ZStack(alignment:.topLeading) {
                Color.black
                PlayerSurface(player:model.player).frame(width:width,height:height).position(x:canvas.midX,y:canvas.midY)
                ForEach(layers.filter {$0.id == model.selected}) {layer in
                    Rectangle().stroke(Palette.accent,lineWidth:1.5).frame(width:layer.rect.width,height:layer.rect.height)
                        .rotationEffect(.degrees(layer.rotation)).position(x:layer.rect.midX,y:layer.rect.midY)
                        .allowsHitTesting(false)
                }
                if snapX {Rectangle().fill(Palette.teal).frame(width:1,height:height).position(x:canvas.midX,y:canvas.midY).allowsHitTesting(false)}
                if snapY {Rectangle().fill(Palette.teal).frame(width:width,height:1).position(x:canvas.midX,y:canvas.midY).allowsHitTesting(false)}
                if model.project.durationUs == 0 {Text("Add videos and photos to start").foregroundStyle(Palette.dim).frame(width:available.width,height:available.height)}
            }
            .clipped().contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance:0).onChanged {value in
                if !gestures.contains("drag") {
                    let hit = layers.reversed().first {$0.contains(value.startLocation)}
                    model.selected = hit?.id
                    begin("drag")
                }
                translation = value.translation;apply(canvas:canvas)
            }.onEnded {_ in end("drag")})
            .simultaneousGesture(MagnificationGesture().onChanged {value in begin("scale");magnification = value;apply(canvas:canvas)}.onEnded {_ in end("scale")})
            .simultaneousGesture(RotationGesture().onChanged {value in begin("rotation");rotation = value.degrees;apply(canvas:canvas)}.onEnded {_ in end("rotation")})
        }.padding(12).accessibilityIdentifier("editor.preview")
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
        snapX = abs(t.cx-0.5)<0.015;snapY = abs(t.cy-0.5)<0.015
        if snapX {t.cx = 0.5};if snapY {t.cy = 0.5}
        t.scale = clamp(t.scale*magnification,0.05,8);t.rotation += rotation
        let rightAngle = (t.rotation/90).rounded()*90;if abs(t.rotation-rightAngle)<3 {t.rotation = rightAngle}
        let time = model.playhead,fps = model.project.canvas.fps
        model.liveVisualEdit {$0.setTransform(t,at:time,fps:fps)}
    }
    private func layers(in canvas:CGRect)->[PreviewLayer] {
        var layers:[PreviewLayer] = []
        for track in model.project.tracks.reversed() where !track.hidden && track.kind != .audio {
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
