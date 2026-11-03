import SwiftUI
import AVFoundation
import CoreText

struct ValueSlider: View {
    var title:String
    @Binding var value:Double
    var range:ClosedRange<Double> = 0...1
    var body: some View {VStack(alignment:.leading,spacing:4) {HStack {Text(title); Spacer(); Text(value.formatted(.number.precision(.fractionLength(2)))).foregroundStyle(Palette.dim).monospacedDigit()}; Slider(value:$value,in:range)}.font(.caption)}
}
struct CanvasControls: View {
    @Binding var canvas:CanvasSettings
    var body: some View {Form {
        Picker("Ratio",selection:$canvas.aspect) {ForEach(Aspect.allCases,id:\.self) {Text($0.rawValue).tag($0)}}
        Picker("Resolution",selection:$canvas.tier) {ForEach(Resolution.allCases.reversed(),id:\.self) {Text($0.label).tag($0)}}
        Picker("Frame rate",selection:$canvas.fps) {ForEach([60,50,30,25,24],id:\.self) {Text("\($0) fps").tag($0)}}
        Section("Background") {Toggle("Blur",isOn:$canvas.blurred); if canvas.blurred {ValueSlider(title:"Blur",value:$canvas.blur)} else {ColorStrip(value:$canvas.background)}}
        Text("\(canvas.size.width) × \(canvas.size.height)").foregroundStyle(Palette.dim)
    }.scrollContentBackground(.hidden).background(Palette.surface)}
}
struct ColorStrip: View {
    @Binding var value:UInt32
    let colors:[UInt32] = [0x00000000,0xFF000000,0xFFFFFFFF,0xFF8B6CFF,0xFF2FD1C1,0xFFFF5A6A,0xFFFFCB66,0xFF4F7CFF,0xFFB0457E]
    var body: some View {ScrollView(.horizontal,showsIndicators:false) {HStack {ForEach(colors,id:\.self) {color in Button {value = color} label:{Circle().fill(Color(argb:color)).frame(width:28,height:28).overlay(Circle().stroke(value == color ? Color.white:Palette.dim,lineWidth:value == color ? 3:1)).overlay {if color == 0 {Image(systemName:"nosign").foregroundStyle(Palette.dim)}}.padding(3)}.buttonStyle(.plain)}}}}
}
struct InspectorView: View {
    @ObservedObject var model:EditorModel
    var panel:String
    func value(_ key:WritableKeyPath<Clip,Double>) -> Binding<Double> {Binding(get:{model.clip?[keyPath:key] ?? 0},set:{v in model.edit {$0[keyPath:key] = v}})}
    func adjust(_ key:WritableKeyPath<Adjust,Double>) -> Binding<Double> {Binding(get:{model.clip?.adjust[keyPath:key] ?? 0},set:{v in model.edit {$0.adjust[keyPath:key] = v}})}
    func transform(_ key:WritableKeyPath<Transform,Double>) -> Binding<Double> {
        Binding(get:{model.clip?.transform(at:model.playhead)[keyPath:key] ?? 0},set:{v in
            guard let clip = model.clip else {return}; var t = clip.transform(at:model.playhead); t[keyPath:key] = v
            let time = model.playhead,fps = model.project.canvas.fps; model.edit {$0.setTransform(t,at:time,fps:fps)}
        })
    }
    func text<T>(_ key:WritableKeyPath<TextStyle,T>,fallback:T) -> Binding<T> {Binding(get:{model.clip?.text?[keyPath:key] ?? fallback},set:{v in model.edit {$0.text?[keyPath:key] = v}})}
    var body: some View {
        VStack(alignment:.leading,spacing:0) {
            Text(panel).font(.headline).padding()
            Divider()
            if panel == "Ratio" {CanvasControls(canvas:Binding(get:{model.project.canvas},set:{v in model.change {$0.canvas = v}}))}
            else {ScrollView {VStack(alignment:.leading,spacing:18) {content}.padding()}}
        }.background(Palette.surface)
    }
    @ViewBuilder var content:some View {
        switch panel {
        case "Speed":
            ValueSlider(title:"Speed",value:Binding(get:{model.clip?.speed ?? 1},set:{v in if let id = model.selected {model.change {$0.setSpeed(id,speed:v)}}}),range:0.25...4)
            HStack {ForEach([0.25,0.5,1,2,4],id:\.self) {s in Button("\(s.formatted())×") {if let id = model.selected {model.change {$0.setSpeed(id,speed:s)}}}.buttonStyle(.bordered)}}
            Text("Pitch is preserved.").font(.caption).foregroundStyle(Palette.dim)
        case "Volume":
            ValueSlider(title:"Volume",value:value(\.volume),range:0...2)
            ValueSlider(title:"Fade in (seconds)",value:Binding(get:{Double(model.clip?.fadeInUs ?? 0)/1_000_000},set:{v in model.edit {$0.fadeInUs = Int64(v*1_000_000)}}),range:0...5)
            ValueSlider(title:"Fade out (seconds)",value:Binding(get:{Double(model.clip?.fadeOutUs ?? 0)/1_000_000},set:{v in model.edit {$0.fadeOutUs = Int64(v*1_000_000)}}),range:0...5)
        case "Position":
            ValueSlider(title:"X",value:transform(\.cx),range:-0.5...1.5); ValueSlider(title:"Y",value:transform(\.cy),range:-0.5...1.5)
            ValueSlider(title:"Scale",value:transform(\.scale),range:0.05...4); ValueSlider(title:"Rotation",value:transform(\.rotation),range:-180...180); ValueSlider(title:"Opacity",value:transform(\.opacity))
            HStack {Button("Fit") {model.edit {$0.transform = Transform(); $0.keyframes = []}}; Button("Rotate 90°") {model.edit {$0.transform.rotation += 90}}}.buttonStyle(.bordered)
            HStack {Button("Flip ↔") {model.edit {$0.flipH.toggle()}}; Button("Flip ↕") {model.edit {$0.flipV.toggle()}}}.buttonStyle(.bordered)
        case "Adjust":
            ValueSlider(title:"Brightness",value:adjust(\.brightness),range:-1...1); ValueSlider(title:"Contrast",value:adjust(\.contrast),range:-1...1)
            ValueSlider(title:"Saturation",value:adjust(\.saturation),range:-1...1); ValueSlider(title:"Warmth",value:adjust(\.warmth),range:-1...1); ValueSlider(title:"Tint",value:adjust(\.tint),range:-1...1)
            ValueSlider(title:"Hue",value:adjust(\.hue),range:-180...180); ValueSlider(title:"Vignette",value:adjust(\.vignette)); ValueSlider(title:"Sharpen",value:adjust(\.sharpen))
            Button("Reset") {model.edit {$0.adjust = Adjust()}}
            Button("Apply to all") {if let a = model.clip?.adjust {model.change {p in for t in p.tracks.indices {for c in p.tracks[t].clips.indices {p.tracks[t].clips[c].adjust = a}}}}}
        case "Filters":
            LazyVGrid(columns:[GridItem(.adaptive(minimum:80))],spacing:10) {
                Button("None") {model.edit {$0.filter = nil}}
                ForEach(FilterCube.ids,id:\.self) {id in Button(FilterCube.names[id] ?? id) {model.edit {$0.filter = FilterSetting(id:id)}}.buttonStyle(.bordered).tint(model.clip?.filter?.id == id ? Palette.teal:Palette.accent)}
            }
            ValueSlider(title:"Intensity",value:Binding(get:{model.clip?.filter?.intensity ?? 1},set:{v in model.edit {$0.filter?.intensity = v}}))
            Button("Apply to all") {let f = model.clip?.filter; model.change {p in for t in p.tracks.indices {for c in p.tracks[t].clips.indices {p.tracks[t].clips[c].filter = f}}}}
        case "Crop":
            cropSlider("Left",\.left); cropSlider("Right",\.right); cropSlider("Top",\.top); cropSlider("Bottom",\.bottom)
            Button("Reset") {model.edit {$0.crop = CropRect()}}
        case "Transition":
            Button("None") {if let id = model.selected {model.change {$0.setTransition(id,transition:nil)}}}
            ForEach(TransitionType.allCases,id:\.self) {type in Button(type.rawValue) {if let id = model.selected {model.change {$0.setTransition(id,transition:Transition(type:type))}}}.buttonStyle(.bordered)}
            ValueSlider(title:"Duration (seconds)",value:Binding(get:{Double(model.clip?.transitionIn?.durationUs ?? 500_000)/1_000_000},set:{v in if let id = model.selected, var tr = model.clip?.transitionIn {tr.durationUs = Int64(v*1_000_000); model.change {$0.setTransition(id,transition:tr)}}}),range:0.1...3)
        case "Layout":
            ForEach(LayoutPreset.all) {preset in Button(preset.label) {model.change {$0.layout(preset,at:model.playhead)}}.buttonStyle(.bordered)}
        case "Text":
            TextField("Text",text:text(\.text,fallback:"Text"),axis:.vertical).textFieldStyle(.roundedBorder)
            ValueSlider(title:"Size",value:text(\.size,fallback:0.07),range:0.02...0.4)
            Toggle("Bold",isOn:text(\.bold,fallback:true)); Toggle("Italic",isOn:text(\.italic,fallback:false)); Toggle("Shadow",isOn:text(\.shadow,fallback:true))
            Picker("Alignment",selection:text(\.alignment,fallback:"Center")) {ForEach(["Left","Center","Right"],id:\.self) {Text($0)}}
            Picker("Font",selection:text(\.fontID,fallback:"system")) {Text("System").tag("system"); ForEach(FontRegistry.names,id:\.self) {Text($0).tag($0)}}
            DownloadFontList {name in model.edit {$0.text?.fontID = name}}
            Text("Color").font(.caption); ColorStrip(value:text(\.color,fallback:0xFFFFFFFF))
            Text("Background").font(.caption); ColorStrip(value:text(\.backgroundColor,fallback:0))
            Text("Outline").font(.caption); ColorStrip(value:text(\.strokeColor,fallback:0xFF000000)); ValueSlider(title:"Outline width",value:text(\.strokeWidth,fallback:0),range:0...0.15)
            ValueSlider(title:"Letter spacing",value:text(\.letterSpacing,fallback:0),range:0...0.5); ValueSlider(title:"Line spacing",value:text(\.lineSpacing,fallback:1.1),range:0.8...2)
            Picker("In",selection:text(\.animIn,fallback:.none)) {ForEach(TextAnimation.allCases,id:\.self) {Text($0.rawValue).tag($0)}}
            Picker("Out",selection:text(\.animOut,fallback:.none)) {ForEach(TextAnimation.allCases,id:\.self) {Text($0.rawValue).tag($0)}}
        case "Stickers":
            LazyVGrid(columns:[GridItem(.adaptive(minimum:48))]) {ForEach(["😀","🥰","😎","🔥","❤️","✨","🎉","🌟","👍","💯","🎬","🎵","🌈","☀️","🌸","⭐️"],id:\.self) {s in Button(s) {model.addText("Sticker",content:s)}.font(.largeTitle).padding(8)}}
        case "Voiceover":
            Text("Recording starts at the playhead.").foregroundStyle(Palette.dim)
            Button(model.recording ? "Stop recording":"Record",systemImage:model.recording ? "stop.circle.fill":"mic.circle.fill") {model.toggleRecording()}.buttonStyle(.borderedProminent).tint(model.recording ? .red:Palette.accent)
        default: Text("Select a clip to edit it.").foregroundStyle(Palette.dim)
        }
    }
    func cropSlider(_ title:String,_ key:WritableKeyPath<CropRect,Double>) -> some View {ValueSlider(title:title,value:Binding(get:{model.clip?.crop[keyPath:key] ?? 0},set:{v in model.edit {$0.crop[keyPath:key] = v}}),range:0...0.49)}
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
