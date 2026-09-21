import XToolsCore
import Testing

struct YAMLPrettifierTests {
    @Test func normalizesWhitespace() {
        let output = YAMLPrettifier.format("key:   value\n\tchild:   yes\n\n\nnext: item")

        #expect(
            output ==
            """
            key: value
              child: yes

            next: item
            """
        )
    }

    @Test func preservesQuotedColonSpacing() {
        let output = YAMLPrettifier.format(#"command:   "echo foo:  bar""#)

        #expect(output == #"command: "echo foo:  bar""#)
    }

    @Test func preservesExistingSpaceIndentation() {
        let output = YAMLPrettifier.format(
            """
            root:
               child:   value
              sibling: ok
            """
        )

        #expect(
            output ==
            """
            root:
               child: value
              sibling: ok
            """
        )
    }

    @Test func formatsSequenceMappings() {
        let output = YAMLPrettifier.format(
            """
            services:
              - name:   web
                image:   nginx
            """
        )

        #expect(
            output ==
            """
            services:
              - name: web
                image: nginx
            """
        )
    }

    @Test func preservesLiteralBlockScalarContent() {
        let output = YAMLPrettifier.format(
            """
            script:   |
              echo foo:  bar
              curl http://example.com/a:b
            next:   value
            """
        )

        #expect(
            output ==
            """
            script: |
              echo foo:  bar
              curl http://example.com/a:b
            next: value
            """
        )
    }

    @Test func preservesFoldedBlockScalarContent() {
        let output = YAMLPrettifier.format(
            """
            notes:   >-
              first:  line
              second:  line
            enabled:   true
            """
        )

        #expect(
            output ==
            """
            notes: >-
              first:  line
              second:  line
            enabled: true
            """
        )
    }

    @Test func preservesRootAndSequenceBlockScalarContentWhenCommentsUseLineFormatter() throws {
        let rootInput = """
        # keep formatter on the comment-preserving path
        >-
          title:   keep-three-spaces
          # scalar content
        """
        let rootOutput = try YAMLPrettifier.formatValidated(
            rootInput,
            options: .init(indent: 2, sortKeys: false)
        )
        #expect(rootOutput.contains("  title:   keep-three-spaces"))
        #expect(rootOutput.contains("  # scalar content"))

        let sequenceInput = [
            "# keep this comment",
            "items:",
            "  - |2",
            "    title:   keep-three-spaces  ",
            "    literal: # value",
            "next:   value"
        ].joined(separator: "\n")
        let sequenceOutput = try YAMLPrettifier.formatValidated(
            sequenceInput,
            options: .init(indent: 2, sortKeys: false)
        )
        #expect(sequenceOutput.contains("    title:   keep-three-spaces  "))
        #expect(sequenceOutput.contains("    literal: # value"))
        #expect(sequenceOutput.hasSuffix("next: value"))
    }

    @Test func preservesMappingSequenceMappingAndExplicitValueBlockScalars() throws {
        let input = [
            "# structural comment",
            "mapping: >+2 # header comment",
            "  first:   value",
            "",
            "  second:  value  ",
            "items:",
            "  - payload: |2",
            "      sequence:   mapping",
            "    next:   value",
            "? explicit",
            ": |-",
            "  explicit:   value",
            "tail:   done"
        ].joined(separator: "\n")

        let output = try YAMLPrettifier.formatValidated(
            input,
            options: .init(indent: 2, sortKeys: false)
        )

        #expect(output.contains("  first:   value\n\n  second:  value  "))
        #expect(output.contains("      sequence:   mapping\n    next: value"))
        #expect(output.contains("  explicit:   value\ntail: done"))
    }

    @Test func validatesValidYAML() throws {
        let output = try YAMLPrettifier.formatValidated(
            """
            services:
              web:
                image: nginx
                ports:
                  - "8080:80"
            """
        )

        #expect(
            output ==
            """
            services:
              web:
                image: nginx
                ports:
                  - "8080:80"
            """
        )
    }

    @Test func formatsWithCustomIndentWidth() throws {
        let input = """
        services:
          web:
            image: nginx
        """
        let output = try YAMLPrettifier.formatValidated(input, options: .init(indent: 4, sortKeys: false))
        #expect(output.contains("    web:\n        image: nginx"))
    }

    @Test func formatsWithTwoSpaceIndentWidth() throws {
        let input = """
        services:
            web:
                image: nginx
        """
        let output = try YAMLPrettifier.formatValidated(input, options: .init(indent: 2, sortKeys: false))
        #expect(output.contains("  web:\n    image: nginx"))
    }

    @Test func formatsWithSortedKeys() throws {
        let input = """
        zebra: 1
        apple: 2
        banana: 3
        """
        let output = try YAMLPrettifier.formatValidated(input, options: .init(indent: 2, sortKeys: true))
        let lines = output.components(separatedBy: "\n")
        #expect(lines.first?.hasPrefix("apple") == true)
        #expect(lines.last?.hasPrefix("zebra") == true)
    }

    @Test func refusesSortingWhenYAMLContainsStructuralComments() throws {
        let samples = [
            "# top comment\nzebra: 1\napple: 2",
            "zebra: 1 # inline comment\napple: 2",
            "zebra: 1\n# standalone comment\napple: 2"
        ]

        for input in samples {
            let error = #expect(throws: (any Error).self) {
                _ = try YAMLPrettifier.formatValidated(input, options: .init(indent: 2, sortKeys: true))
            }

            guard let error,
                  case YAMLPrettifier.ValidationError.unsupportedCommentPreservingSort(let diagnostic) = error else {
                Issue.record("Expected comment-preserving sort capability diagnostic")
                continue
            }
            #expect(diagnostic.message == "当前无法在保留注释的同时对键排序")

            let outcome = FormatRunner.run(input) {
                try YAMLPrettifier.formatValidated($0, options: .init(indent: 2, sortKeys: true))
            }
            let binding = outcome.binding(text: { $0 })
            #expect(binding.output == "")
            #expect(binding.error == diagnostic.workspaceMessage)
            #expect(binding.warning == nil)
        }
    }

    @Test func sortingDoesNotMistakeHashesInsideScalarsForComments() throws {
        let input = """
        zebra: "value # literal"
        url: https://example.test/#fragment
        body: |-
          # block scalar content
          key: value # still scalar content
        apple: 2
        """

        let output = try YAMLPrettifier.formatValidated(
            input,
            options: .init(indent: 2, sortKeys: true)
        )

        #expect(output.contains("value # literal"))
        #expect(output.contains("https://example.test/#fragment"))
        #expect(output.contains("# block scalar content"))
    }

    @Test func sortingTracksQuotedScalarsAcrossPhysicalLines() throws {
        let input = """
        zebra: "double quoted
          # literal hash
          tail"
        single: 'single quoted
          # another literal hash
          it''s still quoted'
        apple: 2
        """

        let output = try YAMLPrettifier.formatValidated(
            input,
            options: .init(indent: 2, sortKeys: true)
        )

        #expect(output.contains("# literal hash"))
        #expect(output.contains("# another literal hash"))
        #expect(output.components(separatedBy: "\n").first?.hasPrefix("apple:") == true)
    }

    @Test func sortingStillRejectsCommentAfterMultilineQuotedScalarCloses() throws {
        let input = """
        zebra: "double quoted
          tail" # structural comment
        apple: 2
        """

        #expect(throws: YAMLPrettifier.ValidationError.self) {
            _ = try YAMLPrettifier.formatValidated(
                input,
                options: .init(indent: 2, sortKeys: true)
            )
        }
    }

    @Test func plainScalarQuotesDoNotHideLaterStructuralComments() throws {
        let input = """
        zebra: it's plain text
        message: say "hello"
        apple: 2 # structural comment
        """

        #expect(throws: YAMLPrettifier.ValidationError.self) {
            _ = try YAMLPrettifier.formatValidated(
                input,
                options: .init(indent: 2, sortKeys: true)
            )
        }
    }

    @Test func blockScalarHeaderCommentCountsAsStructuralCommentForSorting() throws {
        let input = """
        body: |- # keep this header note
          # scalar content is not the refusal trigger
        apple: 2
        """

        #expect(throws: YAMLPrettifier.ValidationError.self) {
            _ = try YAMLPrettifier.formatValidated(input, options: .init(indent: 2, sortKeys: true))
        }
    }

    @Test func rejectsInvalidYAML() throws {
        #expect(throws: YAMLPrettifier.ValidationError.self) {
            _ = try YAMLPrettifier.formatValidated("services:\n  web: [nginx")
        }
    }

    @Test func invalidYAMLErrorDescriptionIncludesDiagnosticDetails() throws {
        let error = #expect(throws: (any Error).self) {
            _ = try YAMLPrettifier.formatValidated("services:\n  web: [nginx")
        }

        guard let error,
              case YAMLPrettifier.ValidationError.invalidSyntax(let diagnostic) = error else {
            Issue.record("Expected YAML validation diagnostic")
            return
        }

        #expect(diagnostic.line != nil)
        #expect(diagnostic.column != nil)
        #expect(diagnostic.message == "流程列表缺少逗号或右方括号")
        #expect(diagnostic.excerpt?.contains("[nginx") == true)
        #expect(diagnostic.localizedDescription == diagnostic.message)
        #expect(diagnostic.formatName == "YAML")
        expectChineseOneSentence(diagnostic)
    }

    @Test func invalidYAMLErrorsNeverExposeEnglishParserText() throws {
        let samples: [(input: String, message: String)] = [
            ("services:\n  web: [nginx", "流程列表缺少逗号或右方括号"),
            ("root:\n\tchild: value", "缩进必须使用空格，不能使用制表符"),
            (#"name: "abc"#, "引号字符串没有闭合"),
            ("ref: *missing", "引用了未定义的锚点别名"),
            ("first: 1\n---\nsecond: 2", "只允许包含一个 YAML 文档")
        ]

        for sample in samples {
            let error = #expect(throws: (any Error).self) {
                _ = try YAMLPrettifier.formatValidated(sample.input)
            }

            guard let error,
                  case YAMLPrettifier.ValidationError.invalidSyntax(let diagnostic) = error else {
                Issue.record("Expected YAML validation diagnostic")
                continue
            }

            #expect(diagnostic.message == sample.message)
            expectChineseOneSentence(diagnostic)
        }
    }

    @Test func yamlSemanticDiagnosticsCoverIndentationColonAndDuplicateKeys() throws {
        let samples: [(input: String, expectedFragments: [String])] = [
            ("user:\n  id: 1\n name: Alice", ["缩进"]),
            ("user\n  id: 1", ["冒号"]),
            ("service:\n  image: nginx:1.25\n  image: nginx:1.26", ["重复", "键"])
        ]

        for sample in samples {
            let error = #expect(throws: (any Error).self) {
                _ = try YAMLPrettifier.formatValidated(sample.input)
            }

            guard let error,
                  case YAMLPrettifier.ValidationError.invalidSyntax(let diagnostic) = error else {
                Issue.record("Expected YAML validation diagnostic")
                continue
            }

            for fragment in sample.expectedFragments {
                #expect(diagnostic.message.contains(fragment))
            }
            expectChineseOneSentence(diagnostic)
        }
    }

    @Test func preservesCommentsWhenFormattingWithoutSorting() throws {
        let input = """
        # Server configuration
        server:
          # Port to listen on
          port: 8080
        """
        let output = try YAMLPrettifier.formatValidated(input, options: .init(indent: 2, sortKeys: false))
        #expect(output.contains("# Server configuration"))
        #expect(output.contains("# Port to listen on"))
    }

    private func expectChineseOneSentence(_ diagnostic: FormatDiagnostic) {
        let message = diagnostic.localizedDescription

        #expect(!message.contains("\n"))
        #expect(!message.contains("did not"))
        #expect(!message.contains("could not"))
        #expect(!message.contains("expected"))
        #expect(!message.contains("unexpected"))
        #expect(!message.contains("while parsing"))
        #expect(!message.contains("scanner"))
        #expect(!message.contains("parser"))
        #expect(!message.contains("YamlError"))
    }

    // MARK: - Comment-preserving path

    /// 带注释的输入走逐行路径（序列化器不保留注释），但 indent 选项仍必须兑现，
    /// 否则用户把缩进从 4 改成 2 会看不到任何变化。
    @Test func commentBearingInputStillHonorsTheIndentOption() throws {
        let fourToTwo = try YAMLPrettifier.format(
            "a:\n    b: 1\nc: 2 # x",
            options: .init(indent: 2, sortKeys: false)
        )
        #expect(fourToTwo == "a:\n  b: 1\nc: 2 # x", Comment(rawValue: fourToTwo))

        let twoToFour = try YAMLPrettifier.format(
            "a:\n  b: 1\nc: 2 # x",
            options: .init(indent: 4, sortKeys: false)
        )
        #expect(twoToFour == "a:\n    b: 1\nc: 2 # x", Comment(rawValue: twoToFour))

        // 多层嵌套按层级折算，注释原样保留。
        let nested = try YAMLPrettifier.format(
            "a: 1 # c\nb:\n    c:\n        d: 2",
            options: .init(indent: 2, sortKeys: false)
        )
        #expect(nested == "a: 1 # c\nb:\n  c:\n    d: 2", Comment(rawValue: nested))

        // 缩进不一致时宁可不改，避免把不同层级压平。
        let inconsistent = try YAMLPrettifier.format(
            "a:\n   b: 1\n     c: 2 # x",
            options: .init(indent: 2, sortKeys: false)
        )
        #expect(inconsistent == "a:\n   b: 1\n     c: 2 # x", Comment(rawValue: inconsistent))
    }

    /// 制表符只有在行首缩进里才展开；标量内容里的字面 tab 必须保留语义。
    /// 此前逐行路径是整行替换，`key: "a<TAB>b"` 会被悄悄改成两个空格（数据损坏）。
    @Test func tabsInsideScalarValuesAreNotRewritten() throws {
        // 逐行路径（带注释）：字面 tab 原样保留。
        let quoted = try YAMLPrettifier.format(
            "key: \"a\tb\" # c",
            options: .init(indent: 2, sortKeys: false)
        )
        #expect(quoted.contains("a\tb"), Comment(rawValue: quoted.debugDescription))

        // 序列化路径（无注释）：tab 写成 YAML 的 \t 转义，语义等价而非被抹成空格。
        let withoutComment = try YAMLPrettifier.format(
            "key: \"a\tb\"",
            options: .init(indent: 2, sortKeys: false)
        )
        #expect(withoutComment == #"key: "a\tb""#, Comment(rawValue: withoutComment.debugDescription))
        #expect(!withoutComment.contains("a  b"), Comment(rawValue: withoutComment.debugDescription))

        // 行首缩进里的 tab 仍然要展开。
        let indented = YAMLPrettifier.format("key: 1\n\tnested: 2 # c")
        #expect(!indented.contains("\t"), Comment(rawValue: indented.debugDescription))
    }

    /// `#` 只在行首或前面是空白、且不在引号标量内时才开启注释。
    /// `url: http://x#y` 这类值不该把格式化整体降级到逐行路径。
    @Test func hashesInsideScalarValuesDoNotDegradeFormatting() throws {
        let url = try YAMLPrettifier.format(
            "url: http://x#y\nnested:\n    child: 1",
            options: .init(indent: 2, sortKeys: false)
        )
        // 若被误判成注释就会走逐行路径、保留 4 空格。
        #expect(url == "url: http://x#y\nnested:\n  child: 1", Comment(rawValue: url))

        let quotedHash = try YAMLPrettifier.format(
            "key: \"a#b\"\nnested:\n    child: 1",
            options: .init(indent: 2, sortKeys: false)
        )
        #expect(quotedHash.contains("nested:\n  child: 1"), Comment(rawValue: quotedHash))
        #expect(quotedHash.contains("\"a#b\""), Comment(rawValue: quotedHash))
    }

    /// 序列化器在 compose→dump 之间会解析锚点、把别名展开成字面值
    /// （`a: &x 1` + `b: *x` 曾变成 `a: 1` + `b: 1`）。带锚点/别名的输入
    /// 必须改走逐行路径原样保留。
    @Test func anchorsAndAliasesSurviveFormatting() throws {
        let anchors = try YAMLPrettifier.format(
            "a: &x 1\nb: *x",
            options: .init(indent: 2, sortKeys: false)
        )
        #expect(anchors == "a: &x 1\nb: *x", Comment(rawValue: anchors))

        // 锚点路径同样要兑现 indent 选项。
        let indented = try YAMLPrettifier.format(
            "root:\n    a: &x 1\n    b: *x",
            options: .init(indent: 2, sortKeys: false)
        )
        #expect(indented == "root:\n  a: &x 1\n  b: *x", Comment(rawValue: indented))

        // 合并键 `<<: *base` 是别名最常见的真实用法。
        let merged = try YAMLPrettifier.format(
            "base: &b\n  x: 1\nmerged:\n  <<: *b",
            options: .init(indent: 2, sortKeys: false)
        )
        #expect(merged.contains("<<: *b"), Comment(rawValue: merged))
        #expect(merged.contains("&b"), Comment(rawValue: merged))
    }

    /// 排序会移动键所在的行，可能把别名挪到锚点定义之前而产出非法 YAML，
    /// 所以与注释一样显式拒绝，而不是静默展开别名。
    @Test func sortingWithAnchorsIsRejectedInsteadOfSilentlyExpanding() throws {
        let error = #expect(throws: (any Error).self) {
            _ = try YAMLPrettifier.format("a: &x 1\nb: *x", options: .init(indent: 2, sortKeys: true))
        }

        guard let error,
              case YAMLPrettifier.ValidationError.unsupportedAnchorPreservingSort(let diagnostic) = error else {
            Issue.record("Expected anchor-preserving sort capability diagnostic")
            return
        }
        #expect(diagnostic.message == "当前无法在保留锚点与别名的同时对键排序")
    }

    /// 引号内的 `*x`、标量中段的 `&`、无名称的裸 `*` 都不是锚点/别名；
    /// 误判会让这些输入在开启排序时被错误拒绝。
    @Test func anchorDetectionDoesNotFireOnLookalikes() throws {
        #expect(throws: Never.self) {
            _ = try YAMLPrettifier.format(#"key: "*x""#, options: .init(indent: 2, sortKeys: true))
        }
        #expect(throws: Never.self) {
            _ = try YAMLPrettifier.format("key: a*b", options: .init(indent: 2, sortKeys: true))
        }
        #expect(throws: Never.self) {
            _ = try YAMLPrettifier.format("cmd: echo *", options: .init(indent: 2, sortKeys: true))
        }
        #expect(throws: Never.self) {
            _ = try YAMLPrettifier.format("key: a&b", options: .init(indent: 2, sortKeys: true))
        }
    }
}
