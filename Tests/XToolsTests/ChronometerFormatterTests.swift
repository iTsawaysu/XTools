import XToolsCore
import Foundation
import Testing

struct ChronometerFormatterTests {
    @Test func formatsZero() {
        let formatted = ChronometerFormatter.format(0)
        #expect(formatted == "00:00.00")
    }

    @Test func formatsSubSecond() {
        let formatted = ChronometerFormatter.format(0.456)
        #expect(formatted == "00:00.45") // 456ms → 45
    }

    @Test func formatsSeconds() {
        let formatted = ChronometerFormatter.format(12.34)
        #expect(formatted == "00:12.34")
    }

    @Test func formatsMinutes() {
        let formatted = ChronometerFormatter.format(125.67)
        #expect(formatted == "02:05.67") // 125.67s → 02:05.67
    }

    @Test func formatsHours() {
        let formatted = ChronometerFormatter.format(3661.23)
        #expect(formatted == "61:01.23") // 3661.23s → 61:01.23
    }

    @Test func handlesNegativeInterval() {
        let formatted = ChronometerFormatter.format(-10.5)
        #expect(formatted == "00:00.00") // negative clamped to zero
    }
}
