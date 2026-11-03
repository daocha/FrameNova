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
    @StateObject private var timelineDisplay = TimelineDisplay()
    @Environment(\.dismiss) var dismiss
    @ViewState<String> private var panel = "Ratio"
    @ViewState<Bool> private var showInspector = false
    @ViewState<Bool> private var fullscreen = false
    @ViewState<Bool> private var export = false
    @ViewState<Bool> private var picker = false
    @ViewState<Bool> private var files = false
    @ViewState<Bool> private var subtitleFiles = false
    @ViewState<Bool> private var replace = false
    @ViewState<Bool> private var libraryOnly = false
    @ViewState<TrackKind> private var importKind:TrackKind = .main
    @ViewState<String> private var name = ""
    @ViewState<Bool> private var rename = false
    init(project:Project,store:ProjectStore) { _model = StateObject(wrappedValue:EditorModel(project:project,store:store)) }
    var body: some View {
        GeometryReader { geo in
            #if targetEnvironment(macCatalyst)
            DesktopWorkspace(model:model, timeline:timelineDisplay, panel:$panel,
                             onImport:importLibrary, onReplace:replaceMedia, onSubtitles:importSubtitles, onExport:{export = true}, onClose:{dismiss()},
                             onRename:{name = model.project.name; rename = true},
                             preview:{preview}, transport:{transport})
            #else
            let landscape = geo.size.width>geo.size.height
            let textFocus = showInspector && ["Text","Font","Style","Animation","Stickers"].contains(panel)
            VStack(spacing:0) {
                topBar
                if fullscreen {
                    preview.frame(maxHeight:.infinity);transport
                } else if textFocus && landscape {
                    HStack(spacing:0) {preview.frame(maxWidth:.infinity,maxHeight:.infinity);inlinePanel.frame(width:min(380,geo.size.width*0.5))}
                } else if textFocus {
                    preview.frame(maxHeight:.infinity)
                    inlinePanel.frame(height:min(geo.size.height*0.42,380))
                } else if landscape {
                    HStack(spacing:0) {
                        preview.frame(maxWidth:.infinity,maxHeight:.infinity)
                        Group {if showInspector {inlinePanel} else {toolGrid}}.frame(width:min(380,geo.size.width*0.5))
                    }.frame(maxHeight:.infinity)
                    transport
                    touchTimeline.frame(height:max(90,(geo.size.height-102)*0.44))
                } else {
                    preview.frame(maxHeight:.infinity)
                    transport
                    touchTimeline.frame(height:clamp(geo.size.height*0.3,180,320))
                    if showInspector {inlinePanel.frame(height:min(geo.size.height*0.34,320))} else {tools}
                }
            }.background(Palette.bg)
            #endif
        }
        .navigationBarBackButtonHidden().toolbar(.hidden,for:.navigationBar)
        .sheet(isPresented:$picker) { MediaPicker(multiple:!replace) { assets,error in picker = false; model.imported(assets,kind:importKind,replace:replace,libraryOnly:libraryOnly); if let error {model.error = error} } }
        .fileImporter(isPresented:$files,allowedContentTypes:subtitleFiles ? [.plainText,.data] : libraryOnly ? [.movie,.image,.audio] : importKind == .audio ? [.audio,.movie]:[.movie,.image],allowsMultipleSelection:!replace) { result in
            do { model.ingest(try result.get(),kind:importKind,replace:replace,subtitles:subtitleFiles,libraryOnly:libraryOnly) } catch {model.error = error.localizedDescription}
        }
        .sheet(isPresented:$export) { ExportView(project:model.project,exporter:model.exporter) }
        .sheet(isPresented:Binding(get:{model.shareURL != nil},set:{if !$0 {model.shareURL = nil}})) {if let url = model.shareURL {ShareSheet(url:url)}}
        .alert("Rename project",isPresented:$rename) { TextField("Name",text:$name); Button("Save") {model.change {$0.name = name}}; Button("Cancel",role:.cancel) {} }
        .alert("FrameNova",isPresented:Binding(get:{model.error != nil},set:{if !$0 {model.error = nil}})) {Button("OK") {model.error = nil}} message: {Text(model.error ?? "")}
        .overlay { if model.busy { ProgressView("Importing…").padding(24).background(Palette.surface,in:RoundedRectangle(cornerRadius:16)) } }
        #if !targetEnvironment(macCatalyst)
        .background { keyboardCommands }
        #endif
        .onChange(of:model.selected) {_,id in
            if id == nil && !["Ratio","Layout","Stickers","Voiceover"].contains(panel) {showInspector = false}
        }
        .onDisappear {model.close()}
    }
    private var touchTimeline:some View {
        TouchTimeline(model:model,display:timelineDisplay,onTransition:{_ in open("Transition")},onText:{_ in open("Text")},onTrack:{track in
            let key:WritableKeyPath<Track,Bool> = track.kind == .overlay ? \.hidden:\.muted
            updateTrack(track,key)
        })
    }
    private var inlinePanel:some View {InspectorView(model:model,panel:panel,onDone:{showInspector = false})}
    private func updateTrack(_ track:Track,_ key:WritableKeyPath<Track,Bool>) {
        model.change {p in if let index = p.tracks.firstIndex(where:{$0.id == track.id}) {p.tracks[index][keyPath:key].toggle()}}
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
    private var preview: some View {PreviewPane(model:model)}
    private var transport: some View {
        HStack(spacing:18) {
            Text("\(formatTime(model.playhead)) / \(formatTime(model.project.durationUs))").font(.caption.monospacedDigit()).foregroundStyle(Palette.dim)
            Spacer()
            Button {model.seek(0)} label:{Image(systemName:"backward.end.fill")}.accessibilityLabel("Start")
            Button {model.play()} label:{Image(systemName:model.playing ? "pause.fill":"play.fill").font(.title3)}.accessibilityLabel(model.playing ? "Pause":"Play")
            Button {model.seek(model.project.durationUs)} label:{Image(systemName:"forward.end.fill")}.accessibilityLabel("End")
            Spacer()
            Button {fullscreen.toggle()} label:{Image(systemName:fullscreen ? "arrow.down.right.and.arrow.up.left":"arrow.up.left.and.arrow.down.right")}.accessibilityLabel(fullscreen ? "Exit fullscreen":"Fullscreen")
            Button {model.selected = nil;model.selectedGap = nil; showInspector = false} label:{Image(systemName:"xmark")}.accessibilityLabel("Deselect")
        }.padding(.horizontal,16).padding(.vertical,10)
    }
    private func tool(_ title:String,_ icon:String,action:@escaping ()->Void) -> some View {
        Button(action:action) {VStack(spacing:6) {Image(systemName:icon).font(.system(size:20)); Text(title).font(.system(size:10)).lineLimit(1)}.frame(minWidth:56,minHeight:54)}.buttonStyle(.plain).help(title).accessibilityLabel(title)
    }
    private func open(_ title:String) {panel = title; showInspector = true}
    private func replaceMedia() {
        libraryOnly = false; subtitleFiles = false; replace = true
        importKind = model.selected.flatMap {model.project.track($0)?.kind} == .audio ? .audio:.main
        files = true
    }
    private func importSubtitles() {libraryOnly = false; replace = false; subtitleFiles = true; files = true}
    private func importLibrary() {libraryOnly = true; subtitleFiles = false; replace = false; files = true}
    private func pick(_ kind:TrackKind,replace:Bool = false) {libraryOnly = false; importKind = kind; self.replace = replace; subtitleFiles = false; if kind == .audio {files = true} else {picker = true}}
    private var tools:some View {
        ScrollView(.horizontal,showsIndicators:false) {HStack(spacing:8) {toolButtons}.padding(10)}
            .background(Palette.surface).accessibilityIdentifier("editor.tools")
    }
    private var toolGrid:some View {
        ScrollView {LazyVGrid(columns:[GridItem(.adaptive(minimum:72))],spacing:12) {toolButtons}.padding(10)}
            .background(Palette.surface).accessibilityIdentifier("editor.tools")
    }
    @ViewBuilder private var toolButtons:some View {
                if let c = model.clip {
                    let audio = c.audioOnly || model.project.asset(c.assetID)?.type == .audio
                    let video = model.project.asset(c.assetID)?.type == .video
                    let track = model.project.track(c.id)
                    if c.text != nil {
                        tool("Edit","pencil") {open("Text")};tool("Font","textformat") {open("Font")}
                        tool("Style","paintbrush") {open("Style")};tool("Animation","sparkles") {open("Animation")}
                        tool("Position","arrow.up.and.down.and.arrow.left.and.right") {open("Position")}
                        tool("Keyframe","diamond") {model.change {$0.toggleKeyframe(c.id,at:model.playhead)}}
                        tool("Split","scissors") {model.split()}
                        tool("Duplicate","doc.on.doc") {model.duplicateSelected()};tool("Delete","trash") {model.delete()}
                    } else if audio {
                        tool("Volume","speaker.wave.2") {open("Volume")};tool("Speed","speedometer") {open("Speed")}
                        tool("Split","scissors") {model.split()};tool("Duplicate","doc.on.doc") {model.duplicateSelected()}
                        tool("Save audio","square.and.arrow.up") {model.saveAudio()};tool("Delete","trash") {model.delete()}
                    } else {
                        tool("Split","scissors") {model.split()}
                        if track?.kind == .main {tool("To new layer","square.3.layers.3d") {model.moveSelectionToLayer()}}
                        if video {tool("Speed","speedometer") {open("Speed")};tool("Volume","speaker.wave.2") {open("Volume")}}
                        tool("Position","arrow.up.and.down.and.arrow.left.and.right") {open("Position")};tool("Layout","square.grid.2x2") {open("Layout")}
                        tool("Keyframe","diamond") {model.change {$0.toggleKeyframe(c.id,at:model.playhead)}}
                        tool("Adjust","slider.horizontal.3") {open("Adjust")};tool("Filters","camera.filters") {open("Filters")};tool("Crop","crop") {open("Crop")}
                        if track?.kind == .overlay {tool("To main","arrow.down.to.line") {model.change {$0.move(c.id,to:"main",at:c.startUs)}}}
                        if video {tool("Freeze","snowflake") {model.freeze()}}
                        if video && model.project.asset(c.assetID)?.hasAudio == true {tool("Extract audio","music.note") {model.extractAudio()};tool("Save audio","square.and.arrow.up") {model.saveAudio()}}
                        tool("Replace","arrow.left.arrow.right") {pick(.main,replace:true)}
                        tool("Duplicate","doc.on.doc") {model.duplicateSelected()};tool("Delete","trash") {model.delete()}
                    }
                } else if let gap = model.selectedGap {
                    tool("Delete gap","trash") {model.change {$0.deleteGap(at:gap)};model.selectedGap = nil}
                    tool("Media","photo.badge.plus") {pick(.main)}
                } else {
                    tool("Media","photo.badge.plus") {pick(.main)}
                    tool("Add layer","square.3.layers.3d") {pick(.overlay)}
                    tool("Text","textformat") {model.addText("Title"); open("Text")}; tool("Subtitle","captions.bubble") {model.addText("Subtitle"); open("Text")}
                    tool("Import SRT/LRC","text.badge.plus") {importSubtitles()}
                    tool("Stickers","face.smiling") {open("Stickers")}; tool("Audio","music.note") {pick(.audio)}
                    tool("Voiceover","mic") {open("Voiceover")}; tool("Layout","square.grid.2x2") {open("Layout")}; tool("Ratio","aspectratio") {open("Ratio")}
                    tool("Split","scissors") {model.split()}; tool("Freeze","snowflake") {model.freeze()}
                    tool("Delete gap","trash") {model.change {$0.deleteGap(at:model.playhead)}}
                }
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
