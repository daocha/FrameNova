import Foundation
struct Cue: Equatable { var start: Int64; var end: Int64; var text: String }
enum Subtitles {
    static func parse(_ text: String, filename: String = "") -> [Cue] {
        let clean = text.replacingOccurrences(of: "\u{FEFF}", with: "").replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
        if filename.lowercased().hasSuffix(".lrc") || (!clean.contains("-->") && clean.contains("[")) { return lrc(clean) }
        let blocks = clean.replacingOccurrences(of:"\n[ \t]*\n",with:"\n\n",options:.regularExpression).components(separatedBy:"\n\n")
        return blocks.compactMap { block in
            let lines = block.components(separatedBy: "\n")
            guard let index = lines.firstIndex(where: { $0.contains("-->") }) else { return nil }
            let times = lines[index].components(separatedBy: "-->")
            guard times.count == 2, let start = timestamp(times[0]), let end = timestamp(times[1]), end > start else { return nil }
            let body = lines.dropFirst(index+1).joined(separator: "\n").replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression).trimmingCharacters(in: .whitespacesAndNewlines)
            return body.isEmpty ? nil : Cue(start: start, end: end, text: body)
        }
    }
    private static func timestamp(_ value: String) -> Int64? {
        let regex = try! NSRegularExpression(pattern: #"(\d{1,2}):(\d{2}):(\d{2})[,.](\d{1,3})"#)
        guard let m = regex.firstMatch(in: value, range: NSRange(value.startIndex..., in: value)) else { return nil }
        let fields = (1...4).map { String(value[Range(m.range(at: $0), in: value)!]) }
        return (Int64(fields[0])!*3600+Int64(fields[1])!*60+Int64(fields[2])!)*1_000_000 + Int64(fields[3].padding(toLength: 3, withPad: "0", startingAt: 0))!*1000
    }
    private static func lrc(_ text: String) -> [Cue] {
        let regex = try! NSRegularExpression(pattern: #"\[(\d{1,3}):(\d{2})(?:[.:](\d{1,3}))?\]"#)
        var stamped: [(Int64, String)] = []
        for line in text.components(separatedBy: "\n") {
            let matches = regex.matches(in: line, range: NSRange(line.startIndex..., in: line))
            guard let last = matches.last, let tail = Range(last.range, in: line) else { continue }
            let body = String(line[tail.upperBound...]).trimmingCharacters(in: .whitespaces)
            for m in matches {
                func field(_ n: Int) -> String { Range(m.range(at: n), in: line).map { String(line[$0]) } ?? "" }
                let fraction = field(3).padding(toLength: 3, withPad: "0", startingAt: 0)
                stamped.append(((Int64(field(1))!*60+Int64(field(2))!)*1_000_000+(Int64(fraction) ?? 0)*1000, body))
            }
        }
        stamped.sort { $0.0 < $1.0 }
        return stamped.enumerated().compactMap { i, item in
            let end = i+1 < stamped.count ? stamped[i+1].0 : item.0+4_000_000
            return item.1.isEmpty || end <= item.0 ? nil : Cue(start: item.0, end: end, text: item.1)
        }
    }
}
extension Project {
    mutating func addSubtitles(_ cues: [Cue]) {
        var clips: [Clip] = []
        for cue in cues.sorted(by: { $0.start < $1.start }) {
            let start = max(cue.start, clips.last?.endUs ?? 0)
            if cue.end-start >= minimumClip {
                var style = TextStyle(); style.text = cue.text; style.role = "Subtitle"
                clips.append(Clip(startUs: start, srcOutUs: cue.end-start, transform: Transform(cy: 0.86), text: style))
            }
        }
        if !clips.isEmpty { tracks.insert(Track(kind: .text, clips: clips), at: 0) }
    }
}
