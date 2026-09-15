import Foundation

struct ToolRegistryCategoryGroup: Hashable {
    let category: ToolCategory
    let tools: [RegisteredTool]
}

struct ToolRegistry {
    enum MatchRank: Int {
        case titlePrefix = 0
        case titleContains = 1
        case keyword = 2
    }

    private let categories: [ToolCategory]
    private let tools: [RegisteredTool]
    private let categoryByID: [ToolCategoryID: ToolCategory]
    private let toolByID: [ToolID: RegisteredTool]
    private struct SearchRecord {
        let title: String
        let keywords: [String]
    }
    private let searchRecordByID: [ToolID: SearchRecord]
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
                SearchRecord(
                    title: Self.normalizedSearchText(tool.title),
                    keywords: tool.keywords.map(Self.normalizedSearchText)
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

    func matchRank(for tool: RegisteredTool, query rawQuery: String) -> MatchRank? {
        let query = Self.normalizedSearchText(rawQuery.trimmingCharacters(in: .whitespacesAndNewlines))
        return matchRank(for: tool, normalizedQuery: query)
    }

    private func matchRank(for tool: RegisteredTool, normalizedQuery query: String) -> MatchRank? {
        let record = searchRecordByID[tool.id] ?? SearchRecord(
            title: Self.normalizedSearchText(tool.title),
            keywords: tool.keywords.map(Self.normalizedSearchText)
        )

        if record.title.hasPrefix(query) {
            return .titlePrefix
        }

        if record.title.contains(query) {
            return .titleContains
        }

        if record.keywords.contains(where: { $0.contains(query) }) {
            return .keyword
        }

        return nil
    }

    func matchingTools(query rawQuery: String) -> [RegisteredTool] {
        let query = rawQuery.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !query.isEmpty else {
            return tools
        }
        let normalizedQuery = Self.normalizedSearchText(query)

        return tools.enumerated()
            .compactMap { originalIndex, tool -> (rank: MatchRank, originalIndex: Int, tool: RegisteredTool)? in
                guard let rank = matchRank(for: tool, normalizedQuery: normalizedQuery) else { return nil }
                return (rank, originalIndex, tool)
            }
            .sorted { left, right in
                if left.rank.rawValue != right.rank.rawValue {
                    return left.rank.rawValue < right.rank.rawValue
                }
                return left.originalIndex < right.originalIndex
            }
            .map(\.tool)
    }

    private static func normalizedSearchText(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
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
            RegisteredTool(
                id: "base64-file-converter",
                title: "Base64 文件",
                categoryID: .converter,
                systemImage: "doc",
                keywords: ["base64", "file", "encode", "decode", "文件", "dataurl"]
            ) {
                IndexBase64FilePage()
            },
            RegisteredTool(
                id: "base64-string",
                title: "Base64 字符串",
                categoryID: .converter,
                systemImage: "text.quote",
                keywords: ["base64", "encode", "decode"]
            ) {
                IndexBase64StringPage()
            },
            RegisteredTool(
                id: "url-encoder-decoder",
                title: "URL 编解码",
                categoryID: .converter,
                systemImage: "link",
                keywords: ["url", "encode", "decode", "percent"]
            ) {
                IndexURLCoderPage()
            },
            RegisteredTool(
                id: "text-to-ascii-binary",
                title: "ASCII / 二进制",
                categoryID: .converter,
                systemImage: "01.square",
                keywords: ["ascii", "binary", "text", "convert", "二进制"]
            ) {
                IndexASCIIBinaryPage()
            },
            RegisteredTool(
                id: "text-to-unicode",
                title: "Unicode 转换",
                categoryID: .converter,
                systemImage: "textformat",
                keywords: ["unicode", "text", "convert", "escape"]
            ) {
                IndexUnicodePage()
            },
            RegisteredTool(
                id: "integer-base-converter",
                title: "进制转换",
                categoryID: .converter,
                systemImage: "arrow.left.arrow.right.square",
                keywords: ["integer", "base", "binary", "octal", "hex", "decimal", "进制"]
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
                keywords: ["case", "upper", "lower", "camel", "snake", "kebab", "大小写"]
            ) {
                IndexCaseConverterPage()
            },

            // MARK: - 加密与生成
            RegisteredTool(
                id: "hash-text",
                title: "Hash 文本",
                categoryID: .crypto,
                systemImage: "number",
                keywords: ["hash", "md5", "sha1", "sha256", "sha512", "sha3", "digest", "摘要"]
            ) {
                IndexHashTextPage()
            },
            RegisteredTool(
                id: "text-encryption",
                title: "文本加密",
                categoryID: .crypto,
                systemImage: "lock",
                keywords: ["encrypt", "decrypt", "aes", "cipher", "加密", "解密"]
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
                id: "token-generator",
                title: "Token 生成器",
                categoryID: .crypto,
                systemImage: "shuffle",
                keywords: ["token", "random", "password", "secret", "随机"]
            ) {
                IndexTokenPage()
            },
            RegisteredTool(
                id: "uuid-generator",
                title: "UUID 生成器",
                categoryID: .crypto,
                systemImage: "barcode",
                keywords: ["uuid", "guid", "unique", "identifier"]
            ) {
                IndexUUIDPage()
            },
            RegisteredTool(
                id: "password-generator",
                title: "密码生成器",
                categoryID: .crypto,
                systemImage: "lock.rectangle",
                keywords: ["password", "random", "generate", "密码", "生成", "强度"]
            ) {
                IndexPasswordGeneratorPage()
            },

            // MARK: - 开发
            RegisteredTool(
                id: "json-formatter",
                title: "JSON 格式化",
                categoryID: .development,
                systemImage: "curlybraces.square",
                keywords: ["json", "prettify", "minify", "format", "beautify", "compress", "美化", "压缩"]
            ) {
                IndexJSONFormatterPage()
            },
            RegisteredTool(
                id: "sql-prettify",
                title: "SQL 格式化",
                categoryID: .development,
                systemImage: "cylinder",
                keywords: ["sql", "prettify", "format", "beautify", "格式化", "美化"]
            ) {
                IndexSQLPrettifyPage()
            },
            RegisteredTool(
                id: "xml-formatter",
                title: "XML 格式化",
                categoryID: .development,
                systemImage: "chevron.left.forwardslash.chevron.right",
                keywords: ["xml", "format", "prettify", "indent"]
            ) {
                IndexXMLFormatPage()
            },
            RegisteredTool(
                id: "yaml-prettify",
                title: "YAML 格式化",
                categoryID: .development,
                systemImage: "list.bullet.indent",
                keywords: ["yaml", "yml", "prettify", "format", "格式化"]
            ) {
                IndexYAMLPrettifyPage()
            },
            RegisteredTool(
                id: "json-diff",
                title: "JSON 对比",
                categoryID: .development,
                systemImage: "curlybraces",
                keywords: ["json", "diff", "compare", "difference", "对比"]
            ) {
                IndexJSONDiffPage()
            },
            RegisteredTool(
                id: "text-diff",
                title: "文本对比",
                categoryID: .development,
                systemImage: "square.split.2x1",
                keywords: ["text", "diff", "compare", "difference", "对比"]
            ) {
                IndexTextDiffPage()
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
                title: "Docker Run → Compose",
                categoryID: .development,
                systemImage: "shippingbox",
                keywords: ["docker", "compose", "convert", "container", "容器"]
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
                id: "image-converter",
                title: "图片格式转换",
                categoryID: .image,
                systemImage: "photo.on.rectangle.angled",
                keywords: ["image", "convert", "format", "png", "jpg", "webp", "图片", "转换"]
            ) {
                IndexImageConverterPage()
            },
            RegisteredTool(
                id: "image-compressor",
                title: "智能压缩图片",
                categoryID: .image,
                systemImage: "arrow.down.right.and.arrow.up.left",
                keywords: ["compress", "image", "optimize", "压缩", "图片"]
            ) {
                IndexImageCompressorPage()
            },
            RegisteredTool(
                id: "image-watermark",
                title: "图片水印",
                categoryID: .image,
                systemImage: "text.below.photo",
                keywords: ["watermark", "image", "photo", "水印", "图片"]
            ) {
                IndexImageWatermarkPage()
            },
            RegisteredTool(
                id: "image-grayscale",
                title: "图片灰阶生成器",
                categoryID: .image,
                systemImage: "circle.lefthalf.filled",
                keywords: ["grayscale", "image", "filter", "灰度", "图片"]
            ) {
                IndexImageGrayscalePage()
            },
            RegisteredTool(
                id: "favicon-generator",
                title: "Favicon 生成器",
                categoryID: .image,
                systemImage: "app.badge",
                keywords: ["favicon", "icon", "generate", "图标", "生成"]
            ) {
                IndexFaviconGeneratorPage()
            },
            RegisteredTool(
                id: "color-picker",
                title: "颜色转换",
                categoryID: .image,
                systemImage: "paintpalette",
                keywords: ["color", "hex", "rgb", "hsl", "picker"]
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
