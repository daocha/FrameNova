import SwiftUI
import AVFoundation
import UniformTypeIdentifiers

struct PlayerSurface: UIViewRepresentable {
    let player: AVPlayer
    final class Surface: UIView { override class var layerClass: AnyClass { AVPlayerLayer.self }; var videoLayer:AVPlayerLayer {layer as! AVPlayerLayer} }
    func makeUIView(context:Context) -> Surface { let v = Surface(); v.videoLayer.videoGravity = .resizeAspect; v.videoLayer.player = player; return v }
    func updateUIView(_ view:Surface,context:Context) { view.videoLayer.player = player }
}
struct EditorView: View {
    @StateObject private var model: EditorModel
    @Environment(\.dismiss) var dismiss
    @ViewState<String> private var panel = "Ratio"
    @ViewState<Bool> private var showInspector = false
    @ViewState<Bool> private var export = false
    @ViewState<Bool> private var picker = false
    @ViewState<Bool> private var files = false
    @ViewState<Bool> private var subtitleFiles = false
    @ViewState<Bool> private var replace = false
    @ViewState<TrackKind> private var importKind:TrackKind = .main
    @ViewState<String> private var name = ""
    @ViewState<Bool> private var rename = false
    @ViewState<CGFloat> private var inspectorWidth:CGFloat = 320
    @ViewState<CGFloat> private var timelineHeight:CGFloat = 260
    @ViewState<Transform?> private var previewDrag:Transform?
    @ViewState<Transform?> private var gestureTransform:Transform?
    init(project:Project,store:ProjectStore) { _model = StateObject(wrappedValue:EditorModel(project:project,store:store)) }
    var body: some View {
        GeometryReader { geo in
            let wide = geo.size.width >= 900
            VStack(spacing:0) {
                topBar
                if wide {
                    HStack(spacing:0) {
                        VStack(spacing:0) {
                            preview.frame(maxHeight:.infinity)
                            transport
                            Divider().overlay(Palette.dim).frame(height:6).contentShape(Rectangle()).gesture(DragGesture().onChanged { timelineHeight = clamp(timelineHeight-$0.translation.height/8,160,geo.size.height*0.6) })
                            TimelineView(model:model).frame(height:timelineHeight)
                            tools
                        }
                        if showInspector {
                            Rectangle().fill(Palette.surface2).frame(width:6).contentShape(Rectangle()).gesture(DragGesture().onChanged { inspectorWidth = clamp(inspectorWidth-$0.translation.width/8,280,460) })
                            InspectorView(model:model,panel:panel).frame(width:inspectorWidth)
                        }
                    }
                } else {
                    preview.frame(maxHeight:.infinity)
                    transport
                    TimelineView(model:model).frame(height:geo.size.height < 540 ? 115:190)
                    tools
                }
            }.background(Palette.bg)
                .sheet(isPresented:Binding(get:{showInspector && !wide},set:{showInspector = $0})) {
                    NavigationStack { InspectorView(model:model,panel:panel).navigationTitle(panel).toolbar { Button("Done") {showInspector = false} } }.presentationDetents([.medium,.large])
                }
        }
        .navigationBarBackButtonHidden().toolbar(.hidden,for:.navigationBar)
        .sheet(isPresented:$picker) { MediaPicker { assets,error in picker = false; model.imported(assets,kind:importKind,replace:replace); if let error {model.error = error} } }
        .fileImporter(isPresented:$files,allowedContentTypes:subtitleFiles ? [.plainText,.data] : importKind == .audio ? [.audio,.movie]:[.movie,.image],allowsMultipleSelection:!replace) { result in
            do { model.ingest(try result.get(),kind:importKind,replace:replace,subtitles:subtitleFiles) } catch {model.error = error.localizedDescription}
        }
        .sheet(isPresented:$export) { ExportView(project:model.project,exporter:model.exporter) }
        .sheet(isPresented:Binding(get:{model.shareURL != nil},set:{if !$0 {model.shareURL = nil}})) {if let url = model.shareURL {ShareSheet(url:url)}}
        .alert("Rename project",isPresented:$rename) { TextField("Name",text:$name); Button("Save") {model.change {$0.name = name}}; Button("Cancel",role:.cancel) {} }
        .alert("FrameNova",isPresented:Binding(get:{model.error != nil},set:{if !$0 {model.error = nil}})) {Button("OK") {model.error = nil}} message: {Text(model.error ?? "")}
        .overlay { if model.busy { ProgressView("Importing…").padding(24).background(Palette.surface,in:RoundedRectangle(cornerRadius:16)) } }
        .background { keyboardCommands }
        .onDisappear {model.close()}
    }
    private var topBar: some View {
        HStack(spacing:12) {
            Button {dismiss()} label:{Image(systemName:"chevron.left").padding(8)}.accessibilityLabel("Close editor")
            Button {name = model.project.name; rename = true} label: {
                VStack(alignment:.leading,spacing:3) {Text(model.project.name).font(.headline).lineLimit(1).foregroundStyle(.white); Text("\(model.project.canvas.aspect.rawValue) · \(model.project.canvas.tier.label) · \(model.project.canvas.fps) fps").font(.caption2)}
            }.buttonStyle(.plain)
            Spacer()
            Button {model.undo()} label:{Image(systemName:"arrow.uturn.backward")}.disabled(!model.canUndo).accessibilityLabel("Undo")
            Button {model.redo()} label:{Image(systemName:"arrow.uturn.forward")}.disabled(!model.canRedo).accessibilityLabel("Redo")
            Button {showInspector.toggle()} label:{Image(systemName:"sidebar.right")}.accessibilityLabel("Inspector")
            Button("Export") {export = true}.buttonStyle(.borderedProminent).disabled(model.project.durationUs == 0)
        }.padding(.horizontal,12).padding(.vertical,8).background(Palette.surface)
    }
    private var preview: some View {
        GeometryReader { g in
            ZStack {
                Color.black
                PlayerSurface(player:model.player)
                if model.project.durationUs == 0 { Text("Add videos and photos to start").foregroundStyle(Palette.dim) }
                if let c = model.clip, model.project.track(c.id)?.kind != .audio {
                    Rectangle().stroke(Palette.accent,lineWidth:1).padding(12).allowsHitTesting(false)
                }
            }.aspectRatio(model.project.canvas.aspect.ratio,contentMode:.fit).frame(maxWidth:.infinity,maxHeight:.infinity)
                .contentShape(Rectangle())
                .gesture(DragGesture().onChanged { value in
                    guard let c = model.clip else {return}; if previewDrag == nil {previewDrag = c.transform(at:model.playhead); model.beginGesture()}
                    guard var t = previewDrag else {return}; t.cx += value.translation.width/max(1,g.size.width); t.cy += value.translation.height/max(1,g.size.height)
                    if abs(t.cx-0.5)<0.015 {t.cx = 0.5}; if abs(t.cy-0.5)<0.015 {t.cy = 0.5}
                    let time = model.playhead, fps = model.project.canvas.fps
                    model.edit {$0.setTransform(t,at:time,fps:fps)}
                }.onEnded {_ in previewDrag = nil; model.endGesture()})
                .simultaneousGesture(MagnificationGesture().onChanged {factor in
                    guard let c = model.clip else {return}; if gestureTransform == nil {gestureTransform = c.transform(at:model.playhead); model.beginGesture()}
                    guard var t = gestureTransform else {return}; t.scale = clamp(t.scale*factor,0.05,8)
                    let time = model.playhead,fps = model.project.canvas.fps; model.edit {$0.setTransform(t,at:time,fps:fps)}
                }.onEnded {_ in gestureTransform = nil; model.endGesture()})
                .simultaneousGesture(RotationGesture().onChanged {angle in
                    guard let c = model.clip else {return}; if gestureTransform == nil {gestureTransform = c.transform(at:model.playhead); model.beginGesture()}
                    guard var t = gestureTransform else {return}; t.rotation += angle.degrees; let snapped = (t.rotation/90).rounded()*90; if abs(t.rotation-snapped)<3 {t.rotation = snapped}
                    let time = model.playhead,fps = model.project.canvas.fps; model.edit {$0.setTransform(t,at:time,fps:fps)}
                }.onEnded {_ in gestureTransform = nil; model.endGesture()})
        }.padding(12)
    }
    private var transport: some View {
        HStack(spacing:18) {
            Text("\(formatTime(model.playhead)) / \(formatTime(model.project.durationUs))").font(.caption.monospacedDigit()).foregroundStyle(Palette.dim)
            Spacer()
            Button {model.seek(0)} label:{Image(systemName:"backward.end.fill")}.accessibilityLabel("Start")
            Button {model.play()} label:{Image(systemName:model.playing ? "pause.fill":"play.fill").font(.title3)}.accessibilityLabel(model.playing ? "Pause":"Play")
            Button {model.seek(model.project.durationUs)} label:{Image(systemName:"forward.end.fill")}.accessibilityLabel("End")
            Spacer()
            Button {model.selected = nil; showInspector = false} label:{Image(systemName:"xmark")}.accessibilityLabel("Deselect")
        }.padding(.horizontal,16).padding(.vertical,10)
    }
    private func tool(_ title:String,_ icon:String,action:@escaping ()->Void) -> some View {
        Button(action:action) {VStack(spacing:6) {Image(systemName:icon).font(.system(size:20)); Text(title).font(.system(size:10)).lineLimit(1)}.frame(minWidth:56,minHeight:54)}.buttonStyle(.plain).help(title)
    }
    private func open(_ title:String) {panel = title; showInspector = true}
    private func pick(_ kind:TrackKind,replace:Bool = false) {importKind = kind; self.replace = replace; subtitleFiles = false; if kind == .audio {files = true} else {picker = true}}
    private var tools: some View {
        ScrollView(.horizontal,showsIndicators:false) {
            HStack(spacing:8) {
                if let c = model.clip {
                    if c.text != nil {
                        tool("Edit","pencil") {open("Text")}; tool("Font","textformat") {open("Text")}; tool("Style","paintbrush") {open("Text")}; tool("Animation","sparkles") {open("Text")}
                    }
                    tool("Split","scissors") {model.split()}
                    if model.project.asset(c.assetID)?.type != .image && c.text == nil {tool("Speed","speedometer") {open("Speed")}; tool("Volume","speaker.wave.2") {open("Volume")}}
                    tool("Position","arrow.up.and.down.and.arrow.left.and.right") {open("Position")}
                    tool("Keyframe","diamond") {model.change {$0.toggleKeyframe(c.id,at:model.playhead)}}
                    if c.text == nil && model.project.track(c.id)?.kind != .audio {
                        tool("Layout","square.grid.2x2") {open("Layout")}; tool("Adjust","slider.horizontal.3") {open("Adjust")}; tool("Filters","camera.filters") {open("Filters")}; tool("Crop","crop") {open("Crop")}
                        if model.project.track(c.id)?.kind == .main {
                            tool("Transition","square.on.square") {open("Transition")}
                            tool("To new layer","square.3.layers.3d") {model.change {p in p.delete(c.id); var moved = c; moved.transitionIn = nil; moved.transform.scale *= 0.6; p.place(moved,kind:.overlay)}}
                        } else if model.project.track(c.id)?.kind == .overlay {tool("To main","arrow.down.to.line") {model.change {$0.move(c.id,to:$0.tracks[$0.mainIndex].id,at:c.startUs)}}}
                        tool("Freeze","snowflake") {model.freeze()}
                        if model.project.asset(c.assetID)?.hasAudio == true {tool("Extract audio","music.note") {model.extractAudio()}; tool("Save audio","square.and.arrow.up") {model.saveAudio()}}
                        tool("Replace","arrow.left.arrow.right") {pick(.main,replace:true)}
                    }
                    tool("Duplicate","doc.on.doc") {model.change {model.selected = $0.duplicate(c.id)}}
                    tool("Delete","trash") {model.delete()}
                } else {
                    tool("Media","photo.badge.plus") {pick(.main)}; tool("Files","folder") {importKind = .main; replace = false; subtitleFiles = false; files = true}
                    tool("Add layer","square.3.layers.3d") {pick(.overlay)}
                    tool("Text","textformat") {model.addText("Title"); open("Text")}; tool("Subtitle","captions.bubble") {model.addText("Subtitle"); open("Text")}
                    tool("Import SRT/LRC","text.badge.plus") {subtitleFiles = true; files = true}
                    tool("Stickers","face.smiling") {open("Stickers")}; tool("Audio","music.note") {pick(.audio)}
                    tool("Voiceover","mic") {open("Voiceover")}; tool("Layout","square.grid.2x2") {open("Layout")}; tool("Ratio","aspectratio") {open("Ratio")}
                    tool("Split","scissors") {model.split()}; tool("Freeze","snowflake") {model.freeze()}
                    tool("Delete gap","trash") {model.change {$0.deleteGap(at:model.playhead)}}
                }
            }.padding(10)
        }.background(Palette.surface)
    }
    private var keyboardCommands: some View {
        Group {
            Button("Undo") {model.undo()}.keyboardShortcut("z",modifiers:.command)
            Button("Redo") {model.redo()}.keyboardShortcut("z",modifiers:[.command,.shift])
            Button("Play") {model.play()}.keyboardShortcut(.space,modifiers:[])
            Button("Split") {model.split()}.keyboardShortcut("b",modifiers:.command)
            Button("Delete") {model.delete()}.keyboardShortcut(.delete,modifiers:[])
            Button("Export") {export = true}.keyboardShortcut("e",modifiers:.command)
        }.hidden()
    }
}
struct TimelineView: View {
    @ObservedObject var model:EditorModel
    @ViewState<Double> private var scale = 70.0
    @ViewState<Double> private var initialScale = 70.0
    @ViewState<Clip?> private var moving:Clip?
    private var width:Double {max(600,Double(model.project.durationUs)/1_000_000*scale+180)}
    private func x(_ time:Int64) -> Double {Double(time)/1_000_000*scale}
    private func snapped(_ time:Int64) -> Int64 {
        var edges:[Int64] = [model.playhead,0]
        for track in model.project.tracks {for clip in track.clips {edges.append(clip.startUs); edges.append(clip.endUs)}}
        guard let edge = edges.min(by:{abs($0-time)<abs($1-time)}) else {return time}
        let threshold = Int64(8.0/scale*1_000_000.0)
        return abs(edge-time) < threshold ? edge:time
    }
    var body: some View {
        ScrollView(.vertical) {HStack(alignment:.top,spacing:0) {
            VStack(spacing:4) {
                HStack {Button {scale = max(15,scale/1.3)} label:{Image(systemName:"minus.magnifyingglass")}; Button {scale = min(500,scale*1.3)} label:{Image(systemName:"plus.magnifyingglass")}}.font(.caption).frame(height:28)
                Group {
                    VStack(spacing:5) {ForEach(model.project.tracks) {t in
                        VStack(spacing:6) {
                            Text(t.kind == .overlay ? "Layer":t.kind.rawValue.capitalized).font(.caption2)
                            HStack(spacing:8) {
                                Button {toggle(t.id,\.muted)} label:{Image(systemName:t.muted ? "speaker.slash":"speaker.wave.1")}
                                Button {toggle(t.id,\.hidden)} label:{Image(systemName:t.hidden ? "eye.slash":"eye")}
                                Button {toggle(t.id,\.locked)} label:{Image(systemName:t.locked ? "lock.fill":"lock.open")}
                            }.font(.system(size:10))
                        }.frame(width:86,height:55).background(Palette.surface2)
                    }}
                }
            }.frame(width:90)
            ScrollView(.horizontal) {
                VStack(alignment:.leading,spacing:5) {
                    ZStack(alignment:.topLeading) {
                        ForEach(0..<Int(width/scale)+1,id:\.self) {s in Text(formatTime(Int64(s)*1_000_000)).font(.system(size:9).monospacedDigit()).foregroundStyle(Palette.dim).offset(x:Double(s)*scale,y:4)}
                    }.frame(width:width,height:28).contentShape(Rectangle()).gesture(DragGesture(minimumDistance:0).onChanged {model.seek(Int64($0.location.x/scale*1_000_000))})
                    ForEach(model.project.tracks) {track in
                        ZStack(alignment:.leading) {
                            Palette.surface
                            ForEach(track.clips) {clip in clipView(clip,track:track)}
                        }.frame(width:width,height:55).contentShape(Rectangle()).onTapGesture {point in model.selected = nil; model.seek(Int64(point.x/scale*1_000_000))}
                    }
                }.overlay(alignment:.topLeading) {Rectangle().fill(.white).frame(width:1.5).offset(x:x(model.playhead)).allowsHitTesting(false)}
            }.simultaneousGesture(MagnificationGesture().onChanged {scale = clamp(initialScale*$0,15,500)}.onEnded {_ in initialScale = scale})
        }}.padding(.vertical,5).background(Palette.bg)
    }
    private func toggle(_ id:String,_ key:WritableKeyPath<Track,Bool>) {model.change {p in if let i = p.tracks.firstIndex(where:{$0.id == id}) {p.tracks[i][keyPath:key].toggle()}}}
    private func clipView(_ clip:Clip,track:Track) -> some View {
        let selected = model.selected == clip.id
        return HStack(spacing:0) {
            if selected {handle(clip,start:true)}
            Text(clip.text?.text ?? model.project.asset(clip.assetID)?.name ?? "Clip").font(.caption2).lineLimit(2).padding(6).frame(maxWidth:.infinity,alignment:.leading)
            if selected {handle(clip,start:false)}
        }.frame(width:max(12,x(clip.durationUs)),height:49).background(Palette.track(track.kind)).clipShape(RoundedRectangle(cornerRadius:5))
            .overlay(RoundedRectangle(cornerRadius:5).stroke(selected ? .white:.clear,lineWidth:2))
            .overlay(alignment:.bottomLeading) {HStack(spacing:3) {ForEach(Array(clip.keyframes.enumerated()),id:\.offset) {_,_ in Image(systemName:"diamond.fill").font(.system(size:6))}}.padding(3)}
            .offset(x:x(clip.startUs))
            .onTapGesture {model.selected = clip.id; model.seek(clip.startUs)}
            .gesture(DragGesture(minimumDistance:8).onChanged {_ in if moving == nil {moving = clip; model.selected = clip.id}}.onEnded {value in
                guard !track.locked else {moving = nil; return}
                let time = snapped(max(0,clip.startUs+Int64(value.translation.width/scale*1_000_000)))
                let tracks = model.project.tracks, index = tracks.firstIndex(where:{$0.id == track.id}) ?? 0
                let target = tracks[clamp(index+Int((value.translation.height/60).rounded()),0,tracks.count-1)].id
                model.change {$0.move(clip.id,to:target,at:time)}; moving = nil
            })
            .contextMenu {Button("Split") {model.selected = clip.id; model.split()}; Button("Duplicate") {model.change {_ = $0.duplicate(clip.id)}}; Button("Delete",role:.destructive) {model.selected = clip.id; model.delete()}}
    }
    private func handle(_ clip:Clip,start:Bool) -> some View {
        RoundedRectangle(cornerRadius:2).fill(.white).frame(width:8).padding(.vertical,8).gesture(DragGesture().onEnded {value in
            let delta = Int64(value.translation.width/scale*1_000_000)
            model.change {if start {$0.trimStart(clip.id,delta:delta)} else {$0.trimEnd(clip.id,delta:delta)}}
        })
    }
}
