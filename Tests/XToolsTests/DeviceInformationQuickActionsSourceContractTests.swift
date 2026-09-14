import Testing

struct DeviceInformationQuickActionsSourceContractTests {
    @Test func deviceInformationHeaderUsesPureCopySummaryAndTheExistingRefreshCommand() throws {
        let page = try readSource("Sources/XTools/ToolPages/Utility/DeviceInformationPage.swift")
        let query = try readSource("Sources/XTools/ToolPages/Utility/DeviceInformationQuery.swift")

        contains(
            query,
            "static func copySummary(from snapshot: DeviceInformationSnapshot) -> String",
            "Device information copy-all formatting must remain pure projection logic"
        )
        contains(
            query,
            "fields(from: snapshot)",
            "Copy-all formatting must reuse the visible field projection instead of a second field list"
        )
        contains(
            page,
            "DeviceInformationProjection.copySummary(from: session.snapshot)",
            "Copy-all content must derive from the current snapshot"
        )
        contains(
            page,
            "IndexCopyButton(text: copySummary, title: \"复制全部\")",
            "Device information must use shared clipboard feedback for copy all"
        )
        contains(
            page,
            "Label(\"刷新\", systemImage: IndexActionSymbol.refresh)",
            "Device information must expose a visible manual refresh action"
        )
        contains(page, ".help(\"刷新设备信息\")", "Manual refresh must explain its action")
        contains(
            page,
            ".accessibilityLabel(\"刷新设备信息\")",
            "Manual refresh must keep a stable Chinese accessibility label"
        )
        occurrenceCount(
            page,
            "session.refresh()",
            2,
            "Screen changes and the manual header action must share the same refresh command"
        )

        contains(page, "ScrollView {", "Device information must retain its internal scroll owner")
        contains(page, "IndexKV(rows: rows, emptyText: \"加载设备信息中…\", copyable: true)", "Per-row copy must remain available")
        contains(page, ".verticallyFilling()", "The fixed query list must continue filling the panel")
        doesNotContain(page, "Timer", "Manual refresh must not introduce periodic collection")
        doesNotContain(page, "ProgressView", "Synchronous refresh must not add a fake loading state")
        doesNotContain(page, ".toolAnimation(", "Device refresh must not add decorative animation")
    }
}
