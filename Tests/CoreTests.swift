import XCTest
@testable import JalkapalloTilastot

final class CoreTests: XCTestCase {
    func testTeamKeyIgnoresPrefixesAndDiacritics() {
        XCTAssertEqual(TeamNames.key("Manchester City FC"), TeamNames.key("Man City"))
        XCTAssertEqual(TeamNames.key("FC Barcelona"), TeamNames.key("Barcelona"))
        XCTAssertEqual(TeamNames.key("Club Atlético de Madrid"), TeamNames.key("Atlético Madrid"))
    }

    func testShotOutsideBox() {
        let inside = Shot(x: 0.95, y: 0.5, xG: 0.3, minute: 10, result: .goal)
        let outside = Shot(x: 0.70, y: 0.5, xG: 0.04, minute: 20, result: .missed)
        XCTAssertFalse(inside.isOutsideBox)
        XCTAssertTrue(outside.isOutsideBox)
    }

    func testFlagForKnownCountry() {
        XCTAssertFalse(Nationality.flag(for: "Finland").isEmpty)
    }
}
