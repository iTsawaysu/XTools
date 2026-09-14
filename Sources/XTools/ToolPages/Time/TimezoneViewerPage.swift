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
    @StateObject private var favoriteStore = TimezoneViewerFavoriteStore()
    @StateObject private var disclosureSections = TimezoneViewerDisclosureExpansionStore()

    private static let favoritesDisclosureID = "favorites"

    var body: some View {
        TimelineView(.periodic(from: Date(), by: 1)) { timeline in
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
                    Text(formatTime(for: group.cities[0].timezone, currentTime: currentTime))
                        .font(ToolTypography.statValue)
                        .foregroundStyle(ToolTheme.textPrimary)
                    Text(formatDate(for: group.cities[0].timezone, currentTime: currentTime))
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

    private func formatTime(for timezone: TimeZone, currentTime: Date) -> String {
        Self.timeFormatter.timeZone = timezone
        return Self.timeFormatter.string(from: currentTime)
    }

    private func formatDate(for timezone: TimeZone, currentTime: Date) -> String {
        Self.dateFormatter.timeZone = timezone
        return Self.dateFormatter.string(from: currentTime)
    }

    @MainActor private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter
    }()

    @MainActor private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd EEEE"
        formatter.locale = Locale(identifier: "zh_CN")
        return formatter
    }()
}

