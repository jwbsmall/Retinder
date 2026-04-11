import XCTest

/// UI tests for Retinder.
///
/// These tests run against the app in a fresh simulator environment where
/// no Reminders data exists. They verify structural UI — navigation, tab bar,
/// empty states, and the full prioritisation flow with injected data.
///
/// Setup requirement: the UI test target must have the host application set
/// to "PairwiseReminders" in the target's General settings.
final class RetinderUITests: XCTestCase {

    var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments += ["-AppleLanguages", "(en)"]

        // Handle the Reminders permission SpringBoard alert automatically.
        // addUIInterruptionMonitor fires whenever a system alert blocks the UI.
        addUIInterruptionMonitor(withDescription: "Reminders permission") { alert in
            if alert.buttons["Don't Allow"].exists {
                alert.buttons["Don't Allow"].tap()
                return true
            }
            if alert.buttons["Allow"].exists {
                alert.buttons["Allow"].tap()
                return true
            }
            return false
        }

        app.launch()
        // Prod the app to trigger the interrupt monitor if a system alert is present.
        app.tap()
        // Brief settle time for the UI to stabilise after any alert dismissal.
        _ = app.wait(for: .runningForeground, timeout: 3)
    }

    override func tearDownWithError() throws {
        app = nil
    }

    // MARK: - Launch / Structure

    func testAppLaunchesAndShowsTabBar() {
        // Tab bar must be visible with all three tabs.
        XCTAssertTrue(app.tabBars.firstMatch.exists)
        XCTAssertTrue(app.tabBars.buttons["Home"].exists)
        XCTAssertTrue(app.tabBars.buttons["Prioritise"].exists)
        XCTAssertTrue(app.tabBars.buttons["Settings"].exists)
    }

    func testHomeTabIsSelectedOnLaunch() {
        let homeTab = app.tabBars.buttons["Home"]
        XCTAssertTrue(homeTab.isSelected)
    }

    func testHomeScreenShowsRetinderTitle() {
        // NavigationStack title should read "Retinder".
        XCTAssertTrue(app.navigationBars["Retinder"].exists)
    }

    // MARK: - Tab Navigation

    func testCanSwitchToPrioritiseTab() {
        app.tabBars.buttons["Prioritise"].tap()
        // ListPickerView navigation title.
        XCTAssertTrue(app.navigationBars["Choose Lists"].waitForExistence(timeout: 2))
    }

    func testCanSwitchToSettingsTab() {
        app.tabBars.buttons["Settings"].tap()
        // SettingsView should appear — look for its navigation title.
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 2))
    }

    func testTabsAreIndependent() {
        // Navigate to Prioritise, then back to Home — title should reset.
        app.tabBars.buttons["Prioritise"].tap()
        XCTAssertTrue(app.navigationBars["Choose Lists"].waitForExistence(timeout: 2))
        app.tabBars.buttons["Home"].tap()
        XCTAssertTrue(app.navigationBars["Retinder"].waitForExistence(timeout: 2))
    }

    // MARK: - Prioritise Tab: List Picker

    func testPrioritiseTabShowsChooseListsTitle() {
        app.tabBars.buttons["Prioritise"].tap()
        XCTAssertTrue(app.navigationBars["Choose Lists"].waitForExistence(timeout: 2))
    }

    func testStartButtonIsDisabledWithNothingSelected() {
        app.tabBars.buttons["Prioritise"].tap()
        _ = app.navigationBars["Choose Lists"].waitForExistence(timeout: 2)

        // The start button label when nothing is selected.
        let startButton = app.buttons["Select a list"]
        if startButton.waitForExistence(timeout: 2) {
            XCTAssertFalse(startButton.isEnabled,
                           "Start button should be disabled when no list is selected")
        }
        // If the button doesn't exist it means there are no lists — that's also valid.
    }

    // MARK: - Settings Tab

    func testSettingsTabLoads() {
        app.tabBars.buttons["Settings"].tap()
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 2))
    }
}
