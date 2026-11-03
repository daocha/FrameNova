import SwiftUI

@MainActor final class TimelineDisplay: ObservableObject {
    @Published var pointsPerSecond: Double = 70
    @Published var rowHeight: Double = 55
    @Published var snapping = true
    var geometry: TimelineGeometry { TimelineGeometry(pointsPerSecond: pointsPerSecond, snapping: snapping) }
    func zoom(_ factor: Double) { pointsPerSecond = clamp(pointsPerSecond * factor, 0.1, 600) }
    func fit(duration: Int64, width: Double) {
        pointsPerSecond = clamp(max(1, width - 168) / max(1, Double(duration) / 1_000_000), 0.1, 600)
    }
}

struct TimelineView: View {
    @ObservedObject var model: EditorModel
    @ObservedObject var display: TimelineDisplay
    var desktop = false
    @EditorFocus<Bool> private var keyboardFocus
    @ViewState<Double?> private var initialScale: Double?
    @ViewState<String?> private var movingID: String?
    @ViewState<CGSize> private var movement = .zero
    @ViewState<String?> private var trimID: String?
    @ViewState<Bool> private var trimStart = false
    @ViewState<Double> private var trimDelta = 0
    @ViewState<Int64?> private var dropTime: Int64?
    @ViewState<String?> private var hoveredTrack: String?

    private var geometry: TimelineGeometry { display.geometry }
    private var headerWidth: Double { desktop ? 136 : 90 }
    private var rowHeight: Double { desktop ? display.rowHeight : 55 }
    private func x(_ time: Int64) -> Double { geometry.position(time) }

    var body: some View {
        GeometryReader { viewport in
            let width = max(Double(viewport.size.width) - headerWidth, max(600, x(model.project.durationUs) + 180))
            ScrollView(.vertical) {
                HStack(alignment: .top, spacing: 0) {
                    headers
                    ScrollViewReader { reader in
                        ScrollView(.horizontal) {
                            VStack(alignment: .leading, spacing: 5) {
                                ruler(width: width)
                                ForEach(model.project.tracks) { track in trackRow(track, width: width) }
                                if desktop {
                                    newTrackRow(.overlay, width: width)
                                    newTrackRow(.audio, width: width)
                                }
                            }
                            .overlay(alignment: .topLeading) { playhead }
                        }
                        .onChange(of: model.playhead) { _, time in
                            if model.playing { withAnimation(.linear(duration: 0.12)) { reader.scrollTo("playhead", anchor: .center) } }
                        }
                        .simultaneousGesture(MagnificationGesture().onChanged { factor in
                            if initialScale == nil { initialScale = display.pointsPerSecond }
                            display.pointsPerSecond = clamp((initialScale ?? 70) * factor, 0.1, 600)
                        }.onEnded { _ in initialScale = nil })
                    }
                }
            }
        }
        .padding(.vertical, 5)
        .background(Palette.bg)
        .focusable()
        .focused($keyboardFocus)
        .focusEffectDisabled()
        .onKeyPress(.space) { guard desktop else { return .ignored }; model.play(); return .handled }
        .onKeyPress(keys: [.leftArrow], phases: [.down, .repeat]) { press in
            guard desktop else { return .ignored }
            if press.modifiers.contains(.command) {model.seek(0)}
            else if press.modifiers.contains(.option) {model.seek(model.project.adjacentCut(to:model.playhead,forward:false))}
            else {model.stepFrames(press.modifiers.contains(.shift) ? -10 : -1)}
            return .handled
        }
        .onKeyPress(keys: [.rightArrow], phases: [.down, .repeat]) { press in
            guard desktop else { return .ignored }
            if press.modifiers.contains(.command) {model.seek(model.project.durationUs)}
            else if press.modifiers.contains(.option) {model.seek(model.project.adjacentCut(to:model.playhead,forward:true))}
            else {model.stepFrames(press.modifiers.contains(.shift) ? 10 : 1)}
            return .handled
        }
        .onKeyPress(.delete) { guard desktop else { return .ignored }; model.delete(); return .handled }
        .onKeyPress(.escape) { guard desktop else { return .ignored }; model.selected = nil; return .handled }
        .accessibilityIdentifier(desktop ? "desktop.timeline" : "editor.timeline")
    }

    private var headers: some View {
        VStack(spacing: 5) {
            HStack {
                if desktop { Text("Tracks").font(.caption.bold()); Spacer() }
                else {
                    Button { display.zoom(1/1.3) } label: { Image(systemName: "minus.magnifyingglass") }
                    Button { display.zoom(1.3) } label: { Image(systemName: "plus.magnifyingglass") }
                }
            }.frame(height: 28).padding(.horizontal, 8)
            ForEach(model.project.tracks) { track in
                VStack(alignment: .leading, spacing: 8) {
                    Text(track.kind == .overlay ? "Layer" : track.kind.rawValue.capitalized).font(.caption2.bold())
                    HStack(spacing: desktop ? 16 : 8) {
                        trackButton(track, key: \.muted, icon: track.muted ? "speaker.slash" : "speaker.wave.1", label: "Mute track")
                        trackButton(track, key: \.hidden, icon: track.hidden ? "eye.slash" : "eye", label: "Hide track")
                        trackButton(track, key: \.locked, icon: track.locked ? "lock.fill" : "lock.open", label: "Lock track")
                    }.font(.system(size: desktop ? 12 : 10))
                }.padding(.horizontal, 8).frame(width: headerWidth, height: rowHeight, alignment: .leading).background(Palette.surface2)
            }
            if desktop {
                Text("New layer").font(.caption2).frame(width: headerWidth, height: 36)
                Text("New audio").font(.caption2).frame(width: headerWidth, height: 36)
            }
        }.frame(width: headerWidth)
    }

    private func trackButton(_ track: Track, key: WritableKeyPath<Track, Bool>, icon: String, label: String) -> some View {
        Button { model.change { p in if let index = p.tracks.firstIndex(where: { $0.id == track.id }) { p.tracks[index][keyPath: key].toggle() } } }
        label: { Image(systemName: icon).foregroundStyle(track[keyPath: key] ? Palette.accent : Palette.dim) }
            .buttonStyle(.plain).help(label).accessibilityLabel(label)
    }

    private func ruler(width: Double) -> some View {
        let step = [1,2,5,10,15,30,60,120,300,600,1800,3600].first {Double($0)*display.pointsPerSecond >= 55} ?? 3600
        return ZStack(alignment: .topLeading) {
            Palette.surface
            ForEach(0..<(Int(width/display.pointsPerSecond)/step+1), id: \.self) { tick in
                VStack(alignment: .leading, spacing: 3) {
                    Text(formatTime(Int64(tick*step)*1_000_000)).font(.system(size: 9).monospacedDigit())
                    Rectangle().frame(width: 1, height: 5)
                }.foregroundStyle(Palette.dim).offset(x: Double(tick*step)*display.pointsPerSecond, y: 3)
            }
        }.frame(width: width, height: 28).contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0).onChanged { if desktop {keyboardFocus = true}; model.seek(geometry.time(at: $0.location.x)) })
    }

    private var playhead: some View {
        VStack(spacing: 0) {
            Image(systemName: "arrowtriangle.down.fill").font(.system(size: 10))
            Rectangle().frame(width: 1.5)
        }.foregroundStyle(.white).frame(width: 10).offset(x: x(model.playhead)-5).id("playhead").allowsHitTesting(false)
    }

    private func trackRow(_ track: Track, width: Double) -> some View {
        ZStack(alignment: .leading) {
            hoveredTrack == track.id ? Palette.accent.opacity(0.15) : Palette.surface
            ForEach(track.clips) { clip in clipView(clip, track: track) }
            if hoveredTrack == track.id, let dropTime { dropMarker(dropTime) }
        }
        .frame(width: width, height: rowHeight)
        .contentShape(Rectangle())
        .onTapGesture { point in if desktop {keyboardFocus = true}; model.selected = nil; model.seek(geometry.time(at: point.x)) }
        .onDrop(of: WorkspaceDrop.types, delegate: TimelineMediaDrop(model: model, geometry: geometry, kind: track.kind, trackID: track.id,
            hoverTime: Binding(get: { hoveredTrack == track.id ? dropTime : nil }, set: { dropTime = $0; hoveredTrack = $0 == nil ? nil : track.id })))
        .opacity(track.hidden ? 0.55 : 1)
        .zIndex(track.clips.contains(where: {$0.id == movingID}) ? 2 : 0)
    }

    private func newTrackRow(_ kind: TrackKind, width: Double) -> some View {
        let id = "new-" + kind.rawValue
        return ZStack(alignment: .leading) {
            Palette.surface2.opacity(0.4)
            Text(kind == .audio ? "Drop sound here to add an audio track" : "Drop video or a photo here to add a layer")
                .font(.caption2).foregroundStyle(Palette.dim).padding(.leading, 12)
            if hoveredTrack == id, let dropTime { dropMarker(dropTime) }
        }.frame(width: width, height: 36)
            .onDrop(of: WorkspaceDrop.types, delegate: TimelineMediaDrop(model: model, geometry: geometry, kind: kind, trackID: nil,
                hoverTime: Binding(get: { hoveredTrack == id ? dropTime : nil }, set: { dropTime = $0; hoveredTrack = $0 == nil ? nil : id })))
    }

    private func dropMarker(_ time: Int64) -> some View {
        Rectangle().fill(Palette.teal).frame(width: 2).offset(x: x(time)).allowsHitTesting(false)
    }

    private func clipView(_ clip: Clip, track: Track) -> some View {
        let selected = model.selected == clip.id
        let dragging = movingID == clip.id
        let trimming = trimID == clip.id
        let delta = trimming ? trimDelta : 0
        let clipWidth = max(24, x(clip.durationUs) + (trimStart ? -delta : delta))
        return HStack(spacing: 0) {
            if selected { handle(clip, start: true) }
            VStack(alignment: .leading, spacing: 4) {
                Text(clip.text?.text ?? model.project.asset(clip.assetID)?.name ?? "Clip").font(.caption2).lineLimit(1)
                if desktop && rowHeight >= 64 {
                    Text("\(formatTime(clip.durationUs))\(clip.speed == 1 ? "" : " · \(clip.speed.formatted())×")").font(.system(size: 9)).foregroundStyle(.white.opacity(0.65))
                }
            }.padding(6).frame(maxWidth: .infinity, alignment: .leading)
            if selected { handle(clip, start: false) }
        }
        .frame(width: clipWidth, height: rowHeight-6)
        .background(Palette.track(track.kind))
        .clipShape(RoundedRectangle(cornerRadius: 5))
        .overlay(RoundedRectangle(cornerRadius: 5).stroke(selected ? Color.white : Color.clear, lineWidth: 2))
        .overlay(alignment: .bottomLeading) {
            ForEach(Array(clip.keyframes.enumerated()), id: \.offset) { _, keyframe in
                Image(systemName: "diamond.fill").font(.system(size: 6)).offset(x: x(keyframe.offsetUs), y: -3)
            }
        }
        .offset(x: max(0, x(clip.startUs) + (dragging ? movement.width : 0) + (trimming && trimStart ? delta : 0)),
                y: dragging ? movement.height : 0)
        .zIndex(dragging ? 10 : selected ? 1 : 0)
        .onTapGesture {
            if desktop {keyboardFocus = true}
            model.selected = clip.id
            if !desktop || !clip.contains(model.playhead) { model.seek(clip.startUs) }
        }
        .gesture(DragGesture(minimumDistance: 8).onChanged { value in
            guard !track.locked else { return }
            if desktop {keyboardFocus = true}; movingID = clip.id; movement = value.translation; model.selected = clip.id
        }.onEnded { value in
            defer { movingID = nil; movement = .zero }
            guard !track.locked else { return }
            let time = geometry.snap(max(0, clip.startUs+Int64(value.translation.width/display.pointsPerSecond*1_000_000)),
                                     project: model.project, playhead: model.playhead, excluding: clip.id)
            let tracks = model.project.tracks, index = tracks.firstIndex(where: { $0.id == track.id }) ?? 0
            let destination = clamp(index+Int((value.translation.height/(rowHeight+5)).rounded()), 0, tracks.count-1)
            model.change { $0.move(clip.id, to: tracks[destination].id, at: time) }
        })
        .contextMenu {
            Button("Split") { model.selected = clip.id; model.split() }
            if track.kind == .main { Button("To new layer") { model.selected = clip.id; model.moveSelectionToLayer() } }
            Button("Duplicate") { model.selected = clip.id; model.duplicateSelected() }
            Button("Delete", role: .destructive) { model.selected = clip.id; model.delete() }
        }.disabled(track.locked)
        .accessibilityLabel(clip.text?.text ?? model.project.asset(clip.assetID)?.name ?? "Clip")
    }

    private func handle(_ clip: Clip, start: Bool) -> some View {
        RoundedRectangle(cornerRadius: 2).fill(.white).frame(width: desktop ? 7 : 8).padding(.vertical, 8)
            .contentShape(Rectangle()).help(start ? "Trim start" : "Trim end")
            .highPriorityGesture(DragGesture().onChanged { value in
                trimID = clip.id; trimStart = start
                trimDelta = clamp(value.translation.width, start ? -x(clip.startUs) : -x(clip.durationUs)+x(minimumClip),
                                  start ? x(clip.durationUs)-x(minimumClip) : 10_000)
            }.onEnded { _ in
                let delta = Int64(trimDelta/display.pointsPerSecond*1_000_000)
                model.change { if start { $0.trimStart(clip.id, delta: delta) } else { $0.trimEnd(clip.id, delta: delta) } }
                trimID = nil; trimDelta = 0
            })
    }
}
