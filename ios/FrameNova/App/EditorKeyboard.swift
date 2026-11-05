import SwiftUI
import UIKit

struct EditorKeyboard: ViewModifier {
    @ObservedObject var model: EditorModel
    @EditorFocus<Bool> private var focused
    @ViewState<PlaybackKeyRepeat> private var repeatSeek = PlaybackKeyRepeat()

    func body(content: Content) -> some View {
        content
            .focusable().focused($focused).focusEffectDisabled()
            .background { WorkspaceKeyboardFocus { focused = true } }
            .onKeyPress(.space, phases: [.down, .repeat]) { press in
                guard EditorKeyboardFocus.textInput == nil else {return .ignored}
                if press.phase == .down {model.play()}
                return .handled
            }
            .onKeyPress(keys: [.delete, .deleteForward], phases: [.down, .repeat]) { _ in
                guard EditorKeyboardFocus.textInput == nil else {return .ignored}
                model.delete();return .handled
            }
            .onKeyPress(keys: [.leftArrow, .rightArrow], phases: [.down, .repeat]) { press in
                guard EditorKeyboardFocus.textInput == nil else {return .ignored}
                let forward = press.key == .rightArrow
                if press.modifiers.contains(.command) {model.seek(forward ? model.project.durationUs : 0)}
                else if press.modifiers.contains(.option) {model.seek(model.project.adjacentCut(to:model.playhead,forward:forward))}
                else {
                    let frames = repeatSeek.frames(direction:forward ? 1 : -1,repeating:press.phase == .repeat,time:ProcessInfo.processInfo.systemUptime)
                    model.seek(model.playhead+Int64(frames * (press.modifiers.contains(.shift) ? 10 : 1))*1_000_000/Int64(max(1,model.project.canvas.fps)),precise:false)
                }
                return .handled
            }
            .onKeyPress(keys: [.leftArrow, .rightArrow], phases: .up) { _ in
                guard EditorKeyboardFocus.textInput == nil else {return .ignored}
                model.seek(model.playhead);return .handled
            }
            .onKeyPress(.escape) {
                guard EditorKeyboardFocus.textInput == nil else {return .ignored}
                model.selected = nil;return .handled
            }
    }
}

/// Observes pointer and touch starts without delaying selection or consuming gestures.
private struct WorkspaceKeyboardFocus: UIViewRepresentable {
    var activate: () -> Void
    func makeUIView(context: Context) -> WorkspaceFocusView {WorkspaceFocusView()}
    func updateUIView(_ view: WorkspaceFocusView, context: Context) {view.activate = activate}
    static func dismantleUIView(_ view: WorkspaceFocusView, coordinator: ()) {view.detach()}
}

private final class WorkspaceFocusView: UIView, UIGestureRecognizerDelegate {
    var activate: (() -> Void)?
    private weak var attachedWindow: UIWindow?
    private lazy var observer: UITapGestureRecognizer = {
        let recognizer = UITapGestureRecognizer()
        recognizer.delegate = self
        recognizer.cancelsTouchesInView = false
        recognizer.delaysTouchesBegan = false
        recognizer.delaysTouchesEnded = false
        return recognizer
    }()
    override func didMoveToWindow() {
        super.didMoveToWindow();detach();attachedWindow = window
        window?.addGestureRecognizer(observer)
    }
    func detach() {attachedWindow?.removeGestureRecognizer(observer);attachedWindow = nil}
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        guard bounds.contains(touch.location(in:self)), window?.rootViewController?.presentedViewController == nil else {return false}
        var candidate = touch.view
        while let view = candidate {
            if view is UITextInput {return false}
            candidate = view.superview
        }
        window?.endEditing(true)
        activate?()
        return false
    }
}
