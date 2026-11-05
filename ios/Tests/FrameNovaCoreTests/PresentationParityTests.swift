import Foundation
import CoreGraphics
import Testing
@testable import FrameNovaCore

@Suite struct PresentationParityTests {
    @Test func portraitCanvasKeepsEveryEdgeInsideLandscapePreview() {
        let canvas = EditorPresentation.canvasRect(in:CGSize(width:393,height:200),aspect:9.0/16)
        #expect(canvas == CGRect(x:147,y:12,width:99,height:176))
        for aspect in Aspect.allCases {
            let bounds = EditorPresentation.canvasRect(in:CGSize(width:1024,height:700),aspect:aspect.ratio)
            #expect(bounds.minX>=12 && bounds.minY>=12 && bounds.maxX<=1012 && bounds.maxY<=688)
            #expect(abs(bounds.width/bounds.height-aspect.ratio)<0.0001)
        }
    }
    @Test func compactProjectCardsUseTwoColumnsOnNarrowPhones() {
        #expect(EditorPresentation.projectColumns(width:320) == 2)
        #expect(EditorPresentation.projectColumns(width:375) == 2)
        #expect(EditorPresentation.projectColumns(width:393) == 2)
        #expect(EditorPresentation.projectColumns(width:768) == 4)
        #expect(EditorPresentation.projectColumns(width:1024) == 5)
        #expect(EditorPresentation.projectColumns(width:2000) == EditorPresentation.projectColumns(width:1400))
    }
    @Test func rotatedCornersReachOutsideEvenWhenUnrotatedBoundsFit() {
        let corners = EditorPresentation.corners(of:CGRect(x:0,y:0,width:100,height:100),rotation:45)
        #expect(corners.contains {$0.x<0})
        #expect(corners.contains {$0.y>100})
    }
    @Test func filmstripsAreBoundedAndFillCoarseToFineAtEveryZoom() {
        let short = FilmstripPlan(duration:500_000),long = FilmstripPlan(duration:600_000_000)
        #expect(short.count == 10);#expect(long.count == 120)
        #expect(Array(long.order.prefix(10)) == [0,12,24,36,48,60,72,84,96,108])
        #expect(Set(long.order).count == 120)
        #expect(long.index(at:-1_000_000) == 0);#expect(long.index(at:600_000_000) == 119)
        #expect(long.index(at:Int64.max) == 119)
        #expect(long.time(at:long.index(at:300_000_000)) == 302_500_000)
        #expect(short.time(at:9)<short.duration)
    }
}
