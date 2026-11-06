import SwiftUI

struct DesktopEditorActions {
    let model: EditorModel
    var importMedia: () -> Void
    var replaceMedia: () -> Void
    var importSubtitles: () -> Void
    var export: () -> Void
    var toggleBrowser: () -> Void
    var toggleInspector: () -> Void
    var resetLayout: () -> Void
    var zoom: (Double) -> Void
    var fit: () -> Void
}
private struct DesktopEditorKey: FocusedValueKey { typealias Value = DesktopEditorActions }
extension FocusedValues {
    var desktopEditor: DesktopEditorActions? {
        get { self[DesktopEditorKey.self] }
        set { self[DesktopEditorKey.self] = newValue }
    }
}

struct DesktopEditorCommands: Commands {
    @FocusedValue(\.desktopEditor) private var editor
    private var editingText: UIResponder? { EditorKeyboardFocus.textInput }
    private var canEdit: Bool { editor?.model.canEditSelection == true && editingText == nil }

    var body: some Commands {
        CommandGroup(replacing: .undoRedo) {
            Button("Undo") {
                if let input = editingText { input.undoManager?.undo() } else { editor?.model.undo() }
            }.keyboardShortcut("z").disabled(!(editingText?.undoManager?.canUndo ?? (editor?.model.canUndo == true)))
            Button("Redo") {
                if let input = editingText { input.undoManager?.redo() } else { editor?.model.redo() }
            }.keyboardShortcut("z", modifiers: [.command, .shift])
                .disabled(!(editingText?.undoManager?.canRedo ?? (editor?.model.canRedo == true)))
        }
        CommandGroup(after: .importExport) {
            Button("Import media…") { editor?.importMedia() }.keyboardShortcut("i").disabled(editor == nil || editor?.model.busy == true)
            Button("Import subtitles…") {editor?.importSubtitles()}.disabled(editor == nil)
            Button("Export project…") { editor?.export() }.keyboardShortcut("e").disabled(editor?.model.project.durationUs ?? 0 == 0)
        }
        CommandMenu("Clip") {
            Button("Split at playhead") { editor?.model.split() }.keyboardShortcut("b").disabled(!canEdit)
            Button("To new layer") { editor?.model.moveSelectionToLayer() }.keyboardShortcut("l", modifiers: [.command, .shift])
                .disabled(editor?.model.canDeleteSelection != true || editingText != nil)
            Divider()
            Button("Duplicate") { editor?.model.duplicateSelected() }.keyboardShortcut("d").disabled(editor?.model.canDeleteSelection != true || editingText != nil)
            Button("Delete") { editor?.model.delete() }.disabled(editor?.model.canDeleteSelection != true || editingText != nil)
            Button("Delete forward") { editor?.model.delete() }.disabled(editor?.model.canDeleteSelection != true || editingText != nil)
            Button("Select all clips") {editor?.model.selectAllClips()}.keyboardShortcut("a").disabled(editor == nil || editingText != nil)
            Button("Deselect clips") {editor?.model.selected = nil}.disabled(editor == nil || editingText != nil)
            Divider()
            Button("Trim start to playhead") { editor?.model.trimToPlayhead(start: true) }.keyboardShortcut("q", modifiers: .option).disabled(!canEdit)
            Button("Trim end to playhead") { editor?.model.trimToPlayhead(start: false) }.keyboardShortcut("w", modifiers: .option).disabled(!canEdit)
            Divider()
            Button("Replace media…") {editor?.replaceMedia()}.disabled(!canEdit || editor?.model.clip?.assetID == nil)
            Button("Freeze frame") {editor?.model.freeze()}.disabled(!canEdit || editor?.model.project.asset(editor?.model.clip?.assetID)?.type != .video)
            Button("Extract audio") {editor?.model.extractAudio()}.disabled(!canEdit || editor?.model.project.asset(editor?.model.clip?.assetID)?.hasAudio != true)
            Button("Save audio…") {editor?.model.saveAudio()}.disabled(!canEdit || editor?.model.project.asset(editor?.model.clip?.assetID)?.hasAudio != true)
            Button("Add text") { editor?.model.addText("Title") }.keyboardShortcut("t", modifiers: [.command, .shift]).disabled(editor == nil)
        }
        CommandMenu("Playback") {
            Button(editor?.model.playing == true ? loc("Pause") : loc("Play")) { editor?.model.play() }.disabled(editor == nil || editingText != nil)
            Button("Seek backward") {editor?.model.seekWithKeyboard(-1)}.keyboardShortcut(.leftArrow,modifiers:[]).disabled(editor == nil || editingText != nil)
            Button("Seek forward") {editor?.model.seekWithKeyboard(1)}.keyboardShortcut(.rightArrow,modifiers:[]).disabled(editor == nil || editingText != nil)
            Button("Seek backward faster") {editor?.model.seekWithKeyboard(-1,largerStep:true)}.keyboardShortcut(.leftArrow,modifiers:.shift).disabled(editor == nil || editingText != nil)
            Button("Seek forward faster") {editor?.model.seekWithKeyboard(1,largerStep:true)}.keyboardShortcut(.rightArrow,modifiers:.shift).disabled(editor == nil || editingText != nil)
            Button("Previous frame") { editor?.model.stepFrames(-1) }.disabled(editor == nil || editingText != nil)
            Button("Next frame") { editor?.model.stepFrames(1) }.disabled(editor == nil || editingText != nil)
            Button("Previous ten frames") { editor?.model.stepFrames(-10) }.disabled(editor == nil || editingText != nil)
            Button("Next ten frames") { editor?.model.stepFrames(10) }.disabled(editor == nil || editingText != nil)
            Divider()
            Button("Previous cut") { if let model = editor?.model { model.seek(model.project.adjacentCut(to: model.playhead, forward: false)) } }.disabled(editor == nil || editingText != nil)
            Button("Next cut") { if let model = editor?.model { model.seek(model.project.adjacentCut(to: model.playhead, forward: true)) } }.disabled(editor == nil || editingText != nil)
            Button("Start of project") {editor?.model.seek(0)}.disabled(editor == nil || editingText != nil)
            Button("End of project") {if let model = editor?.model {model.seek(model.project.durationUs)}}.disabled(editor == nil || editingText != nil)
        }
        CommandMenu("Workspace") {
            Button("Toggle media browser") { editor?.toggleBrowser() }.keyboardShortcut("1", modifiers: [.command, .option]).disabled(editor == nil)
            Button("Toggle inspector") { editor?.toggleInspector() }.keyboardShortcut("2", modifiers: [.command, .option]).disabled(editor == nil)
            Divider()
            Button("Zoom in") { editor?.zoom(1.3) }.keyboardShortcut("=").disabled(editor == nil)
            Button("Zoom out") { editor?.zoom(1/1.3) }.keyboardShortcut("-").disabled(editor == nil)
            Button("Fit timeline") { editor?.fit() }.keyboardShortcut("z", modifiers: .shift).disabled(editor == nil || editingText != nil)
            Divider()
            Button("Reset workspace") { editor?.resetLayout() }.disabled(editor == nil)
        }
    }
}

@MainActor enum EditorKeyboardFocus {
    static weak var responder: UIResponder?
    static var textInput: UIResponder? {
        responder = nil
        UIApplication.shared.sendAction(#selector(UIResponder.frameNovaCaptureResponder(_:)), to: nil, from: nil, for: nil)
        return responder is UITextInput ? responder : nil
    }
}
extension UIResponder {
    @objc func frameNovaCaptureResponder(_ sender: Any?) { EditorKeyboardFocus.responder = self }
}
