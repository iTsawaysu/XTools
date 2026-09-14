import XToolsCore
import Foundation
import Testing

struct ByteSizeFormatterTests {
    @Test func formatBytes() {
        #expect(ByteSizeFormatter.format(bytes: 0) == "0 B")
        #expect(ByteSizeFormatter.format(bytes: 1) == "1 B")
        #expect(ByteSizeFormatter.format(bytes: 512) == "512 B")
        #expect(ByteSizeFormatter.format(bytes: 1023) == "1023 B")
    }

    @Test func formatKilobytes() {
        #expect(ByteSizeFormatter.format(bytes: 1024) == "1 KB")
        #expect(ByteSizeFormatter.format(bytes: 1536) == "1.5 KB")
        #expect(ByteSizeFormatter.format(bytes: 10240) == "10 KB")
        #expect(ByteSizeFormatter.format(bytes: 1048575) == "1024 KB")
    }

    @Test func formatMegabytes() {
        #expect(ByteSizeFormatter.format(bytes: 1048576) == "1 MB")
        #expect(ByteSizeFormatter.format(bytes: 5242880) == "5 MB")
        #expect(ByteSizeFormatter.format(bytes: 1572864) == "1.5 MB")
        #expect(ByteSizeFormatter.format(bytes: 1073741823) == "1024 MB")
    }

    @Test func formatGigabytes() {
        #expect(ByteSizeFormatter.format(bytes: 1073741824) == "1 GB")
        #expect(ByteSizeFormatter.format(bytes: 5368709120) == "5 GB")
        #expect(ByteSizeFormatter.format(bytes: 1610612736) == "1.5 GB")
        #expect(ByteSizeFormatter.format(bytes: 1099511627775) == "1024 GB")
    }

    @Test func formatTerabytes() {
        #expect(ByteSizeFormatter.format(bytes: 1099511627776) == "1 TB")
        #expect(ByteSizeFormatter.format(bytes: 5497558138880) == "5 TB")
        #expect(ByteSizeFormatter.format(bytes: 1649267441664) == "1.5 TB")
    }

    @Test func formatBoundaries() {
        // Test boundary between showing decimals and whole numbers
        #expect(ByteSizeFormatter.format(bytes: 10239) == "10.0 KB")
        #expect(ByteSizeFormatter.format(bytes: 10240) == "10 KB")

        // Test rounding
        #expect(ByteSizeFormatter.format(bytes: 1126) == "1.1 KB") // 1126/1024 = 1.0996
        #expect(ByteSizeFormatter.format(bytes: 1178) == "1.2 KB") // 1178/1024 = 1.1504
    }

    @Test func formatDecimalPlaces() {
        // Values under 10 should show one decimal place
        #expect(ByteSizeFormatter.format(bytes: 2048) == "2 KB")
        #expect(ByteSizeFormatter.format(bytes: 2560) == "2.5 KB")
        #expect(ByteSizeFormatter.format(bytes: 3072) == "3 KB")

        // Values 10 and above should show no decimal places
        #expect(ByteSizeFormatter.format(bytes: 10240) == "10 KB")
        #expect(ByteSizeFormatter.format(bytes: 10752) == "11 KB")
    }
}
