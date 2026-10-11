import Foundation
import Testing
import XToolsCore

/// 开标签渲染的黄金快照：锁定 Foundation 属性序列化细节（单引号保留、
/// `>` 转义、属性空白字符引用）经 format 管线后的字节级输出。
struct XMLOpeningTagGoldenTests {
    @Test func attributeEscapingSurvivesFormatting() throws {
        let cases: [(input: String, expected: String)] = [
            (
                #"<root attr="a &amp; b">text</root>"#,
                #"<root attr="a &amp; b">text</root>"#
            ),
            (
                #"<root attr='single'>x</root>"#,
                #"<root attr='single'>x</root>"#
            ),
            (
                #"<root a="&lt;tag&gt;" b="&quot;q&quot;">x</root>"#,
                #"<root a="&lt;tag&gt;" b="&quot;q&quot;">x</root>"#
            ),
            (
                #"<root attr="line&#10;break">x</root>"#,
                #"<root attr="line&#10;break">x</root>"#
            ),
            (
                #"<ns:root xmlns:ns="http://example.com" ns:id="7"><ns:child>v</ns:child></ns:root>"#,
                """
                <ns:root xmlns:ns="http://example.com" ns:id="7">
                  <ns:child>v</ns:child>
                </ns:root>
                """
            ),
            (
                #"<root xml:space="preserve"><a/> <b/></root>"#,
                #"<root xml:space="preserve"><a/> <b/></root>"#
            ),
            (
                #"<root empty=""><child name="a&#9;b">v</child></root>"#,
                "<root empty=\"\">\n  <child name=\"a&#9;b\">v</child>\n</root>"
            ),
            (
                #"<root apostrophe="it's" angle="a>b">v</root>"#,
                #"<root apostrophe="it's" angle="a&gt;b">v</root>"#
            ),
            (
                #"<ns:root ns:id="7" xmlns:ns="http://example.com"><ns:child>v</ns:child></ns:root>"#,
                """
                <ns:root xmlns:ns="http://example.com" ns:id="7">
                  <ns:child>v</ns:child>
                </ns:root>
                """
            )
        ]

        for (input, expected) in cases {
            #expect(try XMLFormatting.format(input) == expected, "format 输出漂移：\(input)")
        }
    }
}

private final class XMLAttributeValueCollector: NSObject, XMLParserDelegate {
    var attributes: [[String: String]] = []

    func parser(_ parser: XMLParser, didStartElement elementName: String,
                namespaceURI: String?, qualifiedName qName: String?,
                attributes attributeDict: [String: String]) {
        attributes.append(attributeDict)
    }
}

extension XMLOpeningTagGoldenTests {
    @Test func attributeWhitespaceValuesSurviveIndependentParserRoundTrip() throws {
        let inputs = [
            #"<root a="x&#9;y&#13;z&#10;w"><child a="q&#10;r"/></root>"#,
            #"<ns:root xmlns:ns="urn:test" a="x&#xA;y&#x9;z&#xD;w"><ns:child>v</ns:child></ns:root>"#,
            #"<root xml:space="preserve" a="x&#10;y">text<a b="q&#9;r"/> tail</root>"#,
            "<root a='x&#10;y'>text<child b='q&#9;r'/>tail<![CDATA[<fake a='\n'/>]]><!-- <fake a='\t'/> --><?pi x='\r'?></root>",
            #"<!DOCTYPE root [<!ENTITY newline "&#10;">]><root a="x&newline;y"><child/></root>"#,
            "<root a='line\nbreak' b='a\tb' c='a\rb'><child/></root>"
        ]
        for input in inputs {
            let expected = try parsedAttributes(input)
            for minify in [false, true] {
                let output = try XMLFormatting.format(input, minify: minify)
                #expect(try parsedAttributes(output) == expected)
            }
        }
    }

    private func parsedAttributes(_ source: String) throws -> [[String: String]] {
        let collector = XMLAttributeValueCollector()
        let parser = XMLParser(data: Data(source.utf8))
        parser.shouldResolveExternalEntities = false
        parser.delegate = collector
        #expect(parser.parse())
        if let error = parser.parserError { throw error }
        return collector.attributes
    }
}
