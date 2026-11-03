import Foundation
enum FilterCube {
    static let names = ["vivid":"Vivid","warm":"Warm","cool":"Cool","golden":"Golden","teal_orange":"Teal & Orange","film":"Film","chrome":"Chrome","fade":"Fade","pastel":"Pastel","vintage":"Vintage","forest":"Forest","rose":"Rose","cyber":"Cyber","bleach":"Bleach","mono":"Mono","noir":"Noir"]
    static let ids = ["vivid","warm","cool","golden","teal_orange","film","chrome","fade","pastel","vintage","forest","rose","cyber","bleach","mono","noir"]
    static func apply(_ id:String,_ r:Double,_ g:Double,_ b:Double,intensity:Double) -> [Double] {
        func luma(_ r:Double,_ g:Double,_ b:Double) -> Double { 0.2126*r+0.7152*g+0.0722*b }
        func sat(_ r:Double,_ g:Double,_ b:Double,_ s:Double) -> [Double] { let l = luma(r,g,b); return [l+(r-l)*s,l+(g-l)*s,l+(b-l)*s] }
        func contrast(_ v:Double,_ k:Double) -> Double { (v-0.5)*k+0.5 }
        func curve(_ v:Double,_ k:Double) -> Double { let x = clamp(v,0,1); return x+(x*x*(3-2*x)-x)*k }
        func lift(_ v:Double,_ black:Double,_ white:Double = 1) -> Double { black+v*(white-black) }
        var o = [r,g,b]
        switch id {
        case "vivid": o = sat(r,g,b,1.35).map { contrast($0,1.08) }
        case "warm": o = sat(r*1.07+0.02,g*1.01,b*0.88,1.08)
        case "cool": o = sat(r*0.9,g,b*1.08+0.02,1.05)
        case "golden": let l = luma(r,g,b); o = [r*1.08+0.04*l,g*1.03+0.02*l,b*0.82]
        case "teal_orange": let l = luma(r,g,b)-0.5; o = sat(r+l*0.16,g+0.01,b-l*0.18,1.12).map { curve($0,0.25) }
        case "film": let s = sat(r*1.02,g,b*0.97,0.88); o = [lift(curve(s[0],0.35),0.03),lift(curve(s[1],0.35),0.03),lift(curve(s[2],0.35),0.04)]
        case "chrome": let s = sat(r,g,b,1.22); o = [contrast(s[0],1.15)+0.01,contrast(s[1],1.15),contrast(s[2],1.15)-0.01]
        case "fade": let s = sat(r,g,b,0.8); o = [lift(s[0],0.08,0.96),lift(s[1],0.08,0.96),lift(s[2],0.09,0.96)]
        case "pastel": let s = sat(r,g,b,0.7); o = [lift(s[0],0.08)+0.02,lift(s[1],0.08)+0.02,lift(s[2],0.1)+0.03]
        case "vintage": let l = luma(r,g,b); o = [lift(r*0.45+(l*1.07+0.05)*0.55,0.05,0.95),lift(g*0.45+(l*0.92+0.03)*0.55,0.05,0.95),lift(b*0.45+(l*0.72+0.02)*0.55,0.07,0.92)]
        case "forest": o = sat(r*0.94,g*1.06+0.01,b*0.95,1.1)
        case "rose": o = [r*1.05+0.03,g*0.96,b*1.02+0.03]
        case "cyber": let l = luma(r,g,b)-0.5; o = sat(r-l*0.1+0.02,g+l*0.08,b-l*0.1+0.06,1.18)
        case "bleach": o = sat(r,g,b,0.55).map { contrast($0,1.22) }
        case "mono": let l = luma(r,g,b); o = [l,l,l]
        case "noir": let l = curve(contrast(luma(r,g,b),1.25),0.6); o = [l,l,l]
        default: break
        }
        return zip([r,g,b],o).map { clamp($0+($1-$0)*clamp(intensity,0,1),0,1) }
    }
    static func data(_ id:String,intensity:Double) -> Data {
        var values: [Float] = []; values.reserveCapacity(33*33*33*4)
        for b in 0..<33 { for g in 0..<33 { for r in 0..<33 {
            values += apply(id,Double(r)/32,Double(g)/32,Double(b)/32,intensity:intensity).map(Float.init)+[1]
        } } }
        return values.withUnsafeBufferPointer { Data(buffer:$0) }
    }
}
