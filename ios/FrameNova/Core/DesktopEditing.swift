import Foundation

struct TimelineGeometry {
    var pointsPerSecond: Double = 70
    var snapping = true

    func time(at x: Double) -> Int64 {
        Int64(max(0, x) / max(0.1, pointsPerSecond) * 1_000_000)
    }

    func position(_ time: Int64) -> Double { Double(time) / 1_000_000 * pointsPerSecond }

    func snap(_ time: Int64, project: Project, playhead: Int64, excluding clipID: String? = nil) -> Int64 {
        let time = max(0, time)
        guard snapping else { return time }
        var edges: [Int64] = [playhead, 0]
        for track in project.tracks {for clip in track.clips where clip.id != clipID {edges += [clip.startUs, clip.endUs]}}
        guard let closest = edges.min(by: { abs($0-time) < abs($1-time) }),
              abs(closest-time) <= Int64(8 / max(0.1, pointsPerSecond) * 1_000_000) else { return time }
        return closest
    }
}

extension Project {
    mutating func addLibraryAssets(_ media: [MediaAsset]) {
        for asset in media where !assets.contains(where: { $0.id == asset.id }) { assets.append(asset) }
    }

    /// Resolves the destination before adding media, so an incompatible drop cannot create orphan assets.
    @discardableResult mutating func insertAsset(_ asset: MediaAsset, kind: TrackKind, trackID: String? = nil, at time: Int64) -> String? {
        guard kind != .text, kind != .main || !tracks[mainIndex].locked else { return nil }
        if let trackID {
            guard let track = tracks.first(where: { $0.id == trackID }), track.kind == kind, !track.locked else { return nil }
        }
        guard kind == .audio ? asset.hasAudio : asset.type != .audio else { return nil }
        addLibraryAssets([asset])
        let clip = Clip(assetID: asset.id, startUs: max(0, time),
                        srcOutUs: asset.type == .image ? 3_000_000 : max(minimumClip, asset.durationUs),
                        transform: Transform(scale: kind == .overlay ? 0.5 : 1),
                        audioOnly: kind == .audio && asset.type != .audio)
        if kind == .main {
            if tracks[mainIndex].clips.contains(where: {$0.startUs < clip.endUs && clip.startUs < $0.endUs}) {
                insertMain([clip], at: mainInsertTime(time))
            } else {tracks[mainIndex].clips.append(clip); normalize()}
        } else { place(clip, kind: kind, preferred: trackID) }
        return clip.id
    }

    func adjacentCut(to time: Int64, forward: Bool) -> Int64 {
        var edges: [Int64] = [0, durationUs]
        for track in tracks {for clip in track.clips {edges += [clip.startUs, clip.endUs]}}
        return forward ? edges.filter { $0 > time }.min() ?? durationUs : edges.filter { $0 < time }.max() ?? 0
    }
}
