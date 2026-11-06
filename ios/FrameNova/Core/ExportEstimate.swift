import Foundation

/// How big an export is: the same formulas as Android, so both platforms write files of a similar size.
enum ExportEstimate {
    static func bitsPerPixel(_ quality:String) -> Double {quality == "Maximum" ? 0.18 : quality == "High" ? 0.11 : 0.06}
    static func bitrate(width:Int,height:Int,fps:Int,hevc:Bool,quality:String) -> Int {
        let raw = Double(width)*Double(height)*Double(fps)*bitsPerPixel(quality)*(hevc ? 0.7:1)
        return Int(min(150_000_000,max(2_000_000,raw)))
    }
    static func bytes(bitrate:Int,durationUs:Int64) -> Int64 {Int64(bitrate+256_000)/8*max(1,durationUs/1_000_000)}
}
