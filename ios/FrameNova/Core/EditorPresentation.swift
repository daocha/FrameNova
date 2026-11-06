import Foundation
import CoreGraphics

enum EditorPresentation {
    static func canvasRect(in size:CGSize,aspect:Double,margin:Double = 12)->CGRect {
        let width = max(0,size.width-2*margin),height = max(0,size.height-2*margin)
        let w = min(width,height*aspect),h = w/aspect
        return CGRect(x:(size.width-w)/2,y:(size.height-h)/2,width:w,height:h)
    }
    static func corners(of rect:CGRect,rotation:Double)->[CGPoint] {
        let r = rotation * .pi/180
        return [(-1.0,-1.0),(1.0,-1.0),(1.0,1.0),(-1.0,1.0)].map {sx,sy in
            let x = sx*rect.width/2,y = sy*rect.height/2
            return CGPoint(x:rect.midX+x*cos(r)-y*sin(r),y:rect.midY+x*sin(r)+y*cos(r))
        }
    }
    static func projectColumns(width:Double)->Int {
        let available = max(0,min(1400,width)-32)
        // Android's adaptive grid: as many 170 wide columns with 12 gaps as fit, and at least one.
        return max(1,Int((available+12)/182))
    }
}

struct FilmstripPlan {
    let duration:Int64
    var count:Int {clamp(Int(duration/1_000_000),10,120)}
    func index(at time:Int64)->Int {min(count-1,Int(Double(clamp(time,0,max(0,duration)))/Double(max(1,duration))*Double(count)))}
    func time(at index:Int)->Int64 {Int64(Double(max(0,duration))*Double(2*index+1)/Double(2*count))}
    var order:[Int] {
        var result:[Int] = [],seen:Set<Int> = [],step = max(1,count/10)
        while true {
            for index in stride(from:0,to:count,by:step) where seen.insert(index).inserted {result.append(index)}
            if step == 1 {return result};step = max(1,step/2)
        }
    }
}

extension CanvasSettings {
    var formatSummary:String {"\(aspect.rawValue) · \(tier.label) · \(fps) fps"}
}
