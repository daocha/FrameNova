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
        let p = instruction.project, bounds = CGRect(origin:.zero,size:instruction.renderSize)
        var result = CIImage(color:CIColor(color:UIColor(argb:p.canvas.background))).cropped(to:bounds)
        for track in p.tracks.reversed() where !track.hidden && track.kind != .audio {
            var clips = track.clips.filter { $0.contains(time) }
            if track.kind == .main {clips.sort {a,b in
                let i = track.clips.firstIndex(where:{$0.id == a.id}) ?? 0,j = track.clips.firstIndex(where:{$0.id == b.id}) ?? 0
                return !TransitionEffects.upper(track.clips,index:i) && TransitionEffects.upper(track.clips,index:j)
            }}
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
                let fx = TransitionEffects.at(track,clipID:clip.id,time:time)
                transform.cx += fx.dx;transform.cy += fx.dy;transform.scale *= fx.scale;opacity *= fx.alpha
                if let text = clip.text {
                    let animation = TextAnimationMath.at(text,local:time-clip.startUs,duration:clip.durationUs)
                    transform.cy += animation.dy;transform.scale *= animation.scale;opacity *= animation.alpha
                }
                if p.canvas.blurred && track.kind == .main {
                    let fill = max(bounds.width/image.extent.width,bounds.height/image.extent.height)
                    let bg = image.transformed(by:CGAffineTransform(scaleX:fill,y:fill))
                    result = bg.transformed(by:CGAffineTransform(translationX:(bounds.width-bg.extent.width)/2,y:(bounds.height-bg.extent.height)/2)).clampedToExtent().applyingFilter("CIGaussianBlur",parameters:["inputRadius":p.canvas.blur*50]).cropped(to:bounds).applyingFilter("CIColorMatrix",parameters:["inputAVector":CIVector(x:0,y:0,z:0,w:opacity)]).composited(over:result)
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
            if track.kind == .main {
                for clip in track.clips {
                    guard let tr = clip.transitionIn,(tr.type == .dipBlack || tr.type == .dipWhite),time>=clip.startUs,time<clip.startUs+tr.durationUs else {continue}
                    let alpha = TransitionEffects.dipAlpha(Double(time-clip.startUs)/Double(tr.durationUs))
                    let color = tr.type == .dipWhite ? CIColor.white:CIColor.black
                    result = CIImage(color:color).cropped(to:bounds).applyingFilter("CIColorMatrix",parameters:["inputAVector":CIVector(x:0,y:0,z:0,w:alpha)]).composited(over:result)
                }
            }
        }
        return result
    }
    private func grade(_ source: CIImage, clip: Clip) -> CIImage {
        let a = clip.adjust
        var image = source
        if a.brightness != 0 || a.contrast != 0 || a.saturation != 0 || a.warmth != 0 || a.tint != 0 || a.hue != 0 || clip.filter != nil {
            let key = [a.brightness,a.contrast,a.saturation,a.warmth,a.tint,a.hue,clip.filter?.intensity ?? 0].map {String($0)}.joined(separator:":")+(clip.filter?.id ?? "")
            let cube = cubes[key] ?? ColorAdjustments.cube(a,filter:clip.filter)
            if cubes.count>32 {cubes.removeAll()};cubes[key] = cube
            image = image.applyingFilter("CIColorCube",parameters:["inputCubeDimension":33,"inputCubeData":cube])
        }
        if a.sharpen>0 {image = image.applyingFilter("CISharpenLuminance",parameters:["inputSharpness":a.sharpen*2])}
        if a.vignette>0 {image = image.applyingFilter("CIVignette",parameters:["inputIntensity":a.vignette*2,"inputRadius":min(source.extent.width,source.extent.height)/2])}
        return image
    }
    private func textImage(_ style: TextStyle,clip: Clip,time:Int64,canvas:CGSize) -> CIImage {
        let size = CGSize(width:canvas.width,height:canvas.height)
        let renderer = UIGraphicsImageRenderer(size:size,format:{ let f = UIGraphicsImageRendererFormat(); f.scale = 1; return f }())
        let uiImage = renderer.image { _ in
            var value = style.text
            let visible = TextAnimationMath.at(style,local:time-clip.startUs,duration:clip.durationUs).visible
            if visible<1 {value = String(value.prefix(Int(Double(value.count)*visible)))}
            let fontSize = canvas.height*style.size
            var attrs = TextFonts.layoutAttributes(style,size:fontSize)
            attrs[.foregroundColor] = UIColor(argb:style.color)
            if style.strokeWidth > 0 { attrs[.strokeColor] = UIColor(argb:style.strokeColor); attrs[.strokeWidth] = -style.strokeWidth*100 }
            if style.shadow { let shadow = NSShadow(); shadow.shadowColor = UIColor.black.withAlphaComponent(0.6); shadow.shadowBlurRadius = fontSize*0.08; shadow.shadowOffset = CGSize(width:0,height:fontSize*0.04); attrs[.shadow] = shadow }
            let attributed = NSAttributedString(string:value,attributes:attrs)
            let measured = attributed.boundingRect(with:CGSize(width:size.width*0.9,height:size.height),options:[.usesLineFragmentOrigin,.usesFontLeading],context:nil)
            let rect = CGRect(x:(size.width-measured.width)/2,y:(size.height-measured.height)/2,width:measured.width,height:measured.height)
            if style.backgroundColor != 0 { UIColor(argb:style.backgroundColor).setFill(); UIBezierPath(roundedRect:rect.insetBy(dx:-10,dy:-5),cornerRadius:6).fill() }
            attributed.draw(in:rect)
        }
        return CIImage(image:uiImage)!
    }
}
