import SwiftUI
import UIKit

struct TouchTimeline: UIViewRepresentable {
    @ObservedObject var model:EditorModel
    @ObservedObject var display:TimelineDisplay
    @ObservedObject private var thumbnails = TimelineThumbnails.shared
    @ObservedObject private var waveforms = AudioWaveforms.shared
    var onTransition:(String)->Void
    var onText:(String)->Void
    var onTrack:(Track)->Void
    func makeUIView(context:Context) -> TouchTimelineCanvas {
        let view = TouchTimelineCanvas();view.model = model;view.display = display;return view
    }
    func updateUIView(_ view:TouchTimelineCanvas,context:Context) {
        view.model = model;view.display = display
        view.onTransition = onTransition;view.onText = onText;view.onTrack = onTrack
        view.setNeedsDisplay()
    }
    static func dismantleUIView(_ view:TouchTimelineCanvas,coordinator:()) {view.stopFling()}
}

final class TouchTimelineCanvas:UIView,UIGestureRecognizerDelegate {
    weak var model:EditorModel?
    weak var display:TimelineDisplay?
    var onTransition:((String)->Void)?
    var onText:((String)->Void)?
    var onTrack:((Track)->Void)?
    private struct Row {var track:Track;var rect:CGRect}
    private enum Hit {case clip(Clip,Track),handle(Clip,Bool),transition(String),header(Track),lock(Track),gap(Int64),empty}
    private enum Mode {case scrub,trim(Clip,Bool),move(Clip,Track)}
    private var mode:Mode?
    private var verticalOffset:CGFloat = 0
    private var delta = CGPoint.zero
    private var origin = CGPoint.zero
    private var last = CGPoint.zero
    private var scrub = TimelineScrubPosition(position:0)
    private var pinchStart:Double = 70
    private var fling:CADisplayLink?
    private var velocity:CGFloat = 0
    private var lastFrame:CFTimeInterval = 0
    private var lastTap:(String,CFTimeInterval)?
    private var snapTime:Int64?
    private var pan:UIPanGestureRecognizer!
    private var hold:UILongPressGestureRecognizer!
    private var viewport:TimelineViewport {TimelineViewport(width:bounds.width,playhead:model?.playhead ?? 0,pointsPerSecond:display?.pointsPerSecond ?? 70)}
    private func x(_ time:Int64) -> CGFloat {viewport.position(time)}
    private func height(_ kind:TrackKind) -> CGFloat {switch kind {case .main:return 58;case .overlay:return 46;case .text:return 30;case .audio:return 38}}
    private var rows:[Row] {
        guard let project = model?.project else {return []}
        var y:CGFloat = 29-verticalOffset
        return project.tracks.map {track in let rect = CGRect(x:0,y:y,width:bounds.width,height:height(track.kind));y += rect.height+5;return Row(track:track,rect:rect)}
    }
    override init(frame:CGRect) {
        super.init(frame:frame);isOpaque = true;backgroundColor = UIColor(argb:0xFF0E0E12)
        accessibilityIdentifier = "editor.touchTimeline"
        isMultipleTouchEnabled = true;isAccessibilityElement = true;accessibilityTraits = .adjustable
        pan = UIPanGestureRecognizer(target:self,action:#selector(panned(_:)));pan.maximumNumberOfTouches = 1;pan.delegate = self
        hold = UILongPressGestureRecognizer(target:self,action:#selector(held(_:)));hold.minimumPressDuration = 0.45;hold.allowableMovement = 8;hold.delegate = self
        pan.require(toFail:hold)
        let tap = UITapGestureRecognizer(target:self,action:#selector(tapped(_:)));tap.require(toFail:pan);tap.require(toFail:hold)
        let pinch = UIPinchGestureRecognizer(target:self,action:#selector(pinched(_:)));pinch.delegate = self
        for recognizer in [pan!,hold!,tap,pinch] {addGestureRecognizer(recognizer)}
        accessibilityLabel = "Timeline. Swipe to scrub. Hold a clip to move it. Drag the selected clip's white handles to trim."
    }
    required init?(coder:NSCoder) {fatalError("init(coder:) is unavailable")}
    override func accessibilityIncrement() {if let model {model.scrub(model.playhead+1_000_000)}}
    override func accessibilityDecrement() {if let model {model.scrub(model.playhead-1_000_000)}}
    override func layoutSubviews() {super.layoutSubviews();setNeedsDisplay()}
    func stopFling() {fling?.invalidate();fling = nil;lastFrame = 0}
    func gestureRecognizer(_ recognizer:UIGestureRecognizer,shouldReceive touch:UITouch) -> Bool {stopFling();return true}
    override func gestureRecognizerShouldBegin(_ recognizer:UIGestureRecognizer) -> Bool {
        if recognizer === hold {
            if case .clip(_,let track) = hit(hold.location(in:self)) {return !track.locked}
            return false
        }
        return true
    }
    private func transitions(_ row:Row) -> [(Clip,CGPoint)] {
        guard row.track.kind == .main,row.track.clips.count>1 else {return []}
        return (1..<row.track.clips.count).compactMap {index in
            let previous = row.track.clips[index-1],clip = row.track.clips[index]
            guard clip.startUs<=previous.endUs+2_000,clip.id != model?.selected,previous.id != model?.selected else {return nil}
            return (clip,CGPoint(x:x(clip.startUs+(clip.transitionIn?.durationUs ?? 0)/2),y:row.rect.midY))
        }
    }
    private func hit(_ point:CGPoint) -> Hit {
        guard point.y>=24,let model else {return .empty}
        guard let row = rows.first(where:{$0.rect.contains(point)}) else {return .empty}
        if point.x<60 {return point.x>=30 ? .lock(row.track):.header(row.track)}
        if let clip = row.track.clips.first(where:{$0.id == model.selected}),!row.track.locked {
            if abs(point.x-x(clip.startUs))<16 {return .handle(clip,true)}
            if abs(point.x-x(clip.endUs))<16 {return .handle(clip,false)}
        }
        for (clip,center) in transitions(row) where abs(point.x-center.x)<14 && abs(point.y-center.y)<14 {return .transition(clip.id)}
        if let clip = row.track.clips.last(where:{point.x>=x($0.startUs) && point.x<=x($0.endUs)}) {return .clip(clip,row.track)}
        let time = viewport.time(at:point.x)
        return row.track.kind == .main && model.project.mainGap(at:time) != nil ? .gap(time):.empty
    }
    @objc private func tapped(_ recognizer:UITapGestureRecognizer) {
        guard let model else {return}
        switch hit(recognizer.location(in:self)) {
        case .clip(let clip,_):
            let now = CACurrentMediaTime()
            if clip.text != nil,lastTap?.0 == clip.id,now-(lastTap?.1 ?? 0)<0.32 {model.selected = clip.id;onText?(clip.id);lastTap = nil}
            else {model.selectedGap = nil;model.selected = model.selected == clip.id ? nil:clip.id;lastTap = (clip.id,now)}
        case .handle(let clip,_):model.selected = clip.id
        case .header(let track):if track.kind != .text {onTrack?(track)}
        case .lock(let track):model.change {p in if let i = p.tracks.firstIndex(where:{$0.id == track.id}) {p.tracks[i].locked.toggle()}}
        case .transition(let id):model.selected = id;onTransition?(id)
        case .gap(let time):model.selected = nil;model.selectedGap = time
        case .empty:model.selected = nil;model.selectedGap = nil
        }
        setNeedsDisplay()
    }
    @objc private func panned(_ recognizer:UIPanGestureRecognizer) {
        guard let model,let display else {return}
        let point = recognizer.location(in:self)
        switch recognizer.state {
        case .began:
            let translation = recognizer.translation(in:self)
            origin = CGPoint(x:point.x-translation.x,y:point.y-translation.y);last = origin;delta = .zero
            if case .handle(let clip,let start) = hit(origin) {mode = .trim(clip,start)}
            else {mode = .scrub;scrub = TimelineScrubPosition(position:model.playhead);model.scrub(model.playhead)}
            updatePan(point)
        case .changed:updatePan(point)
        case .ended:
            updatePan(point)
            if case .trim(let clip,let start) = mode {
                let amount = trimAmount(clip,start:start)
                model.change {if start {$0.trimStart(clip.id,delta:amount)} else {$0.trimEnd(clip.id,delta:amount)}}
            } else if case .scrub = mode {
                velocity = recognizer.velocity(in:self).x
                if abs(velocity)>400 {fling = CADisplayLink(target:self,selector:#selector(tick(_:)));fling?.add(to:.main,forMode:.common)}
            }
            mode = nil;snapTime = nil;setNeedsDisplay()
        case .cancelled,.failed:mode = nil;snapTime = nil;setNeedsDisplay()
        default:break
        }
        _ = display
    }
    private func updatePan(_ point:CGPoint) {
        guard let model,let display else {return}
        delta = CGPoint(x:point.x-origin.x,y:point.y-origin.y)
        if case .scrub = mode {
            model.scrub(scrub.move(delta:point.x-last.x,pointsPerSecond:display.pointsPerSecond,duration:model.project.durationUs))
            let content = 29+model.project.tracks.reduce(CGFloat(0)) {$0+height($1.kind)+5}+46
            verticalOffset = clamp(verticalOffset-(point.y-last.y),0,max(0,content-bounds.height))
        }
        last = point;setNeedsDisplay()
    }
    @objc private func tick(_ link:CADisplayLink) {
        guard let model,let display else {stopFling();return}
        if lastFrame == 0 {lastFrame = link.timestamp;return}
        let dt = min(0.05,link.timestamp-lastFrame);lastFrame = link.timestamp
        velocity *= exp(-5*dt)
        let time = scrub.move(delta:velocity*dt,pointsPerSecond:display.pointsPerSecond,duration:model.project.durationUs)
        model.scrub(time);setNeedsDisplay()
        if abs(velocity)<15 || time == 0 || time == model.project.durationUs {stopFling()}
    }
    @objc private func held(_ recognizer:UILongPressGestureRecognizer) {
        guard let model else {return}
        let point = recognizer.location(in:self)
        switch recognizer.state {
        case .began:
            guard case .clip(let clip,let track) = hit(point),!track.locked else {return}
            model.scrub(model.playhead);model.selected = clip.id;mode = .move(clip,track);origin = point;delta = .zero
            UIImpactFeedbackGenerator(style:.medium).impactOccurred()
        case .changed:delta = CGPoint(x:point.x-origin.x,y:point.y-origin.y)
        case .ended:
            if case .move(let clip,let source) = mode,let target = dropTarget(clip,source:source,y:point.y) {
                let time = movedStart(clip)
                model.change {if target.fresh {$0.moveToNewTrack(clip.id,kind:target.kind,at:time)} else if let id = target.id {$0.move(clip.id,to:id,at:time)}}
            }
            mode = nil;snapTime = nil
        case .cancelled,.failed:mode = nil;snapTime = nil
        default:break
        }
        setNeedsDisplay()
    }
    private func dropTarget(_ clip:Clip,source:Track,y:CGFloat) -> (id:String?,kind:TrackKind,fresh:Bool)? {
        guard let project = model?.project else {return nil}
        if let row = rows.first(where:{y >= $0.rect.minY && y < $0.rect.maxY+5}),project.accepts(clip,kind:row.track.kind),!row.track.locked {return (row.track.id,row.track.kind,false)}
        let kind:TrackKind = clip.text != nil ? .text : clip.audioOnly || project.asset(clip.assetID)?.type == .audio ? .audio:.overlay
        let compatible = rows.filter {project.accepts(clip,kind:$0.track.kind)}
        if y < (compatible.first?.rect.minY ?? 29) || y > (rows.last?.rect.maxY ?? 29) {return (nil,kind,true)}
        return nil
    }
    private func movedStart(_ clip:Clip) -> Int64 {
        guard let model,let display else {return clip.startUs}
        let raw = clip.startUs+Int64(delta.x/display.pointsPerSecond*1_000_000)
        let best = display.geometry.snappedStart(raw,duration:clip.durationUs,project:model.project,playhead:model.playhead,excluding:clip.id)
        snapTime = best != max(0,raw) ? best:nil;return best
    }
    private func trimAmount(_ clip:Clip,start:Bool) -> Int64 {
        guard let model,let display else {return 0}
        let edge = start ? clip.startUs:clip.endUs,raw = edge+Int64(delta.x/display.pointsPerSecond*1_000_000)
        let best = display.geometry.snap(raw,project:model.project,playhead:model.playhead,excluding:clip.id)
        snapTime = best != raw ? best:nil;return best-edge
    }
    @objc private func pinched(_ recognizer:UIPinchGestureRecognizer) {
        guard let display else {return}
        if recognizer.state == .began {stopFling();mode = nil;pinchStart = display.pointsPerSecond}
        display.pointsPerSecond = clamp(pinchStart*recognizer.scale,8,1600);setNeedsDisplay()
    }
    override func draw(_ rect:CGRect) {
        guard let context = UIGraphicsGetCurrentContext(),let model else {return}
        UIColor(argb:0xFF0E0E12).setFill();context.fill(bounds)
        accessibilityValue = "Playhead \(formatTime(model.playhead))"+(model.clip.map {"; Start \(formatTime($0.startUs)); End \(formatTime($0.endUs))"} ?? "")
        drawRuler(context)
        context.saveGState();context.clip(to:CGRect(x:0,y:24,width:bounds.width,height:max(0,bounds.height-24)))
        for row in rows where row.rect.maxY>=24 && row.rect.minY<bounds.height {
            UIColor(argb:0xFF17171D).setFill();context.fill(row.rect)
            if row.track.kind == .main,let selected = model.selectedGap,let gap = model.project.mainGap(at:selected) {
                let rect = CGRect(x:x(gap.start),y:row.rect.minY,width:x(gap.end)-x(gap.start),height:row.rect.height)
                UIColor.white.withAlphaComponent(0.15).setFill();context.fill(rect);UIColor.white.setStroke();context.stroke(rect,width:2)
            }
            let clips = row.track.clips.sorted {($0.id == model.selected ? 1:0)<($1.id == model.selected ? 1:0)}
            for var clip in clips {
                if case .move(let moving,_) = mode,moving.id == clip.id {continue}
                if case .trim(let original,let start) = mode,original.id == clip.id {
                    var copy = model.project;let delta = trimAmount(original,start:start)
                    if start {copy.trimStart(clip.id,delta:delta)} else {copy.trimEnd(clip.id,delta:delta)}
                    clip = copy.clip(clip.id) ?? clip
                }
                drawClip(clip,row:row,context:context)
            }
            for (clip,center) in transitions(row) where center.x >= -14 && center.x <= bounds.width+14 {
                let box = CGRect(x:center.x-8,y:center.y-8,width:16,height:16)
                (clip.transitionIn == nil ? UIColor.white:UIColor(argb:0xFF8B6CFF)).setFill();UIBezierPath(roundedRect:box,cornerRadius:4).fill()
                text("=",in:box,color:clip.transitionIn == nil ? .black:.white,size:12)
            }
            do {
                UIColor(argb:0xFF202028).setFill();context.fill(CGRect(x:0,y:row.rect.minY,width:60,height:row.rect.height))
                let icon = row.track.kind == .text ? "textformat" : row.track.hidden ? "eye.slash" : row.track.muted ? "speaker.slash" : row.track.kind == .audio ? "waveform":"film"
                UIImage(systemName:icon)?.withTintColor(.lightGray,renderingMode:.alwaysOriginal).draw(in:CGRect(x:7,y:row.rect.midY-8,width:16,height:16))
                UIImage(systemName:row.track.locked ? "lock.fill":"lock.open")?.withTintColor(row.track.locked ? .systemYellow:.lightGray,renderingMode:.alwaysOriginal).draw(in:CGRect(x:37,y:row.rect.midY-8,width:16,height:16))
            }
        }
        if case .move(let clip,let track) = mode,let row = rows.first(where:{$0.track.id == track.id}) {
            var moved = clip;moved.startUs = movedStart(clip)
            context.saveGState();context.setAlpha(0.85)
            drawClip(moved,row:Row(track:track,rect:row.rect.offsetBy(dx:0,dy:delta.y)),context:context)
            context.restoreGState()
        }
        if let snapTime {UIColor(argb:0xFF2FD1C1).setStroke();context.setLineWidth(1);context.move(to:CGPoint(x:x(snapTime),y:24));context.addLine(to:CGPoint(x:x(snapTime),y:bounds.height));context.strokePath()}
        context.restoreGState()
        UIColor.white.setStroke();context.setLineWidth(2);context.move(to:CGPoint(x:bounds.midX,y:0));context.addLine(to:CGPoint(x:bounds.midX,y:bounds.height));context.strokePath()
        UIColor.white.setFill();context.fillEllipse(in:CGRect(x:bounds.midX-4,y:16,width:8,height:8))
    }
    private func drawRuler(_ context:CGContext) {
        guard let display else {return}
        UIColor(argb:0xFF17171D).setFill();context.fill(CGRect(x:0,y:0,width:bounds.width,height:24))
        let major = [0.1,0.25,0.5,1,2,5,10,15,30,60,120,300].first {$0*display.pointsPerSecond>=90} ?? 600
        let minor = major/5,start = max(0,Double(viewport.time(at:0))/1_000_000)
        var index = Int(floor(start/minor))
        while Double(index)*minor <= Double(viewport.time(at:bounds.width))/1_000_000 {
            let time = Int64(Double(index)*minor*1_000_000),position = x(time),big = index%5 == 0
            UIColor.gray.setStroke();context.setLineWidth(1);context.move(to:CGPoint(x:position,y:big ? 16:20));context.addLine(to:CGPoint(x:position,y:24));context.strokePath()
            if big {text(major<1 ? String(format:"%.1f",Double(time)/1_000_000):formatTime(time),in:CGRect(x:position+3,y:1,width:70,height:15),color:.gray,size:9)}
            index += 1
        }
    }
    private func drawClip(_ clip:Clip,row:Row,context:CGContext) {
        guard let model else {return}
        let box = CGRect(x:x(clip.startUs),y:row.rect.minY,width:max(2,x(clip.endUs)-x(clip.startUs)),height:row.rect.height)
        guard box.maxX>=0,box.minX<=bounds.width else {return}
        let selected = model.selected == clip.id
        context.saveGState();context.setAlpha(row.track.hidden ? 0.35:1)
        let path = UIBezierPath(roundedRect:box,cornerRadius:6)
        let color:UInt32 = row.track.kind == .main ? 0xFF3A3A48 : row.track.kind == .overlay ? 0xFF4A3B7A : row.track.kind == .text ? 0xFFB0457E:0xFF1F6F6A
        UIColor(argb:color).setFill();path.fill();context.saveGState();path.addClip()
        if let asset = model.project.asset(clip.assetID),asset.type != .audio,!clip.audioOnly {
            let step:CGFloat = max(16,box.height*clamp(Double(asset.width)/Double(max(1,asset.height)),0.5,2))
            var tile = max(0,Int((max(0,box.minX)-box.minX)/step))
            let end = min(box.maxX,bounds.width)
            while box.minX+CGFloat(tile)*step<end {
                let tileX = box.minX+CGFloat(tile)*step
                let at = clip.sourceTime(at:clip.startUs+Int64(CGFloat(tile)*step/(display?.pointsPerSecond ?? 70)*1_000_000))
                if let image = TimelineThumbnails.shared.image(asset,at:at) {
                    let target = CGRect(x:tileX,y:box.minY,width:step,height:box.height)
                    let factor = max(target.width/image.size.width,target.height/image.size.height)
                    let size = CGSize(width:image.size.width*factor,height:image.size.height*factor)
                    context.saveGState();context.clip(to:target);image.draw(in:CGRect(x:target.midX-size.width/2,y:target.midY-size.height/2,width:size.width,height:size.height));context.restoreGState()
                }
                tile += 1
            }
            UIColor.black.withAlphaComponent(0.35).setFill();context.fill(CGRect(x:box.minX,y:box.minY,width:box.width,height:16))
        }
        if let asset = model.project.asset(clip.assetID),asset.hasAudio,(clip.audioOnly || row.track.kind == .audio || asset.type == .audio),let peaks = AudioWaveforms.shared.peaks(asset,ready:{[weak self] in self?.setNeedsDisplay()}) {
            var position = max(0,box.minX)
            UIColor(argb:0xFF2FD1C1).setStroke();context.setLineWidth(2)
            while position<min(box.maxX,bounds.width) {
                let timeline = clip.startUs+Int64((position-box.minX)/(display?.pointsPerSecond ?? 70)*1_000_000)
                let index = Int(clip.sourceTime(at:timeline)/AudioWaveforms.stepUs)
                let value = index<peaks.count ? peaks[index]:0
                let amplitude = CGFloat(clamp(Double(value)*min(clip.volume,1.5),0.02,1))*box.height*0.42
                context.move(to:CGPoint(x:position,y:box.midY-amplitude));context.addLine(to:CGPoint(x:position,y:box.midY+amplitude));position += 3
            }
            context.strokePath()
        }
        var badges:[String] = []
        if clip.speed != 1 {badges.append("\(clip.speed.formatted())×")}
        if clip.text == nil && clip.volume == 0 {badges.append("muted")}
        if clip.filter != nil {badges.append("fx")}
        let title = (clip.text?.text ?? model.project.asset(clip.assetID)?.name ?? "Clip")+(badges.isEmpty ? "":"  "+badges.joined(separator:" · "))
        text(title,in:CGRect(x:max(0,box.minX)+6,y:box.minY+2,width:max(1,min(box.maxX,bounds.width)-max(0,box.minX)-12),height:16),color:.white,size:10)
        UIColor.white.withAlphaComponent(0.7).setStroke();context.setLineWidth(1)
        if clip.fadeInUs>0 {context.move(to:CGPoint(x:box.minX,y:box.maxY));context.addLine(to:CGPoint(x:box.minX+CGFloat(clip.fadeInUs)/CGFloat(max(1,clip.durationUs))*box.width,y:box.minY));context.strokePath()}
        if clip.fadeOutUs>0 {context.move(to:CGPoint(x:box.maxX-CGFloat(clip.fadeOutUs)/CGFloat(max(1,clip.durationUs))*box.width,y:box.minY));context.addLine(to:CGPoint(x:box.maxX,y:box.maxY));context.strokePath()}
        context.restoreGState()
        for frame in clip.keyframes {UIColor.white.setFill();let center = CGPoint(x:x(clip.startUs+frame.offsetUs),y:box.maxY-5);let diamond = UIBezierPath();diamond.move(to:CGPoint(x:center.x,y:center.y-3));diamond.addLine(to:CGPoint(x:center.x+3,y:center.y));diamond.addLine(to:CGPoint(x:center.x,y:center.y+3));diamond.addLine(to:CGPoint(x:center.x-3,y:center.y));diamond.close();diamond.fill()}
        if selected {
            UIColor.white.setStroke();path.lineWidth = 2;path.stroke()
            UIColor.white.setFill()
            for edge in [box.minX,box.maxX] {UIBezierPath(roundedRect:CGRect(x:edge-5,y:box.minY+2,width:10,height:box.height-4),cornerRadius:3).fill()}
        }
        context.restoreGState()
    }
    private func text(_ value:String,in rect:CGRect,color:UIColor,size:CGFloat) {
        let paragraph = NSMutableParagraphStyle();paragraph.lineBreakMode = .byTruncatingTail
        (value as NSString).draw(in:rect,withAttributes:[.font:UIFont.systemFont(ofSize:size),.foregroundColor:color,.paragraphStyle:paragraph])
    }
}
