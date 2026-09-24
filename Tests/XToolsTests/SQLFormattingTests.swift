import XToolsCore
import Testing

struct SQLFormattingTests {
    @Test func formatsComplexQuery() throws {
        let input = """
        with active_users as (select u.id,u.name,case when u.deleted_at is null then 'active' else 'inactive' end as status from users u left join orders o on o.user_id=u.id where u.created_at>'2024-01-01') select au.id,au.name,count(o.id) as order_count from active_users au join orders o on o.user_id=au.id where exists (select 1 from payments p where p.order_id=o.id) group by au.id,au.name order by au.name;
        """

        let output = try SQLFormatting.format(input)

        #expect(output == """
            WITH active_users AS (
              SELECT
                u.id,
                u.name,
                CASE
                  WHEN u.deleted_at IS NULL THEN 'active'
                  ELSE 'inactive'
                END AS status
              FROM
                users u
                LEFT JOIN orders o ON o.user_id = u.id
              WHERE
                u.created_at > '2024-01-01'
            )
            SELECT
              au.id,
              au.name,
              count(o.id) AS order_count
            FROM
              active_users au
              JOIN orders o ON o.user_id = au.id
            WHERE
              EXISTS (
              SELECT
                1
              FROM
                payments p
              WHERE
                p.order_id = o.id
            )
            GROUP BY
              au.id,
              au.name
            ORDER BY
              au.name;
            """)
    }

    @Test func appliesFormattingOptions() throws {
        let input = "select id,name,email from users where id=1 and deleted_at is null"
        let options = SQLFormatting.Options(
            keywordCase: .lower,
            indentWidth: 4
        )

        let output = try SQLFormatting.format(input, options: options)

        #expect(output == """
            select
                id,
                name,
                email
            from
                users
            where
                id = 1
                and deleted_at is null
            """)
    }

    @Test func reportsValidationErrors() throws {
        do {
            _ = try SQLFormatting.format("select * from users where id in (1, 2")
            Issue.record("Expected unbalanced parentheses error")
        } catch let error as SQLFormatting.ValidationError {
            guard case .unbalancedParentheses(let diagnostic) = error else {
                Issue.record("Expected unbalanced parentheses error, got \(error)")
                return
            }
            #expect(diagnostic.message.contains("左括号"))
            #expect(diagnostic.line == 1)
            #expect(diagnostic.column == 33)
            #expect(!diagnostic.workspaceMessage.contains("处理方式："))
        } catch {
            Issue.record("Expected SQL validation error, got \(error)")
        }
    }

    @Test func reportsUnterminatedStringLocation() throws {
        do {
            _ = try SQLFormatting.format("select * from users where name = 'Alice")
            Issue.record("Expected unterminated string error")
        } catch let error as SQLFormatting.ValidationError {
            guard case .unterminatedString(let diagnostic) = error else {
                Issue.record("Expected unterminated string error, got \(error)")
                return
            }
            #expect(diagnostic.message.contains("字符串"))
            #expect(diagnostic.line == 1)
            #expect(diagnostic.column == 34)
        } catch {
            Issue.record("Expected SQL validation error, got \(error)")
        }
    }

    @Test func rejectsObviousIncompleteSelectStructures() throws {
        let cases = [
            (
                sql: "select from where order by;",
                expectedMessage: "SELECT 缺少要查询的列或表达式"
            ),
            (
                sql: "select id from where id = 1;",
                expectedMessage: "FROM 缺少表名或子查询"
            ),
            (
                sql: "select id from users order by;",
                expectedMessage: "ORDER BY 缺少排序表达式"
            )
        ]

        for testCase in cases {
            do {
                _ = try SQLFormatting.format(testCase.sql)
                Issue.record("Expected incomplete SQL structure error for \(testCase.sql)")
            } catch let error as SQLFormatting.ValidationError {
                guard case .incompleteStatement(let diagnostic) = error else {
                    Issue.record("Expected incomplete SQL structure error, got \(error)")
                    continue
                }
                #expect(diagnostic.message == testCase.expectedMessage)
                #expect(diagnostic.line == 1)
                #expect(diagnostic.displayMessage == diagnostic.message)
            } catch {
                Issue.record("Expected SQL validation error, got \(error)")
            }
        }
    }

    @Test func ignoresNestedFromAndReportsLaterStatementOffset() {
        let input = "SELECT id FROM (SELECT x FROM inner_table /*inner*/ ) AS s;\nSELECT y FROM /*outer*/ ;"
        let error = #expect(throws: (any Error).self) {
            try SQLFormatting.validate(input)
        }

        guard let error,
              case SQLFormatting.ValidationError.incompleteStatement(let diagnostic) = error else {
            Issue.record("Expected incomplete FROM in the second statement")
            return
        }
        #expect(diagnostic.message == "FROM 缺少表名或子查询")
        #expect(diagnostic.line == 2)
        #expect(diagnostic.column == 10)
    }

    @Test func selectDiagnosticPrecedesFromAndOrderInNestedStatement() {
        let input = "SELECT FROM (SELECT x FROM t) AS s ORDER BY;"
        let error = #expect(throws: (any Error).self) {
            try SQLFormatting.validate(input)
        }

        guard let error,
              case SQLFormatting.ValidationError.incompleteStatement(let diagnostic) = error else {
            Issue.record("Expected incomplete SELECT before FROM and ORDER BY")
            return
        }
        #expect(diagnostic.message == "SELECT 缺少要查询的列或表达式")
        #expect(diagnostic.line == 1)
        #expect(diagnostic.column == 1)
    }

    @Test func reportsStandaloneOrderByAsStructureError() throws {
        let error = #expect(throws: (any Error).self) {
            _ = try SQLFormatting.format("order by;")
        }

        guard let error,
              case SQLFormatting.ValidationError.incompleteStatement(let diagnostic) = error else {
            Issue.record("Expected incomplete SQL structure diagnostic for standalone ORDER BY")
            return
        }

        #expect(diagnostic.message.contains("ORDER BY"))
        #expect(diagnostic.message.contains("排序"))
        #expect(diagnostic.localizedDescription == diagnostic.message)
        #expect(!diagnostic.workspaceMessage.contains("处理方式："))
    }

    @Test func formatsNeighboringValidSelectWithOrderBy() throws {
        let output = try SQLFormatting.format("select id from users order by id;")

        #expect(output.contains("SELECT"))
        #expect(output.contains("FROM"))
        #expect(output.contains("ORDER BY"))
    }

    @Test func formatsDDLConstraints() throws {
        let input = """
        CREATE TABLE product_inventory (
        item_id INT PRIMARY KEY AUTO_INCREMENT,
        updated_at DATETIME ON UPDATE CURRENT_TIMESTAMP,
        category_id INT,
        CONSTRAINT fk_category FOREIGN KEY (category_id)
            REFERENCES categories(id) ON DELETE SET NULL
        ) ENGINE=InnoDB;
        """

        let output = try SQLFormatting.format(input)

        #expect(output.contains("ON UPDATE CURRENT_TIMESTAMP"))
        #expect(output.contains("ON DELETE SET NULL"))
    }

    @Test func handlesBetweenClauses() throws {
        let input = "SELECT * FROM orders WHERE created_at BETWEEN '2023-01-01' AND '2023-12-31' AND status = 'completed'"

        let output = try SQLFormatting.format(input)

        #expect(output.contains("BETWEEN '2023-01-01' AND '2023-12-31'"))
    }

    @Test func formatsMultiStatementScripts() throws {
        let input = "INSERT INTO logs (event) VALUES ('start');UPDATE users SET status='active';DELETE FROM temp;"

        let output = try SQLFormatting.format(input)

        let lines = output.split(separator: "\n", omittingEmptySubsequences: false)
        let emptyLineCount = lines.filter { $0.trimmingCharacters(in: .whitespaces).isEmpty }.count

        #expect(emptyLineCount > 0)
    }

    @Test func formatsTransactionBoundaryKeywords() throws {
        let input = "begin; insert into logs(event, payload) values ('start', '{\"ok\":true}'); commit;"

        let output = try SQLFormatting.format(input)

        #expect(output.contains("BEGIN;"))
        #expect(output.contains("INSERT INTO"))
        #expect(output.contains("COMMIT;"))
    }

    @Test func rejectsPostgresDollarQuotedLiteralsWithClearDiagnostic() throws {
        let samples = [
            "select $$hello; -- not comment$$ as body;",
            """
            select $tag$line 1;
            line 2; -- this is text
            $tag$ as body;
            """
        ]

        for sample in samples {
            do {
                _ = try SQLFormatting.format(sample)
                Issue.record("Expected unsupported dialect diagnostic for \(sample)")
            } catch let error as SQLFormatting.ValidationError {
                guard case .unsupportedDialectLiteral(let diagnostic) = error else {
                    Issue.record("Expected unsupported dialect literal, got \(error)")
                    continue
                }
                #expect(diagnostic.message.contains("PostgreSQL"))
                #expect(diagnostic.message.contains("dollar-quoted"))
                #expect(!diagnostic.workspaceMessage.contains("处理方式："))
            } catch {
                Issue.record("Expected SQL validation error, got \(error)")
            }
        }
    }

    @Test func formatsWindowFunctions() throws {
        let input = "SELECT id, name, ROW_NUMBER() OVER(PARTITION BY department_id ORDER BY salary DESC) as rank FROM employees"

        let output = try SQLFormatting.format(input)

        #expect(output.contains("PARTITION BY"))
    }

    @Test func handlesDistinct() throws {
        let input = "SELECT DISTINCT category_name, username FROM users"

        let output = try SQLFormatting.format(input)
        let lines = output.split(separator: "\n")

        #expect(lines.count > 1)
    }

    @Test func verifiesOriginalExamples() throws {
        let example1 = """
        SELECT DISTINCT
         c.category_name AS category,
         u.username,
         COUNT(o.order_id) OVER(PARTITION BY c.category_id) AS cat_order_count,
         SUM(CASE WHEN o.status = 'completed' THEN o.amount ELSE 0 END) AS total_revenue,
         AVG(o.amount) AS avg_amount
        FROM users AS u
        INNER JOIN orders AS o ON u.user_id = o.user_id
        LEFT JOIN categories AS c ON o.category_id = c.category_id
        WHERE u.status = 'active'
        AND o.created_at BETWEEN '2023-01-01' AND '2023-12-31'
        AND c.category_name LIKE 'Electronics%'
        AND u.region IN ('North', 'South')
        AND EXISTS (SELECT 1 FROM profiles p WHERE p.user_id = u.user_id AND p.is_verified = 1)
        GROUP BY c.category_name, u.username
        HAVING total_revenue > 1000
        ORDER BY total_revenue DESC, u.username ASC
        LIMIT 50 OFFSET 0
        """

        let output1 = try SQLFormatting.format(example1)
        // Example 1: SELECT DISTINCT should be on one line
        #expect(output1.contains("SELECT DISTINCT"))
        // Example 1: FROM should be alone, table indented
        #expect(output1.contains("FROM\n  users"))
        // Example 1: JOIN and ON should be on same line
        #expect(output1.contains("INNER JOIN orders AS o ON"))
        // Example 1: WHERE should be alone, condition indented
        #expect(output1.contains("WHERE\n  u.status"))
        // Example 1: BETWEEN should not break AND
        #expect(output1.contains("BETWEEN '2023-01-01' AND '2023-12-31'"))

        let example2 = """
        CREATE TABLE IF NOT EXISTS product_inventory (
        item_id INT PRIMARY KEY AUTO_INCREMENT,
        updated_at DATETIME ON UPDATE CURRENT_TIMESTAMP,
        category_id INT,
        CONSTRAINT fk_category FOREIGN KEY (category_id)
            REFERENCES categories(id) ON DELETE SET NULL
        ) ENGINE=InnoDB;
        """

        let output2 = try SQLFormatting.format(example2)
        // Example 2: Each column should be on separate line
        #expect(output2.contains("item_id INT"))
        // Example 2: ON UPDATE should stay together
        #expect(output2.contains("ON UPDATE CURRENT_TIMESTAMP"))
        // Example 2: ON DELETE SET NULL should stay together
        #expect(output2.contains("ON DELETE SET NULL"))

        let example3 = """
        INSERT INTO logs (event) VALUES ('start');UPDATE users SET status='active';DELETE FROM temp;
        """

        let output3 = try SQLFormatting.format(example3)
        let lines3 = output3.split(separator: "\n", omittingEmptySubsequences: false)
        let emptyLineCount = lines3.filter { $0.trimmingCharacters(in: .whitespaces).isEmpty }.count
        // Example 3: Multi-statement should have blank lines between statements
        #expect(emptyLineCount > 0)
    }

    @Test func verifyVarcharNotSplit() throws {
        let input = """
        CREATE TABLE product_inventory (
        sku_code VARCHAR(50) NOT NULL,
        price DECIMAL(10, 2) DEFAULT 0.00
        );
        """

        let output = try SQLFormatting.format(input)
        // VARCHAR(50) should not be split across lines
        #expect(!output.contains("VARCHAR (\n"))
        // DECIMAL(10, 2) should not be split across lines
        #expect(!output.contains("DECIMAL (\n"))
        // VARCHAR(50) should stay together
        #expect(output.contains("VARCHAR(50)") || output.contains("varchar(50)"))
    }

    @Test func preservesDoubledQuotesInsideQuotedIdentifiersAndStrings() throws {
        let input = #"SELECT "weird""name", 'it''s ok', `tick``name` FROM users"#

        let output = try SQLFormatting.format(input)

        #expect(output.contains(#""weird""name""#))
        #expect(output.contains(#"'it''s ok'"#))
        #expect(output.contains(#"`tick``name`"#))
    }

    @Test func preservesPostgresJSONOperators() throws {
        let output = try SQLFormatting.format(
            #"select payload->>'tool' as tool_name from audit_logs where payload @> '{"success": true}'::jsonb;"#
        )

        #expect(output.contains("payload ->> 'tool'"))
        #expect(output.contains("payload @>"))
        #expect(!output.contains("payload-> >"))
        #expect(!output.contains("payload @ >"))
    }

    @Test func preservesCommonAtomicTokensInFormatAndCompactModes() throws {
        let samples = [
            (sql: "select 1e-3 as value;", token: "1e-3"),
            (sql: "select $1 as value;", token: "$1"),
            (sql: "select :name as value;", token: ":name"),
            (sql: "select [a]]b] from t;", token: "[a]]b]")
        ]

        for sample in samples {
            for minify in [false, true] {
                let options = SQLFormatting.Options(minify: minify)
                let output = try SQLFormatting.format(sample.sql, options: options)
                let reformatted = try SQLFormatting.format(output, options: options)

                #expect(output.contains(sample.token), "Expected atomic token \(sample.token) in \(output)")
                #expect(reformatted.contains(sample.token), "Expected re-tokenized atomic token \(sample.token) in \(reformatted)")
            }
        }
    }

    @Test func preservesSupportedNeighboringDialectTokensAtomically() throws {
        let samples = [
            (sql: "select @name as value;", token: "@name"),
            (sql: "select ? as value;", token: "?"),
            (sql: "select B'1001' as value;", token: "B'1001'"),
            (sql: "select X'1FF' as value;", token: "X'1FF'"),
            (sql: "select N'text' as value;", token: "N'text'"),
            (sql: "select 0xFF as value;", token: "0xFF")
        ]

        for sample in samples {
            for minify in [false, true] {
                let output = try SQLFormatting.format(
                    sample.sql,
                    options: SQLFormatting.Options(minify: minify)
                )
                let reformatted = try SQLFormatting.format(
                    output,
                    options: SQLFormatting.Options(minify: minify)
                )

                #expect(output.contains(sample.token), "Expected atomic token \(sample.token) in \(output)")
                #expect(reformatted.contains(sample.token), "Expected re-tokenized atomic token \(sample.token) in \(reformatted)")
            }
        }
    }

    @Test func preservesCastAndJSONOperatorBoundariesBesidePlaceholders() throws {
        let output = try SQLFormatting.format(
            #"select :name::text, payload->>'tool', payload @> '{"ok":true}', payload ? 'ok' from audit_logs;"#
        )

        #expect(output.contains(":name::text"))
        #expect(output.contains("payload ->> 'tool'"))
        #expect(output.contains("payload @>"))
        #expect(output.contains("payload ? 'ok'"))
    }

    @Test func verifyWindowFunctionClosingParen() throws {
        let input = """
        SELECT COUNT(o.order_id) OVER(PARTITION BY c.category_id) AS cat_count FROM orders o
        """

        let output = try SQLFormatting.format(input)
        // Closing paren of window function should be on its own line
        #expect(output.contains("category_id\n"))
    }

    // MARK: - Line endings

    /// 行注释必须在任何换行形式上终止。Swift 里 `\r\n` 是**单个** Character
    /// （一个字素簇），它既不等于 "\n" 也不等于 "\r"；早先逐字符比较的写法会让
    /// CRLF 输入下的行注释一路吞到结尾，把整条语句都变成注释。
    @Test func lineCommentsTerminateOnEveryLineEndingForm() throws {
        let outputs = ["\n", "\r", "\r\n"].map { ending in
            (try? SQLFormatting.format("select 1 -- c\(ending)from t")) ?? "<throw>"
        }

        for output in outputs {
            #expect(!output.contains("\r"), Comment(rawValue: output.debugDescription))
            #expect(output.contains("FROM"), Comment(rawValue: output.debugDescription))
            #expect(output.contains("t"), Comment(rawValue: output.debugDescription))
            // 注释不能吞掉后面的语句：FROM 必须仍然被识别为关键字而独立成行。
            #expect(output.contains("-- c\n"), Comment(rawValue: output.debugDescription))
        }

        #expect(outputs[0] == outputs[1], Comment(rawValue: outputs.map(\.debugDescription).joined(separator: " vs ")))
        #expect(outputs[0] == outputs[2], Comment(rawValue: outputs.map(\.debugDescription).joined(separator: " vs ")))
    }

    /// 块注释与普通语句同样不应残留孤立回车。
    @Test func blockCommentsAndStatementsDropCarriageReturns() throws {
        let block = try SQLFormatting.format("select /* a */ 1\r\nfrom t")
        #expect(!block.contains("\r"), Comment(rawValue: block.debugDescription))

        let plain = try SQLFormatting.format("select 1\r\nfrom t")
        #expect(!plain.contains("\r"), Comment(rawValue: plain.debugDescription))
    }
}
