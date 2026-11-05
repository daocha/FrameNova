import AVFoundation
import SwiftUI

@MainActor final class EditorModel: ObservableObject {
    @Published var project: Project
    @Published private var selection: String?
    @Published private(set) var selectedIDs:Set<String> = []
    var selected: String? {
        get {selection}
        set {
            let next = newValue.flatMap {project.track($0)?.locked == false ? $0:nil}
            if selection != next || selectedIDs != Set(next.map {[$0]} ?? []) {
                selection = next;selectedIDs = Set(next.map {[$0]} ?? []);selectedGap = nil
            }
        }
    }
    func selectClip(_ id:String,extending:Bool = false) {
        guard project.track(id)?.locked == false else {return}
        if !extending {if !selectedIDs.contains(id) {selected = id};return}
        var ids = selectedIDs
        if ids.contains(id) {ids.remove(id)} else {ids.insert(id)}
        selectedIDs = ids
        selection = ids.contains(id) ? id:selection.flatMap {ids.contains($0) ? $0:nil} ?? project.tracks.lazy.flatMap(\.clips).first {ids.contains($0.id)}?.id
        selectedGap = nil
    }
    func selectAllClips() {
        selectedIDs = Set(project.tracks.filter {!$0.locked}.flatMap(\.clips).map(\.id))
        selection = project.tracks.lazy.flatMap(\.clips).first {selectedIDs.contains($0.id)}?.id
        selectedGap = nil
    }
    @Published var selectedGap: Int64?
    @Published var playhead: Int64 = 0
    @Published var playing = false
    @Published var error: String? {didSet {if let error {AppLog.record(error)}}}
    @Published var busy = false
    @Published var importStatus:String?
    @Published var revision = 0
    @Published var recording = false
    @Published var recordingLevel = 0.0
    @Published var recordingElapsed = 0.0
    private var recordingMeter:Task<Void,Never>?
    @Published var shareURL:URL?
    private var gestureStart:Project?
    private var previewState:PreviewProjectState?
    let player = AVPlayer()
    let exporter = Exporter()
    let store: ProjectStore
    private var undoStack: [Project] = [], redoStack: [Project] = []
    private var rebuild: Task<Void,Never>?
    private var keyboardSeek = KeyboardSeekCursor()
    private var keyboardSeekIdle:Task<Void,Never>?
    private var seekInProgress = false
    private var pendingSeek:Int64?
    private var pendingSeekPrecise = true
    private var seekGeneration = 0
    private var observer: Any?
    private var recorder: AVAudioRecorder?
    private var recordStart: Int64 = 0
    private var endObserver: NSObjectProtocol?
    init(project:Project,store:ProjectStore) {
        self.project = project; self.store = store
        observer = player.addPeriodicTimeObserver(forInterval:CMTime(value:1,timescale:30),queue:.main) { [weak self] _ in
            Task { @MainActor in
                guard let self,self.playing,self.keyboardSeek.target == nil,!self.seekInProgress,self.pendingSeek == nil else {return}
                let seconds = self.player.currentTime().seconds
                if seconds.isFinite {self.playhead = clamp(Int64(max(0,seconds)*1_000_000),0,self.project.durationUs)}
            }
        }
        endObserver = NotificationCenter.default.addObserver(forName:.AVPlayerItemDidPlayToEndTime,object:nil,queue:.main) { [weak self] notification in
            Task { @MainActor in guard let self, notification.object as? AVPlayerItem === self.player.currentItem else { return }; self.playing = false }
        }
        TimelineThumbnails.shared.prepare(project.assets)
        schedulePreview()
    }
    var clip: Clip? { selectedIDs.count<=1 ? project.clip(selected):nil }
    var canUndo: Bool { !undoStack.isEmpty }; var canRedo: Bool { !redoStack.isEmpty }
    func change(_ body:(inout Project)->Void) {
        let old = project; body(&project)
        guard old != project else { return }
        guard old.tracks.filter(\.locked).allSatisfy({track in project.tracks.first(where:{$0.id == track.id})?.clips == track.clips}) else {project = old;return}
        if old.assets != project.assets {TimelineThumbnails.shared.prepare(project.assets)}
        if gestureStart == nil {undoStack.append(old); if undoStack.count > 100 {undoStack.removeFirst()}}; redoStack = []
        reconcileSelection()
        revision += 1
        var lockUpdate = old
        lockUpdate.coverAssetID = project.coverAssetID
        if old.tracks.map(\.id) == project.tracks.map(\.id) {
            for i in lockUpdate.tracks.indices {lockUpdate.tracks[i].locked = project.tracks[i].locked}
        }
        if lockUpdate == project {persist()}
        else if gestureStart != nil && old.usesSameComposition(as:project) {refreshVisualPreview()}
        else {persist();schedulePreview()}
    }
    func beginGesture() {if gestureStart == nil {gestureStart = project}}
    func endGesture() {
        if let old = gestureStart,old != project {undoStack.append(old);if undoStack.count>100 {undoStack.removeFirst()};redoStack = [];persist()}
        gestureStart = nil
    }
    func liveVisualEdit(_ body:(inout Clip)->Void) {
        guard let id = selected,canEditSelection else {return}
        beginGesture();change {$0.update(id,body)}
    }
    private func refreshVisualPreview() {
        previewState?.update(project)
        if let video = player.currentItem?.videoComposition {player.currentItem?.videoComposition = video.mutableCopy() as? AVVideoComposition}
        seek(playhead)
    }

    func edit(_ body:(inout Clip)->Void) {
        guard let id = selected, canEditSelection else { return }
        change { $0.update(id,body) }
    }
    func undo() { guard let p = undoStack.popLast() else { return }; redoStack.append(project); project = p;reconcileSelection(); persist(); revision += 1; schedulePreview() }
    func redo() { guard let p = redoStack.popLast() else { return }; undoStack.append(project); project = p;reconcileSelection(); persist(); revision += 1; schedulePreview() }
    private func reconcileSelection() {
        let valid = selectedIDs.filter {project.track($0)?.locked == false}
        if valid != selectedIDs {selectedIDs = valid}
        if let selection,!selectedIDs.contains(selection) {self.selection = project.tracks.lazy.flatMap(\.clips).first {selectedIDs.contains($0.id)}?.id}
        if let selectedGap,project.tracks[project.mainIndex].locked || project.mainGap(at:selectedGap) == nil {self.selectedGap = nil}
        playhead = clamp(playhead,0,project.durationUs)
    }
    func persist() { do { try store.save(project) } catch { self.error = error.localizedDescription } }
    func schedulePreview() {
        cancelKeyboardSeek()
        rebuild?.cancel(); player.pause(); playing = false; seekGeneration += 1; seekInProgress = false; pendingSeek = nil
        let snapshot = project
        let state = PreviewProjectState(snapshot);previewState = state
        rebuild = Task {
            do {
                try await Task.sleep(nanoseconds:160_000_000)
                guard snapshot.durationUs > 0 else { player.replaceCurrentItem(with:nil); return }
                let built = try await CompositionFactory.build(snapshot,previewState:state)
                try Task.checkCancellation()
                let resume = playing
                player.replaceCurrentItem(with:built.playerItem()); seek(min(playhead,snapshot.durationUs))
                if resume {player.play()}
            } catch is CancellationError {} catch { self.error = error.localizedDescription }
        }
    }
    func seek(_ time:Int64,precise:Bool = true) {
        cancelKeyboardSeek()
        requestSeek(time,precise:precise)
    }
    func seekWithKeyboard(_ direction:Int,repeating:Bool? = nil,largerStep:Bool = false) {
        let target = keyboardSeek.step(from:playhead,direction:direction,repeating:repeating,
            time:ProcessInfo.processInfo.systemUptime,fps:project.canvas.fps,playing:playing,
            largerStep:largerStep,duration:project.durationUs)
        requestSeek(target)
        keyboardSeekIdle?.cancel()
        keyboardSeekIdle = Task {[weak self] in
            do {try await Task.sleep(nanoseconds:300_000_000)} catch {return}
            self?.finishKeyboardSeek()
        }
    }
    func finishKeyboardSeek() {
        keyboardSeekIdle?.cancel();keyboardSeekIdle = nil
        if let target = keyboardSeek.finish() {requestSeek(target)}
    }
    private func cancelKeyboardSeek() {
        keyboardSeekIdle?.cancel();keyboardSeekIdle = nil;keyboardSeek.finish()
    }
    private func requestSeek(_ time:Int64,precise:Bool = true) {
        playhead = clamp(time,0,project.durationUs)
        pendingSeek = playhead
        pendingSeekPrecise = precise
        flushSeek()
    }
    func scrub(_ time:Int64) {
        if playing {player.pause();playing = false}
        seek(time,precise:false)
    }
    func finishScrub() {seek(playhead)}
    private func flushSeek() {
        guard !seekInProgress,player.currentItem != nil,let time = pendingSeek else {return}
        pendingSeek = nil;seekInProgress = true
        let generation = seekGeneration
        let tolerance = pendingSeekPrecise ? CMTime.zero:CMTime(value:1,timescale:Int32(max(1,project.canvas.fps)))
        player.seek(to:mediaTime(time),toleranceBefore:tolerance,toleranceAfter:tolerance) {[weak self] _ in
            Task {@MainActor in
                guard let self,self.seekGeneration == generation else {return}
                self.seekInProgress = false;self.flushSeek()
            }
        }
    }
    func play() {
        guard project.durationUs>0 else {return}
        if playing { player.pause(); playing = false }
        else { if playhead >= project.durationUs { seek(0) }; player.play(); playing = true }
    }
    func close() {
        cancelKeyboardSeek()
        if recording {toggleRecording()}
        rebuild?.cancel();player.pause();persist()
        let snapshot = project
        Task {[store] in _ = await store.cover(snapshot)}
        if let observer {player.removeTimeObserver(observer);self.observer = nil}
        if let endObserver {NotificationCenter.default.removeObserver(endObserver);self.endObserver = nil}
        recorder?.stop()
    }
    func split() {
        guard selectedIDs.count<=1,let id = selected ?? project.tracks[project.mainIndex].clips.first(where: {$0.contains(playhead)})?.id,project.track(id)?.locked != true else {return}
        var next:String?
        change {next = $0.split(id,at:playhead)}
        selected = next ?? id
    }
    var canDeleteSelection:Bool {!selectedIDs.isEmpty && selectedIDs.allSatisfy {project.track($0)?.locked == false}}
    func delete() {
        guard canDeleteSelection else {return}
        let ids = selectedIDs
        change {p in for index in p.tracks.indices {p.tracks[index].clips.removeAll {ids.contains($0.id)}};p.normalize()}
        selected = nil
    }
    func addText(_ role:String,content:String? = nil) {
        var style = TextStyle();style.role = role
        if role == "Subtitle" {style.text = content ?? "Subtitle";style.size = 0.055;style.strokeWidth = 0.08}
        else if role == "Sticker" {style.text = content ?? "⭐";style.size = content == nil ? 0.18:0.2;style.bold = false;style.shadow = false}
        else {style.text = content ?? "Your title";style.size = 0.09}
        let c = Clip(startUs:playhead,transform:Transform(cy:role == "Subtitle" ? 0.86:0.5),text:style)
        change { $0.place(c,kind:.text) }; selected = c.id
    }
    func ingest(_ urls:[URL],kind:TrackKind,replace:Bool = false,subtitles:Bool = false,libraryOnly:Bool = false) {
        let scoped = urls.filter {$0.startAccessingSecurityScopedResource()}
        busy = true;importStatus = "Importing \(urls.count) files…"
        AppLog.record("Import started: \(urls.count) files, library=\(libraryOnly)")
        Task {
            defer {busy = false;scoped.forEach {$0.stopAccessingSecurityScopedResource()}}
            do {
                if subtitles {
                    for url in urls {
                        let access = url.startAccessingSecurityScopedResource(); defer { if access { url.stopAccessingSecurityScopedResource() } }
                        let cues = Subtitles.parse(try String(contentsOf:url,encoding:.utf8),filename:url.lastPathComponent)
                        guard !cues.isEmpty else { throw MediaError.invalid }; change { $0.addSubtitles(cues) }
                    }
                    importStatus = "Imported subtitles"
                } else {
                    var assets: [MediaAsset] = []
                    var failures:[String] = []
                    for url in urls {
                        do {assets.append(try await ProjectStore.ingest(url))}
                        catch {failures.append("\(url.lastPathComponent): \(error.localizedDescription)")}
                    }
                    imported(assets,kind:kind,replace:replace,libraryOnly:libraryOnly)
                    importStatus = failures.isEmpty ? "Imported \(assets.count) files":"Imported \(assets.count) of \(urls.count) files. \(failures.joined(separator:"; "))"
                    AppLog.record("\(importStatus ?? ""); library now has \(project.assets.count) assets")
                    if !failures.isEmpty {error = failures.joined(separator:"\n")}
                }
            } catch {importStatus = "Import failed: \(error.localizedDescription)";AppLog.record(importStatus ?? "Import failed");self.error = error.localizedDescription}
        }
    }
    func imported(_ assets:[MediaAsset],kind:TrackKind,replace:Bool = false,libraryOnly:Bool = false) {
        if libraryOnly {change {$0.addLibraryAssets(assets)}; return}
        if replace, let a = assets.first, let id = selected {
            change { p in
                p.addLibraryAssets([a]);p.update(id) {c in let range = c.srcOutUs-c.srcInUs;c.assetID = a.id;c.srcInUs = 0;c.srcOutUs = a.type == .image ? range:min(a.durationUs,range);c.crop = CropRect()}
            }
        } else { change { $0.add(assets,kind:kind,at:playhead) } }
    }
    var canEditSelection: Bool {selectedIDs.count == 1 && (selected.map {project.clip($0) != nil && project.track($0)?.locked != true} ?? false)}
    func duplicateSelected() {
        guard canDeleteSelection else {return}
        let ids = project.tracks.flatMap(\.clips).filter {selectedIDs.contains($0.id)}.map(\.id)
        var copies:[String] = []
        change {p in for id in ids {if let copy = p.duplicate(id) {copies.append(copy)}}}
        selectedIDs = Set(copies);selection = copies.last
    }
    func moveSelectionToLayer() {
        guard canDeleteSelection else {return}
        let ids = project.tracks.flatMap(\.clips).filter {selectedIDs.contains($0.id)}.map(\.id)
        change {p in for id in ids {p.moveToNewLayer(id)}}
    }
    func insert(_ asset:MediaAsset,kind:TrackKind? = nil,trackID:String? = nil,at time:Int64? = nil) {
        let destination = kind ?? (asset.type == .audio ? .audio:.main)
        var inserted:String?
        change {p in
            if let id = p.insertAsset(asset,kind:destination,trackID:trackID,at:time ?? playhead) {inserted = id}
            else {error = "This media cannot be added to that track. Check the track type and lock."}
        }
        if let inserted {selected = inserted}
    }
    func stepFrames(_ frames:Int) {seek(playhead+Int64(frames)*1_000_000/Int64(project.canvas.fps))}
    func trimToPlayhead(start:Bool) {
        guard let clip, clip.contains(playhead), canEditSelection else {return}
        change {if start {$0.trimStart(clip.id,delta:playhead-clip.startUs)} else {$0.trimEnd(clip.id,delta:playhead-clip.endUs)}}
    }
    func extractAudio() {
        guard let id = clip?.id,canEditSelection else {return}
        var extracted:String?
        change {extracted = $0.extractAudio(id)}
        if let extracted {selected = extracted}
    }
    func saveAudio() {
        guard let c = clip, let media = project.asset(c.assetID), media.hasAudio else {return}
        busy = true
        Task {
            defer {busy = false}
            do {
                var audio = c; audio.startUs = 0; audio.audioOnly = true; audio.transitionIn = nil
                var p = Project(name:"Audio",canvas:project.canvas,assets:[media]); p.tracks.append(Track(kind:.audio,clips:[audio]))
                let built = try await CompositionFactory.build(p)
                guard let session = AVAssetExportSession(asset:built.asset,presetName:AVAssetExportPresetAppleM4A) else {throw MediaError.export}
                let url = FileManager.default.temporaryDirectory.appendingPathComponent("FrameNova-"+newID()+".m4a")
                session.outputURL = url; session.outputFileType = .m4a; session.audioMix = built.audio
                await session.export()
                guard session.status == .completed else {throw session.error ?? MediaError.export}
                shareURL = url
            } catch {self.error = error.localizedDescription}
        }
    }
    func freeze() {
        guard let c = clip ?? project.tracks[project.mainIndex].clips.first(where: { $0.contains(playhead) }), let media = project.asset(c.assetID), media.type == .video else { return }
        busy = true
        Task {
            defer { busy = false }
            do {
                let generator = AVAssetImageGenerator(asset:AVURLAsset(url:ProjectStore.mediaURL(media.path))); generator.appliesPreferredTrackTransform = true
                let result = try await generator.image(at:mediaTime(c.sourceTime(at:playhead)))
                guard let data = UIImage(cgImage:result.image).pngData() else { throw MediaError.invalid }
                let path = newID()+".png"; try data.write(to:ProjectStore.mediaURL(path))
                let a = MediaAsset(path:path,type:.image,name:"Freeze frame",durationUs:2_000_000,width:result.image.width,height:result.image.height)
                change { p in
                    p.assets.append(a); var still = c; still.id = newID(); still.assetID = a.id; still.srcInUs = 0; still.srcOutUs = 2_000_000; still.speed = 1; still.keyframes = []; still.transitionIn = nil
                    if p.track(c.id)?.kind == .main { let second = p.split(c.id,at:playhead); p.insertMain([still],at:second != nil ? playhead:c.endUs) }
                    else { still.startUs = playhead; p.place(still,kind:.overlay) }
                }
            } catch { self.error = error.localizedDescription }
        }
    }
    func toggleRecording() {
        if recording {
            recorder?.stop(); recording = false;recordingMeter?.cancel();recordingMeter = nil;recordingLevel = 0;player.pause();playing = false;player.isMuted = false
            try? AVAudioSession.sharedInstance().setCategory(.playback,mode:.moviePlayback)
            guard let url = recorder?.url else { return }; recorder = nil
            Task {
                defer {try? FileManager.default.removeItem(at:url)}
                do {
                    var asset = try await ProjectStore.ingest(url);asset.name = "Voiceover"
                    let before = Set(project.tracks.flatMap(\.clips).map(\.id))
                    change {$0.add([asset],kind:.audio,at:recordStart)}
                    selected = project.tracks.flatMap(\.clips).first(where:{!before.contains($0.id)})?.id
                } catch {self.error = error.localizedDescription}
            }
            return
        }
        Task {
            let granted = await withCheckedContinuation { continuation in AVAudioSession.sharedInstance().requestRecordPermission { continuation.resume(returning:$0) } }
            guard granted else { error = "Allow microphone access in Settings to record a voiceover."; return }
            do {
                player.pause(); playing = false
                try AVAudioSession.sharedInstance().setCategory(.playAndRecord,mode:.default,options:[.defaultToSpeaker,.allowBluetooth])
                try AVAudioSession.sharedInstance().setActive(true)
                let url = FileManager.default.temporaryDirectory.appendingPathComponent(newID()+".m4a")
                recorder = try AVAudioRecorder(url:url,settings:[AVFormatIDKey:kAudioFormatMPEG4AAC,AVSampleRateKey:48000,AVNumberOfChannelsKey:1,AVEncoderBitRateKey:128000]); recordStart = playhead
                recorder?.isMeteringEnabled = true;recordingElapsed = 0
                recording = recorder?.record() == true
                guard recording else {throw MediaError.invalid}
                player.isMuted = true
                if project.durationUs>playhead {player.play();playing = true}
                recordingMeter = Task {[weak self] in
                    while !Task.isCancelled {
                        guard let self,self.recording,let recorder = self.recorder else {return}
                        recorder.updateMeters();self.recordingLevel = clamp(pow(10,Double(recorder.averagePower(forChannel:0))/20),0,1)
                        self.recordingElapsed = recorder.currentTime
                        try? await Task.sleep(nanoseconds:60_000_000)
                    }
                }
            } catch {recording = false;player.isMuted = false;self.error = error.localizedDescription}
        }
    }
}
