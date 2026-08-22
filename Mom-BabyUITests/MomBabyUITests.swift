import XCTest

final class MomBabyUITests: XCTestCase {
    @MainActor
    func testAppLaunchesIntoAProtectedExperienceRoot() {
        let app = XCUIApplication()
        app.launch()

        let onboarding = app.otherElements["onboarding.root"]
        if onboarding.waitForExistence(timeout: 15) {
            XCTAssertTrue(app.otherElements["onboarding.welcome"].exists)
        } else {
            XCTAssertTrue(app.scrollViews["today.root"].waitForExistence(timeout: 2))
        }
    }
}
