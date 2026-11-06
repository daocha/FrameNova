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
    @ViewState<Int> private var inspectorRequest = 0
    @ViewState<Bool> private var fullscreen = false
    @ViewState<CGFloat> private var coverDrag = 0
    @ViewState<Bool> private var export = false
    @ViewState<Bool> private var picker = false
    @ViewState<Bool> private var files = false
    @ViewState<Bool> private var mediaSources = false
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
                             inspectorRequest:inspectorRequest, preview:{preview}, transport:{transport}, tools:{toolButtons})
            #else
            let landscape = geo.size.width>geo.size.height
            // Every panel slides up over the editor, as the cover panel does, so the preview keeps its size.
            let panelOverlay = showInspector
            VStack(spacing:0) {
                topBar
                if fullscreen {
                    preview.frame(maxHeight:.infinity);transport
                } else if landscape {
                    HStack(spacing:0) {
                        preview.frame(maxWidth:.infinity,maxHeight:.infinity)
                        toolGrid.frame(width:min(380,geo.size.width*0.5))
                    }.frame(maxHeight:.infinity)
                    transport
                    touchTimeline.frame(height:max(90,(geo.size.height-96)*0.44))
                } else {
                    preview.frame(maxHeight:.infinity)
                    transport
                    touchTimeline.frame(height:clamp(geo.size.height*0.3,180,320))
                    tools
                }
            }.background(Palette.bg)
            .overlay(alignment:.bottom) {
                if panelOverlay && !fullscreen {
                    InspectorView(model:model,panel:panel,onDone:{showInspector = false},onHeaderDrag:{drag,ended in
                        // Swiping down from the header hides the panel; letting go early lets it spring back.
                        if !ended {coverDrag = max(0,drag.translation.height)}
                        else if drag.translation.height>geo.size.height*0.12 || drag.predictedEndTranslation.height>geo.size.height*0.25 {showInspector = false}
                        else {withAnimation(.easeOut(duration:0.2)) {coverDrag = 0}}
                    }).frame(height:geo.size.height*0.6)
                        .clipShape(UnevenRoundedRectangle(topLeadingRadius:18,topTrailingRadius:18))
                        .shadow(color:.black.opacity(0.4),radius:12)
                        .offset(y:coverDrag)
                        .transition(.move(edge:.bottom).combined(with:.opacity))
                }
            }
            .animation(.easeOut(duration:0.26),value:panelOverlay)
            .onChange(of:panelOverlay) {_,shown in if shown {coverDrag = 0}}
            #endif
        }
        .navigationBarBackButtonHidden().toolbar(.hidden,for:.navigationBar)
        .sheet(isPresented:$picker) { MediaPicker(multiple:!replace) { assets,error in picker = false; model.imported(assets,kind:importKind,replace:replace,libraryOnly:libraryOnly); if let error {model.error = error} } }
        .mediaFileImporter(isPresented:$files,allowedContentTypes:subtitleFiles ? [.plainText,.data] : libraryOnly ? [.movie,.image,.audio] : importKind == .audio ? [.audio,.movie]:[.movie,.image],allowsMultipleSelection:!replace,onCancellation:{model.importStatus = localized("File selection cancelled. No files imported.")}) { result in
            do { model.ingest(try result.get(),kind:importKind,replace:replace,subtitles:subtitleFiles,libraryOnly:libraryOnly) } catch {model.error = error.localizedDescription}
        }
        .confirmationDialog("Choose media source",isPresented:$mediaSources,titleVisibility:.visible) {
            Button("Files…") {files = true}
            Button("Photos…") {picker = true}
            Button("Cancel",role:.cancel) {}
        }
        .sheet(isPresented:$export) { ExportView(project:model.project,exporter:model.exporter) }
        .sheet(isPresented:Binding(get:{model.shareURL != nil},set:{if !$0 {model.shareURL = nil}})) {if let url = model.shareURL {ShareSheet(url:url)}}
        .alert("Rename project",isPresented:$rename) { TextField("Name",text:$name); Button("Save") {model.change {$0.name = name}}; Button("Cancel",role:.cancel) {} }
        .alert("FrameNova",isPresented:Binding(get:{model.error != nil},set:{if !$0 {model.error = nil}})) {Button("OK") {model.error = nil}} message: {Text(model.error ?? "")}
        .overlay {
            if model.busy {
                // Android dims the editor and shows the spinner with its label, without a card.
                VStack(spacing:12) {ProgressView().controlSize(.large); Text("Importing…")}.frame(maxWidth:.infinity,maxHeight:.infinity).background(Color.black.opacity(0.45).ignoresSafeArea())
            }
        }
        .modifier(EditorKeyboard(model:model))
        #if !targetEnvironment(macCatalyst)
        .background {keyboardCommands}
        #endif
        .onChange(of:model.selected) {_,id in
            if id == nil && !["Ratio","Cover","Layout","Stickers","Voiceover"].contains(panel) {showInspector = false}
        }
        .onDisappear {model.close()}
    }
    private var touchTimeline:some View {
        TouchTimeline(model:model,display:timelineDisplay,onCover:{model.selected = nil;model.selectedGap = nil;open("Cover")},onTransition:{_ in open("Transition")},onText:{_ in open("Text")},onTrack:{track in
            let key:WritableKeyPath<Track,Bool> = track.kind == .overlay ? \.hidden:\.muted
            updateTrack(track,key)
        })
    }
    private func updateTrack(_ track:Track,_ key:WritableKeyPath<Track,Bool>) {
        model.change {p in if let index = p.tracks.firstIndex(where:{$0.id == track.id}) {p.tracks[index][keyPath:key].toggle()}}
    }
    /// Same bar as Android: back, name and format, undo, redo, Export; no fill of its own.
    private var topBar: some View {
        HStack(spacing:0) {
            Button {dismiss()} label:{Image(systemName:"arrow.left").font(.system(size:20)).foregroundStyle(Palette.text).frame(width:48,height:48)}.accessibilityLabel("Close editor")
            ProjectHeading(project:model.project,expanded:showInspector && panel == "Ratio",onRename:{name = model.project.name;rename = true},onFormat:{
                let close = showInspector && panel == "Ratio"
                model.selected = nil;model.selectedGap = nil;panel = "Ratio";showInspector = !close
            }).frame(maxWidth:.infinity,alignment:.leading)
            Button {model.undo()} label:{Image(systemName:"arrow.uturn.backward").font(.system(size:20)).frame(width:48,height:48)}.disabled(!model.canUndo).accessibilityLabel("Undo")
            Button {model.redo()} label:{Image(systemName:"arrow.uturn.forward").font(.system(size:20)).frame(width:48,height:48)}.disabled(!model.canRedo).accessibilityLabel("Redo")
            Button {export = true} label:{
                Text("Export").font(.system(size:14,weight:.medium)).foregroundStyle(.white).padding(.horizontal,24).frame(height:40)
                    .background(Palette.accent,in:RoundedRectangle(cornerRadius:10)).opacity(model.project.durationUs == 0 ? 0.4:1)
            }.disabled(model.project.durationUs == 0).padding(.trailing,6)
        }.padding(.horizontal,4).frame(height:52)
    }
    private var preview: some View {PreviewPane(model:model,onText:{_ in open("Text")})}
    private var transport: some View {
        #if targetEnvironment(macCatalyst)
        HStack(spacing:18) {
            Text("\(formatTime(model.playhead)) / \(formatTime(model.project.durationUs))").font(.caption.monospacedDigit()).foregroundStyle(Palette.dim)
            Spacer()
            Button {model.seek(0)} label:{Image(systemName:"backward.end.fill")}.accessibilityLabel("Start")
            Button {model.play()} label:{Image(systemName:model.playing ? "pause.fill":"play.fill").font(.title3)}.disabled(model.project.durationUs == 0).accessibilityLabel(model.playing ? loc("Pause"):loc("Play"))
            Button {model.seek(model.project.durationUs)} label:{Image(systemName:"forward.end.fill")}.accessibilityLabel("End")
            Spacer()
            Button {fullscreen.toggle()} label:{Image(systemName:fullscreen ? "arrow.down.right.and.arrow.up.left":"arrow.up.left.and.arrow.down.right")}.accessibilityLabel(fullscreen ? loc("Exit fullscreen"):loc("Fullscreen"))
            Button {model.selected = nil;model.selectedGap = nil; showInspector = false} label:{Image(systemName:"xmark")}.accessibilityLabel("Deselect")
        }.padding(.horizontal,16).padding(.vertical,10)
        #else
        // Android's transport bar: the time on the left, the three controls centred, full screen on the right.
        HStack(spacing:0) {
            Text("\(formatTimecode(model.playhead,fps:model.project.canvas.fps)) / \(formatTime(model.project.durationUs))").font(.system(size:12).monospacedDigit()).foregroundStyle(Palette.dim)
                .frame(maxWidth:.infinity,alignment:.leading)
            Button {model.seek(0)} label:{Image(systemName:"backward.end.fill").font(.system(size:20)).frame(width:48,height:48)}.accessibilityLabel("Start")
            Button {model.play()} label:{Image(systemName:model.playing ? "pause.fill":"play.fill").font(.system(size:30)).frame(width:48,height:48)}.disabled(model.project.durationUs == 0).accessibilityLabel(model.playing ? loc("Pause"):loc("Play"))
            Button {model.seek(model.project.durationUs)} label:{Image(systemName:"forward.end.fill").font(.system(size:20)).frame(width:48,height:48)}.accessibilityLabel("End")
            Button {fullscreen.toggle()} label:{Image(systemName:fullscreen ? "arrow.down.right.and.arrow.up.left":"arrow.up.left.and.arrow.down.right").font(.system(size:20)).frame(width:48,height:48)}
                .accessibilityLabel(fullscreen ? loc("Exit fullscreen"):loc("Fullscreen")).frame(maxWidth:.infinity,alignment:.trailing)
        }.foregroundStyle(Palette.text).padding(.horizontal,12).frame(height:44)
        #endif
    }
    private func tool(_ title:LocalizedStringKey,_ icon:String,action:@escaping ()->Void) -> some View {
        Button(action:action) {
            #if targetEnvironment(macCatalyst)
            Label(title,systemImage:icon).font(.system(size:15)).fixedSize().padding(.horizontal,8).frame(minHeight:36)
            #else
            VStack(spacing:2) {Image(systemName:icon).font(.system(size:22)).frame(height:24); Text(title).font(.small(11)).lineLimit(1)}
                .foregroundStyle(Palette.text).frame(width:76).padding(.vertical,6).contentShape(RoundedRectangle(cornerRadius:10))
            #endif
        }.buttonStyle(.plain).help(title).accessibilityLabel(title)
    }
    private func open(_ title:String) {panel = title;showInspector = true;inspectorRequest += 1}
    private func replaceMedia() {
        libraryOnly = false; subtitleFiles = false; replace = true
        importKind = model.selected.flatMap {model.project.track($0)?.kind} == .audio ? .audio:.main
        chooseMediaSource()
    }
    private func importSubtitles() {libraryOnly = false; replace = false; subtitleFiles = true; files = true}
    private func importLibrary() {libraryOnly = true;subtitleFiles = false;replace = false;importKind = .main;chooseMediaSource()}
    private func pick(_ kind:TrackKind,replace:Bool = false) {libraryOnly = false; importKind = kind; self.replace = replace; subtitleFiles = false; chooseMediaSource()}
    private func chooseMediaSource() {
        if importKind == .audio {files = true;return}
        #if targetEnvironment(macCatalyst)
        mediaSources = true
        #else
        picker = true
        #endif
    }
    private var tools:some View {
        ScrollView(.horizontal,showsIndicators:false) {HStack(spacing:2) {toolButtons}.padding(.vertical,8)}
            .background(Palette.surface).accessibilityIdentifier("editor.tools")
    }
    private var toolGrid:some View {
        ScrollView {LazyVGrid(columns:[GridItem(.adaptive(minimum:84),spacing:0,alignment:.leading)],spacing:0) {toolButtons}.padding(8)}
            .background(Palette.surface).accessibilityIdentifier("editor.tools")
    }
    /// Android labels this tool "Aspect ratio"; the Mac sidebar keeps the short "Ratio".
    private var ratioTitle:LocalizedStringKey {
        #if targetEnvironment(macCatalyst)
        "Ratio"
        #else
        "Aspect ratio"
        #endif
    }
    @ViewBuilder private var toolButtons:some View {
                if model.selectedIDs.count>1 {
                    tool("To new layer","square.3.layers.3d") {model.moveSelectionToLayer()}
                    tool("Duplicate","doc.on.doc") {model.duplicateSelected()}
                    tool("Delete","trash") {model.delete()}
                } else if let c = model.clip {
                    let audio = c.audioOnly || model.project.asset(c.assetID)?.type == .audio
                    let video = model.project.asset(c.assetID)?.type == .video
                    let track = model.project.track(c.id)
                    if c.text != nil {
                        tool("Edit","pencil") {open("Text")};tool("Font","textformat") {open("Font")}
                        tool("Style","paintbrush") {open("Style")};tool("Animation","sparkles") {open("Animation")}
                        tool("Position","arrow.up.and.down.and.arrow.left.and.right") {open("Position")}
                        tool("Keyframe","diamond") {model.change {$0.toggleKeyframe(c.id,at:model.playhead)}}
                        tool("Split","scissors") {model.split()}
                        tool("To new layer","square.3.layers.3d") {model.moveSelectionToLayer()}
                        tool("Duplicate","doc.on.doc") {model.duplicateSelected()};tool("Delete","trash") {model.delete()}
                    } else if audio {
                        tool("Volume","speaker.wave.2") {open("Volume")};tool("Speed","speedometer") {open("Speed")}
                        tool("Split","scissors") {model.split()}
                        tool("To new layer","square.3.layers.3d") {model.moveSelectionToLayer()}
                        tool("Duplicate","doc.on.doc") {model.duplicateSelected()}
                        tool("Save audio","square.and.arrow.up") {model.saveAudio()};tool("Delete","trash") {model.delete()}
                    } else {
                        tool("Split","scissors") {model.split()}
                        tool("To new layer","square.3.layers.3d") {model.moveSelectionToLayer()}
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
                    tool("Voiceover","mic") {open("Voiceover")}; tool("Layout","square.grid.2x2") {open("Layout")}; tool(ratioTitle,"aspectratio") {open("Ratio")}
                    tool("Split","scissors") {model.split()}; tool("Freeze","snowflake") {model.freeze()}
                }
    }
    private var keyboardCommands: some View {
        Group {
            Button("Undo") {model.undo()}.keyboardShortcut("z",modifiers:.command)
            Button("Redo") {model.redo()}.keyboardShortcut("z",modifiers:[.command,.shift])
            Button("Split") {model.split()}.keyboardShortcut("b",modifiers:.command)
            Button("Export") {export = true}.keyboardShortcut("e",modifiers:.command)
        }.hidden()
    }
}

struct ProjectHeading:View {
    let project:Project
    let expanded:Bool
    let onRename:()->Void
    let onFormat:()->Void
    var body:some View {
        VStack(alignment:.leading,spacing:1) {
            Button(action:onRename) {Text(project.name).font(.headline).lineLimit(1).foregroundStyle(.white)}
                .accessibilityLabel("Rename project").accessibilityIdentifier("editor.projectName")
            Button(action:onFormat) {
                HStack(spacing:4) {
                    Text(project.canvas.formatSummary).font(.small(11)).lineLimit(1).minimumScaleFactor(0.8)
                    Image(systemName:"arrowtriangle.down.fill").font(.system(size:8)).rotationEffect(.degrees(expanded ? 180:0))
                }.foregroundStyle(Palette.accent).padding(.vertical,3).contentShape(Rectangle())
            }.accessibilityLabel(expanded ? loc("Hide project format"):loc("Show project format"))
                .accessibilityValue(project.canvas.formatSummary).accessibilityIdentifier("editor.projectFormat")
        }.buttonStyle(.plain)
    }
}
