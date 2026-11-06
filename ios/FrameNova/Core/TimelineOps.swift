import Foundation

extension Project {
    @discardableResult mutating func extractAudio(_ id:String)->String? {
        guard let source = clip(id),track(id)?.locked == false,!source.audioOnly,
              asset(source.assetID)?.type == .video,asset(source.assetID)?.hasAudio == true else {return nil}
        var audio = source
        audio.id = newID();audio.audioOnly = true;audio.transitionIn = nil;audio.keyframes = []
        audio.transform = Transform();audio.crop = CropRect();audio.adjust = Adjust();audio.filter = nil
        update(id) {$0.volume = 0}
        place(audio,kind:.audio)
        return audio.id
    }

    mutating func normalize() {
        var laid: [Clip] = []
        for var c in tracks[mainIndex].clips.sorted(by: { $0.startUs < $1.startUs }) {
            c.startUs = max(0, c.startUs)
            if let prev = laid.last {
                if var tr = c.transitionIn {
                    let maxD = min(prev.durationUs, c.durationUs)/2
                    if maxD < minimumClip || c.startUs > prev.endUs+2_000 { c.transitionIn = nil }
                    else { tr.durationUs = clamp(tr.durationUs, minimumClip, maxD); c.transitionIn = tr; c.startUs = prev.endUs-tr.durationUs }
                }
                if c.transitionIn == nil && c.startUs < prev.endUs { c.startUs = prev.endUs }
            } else { c.transitionIn = nil }
            laid.append(c)
        }
        tracks[mainIndex].clips = laid
        tracks.removeAll { $0.kind != .main && $0.clips.isEmpty }
        for i in tracks.indices { tracks[i].clips.sort { $0.startUs < $1.startUs } }
    }
    mutating func update(_ id: String, _ change: (inout Clip) -> Void) {
        for t in tracks.indices { if let c = tracks[t].clips.firstIndex(where: { $0.id == id }) { change(&tracks[t].clips[c]) } }
        normalize()
    }
    mutating func delete(_ id: String) { for i in tracks.indices { tracks[i].clips.removeAll { $0.id == id } }; normalize() }
    mutating func place(_ clip: Clip, kind: TrackKind, preferred: String? = nil) {
        func free(_ t: Track) -> Bool { t.kind == kind && !t.locked && !t.clips.contains { $0.startUs < clip.endUs && clip.startUs < $0.endUs } }
        let candidates = tracks.indices.filter { free(tracks[$0]) }
        let target = candidates.first { tracks[$0].id == preferred } ?? (kind == .overlay ? candidates.last : candidates.first)
        if let i = target { tracks[i].clips.append(clip) }
        else {
            let index = kind == .text ? 0 : kind == .overlay ? mainIndex : tracks.count
            tracks.insert(Track(kind: kind, clips: [clip]), at: index)
        }
        normalize()
    }
    func mainInsertTime(_ time: Int64) -> Int64 {
        let clips = tracks[mainIndex].clips, end = clips.last?.endUs ?? 0
        if time >= end { return end }
        guard let c = clips.last(where: { $0.contains(time) }) else { return max(0, time) }
        return time < c.startUs+c.durationUs/2 ? c.startUs : c.endUs
    }
    mutating func insertMain(_ clips: [Clip], at time: Int64) {
        guard !clips.isEmpty else { return }
        let at = max(0, time), original = tracks[mainIndex].clips
        let before = original.filter { $0.startUs + ($0.transitionIn?.durationUs ?? 0) < at }
        var after = original.filter { $0.startUs + ($0.transitionIn?.durationUs ?? 0) >= at }
        var cursor = at
        let inserted = clips.map { c -> Clip in var c = c; c.startUs = cursor; c.transitionIn = nil; cursor += c.durationUs; return c }
        if !after.isEmpty { after[0].startUs = max(after[0].startUs, cursor); after[0].transitionIn = nil }
        tracks[mainIndex].clips = before + inserted + after; normalize()
    }
    mutating func add(_ media: [MediaAsset], kind: TrackKind, at time: Int64) {
        assets += media.filter { a in !assets.contains { $0.id == a.id } }
        let clips = media.filter { kind != .main || $0.type != .audio }.map {
            Clip(assetID: $0.id, startUs: time, srcOutUs: $0.type == .image ? 3_000_000 : max(minimumClip, $0.durationUs),
                 transform: Transform(scale: kind == .overlay ? 0.5 : 1), audioOnly: kind == .audio && $0.type != .audio)
        }
        if kind == .main { insertMain(clips, at: mainInsertTime(time)) }
        else { for c in clips { place(c, kind: kind) } }
    }
    @discardableResult mutating func split(_ id: String, at time: Int64) -> String? {
        guard let c = clip(id), let t = tracks.firstIndex(where: { $0.clips.contains { $0.id == id } }),
              time-c.startUs >= minimumClip, c.endUs-time >= minimumClip else { return nil }
        let cut = c.sourceTime(at: time), offset = time-c.startUs
        var a = c, b = c; a.srcOutUs = cut; a.fadeOutUs = 0
        b.id = newID(); b.startUs = time; b.srcInUs = cut; b.transitionIn = nil; b.fadeInUs = 0
        if !c.keyframes.isEmpty {
            let boundary = c.transform(at: time)
            a.keyframes = c.keyframes.filter { $0.offsetUs < offset } + [Keyframe(offsetUs: offset, transform: boundary)]
            b.keyframes = [Keyframe(offsetUs: 0, transform: boundary)] + c.keyframes.filter { $0.offsetUs > offset }.map { Keyframe(offsetUs: $0.offsetUs-offset, transform: $0.transform, smooth: $0.smooth) }
        }
        tracks[t].clips.removeAll { $0.id == id }; tracks[t].clips += [a,b]; normalize(); return b.id
    }
    @discardableResult mutating func duplicate(_ id: String) -> String? {
        guard var c = clip(id), let t = track(id) else { return nil }
        c.id = newID(); c.transitionIn = nil
        if t.kind == .main { insertMain([c], at: c.endUs) }
        else { c.startUs = c.endUs; place(c, kind: t.kind, preferred: t.id) }; return c.id
    }
    mutating func trimStart(_ id: String, delta: Int64) {
        guard let c = clip(id), let track = track(id), !track.locked else { return }
        let index = track.clips.firstIndex(where:{$0.id == id}) ?? 0
        let prev = index > 0 ? track.clips[index-1] : nil
        let stretch = c.text != nil || asset(c.assetID)?.type == .image
        let limit = c.transitionIn != nil ? 0 : max(0, c.startUs-(prev?.endUs ?? 0))
        let d = clamp(delta, -min(limit, stretch ? 3_600_000_000 : Int64(Double(c.srcInUs)/c.speed)), max(0,c.durationUs-minimumClip))
        guard d != 0 else {return}
        let boundary = c.transform(at:c.startUs+d)
        update(id) { v in
            v.startUs += d
            if stretch { v.srcOutUs -= v.srcInUs + Int64(Double(d)*v.speed); v.srcInUs = 0 }
            else { v.srcInUs += Int64(Double(d)*v.speed) }
            v.keyframes = v.keyframes.filter { $0.offsetUs >= d }.map { Keyframe(offsetUs: $0.offsetUs-d, transform: $0.transform, smooth: $0.smooth) }
            // Preserve the evaluated pose even when no later animation keys survive.
            if d>0 && !c.keyframes.isEmpty && !v.keyframes.contains(where:{$0.offsetUs == 0}) {
                v.keyframes.insert(Keyframe(offsetUs:0,transform:boundary),at:0)
            }
            if let tr = v.transitionIn { let overlap = (prev?.endUs ?? c.startUs)-v.startUs; v.transitionIn = overlap >= minimumClip ? Transition(type: tr.type, durationUs: min(tr.durationUs, overlap)) : nil }
        }
    }
    mutating func trimEnd(_ id: String, delta: Int64) {
        guard let c = clip(id), let t = track(id), !t.locked else { return }
        let index = t.clips.firstIndex(where:{$0.id == id}) ?? 0
        let next = index+1 < t.clips.count ? t.clips[index+1]:nil
        let stretch = c.text != nil || asset(c.assetID)?.type == .image
        let d = t.kind == .main ? delta : min(delta, max(0,(next?.startUs ?? Int64.max)-c.endUs))
        let upper = stretch ? 3_600_000_000 : max(c.srcOutUs, asset(c.assetID)?.durationUs ?? c.srcOutUs)
        var trimmed = c
        trimmed.srcOutUs = clamp(c.srcOutUs+Int64(Double(d)*c.speed), c.srcInUs+Int64(Double(minimumClip)*c.speed), upper)
        guard let ti = tracks.firstIndex(where:{$0.id == t.id}) else {return}
        tracks[ti].clips[index] = trimmed
        if let next, let transition = next.transitionIn, trimmed.endUs < c.endUs {
            let overlap = trimmed.endUs-next.startUs
            tracks[ti].clips[index+1].transitionIn = overlap >= minimumClip ? Transition(type:transition.type,durationUs:min(transition.durationUs,overlap)):nil
        }
        normalize()
    }
    mutating func setSpeed(_ id: String, speed: Double) {
        update(id) { c in let s = clamp(speed, 0.1, 10), ratio = c.speed/s; c.speed = s; c.keyframes = c.keyframes.map { Keyframe(offsetUs: Int64(Double($0.offsetUs)*ratio), transform: $0.transform, smooth: $0.smooth) } }
    }
    mutating func setTransition(_ id: String, transition: Transition?) {
        guard let c = clip(id), track(id)?.kind == .main else { return }
        update(id) { $0.transitionIn = transition }
        guard let updated = clip(id) else { return }
        let delta = updated.startUs-c.startUs
        if let i = tracks[mainIndex].clips.firstIndex(where: { $0.id == id }) {
            for k in tracks[mainIndex].clips.indices where k > i { tracks[mainIndex].clips[k].startUs += delta }
        }
        normalize()
    }
    mutating func move(_ id: String, to targetID: String, at time: Int64) {
        guard var c = clip(id), let source = track(id), !source.locked,
              let target = tracks.first(where: { $0.id == targetID }), !target.locked else { return }
        let category: TrackKind = c.text != nil ? .text : c.audioOnly || asset(c.assetID)?.type == .audio ? .audio : .main
        guard target.kind == category || (category == .main && target.kind == .overlay) else { return }
        delete(id); c.startUs = max(0,time); c.transitionIn = nil
        if target.kind == .main {
            if source.kind != .main { c.transform = Transform(); c.keyframes = [] }
            if tracks[mainIndex].clips.contains(where: { $0.startUs < c.endUs && c.startUs < $0.endUs }) { insertMain([c], at: mainInsertTime(c.startUs)) }
            else { tracks[mainIndex].clips.append(c); normalize() }
        } else { place(c, kind: target.kind, preferred: target.id) }
    }
    mutating func toggleKeyframe(_ id: String, at time: Int64) {
        let fps = canvas.fps
        update(id) { c in
            guard time >= c.startUs && time <= c.endUs else { return }
            let offset = time-c.startUs
            if let i = c.keyframes.firstIndex(where: { abs($0.offsetUs-offset) <= 500_000/Int64(fps) }) { c.keyframes.remove(at: i) }
            else { c.keyframes.append(Keyframe(offsetUs: offset, transform: c.transform(at: time))); c.keyframes.sort { $0.offsetUs < $1.offsetUs } }
        }
    }
    mutating func deleteGap(at time: Int64) {
        let clips = tracks[mainIndex].clips
        guard !clips.contains(where: { $0.contains(time) }), let next = clips.first(where: { $0.startUs > time }) else { return }
        let prev = clips.filter { $0.endUs <= time }.map(\.endUs).max() ?? 0, length = next.startUs-prev
        for i in tracks[mainIndex].clips.indices where tracks[mainIndex].clips[i].startUs >= next.startUs { tracks[mainIndex].clips[i].startUs -= length }
        normalize()
    }
}
