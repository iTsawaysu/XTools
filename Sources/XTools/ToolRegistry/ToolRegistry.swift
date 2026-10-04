import Foundation

struct ToolRegistryCategoryGroup: Hashable {
    let category: ToolCategory
    let tools: [RegisteredTool]
}

/// One ranked search hit: the tool plus the engine match that ranked it.
/// `match` is nil only for the unfiltered empty-query pass-through.
struct ToolRegistryRankedMatch {
    let tool: RegisteredTool
    let match: ToolSearchEngine.Match?
}

struct ToolRegistry {
    private let categories: [ToolCategory]
    private let tools: [RegisteredTool]
    private let categoryByID: [ToolCategoryID: ToolCategory]
    private let toolByID: [ToolID: RegisteredTool]
    // Folded + pinyin search records are prebuilt once per registry; queries
    // only run comparisons against them (see `ToolSearchRecord`).
    private let searchRecordByID: [ToolID: ToolSearchRecord]
    // Preserve the original tool ordering within each category.
    private let toolsByCategory: [ToolCategoryID: [RegisteredTool]]

    init(categories: [ToolCategory], tools: [RegisteredTool]) {
        self.categories = categories
        self.tools = tools
        self.categoryByID = Dictionary(uniqueKeysWithValues: categories.map { ($0.id, $0) })
        self.toolByID = Dictionary(uniqueKeysWithValues: tools.map { ($0.id, $0) })
        self.toolsByCategory = Dictionary(grouping: tools) { $0.categoryID }
        self.searchRecordByID = Dictionary(uniqueKeysWithValues: tools.map { tool in
            (
                tool.id,
                ToolSearchRecord(
                    title: tool.title,
                    keywords: tool.keywords,
                    aliases: tool.aliases
                )
            )
        })
    }

    var toolCount: Int {
        tools.count
    }

    func category(for id: ToolCategoryID) -> ToolCategory? {
        categoryByID[id]
    }

    func categoryTitle(for id: ToolCategoryID) -> String? {
        category(for: id)?.title
    }

    func categoryGroups() -> [ToolRegistryCategoryGroup] {
        categories.map { category in
            ToolRegistryCategoryGroup(
                category: category,
                tools: toolsByCategory[category.id] ?? []
            )
        }
    }

    func tools(for ids: [ToolID]) -> [RegisteredTool] {
        ids.compactMap { toolByID[$0] }
    }

    func tool(for id: ToolID) -> RegisteredTool? {
        toolByID[id]
    }

    func firstToolIDInCategoryOrder() -> ToolID? {
        categoryGroups()
            .lazy
            .compactMap { $0.tools.first?.id }
            .first
    }

    /// Ranked matches for the palette projection: tier order first, fzf
    /// score within a tier, original registration order as the final stable
    /// tiebreak. An empty query passes every tool through unranked, which
    /// `matchingTools(query:)` preserves as plain registration order.
    func matchingToolMatches(query rawQuery: String) -> [ToolRegistryRankedMatch] {
        let query = rawQuery.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !query.isEmpty else {
            return tools.map { ToolRegistryRankedMatch(tool: $0, match: nil) }
        }

        struct RankedHit {
            let tool: RegisteredTool
            let match: ToolSearchEngine.Match
            let originalIndex: Int
        }

        // Records are prebuilt for every tool in init; a miss means the tool
        // did not come from this registry, so it simply does not match.
        let hits = tools.enumerated().compactMap { originalIndex, tool -> RankedHit? in
            guard let record = searchRecordByID[tool.id],
                  let match = ToolSearchEngine.match(record: record, query: query)
            else { return nil }
            return RankedHit(tool: tool, match: match, originalIndex: originalIndex)
        }

        return hits
            .sorted { left, right in
                if left.match.tier != right.match.tier {
                    return left.match.tier < right.match.tier
                }
                if left.match.score != right.match.score {
                    return left.match.score > right.match.score
                }
                return left.originalIndex < right.originalIndex
            }
            .map { ToolRegistryRankedMatch(tool: $0.tool, match: $0.match) }
    }

    func matchingTools(query rawQuery: String) -> [RegisteredTool] {
        matchingToolMatches(query: rawQuery).map(\.tool)
    }
}

extension ToolRegistry {
    static let `default` = ToolRegistry(
        categories: [
            ToolCategory(
                id: .converter,
                title: "编码与转换",
                systemImage: "arrow.left.arrow.right"
            ),
            ToolCategory(
                id: .crypto,
                title: "加密与生成",
                systemImage: "lock.shield"
            ),
            ToolCategory(
                id: .development,
                title: "开发",
                systemImage: "hammer"
            ),
            ToolCategory(
                id: .web,
                title: "Web",
                systemImage: "globe"
            ),
            ToolCategory(
                id: .image,
                title: "图像与颜色",
                systemImage: "photo"
            ),
            ToolCategory(
                id: .time,
                title: "时间与日期",
                systemImage: "clock"
            ),
            ToolCategory(
                id: .utility,
                title: "辅助工具",
                systemImage: "wrench.and.screwdriver"
            )
        ],
        tools: [
            // MARK: - 编码与转换
            // Hub 别名的 label 与页面分段 label 一致、segment 即分段 rawValue；
            // matching 逐字吸收原有功能性关键词，保证命中 tier/score 不变。
            RegisteredTool(
                id: "base64-file-converter",
                title: "Base64 文件",
                categoryID: .converter,
                systemImage: "doc",
                keywords: ["base64", "file", "encode", "decode", "文件"],
                aliases: [
                    ToolAlias("Data URL", matching: ["dataurl", "data url"])
                ]
            ) {
                IndexBase64FilePage()
            },
            RegisteredTool(
                id: "text-encoding",
                title: "文本编码",
                categoryID: .converter,
                systemImage: "text.quote",
                keywords: ["encode", "decode", "text", "convert"],
                aliases: [
                    ToolAlias("Base64", matching: ["base64"], segment: "base64"),
                    ToolAlias("URL", matching: ["url", "percent"], segment: "url"),
                    ToolAlias("ASCII/二进制", matching: ["ascii", "binary", "二进制"], segment: "ascii"),
                    ToolAlias("Unicode", matching: ["unicode", "escape"], segment: "unicode")
                ]
            ) {
                IndexEncodingHubPage()
            },
            RegisteredTool(
                id: "integer-base-converter",
                title: "进制转换",
                categoryID: .converter,
                systemImage: "arrow.left.arrow.right.square",
                keywords: ["integer", "base", "进制"],
                aliases: [
                    ToolAlias("二进制", matching: ["binary"]),
                    ToolAlias("八进制", matching: ["octal"]),
                    ToolAlias("十进制", matching: ["decimal"]),
                    ToolAlias("十六进制", matching: ["hex", "hexadecimal"])
                ]
            ) {
                IndexBaseConverterPage()
            },
            RegisteredTool(
                id: "roman-numeral-converter",
                title: "罗马数字",
                categoryID: .converter,
                systemImage: "building.columns",
                keywords: ["roman", "numeral", "convert"]
            ) {
                IndexRomanPage()
            },
            RegisteredTool(
                id: "case-converter",
                title: "大小写转换",
                categoryID: .converter,
                systemImage: "textformat.size",
                keywords: ["case", "大小写"],
                aliases: [
                    ToolAlias("camelCase", matching: ["camel"]),
                    ToolAlias("snake_case", matching: ["snake"]),
                    ToolAlias("kebab-case", matching: ["kebab"]),
                    ToolAlias("大写", matching: ["upper"]),
                    ToolAlias("小写", matching: ["lower"])
                ]
            ) {
                IndexCaseConverterPage()
            },

            // MARK: - 加密与生成
            RegisteredTool(
                id: "hash-text",
                title: "Hash 文本",
                categoryID: .crypto,
                systemImage: "number",
                keywords: ["hash", "digest", "摘要"],
                aliases: [
                    ToolAlias("MD5", matching: ["md5"]),
                    ToolAlias("SHA-1", matching: ["sha1", "sha-1"]),
                    ToolAlias("SHA-256", matching: ["sha256", "sha-256"]),
                    ToolAlias("SHA-512", matching: ["sha512", "sha-512"]),
                    ToolAlias("SHA-3", matching: ["sha3", "sha-3"])
                ]
            ) {
                IndexHashTextPage()
            },
            RegisteredTool(
                id: "text-encryption",
                title: "文本加密",
                categoryID: .crypto,
                systemImage: "lock",
                keywords: ["encrypt", "decrypt", "cipher", "加密", "解密"],
                aliases: [
                    ToolAlias("AES", matching: ["aes"])
                ]
            ) {
                IndexTextEncryptionPage()
            },
            RegisteredTool(
                id: "string-obfuscator",
                title: "字符串遮蔽",
                categoryID: .crypto,
                systemImage: "eye.slash",
                keywords: ["string", "obfuscate", "mask", "redact", "混淆", "脱敏", "遮蔽"]
            ) {
                IndexStringObfuscatorPage()
            },
            RegisteredTool(
                id: "generator",
                title: "生成器",
                categoryID: .crypto,
                systemImage: "shuffle",
                keywords: ["random", "secret", "generate", "unique", "identifier", "随机", "生成", "强度"],
                aliases: [
                    ToolAlias("Token", matching: ["token"], segment: "token"),
                    ToolAlias("UUID", matching: ["uuid", "guid"], segment: "uuid"),
                    ToolAlias("密码", matching: ["password"], segment: "password")
                ]
            ) {
                IndexGeneratorHubPage()
            },

            // MARK: - 开发
            RegisteredTool(
                id: "formatter",
                title: "格式化",
                categoryID: .development,
                systemImage: "curlybraces.square",
                keywords: ["format", "prettify", "beautify", "minify", "compress", "格式化", "美化", "压缩"],
                aliases: [
                    ToolAlias("JSON", matching: ["json"], segment: "json"),
                    ToolAlias("XML", matching: ["xml"], segment: "xml"),
                    ToolAlias("YAML", matching: ["yaml", "yml"], segment: "yaml"),
                    ToolAlias("SQL", matching: ["sql"], segment: "sql")
                ]
            ) {
                IndexFormatterHubPage()
            },
            RegisteredTool(
                id: "diff",
                title: "对比",
                categoryID: .development,
                systemImage: "square.split.2x1",
                keywords: ["diff", "compare", "difference", "对比"],
                aliases: [
                    ToolAlias("JSON", matching: ["json"], segment: "json"),
                    ToolAlias("文本", matching: ["text"], segment: "text")
                ]
            ) {
                IndexDiffHubPage()
            },
            RegisteredTool(
                id: "regex-tester",
                title: "正则测试",
                categoryID: .development,
                systemImage: "text.magnifyingglass",
                keywords: ["regex", "regular expression", "pattern", "test", "正则"]
            ) {
                IndexRegexPage()
            },
            RegisteredTool(
                id: "docker-run-to-docker-compose-converter",
                title: "Docker Run ↔ Compose",
                categoryID: .development,
                systemImage: "shippingbox",
                keywords: ["docker", "compose", "convert", "run", "容器", "双向转换"]
            ) {
                IndexDockerPage()
            },
            RegisteredTool(
                id: "html-to-markdown",
                title: "HTML → Markdown",
                categoryID: .development,
                systemImage: "doc.plaintext",
                keywords: ["html", "markdown", "convert", "url", "转换"]
            ) {
                IndexHTMLToMarkdownPage()
            },
            RegisteredTool(
                id: "crontab-generator",
                title: "Crontab 生成",
                categoryID: .development,
                systemImage: "clock.arrow.circlepath",
                keywords: ["cron", "crontab", "schedule", "timer", "定时"]
            ) {
                IndexCrontabPage()
            },
            RegisteredTool(
                id: "random-port-generator",
                title: "随机端口",
                categoryID: .development,
                systemImage: "server.rack",
                keywords: ["port", "random", "network", "socket", "随机端口", "可用端口"]
            ) {
                IndexPortPage()
            },
            RegisteredTool(
                id: "chmod-calculator",
                title: "Chmod 计算器",
                categoryID: .development,
                systemImage: "terminal",
                keywords: ["chmod", "permission", "unix", "linux", "权限"]
            ) {
                IndexChmodPage()
            },
            RegisteredTool(
                id: "source-control",
                title: "源码管理",
                categoryID: .development,
                systemImage: "arrow.triangle.branch",
                keywords: ["git", "repository", "pull", "source control", "源码", "仓库"]
            ) {
                IndexSourceControlPage()
            },

            // MARK: - Web
            RegisteredTool(
                id: "jwt-parser",
                title: "JWT",
                categoryID: .web,
                systemImage: "ticket",
                keywords: ["jwt", "json web token", "generate", "sign", "encode", "parse", "decode", "生成", "签名", "解析"]
            ) {
                IndexJWTPage()
            },
            RegisteredTool(
                id: "basic-auth-generator",
                title: "Basic Auth",
                categoryID: .web,
                systemImage: "key",
                keywords: ["basic", "auth", "authorization", "header", "generate", "parse", "decode", "生成", "解析", "解码"]
            ) {
                IndexBasicAuthPage()
            },
            RegisteredTool(
                id: "http-status-codes",
                title: "HTTP 状态码",
                categoryID: .web,
                systemImage: "network",
                keywords: ["http", "status", "code", "response"]
            ) {
                IndexHTTPStatusPage()
            },
            RegisteredTool(
                id: "useragent-parser",
                title: "User-Agent 解析",
                categoryID: .web,
                systemImage: "rectangle.and.text.magnifyingglass",
                keywords: ["useragent", "user agent", "browser", "parser", "浏览器"]
            ) {
                IndexUserAgentParserPage()
            },
            RegisteredTool(
                id: "keycode-info",
                title: "键盘事件",
                categoryID: .web,
                systemImage: "keyboard",
                keywords: ["keycode", "keyboard", "key", "event", "按键", "键盘事件"]
            ) {
                IndexKeycodePage()
            },

            // MARK: - 图像与颜色
            RegisteredTool(
                id: "image-tools",
                title: "图片处理",
                categoryID: .image,
                systemImage: "photo.on.rectangle.angled",
                keywords: [
                    "image", "photo", "picture", "watermark", "图片",
                    "generate", "生成", "水印"
                ],
                aliases: [
                    ToolAlias("格式转换", matching: ["convert", "format", "转换", "png", "jpg", "webp"], segment: "convert"),
                    ToolAlias("压缩", matching: ["compress", "optimize", "压缩"], segment: "compress"),
                    ToolAlias("灰度", matching: ["grayscale", "filter", "灰度"], segment: "grayscale"),
                    ToolAlias("水印", matching: ["watermark", "水印"], segment: "watermark"),
                    ToolAlias("Favicon", matching: ["favicon", "icon", "图标"], segment: "favicon")
                ]
            ) {
                IndexImageHubPage()
            },
            RegisteredTool(
                id: "color-picker",
                title: "颜色转换",
                categoryID: .image,
                systemImage: "paintpalette",
                keywords: ["color", "picker"],
                aliases: [
                    ToolAlias("HEX", matching: ["hex"]),
                    ToolAlias("RGB", matching: ["rgb"]),
                    ToolAlias("HSL", matching: ["hsl"])
                ]
            ) {
                IndexColorPage()
            },

            // MARK: - 时间与日期
            RegisteredTool(
                id: "date-time-converter",
                title: "时间戳转换",
                categoryID: .time,
                systemImage: "calendar",
                keywords: ["date", "time", "timestamp", "unix", "epoch", "convert", "时间戳"]
            ) {
                IndexDateTimePage()
            },
            RegisteredTool(
                id: "timezone-viewer",
                title: "时区查看器",
                categoryID: .time,
                systemImage: "globe.americas",
                keywords: ["timezone", "time", "zone", "world", "时区", "时间"]
            ) {
                IndexTimezoneViewerPage()
            },
            RegisteredTool(
                id: "date-calculator",
                title: "日期计算",
                categoryID: .time,
                systemImage: "calendar.badge.clock",
                keywords: ["date", "calculate", "difference", "add", "subtract", "日期"]
            ) {
                IndexDateCalcPage()
            },
            RegisteredTool(
                id: "chronometer",
                title: "计时器",
                categoryID: .time,
                systemImage: "timer",
                keywords: ["timer", "stopwatch", "chronometer", "lap", "计时", "秒表"]
            ) {
                IndexChronometerPage()
            },

            // MARK: - 辅助工具
            RegisteredTool(
                id: "device-information",
                title: "设备信息",
                categoryID: .utility,
                systemImage: "desktopcomputer",
                keywords: ["device", "system", "info", "hardware", "设备", "系统"]
            ) {
                IndexDeviceInfoPage()
            },
            RegisteredTool(
                id: "file-type-detector",
                title: "文件类型探测器",
                categoryID: .utility,
                systemImage: "doc.questionmark",
                keywords: ["file", "type", "mime", "detect", "文件", "类型"]
            ) {
                IndexFileTypeDetectorPage()
            },
            RegisteredTool(
                id: "math-evaluator",
                title: "数学计算",
                categoryID: .utility,
                systemImage: "function",
                keywords: ["math", "evaluate", "calculate", "expression"]
            ) {
                IndexMathPage()
            },
            RegisteredTool(
                id: "text-statistics",
                title: "文本统计",
                categoryID: .utility,
                systemImage: "chart.bar.doc.horizontal",
                keywords: ["text", "statistics", "word count", "analyze", "统计"]
            ) {
                IndexTextStatsPage()
            },
            RegisteredTool(
                id: "emoji-picker",
                title: "Emoji 与符号",
                categoryID: .utility,
                systemImage: "face.smiling",
                keywords: ["emoji", "icon", "smiley", "symbol", "symbols", "表情", "符号", "特殊符号"]
            ) {
                IndexEmojiPage()
            }
        ]
    )
}
