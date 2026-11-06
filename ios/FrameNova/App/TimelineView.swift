import SwiftUI

@MainActor final class TimelineDisplay: ObservableObject {
    @Published var pointsPerSecond: Double = 70
    @Published var rowHeight: Double = 55
    @Published var snapping = true
    var geometry: TimelineGeometry { TimelineGeometry(pointsPerSecond: pointsPerSecond, snapping: snapping) }
    func zoom(_ factor: Double) { pointsPerSecond = clamp(pointsPerSecond * factor, 8, 1600) }
    func fit(duration: Int64, width: Double) {
        pointsPerSecond = clamp(max(1, width - 168) / max(1, Double(duration) / 1_000_000), 0.1, 600)
    }
}

struct TimelineView: View {
    @ObservedObject var model: EditorModel
    @ObservedObject var display: TimelineDisplay
    @StateObject private var pointer = DesktopPointerState()
    var desktop = false
    var onCover:()->Void = {}
    @EditorFocus<Bool> private var keyboardFocus
    @ViewState<Double?> private var initialScale: Double?
    @ViewState<String?> private var movingID: String?
    @ViewState<String?> private var pressedID:String?
    @ViewState<Bool> private var extendingSelection = false
    @ViewState<CGSize> private var movement = .zero
    @ViewState<String?> private var trimID: String?
    @ViewState<Bool> private var trimStart = false
    @ViewState<Double> private var trimDelta = 0
    @ViewState<Int64?> private var dropTime: Int64?
    @ViewState<String?> private var hoveredTrack: String?
    @ViewState<Double> private var horizontalOffset = 0
    @ViewState<Double> private var viewportWidth = 1000
    @ViewState<CGPoint?> private var rulerHover = nil
    @ViewState<Bool> private var rulerDragging = false

    private var geometry: TimelineGeometry { display.geometry }
    private var headerWidth: Double { desktop ? 136 : 90 }
    private var rowHeight: Double { desktop ? display.rowHeight : 55 }
    private func x(_ time: Int64) -> Double { geometry.position(time) }

    var body: some View {
        GeometryReader { viewport in
            let width = max(Double(viewport.size.width) - headerWidth, max(600, x(model.project.durationUs) + 180))
            ScrollView(.vertical) {
                LazyVStack(spacing:5,pinnedViews:[.sectionHeaders]) {
                  Section {
                   HStack(alignment: .top, spacing: 0) {
                    headers
                    ScrollViewReader { reader in
                        ScrollView(.horizontal) {
                            HStack(alignment:.top,spacing:0) {
                                coverColumn
                                VStack(alignment: .leading, spacing: 5) {
                                    ForEach(model.project.tracks) { track in trackRow(track, width: width) }
                                    if desktop {
                                        newTrackRow(.overlay, width: width)
                                        newTrackRow(.audio, width: width)
                                    }
                                }
                                .overlay(alignment: .topLeading) { playhead }
                                .background(GeometryReader {proxy in Color.clear.preference(key:TimelineOffsetKey.self,value:-proxy.frame(in:.named("timeline.scrollViewport")).minX)})
                            }
                        }
                        .coordinateSpace(name:"timeline.scrollViewport")
                        .onPreferenceChange(TimelineOffsetKey.self) {horizontalOffset = $0}
                        .onChange(of: model.playhead) { _, time in
                            let position = geometry.viewportPosition(time,scrollOffset:horizontalOffset)
                            if !rulerDragging && (position<0 || position>viewportWidth-12) {
                                reader.scrollTo("playhead",anchor:.center)
                            }
                        }
                        .onChange(of:display.pointsPerSecond) {_,_ in reader.scrollTo("playhead",anchor:.center)}
                        .simultaneousGesture(MagnificationGesture().onChanged { factor in
                            if initialScale == nil { initialScale = display.pointsPerSecond }
                            display.pointsPerSecond = clamp((initialScale ?? 70) * factor, 8, 1600)
                        }.onEnded { _ in initialScale = nil })
                    }
                   }
                  } header: {
                    HStack(spacing:0) {
                        Text("Tracks").font(.callout.bold()).frame(width:headerWidth,height:desktop ? 64 : 28).background(Palette.surface)
                        ruler(width:max(0,viewport.size.width-headerWidth)).clipped()
                    }.background(Palette.surface).zIndex(20)
                  }
                }
            }
            .onAppear {viewportWidth = max(0,viewport.size.width-headerWidth)}
            .onChange(of:viewport.size.width) {_,width in viewportWidth = max(0,width-headerWidth)}
            #if targetEnvironment(macCatalyst)
            .background {TimelineScrollZoom(onZoom:{display.zoom($0)})}
            .background {DesktopPointerModifiers(state:pointer)}
            #endif
        }
        .padding(.vertical, 5)
        .background(Palette.bg)
        .coordinateSpace(name:"editor.timelineDrag")
        .focusable()
        .focused($keyboardFocus)
        .focusEffectDisabled()
        .accessibilityIdentifier(desktop ? "desktop.timeline" : "editor.timeline")
    }

    private var headers: some View {
        VStack(spacing: 5) {
            ForEach(model.project.tracks) { track in
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing:6) {
                        Text(loc(track.kind == .overlay ? "Layer" : track.kind.rawValue.capitalized)).font(.subheadline.bold())
                    }
                    HStack(spacing: desktop ? 16 : 8) {
                        trackButton(track, key: \.muted, icon: track.muted ? "speaker.slash" : "speaker.wave.1", label: loc("Mute track"))
                        trackButton(track, key: \.hidden, icon: track.hidden ? "eye.slash" : "eye", label: loc("Hide track"))
                        trackButton(track, key: \.locked, icon: track.locked ? "lock.fill" : "lock.open", label: track.locked ? loc("Unlock track") : loc("Lock track"))
                    }.font(.system(size: desktop ? 12 : 10))
                }.padding(.horizontal, 8).frame(width: headerWidth, height: rowHeight, alignment: .leading).background(track.locked ? Color.gray.opacity(0.2):Palette.surface2)
            }
            if desktop {
                Text("New layer").font(.subheadline).frame(width: headerWidth, height: 36)
                Text("New audio").font(.subheadline).frame(width: headerWidth, height: 36)
            }
        }.frame(width: headerWidth)
    }

    private func trackButton(_ track: Track, key: WritableKeyPath<Track, Bool>, icon: String, label: String) -> some View {
        Button { model.change { p in if let index = p.tracks.firstIndex(where: { $0.id == track.id }) { p.tracks[index][keyPath: key].toggle() } } }
        label: { Image(systemName: icon).foregroundStyle(track[keyPath: key] ? Palette.accent : Palette.dim) }
            .buttonStyle(.plain).help(label).accessibilityLabel(label)
    }

    private func ruler(width: Double) -> some View {
        let major = [0.1,0.25,0.5,1,2,5,10,15,30,60,120,300,600,1800,3600].first {$0*display.pointsPerSecond >= 90} ?? 3600
        let minor = major/5,spacing = minor*display.pointsPerSecond
        let firstTick = max(0,Int(horizontalOffset/spacing)-1)
        let lastTick = max(firstTick,Int((horizontalOffset+width)/spacing)+1)
        return GeometryReader { proxy in
            ZStack(alignment: .topLeading) {
                Palette.surface
                ForEach(firstTick...lastTick, id: \.self) { tick in
                    let seconds = Double(tick)*minor
                    VStack(alignment: .leading, spacing: 3) {
                        if tick%5 == 0 {
                            Text(major < 1 ? String(format:"%.2fs",seconds):formatTime(Int64(seconds*1_000_000))).font(.system(size: 9).monospacedDigit())
                        }
                        Rectangle().frame(width: 1, height: tick%5 == 0 ? 5:3)
                    }.foregroundStyle(Palette.dim).offset(x: Double(tick)*spacing-horizontalOffset, y: tick%5 == 0 ? 3:20)
                }
            }.contentShape(Rectangle())
                .onContinuousHover(coordinateSpace:.global) {phase in
                    guard !rulerDragging else {return}
                    switch phase {case .active(let point):rulerHover = point;case .ended:rulerHover = nil}
                }
                .gesture(DragGesture(minimumDistance:0,coordinateSpace:.global).onChanged {drag in
                    if desktop {keyboardFocus = true}
                    rulerDragging = true;rulerHover = drag.location
                    model.scrub(geometry.time(atViewportX:drag.location.x-proxy.frame(in:.global).minX,scrollOffset:horizontalOffset))
                }.onEnded {drag in
                    // Land exactly where the pointer was released, even if the last move event was coalesced.
                    model.scrub(geometry.time(atViewportX:drag.location.x-proxy.frame(in:.global).minX,scrollOffset:horizontalOffset))
                    rulerDragging = false;rulerHover = nil;model.finishScrub()
                })
                .preference(key:WorkspacePointerHintKey.self,value:rulerHover.map {
                    WorkspacePointerHint(location:$0,symbol:"arrow.left.and.right")
                })
                .help("Drag left or right to seek")
        }.frame(width:width,height:desktop ? 64:28)
    }

    private var coverWidth: Double {rowHeight*model.project.canvas.aspect.ratio+6}
    /// The video's cover, shown like a clip in the main layer just before time zero; a plus marks that none is set yet.
    private var coverColumn: some View {
        VStack(spacing:5) {
            ForEach(model.project.tracks) {track in
                if track.kind == .main {
                    Button(action:onCover) {
                        ZStack {
                            if let asset = model.project.asset(model.project.coverAssetID),asset.type == .image {FramedCover(asset:asset,framing:model.project.framing)}
                            else {Palette.surface2;Image(systemName:"plus").font(.title3).foregroundStyle(Palette.accent)}
                        }
                        .frame(width:coverWidth-6,height:rowHeight).clipShape(RoundedRectangle(cornerRadius:6))
                        .overlay {RoundedRectangle(cornerRadius:6).stroke(Palette.accent.opacity(0.8),lineWidth:2)}
                        .overlay(alignment:.topLeading) {Text("Cover").font(.system(size:14)).foregroundStyle(.white).shadow(radius:2).padding(4)}
                    }.buttonStyle(.plain).padding(.trailing,6)
                        .accessibilityLabel("Add or edit cover").accessibilityIdentifier("desktop.mainCover")
                        .help("Choose the cover image of the exported video")
                } else {Color.clear.frame(width:coverWidth,height:rowHeight)}
            }
        }.frame(width:coverWidth)
    }

    private var playhead: some View {
        HStack(spacing:0) {
            Color.clear.frame(width:x(model.playhead))
            VStack(spacing: 0) {
                Image(systemName: "arrowtriangle.down.fill").font(.system(size: 10))
                Rectangle().frame(width: 1.5)
            }.foregroundStyle(.white).frame(width:10).id("playhead")
            Spacer(minLength:0)
        }.padding(.leading,-5).allowsHitTesting(false)
    }

    private func trackRow(_ track: Track, width: Double) -> some View {
        ZStack(alignment: .leading) {
            (hoveredTrack == track.id ? Palette.accent.opacity(0.15) : Palette.surface)
                .contentShape(Rectangle())
                .onTapGesture {point in
                    if desktop {keyboardFocus = true}
                    let time = geometry.time(at:point.x)
                    if let clip = track.clips.first(where:{$0.contains(time)}),!track.locked {
                        model.selectClip(clip.id,extending:desktop && pointer.command)
                    } else if !desktop || !pointer.command {model.selected = nil;model.selectedGap = nil}
                }
            ForEach(track.clips.filter {clip in
                clip.id == movingID || clip.id == trimID || (x(clip.endUs) >= horizontalOffset-32 && x(clip.startUs) <= horizontalOffset+viewportWidth+32)
            }) { clip in clipView(clip, track: track) }
            if hoveredTrack == track.id, let dropTime { dropMarker(dropTime) }
        }
        .frame(width: width, height: rowHeight)
        .contentShape(Rectangle())
        .onDrop(of: WorkspaceDrop.types, delegate: TimelineMediaDrop(model: model, geometry: geometry, kind: track.kind, trackID: track.id,
            hoverTime: Binding(get: { hoveredTrack == track.id ? dropTime : nil }, set: { dropTime = $0; hoveredTrack = $0 == nil ? nil : track.id })))
        .opacity(track.hidden ? 0.55 : 1)
        .zIndex(track.clips.contains(where: {$0.id == movingID}) ? 2 : 0)
    }

    private func newTrackRow(_ kind: TrackKind, width: Double) -> some View {
        let id = "new-" + kind.rawValue
        return ZStack(alignment: .leading) {
            Palette.surface2.opacity(0.4)
            Text(kind == .audio ? loc("Drop sound here to add an audio track") : loc("Drop video or a photo here to add a layer"))
                .font(.subheadline).foregroundStyle(Palette.dim).padding(.leading, 12)
            if hoveredTrack == id, let dropTime { dropMarker(dropTime) }
        }.frame(width: width, height: 36)
            .onDrop(of: WorkspaceDrop.types, delegate: TimelineMediaDrop(model: model, geometry: geometry, kind: kind, trackID: nil,
                hoverTime: Binding(get: { hoveredTrack == id ? dropTime : nil }, set: { dropTime = $0; hoveredTrack = $0 == nil ? nil : id })))
    }

    private func dropMarker(_ time: Int64) -> some View {
        Rectangle().fill(Palette.teal).frame(width: 2).offset(x: x(time)).allowsHitTesting(false)
    }

    private func clipView(_ clip: Clip, track: Track) -> some View {
        let selected = model.selectedIDs.contains(clip.id)
        let dragging = movingID == clip.id
        let shown = displayedClip(clip)
        let clipWidth = max(24,x(shown.durationUs))
        // The drawn slice ignores the drag offset, so dragging only moves the finished clip instead of redrawing its media.
        let clipLeft = max(0,x(shown.startUs))
        let slice = TimelineClipSlice(clipStart:clipLeft,clipWidth:clipWidth,scrollOffset:horizontalOffset,viewportWidth:viewportWidth)
        return HStack(spacing: 0) {
            if selected && model.selectedIDs.count == 1 && !track.locked && slice.showsStart { handle(clip, start: true) }
            VStack(alignment: .leading, spacing: 4) {
                Text(clip.text?.text ?? model.project.asset(clip.assetID)?.name ?? loc("Clip")).font(.subheadline).lineLimit(1)
                if desktop && rowHeight >= 64 {
                    Text("\(formatTime(clip.durationUs))\(clip.speed == 1 ? "" : " · \(clip.speed.formatted())×")").font(.system(size:13)).foregroundStyle(.white.opacity(0.65))
                }
            }.padding(6).frame(maxWidth: .infinity, alignment: .leading)
            if selected && model.selectedIDs.count == 1 && !track.locked && slice.showsEnd { handle(clip, start: false) }
        }
        .frame(width: slice.width, height: rowHeight-6)
        .contentShape(Rectangle())
        .background {
            ZStack {
                if track.locked {Color(argb:0xFF505058)} else {Palette.track(track.kind)}
                if let asset = model.project.asset(clip.assetID) {
                    TimelineMediaStrip(clip:shown,asset:asset,pointsPerSecond:display.pointsPerSecond,
                        clipOffset:slice.clipOffset,locked:track.locked).equatable()
                    Color.black.opacity(clip.audioOnly || asset.type == .audio ? 0:0.3)
                }
            }.allowsHitTesting(false)
        }
        .clipShape(RoundedRectangle(cornerRadius: 5))
        .overlay(RoundedRectangle(cornerRadius: 5).stroke(selected ? Color.white : Color.clear, lineWidth: 2))
        .overlay(alignment: .bottomLeading) {
            ForEach(Array(clip.keyframes.enumerated()), id: \.offset) { _, keyframe in
                Image(systemName: "diamond.fill").font(.system(size: 6)).offset(x: x(keyframe.offsetUs)-slice.clipOffset, y: -3)
            }
        }
        .overlay {
            if track.locked {RoundedRectangle(cornerRadius:5).fill(Color.gray.opacity(0.35)).allowsHitTesting(false)}
        }
        .offset(x: slice.origin+(dragging ? movement.width:0),
                y: dragging ? movement.height : 0)
        .zIndex(dragging ? 10 : selected ? 1 : 0)
        .gesture(DragGesture(minimumDistance:0,coordinateSpace:.named("editor.timelineDrag")).onChanged {value in
            guard !track.locked else {return}
            if pressedID != clip.id {
                if desktop {keyboardFocus = true}
                pressedID = clip.id;extendingSelection = desktop && pointer.command
                model.selectClip(clip.id,extending:extendingSelection)
            }
            // Published properties notify on every write, so touch them only when they change.
            if model.selectedGap != nil {model.selectedGap = nil}
            if model.playing {model.scrub(model.playhead)}
            guard !extendingSelection,model.selectedIDs.count == 1,hypot(value.translation.width,value.translation.height)>=4 else {return}
            if movingID != clip.id {movingID = clip.id}
            movement = value.translation
        }.onEnded {value in
            defer {movingID = nil;movement = .zero;pressedID = nil}
            if !extendingSelection && hypot(value.translation.width,value.translation.height)<4 {model.selected = clip.id}
            guard !track.locked,movingID == clip.id else {return}
            let time = geometry.snappedStart(clip.startUs+Int64(value.translation.width/display.pointsPerSecond*1_000_000),duration:clip.durationUs,project:model.project,playhead:model.playhead,excluding:clip.id)
            let tracks = model.project.tracks,index = tracks.firstIndex(where:{$0.id == track.id}) ?? 0
            let destination = model.project.dragDestination(from:index,rows:Int((value.translation.height/(rowHeight+5)).rounded()))
            if destination.newLayer {
                let kind = model.project.newLayerKind(for:clip)
                model.change {$0.moveToNewTrack(clip.id,kind:kind,at:time)}
            } else if let target = destination.trackIndex {
                model.change {$0.move(clip.id,to:tracks[target].id,at:time)}
            }
        })
        .contextMenu {
            Button("Split") { model.selected = clip.id; model.split() }.disabled(track.locked)
            Button("To new layer") { model.selectClip(clip.id); model.moveSelectionToLayer() }.disabled(track.locked)
            Button("Duplicate") { model.selectClip(clip.id); model.duplicateSelected() }.disabled(track.locked)
            Button("Delete", role: .destructive) { model.selectClip(clip.id); model.delete() }.disabled(track.locked)
        }
        .accessibilityLabel(clip.text?.text ?? model.project.asset(clip.assetID)?.name ?? loc("Clip"))
        .allowsHitTesting(!track.locked)
    }

    private func displayedClip(_ clip:Clip)->Clip {
        guard trimID == clip.id else {return clip}
        var preview = model.project
        let amount = Int64(trimDelta/display.pointsPerSecond*1_000_000)
        if trimStart {preview.trimStart(clip.id,delta:amount)} else {preview.trimEnd(clip.id,delta:amount)}
        return preview.clip(clip.id) ?? clip
    }

    private func handle(_ clip: Clip, start: Bool) -> some View {
        RoundedRectangle(cornerRadius: 2).fill(.white).frame(width: desktop ? 7 : 8).padding(.vertical, 8)
            .contentShape(Rectangle()).help(start ? loc("Trim start") : loc("Trim end"))
            .highPriorityGesture(DragGesture(coordinateSpace:.named("editor.timelineDrag")).onChanged { value in
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

private struct TimelineOffsetKey:PreferenceKey {static let defaultValue:Double = 0;static func reduce(value:inout Double,nextValue:()->Double) {value = nextValue()}}
