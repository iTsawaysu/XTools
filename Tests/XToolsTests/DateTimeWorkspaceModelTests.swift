import Foundation
import Testing
@testable import XTools

@MainActor
struct DateTimeWorkspaceModelTests {
    @Test func fractionalInitializationUsesOneWholeSecondInstantForEveryResult() {
        let wholeSeconds: TimeInterval = 1_784_114_511
        let workspace = DateTimeToolWorkspaceModel(
            date: Date(timeIntervalSince1970: wholeSeconds + 0.986)
        )
        let rows = Dictionary(uniqueKeysWithValues: workspace.rows.map { ($0.0, $0.1) })

        #expect(workspace.timestamp == "1784114511")
        #expect(workspace.activeDate?.timeIntervalSince1970 == wholeSeconds)
        #expect(rows["Unix 秒"] == "1784114511")
        #expect(rows["Unix 毫秒"] == "1784114511000")
        #expect(rows["ISO 8601"] == "2026-07-15T11:21:51Z")
    }
}
