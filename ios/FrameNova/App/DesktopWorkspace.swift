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
                            Text("Preview").font(.caption.bold()).foregroundStyle(Palette.dim)
                            Spacer()
                            Text("\(model.project.canvas.size.width) × \(model.project.canvas.size.height)").font(.caption2.monospacedDigit()).foregroundStyle(Palette.dim)
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
                        model.selected = nil;model.selectedGap = nil;panel = "Cover";showInspector = true
                    })
                }.frame(height: clamp(timelineHeight, 160, timelineLimit))
            }
            .onAppear {
                if timelineHeightDefaultVersion == 0 {
                    if timelineHeight == 270 {timelineHeight = 540}
                    timelineHeightDefaultVersion = 1
                }
                availableWidth = viewport.size.width; timeline.rowHeight = 68; panel = model.clip == nil ? "Ratio" : panels[0]
            }
            .onChange(of: viewport.size.width) { _, width in availableWidth = width }
        }
        .overlayPreferenceValue(WorkspacePointerHintKey.self) {WorkspacePointerHintOverlay(hint:$0)}
        .background(Palette.bg)
        .focusedSceneValue(\.desktopEditor, commandActions)
        .onChange(of:inspectorRequest) {_,_ in showInspector = true}
        .onChange(of:panel) {_,value in if value == "Text" {showInspector = true}}
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
                Text(model.selectedIDs.count>1 ? String(localized: "\(model.selectedIDs.count) clips selected"):model.clip?.text?.text ?? model.project.asset(model.clip?.assetID)?.name ?? loc("Project settings"))
                    .font(.caption.bold()).lineLimit(2)
                Picker("Inspector", selection: $panel) {
                    ForEach(panels.contains(panel) ? panels : panels + [panel], id: \.self) { Text(loc($0)).tag($0) }
                }.pickerStyle(.menu).labelsHidden().frame(maxWidth: .infinity, alignment: .leading).disabled(model.selectedIDs.count>1)
            }.padding(12)
            Divider()
            if model.selectedIDs.count>1 {
                Text("Command-click to add or remove clips. Use Delete, Duplicate or To new layer for the selected clips.")
                    .font(.caption).foregroundStyle(Palette.dim).padding(12)
                Spacer()
            } else {InspectorView(model: model, panel: panel).id(panel)
                .disabled(model.selected.map { model.project.track($0)?.locked == true } == true && panel != "Ratio" && panel != "Cover")
            }
        }.background(Palette.surface).accessibilityIdentifier("desktop.inspector")
    }

    private var timelineToolbar: some View {
        HStack(spacing:8) {
            Text("Timeline").font(.caption.bold())
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
                if start == nil { start = value }
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
