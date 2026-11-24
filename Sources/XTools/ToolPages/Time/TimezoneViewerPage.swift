import SwiftUI

@MainActor
final class TimezoneViewerDisclosureExpansionStore: PersistentDisclosureExpansionStore {
    static let storageKey = "tools.timezoneViewer.collapsedSections.v1"

    init(defaults: UserDefaults = .standard) {
        super.init(storageKey: Self.storageKey, defaults: defaults)
    }
}

@MainActor
final class TimezoneViewerFavoriteStore: ObservableObject {
    static let storageKey = "tools.timezoneViewer.favorites.v1"

    @Published private(set) var favoriteKeys: Set<String>

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let raw = defaults.array(forKey: Self.storageKey) as? [String] ?? []
        self.favoriteKeys = Set(raw)
    }

    @discardableResult
    func toggle(keys: Set<String>) -> Bool {
        if keys.isSubset(of: favoriteKeys) {
            favoriteKeys.subtract(keys)
            persist()
            return false
        }

        favoriteKeys.formUnion(keys)
        persist()
        return true
    }

    private func persist() {
        defaults.set(favoriteKeys.sorted(), forKey: Self.storageKey)
    }
}

struct IndexTimezoneViewerPage: View {
    @Environment(\.toolPageEntryGeneration) private var entryGeneration
    @StateObject private var favoriteStore = TimezoneViewerFavoriteStore()
    @StateObject private var disclosureSections = TimezoneViewerDisclosureExpansionStore()

    private static let favoritesDisclosureID = "favorites"

    var body: some View {
        TimelineView(.animation(minimumInterval: 1, paused: entryGeneration == 0)) { timeline in
            page(currentTime: timeline.date)
        }
    }

    private func page(currentTime: Date) -> some View {
        IndexPage("时区查看器", subtitle: "显示精选全球城市的当前时间，按大洲折叠并按 UTC 偏移量分组。", workspaceSemantic: .queryListWorkspace) {
            IndexPanel("时区列表") {
                ScrollView {
                    VStack(spacing: ToolMetrics.Spacing.lg) {
                        let projection = TimezoneViewerProjection(favoriteKeys: favoriteStore.favoriteKeys, date: currentTime)
                        let favorites = projection.favoriteGroups
                        if !favorites.isEmpty {
                            timezoneDisclosureSection(
                                sectionID: Self.favoritesDisclosureID,
                                title: "收藏"
                            ) {
                                ForEach(favorites) { group in
                                    timezoneGroupCard(group: group, currentTime: currentTime)
                                }
                            }
                        }

                        ForEach(projection.visibleRegions) { regionGroup in
                            timezoneRegionSection(regionGroup, currentTime: currentTime)
                        }
                    }
                    .padding(ToolMetrics.Spacing.sm)
                    .padding(.bottom, ToolMetrics.Spacing.lg)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .verticallyFilling()
            .withoutDiagnosticStatusSlot()
        }
    }

    private func timezoneRegionSection(_ regionGroup: VisibleTimezoneRegion, currentTime: Date) -> some View {
        timezoneDisclosureSection(
            sectionID: Self.regionDisclosureID(regionGroup.region),
            title: regionGroup.region
        ) {
            ForEach(regionGroup.groups) { group in
                timezoneGroupCard(group: group, currentTime: currentTime)
            }
        }
    }

    private func timezoneDisclosureSection<Content: View>(
        sectionID: String,
        title: String,
        @ViewBuilder content: @escaping () -> Content
    ) -> some View {
        IndexDisclosure(
            title: title,
            isExpanded: Binding(
                get: { disclosureSections.isExpanded(sectionID) },
                set: { _ in disclosureSections.toggle(sectionID) }
            )
        ) {
            VStack(spacing: ToolMetrics.Spacing.sm) {
                content()
            }
        }
        .inline()
    }

    private func timezoneGroupCard(group: TimezoneGroup, currentTime: Date) -> some View {
        let isFavorite = group.favoriteKeys.isSubset(of: favoriteStore.favoriteKeys)
        let clock = Self.clockText(at: currentTime, in: group.cities[0].timezone)

        return IndexSurfaceRow(horizontalPadding: ToolMetrics.Spacing.panelInset, verticalPadding: ToolMetrics.Spacing.md) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text(group.offsetString)
                            .font(ToolTypography.monoCaption)
                            .foregroundStyle(ToolTheme.textSecondary)
                        Text(group.cityNames)
                            .font(ToolTypography.bodyMedium)
                            .foregroundStyle(ToolTheme.textPrimary)
                    }
                    Text(clock.time)
                        .font(ToolTypography.statValue)
                        .foregroundStyle(ToolTheme.textPrimary)
                    Text(clock.date)
                        .font(ToolTypography.caption)
                        .foregroundStyle(ToolTheme.textSecondary)
                }
                Spacer()
                IndexIconButton(
                    systemImage: isFavorite ? "star.fill" : "star",
                    help: "\(isFavorite ? "取消收藏" : "收藏") \(group.offsetString)",
                    isActive: isFavorite,
                    activeTint: ToolTheme.warning
                ) {
                    toggleFavorite(keys: group.favoriteKeys)
                }
            }
        }
    }

    private func toggleFavorite(keys: Set<String>) {
        if favoriteStore.toggle(keys: keys) {
            disclosureSections.expand(Self.favoritesDisclosureID)
        }
    }

    private static func regionDisclosureID(_ region: String) -> String {
        "region.\(region)"
    }

    private static let timeFormat: Date.FormatString = "\(hour: .twoDigits(clock: .twentyFourHour, hourCycle: .zeroBased)):\(minute: .twoDigits):\(second: .twoDigits)"
    private static let dateFormat: Date.FormatString = "\(year: .padded(4))-\(month: .twoDigits)-\(day: .twoDigits) \(weekday: .wide)"
    private static let dateLocale = Locale(identifier: "zh_CN")
    private static let dateCalendar = Calendar(identifier: .gregorian)

    @MainActor static func clockText(at instant: Date, in timezone: TimeZone) -> (time: String, date: String) {
        let time = instant.formatted(.verbatim(timeFormat, timeZone: timezone, calendar: .current))
        let date = instant.formatted(.verbatim(dateFormat, locale: dateLocale, timeZone: timezone, calendar: dateCalendar))
        return (time, date)
    }
}

