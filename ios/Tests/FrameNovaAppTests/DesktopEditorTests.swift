import Testing
import Foundation
@testable import FrameNova

@Suite(.serialized) @MainActor struct DesktopEditorTests {
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
        #expect(!model.canEditSelection)
        model.split(); model.duplicateSelected(); model.delete(); model.trimToPlayhead(start: true)
        #expect(model.project == project)
        #expect(!model.canUndo)
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
