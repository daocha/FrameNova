import SwiftUI

@MainActor final class DesktopPointerState:ObservableObject {
    var command = false
}

#if targetEnvironment(macCatalyst)
import UIKit

struct DesktopPointerModifiers:UIViewRepresentable {
    let state:DesktopPointerState
    func makeUIView(context:Context)->PointerModifierView {PointerModifierView()}
    func updateUIView(_ view:PointerModifierView,context:Context) {view.onCommand = {state.command = $0}}
    static func dismantleUIView(_ view:PointerModifierView,coordinator:()) {view.detach()}
}

final class PointerModifierView:UIView,UIGestureRecognizerDelegate {
    var onCommand:((Bool)->Void)?
    private weak var attachedWindow:UIWindow?
    private lazy var observer:UITapGestureRecognizer = {
        let recognizer = UITapGestureRecognizer()
        recognizer.delegate = self
        recognizer.cancelsTouchesInView = false
        recognizer.delaysTouchesBegan = false
        recognizer.delaysTouchesEnded = false
        return recognizer
    }()
    override func didMoveToWindow() {
        super.didMoveToWindow();detach();attachedWindow = window;window?.addGestureRecognizer(observer)
    }
    func detach() {attachedWindow?.removeGestureRecognizer(observer);attachedWindow = nil}
    func gestureRecognizer(_ gestureRecognizer:UIGestureRecognizer,shouldReceive event:UIEvent)->Bool {
        onCommand?(event.modifierFlags.contains(.command))
        return false
    }
}
#endif
