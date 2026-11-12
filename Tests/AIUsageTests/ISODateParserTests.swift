import XCTest
@testable import AIUsage

final class ISODateParserTests: XCTestCase {
    func testUTCAndTimeZoneOffsetsRepresentTheSameInstant() throws {
        let utc = try XCTUnwrap(ISODateParser.parse("2026-11-13T00:00:00Z"))
        XCTAssertEqual(ISODateParser.parse("2026-11-13T08:00:00+08:00"), utc)
        XCTAssertEqual(ISODateParser.parse("2026-11-12T19:00:00-05:00"), utc)
    }

    func testFractionalSecondsRemainSupported() throws {
        let base = try XCTUnwrap(ISODateParser.parse("2026-11-13T00:00:00Z"))
        for fraction in ["1", "123", "123456"] {
            let date = try XCTUnwrap(ISODateParser.parse("2026-11-13T00:00:00.\(fraction)Z"))
            XCTAssertGreaterThan(date, base)
            XCTAssertLessThan(date.timeIntervalSince(base), 1)
        }
        let milliseconds = try XCTUnwrap(ISODateParser.parse("2026-11-13T00:00:00.123+00:00"))
        XCTAssertEqual(milliseconds.timeIntervalSince(base), 0.123, accuracy: 0.001)
    }

    func testMissingEmptyAndInvalidTimesDoNotInventDates() {
        for value: String? in [nil, "", "invalid", "2026-99-99T99:99:99Z"] {
            XCTAssertNil(ISODateParser.parse(value))
        }
    }
}
