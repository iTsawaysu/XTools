import Testing
import XToolsCore

/// 开标签渲染的黄金快照：锁定 Foundation 属性序列化细节（单引号保留、
/// `>` 转义、字符引用解码）经 format 管线后的字节级输出。
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
                "<root attr=\"line\nbreak\">x</root>"
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
                "<root empty=\"\">\n  <child name=\"a\tb\">v</child>\n</root>"
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
