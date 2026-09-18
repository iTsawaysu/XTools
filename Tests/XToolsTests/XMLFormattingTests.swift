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


    @Test func minifiesXML() throws {
        let input = """
        <root>
          <item id="1">a</item>
          <nested>
            <child>b</child>
          </nested>
        </root>
        """
        let minified = try XMLFormatting.minify(input)
        #expect(minified == "<root><item id=\"1\">a</item><nested><child>b</child></nested></root>")
    }

    @Test func formatsWithCustomIndent() throws {
        let input = "<root><item id=\"1\">a</item></root>"
        let formatted = try XMLFormatting.format(input, indentWidth: 4)
        #expect(formatted == "<root>\n    <item id=\"1\">a</item>\n</root>")
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

    @Test func formatsSVGWithDOCTYPEAndXMLDeclaration() throws {
        let input = """
        <?xml version="1.0" encoding="utf-8"?>
        <!DOCTYPE svg PUBLIC "-//W3C//DTD SVG 1.1//EN" "http://www.w3.org/Graphics/SVG/1.1/DTD/svg11.dtd">
        <svg version="1.1" xmlns="http://www.w3.org/2000/svg" width="100" height="100"><circle cx="50" cy="50" r="40" fill="red"/></svg>
        """

        let output = try XMLFormatting.format(input)
        #expect(output.contains("<?xml version=\"1.0\" encoding=\"utf-8\"?>"))
        #expect(output.contains("<!DOCTYPE svg PUBLIC \"-//W3C//DTD SVG 1.1//EN\" \"http://www.w3.org/Graphics/SVG/1.1/DTD/svg11.dtd\">"))
        #expect(output.contains("<svg"))
        #expect(output.contains("version=\"1.1\""))
        #expect(output.contains("  <circle cx=\"50\""))
    }

    @Test func formatsSVGWithDOCTYPEWithoutXMLDeclaration() throws {
        let input = """
        <!DOCTYPE svg PUBLIC "-//W3C//DTD SVG 1.1//EN" "http://www.w3.org/Graphics/SVG/1.1/DTD/svg11.dtd">
        <svg width="100" height="100"><rect width="100" height="100" fill="blue"/></svg>
        """

        let output = try XMLFormatting.format(input)
        #expect(output.hasPrefix("<!DOCTYPE svg PUBLIC"))
        #expect(output.contains("<svg width=\"100\""))
        #expect(output.contains("  <rect width=\"100\""))
    }

    @Test func formatsXMLWithInternalSubsetDOCTYPE() throws {
        let input = """
        <!DOCTYPE note [
        <!ELEMENT note (to,from,body)>
        <!ELEMENT to (#PCDATA)>
        <!ELEMENT from (#PCDATA)>
        <!ELEMENT body (#PCDATA)>
        ]>
        <note><to>User</to><from>Admin</from><body>Hello</body></note>
        """

        let output = try XMLFormatting.format(input)
        #expect(output.contains("<!DOCTYPE note ["))
        #expect(output.contains("<note>"))
        #expect(output.contains("  <to>User</to>"))
    }

    @Test func minifiesSVGWithDOCTYPE() throws {
        let input = """
        <!DOCTYPE svg PUBLIC "-//W3C//DTD SVG 1.1//EN" "http://www.w3.org/Graphics/SVG/1.1/DTD/svg11.dtd">
        <svg width="100" height="100">
          <circle cx="50" cy="50" r="40"/>
        </svg>
        """

        let minified = try XMLFormatting.minify(input)
        #expect(minified.contains("<!DOCTYPE svg PUBLIC"))
        #expect(minified.contains("<svg width=\"100\" height=\"100\"><circle cx=\"50\" cy=\"50\" r=\"40\"></circle></svg>"))
    }

    @Test func formatsAdobeIllustratorSVGWithEntityDeclarationsAndComments() throws {
        let input = """
        <?xml version="1.0" encoding="utf-8"?>
        <!-- Generator: Adobe Illustrator 25.0.0, SVG Export Plug-In . SVG Version: 6.00 Build 0)  -->
        <!DOCTYPE svg PUBLIC "-//W3C//DTD SVG 1.1//EN" "http://www.w3.org/Graphics/SVG/1.1/DTD/svg11.dtd" [
        	<!ENTITY ns_extend "http://ns.adobe.com/Extensibility/1.0/">
        	<!ENTITY ns_ai "http://ns.adobe.com/AdobeIllustrator/10.0/">
        ]>
        <svg version="1.1" id="Layer_1" xmlns="&ns_extend;" xmlns:xlink="&ns_ai;" x="0px" y="0px" viewBox="0 0 100 100">
          <circle cx="50" cy="50" r="40"/>
        </svg>
        """

        let output = try XMLFormatting.format(input)
        #expect(output.contains("<?xml version=\"1.0\" encoding=\"utf-8\"?>"))
        #expect(output.contains("<!DOCTYPE svg PUBLIC"))
        #expect(output.contains("<!ENTITY ns_extend"))
        #expect(output.contains("<!-- Generator: Adobe Illustrator"))
        #expect(output.contains("<svg"))
        #expect(output.contains("version=\"1.1\""))
        #expect(output.contains("  <circle cx=\"50\""))
    }

    @Test func formatsSVGWithEntityReferences() throws {
        let input = """
        <!DOCTYPE svg PUBLIC "-//W3C//DTD SVG 1.1//EN" "http://www.w3.org/Graphics/SVG/1.1/DTD/svg11.dtd">
        <svg width="100" height="100">
          <text x="10" y="20">&copy; 2026 XTools &amp; Co.</text>
        </svg>
        """

        let output = try XMLFormatting.format(input)
        #expect(output.contains("<!DOCTYPE svg PUBLIC"))
        #expect(output.contains("&copy; 2026 XTools"))
    }

    @Test func doctypeExtractionIgnoresCommentsContainingDoctype() throws {
        let input = """
        <!-- Example with <!DOCTYPE fake> inside comment -->
        <!DOCTYPE svg PUBLIC "-//W3C//DTD SVG 1.1//EN" "http://www.w3.org/Graphics/SVG/1.1/DTD/svg11.dtd">
        <svg width="50" height="50"><circle cx="25" cy="25" r="20"/></svg>
        """

        let output = try XMLFormatting.format(input)
        #expect(output.contains("<!DOCTYPE svg PUBLIC"))
        #expect(!output.contains("\n<!DOCTYPE fake>"))
    }

    @Test func doctypeExtractionReturnsNilWhenDoctypeOnlyInComment() throws {
        let input = """
        <!-- Note: <!DOCTYPE html> was removed -->
        <root><item>value</item></root>
        """

        let output = try XMLFormatting.format(input)
        #expect(!output.hasPrefix("<!DOCTYPE"))
        #expect(!output.contains("\n<!DOCTYPE"))
        #expect(output.contains("<root>"))
        #expect(output.contains("  <item>value</item>"))
    }

    @Test func preservesTopLevelComments() throws {
        let input = """
        <!-- Header comment -->
        <root>
          <item>value</item>
        </root>
        <!-- Footer comment -->
        """

        let output = try XMLFormatting.format(input)
        #expect(output.contains("<!-- Header comment -->"))
        #expect(output.contains("<root>"))
        #expect(output.contains("<!-- Footer comment -->"))
    }
}


