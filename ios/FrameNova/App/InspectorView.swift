import SwiftUI
import AVFoundation
import CoreText

/// Android's labelled slider: the name, the slider and the value on one line.
struct ValueSlider: View {
    var title:String
    @Environment(\.editGestureActions) private var editing
    @Binding var value:Double
    var range:ClosedRange<Double> = 0...1
    var format:(Double)->String = percentText
    var body: some View {
        HStack(spacing:0) {
            Text(loc(title)).font(.small(12)).foregroundStyle(Palette.dim).frame(width:84,alignment:.leading)
            EditorSlider(value:Binding(get:{min(max(value,range.lowerBound),range.upperBound)},set:{value = $0}),range:range,label:loc(title),onEditingChanged:{active in if active {editing?.begin()} else {editing?.end()}})
            Text(format(value)).font(.small(12)).foregroundStyle(Palette.text).lineLimit(1).frame(width:52,alignment:.leading)
        }
    }
}
/// Ratio, resolution, frame rate and background, as Android's project format panel and new project sheet show them.
struct CanvasControls: View {
    @Binding var canvas:CanvasSettings
    var body:some View {VStack(alignment:.leading,spacing:0) {
        PanelLabel("Aspect ratio")
        FlowLayout {ForEach(Aspect.allCases,id:\.self) {aspect in Chip(title:aspect.rawValue,selected:canvas.aspect == aspect) {canvas.aspect = aspect}}}
        PanelLabel("Resolution")
        FlowLayout {ForEach(Resolution.allCases.reversed(),id:\.self) {tier in Chip(title:tier.label,selected:canvas.tier == tier) {canvas.tier = tier}}}
        PanelLabel("Frame rate")
        FlowLayout {ForEach([60,50,30,25,24],id:\.self) {fps in Chip(title:localized("\(fps) fps"),selected:canvas.fps == fps) {canvas.fps = fps}}}
        PanelLabel("Background")
        FlowLayout {Chip(title:loc("Color"),selected:!canvas.blurred) {canvas.blurred = false};Chip(title:loc("Blur"),selected:canvas.blurred) {canvas.blurred = true}}
        if canvas.blurred {ValueSlider(title:"Blur",value:$canvas.blur)} else {ColorStrip(value:$canvas.background,allowNone:false)}
        Text("\(canvas.size.width) × \(canvas.size.height)").font(.small(12)).foregroundStyle(Palette.dim)
    }.frame(maxWidth:.infinity,alignment:.leading).accessibilityIdentifier("editor.canvasSettings")}
}
struct ColorStrip: View {
    @Binding var value:UInt32
    var allowNone = false
    var colors:[UInt32] = [0xFFFFFFFF,0xFF000000,0xFFFFD54F,0xFFFF7043,0xFFE53935,0xFFEC407A,0xFFAB47BC,0xFF7E57C2,0xFF42A5F5,0xFF26C6DA,0xFF66BB6A,0xFF9CCC65,0xFF8D6E63,0xFF9E9E9E]
    var body: some View {ScrollView(.horizontal,showsIndicators:false) {HStack(spacing:8) {ForEach((allowNone ? [0]:[])+colors,id:\.self) {color in
        Button {value = color} label:{
            Group {
                if color == 0 {Circle().fill(Palette.surface3).overlay(Text("⌀").font(.system(size:14)).foregroundStyle(Palette.text))}
                else {Circle().fill(Color(argb:color))}
            }.frame(width:30,height:30).overlay(Circle().stroke(value == color ? Palette.accent:(color == 0 ? .clear:Color.white.opacity(0.25)),lineWidth:2))
        }.buttonStyle(.plain)
    }}.padding(.vertical,6)}}
}
struct InspectorView: View {
    @ObservedObject var model:EditorModel
    var panel:String
    var onDone:(()->Void)? = nil
    /// Set when the panel slides over the editor: dragging its header reports the drag, and whether it has ended.
    var onHeaderDrag:((DragGesture.Value,Bool)->Void)? = nil
    /// Asks the cover panel to open its photo choice (the Mac timeline's empty cover tile).
    var choosePhoto:Binding<Bool>? = nil
    @ViewState<String?> private var childPanel:String?
    private var page:String {childPanel ?? panel}
    /// The names Android gives its panels.
    private var title:String {page == "Ratio" ? "Project format":page == "Volume" ? "Volume & fades":page == "Position" ? "Position & size":page}
    func value(_ key:WritableKeyPath<Clip,Double>) -> Binding<Double> {Binding(get:{model.clip?[keyPath:key] ?? 0},set:{v in model.edit {$0[keyPath:key] = v}})}
    func adjust(_ key:WritableKeyPath<Adjust,Double>) -> Binding<Double> {Binding(get:{model.clip?.adjust[keyPath:key] ?? 0},set:{v in model.liveVisualEdit {$0.adjust[keyPath:key] = v}})}
    func transform(_ key:WritableKeyPath<Transform,Double>) -> Binding<Double> {
        Binding(get:{model.clip?.transform(at:model.playhead)[keyPath:key] ?? 0},set:{v in
            guard let clip = model.clip else {return}; var t = clip.transform(at:model.playhead); t[keyPath:key] = v
            let time = model.playhead,fps = model.project.canvas.fps; model.liveVisualEdit {$0.setTransform(t,at:time,fps:fps)}
        })
    }
    func text<T>(_ key:WritableKeyPath<TextStyle,T>,fallback:T) -> Binding<T> {Binding(get:{model.clip?.text?[keyPath:key] ?? fallback},set:{v in model.edit {$0.text?[keyPath:key] = v}})}
    var body: some View {
        VStack(alignment:.leading,spacing:0) {
            VStack(spacing:0) {
                // The handle's area is generous, so the top of the panel is easy to grab.
                if onHeaderDrag != nil {Capsule().fill(Palette.dim.opacity(0.5)).frame(width:36,height:4).padding(.top,8).frame(maxWidth:.infinity,minHeight:28,alignment:.top).contentShape(Rectangle()).accessibilityHidden(true)}
                // Android's panel header: the title, the panel's own actions, then a check mark in the accent colour.
                HStack(spacing:0) {
                    if childPanel != nil {Button {childPanel = nil} label:{Image(systemName:"chevron.left").frame(width:32,height:48)}.accessibilityLabel("Back")}
                    Text(loc(title)).font(.system(size:16,weight:.semibold)).foregroundStyle(Palette.text)
                    Spacer()
                    headerActions
                    if let onDone {Button {model.endGesture();onDone()} label:{Image(systemName:"checkmark").font(.system(size:20)).foregroundStyle(Palette.accent).frame(width:48,height:48)}.accessibilityLabel("Done")}
                }.padding(.leading,16).padding(.trailing,4).frame(minHeight:48)
            }.frame(maxWidth:.infinity).contentShape(Rectangle())
                .gesture(DragGesture(minimumDistance:6,coordinateSpace:.global).onChanged {onHeaderDrag?($0,false)}.onEnded {onHeaderDrag?($0,true)},isEnabled:onHeaderDrag != nil)
            ScrollView {VStack(alignment:.leading,spacing:8) {content}.frame(maxWidth:.infinity,alignment:.leading).padding(.horizontal,16).padding(.vertical,4)}
        }.background(Palette.surface)
            // Takes every touch on the panel when it slides over the editor, so nothing underneath reacts to a drag here.
            .contentShape(Rectangle()).onTapGesture {}
            .environment(\.editGestureActions,EditGestureActions(begin:model.beginGesture,end:model.endGesture))
            .onChange(of:panel) {_,_ in childPanel = nil}
            .onDisappear {model.endGesture();if page == "Voiceover" && model.recording {model.toggleRecording()}}
    }
    @ViewBuilder private var headerActions:some View {
        switch page {
        case "Adjust":
            TextAction(title:loc("Reset")) {model.edit {$0.adjust = Adjust()}}
            TextAction(title:loc("Apply to all")) {if let a = model.clip?.adjust {model.change {p in for t in p.tracks.indices {for c in p.tracks[t].clips.indices {if p.tracks[t].kind != .audio && p.tracks[t].clips[c].text == nil {p.tracks[t].clips[c].adjust = a}}}}}}
        case "Filters":
            TextAction(title:loc("Apply to all")) {let f = model.clip?.filter; model.change {p in for t in p.tracks.indices {for c in p.tracks[t].clips.indices {if p.tracks[t].kind != .audio && p.tracks[t].clips[c].text == nil {p.tracks[t].clips[c].filter = f}}}}}
        case "Crop":
            TextAction(title:loc("Reset")) {model.edit {$0.crop = CropRect()}}
        case "Transition":
            TextAction(title:loc("Apply to all")) {
                let transition = model.clip?.transitionIn
                model.change {p in let ids = p.tracks[p.mainIndex].clips.dropFirst().map(\.id);for id in ids {p.setTransition(id,transition:transition)}}
            }
        default: EmptyView()
        }
    }
    private static let cropRatios:[(label:String,ratio:Double)] = [("Original",0),("1:1",1),("16:9",16.0/9),("9:16",9.0/16),("4:5",0.8),("4:3",4.0/3),("21:9",21.0/9)]
    private func speedText(_ speed:Double) -> String {let text = String(format:"%g",speed);return (text.contains(".") ? text:text+".0")+"×"}
    private func setSpeed(_ speed:Double) {if let id = model.selected {model.change {$0.setSpeed(id,speed:speed)}}}
    @ViewBuilder var content:some View {
        switch page {
        case "Cover":
            CoverPanel(model:model,choosePhoto:choosePhoto)
        case "Ratio":
            CanvasControls(canvas:Binding(get:{model.project.canvas},set:{v in model.change {$0.canvas = v}}))
        case "Speed":
            if model.project.asset(model.clip?.assetID)?.type == .image {
                Text("Photos don't have a speed. Trim them to change their duration.").foregroundStyle(Palette.dim)
            } else {
                let speed = model.clip?.speed ?? 1
                ValueSlider(title:"Speed",value:Binding(get:{log(speed)/log(4)},set:{setSpeed(pow(4,$0))}),range:-1...1,format:{String(format:"%.2f×",pow(4,$0))})
                FlowLayout {ForEach([0.25,0.5,0.75,1,1.5,2,3,4],id:\.self) {s in Chip(title:speedText(s),selected:abs(speed-s)<0.01) {setSpeed(s)}}}
                Text(String(format:loc("New duration %@. Pitch is preserved."),secondsText(Double(model.clip?.durationUs ?? 0)/1_000_000))).font(.small(12)).foregroundStyle(Palette.dim)
            }
        case "Volume":
            let maxFade = max(0.1,min(10,Double(model.clip?.durationUs ?? 0)/2_000_000))
            ValueSlider(title:"Volume",value:value(\.volume),range:0...2)
            ValueSlider(title:"Fade in",value:Binding(get:{Double(model.clip?.fadeInUs ?? 0)/1_000_000},set:{v in model.edit {$0.fadeInUs = Int64(v*1_000_000)}}),range:0...maxFade,format:secondsText)
            ValueSlider(title:"Fade out",value:Binding(get:{Double(model.clip?.fadeOutUs ?? 0)/1_000_000},set:{v in model.edit {$0.fadeOutUs = Int64(v*1_000_000)}}),range:0...maxFade,format:secondsText)
            FlowLayout {Chip(title:model.clip?.volume == 0 ? loc("Unmute"):loc("Mute"),selected:model.clip?.volume == 0) {model.edit {$0.volume = $0.volume == 0 ? 1:0}}}
        case "Position":
            FlowLayout(spacing:8) {
                OutlinedAction(title:loc("Fit")) {setTransform { $0.cx = 0.5;$0.cy = 0.5;$0.scale = 1 }}
                if let clip = model.clip,let asset = model.project.asset(clip.assetID),asset.width>0,asset.height>0 {
                    OutlinedAction(title:loc("Fill")) {
                        let w = Double(asset.width)*max(0.01,1-clip.crop.left-clip.crop.right),h = Double(asset.height)*max(0.01,1-clip.crop.top-clip.crop.bottom),size = model.project.canvas.size
                        let fit = min(Double(size.width)/w,Double(size.height)/h),fill = max(Double(size.width)/w,Double(size.height)/h)
                        setTransform {$0.cx = 0.5;$0.cy = 0.5;$0.scale = fill/fit}
                    }
                }
                OutlinedAction(title:loc("Rotate 90°")) {setTransform {$0.rotation = ((($0.rotation/90).rounded()+1)*90).truncatingRemainder(dividingBy:360)}}
                if model.clip?.text == nil {
                    OutlinedAction(title:loc("Flip ↔")) {model.edit {$0.flipH.toggle()}}
                    OutlinedAction(title:loc("Flip ↕")) {model.edit {$0.flipV.toggle()}}
                }
                OutlinedAction(title:loc("Reset")) {model.edit {$0.transform = Transform();$0.keyframes = []}}
            }
            ValueSlider(title:"Scale",value:transform(\.scale),range:0.05...4)
            ValueSlider(title:"Rotation",value:transform(\.rotation),range:-180...180,format:{"\(Int($0.rounded()))°"})
            ValueSlider(title:"Opacity",value:transform(\.opacity))
            ValueSlider(title:"X",value:transform(\.cx),range:-0.5...1.5); ValueSlider(title:"Y",value:transform(\.cy),range:-0.5...1.5)
            if model.clip?.keyframes.isEmpty == false {Text("Keyframed: changes apply to the keyframe at the playhead.").font(.small(12)).foregroundStyle(Palette.dim)}
        case "Adjust":
            ValueSlider(title:"Brightness",value:adjust(\.brightness),range:-1...1,format:signedText); ValueSlider(title:"Contrast",value:adjust(\.contrast),range:-1...1,format:signedText)
            ValueSlider(title:"Saturation",value:adjust(\.saturation),range:-1...1,format:signedText); ValueSlider(title:"Warmth",value:adjust(\.warmth),range:-1...1,format:signedText)
            ValueSlider(title:"Tint",value:adjust(\.tint),range:-1...1,format:signedText)
            ValueSlider(title:"Hue",value:adjust(\.hue),range:-180...180,format:{"\(Int($0.rounded()))°"})
            ValueSlider(title:"Sharpen",value:adjust(\.sharpen)); ValueSlider(title:"Vignette",value:adjust(\.vignette))
        case "Filters":
            ScrollView(.horizontal,showsIndicators:false) {HStack(spacing:10) {
                FilterPreview(id:nil,selected:model.clip?.filter == nil) {model.edit {$0.filter = nil}}.frame(width:64)
                ForEach(FilterCube.ids,id:\.self) {id in FilterPreview(id:id,selected:model.clip?.filter?.id == id) {model.edit {$0.filter = FilterSetting(id:id,intensity:model.clip?.filter?.intensity ?? 1)}}.frame(width:64)}
            }.padding(.vertical,8)}
            if model.clip?.filter != nil {ValueSlider(title:"Intensity",value:Binding(get:{model.clip?.filter?.intensity ?? 1},set:{v in model.liveVisualEdit {$0.filter?.intensity = v}}))}
        case "Crop":
            FlowLayout {ForEach(Self.cropRatios,id:\.label) {crop in
                let label = crop.label,ratio = crop.ratio
                
                Chip(title:label == "Original" ? loc(label):label) {
                    guard let asset = model.project.asset(model.clip?.assetID),asset.width>0,asset.height>0 else {return}
                    let source = Double(asset.width)/Double(asset.height)
                    model.edit {$0.crop = ratio == 0 ? CropRect():source>ratio ? CropRect(left:(1-ratio/source)/2,right:(1-ratio/source)/2):CropRect(top:(1-source/ratio)/2,bottom:(1-source/ratio)/2)}
                }
            }}
            cropSlider("Left",\.left); cropSlider("Right",\.right); cropSlider("Top",\.top); cropSlider("Bottom",\.bottom)
        case "Transition":
            let current = model.clip?.transitionIn
            FlowLayout {
                Chip(title:loc("None"),selected:current == nil) {if let id = model.selected {model.change {$0.setTransition(id,transition:nil)}}}
                ForEach(TransitionType.allCases,id:\.self) {type in Chip(title:loc(type.rawValue),selected:current?.type == type) {if let id = model.selected {model.change {$0.setTransition(id,transition:Transition(type:type,durationUs:Int64(min(Double(current?.durationUs ?? 500_000)/1_000_000,maxTransitionDuration)*1_000_000)))}}}}
            }
            if current != nil {
                ValueSlider(title:"Duration",value:Binding(get:{min(Double(current?.durationUs ?? 500_000)/1_000_000,maxTransitionDuration)},set:{v in if let id = model.selected, var tr = model.clip?.transitionIn {tr.durationUs = Int64(v*1_000_000); model.change {$0.setTransition(id,transition:tr)}}}),range:0.1...maxTransitionDuration,format:secondsText)
            }
        case "Layout":
            LayoutPanel(model:model)
        case "Text":
            TextField("Text",text:text(\.text,fallback:"Text"),axis:.vertical).textFieldStyle(.roundedBorder)
            FlowLayout {
                ForEach([("Top",0.14),("Center",0.5),("Bottom",0.86)],id:\.0) {label,y in OutlinedAction(title:loc(label)) {setTransform {$0.cy = y;$0.cx = 0.5}}}
                OutlinedAction(title:loc("Font")) {childPanel = "Font"};OutlinedAction(title:loc("Style")) {childPanel = "Style"};OutlinedAction(title:loc("Animation")) {childPanel = "Animation"}
            }
        case "Font":
            FontPickerPanel(model:model)
        case "Style":
            HStack(spacing:0) {
                toggleIcon("bold",on:text(\.bold,fallback:true),label:"Bold"); toggleIcon("italic",on:text(\.italic,fallback:false),label:"Italic")
                Spacer().frame(width:12)
                ForEach([("Left","text.alignleft"),("Center","text.aligncenter"),("Right","text.alignright")],id:\.0) {name,icon in
                    Button {model.edit {$0.text?.alignment = name}} label:{Image(systemName:icon).font(.system(size:20)).foregroundStyle(model.clip?.text?.alignment == name ? Palette.accent:Palette.dim).frame(width:48,height:48)}.accessibilityLabel(loc("Align "+name.lowercased()))
                }
                Spacer()
                Text("Shadow").font(.small(12)).foregroundStyle(Palette.dim).padding(.trailing,8)
                Toggle("Shadow",isOn:text(\.shadow,fallback:true)).labelsHidden()
            }
            ValueSlider(title:"Size",value:text(\.size,fallback:0.07),range:0.02...0.35,format:{String(format:"%.1f",($0*1000).rounded()/10)})
            PanelLabel("Color"); ColorStrip(value:text(\.color,fallback:0xFFFFFFFF),allowNone:false)
            ValueSlider(title:"Outline",value:text(\.strokeWidth,fallback:0),range:0...0.25)
            if (model.clip?.text?.strokeWidth ?? 0)>0 {ColorStrip(value:text(\.strokeColor,fallback:0xFF000000),allowNone:false)}
            PanelLabel("Background"); ColorStrip(value:text(\.backgroundColor,fallback:0),allowNone:true,colors:[0xCC000000,0x99000000,0xCCFFFFFF,0xE6FFD54F,0xE6E53935,0xE642A5F5,0xE666BB6A,0xE67E57C2])
            ValueSlider(title:"Letters",value:text(\.letterSpacing,fallback:0),range:-0.05...0.5,format:{String(format:"%.2f",$0)})
            ValueSlider(title:"Lines",value:text(\.lineSpacing,fallback:1.1),range:0.8...2,format:{String(format:"%.1f",$0)})
        case "Animation":
            PanelLabel("In")
            FlowLayout {ForEach(TextAnimation.allCases,id:\.self) {a in Chip(title:loc(a.rawValue),selected:model.clip?.text?.animIn == a) {model.edit {$0.text?.animIn = a}}}}
            PanelLabel("Out")
            FlowLayout {ForEach(TextAnimation.allCases.filter {$0 != .typewriter},id:\.self) {a in Chip(title:loc(a.rawValue),selected:model.clip?.text?.animOut == a) {model.edit {$0.text?.animOut = a}}}}
            ValueSlider(title:"Duration",value:Binding(get:{Double(model.clip?.text?.animDurationUs ?? 400_000)/1_000_000},set:{value in model.edit {$0.text?.animDurationUs = Int64(value*1_000_000)}}),range:0.1...2,format:secondsText)
        case "Stickers":
            FlowLayout(spacing:8) {ForEach(["⭐","✨","🔥","❤️","💖","😂","😍","🥰","😎","🤩","😭","🥺","👍","👏","🙌","🎉","🎂","🎵","🎬","📸","🌸","🌈","☀️","🌙","⚡","💯","✅","❌","➡️","⬅️","⬆️","⬇️","💬","💭","🐶","🐱","🍜","☕","✈️","🏝️"],id:\.self) {s in
                Button {model.addText("Sticker",content:s)} label:{Text(s).font(.system(size:26)).frame(width:48,height:48).background(Palette.surface2,in:RoundedRectangle(cornerRadius:10))}.buttonStyle(.plain)
            }}
            Text("Tip: use Overlay to add your own PNG stickers with transparency.").font(.small(12)).foregroundStyle(Palette.dim).padding(.top,8)
        case "Voiceover":
            HStack(spacing:16) {
                Button {model.toggleRecording()} label:{
                    Image(systemName:model.recording ? "stop.fill":"circle.fill").font(.system(size:28)).foregroundStyle(.white).frame(width:72,height:72).background(model.recording ? Palette.danger:Palette.accent,in:Circle())
                }.buttonStyle(.plain).accessibilityLabel(model.recording ? loc("Stop recording"):loc("Record"))
                VStack(alignment:.leading,spacing:8) {
                    Text(model.recording ? String(format:loc("Recording… %@"),formatTime(Int64(model.recordingElapsed*1_000_000))):loc("Records from the playhead while the video plays.")).foregroundStyle(Palette.dim)
                    GeometryReader {geometry in ZStack(alignment:.leading) {Capsule().fill(Palette.surface3);Capsule().fill(Palette.teal).frame(width:geometry.size.width*min(1,max(0,model.recordingLevel)))}}.frame(height:8)
                }
            }.padding(.vertical,8)
        default: Text("Select a clip to edit it.").foregroundStyle(Palette.dim)
        }
    }
    private func toggleIcon(_ icon:String,on:Binding<Bool>,label:String) -> some View {
        Button {on.wrappedValue.toggle()} label:{Image(systemName:icon).font(.system(size:20)).foregroundStyle(on.wrappedValue ? Palette.accent:Palette.dim).frame(width:48,height:48)}.accessibilityLabel(loc(label))
    }
    private var maxTransitionDuration:Double {
        let clips = model.project.tracks[model.project.mainIndex].clips
        guard let i = clips.firstIndex(where:{$0.id == model.selected}),i>0 else {return 0.5}
        return max(0.1,Double(min(clips[i-1].durationUs,clips[i].durationUs))/2_000_000)
    }
    private func setTransform(_ update:(inout Transform)->Void) {
        guard let clip = model.clip else {return};var t = clip.transform(at:model.playhead);update(&t)
        let time = model.playhead,fps = model.project.canvas.fps
        model.edit {$0.setTransform(t,at:time,fps:fps)}
    }
    func cropSlider(_ title:String,_ key:WritableKeyPath<CropRect,Double>) -> some View {ValueSlider(title:title,value:Binding(get:{model.clip?.crop[keyPath:key] ?? 0},set:{v in model.liveVisualEdit {$0.crop[keyPath:key] = v}}),range:0...0.45)}
}
@MainActor enum FontRegistry {
    static var names:[String] {UIFont.familyNames.sorted().flatMap {UIFont.fontNames(forFamilyName:$0)}}
    static func register() {
        for url in (try? FileManager.default.contentsOfDirectory(at:DownloadFonts.folder,includingPropertiesForKeys:nil)) ?? [] {CTFontManagerRegisterFontsForURL(url as CFURL,.process,nil)}
        for ext in ["ttf","otf"] {for url in Bundle.main.urls(forResourcesWithExtension:ext,subdirectory:nil) ?? [] {CTFontManagerRegisterFontsForURL(url as CFURL,.process,nil)}}
    }
}
/// Saves a copy of a file to a place the user chooses (the Files picker on iPhone and iPad, a save panel on the Mac).
struct FileSaveSheet: UIViewControllerRepresentable {
    let url:URL
    /// Called with the file at the chosen location.
    var onPicked:(URL)->Void = {_ in}
    /// Called when the picker closes, whether or not a location was chosen.
    var onFinish:()->Void = {}
    func makeCoordinator() -> Coordinator {Coordinator(onPicked:onPicked,onFinish:onFinish)}
    func makeUIViewController(context:Context) -> UIDocumentPickerViewController {
        let picker = UIDocumentPickerViewController(forExporting:[url],asCopy:true)
        picker.delegate = context.coordinator
        return picker
    }
    func updateUIViewController(_ controller:UIDocumentPickerViewController,context:Context) {}
    final class Coordinator:NSObject,UIDocumentPickerDelegate {
        let onPicked:(URL)->Void
        let onFinish:()->Void
        init(onPicked:@escaping (URL)->Void,onFinish:@escaping ()->Void) {self.onPicked = onPicked;self.onFinish = onFinish}
        func documentPicker(_ controller:UIDocumentPickerViewController,didPickDocumentsAt urls:[URL]) {
            if let url = urls.first {onPicked(url)}
            onFinish()
        }
        func documentPickerWasCancelled(_ controller:UIDocumentPickerViewController) {onFinish()}
    }
}
struct ShareSheet: UIViewControllerRepresentable {
    let url:URL
    func makeUIViewController(context:Context) -> UIActivityViewController {UIActivityViewController(activityItems:[url],applicationActivities:nil)}
    func updateUIViewController(_ controller:UIActivityViewController,context:Context) {}
}
/// Android's export dialog: chips for resolution, frame rate, codec and quality, the size estimate, then progress and the result.
struct ExportView: View {
    let project:Project
    @ObservedObject var exporter:Exporter
    /// Closes the dialog by clearing the state that presents it. `dismiss` is not used: in the Mac's in-window dialog it
    /// would close the whole editor.
    var onClose:()->Void = {}
    @ViewState<ExportSettings> private var settings = ExportSettings()
    @ViewState<Bool> private var share = false
    @ViewState<Bool> private var saved = false
    @ViewState<URL?> private var saveFile:URL?
    private var canvas:CanvasSettings {var c = project.canvas;c.tier = settings.tier;return c}
    private var bitrate:Int {ExportEstimate.bitrate(width:canvas.size.width,height:canvas.size.height,fps:settings.fps,hevc:settings.hevc,quality:settings.quality)}
    private var fileSize:String? {
        let size = exporter.savedBytes ?? exporter.url.flatMap {(try? $0.resourceValues(forKeys:[.fileSizeKey]))?.fileSize}
        return size.map {String(format:"%.1f MB",Double($0)/1_000_000)}
    }
    private var title:String {
        if exporter.running {return loc("Exporting…")}
        if exporter.savedTo != nil {return loc("Video saved")}
        if exporter.url != nil {return saved ? loc("Video saved"):loc("Export complete")}
        if exporter.error != nil {return loc("Export failed")}
        return loc("Export")
    }
    private func line(_ text:String,size:CGFloat = 12) -> some View {Text(text).font(.system(size:size)).foregroundStyle(Palette.dim).fixedSize(horizontal:false,vertical:true)}
    @ViewBuilder private var content:some View {
        if exporter.running {
            Text(project.name).font(.system(size:16)).foregroundStyle(Palette.text).lineLimit(1)
            ProgressView(value:Double(exporter.progress)).padding(.top,12)
            line(String(format:loc("%lld%% · keeps running if you leave the app"),Int(exporter.progress*100))).padding(.top,6)
        } else if let url = exporter.savedTo ?? exporter.url {
            Text(url.lastPathComponent+(fileSize.map {"\n"+$0} ?? "")).font(.system(size:16)).foregroundStyle(Palette.text)
            if let error = exporter.error {Text(error).font(.system(size:14)).foregroundStyle(Palette.danger).padding(.top,8)}
        } else if let error = exporter.error {
            Text(error).font(.system(size:16)).foregroundStyle(Palette.text)
        } else {
            PanelLabel("Resolution")
            FlowLayout {ForEach(Resolution.allCases.reversed(),id:\.self) {tier in Chip(title:tier.label,selected:settings.tier == tier) {settings.tier = tier}}}
            PanelLabel("Frame rate")
            FlowLayout {ForEach([60,50,30,25,24],id:\.self) {fps in Chip(title:"\(fps)",selected:settings.fps == fps) {settings.fps = fps}}}
            PanelLabel("Codec")
            FlowLayout {Chip(title:loc("HEVC (smaller)"),selected:settings.hevc) {settings.hevc = true};Chip(title:loc("H.264 (compatible)"),selected:!settings.hevc) {settings.hevc = false}}
            PanelLabel("Quality")
            FlowLayout {ForEach(["Standard","High","Maximum"],id:\.self) {quality in Chip(title:loc(quality),selected:settings.quality == quality) {settings.quality = quality}}}
            line(String(format:loc("%lld × %lld · %@ Mbps · about %@ MB"),canvas.size.width,canvas.size.height,String(format:"%.0f",Double(bitrate)/1_000_000),String(format:"%.0f",Double(ExportEstimate.bytes(bitrate:bitrate,durationUs:project.durationUs))/1_000_000))).padding(.top,8)
            if project.assets.contains(where:{$0.isHDR == true}) {line(loc("HDR clips are converted to SDR."))}
        }
    }
    /// iPhone and iPad add the finished video to the Photos library.
    private func saveVideo() {
        Task {await exporter.saveToPhotos(); saved = exporter.error == nil}
    }
    #if targetEnvironment(macCatalyst)
    /// The Mac asks where to save the video before rendering (the Finder's save dialog), so a long export can never end
    /// with a video nobody saved. A placeholder file with the project's name is offered to the dialog; the render is
    /// written into the file the user picks.
    private func askDestination() {
        let invalid = CharacterSet(charactersIn:"/:\\").union(.controlCharacters)
        let base = project.name.components(separatedBy:invalid).joined(separator:" ").trimmingCharacters(in:.whitespaces)
        let placeholder = FileManager.default.temporaryDirectory.appendingPathComponent("\(base.isEmpty ? "FrameNova":base).mp4")
        try? FileManager.default.removeItem(at:placeholder)
        guard FileManager.default.createFile(atPath:placeholder.path,contents:Data()) else {exporter.error = loc("Could not prepare the export file.");return}
        saveFile = placeholder
    }
    #endif
    @ViewBuilder private var buttons:some View {
        if exporter.running {TextAction(title:loc("Cancel")) {exporter.cancel()}}
        else if exporter.savedTo != nil {
            TextAction(title:loc("Done"),prominent:true) {onClose()}.keyboardShortcut(.defaultAction)
        } else if exporter.url != nil {
            TextAction(title:loc("Share")) {share = true}
            TextAction(title:saved ? loc("Saved"):loc("Save video"),enabled:!saved) {saveVideo()}
            TextAction(title:loc("Done"),prominent:true) {onClose()}.keyboardShortcut(.defaultAction)
        } else if exporter.error != nil {TextAction(title:loc("OK"),prominent:true) {exporter.error = nil}}
        else {
            TextAction(title:loc("Cancel")) {onClose()}.keyboardShortcut(.cancelAction)
            #if targetEnvironment(macCatalyst)
            FilledAction(title:loc("Export")) {askDestination()}
            #else
            FilledAction(title:loc("Export")) {exporter.start(project,settings:settings)}
            #endif
        }
    }
    var body: some View {
        VStack(alignment:.leading,spacing:0) {
            Text(title).font(.system(size:24)).foregroundStyle(Palette.text).padding(.bottom,16)
            ScrollView {VStack(alignment:.leading,spacing:0) {content}.frame(maxWidth:.infinity,alignment:.leading)}
            HStack(spacing:8) {Spacer(); buttons}.padding(.top,24)
        }.padding(24).background(Palette.surface3.ignoresSafeArea()).presentationDetents([.medium,.large])
            .onAppear {
                // A finished export belongs to the project as it was then: start from the settings again.
                exporter.reset()
                settings.tier = project.canvas.tier; settings.fps = project.canvas.fps
            }
            .sheet(isPresented:$share) {if let url = exporter.url {ShareSheet(url:url)}}
            .sheet(isPresented:Binding(get:{saveFile != nil},set:{if !$0 {saveFile = nil}})) {
                if let file = saveFile {FileSaveSheet(url:file,onPicked:{destination in exporter.start(project,settings:settings,destination:destination)}) {saveFile = nil}}
            }
            .interactiveDismissDisabled(exporter.running)
    }
}
