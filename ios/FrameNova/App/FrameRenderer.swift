import CoreImage
import UIKit

extension UIColor {
    convenience init(argb: UInt32) { self.init(red:CGFloat((argb>>16)&255)/255,green:CGFloat((argb>>8)&255)/255,blue:CGFloat(argb&255)/255,alpha:CGFloat((argb>>24)&255)/255) }
}
final class FrameRenderer {
    let context = CIContext(options:[.cacheIntermediates:false])
    private var images: [String:CIImage] = [:]
    private var cubes: [String:Data] = [:]
    func render(_ instruction: FrameInstruction, at time: Int64, frame: (Int32) -> CIImage?) throws -> CIImage {
        let p = instruction.project, size = p.canvas.size, bounds = CGRect(x:0,y:0,width:size.width,height:size.height)
        var result = CIImage(color:CIColor(color:UIColor(argb:p.canvas.background))).cropped(to:bounds)
        for track in p.tracks.reversed() where !track.hidden && track.kind != .audio {
            let clips = track.clips.filter { $0.contains(time) }
            for clip in clips {
                guard !clip.audioOnly else { continue }
                var image: CIImage
                if let text = clip.text { image = textImage(text,clip:clip,time:time,canvas:bounds.size) }
                else if let media = p.asset(clip.assetID) {
                    if media.type == .image {
                        if let cached = images[media.path] { image = cached }
                        else {
                            guard let loaded = CIImage(contentsOf:ProjectStore.mediaURL(media.path),options:[.applyOrientationProperty:true]) else { throw MediaError.missing(media.name) }
                            images[media.path] = loaded; image = loaded
                        }
                    } else if let source = instruction.sources[clip.id], let loaded = frame(source) {
                        image = loaded.transformed(by:instruction.orientations[clip.id] ?? .identity)
                    } else { continue }
                } else { continue }
                image = image.transformed(by:CGAffineTransform(translationX:-image.extent.minX,y:-image.extent.minY))
                let extent = image.extent, c = clip.crop
                let crop = CGRect(x:extent.width*c.left,y:extent.height*c.bottom,width:extent.width*max(0.01,1-c.left-c.right),height:extent.height*max(0.01,1-c.top-c.bottom))
                image = image.cropped(to:crop).transformed(by:CGAffineTransform(translationX:-crop.minX,y:-crop.minY))
                image = grade(image,clip:clip)
                var transform = clip.transform(at:time)
                var opacity = transform.opacity
                let incoming = clip.transitionIn
                if let tr = incoming, time < clip.startUs+tr.durationUs {
                    let t = Double(time-clip.startUs)/Double(tr.durationUs)
                    transition(tr.type,t:t,incoming:true,transform:&transform,opacity:&opacity)
                    if tr.type == .dipBlack || tr.type == .dipWhite {
                        let color = tr.type == .dipWhite ? CIColor.white : CIColor.black
                        result = CIImage(color:color).cropped(to:bounds).applyingFilter("CIColorMatrix",parameters:["inputAVector":CIVector(x:0,y:0,z:0,w:1-t)]).composited(over:result)
                    }
                }
                if let next = track.clips.first(where: { $0.startUs > clip.startUs && $0.transitionIn != nil && $0.contains(time) }), let tr = next.transitionIn, time < next.startUs+tr.durationUs {
                    let t = Double(time-next.startUs)/Double(tr.durationUs)
                    if tr.type.rawValue.hasPrefix("Push") || tr.type == .zoomOut { transition(tr.type,t:t,incoming:false,transform:&transform,opacity:&opacity) }
                }
                if let text = clip.text {
                    let d = Double(max(1,text.animDurationUs))
                    let enter = clamp(Double(time-clip.startUs)/d,0,1), exit = clamp(Double(clip.endUs-time)/d,0,1)
                    animate(text.animIn,progress:enter,transform:&transform,opacity:&opacity)
                    animate(text.animOut,progress:exit,transform:&transform,opacity:&opacity)
                }
                if p.canvas.blurred && track.kind == .main {
                    let fill = max(bounds.width/image.extent.width,bounds.height/image.extent.height)
                    let bg = image.transformed(by:CGAffineTransform(scaleX:fill,y:fill))
                    result = bg.transformed(by:CGAffineTransform(translationX:(bounds.width-bg.extent.width)/2,y:(bounds.height-bg.extent.height)/2)).clampedToExtent().applyingFilter("CIGaussianBlur",parameters:["inputRadius":p.canvas.blur*50]).cropped(to:bounds).composited(over:result)
                }
                let fit = min(bounds.width/image.extent.width,bounds.height/image.extent.height)*transform.scale
                let sx = fit*(clip.flipH ? -1.0:1.0), sy = fit*(clip.flipV ? -1.0:1.0)
                image = image.transformed(by:CGAffineTransform(translationX:-image.extent.width/2,y:-image.extent.height/2))
                    .transformed(by:CGAffineTransform(scaleX:sx,y:sy))
                    .transformed(by:CGAffineTransform(rotationAngle:-transform.rotation * .pi/180))
                    .transformed(by:CGAffineTransform(translationX:transform.cx*bounds.width,y:(1-transform.cy)*bounds.height))
                    .applyingFilter("CIColorMatrix",parameters:["inputAVector":CIVector(x:0,y:0,z:0,w:opacity)])
                result = image.composited(over:result).cropped(to:bounds)
            }
        }
        return result
    }
    private func animate(_ animation: TextAnimation, progress: Double, transform: inout Transform, opacity: inout Double) {
        switch animation {
        case .none,.typewriter: break
        case .fade: opacity *= progress
        case .slideUp: transform.cy += (1-progress)*0.15; opacity *= progress
        case .slideDown: transform.cy -= (1-progress)*0.15; opacity *= progress
        case .pop: transform.scale *= max(0.01,progress*(1+0.2*sin(progress * .pi))); opacity *= progress
        case .zoom: transform.scale *= max(0.01,progress); opacity *= progress
        }
    }
    private func transition(_ type: TransitionType,t:Double,incoming:Bool,transform:inout Transform,opacity:inout Double) {
        let distance = incoming ? 1-t : -t
        switch type {
        case .fade: if incoming { opacity *= t }
        case .dipBlack,.dipWhite: if incoming { opacity *= max(0,2*t-1) }
        case .pushLeft,.slideLeft: transform.cx += distance
        case .pushRight,.slideRight: transform.cx -= distance
        case .pushUp,.slideUp: transform.cy += distance
        case .pushDown,.slideDown: transform.cy -= distance
        case .zoomIn: transform.scale *= 1+(1-t)*0.5; opacity *= t
        case .zoomOut: transform.scale *= incoming ? 0.5+t*0.5 : 1+t*0.5; if incoming { opacity *= t }
        }
    }
    private func grade(_ source: CIImage, clip: Clip) -> CIImage {
        let a = clip.adjust
        var image = source.applyingFilter("CIColorControls",parameters:["inputBrightness":a.brightness,"inputContrast":1+a.contrast,"inputSaturation":1+a.saturation])
        image = image.applyingFilter("CITemperatureAndTint",parameters:["inputNeutral":CIVector(x:6500,y:0),"inputTargetNeutral":CIVector(x:6500+a.warmth*2500,y:a.tint*100)])
            .applyingFilter("CIHueAdjust",parameters:["inputAngle":a.hue * .pi/180])
        if a.sharpen > 0 { image = image.applyingFilter("CISharpenLuminance",parameters:["inputSharpness":a.sharpen*2]) }
        if a.vignette > 0 { image = image.applyingFilter("CIVignette",parameters:["inputIntensity":a.vignette*2,"inputRadius":min(source.extent.width,source.extent.height)/2]) }
        if let setting = clip.filter {
            let key = setting.id+String(setting.intensity)
            let cube = cubes[key] ?? FilterCube.data(setting.id,intensity:setting.intensity)
            if cubes.count > 32 {cubes.removeAll()}; cubes[key] = cube
            image = image.applyingFilter("CIColorCube",parameters:["inputCubeDimension":16,"inputCubeData":cube])
        }
        return image
    }
    private func textImage(_ style: TextStyle,clip: Clip,time:Int64,canvas:CGSize) -> CIImage {
        let size = CGSize(width:canvas.width,height:canvas.height)
        let renderer = UIGraphicsImageRenderer(size:size,format:{ let f = UIGraphicsImageRendererFormat(); f.scale = 1; return f }())
        let uiImage = renderer.image { _ in
            var value = style.text
            if style.animIn == .typewriter { value = String(value.prefix(Int(Double(value.count)*clamp(Double(time-clip.startUs)/Double(max(1,style.animDurationUs)),0,1)))) }
            let fontSize = canvas.height*style.size
            var font = style.fontID == "system" ? UIFont.systemFont(ofSize:fontSize,weight:style.bold ? .bold:.regular) : UIFont(name:style.fontID,size:fontSize) ?? UIFont.systemFont(ofSize:fontSize)
            if style.italic, let descriptor = font.fontDescriptor.withSymbolicTraits([.traitItalic,style.bold ? .traitBold:[]]) { font = UIFont(descriptor:descriptor,size:fontSize) }
            let paragraph = NSMutableParagraphStyle(); paragraph.alignment = style.alignment == "Left" ? .left : style.alignment == "Right" ? .right:.center; paragraph.lineSpacing = fontSize*(style.lineSpacing-1)
            var attrs: [NSAttributedString.Key:Any] = [.font:font,.foregroundColor:UIColor(argb:style.color),.paragraphStyle:paragraph,.kern:style.letterSpacing*fontSize]
            if style.strokeWidth > 0 { attrs[.strokeColor] = UIColor(argb:style.strokeColor); attrs[.strokeWidth] = -style.strokeWidth*100 }
            if style.shadow { let shadow = NSShadow(); shadow.shadowColor = UIColor.black; shadow.shadowBlurRadius = fontSize*0.12; shadow.shadowOffset = CGSize(width:1,height:2); attrs[.shadow] = shadow }
            let attributed = NSAttributedString(string:value,attributes:attrs)
            let measured = attributed.boundingRect(with:CGSize(width:size.width*0.9,height:size.height),options:[.usesLineFragmentOrigin,.usesFontLeading],context:nil)
            let rect = CGRect(x:(size.width-measured.width)/2,y:(size.height-measured.height)/2,width:measured.width,height:measured.height)
            if style.backgroundColor != 0 { UIColor(argb:style.backgroundColor).setFill(); UIBezierPath(roundedRect:rect.insetBy(dx:-10,dy:-5),cornerRadius:6).fill() }
            attributed.draw(in:rect)
        }
        return CIImage(image:uiImage)!
    }
}
