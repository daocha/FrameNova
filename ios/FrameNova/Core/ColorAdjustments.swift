import Foundation

enum ColorAdjustments {
    static func apply(_ a:Adjust,filter:FilterSetting?,r:Double,g:Double,b:Double)->[Double] {
        let factor = a.contrast == 0 ? 1:(1+a.contrast*0.7)/(1.0001-a.contrast*0.7)
        var rgb = [r,g,b].map {($0+a.brightness*0.5)*factor+(1-factor)*0.5}
        if a.saturation != 0 || a.hue != 0 {
            rgb = rgb.map {clamp($0,0,1)}
            let hi = rgb.max()!,lo = rgb.min()!,delta = hi-lo,light = (hi+lo)/2
            var hue = 0.0
            if delta>1e-10 {
                if hi == rgb[0] {hue = (rgb[1]-rgb[2])/delta}
                else if hi == rgb[1] {hue = 2+(rgb[2]-rgb[0])/delta}
                else {hue = 4+(rgb[0]-rgb[1])/delta}
                hue /= 6
            }
            hue += a.hue/360;hue -= floor(hue)
            let saturation = clamp((delta/max(1e-10,1-abs(2*light-1)))+a.saturation,0,1)
            let chroma = (1-abs(2*light-1))*saturation
            rgb = [0.0,4.0,2.0].map {offset in
                let value = (hue*6+offset).truncatingRemainder(dividingBy:6)
                return (clamp(abs(value-3)-1,0,1)-0.5)*chroma+light
            }
        }
        rgb[0] *= 1+0.12*a.warmth;rgb[1] *= 1-0.10*a.tint;rgb[2] *= 1-0.12*a.warmth
        if let filter {rgb = FilterCube.apply(filter.id,rgb[0],rgb[1],rgb[2],intensity:filter.intensity)}
        return rgb.map {clamp($0,0,1)}
    }
    static func cube(_ adjust:Adjust,filter:FilterSetting?)->Data {
        var values:[Float] = [];values.reserveCapacity(33*33*33*4)
        for b in 0..<33 {for g in 0..<33 {for r in 0..<33 {
            let output = apply(adjust,filter:filter,r:Double(r)/32,g:Double(g)/32,b:Double(b)/32)
            values.append(Float(output[0]));values.append(Float(output[1]));values.append(Float(output[2]));values.append(1)
        }}}
        return values.withUnsafeBufferPointer {Data(buffer:$0)}
    }
}
