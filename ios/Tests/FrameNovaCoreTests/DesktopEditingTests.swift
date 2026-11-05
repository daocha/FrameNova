import Foundation
import Testing
@testable import FrameNovaCore

@Suite struct DesktopEditingTests {
    let video = MediaAsset(id: "video", path: "video.mov", type: .video, name: "Video", durationUs: 5_000_000, hasAudio: true)
    let photo = MediaAsset(id: "photo", path: "photo.png", type: .image, name: "Photo", durationUs: 3_000_000)
    let audio = MediaAsset(id: "audio", path: "audio.m4a", type: .audio, name: "Audio", durationUs: 4_000_000, hasAudio: true)

    @Test func mediaBinDoesNotAlterTimelineAndDeduplicatesImports() {
        var project = Project(name: "Media")
        project.addLibraryAssets([video, photo, video])
        #expect(project.assets.count == 2)
        #expect(project.durationUs == 0)
        #expect(project.tracks.count == 1)
        let first = project.insertAsset(video, kind: .main, at: 0)
        let second = project.insertAsset(video, kind: .main, at: 5_000_000)
        #expect(first != second)
        #expect(project.assets.count == 2)
        #expect(project.durationUs == 10_000_000)
    }

    @Test func dropPreservesGapAndInsertsIntoOccupiedMainAtNearestEdge() throws {
        var project = Project(name: "Drop")
        project.insertAsset(video, kind: .main, at: 0)
        let nextResult = project.insertAsset(photo, kind: .main, at: 4_500_000)
        let next = try #require(nextResult)
        #expect(project.clip(next)?.startUs == 5_000_000)
        let firstID = try #require(project.tracks.first?.clips.first?.id)
        project.move(firstID, to: "main", at: 2_000_000)
        #expect(project.clip(firstID)?.startUs == 2_000_000)
        #expect(project.tracks[project.mainIndex].clips[0].startUs == 2_000_000)
    }

    @Test func droppingOnEmptySpacePreservesTheChosenTime() throws {
        var project = Project(name: "Empty space")
        let firstResult = project.insertAsset(video, kind: .main, at: 2_000_000)
        let first = try #require(firstResult)
        #expect(project.clip(first)?.startUs == 2_000_000)
        let lastResult = project.insertAsset(photo, kind: .main, at: 20_000_000)
        let last = try #require(lastResult)
        #expect(project.clip(last)?.startUs == 20_000_000)
        #expect(project.clip(first)?.endUs == 7_000_000)
    }

    @Test func dropUsesChosenFreeLayerAndAllocatesAnotherForCollisions() throws {
        var project = Project(name: "Layers")
        let firstResult = project.insertAsset(video, kind: .overlay, at: 0)
        let first = try #require(firstResult)
        let target = try #require(project.track(first)?.id)
        let secondResult = project.insertAsset(photo, kind: .overlay, trackID: target, at: 6_000_000)
        let second = try #require(secondResult)
        #expect(project.track(second)?.id == target)
        let overlapResult = project.insertAsset(photo, kind: .overlay, trackID: target, at: 1_000_000)
        let overlap = try #require(overlapResult)
        #expect(project.track(overlap)?.id != target)
    }

    @Test func incompatibleAndLockedDropsAreNoOps() {
        var project = Project(name: "Locked")
        project.tracks[0].locked = true
        let original = project
        let rejected1 = project.insertAsset(video, kind: .main, trackID: "main", at: 0)
        #expect(rejected1 == nil)
        let rejectedDefault = project.insertAsset(video, kind: .main, at: 0)
        #expect(rejectedDefault == nil)
        let rejected2 = project.insertAsset(audio, kind: .overlay, at: 0)
        #expect(rejected2 == nil)
        let rejected3 = project.insertAsset(photo, kind: .audio, at: 0)
        #expect(rejected3 == nil)
        let rejected4 = project.insertAsset(video, kind: .text, at: 0)
        #expect(rejected4 == nil)
        #expect(project == original)
    }

    @Test func automaticLayerPlacementSkipsLockedTracks() throws {
        var project = Project(name: "Layer lock")
        project.insertAsset(photo, kind: .overlay, at: 0)
        project.tracks[0].locked = true
        let locked = project.tracks[0].id
        let result = project.insertAsset(photo, kind: .overlay, at: 10_000_000)
        let id = try #require(result)
        #expect(project.track(id)?.id != locked)
        #expect(project.tracks.first(where: {$0.id == locked})?.clips.count == 1)
    }

    @Test func videoDroppedOnAudioTrackUsesOnlyAudio() throws {
        var project = Project(name: "Sound")
        let idResult = project.insertAsset(video, kind: .audio, at: 2_000_000)
        let id = try #require(idResult)
        #expect(project.clip(id)?.audioOnly == true)
        #expect(project.clip(id)?.startUs == 2_000_000)
        #expect(project.track(id)?.kind == .audio)
    }

    @Test func snapToleranceTracksZoomAndExcludesDraggedClip() {
        var project = Project(name: "Snap")
        let id = project.insertAsset(video, kind: .main, at: 0)
        let geometry = TimelineGeometry(pointsPerSecond: 100)
        #expect(geometry.time(at: -100) == 0)
        #expect(geometry.time(at: 150) == 1_500_000)
        #expect(TimelineGeometry(pointsPerSecond:0.5).time(at:150) == 300_000_000)
        #expect(geometry.snap(4_950_000, project: project, playhead: 2_000_000) == 5_000_000)
        #expect(geometry.snap(4_950_000, project: project, playhead: 2_000_000, excluding: id) == 4_950_000)
        #expect(TimelineGeometry(pointsPerSecond: 600).snap(4_950_000, project: project, playhead: 0) == 4_950_000)
        #expect(TimelineGeometry(snapping: false).snap(4_999_000, project: project, playhead: 0) == 4_999_000)
    }

    @Test func zoomedRulerKeepsSeekingAndPlayheadAlignedNearClipEnd() {
        let end:Int64 = 600_000_000, width = 720.0
        for zoom in [70.0,600.0,1600.0] {
            let geometry = TimelineGeometry(pointsPerSecond:zoom)
            let offset = geometry.position(end)-width+40
            for localX in [0.0,width/2,width-40] {
                let time = geometry.time(atViewportX:localX,scrollOffset:offset)
                #expect(abs(geometry.viewportPosition(time,scrollOffset:offset)-localX)<0.002)
            }
            #expect(geometry.time(atViewportX:width-40,scrollOffset:offset) == end)
            #expect(abs(geometry.viewportPosition(end,scrollOffset:offset)-(width-40))<0.002)
        }
    }

    @Test func cutNavigationIncludesOtherTracksAndProjectBounds() {
        var project = Project(name: "Navigation")
        project.insertAsset(video, kind: .main, at: 0)
        project.insertAsset(audio, kind: .audio, at: 2_000_000)
        #expect(project.adjacentCut(to: 0, forward: false) == 0)
        #expect(project.adjacentCut(to: 0, forward: true) == 2_000_000)
        #expect(project.adjacentCut(to: 2_000_000, forward: true) == 5_000_000)
        #expect(project.adjacentCut(to: 6_000_000, forward: true) == 6_000_000)
        #expect(project.adjacentCut(to: 6_000_000, forward: false) == 5_000_000)
    }
}
