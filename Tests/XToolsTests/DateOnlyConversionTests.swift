import XToolsCore
import Foundation
import Testing

struct DateOnlyConversionTests {
    @Test func acceptsDashOrSlashAndNormalizesToStartOfDay() {
        let timeZone = TimeZone(secondsFromGMT: 0)!

        let dash = DateOnlyConversion.date(fromText: "2026-07-06", timeZone: timeZone)
        let slash = DateOnlyConversion.date(fromText: "2026/7/6", timeZone: timeZone)

        #expect(dash == slash)
        #expect(DateOnlyConversion.string(from: dash!, timeZone: timeZone) == "2026-07-06")
    }

    @Test func rejectsImpossibleOrMalformedDates() {
        let timeZone = TimeZone(secondsFromGMT: 0)!

        #expect(DateOnlyConversion.date(fromText: "2026-02-29", timeZone: timeZone) == nil)
        #expect(DateOnlyConversion.date(fromText: "2026-13-01", timeZone: timeZone) == nil)
        #expect(DateOnlyConversion.date(fromText: "2026.07.06", timeZone: timeZone) == nil)
        #expect(DateOnlyConversion.date(fromText: "", timeZone: timeZone) == nil)
    }

    @Test func acceptsLeapDayInGregorianCalendar() {
        let timeZone = TimeZone(secondsFromGMT: 0)!

        let leapDay = DateOnlyConversion.date(fromText: "2024-02-29", timeZone: timeZone)

        #expect(leapDay != nil)
        #expect(DateOnlyConversion.string(from: leapDay!, timeZone: timeZone) == "2024-02-29")
    }
}
