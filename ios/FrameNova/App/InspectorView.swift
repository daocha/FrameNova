import SwiftUI
import AVFoundation
import CoreText

struct ValueSlider: View {
    var title:String
    @Environment(\.editGestureActions) private var editing
    @Binding var value:Double
    var range:ClosedRange<Double> = 0...1
    var body: some View {VStack(alignment:.leading,spacing:4) {HStack {Text(title); Spacer(); Text(value.formatted(.number.precision(.fractionLength(2)))).foregroundStyle(Palette.dim).monospacedDigit()}; Slider(value:$value,in:range,onEditingChanged:{active in if active {editing?.begin()} else {editing?.end()}})}.font(.caption)}
}
struct CanvasControls: View {
    @Binding var canvas:CanvasSettings
    var body:some View {ScrollView {VStack(alignment:.leading,spacing:12) {
        Text("Aspect ratio").font(.caption).foregroundStyle(Palette.dim)
        LazyVGrid(columns:[GridItem(.adaptive(minimum:64))]) {ForEach(Aspect.allCases,id:\.self) {aspect in
            Button(aspect.rawValue) {canvas.aspect = aspect}.buttonStyle(.bordered).tint(canvas.aspect == aspect ? Palette.accent:Palette.dim)
        }}
        Text("Resolution").font(.caption).foregroundStyle(Palette.dim)
        LazyVGrid(columns:[GridItem(.adaptive(minimum:64))]) {ForEach(Resolution.allCases.reversed(),id:\.self) {tier in
            Button(tier.label) {canvas.tier = tier}.buttonStyle(.bordered).tint(canvas.tier == tier ? Palette.accent:Palette.dim)
        }}
        Text("Frame rate").font(.caption).foregroundStyle(Palette.dim)
        LazyVGrid(columns:[GridItem(.adaptive(minimum:72))]) {ForEach([60,50,30,25,24],id:\.self) {fps in
            Button("\(fps) fps") {canvas.fps = fps}.buttonStyle(.bordered).tint(canvas.fps == fps ? Palette.accent:Palette.dim)
        }}
        Text("Background").font(.caption).foregroundStyle(Palette.dim)
        HStack {Button("Color") {canvas.blurred = false}.tint(canvas.blurred ? Palette.dim:Palette.accent);Button("Blur") {canvas.blurred = true}.tint(canvas.blurred ? Palette.accent:Palette.dim)}.buttonStyle(.bordered)
        if canvas.blurred {ValueSlider(title:"Blur",value:$canvas.blur)} else {ColorStrip(value:$canvas.background,allowNone:false)}
        Text("\(canvas.size.width) × \(canvas.size.height)").font(.caption).foregroundStyle(Palette.dim)
    }.padding()}.background(Palette.surface).accessibilityIdentifier("editor.canvasSettings")}
}
struct ColorStrip: View {
    @Binding var value:UInt32
    var allowNone = false
    var colors:[UInt32] = [0xFFFFFFFF,0xFF000000,0xFFFFD54F,0xFFFF7043,0xFFE53935,0xFFEC407A,0xFFAB47BC,0xFF7E57C2,0xFF42A5F5,0xFF26C6DA,0xFF66BB6A,0xFF9CCC65,0xFF8D6E63,0xFF9E9E9E]
    var body: some View {ScrollView(.horizontal,showsIndicators:false) {HStack {ForEach((allowNone ? [0]:[])+colors,id:\.self) {color in Button {value = color} label:{Circle().fill(Color(argb:color)).frame(width:28,height:28).overlay(Circle().stroke(value == color ? Color.white:Palette.dim,lineWidth:value == color ? 3:1)).overlay {if color == 0 {Image(systemName:"nosign").foregroundStyle(Palette.dim)}}.padding(3)}.buttonStyle(.plain)}}}}
}
struct InspectorView: View {
    @ObservedObject var model:EditorModel
    var panel:String
    var onDone:(()->Void)? = nil
    @ViewState<String?> private var childPanel:String?
    private var page:String {childPanel ?? panel}
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
            HStack {if childPanel != nil {Button {childPanel = nil} label:{Image(systemName:"chevron.left")}.accessibilityLabel("Back")};Text(page == "Ratio" ? "Project format":page).font(.headline);Spacer();if let onDone {Button("Done") {model.endGesture();onDone()}}}.padding()
            Divider()
            if page == "Ratio" {CanvasControls(canvas:Binding(get:{model.project.canvas},set:{v in model.change {$0.canvas = v}}))}
            else {ScrollView {VStack(alignment:.leading,spacing:18) {content}.padding()}}
        }.background(Palette.surface)
            .environment(\.editGestureActions,EditGestureActions(begin:model.beginGesture,end:model.endGesture))
            .onChange(of:panel) {_,_ in childPanel = nil}
            .onDisappear {model.endGesture();if page == "Voiceover" && model.recording {model.toggleRecording()}}
    }
    @ViewBuilder var content:some View {
        switch page {
        case "Speed":
            ValueSlider(title:"Speed",value:Binding(get:{model.clip?.speed ?? 1},set:{v in if let id = model.selected {model.change {$0.setSpeed(id,speed:v)}}}),range:0.25...4)
            HStack {ForEach([0.25,0.5,1,2,4],id:\.self) {s in Button("\(s.formatted())×") {if let id = model.selected {model.change {$0.setSpeed(id,speed:s)}}}.buttonStyle(.bordered)}}
            Text("Pitch is preserved.").font(.caption).foregroundStyle(Palette.dim)
        case "Volume":
            ValueSlider(title:"Volume",value:value(\.volume),range:0...2)
            audioFades
            Button(model.clip?.volume == 0 ? "Unmute":"Mute") {model.edit {$0.volume = $0.volume == 0 ? 1:0}}
        case "Fade":
            audioFades
        case "Position":
            ValueSlider(title:"X",value:transform(\.cx),range:-0.5...1.5); ValueSlider(title:"Y",value:transform(\.cy),range:-0.5...1.5)
            ValueSlider(title:"Scale",value:transform(\.scale),range:0.05...4); ValueSlider(title:"Rotation",value:transform(\.rotation),range:-180...180); ValueSlider(title:"Opacity",value:transform(\.opacity))
            HStack {Button("Fit") {setTransform { $0.cx = 0.5;$0.cy = 0.5;$0.scale = 1 }}
                Button("Fill") {
                    guard let clip = model.clip,let asset = model.project.asset(clip.assetID),asset.width>0,asset.height>0 else {return}
                    let w = Double(asset.width)*max(0.01,1-clip.crop.left-clip.crop.right),h = Double(asset.height)*max(0.01,1-clip.crop.top-clip.crop.bottom),size = model.project.canvas.size
                    let fit = min(Double(size.width)/w,Double(size.height)/h),fill = max(Double(size.width)/w,Double(size.height)/h)
                    setTransform {$0.cx = 0.5;$0.cy = 0.5;$0.scale = fill/fit}
                }
                Button("Rotate 90°") {setTransform {$0.rotation = (floor($0.rotation/90)+1)*90}}}.buttonStyle(.bordered)
            HStack {Button("Flip ↔") {model.edit {$0.flipH.toggle()}}; Button("Flip ↕") {model.edit {$0.flipV.toggle()}}}.buttonStyle(.bordered)
            Button("Reset") {model.edit {$0.transform = Transform();$0.keyframes = []}}
        case "Adjust":
            ValueSlider(title:"Brightness",value:adjust(\.brightness),range:-1...1); ValueSlider(title:"Contrast",value:adjust(\.contrast),range:-1...1)
            ValueSlider(title:"Saturation",value:adjust(\.saturation),range:-1...1); ValueSlider(title:"Warmth",value:adjust(\.warmth),range:-1...1); ValueSlider(title:"Tint",value:adjust(\.tint),range:-1...1)
            ValueSlider(title:"Hue",value:adjust(\.hue),range:-180...180); ValueSlider(title:"Vignette",value:adjust(\.vignette)); ValueSlider(title:"Sharpen",value:adjust(\.sharpen))
            Button("Reset") {model.edit {$0.adjust = Adjust()}}
            Button("Apply to all") {if let a = model.clip?.adjust {model.change {p in for t in p.tracks.indices {for c in p.tracks[t].clips.indices {if p.tracks[t].kind != .audio && p.tracks[t].clips[c].text == nil {p.tracks[t].clips[c].adjust = a}}}}}}
        case "Filters":
            LazyVGrid(columns:[GridItem(.adaptive(minimum:64))],spacing:10) {
                FilterPreview(id:nil,selected:model.clip?.filter == nil) {model.edit {$0.filter = nil}}
                ForEach(FilterCube.ids,id:\.self) {id in FilterPreview(id:id,selected:model.clip?.filter?.id == id) {model.edit {$0.filter = FilterSetting(id:id)}}}
            }
            ValueSlider(title:"Intensity",value:Binding(get:{model.clip?.filter?.intensity ?? 1},set:{v in model.liveVisualEdit {$0.filter?.intensity = v}}))
            Button("Apply to all") {let f = model.clip?.filter; model.change {p in for t in p.tracks.indices {for c in p.tracks[t].clips.indices {if p.tracks[t].kind != .audio && p.tracks[t].clips[c].text == nil {p.tracks[t].clips[c].filter = f}}}}}
        case "Crop":
            ScrollView(.horizontal) {HStack {
                Button("Original") {model.edit {$0.crop = CropRect()}}
                ForEach([Aspect.square,.wide,.portrait,.social,.classic,.cinema],id:\.self) {aspect in Button(aspect.rawValue) {
                    guard let asset = model.project.asset(model.clip?.assetID),asset.width>0,asset.height>0 else {return}
                    let source = Double(asset.width)/Double(asset.height),ratio = aspect.ratio
                    model.edit {$0.crop = source>ratio ? CropRect(left:(1-ratio/source)/2,right:(1-ratio/source)/2):CropRect(top:(1-source/ratio)/2,bottom:(1-source/ratio)/2)}
                }}
            }.buttonStyle(.bordered)}
            cropSlider("Left",\.left); cropSlider("Right",\.right); cropSlider("Top",\.top); cropSlider("Bottom",\.bottom)
            Button("Reset") {model.edit {$0.crop = CropRect()}}
        case "Transition":
            Button("None") {if let id = model.selected {model.change {$0.setTransition(id,transition:nil)}}}
            ForEach(TransitionType.allCases,id:\.self) {type in Button(type.rawValue) {if let id = model.selected {model.change {$0.setTransition(id,transition:Transition(type:type))}}}.buttonStyle(.bordered)}
            ValueSlider(title:"Duration (seconds)",value:Binding(get:{Double(model.clip?.transitionIn?.durationUs ?? 500_000)/1_000_000},set:{v in if let id = model.selected, var tr = model.clip?.transitionIn {tr.durationUs = Int64(v*1_000_000); model.change {$0.setTransition(id,transition:tr)}}}),range:0.1...maxTransitionDuration)
            Button("Apply to all") {
                let transition = model.clip?.transitionIn
                model.change {p in let ids = p.tracks[p.mainIndex].clips.dropFirst().map(\.id);for id in ids {p.setTransition(id,transition:transition)}}
            }
        case "Layout":
            LayoutPanel(model:model)
        case "Text":
            TextField("Text",text:text(\.text,fallback:"Text"),axis:.vertical).textFieldStyle(.roundedBorder)
            HStack {Button("Font") {childPanel = "Font"};Button("Style") {childPanel = "Style"};Button("Animation") {childPanel = "Animation"}}.buttonStyle(.bordered)
        case "Font":
            FontPickerPanel(model:model)
        case "Style":
            ValueSlider(title:"Size",value:text(\.size,fallback:0.07),range:0.02...0.4)
            Toggle("Bold",isOn:text(\.bold,fallback:true));Toggle("Italic",isOn:text(\.italic,fallback:false));Toggle("Shadow",isOn:text(\.shadow,fallback:true))
            Picker("Alignment",selection:text(\.alignment,fallback:"Center")) {ForEach(["Left","Center","Right"],id:\.self) {Text($0)}}
            Text("Color").font(.caption);ColorStrip(value:text(\.color,fallback:0xFFFFFFFF),allowNone:false)
            Text("Background").font(.caption);ColorStrip(value:text(\.backgroundColor,fallback:0),allowNone:true,colors:[0xCC000000,0x99000000,0xCCFFFFFF,0xE6FFD54F,0xE6E53935,0xE642A5F5,0xE666BB6A,0xE67E57C2])
            Text("Outline").font(.caption);ColorStrip(value:text(\.strokeColor,fallback:0xFF000000),allowNone:false)
            ValueSlider(title:"Outline width",value:text(\.strokeWidth,fallback:0),range:0...0.15)
            ValueSlider(title:"Letter spacing",value:text(\.letterSpacing,fallback:0),range:0...0.5)
            ValueSlider(title:"Line spacing",value:text(\.lineSpacing,fallback:1.1),range:0.8...2)
        case "Animation":
            Picker("In",selection:text(\.animIn,fallback:.none)) {ForEach(TextAnimation.allCases,id:\.self) {Text($0.rawValue).tag($0)}}
            Picker("Out",selection:text(\.animOut,fallback:.none)) {ForEach(TextAnimation.allCases.filter {$0 != .typewriter},id:\.self) {Text($0.rawValue).tag($0)}}
            ValueSlider(title:"Duration",value:Binding(get:{Double(model.clip?.text?.animDurationUs ?? 400_000)/1_000_000},set:{value in model.edit {$0.text?.animDurationUs = Int64(value*1_000_000)}}),range:0.1...2)
        case "Stickers":
            LazyVGrid(columns:[GridItem(.adaptive(minimum:48))]) {ForEach(["⭐","✨","🔥","❤️","💖","😂","😍","🥰","😎","🤩","😭","🥺","👍","👏","🙌","🎉","🎂","🎵","🎬","📸","🌸","🌈","☀️","🌙","⚡","💯","✅","❌","➡️","⬅️","⬆️","⬇️","💬","💭","🐶","🐱","🍜","☕","✈️","🏝️"],id:\.self) {s in Button(s) {model.addText("Sticker",content:s)}.font(.largeTitle).padding(8)}}
        case "Voiceover":
            Text(model.recording ? "Recording… \(formatTime(Int64(model.recordingElapsed*1_000_000)))":"Records from the playhead while the video plays.").foregroundStyle(Palette.dim)
            Button(model.recording ? "Stop recording":"Record",systemImage:model.recording ? "stop.circle.fill":"mic.circle.fill") {model.toggleRecording()}.buttonStyle(.borderedProminent).tint(model.recording ? .red:Palette.accent)
            ProgressView(value:model.recordingLevel).tint(Palette.teal)
        default: Text("Select a clip to edit it.").foregroundStyle(Palette.dim)
        }
    }
    @ViewBuilder private var audioFades:some View {
        ValueSlider(title:"Fade in (seconds)",value:Binding(get:{Double(model.clip?.fadeInUs ?? 0)/1_000_000},set:{v in model.edit {$0.fadeInUs = Int64(v*1_000_000)}}),range:0...max(0.1,min(10,Double(model.clip?.durationUs ?? 0)/2_000_000)))
        ValueSlider(title:"Fade out (seconds)",value:Binding(get:{Double(model.clip?.fadeOutUs ?? 0)/1_000_000},set:{v in model.edit {$0.fadeOutUs = Int64(v*1_000_000)}}),range:0...max(0.1,min(10,Double(model.clip?.durationUs ?? 0)/2_000_000)))
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
struct ShareSheet: UIViewControllerRepresentable {
    let url:URL
    func makeUIViewController(context:Context) -> UIActivityViewController {UIActivityViewController(activityItems:[url],applicationActivities:nil)}
    func updateUIViewController(_ controller:UIActivityViewController,context:Context) {}
}
struct ExportView: View {
    let project:Project
    @ObservedObject var exporter:Exporter
    @Environment(\.dismiss) var dismiss
    @ViewState<ExportSettings> private var settings = ExportSettings()
    @ViewState<Bool> private var share = false
    @ViewState<Bool> private var saved = false
    var body: some View {NavigationStack {Form {
        if exporter.running {ProgressView(value:exporter.progress); Text("Exporting… \(Int(exporter.progress*100))%"); Button("Cancel",role:.destructive) {exporter.cancel()}}
        else if let url = exporter.url {
            Text("Export complete").font(.headline)
            Text(url.lastPathComponent).font(.caption)
            Button("Share") {share = true}
            Button(saved ? "Saved":"Save video") {Task {await exporter.saveToPhotos(); saved = exporter.error == nil}}.disabled(saved)
        } else {
            Picker("Resolution",selection:$settings.tier) {ForEach(Resolution.allCases.reversed(),id:\.self) {Text($0.label).tag($0)}}
            Picker("Frame rate",selection:$settings.fps) {ForEach([60,50,30,25,24],id:\.self) {Text("\($0) fps").tag($0)}}
            Toggle("HEVC",isOn:$settings.hevc)
            Picker("Quality",selection:$settings.quality) {ForEach(["High","Medium","Low"],id:\.self) {Text($0)}}
            Button("Export") {exporter.start(project,settings:settings)}.buttonStyle(.borderedProminent)
        }
        if let error = exporter.error {Text(error).foregroundStyle(.red)}
    }.navigationTitle("Export").toolbar {Button("Done") {dismiss()}}}
        .onAppear {settings.tier = project.canvas.tier; settings.fps = project.canvas.fps}
        .sheet(isPresented:$share) {if let url = exporter.url {ShareSheet(url:url)}}
        .interactiveDismissDisabled(exporter.running)
    }
}
