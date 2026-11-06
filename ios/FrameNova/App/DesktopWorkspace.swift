import SwiftUI

struct DesktopWorkspace<Preview: View, Transport: View, Tools: View>: View {
    @ObservedObject var model: EditorModel
    @ObservedObject var timeline: TimelineDisplay
    @Binding var panel: String
    var onImport: () -> Void
    var onReplace: () -> Void
    var onSubtitles: () -> Void
    var onExport: () -> Void
    var onClose: () -> Void
    var onRename: () -> Void
    var inspectorRequest:Int
    @ViewBuilder var preview: () -> Preview
    @ViewBuilder var transport: () -> Transport
    @ViewBuilder var tools:()->Tools
    @AppStorage("desktop.showBrowser") private var showBrowser = true
    @AppStorage("desktop.showInspector") private var showInspector = true
    @AppStorage("desktop.browserWidth") private var browserWidth = 240.0
    @AppStorage("desktop.inspectorWidth") private var inspectorWidth = 300.0
    @AppStorage("desktop.timelineHeight") private var timelineHeight = 540.0
    @AppStorage("desktop.timelineHeightDefaultVersion") private var timelineHeightDefaultVersion = 0
    @ViewState<Double> private var availableWidth = 1000
    @ViewState<Bool> private var chooseCoverPhoto = false
    @ViewState<Bool> private var showCover = false

    private var panels: [String] {
        guard let clip = model.clip else { return ["Ratio", "Cover", "Layout", "Stickers", "Voiceover"] }
        if clip.text != nil { return ["Text", "Font", "Style", "Animation", "Position", "Ratio"] }
        if clip.audioOnly || model.project.asset(clip.assetID)?.type == .audio { return ["Volume", "Speed", "Ratio"] }
        var choices = ["Position", "Crop", "Adjust", "Filters", "Layout"]
        if model.project.asset(clip.assetID)?.type == .video { choices += ["Speed", "Volume"] }
        if model.project.track(clip.id)?.kind == .main { choices.append("Transition") }
        return choices + ["Ratio"]
    }

    var body: some View {
        GeometryReader { viewport in
            let timelineLimit = max(160,Double(viewport.size.height)-300)
            VStack(spacing: 0) {
                toolbar
                HStack(spacing: 0) {
                    if showBrowser {
                        DesktopMediaBrowser(model: model, onImport: onImport).frame(width: clamp(browserWidth, 190, 320))
                        WorkspaceDivider(value: $browserWidth, range: 190...320)
                    }
                    VStack(spacing: 0) {
                        HStack {
                            Text("Preview").font(.callout.bold()).foregroundStyle(Palette.dim)
                            Spacer()
                            Text("\(model.project.canvas.size.width) × \(model.project.canvas.size.height)").font(.subheadline.monospacedDigit()).foregroundStyle(Palette.dim)
                        }.padding(.horizontal, 16).padding(.top, 10)
                        preview().frame(maxWidth: .infinity, maxHeight: .infinity)
                        transport()
                    }.frame(maxWidth: .infinity, maxHeight: .infinity)
                    if showInspector {
                        WorkspaceDivider(value: $inspectorWidth, range: 260...360, reversed: true)
                        inspector.frame(width: clamp(inspectorWidth, 260, 360))
                    }
                }.frame(maxHeight: .infinity)
                WorkspaceDivider(value: $timelineHeight, range: 160...timelineLimit, horizontal: true, reversed: true)
                VStack(spacing: 0) {
                    timelineToolbar
                    TimelineView(model: model, display: timeline, desktop: true,onCover:{
                        model.selected = nil;model.selectedGap = nil;showCover = true
                        // An empty tile (the plus) goes straight to choosing a photo.
                        if model.project.asset(model.project.coverAssetID)?.type != .image {chooseCoverPhoto = true}
                    })
                }.frame(height: clamp(timelineHeight, 160, timelineLimit))
            }
            .onAppear {
                if timelineHeightDefaultVersion < 3 {
                    // Some builds stored "as tall as possible" (4000); go back to the normal default once.
                    if timelineHeight == 270 || timelineHeight == 4000 {timelineHeight = 540}
                    timelineHeightDefaultVersion = 3
                }
                availableWidth = viewport.size.width; timeline.rowHeight = 68; panel = model.clip == nil ? "Ratio" : panels[0]
            }
            .onChange(of: viewport.size.width) { _, width in availableWidth = width }
        }
        .overlayPreferenceValue(WorkspacePointerHintKey.self) {WorkspacePointerHintOverlay(hint:$0)}
        .background(Palette.bg)
        .focusedSceneValue(\.desktopEditor, commandActions)
        .onChange(of:inspectorRequest) {_,_ in showInspector = true}
        .onChange(of:panel) {_,value in
            if value == "Text" {showInspector = true}
            // The cover has its own dialog on the Mac instead of a side panel.
            if value == "Cover" {panel = panels.first {$0 != "Cover"} ?? "Ratio";showCover = true}
        }
        .overlay {
            // An in-window dialog: the system sheet did not pass clicks to its buttons in the editor on the Mac.
            if showCover {DesktopDialog(width:560,height:640) {CoverDialog(model:model,choosePhoto:$chooseCoverPhoto) {showCover = false}}}
        }
        .onChange(of: model.selected) { _, _ in
            if !panels.contains(panel) || model.clip != nil { panel = panels[0] }
        }
        .accessibilityIdentifier("desktop.workspace")
    }

    private var toolbar: some View {
        HStack(spacing: 12) {
            Button(action: onClose) { Image(systemName: "chevron.left") }.help("Back to projects")
            ProjectHeading(project:model.project,expanded:showInspector && panel == "Ratio",onRename:onRename,onFormat:{
                let close = showInspector && panel == "Ratio"
                model.selected = nil;model.selectedGap = nil;panel = "Ratio";showInspector = !close
            })
            Spacer()
            Button(action: onImport) { Label("Import", systemImage: "square.and.arrow.down") }.disabled(model.busy).help("Import media (⌘I)")
            Button { showBrowser.toggle() } label: { Image(systemName: "sidebar.left") }.help("Toggle media browser")
            Button { showInspector.toggle() } label: { Image(systemName: "sidebar.right") }.help("Toggle inspector")
            Button("Export", action: onExport).buttonStyle(.borderedProminent).disabled(model.project.durationUs == 0)
        }.controlSize(.small).padding(.horizontal, 12).padding(.vertical, 10).background(Palette.surface)
    }

    private var inspector: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 8) {
                Text(model.selectedIDs.count>1 ? localized("\(model.selectedIDs.count) clips selected"):model.clip?.text?.text ?? model.project.asset(model.clip?.assetID)?.name ?? loc("Project settings"))
                    .font(.system(size:16,weight:.bold)).lineLimit(2)
                Picker("Inspector", selection: $panel) {
                    ForEach(panels.contains(panel) ? panels : panels + [panel], id: \.self) { Text(loc($0)).tag($0) }
                }.pickerStyle(.menu).labelsHidden().frame(maxWidth: .infinity, alignment: .leading).disabled(model.selectedIDs.count>1)
            }.padding(12)
            Divider()
            if model.selectedIDs.count>1 {
                Text("Command-click to add or remove clips. Use Delete, Duplicate or To new layer for the selected clips.")
                    .font(.callout).foregroundStyle(Palette.dim).padding(12)
                Spacer()
            } else {InspectorView(model: model, panel: panel, choosePhoto: $chooseCoverPhoto).id(panel)
                .disabled(model.selected.map { model.project.track($0)?.locked == true } == true && panel != "Ratio" && panel != "Cover")
            }
        }.background(Palette.surface).accessibilityIdentifier("desktop.inspector")
    }

    private var timelineToolbar: some View {
        HStack(spacing:8) {
            Text("Timeline").font(.system(size:14,weight:.bold))
            Button {model.undo()} label:{Image(systemName:"arrow.uturn.backward")}.disabled(!model.canUndo).help("Undo (⌘Z)").accessibilityLabel("Undo")
            Button {model.redo()} label:{Image(systemName:"arrow.uturn.forward")}.disabled(!model.canRedo).help("Redo (⇧⌘Z)").accessibilityLabel("Redo")
            Divider().frame(height:18)
            ScrollView(.horizontal) {
                HStack(spacing:4) {tools()}.padding(.vertical,4)
                    .disabled(model.selected.map {model.project.track($0)?.locked == true} == true)
            }.accessibilityIdentifier("desktop.timelineTools")
            Divider().frame(height:18)
            Button {model.selected = nil;model.seek(model.project.adjacentCut(to:model.playhead,forward:false))} label:{Image(systemName:"backward.end")}.help("Previous cut")
            Button {model.selected = nil;model.seek(model.project.adjacentCut(to:model.playhead,forward:true))} label:{Image(systemName:"forward.end")}.help("Next cut")
            Toggle(isOn:$timeline.snapping) {Label("Snap",systemImage:"align.horizontal.left")}.toggleStyle(.button).controlSize(.small)
            Menu {
                Button("Compact tracks") {timeline.rowHeight = 44}
                Button("Standard tracks") {timeline.rowHeight = 68}
                Button("Large tracks") {timeline.rowHeight = 96}
            } label:{Image(systemName:"line.3.horizontal")}.help("Track height").accessibilityLabel("Track height")
            Button {timeline.zoom(1/1.3)} label:{Image(systemName:"minus.magnifyingglass")}.help("Zoom out (⌘−)")
            EditorSlider(value:Binding(get:{log2(timeline.pointsPerSecond)},set:{timeline.pointsPerSecond = pow(2,$0)}),range:log2(0.1)...log2(1600),label:loc("Timeline zoom")).frame(width:70)
            Button {timeline.zoom(1.3)} label:{Image(systemName:"plus.magnifyingglass")}.help("Zoom in (⌘+)")
            Button("Fit") {timeline.fit(duration:model.project.durationUs,width:availableWidth)}.help("Fit project to timeline (⇧Z)")
        }.buttonStyle(.borderless).padding(.horizontal,12).frame(height:44).background(Palette.surface)
    }

    private var commandActions: DesktopEditorActions {
        DesktopEditorActions(model: model, importMedia: onImport, replaceMedia: onReplace, importSubtitles: onSubtitles, export: onExport,
                             toggleBrowser: { showBrowser.toggle() }, toggleInspector: { showInspector.toggle() },
                             resetLayout: { browserWidth = 240; inspectorWidth = 300; timelineHeight = 540; showBrowser = true; showInspector = true; timeline.pointsPerSecond = 70; timeline.rowHeight = 68; timeline.snapping = true },
                             zoom: { timeline.zoom($0) }, fit: { timeline.fit(duration: model.project.durationUs, width: availableWidth) })
    }
}

/// The cover chooser as a dialog, opened from the cover tile in the main layer or the inspector menu.
struct CoverDialog: View {
    @ObservedObject var model: EditorModel
    var choosePhoto:Binding<Bool>? = nil
    /// Closes the dialog by clearing the state that presents it. `dismiss` is not used: in an in-window dialog it would
    /// close the whole editor.
    let onClose:()->Void
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Cover").font(.system(size:18,weight:.bold))
                Spacer()
                TextAction(title:loc("Done"),prominent:true) {onClose()}.keyboardShortcut(.defaultAction)
            }.padding(16)
            Divider()
            ScrollView {CoverPanel(model:model,choosePhoto:choosePhoto).padding(16)}
        }
        .frame(maxWidth:.infinity,maxHeight:.infinity)
        .background(Palette.surface)
        .accessibilityIdentifier("desktop.coverDialog")
    }
}

/// A dialog drawn inside the window over a dimmed backdrop, for the Mac, where the dialogs opened from the editor are not
/// presented as system sheets. The backdrop takes every click, so nothing behind the dialog reacts.
struct DesktopDialog<Content:View>:View {
    var width:CGFloat = 560
    var height:CGFloat = 640
    @ViewBuilder var content:()->Content
    var body:some View {
        GeometryReader {geo in
            ZStack {
                Color.black.opacity(0.5).ignoresSafeArea().contentShape(Rectangle()).onTapGesture {}
                content()
                    .frame(width:min(width,geo.size.width-48),height:min(height,geo.size.height-48))
                    .background(Palette.surface3,in:RoundedRectangle(cornerRadius:14))
                    .clipShape(RoundedRectangle(cornerRadius:14))
                    .shadow(color:.black.opacity(0.5),radius:24,y:8)
            }.frame(width:geo.size.width,height:geo.size.height)
        }
    }
}

/// The export dialog: a system sheet on iPhone and iPad, an in-window dialog on the Mac.
struct ExportPresentation:ViewModifier {
    @Binding var isPresented:Bool
    let project:Project
    let exporter:Exporter
    func body(content:Content)->some View {
        #if targetEnvironment(macCatalyst)
        content.overlay {
            if isPresented {DesktopDialog(width:560,height:680) {ExportView(project:project,exporter:exporter,onClose:{isPresented = false})}}
        }
        #else
        content.sheet(isPresented:$isPresented) {ExportView(project:project,exporter:exporter,onClose:{isPresented = false})}
        #endif
    }
}

struct WorkspaceDivider: View {
    @Binding var value: Double
    let range: ClosedRange<Double>
    var horizontal = false
    var reversed = false
    @ViewState<Double?> private var start: Double?
    @ViewState<CGPoint?> private var pointerLocation = nil
    var body: some View {
        Rectangle().fill((pointerLocation != nil || start != nil) ? Palette.accent.opacity(0.6) : Palette.surface2)
            .frame(width: horizontal ? nil : 5, height: horizontal ? 5 : nil)
            .contentShape(Rectangle())
            .onContinuousHover(coordinateSpace:.global) {phase in
                guard start == nil else {return}
                switch phase {case .active(let point):pointerLocation = point;case .ended:pointerLocation = nil}
            }
            .gesture(DragGesture(minimumDistance: 0,coordinateSpace:.global).onChanged { drag in
                if start == nil { start = clamp(value, range.lowerBound, range.upperBound) }
                pointerLocation = drag.location
                let delta = horizontal ? drag.translation.height : drag.translation.width
                value = clamp((start ?? value) + delta * (reversed ? -1 : 1), range.lowerBound, range.upperBound)
            }.onEnded { _ in start = nil;pointerLocation = nil })
            .preference(key:WorkspacePointerHintKey.self,value:pointerLocation.map {
                WorkspacePointerHint(location:$0,symbol:horizontal ? "arrow.up.and.down":"arrow.left.and.right")
            })
            .zIndex(100)
            .accessibilityLabel(horizontal ? loc("Resize timeline") : loc("Resize panel"))
            .accessibilityAdjustableAction { direction in value = clamp(value + (direction == .increment ? 20 : -20), range.lowerBound, range.upperBound) }
            .help("Drag to resize")
    }
}
