//
//  sheRuntimeUITests.swift
//  sheRuntimeUITests
//
//  Created by ari on 2026/8/27.
//

import XCTest

final class sheRuntimeUITests: XCTestCase {

    override func setUpWithError() throws {
        // Put setup code here. This method is called before the invocation of each test method in the class.

        // In UI tests it is usually best to stop immediately when a failure occurs.
        continueAfterFailure = false

        // In UI tests it’s important to set the initial state - such as interface orientation - required for your tests before they run. The setUp method is a good place to do this.
    }

    override func tearDownWithError() throws {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
    }

    @MainActor
    func testExample() throws {
        // UI tests must launch the application that they test.
        let app = XCUIApplication()
        app.launch()

        // Use XCTAssert and related functions to verify your tests produce the correct results.
        // XCUIAutomation Documentation
        // https://developer.apple.com/documentation/xcuiautomation
    }

    @MainActor
    func testGlobalVoiceRecordingUsesImmersiveControls() throws {
        let app = XCUIApplication()
        app.launchArguments += ["-voiceCaptureCoachmarkSeen", "YES"]
        app.launchEnvironment["SHOT_PAGE"] = "0"
        app.launch()

        let voiceEntry = app.buttons["随手语音记录"]
        XCTAssertTrue(voiceEntry.waitForExistence(timeout: 3))
        voiceEntry.tap()

        let microphoneAlert = app.alerts.firstMatch
        if microphoneAlert.waitForExistence(timeout: 1) {
            let allowButton = microphoneAlert.buttons.matching(
                NSPredicate(format: "label CONTAINS '允许' OR label CONTAINS 'Allow'")
            ).firstMatch
            if allowButton.exists { allowButton.tap() }
        }

        XCTAssertTrue(app.staticTexts["Robo正在听～"].waitForExistence(timeout: 4))
        XCTAssertTrue(app.buttons["取消"].exists)
        XCTAssertTrue(app.buttons["说完了"].exists)
        XCTAssertFalse(app.buttons["今日"].exists)
        XCTAssertFalse(app.buttons["地图"].exists)
        XCTAssertFalse(app.buttons["洞察"].exists)
        XCTAssertFalse(app.buttons["问问"].exists)

        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "Immersive voice recording"
        attachment.lifetime = .keepAlways
        add(attachment)

        app.buttons["取消"].tap()
        XCTAssertTrue(app.staticTexts["已取消本次记录"].waitForExistence(timeout: 2))
    }

    @MainActor
    func testVoiceEntryRemainsAvailableOnAskTab() throws {
        let app = XCUIApplication()
        app.launchArguments += ["-voiceCaptureCoachmarkSeen", "YES"]
        app.launchEnvironment["SHOT_PAGE"] = "3"
        app.launch()

        XCTAssertTrue(app.buttons["随手语音记录"].waitForExistence(timeout: 3))
    }

    @MainActor
    func testLaunchPerformance() throws {
        // This measures how long it takes to launch your application.
        measure(metrics: [XCTApplicationLaunchMetric()]) {
            XCUIApplication().launch()
        }
    }
}
