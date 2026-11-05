import Foundation

let minimumClip: Int64 = 100_000
func newID() -> String { String(UUID().uuidString.replacingOccurrences(of: "-", with: "").prefix(12)) }
func clamp<T: Comparable>(_ value: T, _ low: T, _ high: T) -> T { min(high, max(low, value)) }

enum Aspect: String, Codable, CaseIterable {
    case wide = "16:9", portrait = "9:16", square = "1:1", social = "4:5", classic = "4:3", tall = "3:4", cinema = "21:9"
    var ratio: Double { let parts = rawValue.split(separator: ":").map { Double($0)! }; return parts[0] / parts[1] }
}
enum Resolution: Int, Codable, CaseIterable {
    case hd = 1280, fhd = 1920, qhd = 2560, uhd = 3840
    var label: String { switch self { case .hd: return "720p"; case .fhd: return "1080p"; case .qhd: return "2K"; case .uhd: return "4K" } }
}
struct CanvasSettings: Codable, Equatable {
    var aspect: Aspect = .wide
    var tier: Resolution = .uhd
    var fps = 30
    var background: UInt32 = 0xFF000000
    var blurred = false
    var blur = 0.6
    var size: (width: Int, height: Int) {
        let long = Double(tier.rawValue), short = Double(tier.rawValue * 9 / 16)
        let box = aspect.ratio >= 1 ? (long, short) : (short, long)
        let w = min(box.0, box.1 * aspect.ratio), h = w / aspect.ratio
        return (max(2, Int((w / 2).rounded()) * 2), max(2, Int((h / 2).rounded()) * 2))
    }
}
enum MediaType: String, Codable { case video, image, audio }
struct MediaAsset: Codable, Equatable, Identifiable {
    var id = newID()
    var path: String
    var type: MediaType
    var name: String
    var durationUs: Int64
    var width = 0
    var height = 0
    var hasAudio = false
    var frameRate: Double = 0
}
enum TrackKind: String, Codable, CaseIterable { case text, overlay, main, audio }
struct Track: Codable, Equatable, Identifiable {
    var id = newID()
    var kind: TrackKind
    var clips: [Clip] = []
    var muted = false
    var hidden = false
    var locked = false
}
struct Transform: Codable, Equatable {
    var cx = 0.5, cy = 0.5, scale = 1.0, rotation = 0.0, opacity = 1.0
    func interpolated(to b: Transform, fraction t: Double) -> Transform {
        Transform(cx: cx + (b.cx-cx)*t, cy: cy + (b.cy-cy)*t, scale: scale + (b.scale-scale)*t,
                  rotation: rotation + (b.rotation-rotation)*t, opacity: opacity + (b.opacity-opacity)*t)
    }
}
struct Keyframe: Codable, Equatable { var offsetUs: Int64; var transform: Transform; var smooth = true }
struct CropRect: Codable, Equatable { var left = 0.0, top = 0.0, right = 0.0, bottom = 0.0 }
struct Adjust: Codable, Equatable {
    var brightness = 0.0, contrast = 0.0, saturation = 0.0, warmth = 0.0, tint = 0.0, hue = 0.0, vignette = 0.0, sharpen = 0.0
}
struct FilterSetting: Codable, Equatable { var id: String; var intensity = 1.0 }
enum TransitionType: String, Codable, CaseIterable {
    case fade = "Fade", dipBlack = "Dip to black", dipWhite = "Dip to white"
    case pushLeft = "Push left", pushRight = "Push right", pushUp = "Push up", pushDown = "Push down"
    case slideLeft = "Slide left", slideRight = "Slide right", slideUp = "Slide up", slideDown = "Slide down"
    case zoomIn = "Zoom in", zoomOut = "Zoom out"
}
struct Transition: Codable, Equatable { var type: TransitionType; var durationUs: Int64 = 500_000 }
enum TextAnimation: String, Codable, CaseIterable { case none = "None", fade = "Fade", slideUp = "Slide up", slideDown = "Slide down", pop = "Pop", typewriter = "Typewriter", zoom = "Zoom" }
struct TextStyle: Codable, Equatable {
    var text = "Text", fontID = "system"
    var size = 0.07
    var color: UInt32 = 0xFFFFFFFF
    var bold = true, italic = false, shadow = true
    var alignment = "Center"
    var strokeColor: UInt32 = 0xFF000000
    var strokeWidth = 0.0
    var backgroundColor: UInt32 = 0
    var letterSpacing = 0.0, lineSpacing = 1.1
    var animIn: TextAnimation = .none, animOut: TextAnimation = .none
    var animDurationUs: Int64 = 400_000
    var role = "Title"
}
struct Clip: Codable, Equatable, Identifiable {
    var id = newID()
    var assetID: String? = nil
    var startUs: Int64 = 0
    var srcInUs: Int64 = 0
    var srcOutUs: Int64 = 3_000_000
    var speed = 1.0, volume = 1.0
    var fadeInUs: Int64 = 0, fadeOutUs: Int64 = 0
    var transform = Transform()
    var keyframes: [Keyframe] = []
    var crop = CropRect()
    var flipH = false, flipV = false
    var adjust = Adjust()
    var filter: FilterSetting? = nil
    var transitionIn: Transition? = nil
    var text: TextStyle? = nil
    var audioOnly = false
    var durationUs: Int64 { Int64(Double(srcOutUs - srcInUs) / speed) }
    var endUs: Int64 { startUs + durationUs }
    /// Fade envelope in timeline time, matching the audio mix's half-duration cap.
    func audioFadeGain(at time: Int64) -> Double {
        let duration = max(0,durationUs), offset = clamp(time-startUs,0,duration)
        let incoming = clamp(fadeInUs,0,duration/2), outgoing = clamp(fadeOutUs,0,duration/2)
        let fadeIn = incoming > 0 ? Double(offset)/Double(incoming):1
        let fadeOut = outgoing > 0 ? Double(duration-offset)/Double(outgoing):1
        return clamp(min(fadeIn,fadeOut),0,1)
    }
    func contains(_ time: Int64) -> Bool { time >= startUs && time < endUs }
    func sourceTime(at time: Int64) -> Int64 { clamp(srcInUs + Int64(Double(clamp(time-startUs, 0, durationUs))*speed), srcInUs, srcOutUs) }
    func transform(at time: Int64) -> Transform {
        let sorted = keyframes.sorted { $0.offsetUs < $1.offsetUs }, offset = time-startUs
        guard let first = sorted.first, let last = sorted.last else { return transform }
        if offset <= first.offsetUs { return first.transform }; if offset >= last.offsetUs { return last.transform }
        let i = sorted.firstIndex { $0.offsetUs > offset }!, a = sorted[i-1], b = sorted[i]
        var t = Double(offset-a.offsetUs)/Double(max(1, b.offsetUs-a.offsetUs))
        if b.smooth { t = t*t*(3-2*t) }
        return a.transform.interpolated(to: b.transform, fraction: t)
    }
    mutating func setTransform(_ value: Transform, at time: Int64, fps: Int) {
        if keyframes.isEmpty { transform = value; return }
        let offset = clamp(time-startUs, 0, durationUs)
        if let i = keyframes.firstIndex(where: { abs($0.offsetUs-offset) <= 500_000/Int64(fps) }) { keyframes[i].transform = value }
        else { keyframes.append(Keyframe(offsetUs: offset, transform: value)) }
        keyframes.sort { $0.offsetUs < $1.offsetUs }
    }
}
struct Project: Codable, Equatable, Identifiable {
    var id = newID()
    var name: String
    var createdAt = Date(), modifiedAt = Date()
    var canvas = CanvasSettings()
    var coverAssetID: String?
    var assets: [MediaAsset] = []
    var tracks = [Track(id: "main", kind: .main)]
    var durationUs: Int64 { tracks.reduce(0) {end,track in track.clips.reduce(end) {max($0,$1.endUs)}} }
    var mainIndex: Int { tracks.firstIndex { $0.kind == .main }! }
    func asset(_ id: String?) -> MediaAsset? { assets.first { $0.id == id } }
    func clip(_ id: String?) -> Clip? { tracks.lazy.flatMap(\.clips).first { $0.id == id } }
    func track(_ clipID: String) -> Track? { tracks.first { $0.clips.contains { $0.id == clipID } } }
}
func formatTime(_ us: Int64) -> String { let s = max(0, us)/1_000_000; return String(format: "%02lld:%02lld", s/60, s%60) }
