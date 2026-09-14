import Foundation

struct TimezoneInfo: Identifiable, Hashable {
    var id: String { "\(region)|\(name)|\(timezone.identifier)" }

    let timezone: TimeZone
    let name: String
    let region: String
}

struct TimezoneRegion: Identifiable {
    var id: String { region }

    let region: String
    let timezones: [TimezoneInfo]
}

struct VisibleTimezoneRegion: Identifiable {
    var id: String { region }
    var cityCount: Int { groups.reduce(0) { $0 + $1.cities.count } }

    let region: String
    let groups: [TimezoneGroup]
}

struct TimezoneGroup: Identifiable, Hashable {
    var id: Int { offsetSeconds }
    var favoriteKeys: Set<String> { Set(cities.map { $0.timezone.identifier }) }

    let offsetSeconds: Int
    let cities: [TimezoneInfo]

    var offsetString: String {
        let totalMinutes = offsetSeconds / 60
        let sign = totalMinutes >= 0 ? "+" : "-"
        let absoluteMinutes = abs(totalMinutes)
        let hours = absoluteMinutes / 60
        let minutes = absoluteMinutes % 60

        if minutes == 0 {
            return "UTC\(sign)\(hours)"
        }
        return String(format: "UTC%@%d:%02d", sign, hours, minutes)
    }

    var cityNames: String {
        cities.map { $0.name }.joined(separator: " / ")
    }
}

enum TimezoneCityCatalog {
    static let defaultRegions: [TimezoneRegion] = [
        TimezoneRegion(region: "亚洲", timezones: [
            TimezoneInfo(timezone: TimeZone(identifier: "Asia/Shanghai")!, name: "北京", region: "亚洲"),
            TimezoneInfo(timezone: TimeZone(identifier: "Asia/Tokyo")!, name: "东京", region: "亚洲"),
            TimezoneInfo(timezone: TimeZone(identifier: "Asia/Seoul")!, name: "首尔", region: "亚洲"),
            TimezoneInfo(timezone: TimeZone(identifier: "Asia/Singapore")!, name: "新加坡", region: "亚洲"),
            TimezoneInfo(timezone: TimeZone(identifier: "Asia/Hong_Kong")!, name: "香港", region: "亚洲"),
            TimezoneInfo(timezone: TimeZone(identifier: "Asia/Bangkok")!, name: "曼谷", region: "亚洲"),
            TimezoneInfo(timezone: TimeZone(identifier: "Asia/Kolkata")!, name: "德里", region: "亚洲"),
            TimezoneInfo(timezone: TimeZone(identifier: "Asia/Dubai")!, name: "迪拜", region: "亚洲")
        ]),
        TimezoneRegion(region: "欧洲", timezones: [
            TimezoneInfo(timezone: TimeZone(identifier: "Europe/London")!, name: "伦敦", region: "欧洲"),
            TimezoneInfo(timezone: TimeZone(identifier: "Europe/Paris")!, name: "巴黎", region: "欧洲"),
            TimezoneInfo(timezone: TimeZone(identifier: "Europe/Berlin")!, name: "柏林", region: "欧洲"),
            TimezoneInfo(timezone: TimeZone(identifier: "Europe/Moscow")!, name: "莫斯科", region: "欧洲"),
            TimezoneInfo(timezone: TimeZone(identifier: "Europe/Rome")!, name: "罗马", region: "欧洲"),
            TimezoneInfo(timezone: TimeZone(identifier: "Europe/Madrid")!, name: "马德里", region: "欧洲"),
            TimezoneInfo(timezone: TimeZone(identifier: "Europe/Amsterdam")!, name: "阿姆斯特丹", region: "欧洲")
        ]),
        TimezoneRegion(region: "北美", timezones: [
            TimezoneInfo(timezone: TimeZone(identifier: "America/New_York")!, name: "纽约", region: "北美"),
            TimezoneInfo(timezone: TimeZone(identifier: "America/Los_Angeles")!, name: "洛杉矶", region: "北美"),
            TimezoneInfo(timezone: TimeZone(identifier: "America/Chicago")!, name: "芝加哥", region: "北美"),
            TimezoneInfo(timezone: TimeZone(identifier: "America/Toronto")!, name: "多伦多", region: "北美"),
            TimezoneInfo(timezone: TimeZone(identifier: "America/Mexico_City")!, name: "墨西哥城", region: "北美"),
            TimezoneInfo(timezone: TimeZone(identifier: "America/Vancouver")!, name: "温哥华", region: "北美")
        ]),
        TimezoneRegion(region: "南美", timezones: [
            TimezoneInfo(timezone: TimeZone(identifier: "America/Sao_Paulo")!, name: "圣保罗", region: "南美"),
            TimezoneInfo(timezone: TimeZone(identifier: "America/Buenos_Aires")!, name: "布宜诺斯艾利斯", region: "南美"),
            TimezoneInfo(timezone: TimeZone(identifier: "America/Lima")!, name: "利马", region: "南美"),
            TimezoneInfo(timezone: TimeZone(identifier: "America/Bogota")!, name: "波哥大", region: "南美")
        ]),
        TimezoneRegion(region: "非洲", timezones: [
            TimezoneInfo(timezone: TimeZone(identifier: "Africa/Cairo")!, name: "开罗", region: "非洲"),
            TimezoneInfo(timezone: TimeZone(identifier: "Africa/Johannesburg")!, name: "约翰内斯堡", region: "非洲"),
            TimezoneInfo(timezone: TimeZone(identifier: "Africa/Lagos")!, name: "拉各斯", region: "非洲"),
            TimezoneInfo(timezone: TimeZone(identifier: "Africa/Nairobi")!, name: "内罗毕", region: "非洲")
        ]),
        TimezoneRegion(region: "大洋洲", timezones: [
            TimezoneInfo(timezone: TimeZone(identifier: "Australia/Sydney")!, name: "悉尼", region: "大洋洲"),
            TimezoneInfo(timezone: TimeZone(identifier: "Australia/Melbourne")!, name: "墨尔本", region: "大洋洲"),
            TimezoneInfo(timezone: TimeZone(identifier: "Pacific/Auckland")!, name: "奥克兰", region: "大洋洲"),
            TimezoneInfo(timezone: TimeZone(identifier: "Pacific/Fiji")!, name: "斐济", region: "大洋洲")
        ])
    ]
}

struct TimezoneViewerProjection {
    let favoriteGroups: [TimezoneGroup]
    let visibleRegions: [VisibleTimezoneRegion]

    init(
        regions: [TimezoneRegion] = TimezoneCityCatalog.defaultRegions,
        favoriteKeys: Set<String>,
        date: Date = Date()
    ) {
        var favoriteCities: [TimezoneInfo] = []
        var visibleRegions: [VisibleTimezoneRegion] = []

        for region in regions {
            var visibleCities: [TimezoneInfo] = []

            for city in region.timezones {
                if favoriteKeys.contains(city.timezone.identifier) {
                    favoriteCities.append(city)
                } else {
                    visibleCities.append(city)
                }
            }

            let groups = TimezoneViewerLogic.groupByOffset(visibleCities, date: date)
            if !groups.isEmpty {
                visibleRegions.append(VisibleTimezoneRegion(region: region.region, groups: groups))
            }
        }

        self.favoriteGroups = TimezoneViewerLogic.groupByOffset(favoriteCities, date: date)
        self.visibleRegions = visibleRegions
    }
}

enum TimezoneViewerLogic {
    static func groupByOffset(_ timezones: [TimezoneInfo], date: Date = Date()) -> [TimezoneGroup] {
        let grouped = Dictionary(grouping: timezones) { info in
            info.timezone.secondsFromGMT(for: date)
        }
        return grouped.map { offset, cities in
            TimezoneGroup(offsetSeconds: offset, cities: cities.sorted { $0.name < $1.name })
        }.sorted { $0.offsetSeconds < $1.offsetSeconds }
    }

    static func favoriteGroups(
        _ regions: [TimezoneRegion],
        favoriteKeys: Set<String>,
        date: Date = Date()
    ) -> [TimezoneGroup] {
        groupByOffset(
            regions.flatMap(\.timezones)
                .filter { favoriteKeys.contains($0.timezone.identifier) },
            date: date
        )
    }

    static func visibleRegionGroups(
        _ regions: [TimezoneRegion],
        favoriteKeys: Set<String>,
        date: Date = Date()
    ) -> [VisibleTimezoneRegion] {
        regions.compactMap { region in
            let groups = groupByOffset(
                region.timezones.filter { !favoriteKeys.contains($0.timezone.identifier) },
                date: date
            )
            guard !groups.isEmpty else { return nil }
            return VisibleTimezoneRegion(region: region.region, groups: groups)
        }
    }
}
