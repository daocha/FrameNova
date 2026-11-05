import Testing
import Foundation
@testable import FrameNova

@Suite(.serialized) @MainActor struct DesktopEditorTests {
    @Test func commandSelectionSpansTrackTypesAndDeleteIsOneUndoStep() {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(newID())
        let store = ProjectStore(directory:folder)
        var project = Project(name:"Multiple selection")
        project.tracks = [Track(id:"overlay",kind:.overlay,clips:[Clip(id:"layer")]),
            Track(id:"main",kind:.main,clips:[Clip(id:"video")]),
            Track(id:"audio",kind:.audio,clips:[Clip(id:"sound",audioOnly:true)]),
            Track(id:"locked",kind:.text,clips:[Clip(id:"locked-clip",text:TextStyle())],locked:true)]
        let model = EditorModel(project:project,store:store)
        defer {model.close();try? FileManager.default.removeItem(at:folder)}
        model.selected = "video"
        model.selectClip("layer",extending:true);model.selectClip("sound",extending:true)
        model.selectClip("locked-clip",extending:true)
        #expect(model.selectedIDs == ["video","layer","sound"])
        #expect(model.canDeleteSelection && !model.canEditSelection)
        model.selectClip("layer",extending:true)
        #expect(model.selectedIDs == ["video","sound"])
        model.selectClip("layer",extending:true)
        model.delete()
        #expect(model.project.clip("video") == nil && model.project.clip("layer") == nil && model.project.clip("sound") == nil)
        #expect(model.project.clip("locked-clip") != nil)
        model.undo();#expect(model.project == project);#expect(!model.canUndo)
        model.redo();#expect(model.project.clip("video") == nil)
    }

    @Test func selectAllSkipsLockedClipsAndDuplicateKeepsMultipleSelection() {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(newID())
        let store = ProjectStore(directory:folder)
        var project = Project(name:"Selection actions")
        project.tracks[0].clips = [Clip(id:"a"),Clip(id:"b",startUs:3_000_000)]
        project.tracks.append(Track(kind:.audio,clips:[Clip(id:"locked",audioOnly:true)],locked:true))
        let model = EditorModel(project:project,store:store)
        defer {model.close();try? FileManager.default.removeItem(at:folder)}
        model.selectAllClips();#expect(model.selectedIDs == ["a","b"])
        model.duplicateSelected()
        #expect(model.selectedIDs.count == 2)
        #expect(model.selectedIDs.isDisjoint(with:["a","b","locked"]))
        model.undo();#expect(model.project == project)
        model.selected = "a";model.selectClip("b",extending:true)
        model.change {$0.tracks[0].locked = true}
        #expect(model.selectedIDs.isEmpty && model.selected == nil)
    }

    @Test func libraryImportIsSavedWithoutAddingClipsAndSupportsUndo() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(newID())
        let store = ProjectStore(directory: folder), project = Project(name: "Desktop import test")
        let model = EditorModel(project: project, store: store)
        defer { model.close(); try? FileManager.default.removeItem(at: folder) }
        let asset = MediaAsset(path: newID()+".png", type: .image, name: "Photo", durationUs: 3_000_000)
        model.imported([asset], kind: .main, libraryOnly: true)
        #expect(model.project.assets == [asset])
        #expect(model.project.durationUs == 0)
        let saved = try #require(store.projects.first(where: { $0.id == project.id }))
        #expect(saved.assets == [asset])
        model.undo()
        #expect(model.project.assets.isEmpty)
        model.redo()
        #expect(model.project.assets == [asset])
    }

    @Test func lockedClipRejectsDesktopEditingActions() {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(newID())
        let store = ProjectStore(directory: folder)
        var project = Project(name: "Desktop lock test")
        project.tracks[0].clips = [Clip(srcOutUs: 5_000_000, text: TextStyle())]
        project.tracks[0].locked = true
        let model = EditorModel(project: project, store: store)
        defer { model.close(); try? FileManager.default.removeItem(at: folder) }
        model.selected = project.tracks[0].clips[0].id; model.seek(2_000_000)
        #expect(model.selected == nil)
        #expect(!model.canEditSelection)
        model.split(); model.duplicateSelected(); model.delete(); model.trimToPlayhead(start: true)
        #expect(model.project == project)
        model.change {$0.tracks[0].clips.removeAll()}
        #expect(model.project == project)
        #expect(!model.canUndo)
        model.change {$0.tracks[0].locked = false}
        model.selected = project.tracks[0].clips[0].id
        model.delete()
        #expect(model.project.tracks[0].clips.isEmpty)
    }

    @Test func lockingSelectedTrackClearsSelectionAndUndoRestoresEditability() {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(newID())
        let store = ProjectStore(directory:folder)
        var project = Project(name:"Track selection")
        project.tracks[0].clips = [Clip(id:"clip",srcOutUs:5_000_000,text:TextStyle())]
        let model = EditorModel(project:project,store:store)
        defer {model.close();try? FileManager.default.removeItem(at:folder)}
        model.selected = "clip"
        model.playing = true
        model.change {$0.tracks[0].locked = true}
        #expect(model.selected == nil)
        #expect(model.playing)
        model.selected = "clip"
        #expect(model.selected == nil)
        model.undo()
        model.selected = "clip"
        #expect(model.canEditSelection)
        model.redo()
        #expect(model.selected == nil)
        #expect(model.project.tracks[0].clips == project.tracks[0].clips)
    }

    @Test func frameSteppingClampsToProjectBounds() {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(newID())
        let store = ProjectStore(directory: folder)
        var project = Project(name: "Desktop seek test")
        project.canvas.fps = 25
        project.tracks[0].clips = [Clip(srcOutUs: 1_000_000, text: TextStyle())]
        let model = EditorModel(project: project, store: store)
        defer { model.close(); try? FileManager.default.removeItem(at: folder) }
        model.stepFrames(-1)
        #expect(model.playhead == 0)
        model.stepFrames(1)
        #expect(model.playhead == 40_000)
        model.stepFrames(100)
        #expect(model.playhead == 1_000_000)
    }
}

@Suite(.serialized) @MainActor struct EditorParityTests {
    @Test func visualGestureMakesOneUndoStepAndKeepsSourceTiming() {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(newID())
        let store = ProjectStore(directory:folder)
        var project = Project(name:"Live edit")
        project.tracks[0].clips = [Clip(id:"clip",srcOutUs:5_000_000,text:TextStyle())]
        let model = EditorModel(project:project,store:store)
        defer {model.close();try? FileManager.default.removeItem(at:folder)}
        model.selected = "clip"
        model.liveVisualEdit {$0.transform.cx = 0.7}
        model.liveVisualEdit {$0.transform.scale = 1.5}
        model.endGesture()
        #expect(model.project.clip("clip")?.srcOutUs == 5_000_000)
        model.undo()
        #expect(model.project == project)
        #expect(!model.canUndo)
        model.redo()
        #expect(model.project.clip("clip")?.transform.scale == 1.5)
    }
    @Test func replacementPreservesSourceRangeSpeedAndResetsCrop() {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(newID())
        let store = ProjectStore(directory:folder)
        let old = MediaAsset(path:newID()+".mov",type:.video,name:"Old",durationUs:10_000_000)
        var project = Project(name:"Replace");project.assets = [old]
        project.tracks[0].clips = [Clip(id:"clip",assetID:old.id,srcInUs:2_000_000,srcOutUs:8_000_000,speed:2,crop:CropRect(left:0.2))]
        let model = EditorModel(project:project,store:store)
        defer {model.close();try? FileManager.default.removeItem(at:folder)}
        model.selected = "clip"
        let photo = MediaAsset(path:newID()+".png",type:.image,name:"New",durationUs:3_000_000)
        model.imported([photo],kind:.main,replace:true)
        #expect(model.clip?.srcInUs == 0);#expect(model.clip?.srcOutUs == 6_000_000)
        #expect(model.clip?.speed == 2);#expect(model.clip?.durationUs == 3_000_000)
        #expect(model.clip?.crop == CropRect())
    }
    @Test func roleDefaultsMatchTitleSubtitleAndStickerTools() {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(newID()),store = ProjectStore(directory:folder)
        let model = EditorModel(project:Project(name:"Roles"),store:store)
        defer {model.close();try? FileManager.default.removeItem(at:folder)}
        model.addText("Title");#expect(model.clip?.text?.text == "Your title");#expect(model.clip?.text?.size == 0.09)
        model.addText("Subtitle");#expect(model.clip?.text?.strokeWidth == 0.08);#expect(model.clip?.transform.cy == 0.86)
        model.addText("Sticker",content:"⭐");#expect(model.clip?.text?.size == 0.2);#expect(model.clip?.text?.shadow == false)
    }
}
