import Testing
import Foundation
@testable import FrameNovaCore
@Suite struct TimelineTests {
    @Test func audioWaveformFadeUsesTimelineTimeAfterTrimAndSpeedChange() {
        let clip = Clip(startUs:5_000_000,srcInUs:2_000_000,srcOutUs:10_000_000,speed:2,fadeInUs:1_000_000,fadeOutUs:1_000_000)
        for (offset,gain) in [(Int64(0),0.0),(500_000,0.5),(2_000_000,1.0),(3_500_000,0.5),(4_000_000,0.0)] {
            expectEqual(clip.audioFadeGain(at:clip.startUs+offset),gain,accuracy:0.0001)
        }
        var shortened = clip
        shortened.srcOutUs = 4_000_000
        expectEqual(shortened.audioFadeGain(at:5_250_000),0.5,accuracy:0.0001)
        expectEqual(shortened.audioFadeGain(at:5_500_000),1,accuracy:0.0001)
        shortened.fadeInUs = 0;shortened.fadeOutUs = 0
        expectEqual(shortened.audioFadeGain(at:5_000_000),1,accuracy:0.0001)
        expectEqual(shortened.audioFadeGain(at:6_000_000),1,accuracy:0.0001)
    }
    func project() -> Project {
        var p = Project(name: "Test")
        p.add([MediaAsset(path: "a.mov", type: .video, name: "A", durationUs: 10_000_000)], kind: .main, at: 0)
        return p
    }
    @Test func testSplitRetainsSourceAndInterpolatedKeyframes() {
        var p = project(); let id = p.tracks[0].clips[0].id
        p.update(id) { $0.keyframes = [Keyframe(offsetUs: 0, transform: Transform()),Keyframe(offsetUs: 10_000_000, transform: Transform(cx: 1), smooth: false)] }
        let second = p.split(id, at: 4_000_000)!
        expectEqual(p.clip(id)!.srcOutUs, 4_000_000)
        expectEqual(p.clip(second)!.srcInUs, 4_000_000)
        expectEqual(p.clip(second)!.transform(at: 4_000_000).cx, 0.7, accuracy: 0.001)
        expectEqual(p.durationUs, 10_000_000)
    }
    @Test func testTrimLeavesGapAndDeleteGapClosesIt() {
        var p = project(); let id = p.tracks[0].clips[0].id
        p.trimStart(id, delta: 2_000_000)
        expectEqual(p.clip(id)!.startUs, 2_000_000); expectEqual(p.durationUs, 10_000_000)
        p.deleteGap(at: 1_000_000); expectEqual(p.clip(id)!.startUs, 0); expectEqual(p.durationUs, 8_000_000)
    }
    @Test func testInsertionPushesOnlyOverlappingClips() {
        var p = project(); let second = p.duplicate(p.tracks[0].clips[0].id)!
        p.insertMain([Clip(srcOutUs: 2_000_000)], at: 10_000_000)
        expectEqual(p.clip(second)!.startUs, 12_000_000)
        expectEqual(p.durationUs, 22_000_000)
    }
    @Test func testTransitionOverlapsAndCapsAtHalfShorterClip() {
        var p = project(); let id = p.duplicate(p.tracks[0].clips[0].id)!
        p.setTransition(id, transition: Transition(type: .fade, durationUs: 9_000_000))
        expectEqual(p.clip(id)!.startUs, 5_000_000); expectEqual(p.durationUs, 15_000_000)
    }
    @Test func testTrimmingTransitionKeepsOnlyRemainingOverlap() {
        var p = project(); let first = p.tracks[0].clips[0].id
        let second = p.duplicate(first)!
        p.setTransition(second,transition:Transition(type:.fade))
        p.trimEnd(first,delta:-200_000)
        expectEqual(p.clip(second)!.transitionIn!.durationUs,300_000)
        expectEqual(p.clip(second)!.startUs,9_500_000)
    }
    @Test func testSpeedScalesKeyframeTimes() {
        var p = project(); let id = p.tracks[0].clips[0].id
        p.update(id) { $0.keyframes = [Keyframe(offsetUs: 4_000_000, transform: Transform())] }
        p.setSpeed(id, speed: 2)
        expectEqual(p.durationUs, 5_000_000); expectEqual(p.clip(id)!.keyframes[0].offsetUs, 2_000_000)
    }
    @Test func testOverlaysGetFreeTracksAndKeepOrder() {
        var p = project(); let a = p.assets[0]
        p.add([a,a], kind: .overlay, at: 0)
        expectEqual(p.tracks.map(\.kind), [.overlay,.overlay,.main])
    }
    @Test func testCanvasMatchesEvenBoundedOutput() {
        for aspect in Aspect.allCases { for tier in Resolution.allCases {
            let c = CanvasSettings(aspect: aspect,tier: tier), size = c.size
            expectEqual(size.width%2,0); expectEqual(size.height%2,0)
            expectLessOrEqual(max(size.width,size.height),tier.rawValue)
            expectEqual(Double(size.width)/Double(size.height),aspect.ratio,accuracy:0.015)
        } }
    }
    @Test func testSubtitleFormats() {
        expectEqual(Subtitles.parse("1\n00:00:01,500 --> 00:00:03,000\n<b>Hello</b>\n").first, Cue(start: 1_500_000,end: 3_000_000,text:"Hello"))
        let cues = Subtitles.parse("[00:01.50]A\n[00:03]B", filename:"lyrics.lrc")
        expectEqual(cues, [Cue(start:1_500_000,end:3_000_000,text:"A"),Cue(start:3_000_000,end:7_000_000,text:"B")])
    }
    @Test func testPersistenceRoundTrip() throws {
        let p = project(); expectEqual(try JSONDecoder().decode(Project.self,from: JSONEncoder().encode(p)),p)
    }
}

func expectEqual<T: Equatable>(_ lhs:T,_ rhs:T) { #expect(lhs == rhs) }
func expectEqual(_ lhs:Double,_ rhs:Double,accuracy:Double) { #expect(abs(lhs-rhs) <= accuracy) }
func expectLessOrEqual<T: Comparable>(_ lhs:T,_ rhs:T) { #expect(lhs <= rhs) }
