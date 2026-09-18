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
}
