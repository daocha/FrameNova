import XCTest

final class EditorInteractionTests:XCTestCase {
    private var app:XCUIApplication!
    override func setUpWithError() throws {
        continueAfterFailure = false;XCUIDevice.shared.orientation = .portrait
        app = XCUIApplication();app.launchArguments = ["--editor-ui-fixture"];app.launch()
    }
    private func timeline()->XCUIElement {
        let view = app.otherElements["editor.touchTimeline"]
        XCTAssertTrue(view.waitForExistence(timeout:10));return view
    }
    private func point(_ view:XCUIElement,x:CGFloat,y:CGFloat)->XCUICoordinate {
        view.coordinate(withNormalizedOffset:.zero).withOffset(CGVector(dx:x,dy:y))
    }
    private func waitForValue(_ view:XCUIElement,contains:String) {
        let predicate = NSPredicate(format:"value CONTAINS %@",contains)
        expectation(for:predicate,evaluatedWith:view);waitForExpectations(timeout:5)
    }
    func testSwipeMovesTimeUnderFixedPlayhead() {
        let view = timeline(),start = point(view,x:view.frame.width/2+40,y:55)
        start.press(forDuration:0.05,thenDragTo:start.withOffset(CGVector(dx:-100,dy:0)))
        let predicate = NSPredicate(format:"NOT (value BEGINSWITH %@)","Playhead 00:00")
        expectation(for:predicate,evaluatedWith:view);waitForExpectations(timeout:5)
    }
    func testLockClearsSelectionAndPreventsTimelineAndPreviewSelection() {
        let view = timeline(),clip = point(view,x:view.frame.width/2+35,y:55)
        clip.tap()
        waitForValue(view,contains:"Start")
        let lock = point(view,x:45,y:55)
        lock.tap()
        let noSelection = NSPredicate(format:"NOT (value CONTAINS %@)","Start")
        expectation(for:noSelection,evaluatedWith:view);waitForExpectations(timeout:5)
        clip.tap()
        XCTAssertFalse((view.value as? String ?? "").contains("Start"))
        app.otherElements["editor.preview"].tap()
        XCTAssertFalse((view.value as? String ?? "").contains("Start"))
        lock.tap();clip.tap()
        waitForValue(view,contains:"Start")
    }
    func testLongPressMovesClipInsteadOfScrollingTimeline() {
        let view = timeline(),start = point(view,x:view.frame.width/2+35,y:55)
        start.tap()
        start.press(forDuration:0.6,thenDragTo:start.withOffset(CGVector(dx:77,dy:0)))
        waitForValue(view,contains:"Start 00:01; End 00:11")
        waitForValue(view,contains:"Playhead 00:00")
    }
    func testTrimHandleChangesSourceRangeAndKeepsEnd() {
        let view = timeline()
        point(view,x:view.frame.width/2+35,y:55).tap()
        let handle = point(view,x:view.frame.width/2,y:55)
        handle.press(forDuration:0.05,thenDragTo:handle.withOffset(CGVector(dx:77,dy:0)))
        waitForValue(view,contains:"Start 00:01; End 00:10")
    }
    func testLayoutPanelShowsNamedVisualPresets() {
        let tool = app.buttons["Layout"],tools = app.scrollViews["editor.tools"]
        for _ in 0..<8 {if tool.isHittable {break};tools.swipeLeft()}
        XCTAssertTrue(tool.isHittable);tool.tap()
        XCTAssertTrue(app.buttons["Side by side"].waitForExistence(timeout:5))
        app.buttons["Side by side"].tap()
        XCTAssertTrue(app.buttons["Done"].isHittable)
    }
    func testMediaPickerHasLibraryPhotosAndVideos() {
        let media = app.buttons["Media"];XCTAssertTrue(media.waitForExistence(timeout:5));media.tap()
        let permission = XCUIApplication(bundleIdentifier:"com.apple.springboard").alerts.firstMatch
        if permission.waitForExistence(timeout:2),permission.buttons["Don’t Allow"].exists {permission.buttons["Don’t Allow"].tap()}
        else if permission.exists,permission.buttons["Don't Allow"].exists {permission.buttons["Don't Allow"].tap()}
        let filters = app.segmentedControls["media.filters"]
        XCTAssertTrue(filters.waitForExistence(timeout:5))
        XCTAssertTrue(filters.buttons["Library"].exists)
        XCTAssertTrue(filters.buttons["Photos"].exists)
        XCTAssertTrue(filters.buttons["Videos"].exists)
    }
    func testFormatSummaryTogglesSettingsAndTitleStillRenames() {
        let view = timeline()
        point(view,x:view.frame.width/2+35,y:55).tap()
        let toggle = app.buttons["editor.projectFormat"]
        XCTAssertTrue(toggle.exists);XCTAssertEqual(toggle.label,"Show project format")
        toggle.tap()
        XCTAssertEqual(toggle.label,"Hide project format")
        let settings = app.scrollViews["editor.canvasSettings"]
        XCTAssertTrue(settings.waitForExistence(timeout:5))
        XCTAssertFalse((view.value as? String ?? "").contains("Start"))
        app.buttons["9:16"].tap()
        let resolution = app.buttons["4K"]
        for _ in 0..<4 {if resolution.isHittable {break};settings.swipeUp()}
        XCTAssertTrue(resolution.isHittable);resolution.tap()
        XCTAssertTrue((toggle.value as? String ?? "").contains("9:16 · 4K"))
        toggle.tap()
        XCTAssertEqual(toggle.label,"Show project format")
        app.buttons["editor.projectName"].tap()
        XCTAssertTrue(app.alerts["Rename project"].waitForExistence(timeout:5))
    }
}
