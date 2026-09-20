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
              <empty/>
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

    @Test func preservesWhitespaceTextNodesInsideXMLSpacePreserve() throws {
        let input = #"<pre xml:space="preserve"><a/> <b/></pre>"#

        #expect(try XMLFormatting.format(input) == "<pre xml:space=\"preserve\"><a/> <b/></pre>")
        #expect(try XMLFormatting.minify(input) == "<pre xml:space=\"preserve\"><a/> <b/></pre>")
    }

    @Test func XMLSpacePreserveIsInheritedAndDefaultRestoresNormalFormatting() throws {
        let input = #"<outer xml:space="preserve"> <inherited><a/> <b/></inherited><normal xml:space="default"><a/>   <b/><again xml:space="preserve"><x/> <y/></again></normal> </outer>"#

        let formatted = try XMLFormatting.format(input)
        #expect(formatted.hasPrefix("<outer xml:space=\"preserve\"> <inherited><a/> <b/></inherited>"))
        #expect(formatted.contains("<normal xml:space=\"default\">\n"))
        #expect(formatted.contains("<again xml:space=\"preserve\"><x/> <y/></again>"))
        #expect(formatted.hasSuffix("</normal> </outer>"))

        let minified = try XMLFormatting.minify(input)
        #expect(minified.contains("<inherited><a/> <b/></inherited>"))
        #expect(minified.contains("<normal xml:space=\"default\"><a/><b/><again xml:space=\"preserve\"><x/> <y/></again></normal>"))
        #expect(minified.hasSuffix("</normal> </outer>"))
    }

    @Test func XMLSpaceDefaultInsidePreservedRootKeepsRootWhitespaceAndFormatsNestedChildren() throws {
        let input = """
        <root xml:space="preserve">
          before
          <section xml:space="default"><a/><b/></section>
          after
        </root>
        """

        #expect(
            try XMLFormatting.format(input) ==
            """
            <root xml:space="preserve">
              before
              <section xml:space="default">
                <a/>
                <b/>
              </section>
              after
            </root>
            """
        )

        #expect(
            try XMLFormatting.format(input, indentWidth: 4) ==
            """
            <root xml:space="preserve">
              before
              <section xml:space="default">
                  <a/>
                  <b/>
              </section>
              after
            </root>
            """
        )
    }

    @Test func XMLSpaceDefaultFirstChildUsesPreservedLinePrefixAsItsLayoutBaseline() throws {
        let input = """
        <root xml:space="preserve">
          <section xml:space="default"><a/><b/></section>
        </root>
        """

        #expect(
            try XMLFormatting.format(input) ==
            """
            <root xml:space="preserve">
              <section xml:space="default">
                <a/>
                <b/>
              </section>
            </root>
            """
        )

        #expect(
            try XMLFormatting.format(input, indentWidth: 4) ==
            """
            <root xml:space="preserve">
              <section xml:space="default">
                  <a/>
                  <b/>
              </section>
            </root>
            """
        )
        #expect(
            try XMLFormatting.minify(input) ==
            "<root xml:space=\"preserve\">\n  <section xml:space=\"default\"><a/><b/></section>\n</root>"
        )
    }

    @Test func XMLSpaceDefaultKeepsRawTabPrefixAndAppendsSelectedSpaces() throws {
        let input = "<root xml:space=\"preserve\">\n\t<section xml:space=\"default\"><a/><b/></section>\n</root>"

        #expect(
            try XMLFormatting.format(input) ==
            "<root xml:space=\"preserve\">\n\t<section xml:space=\"default\">\n\t  <a/>\n\t  <b/>\n\t</section>\n</root>"
        )
        #expect(
            try XMLFormatting.format(input, indentWidth: 4) ==
            "<root xml:space=\"preserve\">\n\t<section xml:space=\"default\">\n\t    <a/>\n\t    <b/>\n\t</section>\n</root>"
        )
    }

    @Test func XMLSpaceDefaultOnSameLineDoesNotInventAnOuterPrefix() throws {
        let input = #"<root xml:space="preserve"><section xml:space="default"><a/><b/></section></root>"#

        #expect(
            try XMLFormatting.format(input) ==
            "<root xml:space=\"preserve\"><section xml:space=\"default\">\n  <a/>\n  <b/>\n</section></root>"
        )
    }

    @Test func XMLSpaceOnlyRecognizesExactSpecificationTokens() throws {
        let uppercase = #"<root xml:space="PRESERVE"><a/><b/></root>"#
        let padded = #"<root xml:space=" preserve "><a/><b/></root>"#
        let invalidOverride = #"<outer xml:space="preserve"><inner xml:space="DEFAULT"><a/> <b/></inner></outer>"#

        #expect(
            try XMLFormatting.format(uppercase) ==
            "<root xml:space=\"PRESERVE\">\n  <a/>\n  <b/>\n</root>"
        )
        #expect(
            try XMLFormatting.format(padded) ==
            "<root xml:space=\" preserve \">\n  <a/>\n  <b/>\n</root>"
        )
        #expect(try XMLFormatting.format(invalidOverride) == invalidOverride)
    }

    @Test func preservesEmptyElementSpellingAndAttributeQuoteStyle() throws {
        let input = #"<root><single value='x'/><expanded></expanded></root>"#

        #expect(
            try XMLFormatting.format(input) ==
            "<root>\n  <single value='x'/>\n  <expanded></expanded>\n</root>"
        )
        #expect(
            try XMLFormatting.minify(input) ==
            "<root><single value='x'/><expanded></expanded></root>"
        )
    }

    @Test func normalizesNonUTFDeclarationForUnicodeStringInput() throws {
        let samples = [
            (#"<?xml version="1.0" encoding="ISO-8859-1"?><root>é</root>"#, "é", #"<?xml version="1.0" encoding="UTF-8"?>"#),
            (#"<?xml version='1.0' encoding='Shift_JIS' standalone='yes'?><root>日本語</root>"#, "日本語", #"<?xml version='1.0' encoding='UTF-8' standalone='yes'?>"#)
        ]

        for (input, text, declaration) in samples {
            let output = try XMLFormatting.format(input)
            #expect(output.hasPrefix(declaration))
            #expect(output.contains(text))
            #expect(!output.contains("Ã"))
        }
    }

    @Test func keepsUTF8DeclarationAndDoesNotInventOne() throws {
        let declared = #"<?xml version="1.0" encoding="utf-8" standalone="no"?><root>é</root>"#
        let declaredOutput = try XMLFormatting.format(declared)
        #expect(declaredOutput.hasPrefix(#"<?xml version="1.0" encoding="utf-8" standalone="no"?>"#))
        #expect(declaredOutput.contains("é"))

        let undeclaredOutput = try XMLFormatting.format("<root>日本語</root>")
        #expect(!undeclaredOutput.hasPrefix("<?xml"))
        #expect(undeclaredOutput == "<root>日本語</root>")
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
        #expect(minified.contains("<svg width=\"100\" height=\"100\"><circle cx=\"50\" cy=\"50\" r=\"40\"/></svg>"))
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

    @Test func preservesTopLevelCommentPIAndDOCTYPESourceOrderInBothModes() throws {
        let input = """
        <!-- before -->
        <?before value?>
        <!DOCTYPE root>
        <?after value?>
        <root/>
        <!-- tail -->
        <?tail value?>
        """
        let expected = """
        <!-- before -->
        <?before value?>
        <!DOCTYPE root>
        <?after value?>
        <root/>
        <!-- tail -->
        <?tail value?>
        """

        #expect(try XMLFormatting.format(input) == expected)
        #expect(try XMLFormatting.minify(input) == expected)
    }

    // MARK: - Nesting depth guard

    /// 缩进渲染是递归的且每层都会序列化整棵子树，过深的文档会让进程栈溢出崩溃
    /// （实测约 160 层即 signal 10）。这道守卫必须在进入渲染前拦住它。
    @Test func deeplyNestedDocumentsAreRejectedInsteadOfCrashing() throws {
        func nested(_ depth: Int) -> String {
            String(repeating: "<a>", count: depth) + String(repeating: "</a>", count: depth)
        }

        // 恰好等于上限仍然可以格式化。
        let atLimit = try XMLFormatting.format(nested(XMLFormatting.maximumNestingDepth))
        #expect(atLimit.contains("<a>"), Comment(rawValue: atLimit))

        // 超过上限给出可定位的诊断，而不是崩溃。
        for depth in [XMLFormatting.maximumNestingDepth + 1, 200, 2000] {
            let error = #expect(throws: (any Error).self) {
                _ = try XMLFormatting.format(nested(depth))
            }
            guard let error,
                  case XMLFormatting.FormattingError.invalidXML(let diagnostic) = error else {
                Issue.record("Expected nesting diagnostic for depth \(depth)")
                continue
            }
            #expect(diagnostic.message.contains("嵌套"), Comment(rawValue: diagnostic.message))
            #expect(diagnostic.message.contains("\(XMLFormatting.maximumNestingDepth)"), Comment(rawValue: diagnostic.message))
            ToolDiagnosticContract.expectFactual(diagnostic.message)
        }

        // minify 走同一条渲染路径，也必须被拦住。
        let minifyError = #expect(throws: (any Error).self) {
            _ = try XMLFormatting.minify(nested(2000))
        }
        #expect(minifyError != nil)
    }

    /// 深度统计用显式栈，且要跨过注释/CDATA 里的尖括号，不能把文本当成嵌套。
    @Test func depthGuardCountsOnlyElementNesting() throws {
        let withCommentNoise = """
        <root><!-- <a><a><a><a> --><b>text</b></root>
        """
        let output = try XMLFormatting.format(withCommentNoise)
        #expect(output.contains("<b>text</b>"), Comment(rawValue: output))

        let withCData = "<root><![CDATA[<a><a><a>]]></root>"
        let cdataOutput = try XMLFormatting.format(withCData)
        #expect(cdataOutput.contains("CDATA"), Comment(rawValue: cdataOutput))
    }
}
