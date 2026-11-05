#if targetEnvironment(macCatalyst)
import SwiftUI
import UIKit

/// Routes modified wheel and trackpad scrolling before the timeline's scroll views consume it.
struct TimelineScrollZoom:UIViewRepresentable {
    var onZoom:(Double)->Void
    func makeUIView(context:Context)->ScrollZoomView {ScrollZoomView()}
    func updateUIView(_ view:ScrollZoomView,context:Context) {view.onZoom = onZoom}
    static func dismantleUIView(_ view:ScrollZoomView,coordinator:()) {view.detach()}
}

final class ScrollZoomView:UIView,UIGestureRecognizerDelegate {
    var onZoom:((Double)->Void)?
    private weak var attachedWindow:UIWindow?
    private var linkedScrollViews:Set<ObjectIdentifier> = []
    private var linkedArea:CGRect?
    private lazy var scroll:UIPanGestureRecognizer = {
        let recognizer = UIPanGestureRecognizer(target:self,action:#selector(scrolled(_:)))
        recognizer.allowedScrollTypesMask = .all
        recognizer.allowedTouchTypes = []
        recognizer.delegate = self
        return recognizer
    }()
    override func didMoveToWindow() {
        super.didMoveToWindow()
        detach()
        attachedWindow = window
        window?.addGestureRecognizer(scroll)
        setNeedsLayout()
    }
    func detach() {
        attachedWindow?.removeGestureRecognizer(scroll)
        attachedWindow = nil;linkedScrollViews.removeAll();linkedArea = nil
    }
    override func layoutSubviews() {
        super.layoutSubviews()
        guard let window = attachedWindow else {return}
        let area = convert(bounds,to:window)
        guard linkedArea != area else {return}
        func link(_ view:UIView) {
            guard view === window || view.convert(view.bounds,to:window).intersects(area) else {return}
            if let view = view as? UIScrollView,view.convert(view.bounds,to:window).intersects(area),
               linkedScrollViews.insert(ObjectIdentifier(view)).inserted {
                view.panGestureRecognizer.require(toFail:scroll)
            }
            for child in view.subviews {link(child)}
        }
        link(window)
        if !linkedScrollViews.isEmpty {linkedArea = area}
    }
    func gestureRecognizer(_ gestureRecognizer:UIGestureRecognizer,shouldReceive event:UIEvent)->Bool {
        event.modifierFlags.contains(.command)
    }
    override func gestureRecognizerShouldBegin(_ gestureRecognizer:UIGestureRecognizer)->Bool {
        gestureRecognizer.modifierFlags.contains(.command) && bounds.contains(gestureRecognizer.location(in:self))
    }
    @objc private func scrolled(_ recognizer:UIPanGestureRecognizer) {
        let translation = recognizer.translation(in:self)
        recognizer.setTranslation(.zero,in:self)
        let delta = abs(translation.y) >= abs(translation.x) ? translation.y:translation.x
        if delta != 0 {onZoom?(exp(clamp(Double(delta)*0.01,-0.4,0.4)))}
    }
}
#endif
