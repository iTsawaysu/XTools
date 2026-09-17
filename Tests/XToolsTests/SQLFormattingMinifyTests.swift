import Testing
@testable import XToolsCore

@Suite struct SQLFormattingMinifyTests {
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
