import SwiftUI

struct DesktopWorkspace<Preview: View, Transport: View>: View {
    @ObservedObject var model: EditorModel
    @ObservedObject var timeline: TimelineDisplay
    @Binding var panel: String
    var onImport: () -> Void
    var onReplace: () -> Void
    var onSubtitles: () -> Void
    var onExport: () -> Void
    var onClose: () -> Void
    var onRename: () -> Void
    @ViewBuilder var preview: () -> Preview
    @ViewBuilder var transport: () -> Transport
    @AppStorage("desktop.showBrowser") private var showBrowser = true
    @AppStorage("desktop.showInspector") private var showInspector = true
    @AppStorage("desktop.browserWidth") private var browserWidth = 240.0
    @AppStorage("desktop.inspectorWidth") private var inspectorWidth = 300.0
    @AppStorage("desktop.timelineHeight") private var timelineHeight = 270.0
    @ViewState<Double> private var availableWidth = 1000

    private var panels: [String] {
        guard let clip = model.clip else { return ["Ratio", "Layout", "Stickers", "Voiceover"] }
        if clip.text != nil { return ["Text", "Font", "Style", "Animation", "Position", "Ratio"] }
        if clip.audioOnly || model.project.asset(clip.assetID)?.type == .audio { return ["Volume", "Speed", "Ratio"] }
        var choices = ["Position", "Crop", "Adjust", "Filters", "Layout"]
        if model.project.asset(clip.assetID)?.type == .video { choices += ["Speed", "Volume"] }
        if model.project.track(clip.id)?.kind == .main { choices.append("Transition") }
        return choices + ["Ratio"]
    }

    var body: some View {
        GeometryReader { viewport in
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
                WorkspaceDivider(value: $timelineHeight, range: 160...max(160, Double(viewport.size.height)*0.6), horizontal: true, reversed: true)
                VStack(spacing: 0) {
                    timelineToolbar
                    TimelineView(model: model, display: timeline, desktop: true)
                }.frame(height: clamp(timelineHeight, 160, max(160, Double(viewport.size.height)*0.6)))
            }
            .onAppear { availableWidth = viewport.size.width; timeline.rowHeight = 68; panel = model.clip == nil ? "Ratio" : panels[0] }
            .onChange(of: viewport.size.width) { _, width in availableWidth = width }
        }
        .background(Palette.bg)
        .focusedSceneValue(\.desktopEditor, commandActions)
        .onChange(of: model.selected) { _, _ in
            if !panels.contains(panel) || model.clip != nil { panel = panels[0] }
        }
        .accessibilityIdentifier("desktop.workspace")
    }

    private var toolbar: some View {
        HStack(spacing: 12) {
            Button(action: onClose) { Image(systemName: "chevron.left") }.help("Back to projects")
            Button(action: onRename) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(model.project.name).font(.headline).lineLimit(1)
                    Text("\(model.project.canvas.aspect.rawValue) · \(model.project.canvas.fps) fps").font(.caption2).foregroundStyle(Palette.dim)
                }
            }.buttonStyle(.plain).help("Rename project")
            Spacer()
            Button(action: onImport) { Label("Import", systemImage: "square.and.arrow.down") }.disabled(model.busy).help("Import media (⌘I)")
            Divider().frame(height: 20)
            Button { model.undo() } label: { Image(systemName: "arrow.uturn.backward") }.disabled(!model.canUndo).help("Undo (⌘Z)")
            Button { model.redo() } label: { Image(systemName: "arrow.uturn.forward") }.disabled(!model.canRedo).help("Redo (⇧⌘Z)")
            Divider().frame(height: 20)
            Button { model.split() } label: { Label("Split", systemImage: "scissors") }.disabled(!model.canEditSelection).help("Split at playhead (⌘B)")
            Button { model.moveSelectionToLayer() } label: { Label("To new layer", systemImage: "square.3.layers.3d") }
                .disabled(!model.canEditSelection || model.clip.map { model.project.track($0.id)?.kind != .main } != false)
            Menu {
                Button("Duplicate") {model.duplicateSelected()}.disabled(!model.canEditSelection)
                Button("Delete",role:.destructive) {model.delete()}.disabled(!model.canEditSelection)
                Button("Replace media…",action:onReplace).disabled(!model.canEditSelection || model.clip?.assetID == nil)
                Divider()
                Button("Keyframe") {if let id = model.selected {model.change {$0.toggleKeyframe(id,at:model.playhead)}}}.disabled(!model.canEditSelection)
                Button("Freeze frame") {model.freeze()}.disabled(model.project.asset(model.clip?.assetID)?.type != .video)
                Button("Extract audio") {model.extractAudio()}.disabled(model.project.asset(model.clip?.assetID)?.hasAudio != true)
                Button("Save audio…") {model.saveAudio()}.disabled(model.project.asset(model.clip?.assetID)?.hasAudio != true)
                Button("To main track") {if let id = model.selected {model.change {$0.move(id,to:"main",at:model.playhead)}}}
                    .disabled(!model.canEditSelection || model.selected.flatMap {model.project.track($0)?.kind} != .overlay)
            } label: {Image(systemName:"ellipsis.circle")}.help("Clip actions")
            Menu {
                Button("Add text") { model.addText("Title"); panel = "Text"; showInspector = true }
                Button("Add subtitle") { model.addText("Subtitle"); panel = "Text"; showInspector = true }
                Button("Import SRT/LRC…", action: onSubtitles)
                Button("Stickers") { model.selected = nil; panel = "Stickers"; showInspector = true }
                Button("Voiceover") { panel = "Voiceover"; showInspector = true }
            } label: { Image(systemName: "plus") }.help("Add text, stickers or voiceover")
            Button { showBrowser.toggle() } label: { Image(systemName: "sidebar.left") }.help("Toggle media browser")
            Button { showInspector.toggle() } label: { Image(systemName: "sidebar.right") }.help("Toggle inspector")
            Button("Export", action: onExport).buttonStyle(.borderedProminent).disabled(model.project.durationUs == 0)
        }.controlSize(.small).padding(.horizontal, 12).padding(.vertical, 10).background(Palette.surface)
    }

    private var inspector: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 8) {
                Text(model.clip?.text?.text ?? model.project.asset(model.clip?.assetID)?.name ?? "Project settings")
                    .font(.caption.bold()).lineLimit(2)
                Picker("Inspector", selection: $panel) {
                    ForEach(panels.contains(panel) ? panels : panels + [panel], id: \.self) { Text($0).tag($0) }
                }.pickerStyle(.menu).labelsHidden().frame(maxWidth: .infinity, alignment: .leading)
            }.padding(12)
            Divider()
            InspectorView(model: model, panel: panel).id(panel)
                .disabled(model.selected.map { model.project.track($0)?.locked == true } == true && panel != "Ratio")
        }.background(Palette.surface).accessibilityIdentifier("desktop.inspector")
    }

    private var timelineToolbar: some View {
        HStack(spacing: 12) {
            Text("Timeline").font(.caption.bold())
            Text("\(model.project.tracks.count) tracks").font(.caption2).foregroundStyle(Palette.dim)
            Divider().frame(height: 16)
            Button { model.selected = nil; model.seek(model.project.adjacentCut(to: model.playhead, forward: false)) } label: { Image(systemName: "backward.end") }.help("Previous cut")
            Button { model.selected = nil; model.seek(model.project.adjacentCut(to: model.playhead, forward: true)) } label: { Image(systemName: "forward.end") }.help("Next cut")
            Toggle(isOn: $timeline.snapping) { Label("Snap", systemImage: "align.horizontal.left") }.toggleStyle(.button).controlSize(.small)
            Spacer()
            Text("Track height").font(.caption2).foregroundStyle(Palette.dim)
            Slider(value: $timeline.rowHeight, in: 44...120).frame(width: 70).accessibilityLabel("Track height")
            Button { timeline.zoom(1/1.3) } label: { Image(systemName: "minus.magnifyingglass") }.help("Zoom out (⌘−)")
            Slider(value: Binding(get:{log2(timeline.pointsPerSecond)},set:{timeline.pointsPerSecond = pow(2,$0)}), in: log2(0.1)...log2(600)).frame(width: 100).accessibilityLabel("Timeline zoom")
            Button { timeline.zoom(1.3) } label: { Image(systemName: "plus.magnifyingglass") }.help("Zoom in (⌘+)")
            Button("Fit") { timeline.fit(duration: model.project.durationUs, width: availableWidth) }.help("Fit project to timeline (⇧Z)")
        }.buttonStyle(.borderless).padding(.horizontal, 12).frame(height: 38).background(Palette.surface)
    }

    private var commandActions: DesktopEditorActions {
        DesktopEditorActions(model: model, importMedia: onImport, replaceMedia: onReplace, importSubtitles: onSubtitles, export: onExport,
                             toggleBrowser: { showBrowser.toggle() }, toggleInspector: { showInspector.toggle() },
                             resetLayout: { browserWidth = 240; inspectorWidth = 300; timelineHeight = 270; showBrowser = true; showInspector = true; timeline.pointsPerSecond = 70; timeline.rowHeight = 68; timeline.snapping = true },
                             zoom: { timeline.zoom($0) }, fit: { timeline.fit(duration: model.project.durationUs, width: availableWidth) })
    }
}

struct WorkspaceDivider: View {
    @Binding var value: Double
    let range: ClosedRange<Double>
    var horizontal = false
    var reversed = false
    @ViewState<Double?> private var start: Double?
    @ViewState<Bool> private var hovered = false
    var body: some View {
        Rectangle().fill(hovered ? Palette.accent.opacity(0.6) : Palette.surface2)
            .frame(width: horizontal ? nil : 5, height: horizontal ? 5 : nil)
            .contentShape(Rectangle())
            .onHover { hovered = $0 }
            .gesture(DragGesture(minimumDistance: 0).onChanged { drag in
                if start == nil { start = value }
                let delta = horizontal ? drag.translation.height : drag.translation.width
                value = clamp((start ?? value) + delta * (reversed ? -1 : 1), range.lowerBound, range.upperBound)
            }.onEnded { _ in start = nil })
            .accessibilityLabel(horizontal ? "Resize timeline" : "Resize panel")
            .accessibilityAdjustableAction { direction in value = clamp(value + (direction == .increment ? 20 : -20), range.lowerBound, range.upperBound) }
            .help("Drag to resize")
    }
}
