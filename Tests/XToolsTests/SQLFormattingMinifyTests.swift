import Testing
@testable import XToolsCore

@Suite struct SQLFormattingMinifyTests {
    @Test(arguments: [
        #"E'line\nnext'"#, #"e'it\'s quoted'"#, #"U&'d\0061ta'"#, #"u&"d\0061ta""#,
        #"U&'a\' UESCAPE '!'"#, #"u&"a\" UESCAPE '!'"#, #"U&'d\0061ta' UESCAPE '\'"#
    ])
    func keepsPostgreSQLPrefixesAttached(literal: String) throws {
        let input = "SELECT \(literal);"
        #expect(try SQLFormatting.format(input) == "SELECT\n  \(literal);")
        #expect(try SQLFormatting.format(input, options: .init(minify: true)) == input)
    }

    @Test func preservesNewlineBetweenAdjacentSingleQuotedLiteralsInBothModes() throws {
        let input = "SELECT 'foo'\r\n  'bar'\n 'baz' FROM example;"
        #expect(try SQLFormatting.format(input) == "SELECT\n  'foo'\n'bar'\n'baz'\nFROM\n  example;")
        #expect(try SQLFormatting.format(input, options: .init(minify: true)) == "SELECT 'foo'\n'bar'\n'baz' FROM example;")
    }

    @Test func testMinifyMultilineString() throws {
        let sql = "SELECT 'hello\n  world' FROM a;"
        let options = SQLFormatting.Options(minify: true)
        let formatted = try SQLFormatting.format(sql, options: options)
        #expect(formatted == "SELECT 'hello\n  world' FROM a;")
    }

    @Test func testMinifyStandardQuery() throws {
        let sql = """
        SELECT
            id,
            name,
            email
        FROM
            users
        WHERE
            status = 1
            AND age > 18
        ORDER BY
            created_at DESC;
        """
        let options = SQLFormatting.Options(keywordCase: .upper, minify: true)
        let formatted = try SQLFormatting.format(sql, options: options)
        #expect(formatted == "SELECT id, name, email FROM users WHERE status = 1 AND age > 18 ORDER BY created_at DESC;")
    }

    @Test func testMinifyWithComments() throws {
        let sql = """
        -- User query
        SELECT id FROM users;
        """
        let options = SQLFormatting.Options(minify: true)
        let formatted = try SQLFormatting.format(sql, options: options)
        #expect(formatted == "-- User query\nSELECT id FROM users;")
    }
}
