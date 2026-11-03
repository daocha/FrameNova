import Foundation

struct TimelineViewport {
    var width: Double
    var playhead: Int64
    var pointsPerSecond: Double
    func position(_ time: Int64) -> Double { width/2 + Double(time-playhead)/1_000_000*pointsPerSecond }
    func time(at x: Double) -> Int64 { playhead + Int64((x-width/2)/max(0.1,pointsPerSecond)*1_000_000) }
}
struct TimelineScrubPosition {
    var position: Int64
    mutating func move(delta: Double, pointsPerSecond: Double, duration: Int64) -> Int64 {
        position = clamp(position-Int64(delta/max(0.1,pointsPerSecond)*1_000_000),0,max(0,duration))
        return position
    }
}
struct OrderedMediaSelection {
    private(set) var ids: [String] = []
    var limit = 50
    mutating func toggle(_ id: String) {
        if let index = ids.firstIndex(of:id) {ids.remove(at:index)}
        else if ids.count < limit {ids.append(id)}
    }
    mutating func set(_ id:String, selected:Bool) {
        if selected {if !ids.contains(id) && ids.count < limit {ids.append(id)}}
        else {ids.removeAll {$0 == id}}
    }
    mutating func clear() {ids = []}
}
extension TimelineGeometry {
    func snappedStart(_ time:Int64,duration:Int64,project:Project,playhead:Int64,excluding:String) -> Int64 {
        guard snapping else {return max(0,time)}
        var candidates:[Int64] = [0,playhead,playhead-duration]
        for track in project.tracks {for clip in track.clips where clip.id != excluding {
            candidates += [clip.startUs,clip.endUs,clip.startUs-duration,clip.endUs-duration]
        }}
        let closest = candidates.min {abs($0-time)<abs($1-time)} ?? time
        return Double(abs(closest-time))/1_000_000.0*pointsPerSecond < 10 ? max(0,closest):max(0,time)
    }
}
extension Project {
    func mainGap(at time:Int64) -> (start:Int64,end:Int64)? {
        let clips = tracks[mainIndex].clips
        guard !clips.contains(where:{$0.contains(time)}),let next = clips.first(where:{$0.startUs>time}) else {return nil}
        let previous = clips.filter {$0.endUs<=time}.map(\.endUs).max() ?? 0
        return next.startUs-previous >= 2_000 ? (previous,next.startUs):nil
    }
    func accepts(_ clip:Clip,kind:TrackKind) -> Bool {
        if clip.text != nil {return kind == .text}
        if clip.audioOnly || asset(clip.assetID)?.type == .audio {return kind == .audio}
        return kind == .main || kind == .overlay
    }
    mutating func moveToNewTrack(_ id:String,kind:TrackKind,at time:Int64) {
        guard var clip = clip(id),track(id)?.locked != true,kind != .main,accepts(clip,kind:kind) else {return}
        delete(id);clip.startUs = max(0,time);clip.transitionIn = nil
        let index = kind == .text ? 0 : kind == .overlay ? tracks.firstIndex(where:{$0.kind == .overlay}) ?? mainIndex : tracks.count
        tracks.insert(Track(kind:kind,clips:[clip]),at:index);normalize()
    }
}

extension Project {
    func usesSameComposition(as other:Project)->Bool {
        guard assets == other.assets,canvas.aspect == other.canvas.aspect,canvas.tier == other.canvas.tier,canvas.fps == other.canvas.fps,tracks.count == other.tracks.count else {return false}
        for (a,b) in zip(tracks,other.tracks) {
            guard a.id == b.id,a.kind == b.kind,a.muted == b.muted,a.hidden == b.hidden,a.clips.count == b.clips.count else {return false}
            for (x,y) in zip(a.clips,b.clips) {
                guard x.id == y.id,x.assetID == y.assetID,x.startUs == y.startUs,x.srcInUs == y.srcInUs,x.srcOutUs == y.srcOutUs,x.speed == y.speed,x.volume == y.volume,x.fadeInUs == y.fadeInUs,x.fadeOutUs == y.fadeOutUs,x.audioOnly == y.audioOnly else {return false}
            }
        }
        return true
    }
}
