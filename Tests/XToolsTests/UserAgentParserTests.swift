import XToolsCore
import Testing

struct UserAgentParserTests {
    // MARK: - Empty input

    @Test func returnsNilForEmptyOrWhitespaceInput() {
        #expect(UserAgentParser.parse("") == nil)
        #expect(UserAgentParser.parse("   \n ") == nil)
    }

    @Test func rejectsStructurallyInvalidUserAgentInput() {
        #expect(UserAgentParser.parse("///") == nil)
        #expect(UserAgentParser.validationIssue("///") == .missingProductToken)
        #expect(UserAgentParser.parse("你好") == nil)
        #expect(UserAgentParser.validationIssue("Mozilla/5.0\nChrome/120") == .containsControlCharacter)
    }

    @Test func validationMessagesAreFactualAndDoNotEchoInput() {
        let terminalLog = "osascript System Events /tmp/private-capture.mov execution error"
        for issue in [
            UserAgentParser.ValidationIssue.containsControlCharacter,
            .missingProductToken,
        ] {
            ToolDiagnosticContract.expectFactual(
                issue.errorDescription ?? "",
                sensitiveInputs: [terminalLog]
            )
        }
        #expect(UserAgentParser.validationIssue(terminalLog) == .missingProductToken)
    }

    // MARK: - Browser detection

    @Test func detectsChromeWithVersion() {
        let ua = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"
        let result = UserAgentParser.parse(ua)
        #expect(result?.browser == "Google Chrome")
        #expect(result?.browserVersion == "120.0.0.0")
    }

    @Test func detectsEdgeAndNotChrome() {
        // Edge UA also contains "chrome/"; the edg/ branch must win.
        let ua = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36 Edg/120.0.0.0"
        let result = UserAgentParser.parse(ua)
        #expect(result?.browser == "Microsoft Edge")
        #expect(result?.browserVersion == "120.0.0.0")
    }

    @Test func detectsFirefox() {
        let ua = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10.15; rv:121.0) Gecko/20100101 Firefox/121.0"
        let result = UserAgentParser.parse(ua)
        #expect(result?.browser == "Mozilla Firefox")
        #expect(result?.browserVersion == "121.0")
    }

    @Test func detectsSafariNotChrome() {
        let ua = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.1 Safari/605.1.15"
        let result = UserAgentParser.parse(ua)
        #expect(result?.browser == "Apple Safari")
        #expect(result?.browserVersion == "17.1")
    }

    @Test func detectsLegacyOpera() {
        let ua = "Opera/9.80 (Windows NT 6.1; U; en) Presto/2.9.168 Version/12.16"
        let result = UserAgentParser.parse(ua)
        #expect(result?.browser == "Opera")
        #expect(result?.browserVersion == "12.16")
    }

    @Test func detectsModernOperaBeforeChrome() {
        let ua = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/106.0.0.0 Safari/537.36 OPR/92.0.0.0"
        let result = UserAgentParser.parse(ua)
        #expect(result?.browser == "Opera")
        #expect(result?.browserVersion == "92.0.0.0")
    }

    @Test func unknownBrowserFallsBackToPlaceholder() {
        let result = UserAgentParser.parse("SomeRandomBot/1.0")
        #expect(result?.browser == "(未知)")
        #expect(result?.browserVersion == "(未知)")
    }

    // MARK: - OS detection

    @Test func mapsKnownWindowsNTVersions() {
        #expect(UserAgentParser.parse("Mozilla/5.0 (Windows NT 10.0)")?.osVersion == "10")
        #expect(UserAgentParser.parse("Mozilla/5.0 (Windows NT 6.3)")?.osVersion == "8.1")
        #expect(UserAgentParser.parse("Mozilla/5.0 (Windows NT 6.2)")?.osVersion == "8")
        #expect(UserAgentParser.parse("Mozilla/5.0 (Windows NT 6.1)")?.osVersion == "7")
        let win = UserAgentParser.parse("Mozilla/5.0 (Windows NT 10.0)")
        #expect(win?.os == "Windows")
    }

    @Test func normalizesUnderscoresInMacVersion() {
        // macOS reports its version with underscores; the parser normalizes to dots.
        let mac = UserAgentParser.parse("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7)")
        #expect(mac?.os == "macOS")
        #expect(mac?.osVersion == "10.15.7")
    }

    @Test func detectsIOSBeforeMacOSCompatibilityToken() {
        let ios = UserAgentParser.parse("Mozilla/5.0 (iPhone; CPU iPhone OS 17_1 like Mac OS X)")
        #expect(ios?.os == "iOS")
        #expect(ios?.osVersion == "17.1")
    }

    @Test func detectsAndroidBeforeLinuxCompatibilityToken() {
        let android = UserAgentParser.parse("Mozilla/5.0 (Linux; Android 14; Pixel 8)")
        #expect(android?.os == "Android")
        #expect(android?.osVersion == "14")

        let pureAndroid = UserAgentParser.parse("Dalvik/2.1.0 (Android 14; Pixel 8)")
        #expect(pureAndroid?.os == "Android")
        #expect(pureAndroid?.osVersion == "14")

        let linux = UserAgentParser.parse("Mozilla/5.0 (X11; Linux x86_64)")
        #expect(linux?.os == "Linux")
        #expect(linux?.osVersion == "(未知)")
    }

    // MARK: - Device detection

    @Test func classifiesExplicitMobileAndTabletEvidence() {
        #expect(UserAgentParser.parse("Mozilla/5.0 (iPhone; CPU iPhone OS 17_1 like Mac OS X)")?.device == "Mobile")
        #expect(UserAgentParser.parse("Mozilla/5.0 (iPad; CPU OS 17_1 like Mac OS X)")?.device == "Tablet")
        #expect(UserAgentParser.parse("Mozilla/5.0 (Linux; Android 14; Pixel Tablet)")?.device == "Tablet")
        #expect(UserAgentParser.parse("Mozilla/5.0 (Linux; Android 14; Pixel 8) AppleWebKit/537.36 Chrome/120.0 Mobile Safari/537.36")?.device == "Mobile")
    }

    @Test func classifiesKnownDesktopBrowsersOnDesktopOperatingSystems() {
        let chromeWindows = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"
        let safariMac = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.1 Safari/605.1.15"
        let firefoxLinux = "Mozilla/5.0 (X11; Linux x86_64; rv:121.0) Gecko/20100101 Firefox/121.0"

        #expect(UserAgentParser.parse(chromeWindows)?.device == "Desktop")
        #expect(UserAgentParser.parse(safariMac)?.device == "Desktop")
        #expect(UserAgentParser.parse(firefoxLinux)?.device == "Desktop")
    }

    @Test func leavesUnknownProductsAndAmbiguousDesktopEvidenceUnknown() {
        for ua in [
            "SomeRandomBot/1.0",
            "curl/8.7.1",
            "SomeRandomBot/1.0 (Linux x86_64)",
            "CustomClient/2.4 (Windows NT 10.0; Win64; x64)",
            "Chrome/120.0.0.0",
        ] {
            #expect(UserAgentParser.parse(ua)?.device == "(未知)")
        }
    }
}
