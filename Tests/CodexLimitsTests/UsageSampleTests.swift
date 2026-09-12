import XCTest
@testable import CodexLimits

final class UsageSampleTests: XCTestCase {
    func testLegacyDateKeyAndMissingDurationStillDecode() throws {
        let json = Data(#"{"date": 100, "remainingPercent": 80, "resetsAt": 200}"#.utf8)
        let reading = try JSONDecoder().decode(UsageSample.self, from: json)
        XCTAssertEqual(reading.observedAt, Date(timeIntervalSinceReferenceDate: 100))
        XCTAssertNil(reading.durationMinutes)
    }

    func testWindowDurationSurvivesPersistence() throws {
        let reading = UsageSample(observedAt: Date(timeIntervalSinceReferenceDate: 100), remainingPercent: 80,
                                  resetsAt: Date(timeIntervalSinceReferenceDate: 200), durationMinutes: 300)
        let decoded = try JSONDecoder().decode(UsageSample.self, from: JSONEncoder().encode(reading))
        XCTAssertEqual(decoded, reading)
    }
}
