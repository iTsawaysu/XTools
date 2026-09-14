import Foundation

public extension RegexMatcher {
    static let presets: [Preset] = [
        Preset(
            id: "mainland-mobile",
            title: "手机号",
            pattern: #"^1[3-9][0-9]{9}$"#,
            flags: "gm",
            examples: [
                Example("13812345678", shouldMatch: true),
                Example("19988887777", shouldMatch: true),
                Example("12012345678", shouldMatch: false),
                Example("1381234567", shouldMatch: false),
                Example("138123456789", shouldMatch: false)
            ]
        ),
        Preset(
            id: "email",
            title: "邮箱",
            pattern: #"^[A-Za-z0-9_%+-]+(?:\.[A-Za-z0-9_%+-]+)*@(?:[A-Za-z0-9](?:[A-Za-z0-9-]{0,61}[A-Za-z0-9])?\.)+[A-Za-z]{2,}$"#,
            flags: "gm",
            examples: [
                Example("test.user@example.com", shouldMatch: true),
                Example("info@my-school.edu.cn", shouldMatch: true),
                Example("bad_email@com", shouldMatch: false),
                Example("@missinguser.com", shouldMatch: false),
                Example("bad..email@example.com", shouldMatch: false),
                Example("user@example-.com", shouldMatch: false)
            ]
        ),
        Preset(
            id: "url",
            title: "URL",
            pattern: #"^https?:\/\/(?:localhost|(?:[A-Za-z0-9](?:[A-Za-z0-9-]{0,61}[A-Za-z0-9])?\.)+[A-Za-z]{2,}|(?:(?:25[0-5]|2[0-4][0-9]|1[0-9]{2}|[1-9]?[0-9])\.){3}(?:25[0-5]|2[0-4][0-9]|1[0-9]{2}|[1-9]?[0-9]))(?::(?:[1-9][0-9]{0,3}|[1-5][0-9]{4}|6[0-4][0-9]{3}|65[0-4][0-9]{2}|655[0-2][0-9]|6553[0-5]))?(?:[\/?#][^\s]*)?$"#,
            flags: "gm",
            examples: [
                Example("https://it-tools.tech/regex-tester", shouldMatch: true),
                Example("http://example.com?a=1", shouldMatch: true),
                Example("http://localhost:3000", shouldMatch: true),
                Example("https://127.0.0.1:8443/path?q=1#frag", shouldMatch: true),
                Example("ftp://example.com", shouldMatch: false),
                Example("https://missing-tld", shouldMatch: false),
                Example("https://example.com:70000", shouldMatch: false),
                Example("https://-example.com", shouldMatch: false)
            ]
        ),
        Preset(
            id: "html-tag-content",
            title: "HTML 标签",
            pattern: #"<([A-Za-z][A-Za-z0-9-]*)(?:\s[^<>]*)?>([\s\S]*?)<\/\1>"#,
            flags: "g",
            examples: [
                Example("<div>欢迎来到正则世界</div>", shouldMatch: true),
                Example("<span>测试文本</span>", shouldMatch: true),
                Example("<h1>标题</h1>", shouldMatch: true),
                Example(#"<a href="https://example.com">链接</a>"#, shouldMatch: true),
                Example("<div>标签不匹配</span>", shouldMatch: false),
                Example("<1div>非法标签</1div>", shouldMatch: false)
            ]
        ),
        Preset(
            id: "ipv4",
            title: "IPv4",
            pattern: #"^(?:(?:25[0-5]|2[0-4][0-9]|1[0-9]{2}|[1-9]?[0-9])\.){3}(?:25[0-5]|2[0-4][0-9]|1[0-9]{2}|[1-9]?[0-9])$"#,
            flags: "gm",
            examples: [
                Example("192.168.1.1", shouldMatch: true),
                Example("127.0.0.1", shouldMatch: true),
                Example("0.0.0.0", shouldMatch: true),
                Example("255.255.255.255", shouldMatch: true),
                Example("256.1.1.1", shouldMatch: false),
                Example("192.168.1", shouldMatch: false),
                Example("192.168.01.1", shouldMatch: false)
            ]
        ),
        Preset(
            id: "strong-password",
            title: "强密码",
            pattern: #"^(?=.*[a-z])(?=.*[A-Z])(?=.*[0-9])[A-Za-z0-9]{8,}$"#,
            flags: "gm",
            examples: [
                Example("Password123", shouldMatch: true),
                Example("p12345678", shouldMatch: false),
                Example("PASSWORD123", shouldMatch: false),
                Example("Ab1", shouldMatch: false),
                Example("Password 123", shouldMatch: false)
            ]
        ),
        Preset(
            id: "date-ymd",
            title: "日期",
            pattern: #"^(?!0000-)(?:(?:[0-9]{4})-(?:(?:0[13578]|1[02])-(?:0[1-9]|[12][0-9]|3[01])|(?:0[469]|11)-(?:0[1-9]|[12][0-9]|30)|02-(?:0[1-9]|1[0-9]|2[0-8]))|(?:[02468][048]00|[13579][26]00|[0-9]{2}(?:0[48]|[2468][048]|[13579][26]))-02-29)$"#,
            flags: "gm",
            examples: [
                Example("2023-05-20", shouldMatch: true),
                Example("1998-12-31", shouldMatch: true),
                Example("2024-02-29", shouldMatch: true),
                Example("2000-02-29", shouldMatch: true),
                Example("2400-02-29", shouldMatch: true),
                Example("2023-13-01", shouldMatch: false),
                Example("2023-01-32", shouldMatch: false),
                Example("2023-02-29", shouldMatch: false),
                Example("1900-02-29", shouldMatch: false),
                Example("2100-02-29", shouldMatch: false),
                Example("0000-01-01", shouldMatch: false)
            ]
        ),
        Preset(
            id: "duplicate-word",
            title: "重复单词",
            pattern: #"\b([A-Za-z]+)\s+\1\b"#,
            flags: "gi",
            examples: [
                Example("I love the the game.", shouldMatch: true),
                Example("This is is a test.", shouldMatch: true),
                Example("The the answer.", shouldMatch: true),
                Example("The theory is sound.", shouldMatch: false),
                Example("area real", shouldMatch: false)
            ]
        ),
        Preset(
            id: "uuid",
            title: "UUID",
            pattern: #"^[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[1-5][0-9A-Fa-f]{3}-[89ABab][0-9A-Fa-f]{3}-[0-9A-Fa-f]{12}$"#,
            flags: "gm",
            examples: [
                Example("550e8400-e29b-41d4-a716-446655440000", shouldMatch: true),
                Example("6ba7b810-9dad-11d1-80b4-00c04fd430c8", shouldMatch: true),
                Example("550e8400e29b41d4a716446655440000", shouldMatch: false),
                Example("550e8400-e29b-61d4-a716-446655440000", shouldMatch: false)
            ]
        ),
        Preset(
            id: "hex-color",
            title: "Hex 颜色",
            pattern: #"^#(?:[0-9A-Fa-f]{3}|[0-9A-Fa-f]{6}|[0-9A-Fa-f]{8})$"#,
            flags: "gm",
            examples: [
                Example("#fff", shouldMatch: true),
                Example("#1A2b3C", shouldMatch: true),
                Example("#11223344", shouldMatch: true),
                Example("123456", shouldMatch: false),
                Example("#12", shouldMatch: false),
                Example("#ggg", shouldMatch: false)
            ]
        )
    ]
}
