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
    @Test func exportEstimateMatchesAndroid() {
        // 4K, 30 fps, high quality, HEVC: 3840*2160*30*0.11*0.7 = about 19.16 Mbps; H.264 is a third larger.
        #expect(abs(ExportEstimate.bitrate(width:3840,height:2160,fps:30,hevc:true,quality:"High")-19_160_000)<100_000)
        #expect(ExportEstimate.bitrate(width:1280,height:720,fps:24,hevc:true,quality:"Standard") == 2_000_000)
        #expect(ExportEstimate.bitrate(width:7680,height:4320,fps:60,hevc:false,quality:"Maximum") == 150_000_000)
        #expect(ExportEstimate.bytes(bitrate:8_000_000,durationUs:10_000_000) == (8_256_000/8)*10)
    }
    @Test func transportTimecodeShowsFramesLikeAndroid() {
        #expect(formatTimecode(0,fps:30) == "00:00.00")
        #expect(formatTimecode(61_500_000,fps:30) == "01:01.15")
        #expect(formatTimecode(1_999_000,fps:24) == "00:01.23")
    }
    @Test func projectCardColumnsFollowAndroidAdaptiveGrid() {
        #expect(EditorPresentation.projectColumns(width:320) == 1)
        #expect(EditorPresentation.projectColumns(width:375) == 1)
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

struct LanguageTests {
    @Test func interpolatedTextKeepsTheKeyWithPlaceholders() {
        let count = 3,name = "clip"
        let text:LocalizedText = "Imported \(count) files named \(name)"
        #expect(text.key == "Imported %lld files named %@")
        #expect(text.arguments.count == 2)
        #expect(localized("100% sure") == "100% sure")
    }
    @Test func languageChoiceIsValidated() {
        #expect(AppLanguage.normalized("zh-Hant") == "zh-Hant")
        #expect(AppLanguage.normalized("fr") == "system")
        #expect(AppLanguage.normalized(nil) == "system")
        #expect(AppLanguage.bundle(for:"en") == nil)
    }
}
