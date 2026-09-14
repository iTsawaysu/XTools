@testable import XTools
import Foundation
import Testing

struct TimezoneViewerLogicTests {
    @Test func defaultCatalogKeepsRegionOrderAndKeyCities() {
        let regions = TimezoneCityCatalog.defaultRegions

        #expect(regions.map(\.region) == ["亚洲", "欧洲", "北美", "南美", "非洲", "大洋洲"])
        #expect(regions.map { $0.timezones.count } == [8, 7, 6, 4, 4, 4])
        #expect(Self.catalogContains(regions, region: "亚洲", name: "北京", identifier: "Asia/Shanghai"))
        #expect(Self.catalogContains(regions, region: "欧洲", name: "伦敦", identifier: "Europe/London"))
        #expect(Self.catalogContains(regions, region: "北美", name: "纽约", identifier: "America/New_York"))
        #expect(Self.catalogContains(regions, region: "大洋洲", name: "悉尼", identifier: "Australia/Sydney"))

        let identifiers = regions.flatMap { $0.timezones.map { $0.timezone.identifier } }

        #expect(Set(identifiers).count == identifiers.count)
        #expect(regions.allSatisfy { region in
            region.timezones.allSatisfy { $0.region == region.region }
        })
    }

    @Test func projectionDerivesFavoritesAndVisibleRegionsFromDefaultCatalog() throws {
        let projection = TimezoneViewerProjection(
            favoriteKeys: ["Asia/Shanghai", "Europe/London", "Australia/Sydney"],
            date: Self.instant("2026-01-15T12:00:00Z")
        )

        #expect(projection.favoriteGroups.map(\.offsetSeconds) == [0, 8 * 3600, 11 * 3600])
        #expect(projection.favoriteGroups.map(\.cityNames) == ["伦敦", "北京", "悉尼"])
        #expect(projection.visibleRegions.map(\.region) == ["亚洲", "欧洲", "北美", "南美", "非洲", "大洋洲"])
        #expect(projection.visibleRegions.map(\.cityCount) == [7, 6, 6, 4, 4, 3])

        let asia = try #require(projection.visibleRegions.first { $0.region == "亚洲" })
        let europe = try #require(projection.visibleRegions.first { $0.region == "欧洲" })
        let oceania = try #require(projection.visibleRegions.first { $0.region == "大洋洲" })

        #expect(!asia.groups.flatMap { $0.cities.map(\.timezone.identifier) }.contains("Asia/Shanghai"))
        #expect(!europe.groups.flatMap { $0.cities.map(\.timezone.identifier) }.contains("Europe/London"))
        #expect(!oceania.groups.flatMap { $0.cities.map(\.timezone.identifier) }.contains("Australia/Sydney"))
    }

    @Test func groupsCitiesByOffsetWithOneFavoriteKey() {
        let cities = [
            Self.city("北京", identifier: "Asia/Shanghai"),
            Self.city("香港", identifier: "Asia/Hong_Kong"),
            Self.city("东京", identifier: "Asia/Tokyo")
        ]

        let groups = TimezoneViewerLogic.groupByOffset(cities, date: Self.instant("2026-01-15T12:00:00Z"))
        let offsets = groups.map { $0.offsetSeconds }
        let firstGroupNames = groups[0].cities.map { $0.name }

        #expect(offsets == [8 * 3600, 9 * 3600])
        #expect(firstGroupNames == ["北京", "香港"])
        #expect(groups[0].favoriteKeys == ["Asia/Hong_Kong", "Asia/Shanghai"])
    }

    @Test func favoriteTimezonesAreRemovedFromVisibleRegionGroups() {
        let regions = [
            TimezoneRegion(region: "亚洲", timezones: [
                Self.city("北京", identifier: "Asia/Shanghai"),
                Self.city("香港", identifier: "Asia/Hong_Kong"),
                Self.city("东京", identifier: "Asia/Tokyo")
            ])
        ]

        let visible = TimezoneViewerLogic.visibleRegionGroups(
            regions,
            favoriteKeys: ["Asia/Hong_Kong", "Asia/Shanghai"],
            date: Self.instant("2026-01-15T12:00:00Z")
        )
        let visibleOffsets = visible[0].groups.map { $0.offsetSeconds }
        let visibleNames = visible[0].groups[0].cities.map { $0.name }

        #expect(visible.count == 1)
        #expect(visibleOffsets == [9 * 3600])
        #expect(visibleNames == ["东京"])
    }

    @Test func visibleRegionGroupsKeepContinentsSeparateWhenOffsetsMatch() {
        let regions = [
            TimezoneRegion(region: "亚洲", timezones: [
                Self.city("北京", identifier: "Asia/Shanghai")
            ]),
            TimezoneRegion(region: "大洋洲", timezones: [
                Self.city("珀斯", identifier: "Australia/Perth")
            ])
        ]

        let visible = TimezoneViewerLogic.visibleRegionGroups(
            regions,
            favoriteKeys: [],
            date: Self.instant("2026-01-15T12:00:00Z")
        )

        #expect(visible.map(\.region) == ["亚洲", "大洋洲"])
        #expect(visible[0].groups[0].offsetSeconds == 8 * 3600)
        #expect(visible[0].groups[0].cities.map(\.name) == ["北京"])
        #expect(visible[1].groups[0].offsetSeconds == 8 * 3600)
        #expect(visible[1].groups[0].cities.map(\.name) == ["珀斯"])
    }

    @Test func favoriteGroupsCollectCitiesGloballyByOffset() {
        let regions = [
            TimezoneRegion(region: "亚洲", timezones: [
                Self.city("北京", identifier: "Asia/Shanghai")
            ]),
            TimezoneRegion(region: "大洋洲", timezones: [
                Self.city("珀斯", identifier: "Australia/Perth")
            ])
        ]

        let favorites = TimezoneViewerLogic.favoriteGroups(
            regions,
            favoriteKeys: ["Asia/Shanghai", "Australia/Perth"],
            date: Self.instant("2026-01-15T12:00:00Z")
        )
        let favoriteNames = favorites[0].cities.map { $0.name }

        #expect(favorites.count == 1)
        #expect(favorites[0].offsetSeconds == 8 * 3600)
        #expect(favoriteNames == ["北京", "珀斯"])
    }

    @Test func favoriteIdentitySurvivesDSTOffsetChanges() {
        let regions = [
            TimezoneRegion(region: "北美", timezones: [
                Self.city("纽约", identifier: "America/New_York")
            ])
        ]

        let winterFavorites = TimezoneViewerLogic.favoriteGroups(
            regions,
            favoriteKeys: ["America/New_York"],
            date: Self.instant("2026-01-15T12:00:00Z")
        )
        let summerFavorites = TimezoneViewerLogic.favoriteGroups(
            regions,
            favoriteKeys: ["America/New_York"],
            date: Self.instant("2026-07-15T12:00:00Z")
        )

        #expect(winterFavorites[0].cities.map(\.name) == ["纽约"])
        #expect(winterFavorites[0].offsetSeconds == -5 * 3600)
        #expect(summerFavorites[0].cities.map(\.name) == ["纽约"])
        #expect(summerFavorites[0].offsetSeconds == -4 * 3600)
    }

    @Test func favoriteDoesNotHideUnrelatedCitiesWithSameCurrentOffset() {
        let regions = [
            TimezoneRegion(region: "北美", timezones: [
                Self.city("纽约", identifier: "America/New_York")
            ]),
            TimezoneRegion(region: "南美", timezones: [
                Self.city("利马", identifier: "America/Lima")
            ])
        ]

        let visible = TimezoneViewerLogic.visibleRegionGroups(
            regions,
            favoriteKeys: ["America/New_York"],
            date: Self.instant("2026-01-15T12:00:00Z")
        )

        #expect(visible.map(\.region) == ["南美"])
        #expect(visible[0].groups[0].cities.map(\.name) == ["利马"])
    }

    private static func city(_ name: String, identifier: String) -> TimezoneInfo {
        TimezoneInfo(
            timezone: TimeZone(identifier: identifier)!,
            name: name,
            region: "测试"
        )
    }

    private static func catalogContains(
        _ regions: [TimezoneRegion],
        region regionName: String,
        name cityName: String,
        identifier: String
    ) -> Bool {
        regions.contains { region in
            region.region == regionName && region.timezones.contains { city in
                city.name == cityName && city.timezone.identifier == identifier && city.region == regionName
            }
        }
    }

    private static func instant(_ value: String) -> Date {
        ISO8601DateFormatter().date(from: value)!
    }
}
