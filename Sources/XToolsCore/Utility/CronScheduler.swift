import Foundation

public enum CronScheduler {

    /// 单个 cron 字段的结构化解释，供 UI 渲染逐字段说明。
    public struct CronFieldExplanation: Equatable, Sendable {
        public let label: String
        public let token: String
        public let explanation: String
        public let isWildcard: Bool

        public init(label: String, token: String, explanation: String, isWildcard: Bool) {
            self.label = label
            self.token = token
            self.explanation = explanation
            self.isWildcard = isWildcard
        }
    }

    public struct ScheduleFields {
        public let minutes: Set<Int>
        public let hours: Set<Int>
        public let daysOfMonth: Set<Int>
        public let months: Set<Int>
        public let weekdays: Set<Int>

        public init(minutes: Set<Int>, hours: Set<Int>, daysOfMonth: Set<Int>, months: Set<Int>, weekdays: Set<Int>) {
            self.minutes = minutes
            self.hours = hours
            self.daysOfMonth = daysOfMonth
            self.months = months
            self.weekdays = weekdays
        }
    }

    /// Resolves `@keyword` presets to their 5-field equivalents.
    /// Returns the trimmed expression if not a keyword.
    /// Special case: `@reboot` returns empty string (no calendar schedule).
    public static func resolveExpression(_ expression: String) -> String {
        let trimmed = expression.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        switch trimmed {
        case "@yearly", "@annually": return "0 0 1 1 *"
        case "@monthly": return "0 0 1 * *"
        case "@weekly": return "0 0 * * 0"
        case "@daily", "@midnight": return "0 0 * * *"
        case "@hourly": return "0 * * * *"
        case "@reboot": return ""
        default: return expression.trimmingCharacters(in: .whitespacesAndNewlines)
        }
    }

    public static func parseFields(_ expression: String) -> ScheduleFields? {
        let parts = expression.split(whereSeparator: \.isWhitespace).map(String.init)
        guard parts.count == 5 else { return nil }

        guard let minutes = expandField(parts[0], min: 0, max: 59),
              let hours = expandField(parts[1], min: 0, max: 23),
              let daysOfMonth = expandField(parts[2], min: 1, max: 31),
              let months = expandField(parts[3], min: 1, max: 12, aliases: monthAliases),
              let weekdays = expandField(parts[4], min: 0, max: 7, aliases: weekdayAliases, field: .weekday)
        else { return nil }

        return ScheduleFields(
            minutes: minutes,
            hours: hours,
            daysOfMonth: daysOfMonth,
            months: months,
            weekdays: weekdays
        )
    }

    public static func validationMessage(_ expression: String) -> String? {
        let trimmed = expression.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.lowercased() == "@reboot" {
            return nil
        }

        guard !trimmed.isEmpty else {
            return "请输入 cron 表达式。"
        }

        let resolved = resolveExpression(expression)

        // 未识别的 @ 预设不能再报「需要 5 个字段」——那会把宏当成字段数错误。
        // resolveExpression 对无法识别的宏原样返回，据此判断。
        if trimmed.hasPrefix("@"), resolved == trimmed {
            return "不支持的 @ 预设；可用 @yearly、@annually、@monthly、@weekly、@daily、@midnight、@hourly、@reboot。"
        }

        let parts = resolved.split(whereSeparator: \.isWhitespace).map(String.init)
        guard parts.count == 5 else {
            return parts.count > 5
                ? "cron 表达式最多 5 个字段：分钟 小时 日 月 星期。"
                : "cron 表达式需要 5 个字段：分钟 小时 日 月 星期。"
        }

        let fieldSpecs: [(name: String, sample: String, min: Int, max: Int, values: Set<Int>?)] = [
            ("分钟", "0-59、*、列表、范围或 */步长", 0, 59, expandField(parts[0], min: 0, max: 59)),
            ("小时", "0-23、*、列表、范围或 */步长", 0, 23, expandField(parts[1], min: 0, max: 23)),
            ("日", "1-31、*、列表、范围或 */步长", 1, 31, expandField(parts[2], min: 1, max: 31)),
            ("月", "1-12 或 JAN-DEC", 1, 12, expandField(parts[3], min: 1, max: 12, aliases: monthAliases)),
            ("星期", "0-7 或 SUN-SAT，0 和 7 都表示周日", 0, 7, expandField(parts[4], min: 0, max: 7, aliases: weekdayAliases, field: .weekday))
        ]

        for (index, spec) in fieldSpecs.enumerated() where spec.values == nil {
            return invalidFieldMessage(
                value: parts[index],
                name: spec.name,
                sample: spec.sample,
                min: spec.min,
                max: spec.max
            )
        }

        return nil
    }

    private static func invalidFieldMessage(
        value: String,
        name: String,
        sample: String,
        min: Int,
        max: Int
    ) -> String {
        let stepParts = value.split(separator: "/", maxSplits: 1, omittingEmptySubsequences: false)
        if stepParts.count == 2,
           let step = Int(stepParts[1]),
           step <= 0 {
            return "\(name)字段的步长必须大于 0。"
        }

        for component in value.split(separator: ",") {
            let base = component.split(separator: "/", maxSplits: 1)[0]
            let bounds = base.split(separator: "-", maxSplits: 1, omittingEmptySubsequences: false)
            if bounds.count == 2,
               let lower = Int(bounds[0]),
               let upper = Int(bounds[1]),
               lower > upper {
                return "\(name)字段的范围起点不能大于终点。"
            }
        }

        let numericValues = value
            .split { !$0.isNumber }
            .compactMap { Int($0) }
        if numericValues.contains(where: { $0 < min || $0 > max }) {
            return "\(name)字段只支持 \(min)–\(max)。"
        }

        return "\(name)字段格式无效；支持 \(sample)。"
    }

    public static func nextRuns(
        _ expression: String,
        count: Int,
        after: Date,
        calendar: Calendar
    ) -> [Date] {
        let resolved = resolveExpression(expression)
        guard !resolved.isEmpty else { return [] }
        guard let fields = parseFields(resolved) else { return [] }

        // Keep the absolute position in a repeated hour and always advance past
        // the minute containing `after`, including when it has fractional seconds.
        guard var cursor = calendar.dateInterval(of: .minute, for: after)?.end else { return [] }

        // Map cron weekdays (0=Sun...6=Sat, 7=Sun) to Calendar's (1=Sun...7=Sat)
        let normalizedWeekdays = Set(fields.weekdays.map { ($0 == 0 || $0 == 7) ? 1 : $0 + 1 })

        let parts = resolved.split(whereSeparator: \.isWhitespace).map(String.init)
        let domWild = isWildcard(parts[2])
        let dowWild = isWildcard(parts[4])

        let sortedMinutes = fields.minutes.sorted()
        let sortedHours = fields.hours.sorted()

        var results: [Date] = []
        let horizon = calendar.date(byAdding: .year, value: 5, to: after) ?? after

        while results.count < count, cursor < horizon {
            // Adding one calendar day to a 01:00 start on a missing-midnight
            // day can land at 01:00 tomorrow. The day interval ends at the
            // actual next local-day boundary, which may be 00:00 tomorrow.
            guard let dayInterval = calendar.dateInterval(of: .day, for: cursor),
                  dayInterval.end > cursor else { break }
            let dayStart = dayInterval.start
            let nextDay = dayInterval.end
            let comps = calendar.dateComponents([.year, .month, .day, .weekday], from: dayStart)
            guard let month = comps.month, let day = comps.day, let weekday = comps.weekday else { break }

            let dayMatches: Bool
            if !domWild && !dowWild {
                dayMatches = fields.daysOfMonth.contains(day) || normalizedWeekdays.contains(weekday)
            } else if !domWild {
                dayMatches = fields.daysOfMonth.contains(day)
            } else if !dowWild {
                dayMatches = normalizedWeekdays.contains(weekday)
            } else {
                dayMatches = true
            }

            if !fields.months.contains(month) || !dayMatches {
                cursor = nextDay
                continue
            }

            let offsetAtStart = calendar.timeZone.secondsFromGMT(for: dayStart)
            let offsetAtEnd = calendar.timeZone.secondsFromGMT(for: nextDay.addingTimeInterval(-1))
            let offsetChange = abs(offsetAtEnd - offsetAtStart)

            // A repeated local hour is not ordered by its wall-clock fields:
            // first 01:45 precedes second 01:30. Collect both occurrences on
            // offset-change days, then order them by their absolute Date values.
            if offsetChange != 0 {
                var candidates: Set<Date> = []
                for hour in sortedHours {
                    for minute in sortedMinutes {
                        var slot = comps
                        slot.hour = hour
                        slot.minute = minute
                        slot.second = 0
                        guard let date = calendar.date(from: slot) else { continue }

                        for occurrence in [
                            date,
                            date.addingTimeInterval(TimeInterval(offsetChange)),
                            date.addingTimeInterval(-TimeInterval(offsetChange))
                        ] where occurrence >= cursor && occurrence < nextDay && occurrence < horizon {
                            if matchesLocalSlot(occurrence, hour: hour, minute: minute, calendar: calendar) {
                                candidates.insert(occurrence)
                            }
                        }
                    }
                }

                for date in candidates.sorted() {
                    results.append(date)
                    if results.count == count { break }
                }
                cursor = nextDay
                continue
            }

            var advanced = false
            outer: for hour in sortedHours {
                for minute in sortedMinutes {
                    var slot = comps
                    slot.hour = hour
                    slot.minute = minute
                    slot.second = 0
                    guard let date = calendar.date(from: slot) else { continue }
                    if date >= cursor, date < nextDay, date < horizon,
                       matchesLocalSlot(date, hour: hour, minute: minute, calendar: calendar) {
                        results.append(date)
                        cursor = date.addingTimeInterval(60)
                        advanced = true
                        break outer
                    }
                }
            }

            if !advanced {
                cursor = nextDay
            }
        }

        return results
    }

    private static func matchesLocalSlot(_ date: Date, hour: Int, minute: Int, calendar: Calendar) -> Bool {
        let actual = calendar.dateComponents([.hour, .minute, .second], from: date)
        return actual.hour == hour && actual.minute == minute && actual.second == 0
    }

    // MARK: - Field explanation

    public static func explainField(_ part: String, index: Int) -> String {
        let unit = ["分钟", "小时", "日", "月", "星期"][index]

        if part == "*" {
            return index == 4 ? "每天" : "每\(unit)"
        }

        // 步长在日、月、星期字段中会随字段周期重置，不能描述成连续时长。
        if part.hasPrefix("*/"), let step = Int(part.dropFirst(2)) {
            switch index {
            case 2: return "每月从 1 日起按 \(step) 日步长"
            case 3: return "每年从 1 月起按 \(step) 月步长"
            case 4: return "每周从周日起按 \(step) 日步长"
            default: return "每隔 \(step) \(unit)"
            }
        }

        // a-b/n 或 a/n：从 a 起按字段步长匹配。
        if part.contains("/"), let slash = part.firstIndex(of: "/"),
           let step = Int(part[part.index(after: slash)...]) {
            let base = String(part[..<slash])
            let start = describeFieldExpression(base, index: index)
            switch index {
            case 2: return "每月从 \(start)起按 \(step) 日步长"
            case 3: return "每年从 \(start)起按 \(step) 月步长"
            case 4: return "每周从 \(start)起按 \(step) 日步长"
            default: return "从 \(start) 起，每隔 \(step) \(unit)"
            }
        }

        // 区间：a-b
        if part.contains("-"), let dash = part.firstIndex(of: "-") {
            let lo = String(part[..<dash])
            let hi = String(part[part.index(after: dash)...])
            return "\(describeFieldValue(lo, index: index)) 到 \(describeFieldValue(hi, index: index))"
        }

        // 多值：a,b,c
        if part.contains(",") {
            let items = part.split(separator: ",").map { describeFieldValue(String($0), index: index) }
            return items.joined(separator: "、")
        }

        return describeFieldValue(part, index: index)
    }

    /// Explains the Unix crontab rule used when both day fields are restricted.
    /// Standard five-field cron matches when either day-of-month or weekday matches.
    public static func dayMatchingExplanation(_ expression: String) -> String? {
        let resolved = resolveExpression(expression)
        guard !resolved.isEmpty, validationMessage(expression) == nil else { return nil }

        let parts = resolved.split(whereSeparator: \.isWhitespace).map(String.init)
        guard parts.count == 5,
              !isWildcard(parts[2]),
              !isWildcard(parts[4])
        else { return nil }

        return "日与星期字段同时受限时，任一字段匹配即运行"
    }

    /// 把单个数值翻译成人类可读的时间点（星期转成中文星期，时分补足语义）。
    public static func describeFieldValue(_ raw: String, index: Int) -> String {
        let normalizedRaw = raw.uppercased()

        if index == 3, let value = monthAliases[normalizedRaw] {
            return describeFieldValue(String(value), index: index)
        }

        if index == 4, let value = weekdayAliases[normalizedRaw] {
            return describeFieldValue(String(value), index: index)
        }

        guard let value = Int(raw) else { return raw }
        switch index {
        case 0: return "第 \(value) 分钟"
        case 1: return "\(value) 点"
        case 2: return "\(value) 号"
        case 3: return "\(value) 月"
        case 4:
            let names = ["周日", "周一", "周二", "周三", "周四", "周五", "周六"]
            let normalized = value == 7 ? 0 : value
            return (0...6).contains(normalized) ? names[normalized] : raw
        default: return raw
        }
    }

    // MARK: - Structured explanation

    private static let fieldLabels = ["分钟 (0-59)", "小时 (0-23)", "日 (1-31)", "月 (1-12)", "星期 (0-7)"]

    /// 逐字段解释；表达式无法解析为 5 个合法字段（含 `@reboot`）时返回 nil。
    public static func fieldExplanations(_ expression: String) -> [CronFieldExplanation]? {
        let resolved = resolveExpression(expression)
        guard !resolved.isEmpty, validationMessage(expression) == nil else { return nil }
        let parts = resolved.split(whereSeparator: \.isWhitespace).map(String.init)
        guard parts.count == 5 else { return nil }
        return parts.enumerated().map { index, token in
            CronFieldExplanation(
                label: fieldLabels[index],
                token: token,
                explanation: explainField(token, index: index),
                isWildcard: token == "*"
            )
        }
    }

    /// 用一句中文概括表达式的执行时机。这是 crontab.guru 式的「先给答案」：
    /// 无法自信概括的写法（步长月份、超长列表等）返回 nil，UI 退回逐字段
    /// 说明，绝不给出含糊表述。
    public static func expressionSummary(_ expression: String) -> String? {
        let trimmed = expression.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.lowercased() != "@reboot" else { return nil }
        guard validationMessage(expression) == nil else { return nil }
        let resolved = resolveExpression(expression)
        let parts = resolved.split(whereSeparator: \.isWhitespace).map(String.init)
        guard parts.count == 5, let fields = parseFields(resolved) else { return nil }

        guard let time = describeTimeOfDay(
            rawHours: parts[1],
            rawMinutes: parts[0],
            hours: fields.hours,
            minutes: fields.minutes
        ) else { return nil }

        let domWildcard = isWildcard(parts[2])
        let dowWildcard = isWildcard(parts[4])
        let domCoverAll = fields.daysOfMonth.count == 31
        let dowCoverAll = Set(fields.weekdays.map { $0 == 7 ? 0 : $0 }).count == 7
        // 月份不参与日字段的 OR 规则，只有字面 * 才算不受限；
        // 受限却无法概括（步长展开超上限等）时放弃整句，绝不静默丢约束。
        let month: String?
        if parts[3] == "*" || fields.months.count == 12 {
            month = nil
        } else if let described = describeMonth(months: fields.months) {
            month = described
        } else {
            return nil
        }

        // 「每年 1 月 1 号」是同时约束月与日的常见特例，直接拼成整句。
        if let m = fields.months.first, fields.months.count == 1,
           dowWildcard, let d = fields.daysOfMonth.first, fields.daysOfMonth.count == 1 {
            return String(format: "每年 %d 月 %d 号 %@%@运行", m, d, time, time.contains(":") ? " " : "")
        }

        // 日匹配语义与 nextRuns 的 vixie 规则一致：通配字段被忽略；
        // 受限字段全覆盖（1-31 / 0-7）时每一天都命中。
        let day: String
        if domWildcard && dowWildcard {
            day = "每天"
        } else if domWildcard {
            if dowCoverAll {
                day = "每天"
            } else {
                guard let dowText = describeDayOfWeek(weekdays: fields.weekdays) else { return nil }
                day = dowText
            }
        } else if dowWildcard {
            if domCoverAll {
                day = "每天"
            } else {
                guard let domText = describeDayOfMonth(days: fields.daysOfMonth) else { return nil }
                day = month == nil ? "每月 \(domText)" : domText
            }
        } else if domCoverAll || dowCoverAll {
            day = "每天"
        } else {
            guard let domText = describeDayOfMonth(days: fields.daysOfMonth),
                  let dowText = describeDayOfWeek(weekdays: fields.weekdays) else { return nil }
            day = month == nil ? "每月 \(domText)或\(dowText)" : "\(domText)或\(dowText)"
        }

        // 频率式描述（每分钟/每隔 N 分钟/每小时…）自带时间范围，不再叠加「每天」。
        let needsDaily = time.contains(":")
        let effectiveDay = needsDaily ? day : (day == "每天" ? nil : day)

        // 时刻形如 "00:00" 时朗读需要空格；频率式（每分钟/每隔 N 分钟/…
        // 每小时）自带衔接，直接接「运行」。
        let spacing = time.contains(":") && !time.hasSuffix("每小时") ? " " : ""
        // 「月的 1 号」需要空格，「月的每周一」不需要。
        let dayConnector = day.hasPrefix("每") ? "" : " "
        switch (effectiveDay, month) {
        case (nil, nil):
            return "\(time)运行"
        case (let day?, nil):
            return "\(day) \(time)\(spacing)运行"
        case (nil, let month?):
            return "\(month)的\(time)\(spacing)运行"
        case (let day?, let month?):
            return "\(month)的\(dayConnector)\(day) \(time)\(spacing)运行"
        }
    }

    /// 时/分字段的人话描述。时刻枚举上限 4 个，超出即放弃概括；
    /// `*` 判断走集合覆盖，`*/n` 步长仍从原文提取。
    private static func describeTimeOfDay(
        rawHours: String,
        rawMinutes: String,
        hours: Set<Int>,
        minutes: Set<Int>
    ) -> String? {
        let hoursCoverAll = hours.count == 24
        let minutesCoverAll = minutes.count == 60

        if hoursCoverAll && minutesCoverAll { return "每分钟" }
        if hoursCoverAll {
            if let step = stepAfterStar(rawMinutes) { return "每隔 \(step) 分钟" }
            if minutes == [0] { return "每小时整点" }
            if minutes.count <= 4 {
                return "每小时第 \(numberList(minutes.sorted(), unit: "分"))"
            }
            return nil
        }
        if minutesCoverAll {
            guard let step = stepAfterStar(rawHours) else { return nil }
            return "每隔 \(step) 小时"
        }
        // 整点 + 步长小时（*/6）按书写意图读作「每隔 N 小时」，先于时刻枚举。
        if minutes == [0], let step = stepAfterStar(rawHours) {
            return "每隔 \(step) 小时"
        }
        if minutes.count == 1, let minute = minutes.first {
            if hours.count <= 4 {
                return hours.sorted().map { String(format: "%02d:%02d", $0, minute) }.joined(separator: "、")
            }
            if minute == 0, isContiguous(hours) {
                return String(format: "%02d:00 至 %02d:00 每小时", hours.min() ?? 0, hours.max() ?? 0)
            }
            return nil
        }
        if hours.count * minutes.count <= 4 {
            var times: [String] = []
            for hour in hours.sorted() {
                for minute in minutes.sorted() {
                    times.append(String(format: "%02d:%02d", hour, minute))
                }
            }
            return times.joined(separator: "、")
        }
        return nil
    }

    /// 日字段描述："1 号"、"1、15 号"、"1 至 15 号"；步长等复杂写法返回 nil。
    private static func describeDayOfMonth(days: Set<Int>) -> String? {
        if days.count == 1, let only = days.first { return "\(only) 号" }
        if isContiguous(days) {
            return "\(days.min() ?? 0) 至 \(days.max() ?? 0) 号"
        }
        if days.count <= 4 {
            return days.sorted().map(String.init).joined(separator: "、") + " 号"
        }
        return nil
    }

    /// 星期字段描述："每周一"、"每周一至周五"、"每周六、日"。
    private static func describeDayOfWeek(weekdays: Set<Int>) -> String? {
        // 短名按下标拼「每周X」："每周日"、"每周一"…
        let shortNames = ["日", "一", "二", "三", "四", "五", "六"]
        let normalized = Set(weekdays.map { $0 == 7 ? 0 : $0 }).sorted()
        guard !normalized.isEmpty else { return nil }
        if normalized == [0, 6] { return "每周六、日" }
        if normalized.count == 1 { return "每周\(shortNames[normalized[0]])" }
        if isContiguous(Set(normalized)) {
            return "每周\(shortNames[normalized[0]])至周\(shortNames[normalized.last!])"
        }
        if normalized.count <= 3 {
            return "每周" + normalized.map { shortNames[$0] }.joined(separator: "、")
        }
        return nil
    }

    /// 月字段描述："3 月"、"3 至 6 月"、"3、6、12 月"。
    private static func describeMonth(months: Set<Int>) -> String? {
        if months.count == 1, let only = months.first { return "\(only) 月" }
        if isContiguous(months) {
            return "\(months.min() ?? 0) 至 \(months.max() ?? 0) 月"
        }
        if months.count <= 4 {
            return months.sorted().map(String.init).joined(separator: "、") + " 月"
        }
        return nil
    }

    /// `*/n` 形态的步长；其余写法（含 `a/n`、区间步长）不参与概括。
    private static func stepAfterStar(_ raw: String) -> Int? {
        guard raw.hasPrefix("*/") else { return nil }
        guard let step = Int(raw.dropFirst(2)) else { return nil }
        return step > 0 ? step : nil
    }

    private static func isContiguous(_ values: Set<Int>) -> Bool {
        guard let lowerBound = values.min(), let upperBound = values.max() else { return false }
        return upperBound - lowerBound + 1 == values.count
    }

    private static func numberList(_ values: [Int], unit: String) -> String {
        values.map(String.init).joined(separator: "、") + " " + unit
    }

    // MARK: - Private helpers

    private enum CronFieldKind {
        case standard
        case weekday
    }

    private static func expandField(
        _ raw: String,
        min: Int,
        max: Int,
        aliases: [String: Int] = [:],
        field: CronFieldKind = .standard
    ) -> Set<Int>? {
        if raw == "*" { return Set(min...max) }
        var values: Set<Int> = []
        let segments = raw.uppercased().split(separator: ",", omittingEmptySubsequences: false).map(String.init)
        for segment in segments {
            guard !segment.isEmpty else { return nil }
            let parts = segment.split(separator: "/", maxSplits: 1, omittingEmptySubsequences: false).map(String.init)
            guard (1...2).contains(parts.count), !parts[0].isEmpty else { return nil }
            let step: Int
            if parts.count == 2 {
                guard let parsedStep = Int(parts[1]), parsedStep > 0 else { return nil }
                step = parsedStep
            } else {
                step = 1
            }
            let base = parts[0]
            let rs: Int, re: Int
            if base == "*" {
                rs = min; re = max
            } else if base.contains("-") {
                let b = base.split(separator: "-", maxSplits: 1, omittingEmptySubsequences: false).map(String.init)
                guard b.count == 2,
                      let s = fieldValue(b[0], aliases: aliases),
                      var e = fieldValue(b[1], aliases: aliases) else { return nil }
                if field == .weekday, b[1] == "SUN", s > 0 {
                    e = 7
                }
                guard s <= e else { return nil }
                rs = s; re = e
            } else {
                guard let single = fieldValue(base, aliases: aliases) else { return nil }
                rs = single; re = parts.count == 2 ? max : single
            }
            guard rs >= min, re <= max, rs <= re else { return nil }
            var c = rs
            while c <= re {
                values.insert(c)
                guard step <= re - c else { break }
                c += step
            }
        }
        return values.isEmpty ? nil : values
    }

    private static func fieldValue(_ raw: String, aliases: [String: Int]) -> Int? {
        aliases[raw] ?? Int(raw)
    }

    private static func describeFieldExpression(_ raw: String, index: Int) -> String {
        if raw.contains("-"), let dash = raw.firstIndex(of: "-") {
            let lo = String(raw[..<dash])
            let hi = String(raw[raw.index(after: dash)...])
            return "\(describeFieldValue(lo, index: index)) 到 \(describeFieldValue(hi, index: index))"
        }

        return describeFieldValue(raw, index: index)
    }

    /// 字段是否「不受限」，用于日/星期字段的「或」语义判定。
    ///
    /// Vixie cron 以字段**首字符是否为 `*`** 置位 DOM_STAR / DOW_STAR，因此
    /// `*/2` 属于不受限，而不是受限；只有「两个字段都受限（都不是以 `*` 开头）」
    /// 时才按「任一字段匹配即运行」处理。此前只把字面量 `*` 视为通配，
    /// 于是 `0 0 */2 * MON` 会额外在非星期一的日子触发。
    private static func isWildcard(_ raw: String) -> Bool {
        raw.hasPrefix("*")
    }

    private static let monthAliases: [String: Int] = [
        "JAN": 1,
        "FEB": 2,
        "MAR": 3,
        "APR": 4,
        "MAY": 5,
        "JUN": 6,
        "JUL": 7,
        "AUG": 8,
        "SEP": 9,
        "OCT": 10,
        "NOV": 11,
        "DEC": 12
    ]

    private static let weekdayAliases: [String: Int] = [
        "SUN": 0,
        "MON": 1,
        "TUE": 2,
        "WED": 3,
        "THU": 4,
        "FRI": 5,
        "SAT": 6
    ]
}
