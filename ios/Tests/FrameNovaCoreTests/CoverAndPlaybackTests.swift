import Foundation
import Testing
@testable import FrameNovaCore

@Suite struct CoverAndPlaybackTests {
    @Test func heldArrowsAccelerateAndNewPressResets() {
        var repeatSeek = PlaybackKeyRepeat()
        let steps = [
            repeatSeek.frames(direction:1,repeating:false,time:10),
            repeatSeek.frames(direction:1,repeating:true,time:10.5),
            repeatSeek.frames(direction:1,repeating:true,time:11.5),
            repeatSeek.frames(direction:1,repeating:true,time:12.1),
            repeatSeek.frames(direction:-1,repeating:true,time:12.2),
            repeatSeek.frames(direction:-1,repeating:false,time:15)
        ]
        #expect(steps == [1,3,10,30,-1,-1])
    }
    @Test func openingCoverShiftsEveryTrackWithoutChangingSourceTiming() throws {
        let image = MediaAsset(path:"cover.png",type:.image,name:"Cover",durationUs:3_000_000)
        var project = Project(name:"Cover")
        project.assets = [image];project.coverAssetID = image.id
        project.tracks[0].clips = [Clip(id:"video",startUs:1_000_000,srcInUs:2_000_000,srcOutUs:6_000_000)]
        project.tracks.append(Track(kind:.audio,clips:[Clip(id:"audio",startUs:500_000,srcOutUs:5_000_000)]))
        project.tracks.append(Track(id:"emptyLocked",kind:.overlay,locked:true))
        let inserted = project.prependCover()
        #expect(project.tracks.contains {$0.id == "emptyLocked" && $0.locked && $0.clips.isEmpty})
        let id = try #require(inserted)
        #expect(project.clip(id)?.startUs == 0)
        #expect(project.clip(id)?.durationUs == 3_000_000)
        #expect(project.clip("video")?.startUs == 4_000_000)
        #expect(project.clip("video")?.srcInUs == 2_000_000)
        #expect(project.clip("audio")?.startUs == 3_500_000)
    }
    @Test func coverCannotShiftLockedClipsAndOldProjectsStillDecode() throws {
        let old = Project(name:"Old")
        var data = try #require(JSONSerialization.jsonObject(with:JSONEncoder().encode(old)) as? [String:Any])
        data.removeValue(forKey:"coverAssetID")
        let decoded = try JSONDecoder().decode(Project.self,from:JSONSerialization.data(withJSONObject:data))
        #expect(decoded.coverAssetID == nil)
        let image = MediaAsset(path:"cover.png",type:.image,name:"Cover",durationUs:3_000_000)
        var project = decoded
        project.assets = [image];project.coverAssetID = image.id
        project.tracks[0].locked = true
        let before = project
        let inserted = project.prependCover()
        #expect(inserted == nil)
        #expect(project == before)
    }
}
