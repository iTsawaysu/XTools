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
        // 2026-10 更新：≥1 小时改用 h:mm:ss.ff；旧行为 "61:01.23"（把小时折进
        // 分钟）已废弃。3661.23s = 1:01:01.23。
        let formatted = ChronometerFormatter.format(3661.23)
        #expect(formatted == "1:01:01.23")
    }

    @Test func formatsHourBoundaryWithCentiseconds() {
        #expect(ChronometerFormatter.format(3661.5) == "1:01:01.50")
        #expect(ChronometerFormatter.format(7200.05) == "2:00:00.05")
        // <1 小时保持 mm:ss.ff。
        #expect(ChronometerFormatter.format(3599.99) == "59:59.99")
        #expect(ChronometerFormatter.format(3599.999) == "59:59.99")
    }

    @Test func handlesNegativeInterval() {
        let formatted = ChronometerFormatter.format(-10.5)
        #expect(formatted == "00:00.00") // negative clamped to zero
    }
}
