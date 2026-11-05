import Foundation
import Testing
@testable import FrameNovaCore

@Suite struct InteractionParityTests {
    @Test func fixedPlayheadCoordinatesRoundTripAcrossZoomAndOrientation() {
        for width in [391.0,844,1024] {for zoom in [8.0,70,1600] {
            let viewport = TimelineViewport(width:width,playhead:3_000_000,pointsPerSecond:zoom)
            #expect(viewport.position(3_000_000) == width/2)
            for time:Int64 in [0,2_000_000,5_000_000] {#expect(abs(viewport.time(at:viewport.position(time))-time)<=1)}
        }}
    }
    @Test func scrubAccumulatesIndependentOfViewUpdatesAndClampsAtEnds() {
        var scrub = TimelineScrubPosition(position:2_000_000)
        for _ in 0..<10 {_ = scrub.move(delta:-7,pointsPerSecond:70,duration:10_000_000)}
        #expect(scrub.position == 3_000_000)
        _ = scrub.move(delta:1_000,pointsPerSecond:70,duration:10_000_000)
        #expect(scrub.position == 0)
        _ = scrub.move(delta:-7,pointsPerSecond:70,duration:10_000_000)
        #expect(scrub.position == 100_000)
    }
    @Test func movingSnapsEitherEdgeWithoutSnappingBackToItself() {
        var project = Project(name:"Snap")
        project.tracks[0].clips = [Clip(id:"target",srcOutUs:5_000_000),Clip(id:"moving",startUs:8_000_000,srcOutUs:2_000_000)]
        let geometry = TimelineGeometry(pointsPerSecond:100)
        #expect(geometry.snappedStart(2_950_000,duration:2_000_000,project:project,playhead:20_000_000,excluding:"moving") == 3_000_000)
        #expect(geometry.snappedStart(7_980_000,duration:2_000_000,project:project,playhead:20_000_000,excluding:"moving") == 7_980_000)
    }
    @Test func movingIntoANewLayerPreservesIDAndSourceRange() {
        var project = Project(name:"Move")
        let clip = Clip(id:"clip",startUs:2_000_000,srcInUs:1_000_000,srcOutUs:6_000_000)
        project.tracks[0].clips = [clip]
        project.moveToNewTrack(clip.id,kind:.overlay,at:3_000_000)
        #expect(project.clip(clip.id)?.startUs == 3_000_000)
        #expect(project.clip(clip.id)?.srcInUs == 1_000_000)
        #expect(project.track(clip.id)?.kind == .overlay)
        #expect(project.tracks[project.mainIndex].clips.isEmpty)
    }
    @Test func toNewLayerKeepsNonMainClipPropertiesAndLeavesOtherTracksAlone() {
        let video = MediaAsset(id:"video",path:"video.mp4",type:.video,name:"Video",durationUs:10_000_000)
        let audio = MediaAsset(id:"audio",path:"audio.wav",type:.audio,name:"Audio",durationUs:10_000_000,hasAudio:true)
        for kind in [TrackKind.overlay,.text,.audio] {
            let clip = Clip(id:"moving",assetID:kind == .text ? nil:kind == .audio ? audio.id:video.id,
                startUs:2_000_000,srcInUs:1_000_000,srcOutUs:5_000_000,speed:2,volume:0.4,
                fadeInUs:200_000,fadeOutUs:300_000,transform:Transform(scale:0.7),text:kind == .text ? TextStyle():nil)
            var sibling = clip;sibling.id = "sibling";sibling.startUs = 10_000_000
            var other = clip;other.id = "other";other.startUs = 20_000_000
            let source = Track(id:"source",kind:kind,clips:[clip,sibling]),free = Track(id:"free",kind:kind,clips:[other])
            let main = Track(id:"main",kind:.main)
            var project = Project(name:"New layer");project.assets = [video,audio]
            project.tracks = kind == .audio ? [main,source,free]:[free,source,main]
            var locked = project;locked.tracks[locked.tracks.firstIndex {$0.id == source.id}!].locked = true
            let before = locked;locked.moveToNewLayer(clip.id);#expect(locked == before)
            project.moveToNewLayer(clip.id)
            #expect(project.clip(clip.id) == clip)
            #expect(project.track(clip.id)?.kind == kind)
            #expect(![source.id,free.id].contains(project.track(clip.id)!.id))
            #expect(project.tracks.first {$0.id == source.id}?.clips == [sibling])
            #expect(project.tracks.first {$0.id == free.id} == free)
            let sourceIndex = project.tracks.firstIndex {$0.id == source.id}!
            let newIndex = project.tracks.firstIndex {$0.id == project.track(clip.id)?.id}!
            #expect(newIndex == sourceIndex + (kind == .audio ? 1:-1))
        }
    }
    @Test func mainToNewLayerCreatesFreshOverlayAndPreservesTiming() {
        let main = Clip(id:"main-clip",startUs:2_000_000,srcInUs:1_000_000,srcOutUs:5_000_000)
        var project = Project(name:"Main move");project.tracks[0].clips = [main]
        let free = Track(id:"free",kind:.overlay,clips:[Clip(startUs:20_000_000)])
        project.tracks.insert(free,at:0);project.moveToNewLayer(main.id)
        #expect(project.track(main.id)?.kind == .overlay)
        #expect(project.track(main.id)?.id != free.id)
        #expect(project.clip(main.id)?.startUs == main.startUs)
        #expect(project.clip(main.id)?.srcInUs == main.srcInUs)
        #expect(project.clip(main.id)?.transform.scale == main.transform.scale*0.6)
        #expect(project.tracks.first {$0.id == free.id} == free)
    }
    @Test func selectionOrderAndLimitSurviveFilterChanges() {
        var selection = OrderedMediaSelection(limit:2)
        selection.toggle("video");selection.toggle("photo");selection.toggle("extra")
        #expect(selection.ids == ["video","photo"])
        selection.toggle("video");selection.toggle("video")
        #expect(selection.ids == ["photo","video"])
        selection.set("photo",selected:true)
        #expect(selection.ids == ["photo","video"])
        selection.set("photo",selected:false);selection.clear()
        #expect(selection.ids.isEmpty)
    }
    @Test func visualChangesReuseCompositionButTimingAndSoundDoNot() {
        var a = Project(name:"Live");a.tracks[0].clips = [Clip(id:"clip",srcOutUs:5_000_000)]
        var b = a;b.update("clip") {$0.transform.scale = 2;$0.adjust.warmth = 0.5}
        #expect(a.usesSameComposition(as:b))
        b.canvas.background = 0xFFFFFFFF
        #expect(a.usesSameComposition(as:b))
        b.update("clip") {$0.volume = 0}
        #expect(!a.usesSameComposition(as:b))
        b = a;b.setSpeed("clip",speed:2)
        #expect(!a.usesSameComposition(as:b))
    }
    @Test func gapSelectionUsesTappedGapInsteadOfPlayhead() {
        var project = Project(name:"Gap")
        project.tracks[0].clips = [Clip(id:"a",srcOutUs:2_000_000),Clip(id:"b",startUs:5_000_000,srcOutUs:2_000_000)]
        #expect(project.mainGap(at:3_000_000)?.start == 2_000_000)
        #expect(project.mainGap(at:3_000_000)?.end == 5_000_000)
        project.deleteGap(at:3_000_000)
        #expect(project.clip("b")?.startUs == 2_000_000)
        #expect(project.mainGap(at:3_000_000) == nil)
    }
    @Test func subtitleDefaultsMatchManualSubtitles() {
        var project = Project(name:"Subtitles");project.addSubtitles([Cue(start:0,end:2_000_000,text:"Line")])
        let clip = project.tracks[0].clips[0]
        #expect(clip.text?.size == 0.055);#expect(clip.text?.strokeWidth == 0.08)
        #expect(clip.transform.cy == 0.86)
    }
    @Test func transitionsRespectLayerOrderAndEasing() {
        let incoming = TransitionEffects.effect(.fade,progress:0.25,incoming:true,incomingOnTop:true)
        #expect(incoming.alpha == 0.15625)
        #expect(TransitionEffects.effect(.fade,progress:0,incoming:false,incomingOnTop:false).alpha == 1)
        #expect(TransitionEffects.effect(.fade,progress:1,incoming:false,incomingOnTop:false).alpha == 0)
        #expect(TransitionEffects.dipAlpha(0) == 0);#expect(TransitionEffects.dipAlpha(0.5) == 1);#expect(TransitionEffects.dipAlpha(1) == 0)
        #expect(TransitionEffects.effect(.pushLeft,progress:0,incoming:true,incomingOnTop:false).dx == 1)
        #expect(TransitionEffects.effect(.pushLeft,progress:1,incoming:false,incomingOnTop:false).dx == -1)
        #expect(TransitionEffects.effect(.zoomIn,progress:0,incoming:true,incomingOnTop:true).scale == 0.6)
    }
    @Test func textAnimationsUseBoundedDurationsAndDistinctExitDirection() {
        var style = TextStyle();style.animIn = .slideUp;style.animOut = .slideUp;style.animDurationUs = 2_000_000
        let enter = TextAnimationMath.at(style,local:0,duration:1_000_000),exit = TextAnimationMath.at(style,local:1_000_000,duration:1_000_000)
        #expect(enter.dy == 0.06);#expect(exit.dy == -0.06)
        #expect(TextAnimationMath.at(style,local:500_000,duration:1_000_000) == TextAnimationEffect())
        #expect(TextAnimationMath.effect(.zoom,progress:0,entering:true).scale == 1.4)
        #expect(TextAnimationMath.effect(.typewriter,progress:0.25,entering:true).visible == 0.25)
    }
    @Test func adjustmentAndCubeMathUseTheSameSliderRanges() {
        let neutral = ColorAdjustments.apply(Adjust(),filter:nil,r:0.2,g:0.4,b:0.6)
        #expect(neutral == [0.2,0.4,0.6])
        #expect(ColorAdjustments.apply(Adjust(brightness:1),filter:nil,r:0.2,g:0.3,b:0.4)[0] == 0.7)
        let hue = ColorAdjustments.apply(Adjust(hue:120),filter:nil,r:1,g:0,b:0)
        #expect(hue[0]<0.001 && hue[1]>0.999 && hue[2]<0.001)
        let mono = ColorAdjustments.apply(Adjust(saturation:-1),filter:nil,r:1,g:0,b:0)
        #expect(mono == [0.5,0.5,0.5])
        #expect(FilterCube.data("vivid",intensity:1).count == 33*33*33*4*MemoryLayout<Float>.size)
    }
}

@Suite struct LayoutParityTests {
    private func project()->Project {
        let asset = MediaAsset(id:"asset",path:"a.mov",type:.video,name:"A",durationUs:5_000_000,width:1920,height:1080)
        var p = Project(name:"Layout");p.add([asset],kind:.main,at:0);p.add([asset],kind:.overlay,at:0);return p
    }
    @Test func sideBySideUsesMainThenOverlayAndFillsBothCells() {
        var p = project();let main = p.tracks[p.mainIndex].clips[0].id,overlay = p.tracks[0].clips[0].id
        p.layout(LayoutPreset.all.first {$0.id == "side2"}!,at:0)
        #expect(p.clip(main)?.transform.cx == 0.25);#expect(p.clip(overlay)?.transform.cx == 0.75)
        #expect(p.clip(main)?.crop.left == 0.25);#expect(p.clip(main)?.crop.right == 0.25)
    }
    @Test func fitResetsPlacementButPreservesOpacity() {
        var p = project();let id = p.tracks[p.mainIndex].clips[0].id
        p.update(id) {$0.transform = Transform(cx:0.2,scale:2,opacity:0.4)}
        p.layout(LayoutPreset.all[0],at:0)
        #expect(p.clip(id)?.transform == Transform(opacity:0.4))
        #expect(p.clip(id)?.crop == CropRect())
    }
    @Test func spacingShrinksCellsWithoutMovingTheirCenters() {
        var a = project(),b = a;let preset = LayoutPreset.all.first {$0.id == "grid4"}!
        a.layout(preset,at:0,gap:0);b.layout(preset,at:0,gap:0.02)
        let id = a.tracks[a.mainIndex].clips[0].id
        #expect(a.clip(id)?.transform.cx == b.clip(id)?.transform.cx)
        #expect(b.clip(id)!.transform.scale<a.clip(id)!.transform.scale)
    }
}
