import XToolsCore
import Foundation
import Testing

struct CronSchedulerTests {
    // MARK: - Keyword resolution

    @Test func resolvesKeywordAliases() {
        #expect(CronScheduler.resolveExpression("@yearly") == "0 0 1 1 *")
        #expect(CronScheduler.resolveExpression("@annually") == "0 0 1 1 *")
        #expect(CronScheduler.resolveExpression("@monthly") == "0 0 1 * *")
        #expect(CronScheduler.resolveExpression("@weekly") == "0 0 * * 0")
        #expect(CronScheduler.resolveExpression("@daily") == "0 0 * * *")
        #expect(CronScheduler.resolveExpression("@midnight") == "0 0 * * *")
        #expect(CronScheduler.resolveExpression("@hourly") == "0 * * * *")
        #expect(CronScheduler.resolveExpression("@reboot") == "")
    }

    @Test func passesThroughRegularExpressions() {
        #expect(CronScheduler.resolveExpression("*/5 * * * *") == "*/5 * * * *")
        #expect(CronScheduler.resolveExpression("  0 9 * * 1-5  ") == "0 9 * * 1-5") // trimmed
    }

    // MARK: - Field parsing

    @Test func parsesWildcardFields() {
        let fields = CronScheduler.parseFields("* * * * *")
        #expect(fields != nil)
        #expect(fields?.minutes == Set(0...59))
        #expect(fields?.hours == Set(0...23))
        #expect(fields?.daysOfMonth == Set(1...31))
        #expect(fields?.months == Set(1...12))
        #expect(fields?.weekdays == Set(0...7))
    }

    @Test func parsesStepAndRangeFields() {
        let stepped = CronScheduler.parseFields("*/15 * * * *")
        #expect(stepped?.minutes == Set([0, 15, 30, 45]))

        let ranged = CronScheduler.parseFields("0 9 * * 1-5")
        #expect(ranged?.weekdays == Set([1, 2, 3, 4, 5]))
        #expect(ranged?.hours == Set([9]))
    }

    @Test func parsesListFields() {
        let listed = CronScheduler.parseFields("0 0,12 * * *")
        #expect(listed?.hours == Set([0, 12]))

        let weekend = CronScheduler.parseFields("0 0 * * 6,0")
        #expect(weekend?.weekdays == Set([6, 0]))
    }

    @Test func parsesMonthAndWeekdayNames() {
        let named = CronScheduler.parseFields("0 9 * JAN MON-FRI")

        #expect(named?.months == Set([1]))
        #expect(named?.weekdays == Set([1, 2, 3, 4, 5]))

        let weekend = CronScheduler.parseFields("0 0 * * SAT-SUN")
        #expect(weekend?.weekdays == Set([6, 7]))
    }

    @Test func rejectsOutOfRangeFields() {
        #expect(CronScheduler.parseFields("60 * * * *") == nil) // minute > 59
        #expect(CronScheduler.parseFields("* 24 * * *") == nil) // hour > 23
        #expect(CronScheduler.parseFields("* * 32 * *") == nil) // day > 31
        #expect(CronScheduler.parseFields("* * * 13 *") == nil) // month > 12
        #expect(CronScheduler.parseFields("* * * * 8") == nil) // weekday > 7
    }

    @Test func rejectsMalformedFields() {
        #expect(CronScheduler.parseFields("* * * *") == nil) // 4 fields
        #expect(CronScheduler.parseFields("* * * * * *") == nil) // 6 fields
        #expect(CronScheduler.parseFields("a * * * *") == nil) // non-numeric
        #expect(CronScheduler.parseFields("*/0 * * * *") == nil) // zero step
        #expect(CronScheduler.parseFields("5-2 * * * *") == nil) // reversed range
        #expect(CronScheduler.parseFields("0 9 ? * 1") == nil) // Quartz-only wildcard
    }

    @Test func validationMessagesNameTheInvalidField() {
        #expect(CronScheduler.validationMessage("*/5 * * * *") == nil)
        #expect(CronScheduler.validationMessage("@reboot") == nil)
        #expect(CronScheduler.validationMessage("* * * *") == "cron 表达式需要 5 个字段：分钟 小时 日 月 星期。")
        #expect(CronScheduler.validationMessage("60 * * * *") == "分钟字段只支持 0–59。")
        #expect(CronScheduler.validationMessage("* 24 * * *") == "小时字段只支持 0–23。")
        #expect(CronScheduler.validationMessage("* * * * 8") == "星期字段只支持 0–7。")
        #expect(CronScheduler.validationMessage("*/0 * * * *") == "分钟字段的步长必须大于 0。")
        #expect(CronScheduler.validationMessage("5-2 * * * *") == "分钟字段的范围起点不能大于终点。")
        #expect(CronScheduler.validationMessage("abc * * * *") == "分钟字段格式无效；支持 0-59、*、列表、范围或 */步长。")
        #expect(CronScheduler.validationMessage("0 9 ? * 1") == "日字段格式无效；支持 1-31、*、列表、范围或 */步长。")

        for expression in ["60 * * * *", "*/0 * * * *", "5-2 * * * *", "abc * * * *"] {
            ToolDiagnosticContract.expectFactual(CronScheduler.validationMessage(expression) ?? "")
        }
    }

    // MARK: - Next-run computation


    @Test func explainsUnixDayFieldsUseOrSemanticsOnlyWhenBothAreRestricted() {
        #expect(
            CronScheduler.dayMatchingExplanation("30 4 1,15 * 5")
                == "日与星期字段同时受限时，任一字段匹配即运行"
        )
        #expect(CronScheduler.dayMatchingExplanation("30 4 * * 5") == nil)
        #expect(CronScheduler.dayMatchingExplanation("30 4 1,15 * *") == nil)
        #expect(CronScheduler.dayMatchingExplanation("@reboot") == nil)
        #expect(CronScheduler.dayMatchingExplanation("invalid") == nil)
    }

    @Test func computesDailyNextRuns() {
        let calendar = gregorianUTC()
        let after = date(calendar, 2026, 1, 1, 12, 0)
        let runs = CronScheduler.nextRuns("0 0 * * *", count: 3, after: after, calendar: calendar)

        #expect(runs.count == 3)
        #expect(runs[0] == date(calendar, 2026, 1, 2, 0, 0))
        #expect(runs[1] == date(calendar, 2026, 1, 3, 0, 0))
        #expect(runs[2] == date(calendar, 2026, 1, 4, 0, 0))
    }

    @Test func computesStepMinuteNextRuns() {
        let calendar = gregorianUTC()
        let after = date(calendar, 2026, 1, 1, 0, 0)
        let runs = CronScheduler.nextRuns("*/15 * * * *", count: 3, after: after, calendar: calendar)

        #expect(runs.count == 3)
        // cursor advances to next whole minute (00:01), first matching */15 slot is 00:15
        #expect(runs[0] == date(calendar, 2026, 1, 1, 0, 15))
        #expect(runs[1] == date(calendar, 2026, 1, 1, 0, 30))
        #expect(runs[2] == date(calendar, 2026, 1, 1, 0, 45))
    }

    @Test func computesWeekdayNextRuns() {
        let calendar = gregorianUTC()
        // 2026-01-01 is a Thursday. "0 9 * * 1-5" = weekdays 9am.
        let after = date(calendar, 2026, 1, 1, 12, 0)
        let runs = CronScheduler.nextRuns("0 9 * * 1-5", count: 2, after: after, calendar: calendar)

        #expect(runs.count == 2)
        // Next weekday after Thu noon is Fri 2026-01-02 09:00
        #expect(runs[0] == date(calendar, 2026, 1, 2, 9, 0))
        // Then skip weekend to Mon 2026-01-05 09:00
        #expect(runs[1] == date(calendar, 2026, 1, 5, 9, 0))
    }

    @Test func computesNextRunsForNamedMonthAndWeekday() {
        let calendar = gregorianUTC()
        // 2026-01-01 is a Thursday. Restricting to JAN and MON-FRI should pick Friday.
        let after = date(calendar, 2026, 1, 1, 12, 0)
        let runs = CronScheduler.nextRuns("0 9 * JAN MON-FRI", count: 2, after: after, calendar: calendar)

        #expect(runs == [
            date(calendar, 2026, 1, 2, 9, 0),
            date(calendar, 2026, 1, 5, 9, 0)
        ])
    }

    @Test func returnsEmptyForInvalidExpression() {
        let calendar = gregorianUTC()
        let after = date(calendar, 2026, 1, 1, 12, 0)
        #expect(CronScheduler.nextRuns("invalid", count: 3, after: after, calendar: calendar).isEmpty)
        #expect(CronScheduler.nextRuns("60 * * * *", count: 3, after: after, calendar: calendar).isEmpty)
    }

    // MARK: - Field explanation

    @Test func explainsWildcardPerUnit() {
        #expect(CronScheduler.explainField("*", index: 0) == "每分钟")
        #expect(CronScheduler.explainField("*", index: 1) == "每小时")
        #expect(CronScheduler.explainField("*", index: 2) == "每日")
        #expect(CronScheduler.explainField("*", index: 3) == "每月")
        // weekday wildcard is special-cased to 每天, not 每星期
        #expect(CronScheduler.explainField("*", index: 4) == "每天")
    }

    @Test func explainsStepValuesWithoutImplyingCrossCycleIntervals() {
        #expect(CronScheduler.explainField("*/5", index: 0) == "每隔 5 分钟")
        #expect(CronScheduler.explainField("*/6", index: 1) == "每隔 6 小时")
        #expect(CronScheduler.explainField("*/5", index: 2) == "每月从 1 日起按 5 日步长")
        #expect(CronScheduler.explainField("*/3", index: 3) == "每年从 1 月起按 3 月步长")
    }

    @Test func explainsBaseStepValues() {
        // a/n form: from a, every n
        #expect(CronScheduler.explainField("10/15", index: 0) == "从 第 10 分钟 起，每隔 15 分钟")
        // Month-field stepping resets every year rather than describing a continuous duration.
        #expect(CronScheduler.explainField("1/2", index: 3) == "每年从 1 月起按 2 月步长")
    }

    @Test func explainsRanges() {
        #expect(CronScheduler.explainField("1-5", index: 4) == "周一 到 周五")
        #expect(CronScheduler.explainField("9-17", index: 1) == "9 点 到 17 点")
        #expect(CronScheduler.explainField("MON-FRI", index: 4) == "周一 到 周五")
    }

    @Test func explainsLists() {
        #expect(CronScheduler.explainField("0,12", index: 1) == "0 点、12 点")
        #expect(CronScheduler.explainField("6,0", index: 4) == "周六、周日")
    }

    @Test func explainsSingleValues() {
        #expect(CronScheduler.explainField("30", index: 0) == "第 30 分钟")
        #expect(CronScheduler.explainField("15", index: 2) == "15 号")
    }

    @Test func describesWeekdayNamesWithSundayNormalization() {
        #expect(CronScheduler.describeFieldValue("0", index: 4) == "周日")
        // 7 normalizes to Sunday (both 0 and 7 mean Sunday in cron)
        #expect(CronScheduler.describeFieldValue("7", index: 4) == "周日")
        #expect(CronScheduler.describeFieldValue("6", index: 4) == "周六")
    }

    @Test func describesNonNumericValueVerbatim() {
        // Non-numeric input falls through to the raw string on every field.
        #expect(CronScheduler.describeFieldValue("UNKNOWN", index: 4) == "UNKNOWN")
        #expect(CronScheduler.explainField("UNKNOWN", index: 3) == "UNKNOWN")
    }

    @Test func describesNamedMonthsAndWeekdays() {
        #expect(CronScheduler.describeFieldValue("MON", index: 4) == "周一")
        #expect(CronScheduler.explainField("JAN", index: 3) == "1 月")
    }

    // MARK: - Helpers

    private func gregorianUTC() -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }

    private func date(_ calendar: Calendar, _ year: Int, _ month: Int, _ day: Int, _ hour: Int, _ minute: Int) -> Date {
        calendar.date(from: DateComponents(
            timeZone: calendar.timeZone,
            year: year,
            month: month,
            day: day,
            hour: hour,
            minute: minute,
            second: 0
        ))!
    }
}
