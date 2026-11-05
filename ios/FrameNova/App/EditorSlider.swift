import SwiftUI

struct EditorSlider:View {
    @Binding var value:Double
    var range:ClosedRange<Double> = 0...1
    var label = ""
    var onEditingChanged:(Bool)->Void = {_ in}
    var body:some View {
        #if targetEnvironment(macCatalyst)
        ClickPositionSlider(value:$value,range:range,label:label,onEditingChanged:onEditingChanged).frame(height:28)
        #else
        Slider(value:$value,in:range,onEditingChanged:onEditingChanged).accessibilityLabel(label)
        #endif
    }
}

#if targetEnvironment(macCatalyst)
import UIKit

private struct ClickPositionSlider:UIViewRepresentable {
    @Binding var value:Double
    let range:ClosedRange<Double>
    let label:String
    let onEditingChanged:(Bool)->Void
    func makeCoordinator()->Coordinator {Coordinator(self)}
    func makeUIView(context:Context)->JumpSlider {
        let slider = JumpSlider()
        slider.setContentHuggingPriority(.defaultLow,for:.horizontal)
        slider.addTarget(context.coordinator,action:#selector(Coordinator.changed(_:)),for:.valueChanged)
        return slider
    }
    func updateUIView(_ slider:JumpSlider,context:Context) {
        context.coordinator.parent = self
        slider.minimumValue = Float(range.lowerBound);slider.maximumValue = Float(range.upperBound)
        slider.value = Float(clamp(value,range.lowerBound,range.upperBound));slider.accessibilityLabel = label
        slider.onEditing = onEditingChanged
    }
    static func dismantleUIView(_ slider:JumpSlider,coordinator:Coordinator) {slider.finishEditing()}
    final class Coordinator:NSObject {
        var parent:ClickPositionSlider
        init(_ parent:ClickPositionSlider) {self.parent = parent}
        @objc func changed(_ slider:JumpSlider) {
            if !slider.interacting {parent.onEditingChanged(true)}
            parent.value = Double(slider.value)
            if !slider.interacting {parent.onEditingChanged(false)}
        }
    }
}

private final class JumpSlider:UISlider {
    var onEditing:((Bool)->Void)?
    private(set) var interacting = false
    override func beginTracking(_ touch:UITouch,with event:UIEvent?)->Bool {
        interacting = true;onEditing?(true)
        let track = trackRect(forBounds:bounds)
        let left = thumbRect(forBounds:bounds,trackRect:track,value:minimumValue).midX
        let right = thumbRect(forBounds:bounds,trackRect:track,value:maximumValue).midX
        let fraction = clamp((touch.location(in:self).x-left)/max(1,right-left),0,1)
        value = minimumValue+Float(fraction)*(maximumValue-minimumValue)
        sendActions(for:.valueChanged)
        let tracking = super.beginTracking(touch,with:event)
        if !tracking {finishEditing()}
        return tracking
    }
    override func endTracking(_ touch:UITouch?,with event:UIEvent?) {super.endTracking(touch,with:event);finishEditing()}
    override func cancelTracking(with event:UIEvent?) {super.cancelTracking(with:event);finishEditing()}
    func finishEditing() {if interacting {interacting = false;onEditing?(false)}}
}
#endif
