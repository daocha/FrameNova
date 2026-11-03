import Foundation
struct Cell { var x: Double; var y: Double; var w: Double; var h: Double }
struct LayoutPreset: Identifiable {
    var id: String; var label: String; var cells: [Cell]
    static func grid(_ cols: Int, _ rows: Int) -> [Cell] { (0..<rows).flatMap { r in (0..<cols).map { c in Cell(x: Double(c)/Double(cols), y: Double(r)/Double(rows), w: 1/Double(cols), h: 1/Double(rows)) } } }
    static let all: [LayoutPreset] = [
        .init(id: "fit", label: "Fit", cells: grid(1,1)),
        .init(id: "side2", label: "Side by side", cells: grid(2,1)), .init(id: "stack2", label: "Top / bottom", cells: grid(1,2)),
        .init(id: "pip_br", label: "PiP bottom right", cells: [Cell(x: 0,y: 0,w: 1,h: 1),Cell(x: 0.62,y: 0.62,w: 0.34,h: 0.34)]),
        .init(id: "pip_tl", label: "PiP top left", cells: [Cell(x: 0,y: 0,w: 1,h: 1),Cell(x: 0.04,y: 0.04,w: 0.34,h: 0.34)]),
        .init(id: "split64", label: "60 / 40", cells: [Cell(x: 0,y: 0,w: 0.6,h: 1),Cell(x: 0.6,y: 0,w: 0.4,h: 1)]),
        .init(id: "cols3", label: "3 columns", cells: grid(3,1)), .init(id: "rows3", label: "3 rows", cells: grid(1,3)),
        .init(id: "big_left3", label: "1 + 2", cells: [Cell(x: 0,y: 0,w: 0.6,h: 1),Cell(x: 0.6,y: 0,w: 0.4,h: 0.5),Cell(x: 0.6,y: 0.5,w: 0.4,h: 0.5)]),
        .init(id: "big_top3", label: "1 over 2", cells: [Cell(x: 0,y: 0,w: 1,h: 0.6),Cell(x: 0,y: 0.6,w: 0.5,h: 0.4),Cell(x: 0.5,y: 0.6,w: 0.5,h: 0.4)]),
        .init(id: "grid4", label: "2 × 2", cells: grid(2,2)),
        .init(id: "big_strip4", label: "1 + 3", cells: [Cell(x: 0,y: 0,w: 1,h: 0.7),Cell(x: 0,y: 0.7,w: 1/3,h: 0.3),Cell(x: 1/3,y: 0.7,w: 1/3,h: 0.3),Cell(x: 2/3,y: 0.7,w: 1/3,h: 0.3)]),
        .init(id: "grid6", label: "3 × 2", cells: grid(3,2))
    ]
}
extension Project {
    mutating func layout(_ preset: LayoutPreset, at time: Int64, gap: Double = 0) {
        let visible = tracks.reversed().filter { !$0.hidden && ($0.kind == .main || $0.kind == .overlay) }.flatMap { $0.clips.filter { $0.contains(time) } }
        let size = canvas.size, w = Double(size.width), h = Double(size.height)
        for (i,c) in visible.enumerated() {
            guard let a = asset(c.assetID), a.width > 0, a.height > 0 else { continue }
            if preset.id == "fit" { update(c.id) { $0.transform = Transform(); $0.crop = CropRect(); $0.keyframes = [] }; continue }
            let cell = preset.cells[i % preset.cells.count], g = gap * min(w,h)
            let cw = max(2,cell.w*w-2*g), ch = max(2,cell.h*h-2*g), ratio = cw/ch, source = Double(a.width)/Double(a.height)
            var crop = CropRect()
            if source > ratio { crop.left = (1-ratio/source)/2; crop.right = crop.left }
            else { crop.top = (1-source/ratio)/2; crop.bottom = crop.top }
            update(c.id) { $0.transform = Transform(cx: cell.x+cell.w/2, cy: cell.y+cell.h/2, scale: cw/min(w,h*ratio), opacity: c.transform.opacity); $0.crop = crop; $0.keyframes = [] }
        }
    }
}
