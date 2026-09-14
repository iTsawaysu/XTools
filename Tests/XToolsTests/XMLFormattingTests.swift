import XToolsCore
import Testing

struct XMLFormattingTests {
    @Test func formatsCompactXMLWithInlineText() throws {
        let output = try XMLFormatting.format(#"<root><item id="1">a</item><empty /></root>"#)

        #expect(
            output ==
            """
            <root>
              <item id="1">a</item>
              <empty></empty>
            </root>
            """
        )
    }

    @Test func preservesCommentsAndCDATA() throws {
        let output = try XMLFormatting.format(#"<root><!-- note --><script><![CDATA[a < b]]></script></root>"#)

        #expect(
            output ==
            """
            <root>
              <!-- note -->
              <script><![CDATA[a < b]]></script>
            </root>
            """
        )
    }

    @Test func preservesMixedContentWhitespace() throws {
        let input = #"<article><p>Hello <strong>world</strong>, this is <em>mixed</em> content.</p><br/><img src="/logo.png" alt="Logo"/></article>"#
        let output = try XMLFormatting.format(input)

        #expect(output.contains("<p>Hello <strong>world</strong>, this is <em>mixed</em> content.</p>"))
        #expect(!output.contains("</strong>\n"))
        #expect(!output.contains("</em>\n"))
    }

    @Test func invalidXMLThrowsFormattingError() throws {
        #expect {
            _ = try XMLFormatting.format("<root><item></root>")
        } throws: { error in
            guard case XMLFormatting.FormattingError.invalidXML = error else { return false }
            return true
        }
    }

    @Test func invalidXMLReportsLocationAndSnippet() throws {
        let error = #expect(throws: (any Error).self) {
            _ = try XMLFormatting.format("<root>\n  <item></root>")
        }

        guard let error,
              case XMLFormatting.FormattingError.invalidXML(let diagnostic) = error else {
            Issue.record("Expected XML formatting diagnostic")
            return
        }

        #expect(diagnostic.line != nil)
        #expect(diagnostic.column != nil)
        #expect(diagnostic.excerpt?.contains("</root>") == true)
        #expect(diagnostic.localizedDescription == diagnostic.message)
        #expect(diagnostic.formatName == "XML")
        #expect(!diagnostic.workspaceMessage.contains("处理方式："))
    }

    @Test func invalidXMLParserErrorsAreChineseOneSentence() throws {
        let error = #expect(throws: (any Error).self) {
            _ = try XMLFormatting.format("<root><item id=1 /></root>")
        }

        guard let error,
              case XMLFormatting.FormattingError.invalidXML(let diagnostic) = error else {
            Issue.record("Expected XML formatting diagnostic")
            return
        }

        #expect(diagnostic.line == 1)
        #expect(diagnostic.column == 27)
        #expect(diagnostic.localizedDescription == "属性值必须使用引号")
        #expect(diagnostic.displayMessage == "属性值必须使用引号")
        #expect(!diagnostic.localizedDescription.contains("NSXMLParserErrorDomain"))
        #expect(!diagnostic.localizedDescription.contains("The operation"))
        #expect(!diagnostic.localizedDescription.contains("error 39"))
    }

    @Test func xmlSemanticDiagnosticsMatchCommonMalformedSamples() throws {
        let samples: [(input: String, expectedFragments: [String])] = [
            ("<root><item>one</items></root>", ["标签", "不匹配"]),
            (#"<user id="1" id="2"><name>Alice</name></user>"#, ["重复", "属性"]),
            ("<root><title>Tom & Jerry</title></root>", ["&", "转义"]),
            ("<one>1</one><two>2</two>", ["根节点"])
        ]

        for sample in samples {
            let error = #expect(throws: (any Error).self) {
                _ = try XMLFormatting.format(sample.input)
            }

            guard let error,
                  case XMLFormatting.FormattingError.invalidXML(let diagnostic) = error else {
                Issue.record("Expected XML formatting diagnostic")
                continue
            }

            for fragment in sample.expectedFragments {
                #expect(diagnostic.message.contains(fragment))
            }
            #expect(!diagnostic.localizedDescription.contains("NSXMLParserErrorDomain"))
            #expect(!diagnostic.localizedDescription.contains("The operation"))
        }
    }
}
